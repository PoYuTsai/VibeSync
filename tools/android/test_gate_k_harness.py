#!/usr/bin/env python3
"""Pure contract tests for the bounded Gate K emulator harness."""

from __future__ import annotations

import os
import subprocess
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
