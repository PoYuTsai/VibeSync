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
# Give the IME/compositor a bounded settle window after the UI tap. This is
# still well inside the 3-second Gate K attempt SLA and avoids racing the
# MediaStore screenshot producer on slower emulators.
trial_trigger_settle_seconds=0.50

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

ime_component_is_registered() {
    local ime_list
    local registered_ime
    ime_list="$(adb shell ime list -a -s 2>/dev/null | tr -d '\r')" || return 1
    while IFS= read -r registered_ime; do
        if [[ "$registered_ime" == "$ime_component" ]]; then
            return 0
        fi
    done <<< "$ime_list"
    return 1
}

wait_for_ime_registration() {
    local max_polls="${1:-40}"
    [[ "$max_polls" =~ ^[1-9][0-9]*$ ]] || return 1
    for poll in $(seq 1 "$max_polls"); do
        if ime_component_is_registered; then
            return 0
        fi
        if (( poll < max_polls )); then
            sleep 0.25
        fi
    done
    echo "Gate K input method did not appear in the system IME list" >&2
    return 1
}

enable_gate_k_ime() {
    local max_polls="${1:-40}"
    wait_for_ime_registration "$max_polls" || return 1
    adb shell ime enable "$ime_component"
}

verify_selected_ime() {
    local max_polls="${1:-20}"
    local selected_ime
    [[ "$max_polls" =~ ^[1-9][0-9]*$ ]] || return 1
    for poll in $(seq 1 "$max_polls"); do
        selected_ime="$(adb shell settings get secure default_input_method 2>/dev/null | tr -d '\r')"
        if [[ "$selected_ime" == "$ime_component" ]]; then
            return 0
        fi
        if (( poll < max_polls )); then
            sleep 0.25
        fi
    done
    echo "Gate K prototype is not the selected default IME (selected=$selected_ime)" >&2
    return 1
}

select_and_verify_ime() {
    local max_attempts="${1:-3}"
    local max_polls="${2:-20}"
    [[ "$max_attempts" =~ ^[1-9][0-9]*$ ]] || return 1
    [[ "$max_polls" =~ ^[1-9][0-9]*$ ]] || return 1
    for attempt in $(seq 1 "$max_attempts"); do
        adb shell ime set "$ime_component" >/dev/null
        if verify_selected_ime "$max_polls"; then
            return 0
        fi
    done
    echo "Gate K prototype could not be selected after bounded retries" >&2
    return 1
}

