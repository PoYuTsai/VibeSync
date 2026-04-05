#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIST_FILE="$SCRIPT_DIR/flutter_ci_smoke_tests.txt"

if [[ ! -f "$LIST_FILE" ]]; then
  echo "Smoke test list not found: $LIST_FILE" >&2
  exit 1
fi

TEST_COUNT=0

while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
  test_file="${raw_line%%#*}"
  test_file="$(printf '%s' "$test_file" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

  if [[ -z "$test_file" ]]; then
    continue
  fi

  TEST_COUNT=$((TEST_COUNT + 1))
  echo "::group::flutter test $test_file"
  flutter test "$test_file"
  echo "::endgroup::"
done < "$LIST_FILE"

if [[ "$TEST_COUNT" -eq 0 ]]; then
  echo "No smoke tests configured." >&2
  exit 1
fi

echo "Flutter CI smoke suite completed successfully."
