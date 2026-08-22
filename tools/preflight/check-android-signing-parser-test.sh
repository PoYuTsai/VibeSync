#!/usr/bin/env bash
# AND-02 signer-digest parser 回歸測試（run 32544433425 迴歸）：
# 只認 Signer #1 的舊解析器擋掉了現行 apksigner 的 V2 Signer: 輸出。
# 這裡以純字串 fixture 驗證擷取與正規化行為，不需要 SDK 或真產物；
# 對帳不一致（wrong fingerprint）的 live fail-closed 證據由
# tools/android/signing-gate-negative-check.sh 提供。
set -euo pipefail

# gate 腳本偵測「被 source」就只載入函式；直接執行一律走完整檢查
gate="$(cd "$(dirname "$0")" && pwd)/check-android-signing.sh"
source "$gate"

expected="1468e4a3a63f403d524285a6de07dbd040d38d09090b2736f2877761fc8b32ee"
expected_norm="1468E4A3A63F403D524285A6DE07DBD040D38D09090B2736F2877761FC8B32EE"
pass=0

check() {
  local label="$1" got="$2" want="$3"
  if [ "$got" != "$want" ]; then
    echo "::error::parser 回歸測試失敗：$label（得到「$got」，預期「$want」）"
    exit 1
  fi
  pass=$((pass + 1))
  echo "OK：$label"
}

# 1) 現行輸出（run 32544433425 實際格式）
current_output="Verifies
Verified using v2 scheme (APK Signature Scheme v2): true
V2 Signer: certificate DN: CN=VibeSync
V2 Signer: certificate SHA-256 digest: $expected
V2 Signer: certificate SHA-1 digest: deadbeef"
check "現行 V2 Signer: 輸出" \
  "$(extract_apk_signer_sha256 "$current_output")" "$expected"

# 2) 舊版輸出（Signer #N）
legacy_output="Signer #1 certificate DN: CN=VibeSync
Signer #1 certificate SHA-256 digest: $expected
Signer #1 certificate SHA-1 digest: deadbeef"
check "舊版 Signer #1 輸出" \
  "$(extract_apk_signer_sha256 "$legacy_output")" "$expected"
check "舊版 Signer #2 輸出" \
  "$(extract_apk_signer_sha256 "Signer #2 certificate SHA-256 digest: $expected")" \
  "$expected"

# 3) 缺 digest 行 → 空字串（主流程會 fail closed）
check "缺 digest 行" \
  "$(extract_apk_signer_sha256 "Verified using v2 scheme: true")" ""

# 4) 行首錨定：前綴不在行首或被加料不得匹配
check "非行首前綴不匹配" \
  "$(extract_apk_signer_sha256 "  V2 Signer: certificate SHA-256 digest: $expected")" ""
check "加料前綴不匹配" \
  "$(extract_apk_signer_sha256 "Fake Signer #1 certificate SHA-256 digest: $expected")" ""

# 5) 正規化：小寫、冒號分隔都收斂成 64 位大寫 hex
check "正規化小寫輸入" \
  "$(validate_signer_sha256 "$expected")" "$expected_norm"
colon_form=$(sed 's/../&:/g;s/:$//' <<<"$expected")
check "正規化冒號分隔輸入" \
  "$(validate_signer_sha256 "$colon_form")" "$expected_norm"

# 6) 畸形 digest → validate 必須非零退出（fail closed）
for bad in "1468e4" "${expected}ff" "${expected%??}zz" ""; do
  if validate_signer_sha256 "$bad" >/dev/null 2>&1; then
    echo "::error::parser 回歸測試失敗：畸形 digest「$bad」應被擋下卻通過了"
    exit 1
  fi
  pass=$((pass + 1))
  echo "OK：畸形 digest 被擋下（${bad:-空字串}）"
done

# 7) 唯一 signer 守門：恰好一個 digest 才成功；零個、相異雙 signer、
#    同 digest 重複行（多 signer）都必須非零退出（fail closed）
other="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
check "唯一 signer 成功輸出" \
  "$(extract_single_apk_signer_sha256 "$current_output")" "$expected"
dual_diff="Signer #1 certificate SHA-256 digest: $expected
Signer #2 certificate SHA-256 digest: $other"
dual_same="V2 Signer: certificate SHA-256 digest: $expected
Signer #1 certificate SHA-256 digest: $expected"
for multi in "$dual_diff" "$dual_same" "no digest here"; do
  if extract_single_apk_signer_sha256 "$multi" >/dev/null 2>&1; then
    echo "::error::parser 回歸測試失敗：非唯一 signer 輸出應被擋下卻通過了"
    exit 1
  fi
  pass=$((pass + 1))
done
echo "OK：零個／雙 signer／重複 digest 都被擋下"

# 8) bypass 負向回歸：直接執行 gate 時，環境變數不能讓它跳過檢查；
#    即使帶舊 bypass 變數且 artifact 不存在，也必須非零退出
if CHECK_ANDROID_SIGNING_LIB_ONLY=1 "$gate" artifact /nonexistent/app.apk \
    >/dev/null 2>&1; then
  echo "::error::parser 回歸測試失敗：直接執行 gate 竟被環境變數 bypass 成功退出"
  exit 1
fi
pass=$((pass + 1))
echo "OK：直接執行 gate 無法被環境變數 bypass"

echo "AND-02 parser 回歸測試全部通過（$pass 項）"
