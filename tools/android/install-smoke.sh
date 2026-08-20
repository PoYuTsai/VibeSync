#!/usr/bin/env bash
# CI-01 安裝＋啟動 smoke（AND-01／AND-03）。可在 CI emulator 或任何 adb
# 連上的實機／模擬器重現：
#   tools/android/install-smoke.sh build/app/outputs/flutter-apk/app-release.apk
# 驗證重點：
#   1. 安裝與 launcher 冷啟動存活 5 秒（ClassNotFound＝0）
#   2. launcher 先建立既有 MainActivity，再送凍結深連結
#      com.poyutsai.vibesync://login-callback → 必須進既有實例 onNewIntent
#      （route=warm），且 dumpsys 計數證明 MainActivity 實例恰一、
#      本 package 的 app task 恰一（AND-03：taskAffinity="" 偏離 pinned
#      flutter_web_auth_2 README 的可執行證據——NEW_TASK 轉送靠 task root
#      component 比對回到既有 task，不疊第二個實例／task）
#   3. 深連結唯一解析到 AuthCallbackDispatcherActivity，無 chooser
#   4. force-stop 後冷啟送 callback → MainActivity onCreate（route=cold）
#   5. 暖啟再送一發 → 同 PID 走 onNewIntent（route=warm），程序不重複
# P1-1：本腳本在 set -o pipefail 下不得把 adb 輸出串進會早退的 grep -q
# （命中時上游 SIGPIPE 141 會讓 pipeline 判失敗而漏報）。一律先把 log 完整
# 擷取進變數，再用 here-string 單次掃描；迴歸防護見
# tools/android/install-smoke-negative-check.sh。
set -euo pipefail

apk="${1:?usage: install-smoke.sh <apk-path>}"
package="com.vibesync.app"
component="$package/.MainActivity"
dispatcher_class="AuthCallbackDispatcherActivity"
# 深連結用非機密 dummy fragment，logcat 端只會記 host（token 不落 log）
callback_uri="com.poyutsai.vibesync://login-callback#type=recovery"
log_tag="VibeSyncAuthRoute"

[ -s "$apk" ] || { echo "::error::找不到 APK：$apk"; exit 1; }

# 各階段 logcat 會被清空以隔離 route log；先累積到 full_log，
# 收尾的 crash／ClassNotFound 掃描才涵蓋全程
full_log=""
capture_phase_log() {
  full_log+="$(adb logcat -d)"$'\n'
  adb logcat -c || true
}

# 在 route log（只含 route 與 host）裡等指定字串，最多 tries 秒。
# 先完整擷取再掃 here-string：無 pipeline、無早退（P1-1）
wait_for_log() {
  local pattern="$1" label="$2" tries="${3:-20}" dump
  for _ in $(seq "$tries"); do
    dump=$(adb logcat -d -s "$log_tag:I")
    if grep -qF "$pattern" <<<"$dump"; then
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

# AND-03 dumpsys 結算：MainActivity ActivityRecord（去重後）恰一個、
# 本 package 所有 ActivityRecord 落在恰一個 task。輪詢數秒等 dispatcher
# （noHistory＋finish）收乾淨，避免 finish 動畫期間誤判。
assert_single_main_and_task() {
  local label="$1" tries="${2:-15}" dump records mains tasks
  for _ in $(seq "$tries"); do
    dump=$(adb shell dumpsys activity activities | tr -d '\r')
    records=$(grep -oE 'ActivityRecord\{[^}]*\}' <<<"$dump" \
      | grep -F "$package/" | sort -u || true)
    mains=$(grep -cF "$package/.MainActivity" <<<"$records" || true)
    tasks=$(grep -oE ' t[0-9]+' <<<"$records" | sort -u | grep -c 't' || true)
    if [ "$mains" -eq 1 ] && [ "$tasks" -eq 1 ]; then
      return 0
    fi
    sleep 1
  done
  echo "$records"
  echo "::error::$label dumpsys 結算失敗：MainActivity 實例=$mains（預期 1）、app task=$tasks（預期 1）"
  exit 1
}

send_callback() {
  local out
  out=$(adb shell "am start -W -a android.intent.action.VIEW -d '$callback_uri'")
  echo "$out"
  grep -q "Status: ok" <<<"$out" \
    || { echo "::error::深連結 VIEW intent 啟動失敗"; exit 1; }
  grep -qF "$dispatcher_class" <<<"$out" \
    || { echo "::error::深連結未解析到 $dispatcher_class（唯一擁有者契約被打破）"; exit 1; }
  assert_no_chooser "$out" "深連結（$1）"
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
launcher_pid=$(single_pid)

# --- 2. 既有 Main 存活時送 callback：必須回到同一實例（AND-03 核心證據）---
capture_phase_log
send_callback "既有 Main"
wait_for_log "dispatcher route=main" "dispatcher 轉送 MainActivity"
wait_for_log "MainActivity route=warm" "既有 MainActivity 走 onNewIntent"
reuse_pid=$(single_pid)
if [ "$launcher_pid" != "$reuse_pid" ]; then
  echo "::error::callback 後 PID 改變（$launcher_pid → $reuse_pid），既有實例未被重用"
  exit 1
fi
assert_single_main_and_task "既有 Main＋callback"

# --- 3. 深連結冷啟：force-stop 後送 recovery VIEW intent ---
adb shell am force-stop "$package"
sleep 2
capture_phase_log
send_callback "冷啟"
wait_for_log "dispatcher route=main" "dispatcher 轉送 MainActivity"
wait_for_log "MainActivity route=cold" "MainActivity 冷啟 onCreate"
sleep 3
cold_pid=$(single_pid)
assert_single_main_and_task "冷啟 callback"

# --- 4. 深連結暖啟：程序活著時再送一發 ---
capture_phase_log
send_callback "暖啟"
wait_for_log "MainActivity route=warm" "MainActivity 暖啟 onNewIntent"
warm_pid=$(single_pid)
if [ "$cold_pid" != "$warm_pid" ]; then
  echo "::error::暖啟後 PID 改變（$cold_pid → $warm_pid），不是 onNewIntent 路徑"
  exit 1
fi
assert_single_main_and_task "暖啟 callback"

# --- crash／ClassNotFound 掃描（涵蓋全部階段，P1-1 fail closed）---
# 無 pipeline、無 grep -q 早退：先取 package 相關行，再各掃一次
capture_phase_log
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

echo "install smoke OK：安裝、launcher 冷啟動、既有 Main callback 重用（單一實例／單一 task）、冷啟（dispatcher→onCreate）、暖啟（onNewIntent 同 PID）、無 chooser、無 ClassNotFound"
