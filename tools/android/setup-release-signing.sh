#!/usr/bin/env bash
# AND-02：由 CI secrets 產生 android/app/keystore.jks 與 android/key.properties。
# distribute.yml 與 release.yml 共用本腳本，勿在 workflow 內各自複製這段邏輯。
# SEC-01：secret 值只進檔案與 env，任何路徑都不得印出；錯誤訊息也不含值。
set -euo pipefail

: "${KEYSTORE_BASE64:?need KEYSTORE_BASE64 env}"
: "${KEYSTORE_PASSWORD:?need KEYSTORE_PASSWORD env}"
: "${KEY_ALIAS:?need KEY_ALIAS env}"
: "${KEY_PASSWORD:?need KEY_PASSWORD env}"

# 已知風險（2026-08-22 run 32495993539）：既有 ANDROID_KEYSTORE secret 曾
# 是無效 Base64。這裡 fail closed 並給出可行動訊息；secret 重建／輪替是
# Eric gate，不得由 CI 或 agent 自行處理。
if ! printf '%s' "$KEYSTORE_BASE64" | base64 -d > android/app/keystore.jks 2>/dev/null; then
  echo "::error::ANDROID_KEYSTORE secret 不是有效 Base64，無法還原 keystore（SEC-01：停在此 gate，待 Eric 驗證／重建 secret）"
  exit 1
fi
if [ ! -s android/app/keystore.jks ]; then
  echo "::error::ANDROID_KEYSTORE 解碼後為空檔（SEC-01：停在此 gate）"
  exit 1
fi

{
  echo "storeFile=keystore.jks"
  echo "storePassword=$KEYSTORE_PASSWORD"
  echo "keyAlias=$KEY_ALIAS"
  echo "keyPassword=$KEY_PASSWORD"
} > android/key.properties

echo "release signing 檔案就緒：android/app/keystore.jks、android/key.properties（值不輸出）"
