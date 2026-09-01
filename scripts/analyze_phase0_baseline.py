#!/usr/bin/env python3
"""Aggregate Analyze Phase 0 observability events into a contradiction-rate baseline.

The Edge function logs one `stream_phase0_observability` event per finished
stream run (see supabase/functions/analyze-chat/phase0_observability.ts). The
event is content-free by construction, so this script only ever handles enums,
counts and indices.

Two input modes:

  # Pull from production Edge logs via the Supabase Management API.
  python3 scripts/analyze_phase0_baseline.py --project-ref <ref> --days 7

  # Parse a file of already exported event_message rows (one event per block).
  python3 scripts/analyze_phase0_baseline.py --from-file events.txt

The PAT is read from ~/.supabase/access-token (the CLI login token). The logs
endpoint silently returns zero rows when the requested window is too wide, so
the script always asks in 6-hour slices.

Stdlib only; run it from WSL.
"""

from __future__ import annotations

import argparse
import collections
import datetime as dt
import json
import pathlib
import re
import sys
import urllib.parse
import urllib.request

EVENT = "stream_phase0_observability"
LOGS_ENDPOINT = "https://api.supabase.com/v1/projects/{ref}/analytics/endpoints/logs.all"
SLICE = dt.timedelta(hours=6)
STYLES = ("extend", "resonate", "tease", "humor", "coldRead")


def read_pat() -> str:
    path = pathlib.Path.home() / ".supabase" / "access-token"
    try:
        return path.read_text().strip()
    except OSError as error:
        sys.exit(f"cannot read Supabase PAT at {path}: {error}")


def fetch_messages(ref: str, days: int) -> list[str]:
    pat = read_pat()
    end = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
    start = end - dt.timedelta(days=days)
    sql = (
        "select timestamp, event_message from function_logs "
        f"where event_message like '%{EVENT}%' order by timestamp limit 1000"
    )
    messages: list[str] = []
    cursor = start
    while cursor < end:
        upper = min(cursor + SLICE, end)
        query = urllib.parse.urlencode(
            {
                "sql": sql,
                "iso_timestamp_start": cursor.strftime("%Y-%m-%dT%H:%M:%SZ"),
                "iso_timestamp_end": upper.strftime("%Y-%m-%dT%H:%M:%SZ"),
            }
        )
        request = urllib.request.Request(
            f"{LOGS_ENDPOINT.format(ref=ref)}?{query}",
            headers={"Authorization": f"Bearer {pat}", "User-Agent": "curl/8.0"},
        )
        with urllib.request.urlopen(request, timeout=60) as response:
            payload = json.load(response)
        if payload.get("error"):
            sys.exit(f"logs query failed for {cursor:%Y-%m-%dT%H:%M}Z: {payload['error']}")
        rows = payload.get("result") or []
        if len(rows) >= 1000:
            print(f"warning: slice {cursor:%Y-%m-%dT%H:%M}Z hit the 1000 row cap", file=sys.stderr)
        messages.extend(row["event_message"] for row in rows)
        cursor = upper
    return messages


# Deno prints console.log metadata with util.inspect formatting, not JSON:
# unquoted identifier keys, double-quoted strings, `[ 1, 2 ]` arrays. The
# telemetry object holds only enums, numbers, booleans, arrays and nested
# records, so quoting the bare keys is enough to make it valid JSON.
_BARE_KEY = re.compile(r'(?<=[{,\s])([A-Za-z_][A-Za-z0-9_]*)(?=:)')


def parse_event(message: str) -> dict | None:
    marker = message.find(EVENT)
    if marker < 0:
        return None
    body = message[marker + len(EVENT):].strip()
    if not body.startswith("{"):
        return None
    depth = 0
    end = None
    in_string = False
    escaped = False
    for index, char in enumerate(body):
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                end = index + 1
                break
    if end is None:
        return None
    literal = body[:end]
    # Only quote keys outside of string literals.
    pieces = re.split(r'("(?:[^"\\]|\\.)*")', literal)
    for index in range(0, len(pieces), 2):
        pieces[index] = _BARE_KEY.sub(r'"\1"', pieces[index])
    try:
        return json.loads("".join(pieces))
    except json.JSONDecodeError:
        return None


def rate(numerator: int, denominator: int) -> str:
    if denominator == 0:
        return "n/a"
    return f"{numerator}/{denominator} ({100.0 * numerator / denominator:.1f}%)"


def status_of(value) -> str:
    if isinstance(value, dict):
        return str(value.get("status", "unknown"))
    return "unknown" if value == "unknown" else "observed"


