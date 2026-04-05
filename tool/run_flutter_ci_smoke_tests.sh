#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIST_FILE="$SCRIPT_DIR/flutter_ci_smoke_tests.txt"

if [[ ! -f "$LIST_FILE" ]]; then
  echo "Smoke test list not found: $LIST_FILE" >&2
  exit 1
fi

mapfile -t TEST_FILES < <(grep -v '^\s*#' "$LIST_FILE" | grep -v '^\s*$')

if [[ ${#TEST_FILES[@]} -eq 0 ]]; then
  echo "No smoke tests configured." >&2
  exit 1
fi

echo "Running ${#TEST_FILES[@]} Flutter smoke tests..."

for test_file in "${TEST_FILES[@]}"; do
  echo "::group::flutter test $test_file"
  flutter test "$test_file"
  echo "::endgroup::"
done

echo "Flutter CI smoke suite completed successfully."
