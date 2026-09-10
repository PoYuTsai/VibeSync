#!/usr/bin/env bash
# 把 out/ 的 24 張圖縮成 App 縮圖尺寸（約 260×180，cover 裁切）並拼成 8 欄×3 列的對照表。
# 每列一位角色；每欄依序 coffee V1/V2、street V1/V2、desk V1/V2、dinner V1/V2。
set -euo pipefail
cd "$(dirname "$0")/out"
mkdir -p thumbs
i=0
for f in $(ls [0-9][0-9]_*.{jpg,png} 2>/dev/null | sort); do
  ffmpeg -loglevel error -y -i "$f" -vf "scale=260:180:force_original_aspect_ratio=increase,crop=260:180" "thumbs/$(printf %02d $i).png"
  i=$((i+1))
done
ffmpeg -loglevel error -y -framerate 1 -i thumbs/%02d.png -vf "tile=8x3:padding=6:margin=6:color=white" -frames:v 1 contact_sheet.png
echo "contact_sheet.png ($i thumbs)"
