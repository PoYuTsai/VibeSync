#!/usr/bin/env bash
# 黑箱契約檢查：對 baselines/<name>.ndjson 驗五槽完整、零 error、segments source contract。
# 用法： ./check_contract.sh <name1> [name2 ...]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAIL=0

for name in "$@"; do
  f="$SCRIPT_DIR/baselines/$name.ndjson"
  if [ ! -f "$f" ]; then echo "[$name] MISSING FILE"; FAIL=1; continue; fi

  errors=$(jq -c 'select(.type=="analysis.error")' "$f" | wc -l)
  styles=$(jq -r 'select(.type=="analysis.reply_option") | .style' "$f" | sort -u | paste -sd, -)
  style_count=$(jq -r 'select(.type=="analysis.reply_option") | .style' "$f" | sort -u | wc -l)
  has_decision=$(jq -c 'select(.type=="analysis.decision")' "$f" | wc -l)
  has_reco=$(jq -c 'select(.type=="analysis.recommendation")' "$f" | wc -l)
  # segments source contract：出段就必須有 sourceIndex + sourceMessage
  bad_segments=$(jq -c 'select(.type=="analysis.reply_option") | .segments[]? | select((.sourceIndex == null) or (.sourceMessage == null) or (.sourceMessage == ""))' "$f" | wc -l)

  status=PASS
  [ "$errors" -eq 0 ] || status=FAIL
  [ "$style_count" -eq 5 ] || status=FAIL
  [ "$has_decision" -ge 1 ] || status=FAIL
  [ "$has_reco" -ge 1 ] || status=FAIL
  [ "$bad_segments" -eq 0 ] || status=FAIL
  [ "$status" = PASS ] || FAIL=1

  echo "[$name] $status — errors=$errors styles($style_count)=$styles decision=$has_decision reco=$has_reco badSegments=$bad_segments"
done

exit $FAIL
