#!/usr/bin/env bash
# voice-benchmark baseline runner — 黑箱 curl 直打 prod analyze-chat stream。
# 手法沿 golden_v2 / P0 stream 復測：.env.golden 測試帳號 password grant 換 token，
# 收完整 ndjson 留檔 baselines/，terminal 只印事件摘要（不洗版）。
#
# 用法： ./run_baseline.sh <case_payload.json> <output_name>
# 例：   ./run_baseline.sh cases/case2_min_first_night.json case2_run1
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PAYLOAD_FILE="$SCRIPT_DIR/$1"
OUT_FILE="$SCRIPT_DIR/baselines/$2.ndjson"

[ -f "$PAYLOAD_FILE" ] || { echo "payload not found: $PAYLOAD_FILE" >&2; exit 1; }

# 憑證：測試帳號在 tools/ocr-golden/.env.golden、anon key 在 repo root .env.local
set -a
. "$REPO_ROOT/tools/ocr-golden/.env.golden"
. "$REPO_ROOT/.env.local"
set +a

SUPABASE_URL="${SUPABASE_URL:-https://fcmwrmwdoqiqdnbisdpg.supabase.co}"

ACCESS_TOKEN=$(curl -sS -X POST \
  "$SUPABASE_URL/auth/v1/token?grant_type=password" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASSWORD\"}" | jq -r '.access_token')

[ -n "$ACCESS_TOKEN" ] && [ "$ACCESS_TOKEN" != "null" ] || { echo "password grant failed" >&2; exit 1; }

curl -sS -N -X POST "$SUPABASE_URL/functions/v1/analyze-chat" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  --max-time 180 \
  -d @"$PAYLOAD_FILE" > "$OUT_FILE"

echo "saved: $OUT_FILE ($(wc -l < "$OUT_FILE") events)"
echo "--- event summary ---"
jq -r '.type' "$OUT_FILE" | sort | uniq -c
echo "--- styles seen ---"
jq -r 'select(.type=="analysis.reply_option") | .style // .replyStyle // empty' "$OUT_FILE" | sort | uniq -c || true
echo "--- errors (if any) ---"
jq -c 'select(.type=="analysis.error")' "$OUT_FILE" || true
