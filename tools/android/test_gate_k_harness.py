#!/usr/bin/env python3
"""Pure contract tests for the bounded Gate K emulator harness."""

from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from gate_k_harness import (
    HarnessContractError,
    find_gate_k_nonce,
    find_gate_k_button_center,
    validate_evidence,
    validate_runner_contract,
    validate_workflow_contract,
)


VALID_UI = """
<hierarchy>
  <node class="android.widget.Button" text="Start Gate K attempt"
        content-desc="Start Gate K attempt" enabled="true" bounds="[10,20][210,100]" />
</hierarchy>
"""

REPO_ROOT = Path(__file__).resolve().parents[2]


def runner_foreground_predicate(
    activity_dump: str,
    expected_package: str = "com.vibesync.gatekhost",
) -> bool:
    runner = (REPO_ROOT / "tools/android/run-gate-k-emulator-trials.sh").read_text(
        encoding="utf-8",
    )
    marker = "activity_package_is_foreground() {"
    start = runner.find(marker)
    if start < 0:
        raise AssertionError("runner foreground predicate seam is missing")
    end = runner.find("\n}", start)
    if end < 0:
        raise AssertionError("runner foreground predicate is not closed")
    function = runner[start : end + 2]
    environment = os.environ.copy()
    environment["ACTIVITY_DUMP"] = activity_dump
    environment["EXPECTED_PACKAGE"] = expected_package
    process = subprocess.run(
        [
            "bash",
            "-c",
            f'{function}\nactivity_package_is_foreground "$ACTIVITY_DUMP" "$EXPECTED_PACKAGE"',
        ],
        env=environment,
        capture_output=True,
        text=True,
        check=False,
    )
    return process.returncode == 0


def runner_shell_function(name: str) -> str:
    runner = (REPO_ROOT / "tools/android/run-gate-k-emulator-trials.sh").read_text(
        encoding="utf-8",
    )
    marker = f"{name}() {{"
    start = runner.find(marker)
    if start < 0:
        raise AssertionError(f"runner {name} evidence seam is missing")
    end = runner.find("\n}", start)
    if end < 0:
        raise AssertionError(f"runner {name} evidence seam is not closed")
    return runner[start : end + 2]


def run_runner_evidence_seam(
    mode: str,
    fake_output: str,
    fake_exit: int = 0,
) -> tuple[int, str, bool, bytes]:
    with tempfile.TemporaryDirectory(prefix="gate-k-evidence-test-") as temp_name:
        temp_dir = Path(temp_name)
        fake_adb = temp_dir / "adb"
        fake_adb.write_text(
            """#!/usr/bin/env bash
if [[ "$#" -ne 2 || "$1" != "exec-out" ]]; then
    echo 'adb command was not one exec-out remote command' >&2
    exit 97
fi
remote_command="$2"
remote_prefix="run-as com.vibesync.gatek sh -c '"
remote_suffix="'"
if [[ "$remote_command" != "$remote_prefix"* || "$remote_command" != *"$remote_suffix" ]]; then
    echo 'remote command did not preserve sh -c quoting' >&2
    exit 98
fi
remote_script="${remote_command#"$remote_prefix"}"
remote_script="${remote_script%"$remote_suffix"}"
if [[ "$remote_script" != *"if [ -f files/gate-k-evidence.json ]"* ||
      "$remote_script" != *"__GATE_K_PRESENT__"* ||
      "$remote_script" != *"__GATE_K_ABSENT__"* ]]; then
    echo 'remote sentinel script was incomplete' >&2
    exit 99
fi
if [[ "${GATE_K_FAKE_EXIT:-0}" != "0" ]]; then
    exit "${GATE_K_FAKE_EXIT}"
fi
printf "%s" "${GATE_K_FAKE_OUTPUT:-}"
""",
            encoding="utf-8",
        )
        fake_adb.chmod(0o755)

        environment = os.environ.copy()
        environment["PATH"] = f"{temp_dir}{os.pathsep}{environment['PATH']}"
        environment["GATE_K_FAKE_OUTPUT"] = fake_output
        environment["GATE_K_FAKE_EXIT"] = str(fake_exit)
        environment["GATE_K_TEMP_DIR"] = str(temp_dir)
        shell = "\n\n".join(
            runner_shell_function(function)
            for function in ("fetch_evidence", "read_trial_count", "export_evidence")
        )
        command = (
            f'{shell}\n'
            'prototype_package="com.vibesync.gatek"\n'
            'temp_dir="$GATE_K_TEMP_DIR"\n'
            'current_evidence_file="$temp_dir/current.json"\n'
            'evidence_file="$temp_dir/export.json"\n'
            f'if [[ "{mode}" == "count" ]]; then read_trial_count; '
            'else export_evidence; fi\n'
        )
        process = subprocess.run(
            ["bash", "-c", command],
            env=environment,
            capture_output=True,
            text=True,
            check=False,
        )
        exported = temp_dir / "export.json"
        return (
            process.returncode,
            process.stdout,
            exported.exists(),
            exported.read_bytes() if exported.exists() else b"",
        )


def run_runner_ime_selection_seam(fake_ime: str) -> int:
    with tempfile.TemporaryDirectory(prefix="gate-k-ime-test-") as temp_name:
        temp_dir = Path(temp_name)
        fake_adb = temp_dir / "adb"
        fake_adb.write_text(
            """#!/usr/bin/env bash
if [[ "$#" -ne 5 || "$1" != "shell" || "$2" != "settings" ||
      "$3" != "get" || "$4" != "secure" || "$5" != "default_input_method" ]]; then
    echo 'unexpected IME verification command' >&2
    exit 97
fi
printf "%s\\n" "${GATE_K_FAKE_IME:-}"
""",
            encoding="utf-8",
        )
        fake_adb.chmod(0o755)
        environment = os.environ.copy()
        environment["PATH"] = f"{temp_dir}{os.pathsep}{environment['PATH']}"
        environment["GATE_K_FAKE_IME"] = fake_ime
        shell = runner_shell_function("verify_selected_ime")
        command = (
            f'{shell}\n'
            'ime_component="com.vibesync.gatek/.GateKPrototypeInputMethodService"\n'
            "verify_selected_ime 1\n"
        )
        process = subprocess.run(
            ["bash", "-c", command],
            env=environment,
            capture_output=True,
            text=True,
            check=False,
        )
        return process.returncode


