#!/usr/bin/env bash
# CI-01 安裝＋啟動 smoke（AND-01／AND-03）。可在 CI emulator 或任何 adb
# 連上的實機／模擬器重現：
#   tools/android/install-smoke.sh build/app/outputs/flutter-apk/app-release.apk
# 驗證重點：
#   1. 安裝與 launcher 冷啟動存活 5 秒（ClassNotFound＝0）
#   2. 凍結深連結 com.poyutsai.vibesync://login-callback 唯一解析到
#      AuthCallbackDispatcherActivity，無 chooser
#   3. 冷啟送 recovery/email VIEW intent → MainActivity onCreate（route=cold）
#   4. 暖啟再送一發 → 同 PID 走 onNewIntent（route=warm），程序不重複
set -euo pipefail

apk="${1:?usage: install-smoke.sh <apk-path>}"
package="com.vibesync.app"
component="$package/.MainActivity"
dispatcher_class="AuthCallbackDispatcherActivity"
# 深連結用非機密 dummy fragment，logcat 端只會記 host（token 不落 log）
callback_uri="com.poyutsai.vibesync://login-callback#type=recovery"
log_tag="VibeSyncAuthRoute"

[ -s "$apk" ] || { echo "::error::找不到 APK：$apk"; exit 1; }

# 在 route log（只含 route 與 host）裡等指定字串，最多 tries 秒
wait_for_log() {
  local pattern="$1" label="$2" tries="${3:-20}"
  for _ in $(seq "$tries"); do
    if adb logcat -d -s "$log_tag:I" | grep -qF "$pattern"; then
      return 0
    fi
    sleep 1
  done
  adb logcat -d -s "$log_tag:I" || true
  echo "::error::等不到 $label（logcat 無「$pattern」）"
  exit 1
}

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

adb wait-for-device
adb install -r "$apk"
adb logcat -c || true

# --- 1. launcher 冷啟動 ---
launch_out=$(adb shell am start -W -n "$component")
echo "$launch_out"
grep -q "Status: ok" <<<"$launch_out" \
  || { echo "::error::$component 啟動失敗（launcher 解析或啟動錯誤）"; exit 1; }

# 冷啟動後程序要活過 5 秒（沒有立即 crash）
sleep 5
adb shell pidof "$package" >/dev/null \
  || { echo "::error::$package 程序在冷啟動後 5 秒內死亡"; exit 1; }

# --- 2＋3. 深連結冷啟：force-stop 後送 recovery VIEW intent ---
adb shell am force-stop "$package"
sleep 2
adb logcat -c || true
cold_out=$(adb shell "am start -W -a android.intent.action.VIEW -d '$callback_uri'")
echo "$cold_out"
grep -q "Status: ok" <<<"$cold_out" \
  || { echo "::error::深連結 VIEW intent 啟動失敗"; exit 1; }
grep -qF "$dispatcher_class" <<<"$cold_out" \
  || { echo "::error::深連結未解析到 $dispatcher_class（唯一擁有者契約被打破）"; exit 1; }
assert_no_chooser "$cold_out" "深連結冷啟"
wait_for_log "dispatcher route=main" "dispatcher 轉送 MainActivity"
wait_for_log "MainActivity route=cold" "MainActivity 冷啟 onCreate"
sleep 3
cold_pid=$(single_pid)

# --- 4. 深連結暖啟：程序活著時再送一發 ---
warm_out=$(adb shell "am start -W -a android.intent.action.VIEW -d '$callback_uri'")
echo "$warm_out"
assert_no_chooser "$warm_out" "深連結暖啟"
wait_for_log "MainActivity route=warm" "MainActivity 暖啟 onNewIntent"
warm_pid=$(single_pid)
if [ "$cold_pid" != "$warm_pid" ]; then
  echo "::error::暖啟後 PID 改變（$cold_pid → $warm_pid），不是 onNewIntent 路徑"
  exit 1
fi

# --- crash／ClassNotFound 掃描（涵蓋深連結階段） ---
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

echo "install smoke OK：安裝、launcher 冷啟動、深連結冷啟（dispatcher→MainActivity onCreate）、暖啟（onNewIntent 同 PID）、無 chooser、無 ClassNotFound"
