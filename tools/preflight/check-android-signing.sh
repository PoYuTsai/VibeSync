#!/usr/bin/env bash
# SEC-01／AND-02 非機密簽名守門。
#
#   keystore 模式：驗證既有 upload keystore 與 storePassword、keyAlias 互相
#     匹配（keyPassword 由 Gradle 簽名時驗證），且不是 Android debug 憑證。
#     密碼一律走 env（keytool -storepass:env），不進 argv、不落地、不輸出；
#     只印 alias、Owner、效期與 SHA256 fingerprint 等中繼資料。
#   artifact 模式：驗證 release APK/AAB 已簽名、非 debug 憑證，並對帳
#     package 為 com.vibesync.app。
#
# 任一驗證失敗即非零退出（fail closed）。不得在此腳本印出任何 secret 值。
set -euo pipefail

EXPECTED_PACKAGE="com.vibesync.app"

fail() {
  echo "::error::$1"
  exit 1
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
        certs=$(keytool -printcert -jarfile "$artifact") \
          || fail "AND-02 gate：AAB 憑證讀取失敗"
        grep -q "Owner:" <<<"$certs" || fail "AND-02 gate：AAB 未簽名"
        # AAB manifest 是 protobuf，applicationId 以位元組層級對帳（粗檢，
        # 找不到即擋；上 Play 後由 Play 端做最終對帳）
        unzip -p "$artifact" base/manifest/AndroidManifest.xml \
          | grep -q "$EXPECTED_PACKAGE" \
          || fail "AND-02 gate：AAB manifest 內找不到 $EXPECTED_PACKAGE"
        pkg="$EXPECTED_PACKAGE"
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
