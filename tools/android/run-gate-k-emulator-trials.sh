#!/usr/bin/env bash
set -Eeuo pipefail

# Bounded, real-device Gate K runner. It never injects a MediaStore row and
# never uses screencap; Android's own keyevent 120 is the only screenshot
# trigger after the UI button tap.

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../.." && pwd)"
android_root="$repo_root/android"
GITHUB_SHA="${GITHUB_SHA:-}"
expected_sha="$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || true)"
if [[ -z "$expected_sha" ]]; then
    echo "unable to resolve the runner checkout HEAD" >&2
    exit 2
fi
if [[ -n "$GITHUB_SHA" && "$GITHUB_SHA" != "$expected_sha" ]]; then
    echo "runner checkout HEAD does not match GITHUB_SHA" >&2
    exit 2
fi
checkout_status="$(git -C "$repo_root" status --porcelain --untracked-files=all)"
if [[ -n "$checkout_status" ]]; then
    echo "runner checkout has uncommitted or untracked files" >&2
    exit 2
fi
prototype_package="com.vibesync.gatek"
host_package="com.vibesync.gatekhost"
ime_component="$prototype_package/.GateKPrototypeInputMethodService"
api_level=34
trial_count=40
output_dir="${GATE_K_OUTPUT_DIR:-$repo_root/.gate-k-artifacts-api34}"

