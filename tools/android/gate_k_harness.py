#!/usr/bin/env python3
"""Pure parser and validator seams for the Gate K emulator runner."""

from __future__ import annotations

import argparse
import json
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

    bounds = matches[0].get("bounds", "")
    parsed = _BOUNDS_RE.fullmatch(bounds)
    if parsed is None:
        raise HarnessContractError("Gate K attempt button has no usable bounds")
    left, top, right, bottom = (int(value) for value in parsed.groups())
    if right <= left or bottom <= top:
        raise HarnessContractError("Gate K attempt button bounds are empty")
    return ((left + right) // 2, (top + bottom) // 2)


def validate_evidence(
    payload: Mapping[str, Any],
    *,
    expected_trials: int,
    expected_api: int,
    require_api_candidate: bool = False,
) -> None:
    """Fail closed on schema, origin, device, timing, and privacy violations."""

    if expected_trials <= 0 or expected_api < 34:
        raise HarnessContractError("invalid validator expectations")
    _reject_forbidden_keys(payload)
    if payload.get("schemaVersion") != 1:
        raise HarnessContractError("unsupported evidence schema")
    records = payload.get("trialRecords")
    summary = payload.get("summary")
    if not isinstance(records, list) or not isinstance(summary, Mapping):
        raise HarnessContractError("evidence root shape is invalid")
    if len(records) != expected_trials or summary.get("totalTrials") != expected_trials:
        raise HarnessContractError("trial count does not match bounded run")

    seen_attempts: set[str] = set()
    for record in records:
        if not isinstance(record, Mapping):
            raise HarnessContractError("trial record is not an object")
        if not _REQUIRED_RECORD_FIELDS.issubset(record):
            raise HarnessContractError("trial record schema is incomplete")
        if record.get("origin") != "RUNTIME":
            raise HarnessContractError("synthetic trial origin is not evidence")
        if record.get("deviceClass") != "EMULATOR":
            raise HarnessContractError("trial is not conservatively classified as emulator")
        if record.get("apiLevel") != expected_api:
            raise HarnessContractError("trial API level does not match runner matrix")
        attempt_id = record.get("attemptId")
        session_id = record.get("sessionId")
        if not isinstance(attempt_id, str) or not attempt_id or attempt_id in seen_attempts:
            raise HarnessContractError("attempt IDs must be non-empty and unique")
        if not isinstance(session_id, str) or not session_id:
            raise HarnessContractError("session ID is missing")
        seen_attempts.add(attempt_id)
        descriptor = record.get("deviceDescriptor")
        if not isinstance(descriptor, str) or not descriptor:
            raise HarnessContractError("raw device descriptor is missing")
        for field in ("manufacturer=", "brand=", "model=", "product=", "fingerprint=", "api="):
            if field not in descriptor:
                raise HarnessContractError("raw device descriptor is incomplete")
        if f"api={expected_api}" not in descriptor:
            raise HarnessContractError("descriptor API does not match runner matrix")
        if record.get("failureReason") not in _BOUNDED_FAILURES:
            raise HarnessContractError("failure reason is outside bounded enum")
        _validate_timing(record)

    api_summaries = summary.get("emulatorApiSummaries")
    if not isinstance(api_summaries, Mapping):
        raise HarnessContractError("per-API summary is missing")
    group = api_summaries.get(str(expected_api))
    if not isinstance(group, Mapping) or group.get("totalTrials") != expected_trials:
        raise HarnessContractError("per-API trial count is missing")
    if require_api_candidate and not (
        group.get("successRateMet") is True and group.get("latencyMet") is True
    ):
        raise HarnessContractError("per-API emulator candidate thresholds are not met")


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
