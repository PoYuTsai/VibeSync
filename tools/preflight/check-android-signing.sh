#!/usr/bin/env bash
# SEC-01／AND-02 非機密簽名守門。
#
#   keystore 模式：驗證既有 upload keystore 與 storePassword、keyAlias 互相
#     匹配（keyPassword 由 Gradle 簽名時驗證），且不是 Android debug 憑證。
#     密碼一律走 env（keytool -storepass:env），不進 argv、不落地、不輸出；
#     只印 alias、Owner、效期與 SHA256 fingerprint 等中繼資料。
#   artifact 模式：驗證 release APK/AAB 已簽名、非 debug 憑證，並對帳
#     package 為 com.vibesync.app。AAB 用 jarsigner -verify 驗簽名項完整性、
#     官方釘版 bundletool 做語意層 package 抽取；負向驗證見
#     tools/android/signing-gate-negative-check.sh。
#
# 任一驗證失敗即非零退出（fail closed）。不得在此腳本印出任何 secret 值。
set -euo pipefail

# ANDROID_EXPECTED_PACKAGE 只供負向驗證腳本注入錯誤期望值，正常路徑用預設
EXPECTED_PACKAGE="${ANDROID_EXPECTED_PACKAGE:-com.vibesync.app}"

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
  # 只放行憑證中繼資料行，避免未來 keytool 輸出格式變動夾帶多餘內容
  grep -E "Alias name:|Owner:|Valid from:|SHA256:|SHA-256" <<<"$1" | head -8 || true
}

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
    echo "AND-02 artifact gate OK：package=$pkg，憑證非 debug"
    ;;
  *)
    fail "usage: check-android-signing.sh keystore <path> | artifact <apk|aab>"
    ;;
esac
