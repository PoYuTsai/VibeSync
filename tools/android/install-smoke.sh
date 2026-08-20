#!/usr/bin/env bash
# CI-01 安裝＋冷啟動 smoke（AND-01 驗證重點：ClassNotFound＝0）。
# 可在 CI emulator 或任何 adb 連上的實機/模擬器重現：
#   tools/android/install-smoke.sh build/app/outputs/flutter-apk/app-release.apk
set -euo pipefail

apk="${1:?usage: install-smoke.sh <apk-path>}"
package="com.vibesync.app"
component="$package/.MainActivity"

[ -s "$apk" ] || { echo "::error::找不到 APK：$apk"; exit 1; }

adb wait-for-device
adb install -r "$apk"
adb logcat -c || true

launch_out=$(adb shell am start -W -n "$component")
echo "$launch_out"
grep -q "Status: ok" <<<"$launch_out" \
  || { echo "::error::$component 啟動失敗（launcher 解析或啟動錯誤）"; exit 1; }

# 冷啟動後程序要活過 5 秒（沒有立即 crash）
sleep 5
adb shell pidof "$package" >/dev/null \
  || { echo "::error::$package 程序在冷啟動後 5 秒內死亡"; exit 1; }

# ponytail: 以 logcat 全域掃例外字串，若未來多程序誤報再改用 --pid 過濾
crash_lines=$(adb logcat -d -s AndroidRuntime:E | grep "$package" || true)
if [ -n "$crash_lines" ]; then
  echo "$crash_lines"
  echo "::error::logcat 出現 $package 的 runtime 例外"
  exit 1
fi
if adb logcat -d | grep "ClassNotFoundException" | grep -q "$package"; then
  echo "::error::logcat 出現 $package 的 ClassNotFoundException"
  exit 1
fi

echo "install smoke OK：$component 安裝、冷啟動、存活 5 秒，無 ClassNotFound"
