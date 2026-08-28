#!/usr/bin/env python3
"""Pure contract tests for the bounded Gate K emulator harness."""

from __future__ import annotations

import unittest

from gate_k_harness import HarnessContractError, find_gate_k_button_center, validate_evidence


VALID_UI = """
<hierarchy>
  <node class="android.widget.Button" text="Start Gate K attempt"
        content-desc="Start Gate K attempt" bounds="[10,20][210,100]" />
</hierarchy>
"""


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
            },
        },
    }


class GateKHarnessTest(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
