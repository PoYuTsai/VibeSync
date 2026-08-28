#!/usr/bin/env python3
"""Pure parser and validator seams for the Gate K emulator runner."""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any, Mapping


BUTTON_LABEL = "Start Gate K attempt"
_BOUNDS_RE = re.compile(r"^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$")
_REQUIRED_RECORD_FIELDS = frozenset(
    {
        "trialId",
        "deviceClass",
        "apiLevel",
        "deviceModel",
        "reportedSuccess",
        "latencyMs",
        "sessionOutcome",
        "dedupeOutcome",
        "attemptId",
        "sessionId",
        "triggerElapsedRealtimeMs",
        "detectedElapsedRealtimeMs",
        "deviceDescriptor",
        "failureReason",
        "origin",
    }
)
_BOUNDED_FAILURES = frozenset(
    {
        "NONE",
        "TIMEOUT",
        "SESSION_ENDED",
        "GRANT_UNAVAILABLE",
        "OBSERVER_ERROR",
        "QUERY_FAILED",
        "CONTENT_UNAVAILABLE",
        "UNVERIFIED_OUTCOME",
        "INVALID_EVENT",
        "INVALID_TIMING",
        "DUPLICATE_CALLBACK",
        "DUPLICATE_ATTEMPT",
        "METADATA_REJECTED",
        "GENERATION_OVERFLOW",
        "HASH_ERROR",
    }
)
_FORBIDDEN_KEYS = frozenset(
    {
        "image",
        "imagebytes",
        "bytes",
        "chat",
        "chattext",
        "content",
        "uri",
        "path",
        "filepath",
        "imagepath",
        "exception",
        "errormessage",
        "stacktrace",
    }
)
_ROOT_FIELDS = frozenset({"schemaVersion", "trialRecords", "summary"})
_SUMMARY_FIELDS = frozenset(
    {
        "totalTrials",
        "successfulTrials",
        "failedTrials",
        "successRate",
        "p50LatencyMs",
        "p95LatencyMs",
        "emulatorApiTrialCounts",
        "minimumTrialsMet",
        "successRateMet",
        "latencyMet",
        "sessionContractMet",
        "dedupeContractMet",
        "runtimeOriginMet",
        "perEmulatorApiThresholdsMet",
        "dataIntegrityMet",
        "invalidRecordCount",
        "invalidTrialIds",
        "invalidAttemptIds",
        "inconsistentSuccessTrialIds",
        "emulatorApiSummaries",
        "emulatorCandidate",
        "decision",
    }
)
_GROUP_FIELDS = frozenset(
    {
        "totalTrials",
        "successfulTrials",
        "failedTrials",
        "successRate",
        "p50LatencyMs",
        "p95LatencyMs",
        "successRateMet",
        "latencyMet",
    }
)
_SESSION_OUTCOMES = frozenset({"ACCEPTED", "IGNORED", "REJECTED", "NOT_EVALUATED"})
_DEDUPE_OUTCOMES = frozenset({"FIRST_SEEN", "DUPLICATE_SUPPRESSED", "NOT_EVALUATED"})
_REQUIRED_EMULATOR_APIS = (34, 35, 36)
_MIN_TRIALS_PER_API = 40
_SUCCESS_RATE_FLOOR = 0.95
_MAX_SUCCESS_LATENCY_MS = 3_000


class HarnessContractError(ValueError):
    """Raised when UI or metadata violates the bounded runner contract."""


