#!/usr/bin/env bash
# 修字 round 2 盲測表產生器：只 case1+case2（修字兩題），舊 vs 修字版 甲/乙隨機。
# ChatGPT 欄沿用第一輪逐字稿（同輸入、GPT 為固定參照；blind/gpt_round1_case{1,2}.md）。
# 產出：
#   blind/fix_round2_sheet.md        （Eric 版：甲/乙匿名＋ChatGPT 具名）
#   blind/fix_round2_key.md          （甲/乙 → 舊/修字 對應，評完才開）
#   blind/fix_round2_bruce_sheet.md  （Bruce 版：A/B/C 全匿名，只取最推薦句）
#   blind/fix_round2_bruce_key.md    （A/B/C → 舊/修字/ChatGPT 對應，評完才開）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$SCRIPT_DIR/blind"

SHEET="$OUT_DIR/fix_round2_sheet.md"
KEY="$OUT_DIR/fix_round2_key.md"
BSHEET="$OUT_DIR/fix_round2_bruce_sheet.md"
BKEY="$OUT_DIR/fix_round2_bruce_key.md"

# case 名 → (舊 baseline, 修字 run, ChatGPT round1 逐字檔, 輸入 paste 檔)
CASES=(
  "case1 承瑋R局（升溫/熱絡） case1_chengwei_run1 fix_case1_run1 gpt_round1_case1.md chatgpt_paste/case1.txt"
  "case2 肉伊（陌生早期） case2_rouyi_run1 fix_case2_rouyi_run1 gpt_round1_case2.md chatgpt_paste/case2.txt"
)

extract() { # $1 = ndjson path → 人眼可讀輸出
  local f="$1"
  echo "**最推薦**"
  jq -r 'select(.type=="analysis.recommendation") | "\(.message)\n\n> 理由：\(.reason)"' "$f"
  echo
  echo "**五種風格**"
  jq -r 'select(.type=="analysis.reply_option") | "- \(.style)：\(.message | gsub("\n"; " ／ "))"' "$f"
}

top_pick() { # $1 = ndjson path → 只取最推薦句（Bruce 版用）
  jq -r 'select(.type=="analysis.recommendation") | .message' "$1" | sed 's/^/> /'
}

gpt_top() { # $1 = gpt round1 逐字檔 → 取「我最推薦/我會建議」後的第一個引用塊
  awk '/^>/{print; inq=1; next} inq{exit}' "$SCRIPT_DIR/blind/$1"
}

bruce_context() { # $1 = round1 bruce_sheet 的題號 → 情境＋她最後說 區塊
  awk -v t="## 第 $1 題" '$0 ~ t{on=1; next} on && /^\*\*A\*\*/{exit} on{print}' \
    "$SCRIPT_DIR/blind/bruce_sheet.md"
}

{
  echo "# Voice 修字盲測表 round 2（$(date +%Y-%m-%d)）"
  echo
  echo "> 只重測修字兩題（case1 pushy guard／case2 框架）。每題甲/乙為 舊/修字 prompt 之一（已隨機）。"
  echo "> ChatGPT 欄沿用第一輪逐字稿（同輸入，GPT 為固定參照；兩位評過第一輪可能認得出，評 新vs舊 時請以甲/乙為主）。"
  echo "> 評法同第一輪：肉眼主觀「哦！還不錯蠻高手的、很幽默」。評完才開 fix_round2_key.md。"
  echo
} > "$SHEET"

{
  echo "# Round 2 答案鑰匙（評完才開）"
  echo
} > "$KEY"

{
  echo "# 回覆品味盲測 round 2（Bruce 版）"
  echo
  echo "> 兩段真實聊天情境（跟上次同題，回覆建議有更新）。每題 A/B/C 三個回覆建議（來源打亂）。"
  echo "> 請憑直覺評：**哪個你會直接拿去用？哪個最像高手回的、最自然不油？**"
  echo "> 每題給一個排名（例如 \`B > A > C\`），想補一句理由更好。第一直覺最準。"
  echo
  echo "---"
  echo
} > "$BSHEET"

{
  echo "# Bruce 版 round 2 對應表（Bruce 評完才開）"
  echo
  echo "| 題 | A | B | C |"
  echo "|----|---|---|---|"
} > "$BKEY"

n=0
for spec in "${CASES[@]}"; do
  set -- $spec
  cid="$1"; label="$2"; old="$3"; new="$4"; gpt="$5"; paste="$6"
  n=$((n+1))

  # Eric 版：甲/乙 二選一洗牌
  if [ "$(shuf -i 0-1 -n 1)" -eq 0 ]; then
    first="$old"; second="$new"; keyline="甲=舊（$old）　乙=修字（$new）"
  else
    first="$new"; second="$old"; keyline="甲=修字（$new）　乙=舊（$old）"
  fi

  {
    echo "## $cid　$label"
    echo
    echo "輸入：\`$paste\`（同第一輪）"
    echo
    echo "### 版本甲"
    echo
    extract "$SCRIPT_DIR/baselines/$first.ndjson"
    echo
    echo "### 版本乙"
    echo
    extract "$SCRIPT_DIR/baselines/$second.ndjson"
    echo
    echo "### ChatGPT（第一輪逐字稿）"
    echo
    cat "$SCRIPT_DIR/blind/$gpt"
    echo
    echo "---"
    echo
  } >> "$SHEET"

  echo "- $cid：$keyline" >> "$KEY"

  # Bruce 版：A/B/C 三方全洗牌（舊/修字/GPT 最推薦句）
  order=$(shuf -e OLD NEW GPT | tr '\n' ' ')
  {
    echo "## 第 $n 題"
    bruce_context "$n"
    slot=A
    for who in $order; do
      echo "**$slot**"
      case "$who" in
        OLD) top_pick "$SCRIPT_DIR/baselines/$old.ndjson" ;;
        NEW) top_pick "$SCRIPT_DIR/baselines/$new.ndjson" ;;
        GPT) gpt_top "$gpt" ;;
      esac
      echo
      slot=$(echo "$slot" | tr 'AB' 'BC')
    done
    echo "---"
    echo
  } >> "$BSHEET"

  bk=$(echo "$order" | sed 's/OLD/舊/; s/NEW/修字/; s/GPT/ChatGPT/')
  set -- $bk
  echo "| 第 $n 題（$cid） | $1 | $2 | $3 |" >> "$BKEY"
done

echo "sheet:       $SHEET"
echo "key:         $KEY（Eric 評完才開）"
echo "bruce sheet: $BSHEET"
echo "bruce key:   $BKEY（Bruce 評完才開）"