def run_runner_ime_selection_sequence(fake_imes: tuple[str, ...], max_polls: int) -> int:
    with tempfile.TemporaryDirectory(prefix="gate-k-ime-sequence-test-") as temp_name:
        temp_dir = Path(temp_name)
        fake_adb = temp_dir / "adb"
        fake_adb.write_text(
            """#!/usr/bin/env bash
if [[ "$#" -ne 5 || "$1" != "shell" || "$2" != "settings" ||
      "$3" != "get" || "$4" != "secure" || "$5" != "default_input_method" ]]; then
    echo 'unexpected IME verification command' >&2
    exit 97
fi
count=0
if [[ -f "$GATE_K_IME_COUNTER" ]]; then
    count="$(cat "$GATE_K_IME_COUNTER")"
fi
count=$((count + 1))
printf '%s' "$count" > "$GATE_K_IME_COUNTER"
value="$(printf '%s\\n' "$GATE_K_FAKE_IME_SEQUENCE" | sed -n "${count}p")"
if [[ -z "$value" ]]; then
    value="$(printf '%s\\n' "$GATE_K_FAKE_IME_SEQUENCE" | tail -n 1)"
fi
printf '%s\\n' "$value"
""",
            encoding="utf-8",
        )
        fake_adb.chmod(0o755)
        environment = os.environ.copy()
        environment["PATH"] = f"{temp_dir}{os.pathsep}{environment['PATH']}"
        environment["GATE_K_IME_COUNTER"] = str(temp_dir / "ime-counter")
        environment["GATE_K_FAKE_IME_SEQUENCE"] = "\n".join(fake_imes)
        shell = runner_shell_function("verify_selected_ime")
        command = (
            f'{shell}\n'
            'ime_component="com.vibesync.gatek/.GateKPrototypeInputMethodService"\n'
            f"verify_selected_ime {max_polls}\n"
        )
        process = subprocess.run(
            ["bash", "-c", command],
            env=environment,
            capture_output=True,
            text=True,
            check=False,
        )
        return process.returncode


def run_runner_ime_reselection_seam(
    fake_imes: tuple[str, ...],
    max_attempts: int,
    max_polls: int,
) -> tuple[int, int]:
    with tempfile.TemporaryDirectory(prefix="gate-k-ime-reselection-test-") as temp_name:
        temp_dir = Path(temp_name)
        fake_adb = temp_dir / "adb"
        fake_adb.write_text(
            """#!/usr/bin/env bash
if [[ "$1" == "shell" && "$2" == "ime" && "$3" == "set" &&
      "$4" == "com.vibesync.gatek/.GateKPrototypeInputMethodService" ]]; then
    count=0
    if [[ -f "$GATE_K_IME_SET_COUNTER" ]]; then
        count="$(cat "$GATE_K_IME_SET_COUNTER")"
    fi
    count=$((count + 1))
    printf '%s' "$count" > "$GATE_K_IME_SET_COUNTER"
    exit 0
fi
if [[ "$#" -ne 5 || "$1" != "shell" || "$2" != "settings" ||
      "$3" != "get" || "$4" != "secure" || "$5" != "default_input_method" ]]; then
    echo 'unexpected IME reselection command' >&2
    exit 97
fi
set_count=0
if [[ -f "$GATE_K_IME_SET_COUNTER" ]]; then
    set_count="$(cat "$GATE_K_IME_SET_COUNTER")"
fi
value="$(printf '%s\\n' "$GATE_K_FAKE_IME_SEQUENCE" | sed -n "${set_count}p")"
if [[ -z "$value" ]]; then
    value="$(printf '%s\\n' "$GATE_K_FAKE_IME_SEQUENCE" | tail -n 1)"
fi
printf '%s\\n' "$value"
""",
            encoding="utf-8",
        )
        fake_adb.chmod(0o755)
        environment = os.environ.copy()
        environment["PATH"] = f"{temp_dir}{os.pathsep}{environment['PATH']}"
        environment["GATE_K_IME_SET_COUNTER"] = str(temp_dir / "ime-set-counter")
        environment["GATE_K_FAKE_IME_SEQUENCE"] = "\n".join(fake_imes)
        shell = "\n\n".join(
            runner_shell_function(function)
            for function in ("verify_selected_ime", "select_and_verify_ime")
        )
        command = (
            f'{shell}\n'
            'ime_component="com.vibesync.gatek/.GateKPrototypeInputMethodService"\n'
            f"select_and_verify_ime {max_attempts} {max_polls}\n"
        )
        process = subprocess.run(
            ["bash", "-c", command],
            env=environment,
            capture_output=True,
            text=True,
            check=False,
        )
        set_count_file = temp_dir / "ime-set-counter"
        set_count = int(set_count_file.read_text(encoding="utf-8")) if set_count_file.exists() else 0
        return process.returncode, set_count


def run_runner_ime_selection_drift_seam(
    initial_ime: str,
    reselection_imes: tuple[str, ...],
    max_attempts: int,
    max_polls: int,
) -> tuple[int, int, str]:
    with tempfile.TemporaryDirectory(prefix="gate-k-ime-selection-guard-test-") as temp_name:
        temp_dir = Path(temp_name)
        fake_adb = temp_dir / "adb"
        fake_adb.write_text(
            """#!/usr/bin/env bash
if [[ "$1" == "shell" && "$2" == "ime" && "$3" == "set" &&
      "$4" == "com.vibesync.gatek/.GateKPrototypeInputMethodService" ]]; then
    count=0
    if [[ -f "$GATE_K_IME_SET_COUNTER" ]]; then
        count="$(cat "$GATE_K_IME_SET_COUNTER")"
    fi
    count=$((count + 1))
    printf '%s' "$count" > "$GATE_K_IME_SET_COUNTER"
    exit 0
fi
if [[ "$#" -ne 5 || "$1" != "shell" || "$2" != "settings" ||
      "$3" != "get" || "$4" != "secure" || "$5" != "default_input_method" ]]; then
    echo 'unexpected IME selection guard command' >&2
    exit 97
fi
set_count=0
if [[ -f "$GATE_K_IME_SET_COUNTER" ]]; then
    set_count="$(cat "$GATE_K_IME_SET_COUNTER")"
fi
if (( set_count == 0 )); then
    value="$GATE_K_INITIAL_IME"
else
    value="$(printf '%s\\n' "$GATE_K_RESELECTION_IME_SEQUENCE" | sed -n "${set_count}p")"
    if [[ -z "$value" ]]; then
        value="$(printf '%s\\n' "$GATE_K_RESELECTION_IME_SEQUENCE" | tail -n 1)"
    fi
fi
printf '%s\\n' "$value"
""",
            encoding="utf-8",
        )
        fake_adb.chmod(0o755)
        environment = os.environ.copy()
        environment["PATH"] = f"{temp_dir}{os.pathsep}{environment['PATH']}"
        environment["GATE_K_IME_SET_COUNTER"] = str(temp_dir / "ime-set-counter")
        environment["GATE_K_INITIAL_IME"] = initial_ime
        environment["GATE_K_RESELECTION_IME_SEQUENCE"] = "\n".join(reselection_imes)
        shell = "\n\n".join(
            runner_shell_function(function)
            for function in (
                "verify_selected_ime",
                "select_and_verify_ime",
                "ensure_gate_k_ime_selected",
            )
        )
        command = (
            f'{shell}\n'
            'ime_component="com.vibesync.gatek/.GateKPrototypeInputMethodService"\n'
            f"ensure_gate_k_ime_selected {max_attempts} {max_polls}\n"
        )
        process = subprocess.run(
            ["bash", "-c", command],
            env=environment,
            capture_output=True,
            text=True,
            check=False,
        )
        set_count_file = temp_dir / "ime-set-counter"
        set_count = int(set_count_file.read_text(encoding="utf-8")) if set_count_file.exists() else 0
        return process.returncode, set_count, process.stderr