usage() {
    cat <<'EOF'
Usage: tools/android/run-gate-k-emulator-trials.sh [options]

Options:
  --api-level N   API level 34, 35, or 36 (default: 34)
  --trials N      bounded trial count, 1..40 (default: 40)
  --output-dir D  app-private evidence export directory
  -h, --help      show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --api-level)
            [[ $# -ge 2 ]] || { usage >&2; exit 2; }
            api_level="$2"
            shift 2
            ;;
        --trials)
            [[ $# -ge 2 ]] || { usage >&2; exit 2; }
            trial_count="$2"
            shift 2
            ;;
        --output-dir)
            [[ $# -ge 2 ]] || { usage >&2; exit 2; }
            output_dir="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

[[ "$api_level" =~ ^[0-9]+$ && "$api_level" -ge 34 && "$api_level" -le 36 ]] || {
    echo "api level must be 34, 35, or 36" >&2
    exit 2
}
[[ "$trial_count" =~ ^[0-9]+$ && "$trial_count" -ge 1 && "$trial_count" -le 40 ]] || {
    echo "trial count must be between 1 and 40" >&2
    exit 2
}

if ! command -v realpath >/dev/null 2>&1; then
    echo "realpath is required for repository-private evidence output" >&2
    exit 2
fi
if [[ "$output_dir" != /* ]]; then
    output_dir="$repo_root/$output_dir"
fi
output_dir="$(realpath -m -- "$output_dir")"
case "$output_dir" in
    "$repo_root"|"$repo_root"/*) ;;
    *)
        echo "evidence output must stay inside the repository" >&2
        exit 2
        ;;
esac

mkdir -p -- "$output_dir"
evidence_file="$output_dir/gate-k-evidence-api${api_level}.json"
metadata_file="$output_dir/device-metadata-api${api_level}.txt"
rm -f -- "$evidence_file"
temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/gate-k-emulator.XXXXXX")"
ui_dump_file="$temp_dir/ui.xml"
current_evidence_file="$temp_dir/current-evidence.json"

cleanup() {
    rm -rf -- "$temp_dir"
}

read_trial_count() {
    if ! adb exec-out run-as "$prototype_package" cat files/gate-k-evidence.json \
        >"$current_evidence_file" 2>/dev/null; then
        echo 0
        return 0
    fi
    python3 - "$current_evidence_file" <<'PY'
import json
import sys

try:
    payload = json.load(open(sys.argv[1], encoding="utf-8"))
    records = payload.get("trialRecords")
    print(len(records) if isinstance(records, list) else -1)
except (OSError, ValueError, TypeError):
    print(-1)
PY
}

export_evidence() {
    if adb exec-out run-as "$prototype_package" cat files/gate-k-evidence.json \
        >"$evidence_file" 2>/dev/null; then
        return 0
    fi
    rm -f -- "$evidence_file"
    return 1
}

collect_device_metadata() {
    {
        printf 'gitSha=%s\n' "$expected_sha"
        printf 'gitRef=%s\n' "${GITHUB_REF:-unavailable}"
        printf 'gitEvent=%s\n' "${GITHUB_EVENT_NAME:-unavailable}"
        printf 'apiLevel=%s\n' "$api_level"
        for property in \
            ro.product.manufacturer \
            ro.product.brand \
            ro.product.model \
            ro.product.name \
            ro.build.fingerprint \
            ro.build.version.sdk; do
            value="$(adb shell getprop "$property" 2>/dev/null | tr -d '\r')"
            printf '%s=%s\n' "$property" "$value"
        done
    } >"$metadata_file"
}

finalize() {
    local exit_code=$?
    trap - EXIT
    set +e
    export_evidence
    collect_device_metadata
    if [[ -s "$evidence_file" ]]; then
        if (( exit_code == 0 )); then
            python3 "$script_dir/gate_k_harness.py" evidence \
                --input "$evidence_file" \
                --expected-trials "$trial_count" \
                --expected-api "$api_level" \
                --require-api-candidate
            validation_code=$?
            if (( validation_code != 0 )); then
                exit_code=1
            fi
        else
            # Preserve and validate whatever real artifact exists, but retain
            # the original failure status so a failed run cannot look green.
            python3 "$script_dir/gate_k_harness.py" evidence \
                --input "$evidence_file" \
                --expected-trials "$trial_count" \
                --expected-api "$api_level" >/dev/null 2>&1
        fi
    elif (( exit_code == 0 )); then
        echo "Gate K evidence artifact was not exported" >&2
        exit_code=1
    fi
    cleanup
    exit "$exit_code"
}

trap finalize EXIT

command -v adb >/dev/null 2>&1 || {
    echo "adb is required; use the controlled Android SDK environment" >&2
    exit 2
}
command -v python3 >/dev/null 2>&1 || {
    echo "python3 is required for bounded artifact validation" >&2
    exit 2
}
[[ -x "$android_root/gradlew" ]] || {
    echo "android/gradlew is missing; materialize the pinned wrapper before running" >&2
    exit 2
}

build_root="$repo_root/build"
(cd "$android_root" && ./gradlew --no-daemon \
    :gate-k-prototype:assembleDebug \
    :gate-k-host:assembleDebug)

prototype_apk="$build_root/gate-k-prototype/outputs/apk/debug/gate-k-prototype-debug.apk"
host_apk="$build_root/gate-k-host/outputs/apk/debug/gate-k-host-debug.apk"
[[ -f "$prototype_apk" && -f "$host_apk" ]] || {
    echo "canonical debug APK outputs were not found" >&2
    exit 1
}

timeout 60s adb wait-for-device >/dev/null
adb install -r "$prototype_apk"
adb install -r "$host_apk"
adb shell pm clear "$prototype_package" >/dev/null 2>&1 || true
adb shell pm grant "$prototype_package" android.permission.READ_MEDIA_IMAGES
adb shell pm revoke "$prototype_package" \
    android.permission.READ_MEDIA_VISUAL_USER_SELECTED >/dev/null 2>&1 || true
adb shell ime enable "$ime_component"
adb shell ime set "$ime_component"
adb shell settings put secure show_ime_with_hard_keyboard 1
[[ "$(adb shell settings get secure show_ime_with_hard_keyboard 2>/dev/null | tr -d '\r')" == "1" ]] || {
    echo "the emulator did not enable the soft IME with a hardware keyboard" >&2
    exit 1
}
adb shell am force-stop "$host_package"
adb shell monkey -p "$host_package" 1 >/dev/null

for _ in $(seq 1 60); do
    if adb shell dumpsys activity activities 2>/dev/null | tr -d '\r' | \
        grep 'mResumedActivity:.*com.vibesync.gatekhost/' >/dev/null; then
        break
    fi
    sleep 0.25
done
adb shell dumpsys activity activities 2>/dev/null | tr -d '\r' | \
    grep 'mResumedActivity:.*com.vibesync.gatekhost/' >/dev/null || {
    echo "host activity did not become the resumed foreground package" >&2
    exit 1
}
if adb shell dumpsys activity activities 2>/dev/null | tr -d '\r' | \
    grep 'mResumedActivity:.*com.vibesync.gatek/' >/dev/null; then
    echo "Gate K IME package incorrectly became the resumed host activity" >&2
    exit 1
fi

initial_count="$(read_trial_count)"
[[ "$initial_count" == "0" ]] || {
    echo "evidence was not empty after app-private reset" >&2
    exit 1
}

dump_ui() {
    adb shell uiautomator dump /sdcard/gate-k-ui.xml >/dev/null 2>&1
    adb exec-out cat /sdcard/gate-k-ui.xml >"$ui_dump_file"
}

find_button_center() {
    python3 "$script_dir/gate_k_harness.py" ui --input "$ui_dump_file"
}

wait_for_button() {
    local center=""
    for _ in $(seq 1 120); do
        if dump_ui && center="$(find_button_center 2>/dev/null)"; then
            printf '%s\n' "$center"
            return 0
        fi
        sleep 0.25
    done
    return 1
}

wait_for_trial_count() {
    local expected="$1"
    local observed
    for _ in $(seq 1 60); do
        observed="$(read_trial_count)"
        if [[ "$observed" == "$expected" ]]; then
            return 0
        fi
        sleep 0.25
    done
    echo "timed out waiting for app-private trial count $expected (last=$observed)" >&2
    return 1
}

for trial in $(seq 1 "$trial_count"); do
    center="$(wait_for_button)" || {
        echo "Gate K attempt button was not found for trial $trial" >&2
        exit 1
    }
    [[ "$center" =~ ^[0-9]+,[0-9]+$ ]] || {
        echo "UI parser returned invalid button center" >&2
        exit 1
    }
    IFS=, read -r center_x center_y <<<"$center"
    adb shell input tap "$center_x" "$center_y"
    sleep 0.10
    # This keyevent is the only screenshot trigger; no screencap or synthetic
    # MediaStore insertion is allowed in this runner.
    adb shell input keyevent 120
    wait_for_trial_count "$trial"
done

echo "Gate K runner captured $trial_count runtime attempts for API $api_level"
