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
# 證據邊界：synthetic VIEW intent 只驗 callback「routing」與 process
# stability，不驗 FlutterWebAuth2.authenticate 真的收到 OAuth 結果
# （plugin callback map 只在 live auth session 進行中才有 entry）。
# live OAuth completion 屬實機驗證證據，見 docs/integrations/auth.md。
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
# 每個 adb 呼叫的時間上限（秒）。API 24 emulator 曾在 MainActivity 啟動後
# 的 post-launch adb 呼叫上 wedge 永不返回，吃滿 45 分鐘 job timeout 且零
# 診斷；所以任何 adb 邊界都必須有界。
# GNU timeout 把 0 視為「停用上限」，會讓有界保證整個失效；bash 的 -lt/-gt
# 遇到超過 intmax 的長數字串會 integer expression expected 後放行。所以用
# 純字面 regex allowlist（溢位安全）：恰好 1..600、無前導零，否則 fail
# closed。
adb_timeout="${SMOKE_ADB_TIMEOUT:-120}"
if [[ ! "$adb_timeout" =~ ^([1-9]|[1-9][0-9]|[1-5][0-9][0-9]|600)$ ]]; then
  echo "::error::SMOKE_ADB_TIMEOUT 必須是 1..600 的十進位整數秒、無前導零（0 會停用 GNU timeout 上限），得到：${adb_timeout}"
  exit 1
fi

# 卡住（timeout 124；-k 補刀後 137）→ 點名 stage 後 fail closed
die_if_hung() {  # $1=timeout exit status $2=stage $3…=被呼叫的 adb 參數
  local status="$1" stage="$2"; shift 2
  if [ "$status" -eq 124 ] || [ "$status" -eq 137 ]; then
    echo "::error::adb 卡住（stage：$stage）超過 ${adb_timeout}s 未返回：adb $*" >&2
    exit 1
  fi
}

# 所有 adb 一律經此包裝：有限 timeout、精確 stage 診斷、fail closed。
# stdout 原樣回傳供 $(…) 擷取。
adb_call() {  # $1=stage 標籤，其餘為 adb 參數
  local stage="$1" out status; shift
  set +e
  out=$(timeout -k 5 "$adb_timeout" adb "$@")
  status=$?
  set -e
  die_if_hung "$status" "$stage" "$@"
  if [ "$status" -ne 0 ]; then
    echo "::error::adb 失敗（stage：$stage，exit=$status）：adb $*" >&2
    exit 1
  fi
  printf '%s\n' "$out"
}

# 程序必須存在且 PID 恰好一個（不得重複）；stdout 回傳該 PID。
# 本函式以 $(…) 呼叫，錯誤訊息一律走 stderr 才看得到。
# pidof 查無程序時 exit 非零是合法輸入（訊息要說「程序不存在」），
# 所以不走 adb_call 的嚴格 exit 檢查，只擋卡住。
single_pid() {  # $1=stage 標籤
  local stage="$1" pids status
  set +e
  pids=$(timeout -k 5 "$adb_timeout" adb shell pidof "$package")
  status=$?
  set -e
  die_if_hung "$status" "$stage" shell pidof "$package"
  pids=$(tr -s ' \r\n' ' ' <<<"$pids" | xargs || true)
  [ -n "$pids" ] || { echo "::error::$package 程序不存在（stage：$stage）" >&2; exit 1; }
  if [ "$(wc -w <<<"$pids")" -ne 1 ]; then
    echo "::error::$package PID 重複（stage：$stage）：$pids" >&2
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
  out=$(adb_call resolver shell "cmd package resolve-activity --brief -a android.intent.action.VIEW -d '$callback_uri'")
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

adb_call wait-for-device wait-for-device
adb_call install install -r "$apk"
assert_unique_callback_owner

# --- 1. launcher 冷啟動（AND-01：ClassNotFound＝0 的行為證據）---
launch_out=$(adb_call launcher-start shell am start -W -n "$component")
echo "$launch_out"
grep -q "Status: ok" <<<"$launch_out" \
  || { echo "::error::$component 啟動失敗（launcher 解析或啟動錯誤）"; exit 1; }

# 冷啟動後程序要活過數秒（沒有立即 crash）
sleep "$startup_wait"
launcher_pid=$(single_pid launcher-alive)

# --- 2. App 執行中送 callback VIEW intent（AND-03 routing 契約；
#        不驗 live OAuth completion，見檔頭證據邊界）---
callback_out=$(adb_call callback-start shell "am start -W -a android.intent.action.VIEW -d '$callback_uri'")
echo "$callback_out"
grep -q "Status: ok" <<<"$callback_out" \
  || { echo "::error::深連結 VIEW intent 啟動失敗"; exit 1; }
assert_no_chooser "$callback_out" "深連結"
sleep 2
after_pid=$(single_pid callback-alive)
if [ "$launcher_pid" != "$after_pid" ]; then
  echo "::error::callback 後 PID 改變（$launcher_pid → $after_pid），程序疑似 crash 重啟"
  exit 1
fi

# --- crash／ClassNotFound 掃描（fail closed）---
# 無 pipeline、無 grep -q 早退：先完整擷取，再取 package 相關行各掃一次
full_log=$(adb_call logcat logcat -d)
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