def run_runner_live_ime_visibility_seam(
    fake_dump: str,
    fake_selected_ime: str = "com.vibesync.gatek/.GateKPrototypeInputMethodService",
) -> int:
    with tempfile.TemporaryDirectory(prefix="gate-k-live-ime-test-") as temp_name:
        temp_dir = Path(temp_name)
        fake_adb = temp_dir / "adb"
        fake_adb.write_text(
            """#!/usr/bin/env bash
if [[ "$#" -eq 3 && "$1" == "shell" && "$2" == "dumpsys" &&
      "$3" == "input_method" ]]; then
    printf "%s\\n" "${GATE_K_FAKE_DUMP:-}"
    exit 0
fi
if [[ "$#" -eq 5 && "$1" == "shell" && "$2" == "settings" &&
      "$3" == "get" && "$4" == "secure" && "$5" == "default_input_method" ]]; then
    printf "%s\\n" "${GATE_K_FAKE_SELECTED_IME:-}"
    exit 0
fi
echo 'unexpected live IME inspection command' >&2
exit 97
""",
            encoding="utf-8",
        )
        fake_adb.chmod(0o755)
        environment = os.environ.copy()
        environment["PATH"] = f"{temp_dir}{os.pathsep}{environment['PATH']}"
        environment["GATE_K_FAKE_DUMP"] = fake_dump
        environment["GATE_K_FAKE_SELECTED_IME"] = fake_selected_ime
        shell = runner_shell_function("verify_live_ime_visible")
        command = (
            f'{shell}\n'
            'ime_component="com.vibesync.gatek/.GateKPrototypeInputMethodService"\n'
            "verify_live_ime_visible 1\n"
        )
        process = subprocess.run(
            ["bash", "-c", command],
            env=environment,
            capture_output=True,
            text=True,
            check=False,
        )
        return process.returncode


def run_runner_ui_dump_seam(mode: str) -> tuple[int, bytes, str]:
    with tempfile.TemporaryDirectory(prefix="gate-k-ui-dump-test-") as temp_name:
        temp_dir = Path(temp_name)
        fake_adb = temp_dir / "adb"
        fake_adb.write_text(
            """#!/usr/bin/env bash
case "$*" in
  "shell rm -f /sdcard/gate-k-ui.xml")
    printf 'remote-rm\\n' >> "$GATE_K_UI_LOG"
    if [[ "$GATE_K_UI_MODE" == "rm-fails" ]]; then exit 1; fi
    exit 0
    ;;
  "shell uiautomator dump --windows /sdcard/gate-k-ui.xml")
    printf 'remote-dump\\n' >> "$GATE_K_UI_LOG"
    if [[ "$GATE_K_UI_MODE" == "dump-fails" ]]; then exit 1; fi
    exit 0
    ;;
  "exec-out cat /sdcard/gate-k-ui.xml")
    printf 'remote-cat\\n' >> "$GATE_K_UI_LOG"
    if [[ "$GATE_K_UI_MODE" == "missing" ]]; then exit 0; fi
    printf '%s' "${GATE_K_UI_PAYLOAD:-}"
    ;;
  *)
    echo 'unexpected UI dump command' >&2
    exit 97
    ;;
esac
""",
            encoding="utf-8",
        )
        fake_adb.chmod(0o755)
        local_dump = temp_dir / "ui.xml"
        local_dump.write_text("<hierarchy>old</hierarchy>", encoding="utf-8")
        command = (
            f'{runner_shell_function("dump_ui")}\n'
            f'ui_dump_file="$GATE_K_UI_DUMP"\n'
            "dump_ui\n"
        )
        environment = os.environ.copy()
        environment["PATH"] = f"{temp_dir}{os.pathsep}{environment['PATH']}"
        environment["GATE_K_UI_MODE"] = mode
        environment["GATE_K_UI_LOG"] = str(temp_dir / "adb.log")
        environment["GATE_K_UI_DUMP"] = str(local_dump)
        environment["GATE_K_UI_PAYLOAD"] = "<hierarchy><node /></hierarchy>"
        process = subprocess.run(
            ["bash", "-c", command],
            env=environment,
            capture_output=True,
            text=True,
            check=False,
        )
        log_file = temp_dir / "adb.log"
        return (
            process.returncode,
            local_dump.read_bytes() if local_dump.exists() else b"",
            log_file.read_text(encoding="utf-8") if log_file.exists() else "",
        )


def run_runner_standard_ui_dump_seam(mode: str) -> tuple[int, bytes, str]:
    with tempfile.TemporaryDirectory(prefix="gate-k-standard-ui-test-") as temp_name:
        temp_dir = Path(temp_name)
        fake_adb = temp_dir / "adb"
        fake_adb.write_text(
            """#!/usr/bin/env bash
case "$*" in
  "shell rm -f /sdcard/gate-k-ui.xml")
    printf 'remote-rm\\n' >> "$GATE_K_UI_LOG"
    if [[ "$GATE_K_UI_MODE" == "rm-fails" ]]; then exit 1; fi
    exit 0
    ;;
  "shell uiautomator dump /sdcard/gate-k-ui.xml")
    printf 'remote-dump\\n' >> "$GATE_K_UI_LOG"
    if [[ "$GATE_K_UI_MODE" == "dump-fails" ]]; then exit 1; fi
    exit 0
    ;;
  "exec-out cat /sdcard/gate-k-ui.xml")
    printf 'remote-cat\\n' >> "$GATE_K_UI_LOG"
    if [[ "$GATE_K_UI_MODE" == "missing" ]]; then exit 0; fi
    printf '%s' "${GATE_K_UI_PAYLOAD:-}"
    ;;
  *)
    echo 'unexpected standard UI dump command' >&2
    exit 97
    ;;
esac
""",
            encoding="utf-8",
        )
        fake_adb.chmod(0o755)
        local_dump = temp_dir / "ui.xml"
        local_dump.write_text("<hierarchy>old</hierarchy>", encoding="utf-8")
        command = (
            f'{runner_shell_function("dump_ui_standard")}\n'
            f'ui_dump_file="$GATE_K_UI_DUMP"\n'
            "dump_ui_standard\n"
        )
        environment = os.environ.copy()
        environment["PATH"] = f"{temp_dir}{os.pathsep}{environment['PATH']}"
        environment["GATE_K_UI_MODE"] = mode
        environment["GATE_K_UI_LOG"] = str(temp_dir / "adb.log")
        environment["GATE_K_UI_DUMP"] = str(local_dump)
        environment["GATE_K_UI_PAYLOAD"] = "<hierarchy><node /></hierarchy>"
        process = subprocess.run(
            ["bash", "-c", command],
            env=environment,
            capture_output=True,
            text=True,
            check=False,
        )
        log_file = temp_dir / "adb.log"
        return (
            process.returncode,
            local_dump.read_bytes() if local_dump.exists() else b"",
            log_file.read_text(encoding="utf-8") if log_file.exists() else "",
        )


