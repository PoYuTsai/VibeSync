#!/usr/bin/env bash
# 逐單元對照多份 run_benchmark 結果（side 準確率＋layout 修復數）。
# 用法: ./compare_runs.sh <runA.json> <runB.json> [runC.json ...]
set -euo pipefail

[ $# -ge 2 ] || { echo "用法: $0 <runA.json> <runB.json> [...]" >&2; exit 1; }

header="id"
for f in "$@"; do
  header="$header\t$(basename "$f" .json | sed 's/^2026-//')"
done
echo -e "$header（sideOK/aligned·layoutAdj）"

ids=$(jq -r '.results[].id' "$1")
for id in $ids; do
  row="$id"
  for f in "$@"; do
    cell=$(jq -r --arg id "$id" '.results[] | select(.id==$id) |
      "\(.sideCorrect)/\(.alignedCount)·\(.telemetry.layoutFirstAdjustedCount // 0)"' "$f")
    row="$row\t${cell:-—}"
  done
  echo -e "$row"
done

echo "---"
for f in "$@"; do
  jq -r --arg n "$(basename "$f" .json)" \
    '"\($n): side \(.overall.sideAccuracy*1000|round/10)% recall \(.overall.messageRecall*1000|round/10)% precision \(.overall.messagePrecision*1000|round/10)% exact \(.overall.exactTextRate*1000|round/10)% CER \(.overall.cer*1000|round/10)‰ units \(.overall.unitsScored)"' "$f"
done