def find_gate_k_button_center(xml_text: str) -> tuple[int, int]:
    """Return the center of the uniquely labelled button in a UI dump."""

    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError as error:
        raise HarnessContractError("uiautomator XML is invalid") from error

    matches = [
        node
        for node in root.iter("node")
        if node.get("text") == BUTTON_LABEL or node.get("content-desc") == BUTTON_LABEL
    ]
    if len(matches) != 1:
        raise HarnessContractError("expected exactly one Gate K attempt button")
    if matches[0].get("enabled") != "true":
        raise HarnessContractError("Gate K attempt button is not ready")

    bounds = matches[0].get("bounds", "")
    parsed = _BOUNDS_RE.fullmatch(bounds)
    if parsed is None:
        raise HarnessContractError("Gate K attempt button has no usable bounds")
    left, top, right, bottom = (int(value) for value in parsed.groups())
    if right <= left or bottom <= top:
        raise HarnessContractError("Gate K attempt button bounds are empty")
    return ((left + right) // 2, (top + bottom) // 2)


def validate_workflow_contract(workflow_text: str, *, branch: str) -> None:
    """Check that the disposable workflow is reachable only on its task branch."""

    if not branch or "\n" in branch or "\r" in branch:
        raise HarnessContractError("workflow branch is invalid")
    lines = workflow_text.splitlines()
    try:
        on_index = next(index for index, line in enumerate(lines) if line.strip() == "on:")
    except StopIteration as error:
        raise HarnessContractError("workflow trigger block is missing") from error

    event_lines: list[str] = []
    for line in lines[on_index + 1 :]:
        if line and not line[0].isspace() and line.strip().endswith(":"):
            break
        event_lines.append(line)
    event_keys = {
        match.group(1)
        for line in event_lines
        if (match := re.match(r"^  ([A-Za-z0-9_-]+):\s*$", line))
    }
    if event_keys != {"workflow_dispatch", "push"}:
        raise HarnessContractError("workflow must expose only dispatch and exact-branch push")

    push_index = next(
        (index for index, line in enumerate(event_lines) if line == "  push:"),
        None,
    )
    if push_index is None:
        raise HarnessContractError("push trigger is missing")
    push_lines: list[str] = []
    for line in event_lines[push_index + 1 :]:
        if re.match(r"^  [A-Za-z0-9_-]+:\s*$", line):
            break
        push_lines.append(line)
    branch_matches = [
        match.group(1)
        for line in push_lines
        if (match := re.match(r"^      - ([^\s#]+)\s*$", line))
    ]
    if branch_matches != [branch]:
        raise HarnessContractError("push trigger must match exactly the task branch")
    required_setup = (
        'FLUTTER_ROOT:-',
        '-d "$FLUTTER_ROOT"',
        "printf 'flutter.sdk=%s\\n' \"$FLUTTER_ROOT\" > android/local.properties",
        "[[ -x android/gradlew && -f android/gradle/wrapper/gradle-wrapper.jar ]]",
        "name: Enable KVM",
        "OPTIONS+=\"static_node=kvm\"",
        "sudo udevadm control --reload-rules",
        "sudo udevadm trigger --name-match=kvm",
        "group: gate-k-${{ github.ref }}",
        "cancel-in-progress: true",
    )
    if any(fragment not in workflow_text for fragment in required_setup):
        raise HarnessContractError("workflow setup must validate Flutter root, wrapper, and KVM")
    if "emulator-options:" in workflow_text:
        raise HarnessContractError("workflow must retain the emulator runner default options")


def validate_runner_contract(runner_text: str) -> None:
    """Check static runner guards that protect provenance and output isolation."""

    required_fragments = (
        'GITHUB_SHA:-',
        'git -C "$repo_root" rev-parse HEAD',
        'GITHUB_SHA" != "$expected_sha"',
        'git -C "$repo_root" status --porcelain --untracked-files=all',
        'checkout_status=',
        'printf \'gitRef=%s\\n\'',
        'GITHUB_REF:-unavailable',
        'printf \'gitEvent=%s\\n\'',
        'GITHUB_EVENT_NAME:-unavailable',
        'build_root="$repo_root/build"',
        'gate-k-prototype/outputs/apk/debug/gate-k-prototype-debug.apk',
        'gate-k-host/outputs/apk/debug/gate-k-host-debug.apk',
        'adb shell settings put secure show_ime_with_hard_keyboard 1',
    )
    missing = [fragment for fragment in required_fragments if fragment not in runner_text]
    if missing:
        raise HarnessContractError(
            f"runner provenance/canonical APK guard is incomplete: {missing}"
        )
    if re.search(r"\bfind\s+", runner_text):
        raise HarnessContractError("runner must not search outside the canonical build root")
    if "realpath -m" not in runner_text or 'case "$output_dir" in' not in runner_text:
        raise HarnessContractError("runner output directory must be constrained to the repository")


def validate_evidence(
    payload: Mapping[str, Any],
    *,
    expected_trials: int,
    expected_api: int,
    require_api_candidate: bool = False,
) -> None:
    """Fail closed on schema, raw outcomes, summary derivation, and privacy."""

    if expected_trials <= 0 or expected_api < 34:
        raise HarnessContractError("invalid validator expectations")
    _reject_forbidden_keys(payload)
    _require_exact_fields(payload, _ROOT_FIELDS, "evidence root")
    if payload.get("schemaVersion") != 1:
        raise HarnessContractError("unsupported evidence schema")
    records = payload.get("trialRecords")
    summary = payload.get("summary")
    if not isinstance(records, list) or not isinstance(summary, Mapping):
        raise HarnessContractError("evidence root shape is invalid")
    _require_exact_fields(summary, _SUMMARY_FIELDS, "evidence summary")
    if len(records) != expected_trials:
        raise HarnessContractError("trial count does not match bounded run")

    seen_trial_ids: set[str] = set()
    seen_attempts: set[str] = set()
    for record in records:
        _validate_runtime_record(
            record,
            expected_api=expected_api,
            seen_trial_ids=seen_trial_ids,
            seen_attempts=seen_attempts,
        )

    _validate_derived_summary(summary, records, expected_trials=expected_trials)
    if require_api_candidate:
        group = summary["emulatorApiSummaries"][str(expected_api)]
        expected_group = _derive_group(records)
        if not (
            expected_group["totalTrials"] >= _MIN_TRIALS_PER_API
            and expected_group["successRateMet"]
            and expected_group["latencyMet"]
        ):
            raise HarnessContractError("raw per-API emulator candidate thresholds are not met")
        if group["totalTrials"] != expected_trials:
            raise HarnessContractError("per-API trial count does not match bounded run")


def _require_exact_fields(value: Mapping[str, Any], expected: frozenset[str], label: str) -> None:
    actual = set(value)
    if actual != expected:
        missing = sorted(expected - actual)
        extra = sorted(actual - expected)
        raise HarnessContractError(f"{label} fields differ (missing={missing}, extra={extra})")


def _validate_runtime_record(
    record: Any,
    *,
    expected_api: int,
    seen_trial_ids: set[str],
    seen_attempts: set[str],
) -> None:
    if not isinstance(record, Mapping):
        raise HarnessContractError("trial record is not an object")
    _require_exact_fields(record, _REQUIRED_RECORD_FIELDS, "trial record")
    string_fields = (
        "trialId",
        "deviceClass",
        "deviceModel",
        "sessionOutcome",
        "dedupeOutcome",
        "attemptId",
        "sessionId",
        "deviceDescriptor",
        "failureReason",
        "origin",
    )
    if any(not isinstance(record[field], str) for field in string_fields):
        raise HarnessContractError("trial record string field has the wrong type")
    if any(not record[field].strip() for field in ("trialId", "attemptId", "sessionId", "deviceDescriptor")):
        raise HarnessContractError("trial record identity or descriptor is empty")
    if record["trialId"] in seen_trial_ids:
        raise HarnessContractError("trial IDs must be unique")
    if record["attemptId"] in seen_attempts:
        raise HarnessContractError("attempt IDs must be unique")
    seen_trial_ids.add(record["trialId"])
    seen_attempts.add(record["attemptId"])

    if record["origin"] != "RUNTIME":
        raise HarnessContractError("synthetic trial origin is not evidence")
    if record["deviceClass"] != "EMULATOR":
        raise HarnessContractError("trial is not conservatively classified as emulator")
    if type(record["apiLevel"]) is not int or record["apiLevel"] != expected_api:
        raise HarnessContractError("trial API level does not match runner matrix")
    if record["sessionOutcome"] not in _SESSION_OUTCOMES:
        raise HarnessContractError("session outcome is outside the bounded enum")
    if record["dedupeOutcome"] not in _DEDUPE_OUTCOMES:
        raise HarnessContractError("dedupe outcome is outside the bounded enum")
    if record["failureReason"] not in _BOUNDED_FAILURES:
        raise HarnessContractError("failure reason is outside bounded enum")
    if type(record["reportedSuccess"]) is not bool:
        raise HarnessContractError("reported success must be a JSON boolean")

    descriptor = record["deviceDescriptor"]
    for field in ("manufacturer=", "brand=", "model=", "product=", "fingerprint=", "api="):
        if field not in descriptor:
            raise HarnessContractError("raw device descriptor is incomplete")
    if f"api={expected_api}" not in descriptor:
        raise HarnessContractError("descriptor API does not match runner matrix")
    _validate_timing(record)
    expected_success = _outcome_indicates_success(record)
    if record["reportedSuccess"] != expected_success:
        raise HarnessContractError("reported success disagrees with verifiable raw outcome")


def _outcome_indicates_success(record: Mapping[str, Any]) -> bool:
    return (
        record["failureReason"] == "NONE"
        and record["sessionOutcome"] == "ACCEPTED"
        and record["dedupeOutcome"] == "FIRST_SEEN"
        and 0 <= record["latencyMs"] <= _MAX_SUCCESS_LATENCY_MS
    )


def _derive_group(records: list[Mapping[str, Any]]) -> dict[str, Any]:
    latencies = sorted(record["latencyMs"] for record in records)
    successful = sum(_outcome_indicates_success(record) for record in records)
    total = len(records)
    rate = successful / total if total else 0.0
    p50 = _percentile_nearest_rank(latencies, 0.50)
    p95 = _percentile_nearest_rank(latencies, 0.95)
    return {
        "totalTrials": total,
        "successfulTrials": successful,
        "failedTrials": total - successful,
        "successRate": rate,
        "p50LatencyMs": p50,
        "p95LatencyMs": p95,
        "successRateMet": total > 0 and rate >= _SUCCESS_RATE_FLOOR,
        "latencyMet": p95 is not None and p95 <= _MAX_SUCCESS_LATENCY_MS,
    }


def _validate_derived_summary(
    summary: Mapping[str, Any],
    records: list[Mapping[str, Any]],
    *,
    expected_trials: int,
) -> None:
    expected_group = _derive_group(records)
    if summary["totalTrials"] != expected_trials:
        raise HarnessContractError("summary totalTrials disagrees with record count")
    if not _same_mapping(summary, _derive_global_summary(records, expected_group)):
        raise HarnessContractError("summary is not independently derived from raw records")

    api_counts = summary["emulatorApiTrialCounts"]
    if not isinstance(api_counts, Mapping):
        raise HarnessContractError("emulator API trial counts are not an object")
    expected_counts = {str(api): sum(record["apiLevel"] == api for record in records) for api in _REQUIRED_EMULATOR_APIS}
    expected_counts = {key: value for key, value in expected_counts.items() if value}
    if dict(api_counts) != expected_counts:
        raise HarnessContractError("emulator API trial counts disagree with records")

    api_summaries = summary["emulatorApiSummaries"]
    if not isinstance(api_summaries, Mapping):
        raise HarnessContractError("per-API summary is missing")
    if set(api_summaries) != {str(api) for api in _REQUIRED_EMULATOR_APIS}:
        raise HarnessContractError("per-API summary keys are incomplete or unexpected")
    for api in _REQUIRED_EMULATOR_APIS:
        group = api_summaries[str(api)]
        if not isinstance(group, Mapping):
            raise HarnessContractError("per-API summary group is not an object")
        _require_exact_fields(group, _GROUP_FIELDS, f"API {api} summary")
        records_for_api = [record for record in records if record["apiLevel"] == api]
        if not _same_mapping(group, _derive_group(records_for_api)):
            raise HarnessContractError(f"API {api} summary disagrees with raw records")


def _derive_global_summary(records: list[Mapping[str, Any]], group: Mapping[str, Any]) -> dict[str, Any]:
    api_counts = {
        str(api): sum(record["apiLevel"] == api for record in records)
        for api in _REQUIRED_EMULATOR_APIS
    }
    api_counts = {key: value for key, value in api_counts.items() if value}
    api_groups = {
        str(api): _derive_group([record for record in records if record["apiLevel"] == api])
        for api in _REQUIRED_EMULATOR_APIS
    }
    minimum_trials_met = all(
        api_groups[str(api)]["totalTrials"] >= _MIN_TRIALS_PER_API
        for api in _REQUIRED_EMULATOR_APIS
    )
    per_api_thresholds_met = all(
        api_groups[str(api)]["totalTrials"] >= _MIN_TRIALS_PER_API
        and api_groups[str(api)]["successRateMet"]
        and api_groups[str(api)]["latencyMet"]
        for api in _REQUIRED_EMULATOR_APIS
    )
    session_contract_met = bool(records) and all(
        record["sessionOutcome"] != "NOT_EVALUATED" for record in records
    )
    dedupe_contract_met = bool(records) and all(
        record["dedupeOutcome"] != "NOT_EVALUATED" for record in records
    )
    runtime_origin_met = bool(records) and all(record["origin"] == "RUNTIME" for record in records)
    successful = group["successfulTrials"]
    total = group["totalTrials"]
    all_emulator = bool(records) and all(record["deviceClass"] == "EMULATOR" for record in records)
    emulator_candidate = (
        all_emulator
        and minimum_trials_met
        and group["successRateMet"]
        and group["latencyMet"]
        and session_contract_met
        and dedupe_contract_met
        and runtime_origin_met
        and per_api_thresholds_met
    )
    return {
        "totalTrials": total,
        "successfulTrials": successful,
        "failedTrials": total - successful,
        "successRate": group["successRate"],
        "p50LatencyMs": group["p50LatencyMs"],
        "p95LatencyMs": group["p95LatencyMs"],
        "emulatorApiTrialCounts": api_counts,
        "minimumTrialsMet": minimum_trials_met,
        "successRateMet": total > 0 and group["successRate"] >= _SUCCESS_RATE_FLOOR,
        "latencyMet": group["p95LatencyMs"] is not None and group["p95LatencyMs"] <= _MAX_SUCCESS_LATENCY_MS,
        "sessionContractMet": session_contract_met,
        "dedupeContractMet": dedupe_contract_met,
        "runtimeOriginMet": runtime_origin_met,
        "perEmulatorApiThresholdsMet": per_api_thresholds_met,
        "dataIntegrityMet": True,
        "invalidRecordCount": 0,
        "invalidTrialIds": [],
        "invalidAttemptIds": [],
        "inconsistentSuccessTrialIds": [],
        "emulatorApiSummaries": api_groups,
        "emulatorCandidate": emulator_candidate,
        "decision": "EMULATOR_CANDIDATE" if emulator_candidate else "INCONCLUSIVE",
    }


def _same_mapping(actual: Mapping[str, Any], expected: Mapping[str, Any]) -> bool:
    if set(actual) != set(expected):
        return False
    for key, expected_value in expected.items():
        actual_value = actual[key]
        if not _same_value(actual_value, expected_value):
            return False
    return True


def _same_value(actual: Any, expected: Any) -> bool:
    if type(expected) is bool:
        return type(actual) is bool and actual == expected
    if type(expected) is int:
        return type(actual) is int and actual == expected
    if type(expected) is float:
        return type(actual) in (int, float) and not isinstance(actual, bool) and math.isclose(
            float(actual), expected, rel_tol=1e-9, abs_tol=1e-9
        )
    if expected is None:
        return actual is None
    if isinstance(expected, str):
        return type(actual) is str and actual == expected
    if isinstance(expected, Mapping):
        return isinstance(actual, Mapping) and _same_mapping(actual, expected)
    if isinstance(expected, list):
        return (
            isinstance(actual, list)
            and len(actual) == len(expected)
            and all(_same_value(actual_item, expected_item) for actual_item, expected_item in zip(actual, expected))
        )
    return type(actual) is type(expected) and actual == expected


def _percentile_nearest_rank(values: list[int], percentile: float) -> int | None:
    if not values:
        return None
    rank = max(1, math.ceil(len(values) * percentile))
    return values[rank - 1]


def validate_evidence_file(
    path: Path,
    *,
    expected_trials: int,
    expected_api: int,
    require_api_candidate: bool = False,
) -> None:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise HarnessContractError("evidence JSON is unreadable") from error
    if not isinstance(payload, Mapping):
        raise HarnessContractError("evidence JSON root is not an object")
    validate_evidence(
        payload,
        expected_trials=expected_trials,
        expected_api=expected_api,
        require_api_candidate=require_api_candidate,
    )


def _validate_timing(record: Mapping[str, Any]) -> None:
    trigger = record.get("triggerElapsedRealtimeMs")
    detected = record.get("detectedElapsedRealtimeMs")
    latency = record.get("latencyMs")
    if not all(type(value) is int for value in (trigger, detected, latency)):
        raise HarnessContractError("attempt timing is not integral")
    if trigger < 0 or detected < trigger or latency < 0 or detected - trigger != latency:
        raise HarnessContractError("attempt timing is inconsistent")


def _reject_forbidden_keys(value: Any) -> None:
    if isinstance(value, Mapping):
        for key, nested in value.items():
            if isinstance(key, str) and key.lower() in _FORBIDDEN_KEYS:
                raise HarnessContractError(f"forbidden evidence field: {key}")
            _reject_forbidden_keys(nested)
    elif isinstance(value, list):
        for nested in value:
            _reject_forbidden_keys(nested)


def _main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    ui_parser = subparsers.add_parser("ui")
    ui_parser.add_argument("--input", type=Path, required=True)

    evidence_parser = subparsers.add_parser("evidence")
    evidence_parser.add_argument("--input", type=Path, required=True)
    evidence_parser.add_argument("--expected-trials", type=int, required=True)
    evidence_parser.add_argument("--expected-api", type=int, required=True)
    evidence_parser.add_argument("--require-api-candidate", action="store_true")

    args = parser.parse_args(argv)
    try:
        if args.command == "ui":
            print("{},{}".format(*find_gate_k_button_center(args.input.read_text(encoding="utf-8"))))
        else:
            validate_evidence_file(
                args.input,
                expected_trials=args.expected_trials,
                expected_api=args.expected_api,
                require_api_candidate=args.require_api_candidate,
            )
            print("Gate K evidence contract: PASS (metadata-only runtime artifact)")
    except (HarnessContractError, OSError) as error:
        print(f"Gate K harness contract failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(_main(sys.argv[1:]))