def valid_evidence() -> dict:
    record = {
        "trialId": "trial-1",
        "deviceClass": "EMULATOR",
        "apiLevel": 34,
        "deviceModel": "sdk_gphone64_x86_64",
        "reportedSuccess": False,
        "latencyMs": 3001,
        "sessionOutcome": "NOT_EVALUATED",
        "dedupeOutcome": "NOT_EVALUATED",
        "attemptId": "attempt-1",
        "sessionId": "session-1",
        "triggerElapsedRealtimeMs": 1000,
        "detectedElapsedRealtimeMs": 4001,
        "deviceDescriptor": (
            "manufacturer=Google|brand=google|model=sdk_gphone64_x86_64|"
            "product=sdk_gphone64_x86_64|fingerprint=generic/sdk|api=34"
        ),
        "failureReason": "TIMEOUT",
        "origin": "RUNTIME",
    }
    return {
        "schemaVersion": 1,
        "trialRecords": [record],
        "summary": {
            "totalTrials": 1,
            "emulatorApiSummaries": {
                "34": {
                    "totalTrials": 1,
                    "successfulTrials": 0,
                    "failedTrials": 1,
                    "successRate": 0.0,
                    "p50LatencyMs": 3001,
                    "p95LatencyMs": 3001,
                    "successRateMet": False,
                    "latencyMet": False,
                },
                "35": {
                    "totalTrials": 0,
                    "successfulTrials": 0,
                    "failedTrials": 0,
                    "successRate": 0.0,
                    "p50LatencyMs": None,
                    "p95LatencyMs": None,
                    "successRateMet": False,
                    "latencyMet": False,
                },
                "36": {
                    "totalTrials": 0,
                    "successfulTrials": 0,
                    "failedTrials": 0,
                    "successRate": 0.0,
                    "p50LatencyMs": None,
                    "p95LatencyMs": None,
                    "successRateMet": False,
                    "latencyMet": False,
                },
            },
            "successfulTrials": 0,
            "failedTrials": 1,
            "successRate": 0.0,
            "p50LatencyMs": 3001,
            "p95LatencyMs": 3001,
            "emulatorApiTrialCounts": {"34": 1},
            "minimumTrialsMet": False,
            "successRateMet": False,
            "latencyMet": False,
            "sessionContractMet": False,
            "dedupeContractMet": False,
            "runtimeOriginMet": True,
            "perEmulatorApiThresholdsMet": False,
            "dataIntegrityMet": True,
            "invalidRecordCount": 0,
            "invalidTrialIds": [],
            "invalidAttemptIds": [],
            "inconsistentSuccessTrialIds": [],
            "emulatorCandidate": False,
            "decision": "INCONCLUSIVE",
        },
    }