def summarize(events: list[dict]) -> str:
    total = len(events)
    lines = [f"# Analyze Phase 0 baseline", "", f"events: {total}", ""]
    if total == 0:
        lines.append("no `stream_phase0_observability` events in the requested window.")
        return "\n".join(lines)

    lines += ["## field observability", "", "| field | observed | unknown |", "|---|---|---|"]
    scalar_fields = [
        "decisionSchema", "action", "messageDecision", "replyMode", "selectedStyle",
        "selectedBallCount", "betaRiskFlags", "solutionModeAllowed",
        "actionMismatch", "ballMismatch", "noSendConflict",
        "candidateCount", "legacyGiveUpBanner", "legacyGiveUpConflict", "coachActionType",
    ]
    record_fields = [
        "meaningfulBallCoverage", "questionCounts", "topicJump", "semanticDistance",
        "solutionMode", "fiveCardSourceDivergence",
    ]
    for field in scalar_fields + record_fields:
        observed = sum(1 for event in events if status_of(event.get(field, "unknown")) == "observed")
        lines.append(f"| {field} | {observed} | {total - observed} |")

    def observed_bool(field: str, key: str | None = None) -> tuple[int, int]:
        hits = observed = 0
        for event in events:
            value = event.get(field, "unknown")
            if key is not None:
                value = value.get(key, "unknown") if isinstance(value, dict) else "unknown"
            if isinstance(value, bool):
                observed += 1
                hits += int(value)
        return hits, observed

    lines += ["", "## contradiction rates (among observed)", ""]
    for label, field, key, invert in [
        ("v1 give-up banner shown while reply cards emitted", "legacyGiveUpConflict", None, False),
        ("v1 give-up banner shown at all", "legacyGiveUpBanner", None, False),
        ("no-send decision but reply candidates emitted", "noSendConflict", None, False),
        ("variant action differs from decision action", "actionMismatch", None, False),
        ("variant balls differ from selected balls", "ballMismatch", None, False),
        ("some style misses a meaningful ball", "meaningfulBallCoverage", "allVariantsCoverMeaningful", True),
        ("five cards cite different sources", "fiveCardSourceDivergence", "allMatch", True),
        ("new topics exceed budget", "topicJump", "exceedsBudget", False),
        ("solution mode used while disallowed", "solutionMode", "conflict", False),
    ]:
        hits, observed = observed_bool(field, key)
        if invert:
            hits = observed - hits
        lines.append(f"- {label}: {rate(hits, observed)}")

    lines += ["", "## question density (max question count per run)", ""]
    histogram: collections.Counter[int] = collections.Counter()
    per_style: dict[str, list[int]] = collections.defaultdict(list)
    for event in events:
        counts = event.get("questionCounts")
        if not isinstance(counts, dict) or counts.get("status") != "observed":
            continue
        histogram[int(counts.get("maxQuestionCount", 0))] += 1
        for style, value in (counts.get("byStyle") or {}).items():
            if isinstance(value, (int, float)):
                per_style[style].append(int(value))
    for bucket in sorted(histogram):
        lines.append(f"- max {bucket} question(s): {histogram[bucket]}")
    for style in STYLES:
        values = per_style.get(style)
        if values:
            lines.append(f"- {style}: mean {sum(values) / len(values):.2f} over {len(values)} runs")

    lines += ["", "## decisions and flags", ""]
    for field in ("messageDecision", "action", "replyMode", "selectedStyle", "coachActionType", "candidateCount"):
        counter = collections.Counter(str(event.get(field, "unknown")) for event in events)
        lines.append(f"- {field}: " + ", ".join(f"{key}={value}" for key, value in counter.most_common()))
    flags: collections.Counter[str] = collections.Counter()
    for event in events:
        value = event.get("betaRiskFlags")
        if isinstance(value, list):
            flags.update(str(flag) for flag in value)
    lines.append("- betaRiskFlags: " + (", ".join(f"{key}={value}" for key, value in flags.most_common()) or "none observed"))
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--project-ref", help="Supabase project ref to query")
    source.add_argument("--from-file", type=pathlib.Path, help="file containing exported event_message text")
    parser.add_argument("--days", type=int, default=7, help="lookback window in days (default 7)")
    parser.add_argument("--json", action="store_true", help="print parsed events as JSON lines instead of the report")
    args = parser.parse_args()

    if args.from_file:
        raw = args.from_file.read_text()
        messages = [f"{EVENT}{chunk}" for chunk in raw.split(EVENT)[1:]]
    else:
        messages = fetch_messages(args.project_ref, args.days)

    events = []
    unparsed = 0
    for message in messages:
        event = parse_event(message)
        if event is None:
            unparsed += 1
        else:
            events.append(event)
    if args.json:
        for event in events:
            print(json.dumps(event, ensure_ascii=False))
        return
    print(summarize(events))
    if unparsed:
        print(f"\nwarning: {unparsed} event(s) could not be parsed", file=sys.stderr)


if __name__ == "__main__":
    main()