verify_live_ime_visible() {
    local max_polls="${1:-40}"
    local input_method_dump=""
    local current_ime_matches
    local ime_visible
    local input_method_line
    local window_vis_seen
    local window_vis_invalid
    local window_vis_visible
    local window_vis_value
    local window_vis_hex
    [[ "$max_polls" =~ ^[1-9][0-9]*$ ]] || return 1
    for _ in $(seq 1 "$max_polls"); do
        input_method_dump="$(adb shell dumpsys input_method 2>/dev/null | tr -d '\r')"
        current_ime_matches=1
        if printf '%s\n' "$input_method_dump" | awk -v expected="$ime_component" '
            /(^|[[:space:]])mCurMethodId[=:]/ ||
            /(^|[[:space:]])mCurImeId[=:]/ {
                value = $0
                sub(/^.*(mCurMethodId|mCurImeId)[=:][[:space:]]*/, "", value)
                sub(/[[:space:]].*$/, "", value)
                if (value == expected) found = 1
            }
            END { exit(found ? 0 : 1) }
        '; then
            current_ime_matches=0
        fi
        ime_visible=1
        if printf '%s\n' "$input_method_dump" | grep -E \
            '(^|[[:space:]])(mInputShown|mIsInputViewShown)=true([[:space:]]|$)' >/dev/null; then
            ime_visible=0
        fi
        window_vis_seen=0
        window_vis_invalid=0
        window_vis_visible=1
        while IFS= read -r input_method_line; do
            case "$input_method_line" in
                *mImeWindowVis=*)
                    window_vis_seen=$((window_vis_seen + 1))
                    window_vis_value="${input_method_line#*mImeWindowVis=}"
                    window_vis_value="${window_vis_value%%[[:space:]]*}"
                    if [[ "$window_vis_value" =~ ^0[xX][0-9a-fA-F]+$ ]]; then
                        window_vis_hex="${window_vis_value:2}"
                        if (( (16#$window_vis_hex & 2) != 0 )); then
                            window_vis_visible=0
                        fi
                    elif [[ "$window_vis_value" =~ ^[0-9]+$ ]]; then
                        if (( (10#$window_vis_value & 2) != 0 )); then
                            window_vis_visible=0
                        fi
                    else
                        window_vis_invalid=1
                    fi
                    ;;
            esac
        done <<<"$input_method_dump"
        if (( ime_visible != 0 && window_vis_seen == 1 &&
            window_vis_invalid == 0 && window_vis_visible == 0 )); then
            ime_visible=0
        fi
        if (( current_ime_matches == 0 && ime_visible == 0 )); then
            return 0
        fi
        sleep 0.25
    done
    echo "Gate K live IME is not the selected visible input method" >&2
    return 1
}

fetch_evidence() {
    local destination="$1"
    local protocol_file="$temp_dir/evidence-protocol.txt"
    local marker=""
    local remote_command="run-as ${prototype_package} sh -c 'set -e; if [ -f files/gate-k-evidence.json ]; then printf \"__GATE_K_PRESENT__\\n\"; cat files/gate-k-evidence.json; else printf \"__GATE_K_ABSENT__\\n\"; fi'"

    rm -f -- "$destination" "$protocol_file"
    if ! adb exec-out "$remote_command" >"$protocol_file" 2>/dev/null; then
        return 1
    fi
    if ! IFS= read -r marker <"$protocol_file"; then
        return 1
    fi
    tail -n +2 "$protocol_file" >"$destination" || {
        rm -f -- "$destination"
        return 1
    }
    case "$marker" in
        __GATE_K_PRESENT__)
            [[ -s "$destination" ]] || {
                rm -f -- "$destination"
                return 1
            }
            return 0
            ;;
        __GATE_K_ABSENT__)
            [[ ! -s "$destination" ]] || {
                rm -f -- "$destination"
                return 1
            }
            rm -f -- "$destination"
            return 3
            ;;
        *)
            rm -f -- "$destination"
            return 1
            ;;
    esac
}

read_trial_count() {
    local fetch_status
    if fetch_evidence "$current_evidence_file"; then
        :
    else
        fetch_status=$?
        if (( fetch_status == 3 )); then
            printf '0\n'
            return 0
        fi
        return 1
    fi
    python3 - "$current_evidence_file" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as evidence_file:
        payload = json.load(evidence_file)
    if not isinstance(payload, dict):
        raise ValueError("evidence root must be an object")
    records = payload.get("trialRecords")
    if not isinstance(records, list):
        raise ValueError("trialRecords must be a list")
    print(len(records))
except (OSError, ValueError, TypeError):
    sys.exit(1)
PY
}

export_evidence() {
    local export_temp_file="$temp_dir/export-evidence.json"
    rm -f -- "$export_temp_file" "$evidence_file"
    if ! fetch_evidence "$export_temp_file"; then
        rm -f -- "$export_temp_file" "$evidence_file"
        return 1
    fi
    if ! python3 - "$export_temp_file" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as evidence_file:
        payload = json.load(evidence_file)
    if not isinstance(payload, dict):
        raise ValueError("evidence root must be an object")
    records = payload.get("trialRecords")
    if not isinstance(records, list):
        raise ValueError("trialRecords must be a list")
except (OSError, ValueError, TypeError):
    sys.exit(1)
PY
    then
        rm -f -- "$export_temp_file" "$evidence_file"
        return 1
    fi
    if ! mv -- "$export_temp_file" "$evidence_file"; then
        rm -f -- "$export_temp_file" "$evidence_file"
        return 1
    fi
    return 0
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
if ! adb shell pm clear "$prototype_package" >/dev/null 2>&1; then
    echo "failed to clear the prototype app-private evidence" >&2
    exit 1
fi
adb shell pm grant "$prototype_package" android.permission.READ_MEDIA_IMAGES
adb shell pm revoke "$prototype_package" \
    android.permission.READ_MEDIA_VISUAL_USER_SELECTED >/dev/null 2>&1 || true
enable_gate_k_ime || {
    echo "Gate K input method was not registered after install" >&2
    exit 1
}
select_and_verify_ime
adb shell settings put secure show_ime_with_hard_keyboard 1
[[ "$(adb shell settings get secure show_ime_with_hard_keyboard 2>/dev/null | tr -d '\r')" == "1" ]] || {
    echo "the emulator did not enable the soft IME with a hardware keyboard" >&2
    exit 1
}
adb shell am force-stop "$host_package"
adb shell monkey -p "$host_package" 1 >/dev/null

activity_package_is_foreground() {
    local activity_dump="$1"
    local expected_package="$2"
    [[ -n "$expected_package" ]] || return 1
    printf '%s\n' "$activity_dump" |
        grep -E '(^|[[:space:]])(ResumedActivity:|topResumedActivity=|mResumedActivity:)' |
        grep -F "$expected_package/" >/dev/null
}

wait_for_host_foreground() {
    local activity_dump=""
    for _ in $(seq 1 60); do
        activity_dump="$(adb shell dumpsys activity activities 2>/dev/null | tr -d '\r')"
        if activity_package_is_foreground "$activity_dump" "$host_package"; then
            if activity_package_is_foreground "$activity_dump" "$prototype_package"; then
                return 1
            fi
            return 0
        fi
        sleep 0.25
    done
    return 1
}

wait_for_host_foreground || {
    echo "host activity did not become the resumed foreground package" >&2
    exit 1
}

start_trial_host() {
    local nonce="$1"
    adb shell am force-stop "$host_package" >/dev/null
    adb shell am start -W -n "$host_package/.MainActivity" \
        --es gate_k_nonce "$nonce" >/dev/null
}

ensure_gate_k_ime_selected() {
    local max_attempts="${1:-3}"
    local max_polls="${2:-20}"
    local selected_ime=""
    selected_ime="$(adb shell settings get secure default_input_method 2>/dev/null | tr -d '\r')"
    if [[ "$selected_ime" == "$ime_component" ]]; then
        return 0
    fi
    select_and_verify_ime "$max_attempts" "$max_polls"
}

ensure_gate_k_ime_selected
verify_live_ime_visible

initial_count="$(read_trial_count)"
[[ "$initial_count" == "0" ]] || {
    echo "evidence was not empty after app-private reset" >&2
    exit 1
}

dump_ui() {
    rm -f -- "$ui_dump_file" &&
        adb shell rm -f /sdcard/gate-k-ui.xml >/dev/null 2>&1 &&
        adb shell uiautomator dump --windows /sdcard/gate-k-ui.xml >/dev/null 2>&1 &&
        adb exec-out cat /sdcard/gate-k-ui.xml >"$ui_dump_file" &&
        [[ -s "$ui_dump_file" ]]
}

dump_ui_standard() {
    rm -f -- "$ui_dump_file" &&
        adb shell rm -f /sdcard/gate-k-ui.xml >/dev/null 2>&1 &&
        adb shell uiautomator dump /sdcard/gate-k-ui.xml >/dev/null 2>&1 &&
        adb exec-out cat /sdcard/gate-k-ui.xml >"$ui_dump_file" &&
        [[ -s "$ui_dump_file" ]]
}

find_button_center() {
    python3 "$script_dir/gate_k_harness.py" ui --input "$ui_dump_file"
}

find_trial_nonce() {
    python3 "$script_dir/gate_k_harness.py" nonce \
        --input "$ui_dump_file" \
        --expected "$1"
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

wait_for_nonce_standard() {
    local expected_nonce="$1"
    local observed_nonce=""
    for _ in $(seq 1 120); do
        if dump_ui_standard &&
            observed_nonce="$(find_trial_nonce "$expected_nonce" 2>/dev/null)" &&
            [[ "$observed_nonce" == "$expected_nonce" ]] &&
            [[ -s "$ui_dump_file" ]]; then
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

previous_nonce=""
for trial in $(seq 1 "$trial_count"); do
    nonce="gate-k-trial-${trial}"
    [[ "$nonce" != "$previous_nonce" ]] || {
        echo "trial nonce was reused" >&2
        exit 1
    }
    start_trial_host "$nonce"
    wait_for_host_foreground || {
        echo "host activity did not become the resumed foreground package for trial $trial" >&2
        exit 1
    }
    ensure_gate_k_ime_selected
    verify_live_ime_visible
    wait_for_nonce_standard "$nonce" || {
        echo "host nonce was not visible in a fresh standard UI dump for trial $trial" >&2
        exit 1
    }
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
    sleep "$trial_trigger_settle_seconds"
    # This keyevent is the only screenshot trigger; no screencap or synthetic
    # MediaStore insertion is allowed in this runner.
    adb shell input keyevent 120
    wait_for_trial_count "$trial"
    previous_nonce="$nonce"
done

echo "Gate K runner captured $trial_count runtime attempts for API $api_level"
