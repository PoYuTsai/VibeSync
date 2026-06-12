#!/usr/bin/env bash
# 盲測表產生器：3 case × 舊/新 去識別（甲/乙隨機）＋ChatGPT 欄留白。
# 產出 blind/blind_sheet.md（給 Eric 看）與 blind/answer_key.md（Eric 評完才開）。
# 用法： ./gen_blind_sheet.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$SCRIPT_DIR/blind"
mkdir -p "$OUT_DIR"

SHEET="$OUT_DIR/blind_sheet.md"
KEY="$OUT_DIR/answer_key.md"

# case 名 → (舊 baseline, 新 run, ChatGPT paste 檔)
CASES=(
  "case1 承瑋R局（升溫/熱絡） case1_chengwei_run1 new_case1_run1 chatgpt_paste/case1.txt"
  "case2 肉伊（陌生早期） case2_rouyi_run1 new_case2_rouyi_run1 chatgpt_paste/case2.txt"
  "case3 Ashley試探球（見面後） case3_ashley_run1 new_case3_run1 chatgpt_paste/case3.txt"
)

extract() { # $1 = ndjson path → 人眼可讀輸出
  local f="$1"
  echo "**最推薦**"
  jq -r 'select(.type=="analysis.recommendation") | "\(.message)\n\n> 理由：\(.reason)"' "$f"
  echo
  echo "**五種風格**"
  jq -r 'select(.type=="analysis.reply_option") | "- \(.style)：\(.message | gsub("\n"; " ／ "))"' "$f"
}

{
  echo "# Voice 盲測表（$(date +%Y-%m-%d)）"
  echo
  echo "> 每題甲/乙為舊/新 prompt 之一（已隨機），ChatGPT 欄請 Eric 拿 chatgpt_paste/ 同輸入餵 free ChatGPT 貼回。"
  echo "> 評法：每題對「甲 vs ChatGPT」「乙 vs ChatGPT」「甲 vs 乙」憑肉眼主觀判：哦！還不錯蠻高手的、很幽默。"
  echo "> 評完才開 answer_key.md。"
  echo
} > "$SHEET"

{
  echo "# 答案鑰匙（評完才開）"
  echo
} > "$KEY"

for spec in "${CASES[@]}"; do
  set -- $spec
  cid="$1"; label="$2"; old="$3"; new="$4"; paste="$5"

  if [ "$(shuf -i 0-1 -n 1)" -eq 0 ]; then
    first="$old"; second="$new"; keyline="甲=舊（$old）　乙=新（$new）"
  else
    first="$new"; second="$old"; keyline="甲=新（$new）　乙=舊（$old）"
  fi

  {
    echo "## $cid　$label"
    echo
    echo "輸入：\`$paste\`（同份餵 ChatGPT）"
    echo
    echo "### 版本甲"
    echo
    extract "$SCRIPT_DIR/baselines/$first.ndjson"
    echo
    echo "### 版本乙"
    echo
    extract "$SCRIPT_DIR/baselines/$second.ndjson"
    echo
    echo "### ChatGPT（Eric 貼回）"
    echo
    echo "（待貼）"
    echo
    echo "---"
    echo
  } >> "$SHEET"

  echo "- $cid：$keyline" >> "$KEY"
done

echo "sheet: $SHEET"
echo "key:   $KEY（Eric 評完才開）"
