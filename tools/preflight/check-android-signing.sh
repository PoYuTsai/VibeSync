#!/usr/bin/env bash
# SEC-01／AND-02 非機密簽名守門。
#
#   keystore 模式：驗證既有 upload keystore 與 storePassword、keyAlias 互相
#     匹配（keyPassword 由 Gradle 簽名時驗證），且不是 Android debug 憑證。
#     密碼一律走 env（keytool -storepass:env），不進 argv、不落地、不輸出；
#     只印效期與 SHA-256 fingerprint。alias 是 GitHub secret、Owner 含
#     識別資訊，一律不得輸出。
#   artifact 模式：驗證 release APK/AAB 已簽名、非 debug 憑證，並對帳
#     package 為 com.poyutsai.vibesync。AAB 用 jarsigner -verify 驗簽名項完整性、
#     官方釘版 bundletool 做語意層 package 抽取；負向驗證見
#     tools/android/signing-gate-negative-check.sh。
#
# 任一驗證失敗即非零退出（fail closed）。不得在此腳本印出任何 secret 值。
set -euo pipefail

# ANDROID_EXPECTED_PACKAGE 只供負向驗證腳本注入錯誤期望值，正常路徑用預設
EXPECTED_PACKAGE="${ANDROID_EXPECTED_PACKAGE:-com.poyutsai.vibesync}"

BUNDLETOOL_VERSION="1.18.3"
BUNDLETOOL_SHA256="a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29"

fail() {
  echo "::error::$1"
  exit 1
}

# 官方 bundletool 釘版下載＋sha256 對拍（fail closed）。
# 可用 BUNDLETOOL_JAR 指到既有 jar（一樣要過 sha256）。結果放 $bundletool_jar。
fetch_bundletool() {
  bundletool_jar="${BUNDLETOOL_JAR:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/bundletool-all-$BUNDLETOOL_VERSION.jar}"
  if [ ! -s "$bundletool_jar" ]; then
    curl -fsSL --retry 3 --retry-all-errors -o "$bundletool_jar" \
      "https://github.com/google/bundletool/releases/download/$BUNDLETOOL_VERSION/bundletool-all-$BUNDLETOOL_VERSION.jar" \
      || fail "bundletool 下載失敗"
  fi
  echo "$BUNDLETOOL_SHA256  $bundletool_jar" | sha256sum -c --status - \
    || { rm -f "$bundletool_jar"; fail "bundletool sha256 對拍失敗（fail closed）"; }
}

print_cert_metadata() {
  # 只放行效期與指紋行；alias（GitHub secret）與 Owner 不得輸出。
  # 白名單式放行也避免未來 keytool 輸出格式變動夾帶多餘內容
  grep -E "Valid from:|SHA256:|SHA-256" <<<"$1" | head -8 || true
}

# 指紋正規化：去冒號與空白、轉大寫（公開憑證指紋，非機密，可印出）
normalize_sha256() {
  tr -d ': ' <<<"$1" | tr '[:lower:]' '[:upper:]'
}

# 從 apksigner --print-certs 輸出擷取所有 signer 憑證 SHA-256（行首錨定，
# 每行一個）。接受現行「V2 Signer:」與舊版「Signer #N」兩種前綴。
# 迴歸背景：run 32544433425 的 apksigner 只印 V2 Signer: 前綴，
# 舊解析器只認 Signer #1 導致誤擋。
extract_apk_signer_sha256() {
  sed -nE 's/^(V2 Signer:|Signer #[0-9]+) certificate SHA-256 digest: //p' \
    <<<"$1"
}

# 本專案 release APK 只該有單一 signer：digest 行必須恰好一行才成功並輸出
# 該值；零行（讀不到）、多行（多 signer 或相異 signer）都非零退出（fail
# closed），不得用 head -1 靜默吞掉額外 signer。
extract_single_apk_signer_sha256() {
  local digests count
  digests=$(extract_apk_signer_sha256 "$1")
  count=$(grep -c . <<<"$digests" || true)
  [ "$count" -eq 1 ] || return 1
  printf '%s\n' "$digests"
}

