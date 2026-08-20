#!/usr/bin/env bash
# P1-3 可執行負向驗證：拿真簽好的 AAB 證明 AND-02 artifact gate 會擋
#   1. 竄改已簽名項後的 AAB → gate 必須非零退出（jarsigner 完整性）
#   2. 期望 package 給錯 → gate 必須非零退出（bundletool 語意對帳）
# 用法：signing-gate-negative-check.sh <signed-aab>
set -euo pipefail

aab="${1:?usage: signing-gate-negative-check.sh <signed-aab>}"
[ -s "$aab" ] || { echo "::error::找不到 AAB：$aab"; exit 1; }
gate="$(cd "$(dirname "$0")/../preflight" && pwd)/check-android-signing.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

expect_gate_fail() {
  local label="$1"
  shift
  if "$@" >"$work/gate.log" 2>&1; then
    cat "$work/gate.log"
    echo "::error::負向驗證失敗：$label 應被 gate 擋下卻通過了"
    exit 1
  fi
  echo "負向驗證 OK：$label 被正確擋下"
}

# 1) 竄改已簽名項：抽出 manifest、附加一個 byte、塞回同名 zip entry
tampered="$work/tampered.aab"
cp "$aab" "$tampered"
mkdir -p "$work/base/manifest"
unzip -p "$aab" base/manifest/AndroidManifest.xml \
  > "$work/base/manifest/AndroidManifest.xml"
printf '\0' >> "$work/base/manifest/AndroidManifest.xml"
(cd "$work" && zip -q "$tampered" base/manifest/AndroidManifest.xml)
expect_gate_fail "竄改後的 AAB" "$gate" artifact "$tampered"

# 2) 錯誤的期望 package（走到 bundletool 語意抽取才會擋）
expect_gate_fail "錯誤 expected package" \
  env ANDROID_EXPECTED_PACKAGE=com.wrong.package "$gate" artifact "$aab"

echo "signing gate 負向驗證全部通過：tampered 與 wrong-package 都會被擋"
