#!/usr/bin/env bash
# CI-01 安裝＋啟動 smoke（AND-01／AND-03）。可在 CI emulator 或任何 adb
# 連上的實機／模擬器重現：
#   tools/android/install-smoke.sh build/app/outputs/flutter-apk/app-release.apk
# 驗證重點：
#   1. 安裝與 launcher 冷啟動存活數秒且 PID 唯一（AND-01：ClassNotFound＝0）
#   2. 凍結深連結（contracts/auth-callback.json）唯一解析到
#      flutter_web_auth_2 CallbackActivity，無 chooser（AND-03）
#   3. App 執行中送 callback VIEW intent：Status ok、無 chooser、同 PID
#      （CallbackActivity 與 App 同程序，不 crash、不疊程序）
#   4. 全程 logcat 掃本 package 的 runtime 例外與 ClassNotFoundException，
#      fail closed
# 注意：本腳本在 set -o pipefail 下不得把 adb 輸出串進會早退的 grep -q
# （命中時上游 SIGPIPE 141 會讓 pipeline 判失敗而漏報）。一律先把 log 完整
# 擷取進變數，再用 here-string 單次掃描；迴歸防護見
# tools/android/install-smoke-negative-check.sh。
set -euo pipefail

apk="${1:?usage: install-smoke.sh <apk-path>}"
[ -s "$apk" ] || { echo "::error::找不到 APK：$apk"; exit 1; }

# 凍結契約唯一真相源：contracts/auth-callback.json
contract="$(cd "$(dirname "$0")/../.." && pwd)/contracts/auth-callback.json"
read -r scheme host callback_activity < <(python3 -c '
import json, sys
c = json.load(open(sys.argv[1]))
print(c["scheme"], c["host"], c["androidCallbackActivity"])
' "$contract")

package="com.vibesync.app"
component="$package/.MainActivity"
# 深連結用非機密 dummy query（token 不進 log）
callback_uri="$scheme://$host?smoke=1"
# 負向 harness 用 fake adb 重現時免等真冷啟動
startup_wait="${SMOKE_STARTUP_WAIT:-5}"

# 程序必須存在且 PID 恰好一個（不得重複）；stdout 回傳該 PID。
# 本函式以 $(…) 呼叫，錯誤訊息一律走 stderr 才看得到
single_pid() {
  local pids
  pids=$(adb shell pidof "$package" | tr -s ' \r\n' ' ' | xargs || true)
  [ -n "$pids" ] || { echo "::error::$package 程序不存在" >&2; exit 1; }
  if [ "$(wc -w <<<"$pids")" -ne 1 ]; then
    echo "::error::$package PID 重複：$pids" >&2
    exit 1
  fi
  echo "$pids"
}

assert_no_chooser() {
  local out="$1" label="$2"
  if grep -Eq "ResolverActivity|ChooserActivity" <<<"$out"; then
    echo "::error::$label 出現 activity 選擇器（chooser），深連結唯一擁有者被打破"
    exit 1
  fi
}

# AND-03：對凍結深連結單獨 resolve，唯一解析結果必須是 plugin
# CallbackActivity 且無 chooser，否則 fail closed。
assert_unique_callback_owner() {
  local out
  out=$(adb shell "cmd package resolve-activity --brief -a android.intent.action.VIEW -d '$callback_uri'")
  out=$(tr -d '\r' <<<"$out")
  echo "resolver: $out"
  assert_no_chooser "$out" "resolver 解析"
  case "$out" in
    *"$package/$callback_activity"*) ;;
    *)
      echo "::error::深連結未唯一解析到 $callback_activity（唯一擁有者契約被打破）：$out"
      exit 1 ;;
  esac
}

adb wait-for-device
adb install -r "$apk"
assert_unique_callback_owner

# --- 1. launcher 冷啟動（AND-01：ClassNotFound＝0 的行為證據）---
launch_out=$(adb shell am start -W -n "$component")
echo "$launch_out"
grep -q "Status: ok" <<<"$launch_out" \
  || { echo "::error::$component 啟動失敗（launcher 解析或啟動錯誤）"; exit 1; }

# 冷啟動後程序要活過數秒（沒有立即 crash）
sleep "$startup_wait"
launcher_pid=$(single_pid)

# --- 2. App 執行中送 callback VIEW intent（AND-03 契約可重現）---
callback_out=$(adb shell "am start -W -a android.intent.action.VIEW -d '$callback_uri'")
echo "$callback_out"
grep -q "Status: ok" <<<"$callback_out" \
  || { echo "::error::深連結 VIEW intent 啟動失敗"; exit 1; }
assert_no_chooser "$callback_out" "深連結"
sleep 2
after_pid=$(single_pid)
if [ "$launcher_pid" != "$after_pid" ]; then
  echo "::error::callback 後 PID 改變（$launcher_pid → $after_pid），程序疑似 crash 重啟"
  exit 1
fi

# --- crash／ClassNotFound 掃描（fail closed）---
# 無 pipeline、無 grep -q 早退：先完整擷取，再取 package 相關行各掃一次
full_log=$(adb logcat -d)
pkg_lines=$(grep -F "$package" <<<"$full_log" || true)
crash_lines=$(grep "AndroidRuntime" <<<"$pkg_lines" || true)
if [ -n "$crash_lines" ]; then
  echo "$crash_lines"
  echo "::error::logcat 出現 $package 的 runtime 例外"
  exit 1
fi
cnf_lines=$(grep -F "ClassNotFoundException" <<<"$pkg_lines" || true)
if [ -n "$cnf_lines" ]; then
  echo "$cnf_lines"
  echo "::error::logcat 出現 $package 的 ClassNotFoundException"
  exit 1
fi

echo "install smoke OK：安裝、resolver 唯一 CallbackActivity owner、launcher 冷啟動存活、callback VIEW intent（同 PID、無 chooser）、無 runtime 例外、無 ClassNotFound"