# 正規化並驗證 signer SHA-256：正規化後必須恰為 64 位十六進位，
# 否則非零退出（fail closed），成功時印出 normalized 值
validate_signer_sha256() {
  local normalized
  normalized=$(normalize_sha256 "$1")
  grep -qE '^[0-9A-F]{64}$' <<<"$normalized" || return 1
  echo "$normalized"
}

# 給 parser 回歸測試 source 用：只有「被 source」才跳過主流程。
# 直接執行時一律走完整 gate，任何環境變數都不能關掉正式檢查
# （負向回歸見 check-android-signing-parser-test.sh）。
if [ "${BASH_SOURCE[0]}" != "$0" ]; then
  return 0
fi

mode="${1:-}"
case "$mode" in
  keystore)
    ks="${2:?keystore path required}"
    : "${ANDROID_KEYSTORE_PASSWORD:?need ANDROID_KEYSTORE_PASSWORD env}"
    : "${ANDROID_KEY_ALIAS:?need ANDROID_KEY_ALIAS env}"
    [ -s "$ks" ] || fail "keystore 不存在或為空：$ks"
    if ! out=$(keytool -list -v -keystore "$ks" \
        -storepass:env ANDROID_KEYSTORE_PASSWORD \
        -alias "$ANDROID_KEY_ALIAS" 2>&1); then
      fail "SEC-01 gate：keystore／storePassword／keyAlias 對不上（keytool 驗證失敗）"
    fi
    print_cert_metadata "$out"
    if grep -q "CN=Android Debug" <<<"$out"; then
      fail "SEC-01 gate：keystore 是 Android debug 憑證，禁止用於 release"
    fi
    # Play upload key 效期守門：notAfter 必須晚於 2033-10-22，否則 fail closed
    until_str=$(sed -n 's/.*until: //p' <<<"$out" | head -1)
    [ -n "$until_str" ] || fail "SEC-01 gate：讀不到憑證效期（keytool 輸出格式變動？）"
    until_epoch=$(date -d "$until_str" +%s 2>/dev/null) \
      || fail "SEC-01 gate：憑證效期解析失敗：$until_str"
    # 「晚於 2033-10-22」＝ notAfter 落在 2033-10-23 00:00 之後（當天到期也擋）
    min_epoch=$(date -d "2033-10-23" +%s)
    [ "$until_epoch" -ge "$min_epoch" ] \
      || fail "SEC-01 gate：upload 憑證效期（$until_str）未晚於 2033-10-22"
    # 公開 SHA-256 fingerprint 正規化後輸出，供產物 signer 對帳（非機密）
    ks_sha256=$(sed -n 's/^[[:space:]]*SHA256: //p' <<<"$out" | head -1)
    [ -n "$ks_sha256" ] || fail "SEC-01 gate：讀不到 keystore SHA-256 fingerprint"
    ks_sha256=$(normalize_sha256 "$ks_sha256")
    [ "${#ks_sha256}" -eq 64 ] \
      || fail "SEC-01 gate：keystore fingerprint 正規化後長度異常"
    echo "keystore 憑證 SHA-256（normalized）：$ks_sha256"
    if [ -n "${GITHUB_OUTPUT:-}" ]; then
      echo "keystore_sha256=$ks_sha256" >> "$GITHUB_OUTPUT"
    fi
    echo "SEC-01 keystore gate OK（keyPassword 由 Gradle 簽名步驟驗證）"
    ;;
  artifact)
    artifact="${2:?artifact path required}"
    [ -s "$artifact" ] || fail "找不到 release 產物：$artifact"
    case "$artifact" in
      *.apk)
        sdk_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
        [ -n "$sdk_root" ] || fail "需要 ANDROID_HOME 以取得 apksigner/aapt"
        apksigner=$(find "$sdk_root/build-tools" -name apksigner | sort -V | tail -1)
        aapt=$(find "$sdk_root/build-tools" -name aapt | sort -V | tail -1)
        [ -n "$apksigner" ] && [ -n "$aapt" ] || fail "build-tools 缺 apksigner/aapt"
        certs=$("$apksigner" verify --print-certs "$artifact") \
          || fail "AND-02 gate：APK 簽名驗證失敗"
        signer_sha256_raw=$(extract_single_apk_signer_sha256 "$certs") \
          || fail "AND-02 gate：APK signer digest 必須恰好一個（讀不到、多 signer 或相異 signer 都擋下，fail closed）"
        pkg=$("$aapt" dump badging "$artifact" \
          | sed -n "s/^package: name='\([^']*\)'.*/\1/p")
        [ "$pkg" = "$EXPECTED_PACKAGE" ] \
          || fail "AND-02 gate：package 對帳失敗（得到 ${pkg:-空}，預期 $EXPECTED_PACKAGE）"
        ;;
      *.aab)
        # 簽名項完整性：竄改任何已簽名項會讓 jarsigner 非零退出；
        # 事後塞入的未簽名項不會使 jarsigner 失敗，故另外掃輸出擋下。
        verify_out=$(jarsigner -verify "$artifact" 2>&1) \
          || fail "AND-02 gate：AAB jarsigner 驗證失敗（簽名項被竄改）"
        grep -q "jar verified" <<<"$verify_out" \
          || fail "AND-02 gate：jarsigner 未回報 jar verified"
        if grep -qi "unsigned entries" <<<"$verify_out"; then
          fail "AND-02 gate：AAB 含未簽名項（疑似事後加料）"
        fi
        certs=$(keytool -printcert -jarfile "$artifact") \
          || fail "AND-02 gate：AAB 憑證讀取失敗"
        grep -q "Owner:" <<<"$certs" || fail "AND-02 gate：AAB 未簽名"
        signer_sha256_raw=$(sed -n \
          's/^[[:space:]]*SHA256: //p' <<<"$certs" | head -1)
        # 語意層 package 對帳：官方釘版 bundletool 解 protobuf manifest，
        # 不做位元組 grep 粗檢
        fetch_bundletool
        pkg=$(java -jar "$bundletool_jar" dump manifest --bundle "$artifact" \
          --xpath /manifest/@package | tr -d '[:space:]') \
          || fail "AND-02 gate：bundletool 讀取 AAB manifest 失敗"
        [ "$pkg" = "$EXPECTED_PACKAGE" ] \
          || fail "AND-02 gate：AAB package 對帳失敗（得到 ${pkg:-空}，預期 $EXPECTED_PACKAGE）"
        ;;
      *)
        fail "不支援的產物型別：$artifact"
        ;;
    esac
    print_cert_metadata "$certs"
    if grep -q "Android Debug" <<<"$certs"; then
      fail "AND-02 gate：release 產物使用 debug 憑證，擋下"
    fi
    # 產物 signer SHA-256 對帳 keystore fingerprint（CI 由 keystore gate 的
    # GITHUB_OUTPUT 供值；本機未提供時跳過並明說，不靜默）
    [ -n "$signer_sha256_raw" ] \
      || fail "AND-02 gate：讀不到產物 signer SHA-256（工具輸出格式變動？）"
    signer_sha256=$(validate_signer_sha256 "$signer_sha256_raw") \
      || fail "AND-02 gate：signer SHA-256 正規化後非 64 位十六進位（格式異常，fail closed）"
    if [ -n "${ANDROID_KEYSTORE_SHA256:-}" ]; then
      expected_sha=$(normalize_sha256 "$ANDROID_KEYSTORE_SHA256")
      [ "$signer_sha256" = "$expected_sha" ] \
        || fail "AND-02 gate：產物 signer SHA-256（$signer_sha256）與 keystore fingerprint 不一致"
      echo "signer fingerprint 對帳 OK：$signer_sha256"
    else
      echo "未提供 ANDROID_KEYSTORE_SHA256，跳過 signer fingerprint 對帳（CI 的 distribute／release job 都會提供）"
    fi
    echo "AND-02 artifact gate OK：package=$pkg，憑證非 debug"
    ;;
  *)
    fail "usage: check-android-signing.sh keystore <path> | artifact <apk|aab>"
    ;;
esac