class GateKHarnessTest(unittest.TestCase):
    def test_service_cancels_active_read_from_each_lifecycle_boundary(self) -> None:
        service = (
            REPO_ROOT
            / "android/gate-k-prototype/src/main/kotlin/com/vibesync/gatek/"
            / "GateKPrototypeInputMethodService.kt"
        ).read_text(encoding="utf-8")

        destroy_start = service.index("override fun onDestroy()")
        destroy_end = service.index("\n    }", destroy_start)
        destroy = service[destroy_start:destroy_end]
        self.assertIn("activeReadLifecycle.onServiceDestroyed()", destroy)
        self.assertLess(
            destroy.index("activeReadLifecycle.onServiceDestroyed()"),
            destroy.index("finishActiveSession()"),
        )

        finish_start = service.index("private fun finishActiveSession()")
        finish_end = service.index("\n    }", finish_start)
        finish = service[finish_start:finish_end]
        self.assertIn("activeReadLifecycle.onSessionHidden(sessionId)", finish)
        self.assertLess(
            finish.index("activeReadLifecycle.onSessionHidden(sessionId)"),
            finish.index("attemptCoordinator.onSessionHidden("),
        )

        timeout_start = service.index("private fun scheduleAttemptTimeout(")
        timeout_end = service.index("\n    }", timeout_start)
        timeout = service[timeout_start:timeout_end]
        self.assertIn("activeReadLifecycle.onAttemptDeadline(", timeout)
        self.assertLess(
            timeout.index("GateKCandidateReadinessPolicy.isDeadlineReached("),
            timeout.index("activeReadLifecycle.onAttemptDeadline("),
        )

    def test_service_rechecks_late_published_read_resources_after_cancel(self) -> None:
        service = (
            REPO_ROOT
            / "android/gate-k-prototype/src/main/kotlin/com/vibesync/gatek/"
            / "GateKPrototypeInputMethodService.kt"
        ).read_text(encoding="utf-8")

        open_start = service.index("private fun openTransientContent(")
        finally_start = service.index("        } finally {", open_start)
        finally_end = service.index("\n        }\n    }", finally_start)
        cleanup = service[finally_start:finally_end]

        self.assertIn("if (!handedOff)", cleanup)
        self.assertIn("closePublishedResources()", cleanup)
        self.assertGreater(
            cleanup.rfind("closePublishedResources()"),
            cleanup.index("if (!handedOff)"),
        )

    def test_service_uses_cancellable_prepare_commit_and_zeroes_content(self) -> None:
        service = (
            REPO_ROOT
            / "android/gate-k-prototype/src/main/kotlin/com/vibesync/gatek/"
            / "GateKPrototypeInputMethodService.kt"
        ).read_text(encoding="utf-8")
        lifecycle = (
            REPO_ROOT
            / "android/gate-k-prototype/src/main/kotlin/com/vibesync/gatek/"
            / "GateKActiveReadLifecycle.kt"
        ).read_text(encoding="utf-8")

        run_start = service.index("val result = readLease.runCancellable(")
        run_end = service.index("\n            } finally {", run_start)
        cancellable_path = service[run_start:run_end]
        self.assertIn("pipeline.prepareObservation(candidate)", cancellable_path)
        self.assertIn("pipeline.prepareAcceptedObservation(", cancellable_path)
        self.assertIn("pipeline.commitPreparedObservation(prepared)", cancellable_path)
        self.assertNotIn("pipeline.observe(", cancellable_path)

        cleanup_start = service.index("            } finally {", run_start)
        cleanup_end = service.index("\n            }\n        }", cleanup_start)
        cleanup = service[cleanup_start:cleanup_end]
        self.assertIn("content.fill(0)", cleanup)
        self.assertLess(
            cleanup.index("content.fill(0)"),
            cleanup.index("activeReadLifecycle.releaseRead(readLease)"),
        )

        self.assertIn("private val commitLock = Any()", lifecycle)
        self.assertIn("synchronized(commitLock)", lifecycle)
        self.assertIn("state.get() != GateKActiveReadState.PROCESSING", lifecycle)

    def test_identity_preparation_is_chunked_and_compatibility_path_rejects_early(self) -> None:
        identity = (
            REPO_ROOT
            / "android/gate-k-prototype/src/main/kotlin/com/vibesync/gatek/"
            / "CandidateIdentity.kt"
        ).read_text(encoding="utf-8")
        self.assertIn("internal fun prepareIdentity(", identity)
        self.assertIn("val chunkSize = 64 * 1024", identity)
        self.assertGreaterEqual(identity.count("shouldContinue()"), 3)

        observe_start = identity.index("fun observe(")
        observe_end = identity.index("    /**", observe_start)
        observe = identity[observe_start:observe_end]
        self.assertLess(
            observe.index("candidate.content.isEmpty()"),
            observe.index("CandidateIdentity(sha256(candidate.content))"),
        )

    def test_runner_requires_selected_gate_k_ime_and_all_interactive_windows(self) -> None:
        runner = (REPO_ROOT / "tools/android/run-gate-k-emulator-trials.sh").read_text(
            encoding="utf-8",
        )
        self.assertIn('adb shell ime set "$ime_component"', runner)
        self.assertIn("settings get secure default_input_method", runner)
        self.assertIn("verify_selected_ime", runner)
        self.assertIn(
            "adb shell uiautomator dump --windows /sdcard/gate-k-ui.xml",
            runner,
        )
        self.assertIn(
            "adb shell uiautomator dump --windows /sdcard/gate-k-ui.xml >/dev/null 2>&1 &&",
            runner,
        )

        with self.subTest(selected="Gate K prototype"):
            self.assertEqual(
                0,
                run_runner_ime_selection_seam(
                    "com.vibesync.gatek/.GateKPrototypeInputMethodService",
                ),
            )
        with self.subTest(selected="Gboard"):
            self.assertNotEqual(
                0,
                run_runner_ime_selection_seam(
                    "com.google.android.inputmethod.latin/com.android.inputmethod.latin.LatinIME",
                ),
            )
        with self.subTest(selected="settles after ime set"):
            self.assertEqual(
                0,
                run_runner_ime_selection_sequence(
                    (
                        "com.google.android.inputmethod.latin/com.android.inputmethod.latin.LatinIME",
                        "com.vibesync.gatek/.GateKPrototypeInputMethodService",
                    ),
                    2,
                ),
            )

    def test_runner_restarts_host_and_rechecks_foreground_before_each_nonce(self) -> None:
        runner = (REPO_ROOT / "tools/android/run-gate-k-emulator-trials.sh").read_text(
            encoding="utf-8",
        )
        self.assertIn("start_trial_host", runner)
        self.assertIn('adb shell am force-stop "$host_package"', runner)
        self.assertIn('adb shell am start -W -n "$host_package/.MainActivity"', runner)
        loop = runner.index('for trial in $(seq 1 "$trial_count");')
        start = runner.index('start_trial_host "$nonce"', loop)
        foreground = runner.index("wait_for_host_foreground", start)
        nonce = runner.index('wait_for_nonce_standard "$nonce"', foreground)
        self.assertLess(loop, start)
        self.assertLess(start, foreground)
        self.assertLess(foreground, nonce)
        self.assertIn('wait_for_host_foreground || {', runner)

    def test_runner_requires_live_visible_gate_k_ime_before_trials(self) -> None:
        runner = (REPO_ROOT / "tools/android/run-gate-k-emulator-trials.sh").read_text(
            encoding="utf-8",
        )
        host_check = runner.index("wait_for_host_foreground || {")
        selection = runner.index("select_and_verify_ime\n")
        live_verification = runner.index(
            "verify_live_ime_visible\n",
            host_check,
        )
        trials = runner.index('for trial in $(seq 1 "$trial_count");', live_verification)
        self.assertLess(selection, host_check)
        self.assertLess(host_check, live_verification)
        self.assertLess(live_verification, trials)
        self.assertIn("dumpsys input_method", runner)
        self.assertIn("mCurMethodId", runner)
        self.assertIn("mCurImeId", runner)
        self.assertNotIn("ime list", runner)

        visible = (
            "mCurMethodId=com.vibesync.gatek/.GateKPrototypeInputMethodService\n"
            "mInputShown=true\n"
        )
        gboard = (
            "mCurMethodId=com.google.android.inputmethod.latin/com.android.inputmethod.latin.LatinIME\n"
            "mInputShown=true\n"
        )
        invisible = (
            "mCurImeId=com.vibesync.gatek/.GateKPrototypeInputMethodService\n"
            "mInputShown=false\n"
        )
        with self.subTest(state="Gate K visible"):
            self.assertEqual(0, run_runner_live_ime_visibility_seam(visible))
        with self.subTest(state="Gboard visible"):
            self.assertNotEqual(0, run_runner_live_ime_visibility_seam(gboard))
        with self.subTest(state="Gate K invisible"):
            self.assertNotEqual(0, run_runner_live_ime_visibility_seam(invisible))
        for window_vis, expected in (
            ("0x1", False),
            ("0x3", True),
            ("0x4", False),
            ("0x8", False),
            ("2", True),
        ):
            with self.subTest(state=f"Gate K mImeWindowVis={window_vis}"):
                dump = (
                    "mCurMethodId=com.vibesync.gatek/.GateKPrototypeInputMethodService\n"
                    f"mImeWindowVis={window_vis}\n"
                )
                result = run_runner_live_ime_visibility_seam(dump)
                if expected:
                    self.assertEqual(0, result)
                else:
                    self.assertNotEqual(0, result)

    def test_runner_dump_ui_clears_stale_files_and_requires_fresh_output(self) -> None:
        runner = (REPO_ROOT / "tools/android/run-gate-k-emulator-trials.sh").read_text(
            encoding="utf-8",
        )
        self.assertIn('rm -f -- "$ui_dump_file"', runner)
        self.assertIn("adb shell rm -f /sdcard/gate-k-ui.xml", runner)
        self.assertIn(
            "adb shell uiautomator dump --windows /sdcard/gate-k-ui.xml",
            runner,
        )
        self.assertIn('[[ -s "$ui_dump_file" ]]', runner)

        returncode, contents, log = run_runner_ui_dump_seam("present")
        self.assertEqual(0, returncode)
        self.assertTrue(contents)
        self.assertEqual("remote-rm\nremote-dump\nremote-cat\n", log)

        returncode, contents, log = run_runner_ui_dump_seam("missing")
        self.assertNotEqual(0, returncode)
        self.assertEqual(b"", contents)
        self.assertEqual("remote-rm\nremote-dump\nremote-cat\n", log)

        returncode, contents, log = run_runner_ui_dump_seam("dump-fails")
        self.assertNotEqual(0, returncode)
        self.assertEqual(b"", contents)
        self.assertEqual("remote-rm\nremote-dump\n", log)

    def test_runner_standard_dump_is_fresh_and_excludes_ime_window_flag(self) -> None:
        runner = (REPO_ROOT / "tools/android/run-gate-k-emulator-trials.sh").read_text(
            encoding="utf-8",
        )
        self.assertIn("dump_ui_standard()", runner)
        self.assertIn(
            "adb shell uiautomator dump /sdcard/gate-k-ui.xml",
            runner,
        )
        self.assertIn(
            "adb shell uiautomator dump /sdcard/gate-k-ui.xml >/dev/null 2>&1 &&",
            runner,
        )

        returncode, contents, log = run_runner_standard_ui_dump_seam("present")
        self.assertEqual(0, returncode)
        self.assertTrue(contents)
        self.assertEqual("remote-rm\nremote-dump\nremote-cat\n", log)

        returncode, contents, log = run_runner_standard_ui_dump_seam("missing")
        self.assertNotEqual(0, returncode)
        self.assertEqual(b"", contents)
        self.assertEqual("remote-rm\nremote-dump\nremote-cat\n", log)

        returncode, contents, log = run_runner_standard_ui_dump_seam("dump-fails")
        self.assertNotEqual(0, returncode)
        self.assertEqual(b"", contents)
        self.assertEqual("remote-rm\nremote-dump\n", log)

    def test_runner_uses_live_ime_then_standard_nonce_then_windows_button(self) -> None:
        runner = (REPO_ROOT / "tools/android/run-gate-k-emulator-trials.sh").read_text(
            encoding="utf-8",
        )
        self.assertIn("dump_ui_standard", runner)
        self.assertIn(
            "adb shell uiautomator dump /sdcard/gate-k-ui.xml",
            runner,
        )
        self.assertNotIn('adb shell input keyevent 4', runner)
        self.assertNotIn('adb shell ime hide', runner)
        self.assertNotIn("find_host_field_center", runner)
        self.assertNotIn("input_method_is_selected_and_hidden", runner)
        trial_loop = runner.index('for trial in $(seq 1 "$trial_count");')
        foreground = runner.index("wait_for_host_foreground || {", trial_loop)
        selected = runner.index("ensure_gate_k_ime_selected", foreground)
        visible = runner.index("verify_live_ime_visible", selected)
        standard = runner.index('wait_for_nonce_standard "$nonce"', visible)
        button = runner.index('center="$(wait_for_button)"', standard)
        trigger = runner.index("adb shell input keyevent 120", button)
        self.assertLess(foreground, selected)
        self.assertLess(selected, visible)
        self.assertLess(visible, standard)
        self.assertLess(standard, button)
        self.assertLess(button, trigger)
        self.assertIn("trial_trigger_settle_seconds=0.50", runner)
        self.assertIn('sleep "$trial_trigger_settle_seconds"', runner)
        self.assertNotIn("sleep 0.10", runner)
        self.assertNotIn('adb shell ime set "$ime_component"', runner[trial_loop:])
        self.assertNotRegex(runner, r"adb shell input tap [0-9]+ [0-9]+")

    def test_runner_reselects_ime_with_bounded_attempts(self) -> None:
        runner = (REPO_ROOT / "tools/android/run-gate-k-emulator-trials.sh").read_text(
            encoding="utf-8",
        )
        self.assertIn("select_and_verify_ime()", runner)
        self.assertIn("ensure_gate_k_ime_selected()", runner)
        self.assertIn('selected_ime="$(adb shell settings get secure default_input_method', runner)
        self.assertIn('if [[ "$selected_ime" == "$ime_component" ]]; then', runner)
        self.assertIn('for attempt in $(seq 1 "$max_attempts");', runner)
        self.assertIn('verify_selected_ime "$max_polls"', runner)
        self.assertEqual(1, runner.count('adb shell ime set "$ime_component"'))
        trial_loop = runner.index('for trial in $(seq 1 "$trial_count");')
        self.assertNotIn('adb shell ime set "$ime_component"', runner[trial_loop:])

        gate_k = "com.vibesync.gatek/.GateKPrototypeInputMethodService"
        gboard = "com.google.android.inputmethod.latin/com.android.inputmethod.latin.LatinIME"
        with self.subTest(state="settles after bounded reselection"):
            returncode, set_count = run_runner_ime_reselection_seam(
                (gboard, gate_k),
                max_attempts=2,
                max_polls=2,
            )
            self.assertEqual(0, returncode)
            self.assertEqual(2, set_count)
        with self.subTest(state="persistent wrong IME fails closed"):
            returncode, set_count = run_runner_ime_reselection_seam(
                (gboard,),
                max_attempts=2,
                max_polls=1,
            )
            self.assertNotEqual(0, returncode)
            self.assertEqual(2, set_count)
        with self.subTest(state="already selected skips ime set"):
            returncode, set_count, _ = run_runner_ime_selection_drift_seam(
                gate_k,
                (gate_k,),
                max_attempts=2,
                max_polls=1,
            )
            self.assertEqual(0, returncode)
            self.assertEqual(0, set_count)
        with self.subTest(state="selection drift is repaired once"):
            returncode, set_count, stderr = run_runner_ime_selection_drift_seam(
                gboard,
                (gate_k,),
                max_attempts=2,
                max_polls=1,
            )
            self.assertEqual(0, returncode)
            self.assertEqual(1, set_count)
            self.assertEqual("", stderr)
            self.assertNotIn(gboard, stderr)
            self.assertNotIn("not the selected default IME", stderr)
        with self.subTest(state="selection drift remains wrong and fails closed"):
            returncode, set_count, _ = run_runner_ime_selection_drift_seam(
                gboard,
                (gboard,),
                max_attempts=2,
                max_polls=1,
            )
            self.assertNotEqual(0, returncode)
            self.assertEqual(2, set_count)

    def test_runner_evidence_protocol_is_fail_closed_for_count_and_export(self) -> None:
        present = "__GATE_K_PRESENT__\n"
        count_cases = (
            ("explicit absence", "__GATE_K_ABSENT__\n", 0),
            ("valid empty", present + '{"trialRecords":[]}', 0),
            (
                "valid one record",
                present + '{"trialRecords":[{"trialId":"one"}]}',
                1,
            ),
        )
        for label, payload, expected_count in count_cases:
            with self.subTest(mode="count", label=label):
                returncode, stdout, _, _ = run_runner_evidence_seam(
                    "count",
                    payload,
                )
                self.assertEqual(0, returncode)
                self.assertEqual(str(expected_count), stdout.strip())

        invalid_cases = (
            ("raw missing-file diagnostic", "cat: files/gate-k-evidence.json: No such file or directory", 0),
            ("malformed JSON", present + "{", 0),
            ("unexpected schema", present + '{"other":[]}', 0),
            ("present marker with diagnostic", present + "cat: permission denied", 0),
            ("transport failure", "", 1),
        )
        for label, payload, fake_exit in invalid_cases:
            with self.subTest(mode="count", label=label):
                returncode, stdout, _, _ = run_runner_evidence_seam(
                    "count",
                    payload,
                    fake_exit=fake_exit,
                )
                self.assertNotEqual(0, returncode)
                self.assertEqual("", stdout)

        for payload in (
            present + '{"trialRecords":[]}',
            present + '{"trialRecords":[{"trialId":"one"}]}',
        ):
            with self.subTest(mode="export", payload=payload):
                returncode, _, exported, contents = run_runner_evidence_seam(
                    "export",
                    payload,
                )
                self.assertEqual(0, returncode)
                self.assertTrue(exported)
                self.assertEqual(payload.split("\n", 1)[1].encode(), contents)

        for label, payload, fake_exit in invalid_cases:
            with self.subTest(mode="export", label=label):
                returncode, _, exported, contents = run_runner_evidence_seam(
                    "export",
                    payload,
                    fake_exit=fake_exit,
                )
                self.assertNotEqual(0, returncode)
                self.assertFalse(exported)
                self.assertEqual(b"", contents)

    def test_foreground_predicate_accepts_current_and_legacy_resumed_fields(self) -> None:
        accepted_dumps = (
            "  ResumedActivity: ActivityRecord{u0 com.vibesync.gatekhost/.MainActivity}",
            "  topResumedActivity=ActivityRecord{u0 com.vibesync.gatekhost/.MainActivity}",
            "  mResumedActivity: ActivityRecord{u0 com.vibesync.gatekhost/.MainActivity}",
        )
        rejected_dumps = (
            "  ResumedActivity: ActivityRecord{u0 com.android.launcher3/.Launcher}\n"
            "  Task{com.vibesync.gatekhost/.MainActivity}",
            "  topResumedActivity=ActivityRecord{u0 com.vibesync.gatekhost2/.MainActivity}",
            "  ActivityRecord{u0 com.vibesync.gatekhost/.MainActivity}",
        )

        for activity_dump in accepted_dumps:
            with self.subTest(activity_dump=activity_dump):
                self.assertTrue(runner_foreground_predicate(activity_dump))
        for activity_dump in rejected_dumps:
            with self.subTest(activity_dump=activity_dump):
                self.assertFalse(runner_foreground_predicate(activity_dump))

    def test_foreground_predicate_supports_prototype_package_reverse_guard(self) -> None:
        runner = (REPO_ROOT / "tools/android/run-gate-k-emulator-trials.sh").read_text(
            encoding="utf-8",
        )
        self.assertIn(
            'activity_package_is_foreground "$activity_dump" "$prototype_package"',
            runner,
        )
        for activity_dump in (
            "  ResumedActivity: ActivityRecord{u0 com.vibesync.gatek/.GateKPrototypeInputMethodService}",
            "  topResumedActivity=ActivityRecord{u0 com.vibesync.gatek/.GateKPrototypeInputMethodService}",
            "  mResumedActivity: ActivityRecord{u0 com.vibesync.gatek/.GateKPrototypeInputMethodService}",
        ):
            with self.subTest(activity_dump=activity_dump):
                self.assertTrue(runner_foreground_predicate(activity_dump, "com.vibesync.gatek"))

    def test_button_parser_returns_center_without_coordinates_in_runner(self) -> None:
        self.assertEqual((110, 60), find_gate_k_button_center(VALID_UI))

    def test_button_parser_rejects_missing_or_ambiguous_button(self) -> None:
        with self.assertRaises(HarnessContractError):
            find_gate_k_button_center("<hierarchy><node text='Other' /></hierarchy>")
        with self.assertRaises(HarnessContractError):
            find_gate_k_button_center(
                "<hierarchy>"
                "<node text='Start Gate K attempt' bounds='[0,0][10,10]' />"
                "<node text='Start Gate K attempt' bounds='[0,0][20,20]' />"
                "</hierarchy>"
            )
        with self.assertRaises(HarnessContractError):
            find_gate_k_button_center(VALID_UI.replace('enabled="true"', 'enabled="false"'))

    def test_nonce_parser_requires_the_expected_unique_host_nonce(self) -> None:
        xml = (
            "<hierarchy>"
            "<node text='Gate K screenshot nonce: trial-1' "
            "content-desc='Gate K screenshot nonce: trial-1' />"
            "</hierarchy>"
        )
        self.assertEqual("trial-1", find_gate_k_nonce(xml, "trial-1"))
        with self.assertRaises(HarnessContractError):
            find_gate_k_nonce(xml, "trial-2")
        with self.assertRaises(HarnessContractError):
            find_gate_k_nonce(
                xml.replace("</hierarchy>", "<node text='Gate K screenshot nonce: trial-1' /></hierarchy>"),
                "trial-1",
            )

    def test_evidence_validator_accepts_runtime_metadata_timeout(self) -> None:
        validate_evidence(valid_evidence(), expected_trials=1, expected_api=34)

    def test_evidence_validator_rejects_synthetic_and_image_fields(self) -> None:
        evidence = valid_evidence()
        evidence["trialRecords"][0]["origin"] = "SYNTHETIC"
        with self.assertRaises(HarnessContractError):
            validate_evidence(evidence, expected_trials=1, expected_api=34)

        evidence = valid_evidence()
        evidence["trialRecords"][0]["imageBytes"] = 1
        with self.assertRaises(HarnessContractError):
            validate_evidence(evidence, expected_trials=1, expected_api=34)

    def test_evidence_validator_rejects_wrong_count_or_api(self) -> None:
        with self.assertRaises(HarnessContractError):
            validate_evidence(valid_evidence(), expected_trials=2, expected_api=34)
        with self.assertRaises(HarnessContractError):
            validate_evidence(valid_evidence(), expected_trials=1, expected_api=35)

    def test_workflow_requires_dispatch_and_exact_branch_push(self) -> None:
        workflow = (
            "on:\n"
            "  workflow_dispatch:\n"
            "  push:\n"
            "    branches:\n"
            "      - codex/android-m6-keyboard-gate-20260828\n"
            "concurrency:\n"
            "  group: gate-k-${{ github.ref }}\n"
            "  cancel-in-progress: true\n"
            "jobs:\n"
            "  setup:\n"
            "    steps:\n"
            "      - name: Materialize ignored Gradle wrapper\n"
            "        run: |\n"
            "          [[ -n \"${FLUTTER_ROOT:-}\" && -d \"$FLUTTER_ROOT\" ]]\n"
            "          printf 'flutter.sdk=%s\\n' \"$FLUTTER_ROOT\" > android/local.properties\n"
            "          [[ -x android/gradlew && -f android/gradle/wrapper/gradle-wrapper.jar ]]\n"
            "      - name: Enable KVM\n"
            "        run: |\n"
            "          echo 'KERNEL==\"kvm\", GROUP=\"kvm\", MODE=\"0666\", OPTIONS+=\"static_node=kvm\"' | sudo tee /etc/udev/rules.d/99-kvm4all.rules\n"
            "          sudo udevadm control --reload-rules\n"
            "          sudo udevadm trigger --name-match=kvm\n"
        )
        validate_workflow_contract(
            workflow,
            branch="codex/android-m6-keyboard-gate-20260828",
        )

        with self.assertRaises(HarnessContractError):
            validate_workflow_contract(workflow.replace("workflow_dispatch", "pull_request"), branch="codex/android-m6-keyboard-gate-20260828")
        with self.assertRaises(HarnessContractError):
            validate_workflow_contract(workflow.replace("codex/android-m6-keyboard-gate-20260828", "main"), branch="codex/android-m6-keyboard-gate-20260828")

        validate_workflow_contract(
            (REPO_ROOT / ".github/workflows/gate-k-prototype.yml").read_text(encoding="utf-8"),
            branch="codex/android-m6-keyboard-gate-20260828",
        )

    def test_runner_requires_sha_guard_metadata_and_canonical_apks(self) -> None:
        runner = """
        GITHUB_SHA=${GITHUB_SHA:-}
        expected_sha="$(git -C "$repo_root" rev-parse HEAD)"
        if [[ -n "$GITHUB_SHA" && "$GITHUB_SHA" != "$expected_sha" ]]; then exit 2; fi
        checkout_status="$(git -C "$repo_root" status --porcelain --untracked-files=all)"
        [[ -z "$checkout_status" ]]
        printf 'gitSha=%s\\n' "$expected_sha"
        printf 'gitRef=%s\\n' "${GITHUB_REF:-unavailable}"
        printf 'gitEvent=%s\\n' "${GITHUB_EVENT_NAME:-unavailable}"
        build_root="$repo_root/build"
        prototype_apk="$build_root/gate-k-prototype/outputs/apk/debug/gate-k-prototype-debug.apk"
        host_apk="$build_root/gate-k-host/outputs/apk/debug/gate-k-host-debug.apk"
        adb shell settings put secure show_ime_with_hard_keyboard 1
        nonce="gate-k-trial-${trial}"
        previous_nonce=""
        adb shell am start -W -n "$host_package/.MainActivity" --es gate_k_nonce "$nonce"
        find_trial_nonce "$nonce"
        output_dir="$(realpath -m -- "$output_dir")"
        case "$output_dir" in
          "$repo_root"|"$repo_root"/*) ;;
          *) exit 2 ;;
        esac
        """
        validate_runner_contract(runner)

        with self.assertRaises(HarnessContractError):
            validate_runner_contract(runner.replace('build_root="$repo_root/build"', 'find "$repo_root/.." -type f'))
        with self.assertRaises(HarnessContractError):
            validate_runner_contract(runner.replace('GITHUB_SHA=${GITHUB_SHA:-}', ''))
        with self.assertRaises(HarnessContractError):
            validate_runner_contract(runner.replace('checkout_status=', 'missing_status='))
        with self.assertRaises(HarnessContractError):
            validate_runner_contract(runner.replace('GITHUB_REF', 'OTHER_REF'))

        validate_runner_contract(
            (REPO_ROOT / "tools/android/run-gate-k-emulator-trials.sh").read_text(encoding="utf-8"),
        )

    def test_workflow_runs_formal_gate_k_matrix_and_trial_count(self) -> None:
        workflow = (
            REPO_ROOT / ".github/workflows/gate-k-prototype.yml"
        ).read_text(encoding="utf-8")
        formal_command = (
            'GATE_K_OUTPUT_DIR="$GITHUB_WORKSPACE/gate-k-artifacts-api${GATE_K_API_LEVEL}" '
            'bash tools/android/run-gate-k-emulator-trials.sh '
            '--api-level "$GATE_K_API_LEVEL" --trials 40'
        )
        self.assertIn("name: Gate K emulator API ${{ matrix.api-level }}", workflow)
        for api_level in (34, 35, 36):
            self.assertIn(f"- api-level: {api_level}", workflow)
        self.assertIn(formal_command, workflow)
        self.assertNotIn("TEMP DIAGNOSTIC", workflow)
        self.assertNotIn("TEMP query-stage", workflow)
        self.assertNotIn("DEBUG-" + "GATEK", workflow)
        self.assertNotIn("gate_k_diagnostic_", workflow)
        self.assertNotIn("--trials 12", workflow)
        self.assertEqual(1, workflow.count("--trials 40"))
        self.assertIn("gate-k-artifacts-api${{ matrix.api-level }}/**", workflow)

    def test_evidence_validator_recomputes_candidate_from_records(self) -> None:
        evidence = valid_evidence()
        group = evidence["summary"]["emulatorApiSummaries"]["34"]
        group["successRateMet"] = True
        group["latencyMet"] = True
        with self.assertRaises(HarnessContractError):
            validate_evidence(evidence, expected_trials=1, expected_api=34, require_api_candidate=True)

    def test_evidence_validator_rejects_extra_and_inconsistent_schema_fields(self) -> None:
        evidence = valid_evidence()
        evidence["trialRecords"][0]["unexpected"] = "value"
        with self.assertRaises(HarnessContractError):
            validate_evidence(evidence, expected_trials=1, expected_api=34)

        evidence = valid_evidence()
        evidence["summary"]["failedTrials"] = 0
        with self.assertRaises(HarnessContractError):
            validate_evidence(evidence, expected_trials=1, expected_api=34)

    def test_evidence_validator_rejects_success_under_reported_by_caller(self) -> None:
        evidence = valid_evidence()
        record = evidence["trialRecords"][0]
        record.update(
            reportedSuccess=False,
            latencyMs=100,
            sessionOutcome="ACCEPTED",
            dedupeOutcome="FIRST_SEEN",
            failureReason="NONE",
            detectedElapsedRealtimeMs=1100,
        )
        summary = evidence["summary"]
        summary.update(
            successfulTrials=0,
            failedTrials=1,
            successRate=0.0,
            p50LatencyMs=100,
            p95LatencyMs=100,
            latencyMet=True,
            sessionContractMet=True,
            dedupeContractMet=True,
            emulatorCandidate=False,
        )
        summary["emulatorApiSummaries"]["34"].update(
            successfulTrials=0,
            failedTrials=1,
            successRate=0.0,
            p50LatencyMs=100,
            p95LatencyMs=100,
            latencyMet=True,
        )
        with self.assertRaises(HarnessContractError):
            validate_evidence(evidence, expected_trials=1, expected_api=34)

    def test_evidence_validator_rejects_bool_as_integer_summary_field(self) -> None:
        evidence = valid_evidence()
        evidence["summary"]["totalTrials"] = True
        with self.assertRaises(HarnessContractError):
            validate_evidence(evidence, expected_trials=1, expected_api=34)


if __name__ == "__main__":
    unittest.main()
