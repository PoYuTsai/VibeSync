#!/usr/bin/env bash
# install-smoke.sh 的 fake adb 迴歸，全部情境確定性重現：
#   1. 正向：resolver 唯一解析到 plugin CallbackActivity → smoke 必須通過。
#   2. wrong-owner：resolver 解析到別的 activity → 必須 fail closed。
#   3. chooser：resolver 回 ResolverActivity → 必須 fail closed。
#   4. crash：全量 log 有本 package 的 AndroidRuntime 例外 → 必須攔下。
#   5. cnf：ClassNotFoundException 命中行後跟遠超 64KB pipe buffer 的
#      非命中 payload——舊寫法（adb logcat -d | grep | grep -q，
#      set -o pipefail）命中後上游 SIGPIPE 141 會漏報；修正版先完整擷取
#      再單次掃描，必須攔下並非零退出（fail closed）。
# 無外部依賴（python3 讀契約檔除外），純 bash，可直接進 CI。
# 用法：tools/android/install-smoke-negative-check.sh
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
smoke="${SMOKE_SCRIPT:-$here/install-smoke.sh}"
contract="$here/../../contracts/auth-callback.json"
callback_activity=$(python3 -c '
import json, sys
print(json.load(open(sys.argv[1]))["androidCallbackActivity"])
' "$contract")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

printf 'not-a-real-apk' > "$work/app.apk"

cat > "$work/adb" <<'FAKE'
#!/usr/bin/env bash
# 極簡 fake adb：只回答 install-smoke.sh 會問的問題，行為由環境變數控制。
#   FAKE_RESOLVE  — cmd package resolve-activity 的輸出（必填）
#   FAKE_TAIL_LOG — clean|crash|cnf：全量 logcat 的異常內容
#   FAKE_HANG     — 子字串；命中「cmd＋參數」的 adb 呼叫永不返回（模擬
#                   emulator/adbd wedge；exec sleep 讓 timeout 信號直達）
#   FAKE_CALLBACK_START — 覆寫「非等待 am start」（callback）的 stdout，
#                   模擬 Error／異常輸出；預設為成功送出標記
#   FAKE_CALLBACK_STDERR — 額外寫到 stderr 的 callback 輸出（真 adb 的
#                   Error／chooser 文字可能走 stderr 且 exit 0）
#   FAKE_LAUNCH_STATUS — launcher am start -W 的狀態：ok（預設）｜timeout
#                   （重現 API 36 的 Status: timeout＋Activity 正確）｜其他
#                   字串原樣進 Status: 行
#   FAKE_PIDOF    — pidof 輸出覆寫；設成空字串＝程序不存在（預設 1234）
#   FAKE_RESUMED  — dumpsys activity 的 resumed 行覆寫（預設 MainActivity
#                   前景 resumed）
cmd="${1:-}"; shift || true
case "$cmd $*" in
  *"${FAKE_HANG:-__none__}"*) exec sleep 300 ;;
esac
case "$cmd" in
  logcat)
    case "$*" in
      *-c*) ;;  # logcat -c 清空：無輸出
      *)
        case "${FAKE_TAIL_LOG:-clean}" in
          crash)
            echo "08-22 00:00:01.000  1234  1234 E AndroidRuntime: FATAL EXCEPTION: main"
            echo "08-22 00:00:01.001  1234  1234 E AndroidRuntime: Process: com.vibesync.app, PID: 1234"
            ;;
          cnf)
            # 命中行在前；之後 2 萬行「有 ClassNotFoundException、無 package」
            # 的行，讓舊寫法第一層 grep 在 grep -q 早退後必吃 SIGPIPE
            echo "08-22 00:00:01.000  1234  1234 E art: java.lang.ClassNotFoundException: com.vibesync.app.Boom"
            yes "08-22 00:00:01.001  1234  1234 E art: java.lang.ClassNotFoundException: com.other.junk" \
              | head -n 20000
            ;;
          *) echo "08-22 00:00:01.000  1234  1234 I chatty: benign line" ;;
        esac ;;
    esac ;;
  shell)
    case "$*" in
      *resolve-activity*) echo "$FAKE_RESOLVE" ;;
      *pidof*) pid_out="${FAKE_PIDOF-1234}"; [ -n "$pid_out" ] && echo "$pid_out" ;;
      *"dumpsys activity"*)
        echo "${FAKE_RESUMED:-    mResumedActivity: ActivityRecord{f00 u0 com.vibesync.app/.MainActivity t7}}" ;;
      *"am start"*)
        # -W（launcher 冷啟動）回等待式輸出；無 -W（callback）回非等待輸出
        case "$*" in
          *" -W "*)
            case "${FAKE_LAUNCH_STATUS:-ok}" in
              ok) echo "Status: ok" ;;
              timeout)
                echo "Starting: Intent { cmp=com.vibesync.app/.MainActivity }"
                echo "Status: timeout"
                echo "Activity: com.vibesync.app/.MainActivity"
                echo "WaitTime: 10666"
                ;;
              *) echo "Status: ${FAKE_LAUNCH_STATUS}" ;;
            esac ;;
          *)
            echo "${FAKE_CALLBACK_START:-Starting: Intent { act=android.intent.action.VIEW dat=scheme://host?smoke=1 }}"
            [ -n "${FAKE_CALLBACK_STDERR:-}" ] && echo "$FAKE_CALLBACK_STDERR" >&2
            ;;
        esac ;;
    esac ;;
  *) ;;  # wait-for-device / install → 成功
esac
exit 0
FAKE
chmod +x "$work/adb"

good_resolve="com.vibesync.app/$callback_activity"

status=0
run_smoke() {  # $1=FAKE_RESOLVE $2=FAKE_TAIL_LOG
  set +e
  FAKE_RESOLVE="$1" FAKE_TAIL_LOG="${2:-clean}" SMOKE_STARTUP_WAIT=0 \
    PATH="$work:$PATH" bash "$smoke" "$work/app.apk" >"$work/out" 2>&1
  status=$?
  set -e
}

expect_fail() {  # $1=情境 $2=必須出現的錯誤字串
  if [ "$status" -eq 0 ]; then
    cat "$work/out"
    echo "::error::$1 應 fail closed 非零退出，卻回報通過"
    exit 1
  fi
  grep -qF "$2" "$work/out" || {
    cat "$work/out"
    echo "::error::$1 非零退出，但原因不是「$2」"
    exit 1
  }
}

# --- 1. 正向：resolver=CallbackActivity → 必須通過 ---
run_smoke "$good_resolve" clean
if [ "$status" -ne 0 ]; then
  cat "$work/out"
  echo "::error::合法情境（resolver=$good_resolve）應通過，卻失敗（exit=$status）"
  exit 1
fi

# --- 2. resolver 解析到錯的 owner ---
run_smoke "com.vibesync.app/.MainActivity" clean
expect_fail "wrong-owner" "唯一擁有者契約被打破"

# --- 3. resolver 回 chooser ---
run_smoke "android/com.android.internal.app.ResolverActivity" clean
expect_fail "chooser" "chooser"

# --- 4. runtime crash ---
run_smoke "$good_resolve" crash
expect_fail "crash" "runtime 例外"

# --- 5. ClassNotFound（SIGPIPE payload）---
run_smoke "$good_resolve" cnf
expect_fail "ClassNotFound" "ClassNotFoundException"

# --- 6. API24 -W 迴歸：am start -W 對秒關的 CallbackActivity 永久等待 ---
# 真實故障重現（run 32553387019）：API24 上 CallbackActivity 無 live auth
# session 時立即 finish，am start -W 等不到它而掛滿 callback-start 上限。
# fake adb 只對「帶等待旗標的 callback 形式」（am start -W -a）卡死；修正後
# callback 命令不含 -W，整條 smoke 必須通過（exit 0）。掛到內部 timeout
# （exit 1）或外層 timeout 15（exit=124）都判紅。
set +e
FAKE_RESOLVE="$good_resolve" FAKE_TAIL_LOG=clean FAKE_HANG="am start -W -a" \
  SMOKE_STARTUP_WAIT=0 SMOKE_ADB_TIMEOUT=1 \
  PATH="$work:$PATH" timeout 15 bash "$smoke" "$work/app.apk" >"$work/out" 2>&1
status=$?
set -e
if [ "$status" -eq 124 ]; then
  cat "$work/out"
  echo "::error::API24 -W 迴歸掛到外層 timeout（exit=124），smoke 未有界返回"
  exit 1
fi
if [ "$status" -ne 0 ]; then
  cat "$work/out"
  echo "::error::callback 不得使用 am start -W（API24 對秒關 CallbackActivity 永久等待）；smoke 應不受 -W 卡死影響並通過，卻回 exit=$status"
  exit 1
fi

# --- 7. callback 非等待輸出含錯誤 → 必須 fail closed ---
# 7a. Error 取代 stdout 的送出標記（無 Starting: Intent → 標記檢查攔下）
run_smoke_cb_error() {  # 環境變數由呼叫端前綴
  set +e
  FAKE_RESOLVE="$good_resolve" FAKE_TAIL_LOG=clean SMOKE_STARTUP_WAIT=0 \
    PATH="$work:$PATH" bash "$smoke" "$work/app.apk" >"$work/out" 2>&1
  status=$?
  set -e
}
FAKE_CALLBACK_START="Error: Activity not started, unable to resolve Intent" \
  run_smoke_cb_error
expect_fail "callback-error-output" "深連結 VIEW intent"

# 7b. 分流迴歸（Codex round1 P1）：真 adb 可能 stdout 給正常
# 「Starting: Intent」、Error 走 stderr 且 exit 0。只擷取 stdout 的舊寫法
# 會假綠；驗證必須看 stdout+stderr 合流，且失敗原因必須正中 Error 分支
# 訊息「輸出含 Error」（刪掉 Error 檢查分支時本案例要紅）。
FAKE_CALLBACK_STDERR="Error: Activity not started, unable to resolve Intent" \
  run_smoke_cb_error
expect_fail "callback-stderr-error" "輸出含 Error"

# --- 8. post-launch adb 卡死（API24 smoke 掛滿 45 分鐘 job timeout 迴歸）---
# 最小區間重現：MainActivity am start -W 回 Status ok 之後，逐一（單變數）讓
# 一個 post-launch adb 邊界永不返回：pidof、callback am start（非等待形式
# 「am start -a」只中 callback、不中 launcher 的 -W -n）、logcat。smoke 必須
# 「自己」以 exit 1 fail closed 並點名精確 stage；掛到外層 timeout 15
# （exit=124）或 stage 對不上都判紅。
# logcat 的 hang 樣式用「logcat -d」：啟動前多了 logcat -c 清空呼叫，
# 用裸「logcat」會先掛在 logcat-clear stage 而測不到 post-launch 邊界
for spec in "pidof|launcher-alive" "am start -a|callback-start" "logcat -d|logcat"; do
  hang="${spec%%|*}"; stage="${spec##*|}"
  set +e
  FAKE_RESOLVE="$good_resolve" FAKE_TAIL_LOG=clean FAKE_HANG="$hang" \
    SMOKE_STARTUP_WAIT=0 SMOKE_ADB_TIMEOUT=2 \
    PATH="$work:$PATH" timeout 15 bash "$smoke" "$work/app.apk" >"$work/out" 2>&1
  status=$?
  set -e
  if [ "$status" -eq 124 ]; then
    cat "$work/out"
    echo "::error::adb 卡死（$hang）掛到外層 timeout（exit=124），smoke 未自行 fail closed"
    exit 1
  fi
  if [ "$status" -ne 1 ]; then
    cat "$work/out"
    echo "::error::adb 卡死（$hang）應由 smoke 內部以 exit 1 fail closed，卻回 exit=$status"
    exit 1
  fi
  grep -qF "adb 卡住（stage：$stage）" "$work/out" || {
    cat "$work/out"
    echo "::error::adb 卡死（$hang）診斷未點名精確 stage「$stage」"
    exit 1
  }
done

# --- 9. SMOKE_ADB_TIMEOUT 驗證（GNU timeout 0＝停用上限，必須 fail closed）---
# 0、超上限、非數字、溢位長數字串（bash 數值比較會 integer expression
# expected 後放行）、前導零都不得進到任何 adb 呼叫；必須 exit 1 並給
# 可行動訊息。
for bad in 0 601 abc 99999999999999999999999 0001; do
  set +e
  FAKE_RESOLVE="$good_resolve" FAKE_TAIL_LOG=clean \
    SMOKE_STARTUP_WAIT=0 SMOKE_ADB_TIMEOUT="$bad" \
    PATH="$work:$PATH" timeout 15 bash "$smoke" "$work/app.apk" >"$work/out" 2>&1
  status=$?
  set -e
  if [ "$status" -ne 1 ]; then
    cat "$work/out"
    echo "::error::SMOKE_ADB_TIMEOUT=$bad 應 fail closed（exit 1），卻回 exit=$status"
    exit 1
  fi
  grep -qF "SMOKE_ADB_TIMEOUT" "$work/out" || {
    cat "$work/out"
    echo "::error::SMOKE_ADB_TIMEOUT=$bad 的錯誤訊息未指出該變數"
    exit 1
  }
done

# --- 10. launcher Status timeout 二次健康檢查（API 36 迴歸）---
# am start -W 回 Status: timeout 時不得直接判死也不得直接放行：
# PID 唯一＋MainActivity 前景 resumed＋log 乾淨 → 以警告放行；
# 任一健康檢查不過 → fail closed。ok／timeout 以外的狀態照樣直接失敗。
run_smoke_timeout() {  # 額外 FAKE_* 由呼叫端前綴
  set +e
  FAKE_RESOLVE="$good_resolve" FAKE_LAUNCH_STATUS=timeout \
    SMOKE_STARTUP_WAIT=0 \
    PATH="$work:$PATH" timeout 15 bash "$smoke" "$work/app.apk" >"$work/out" 2>&1
  status=$?
  set -e
}

# 10a. timeout＋PID 唯一＋MainActivity resumed＋log 乾淨 → 必須通過（帶警告）
run_smoke_timeout
if [ "$status" -ne 0 ]; then
  cat "$work/out"
  echo "::error::timeout＋健康檢查全過 應以警告放行，卻失敗（exit=$status）"
  exit 1
fi
grep -qF "二次健康檢查通過" "$work/out" || {
  cat "$work/out"
  echo "::error::timeout＋健康 通過但缺少明確警告訊息"
  exit 1
}

# 10b. timeout＋無 PID → fail closed
FAKE_PIDOF="" run_smoke_timeout
expect_fail "timeout-no-pid" "程序不存在"

# 10c. timeout＋前景 resumed 是別的 activity → fail closed
FAKE_RESUMED="    mResumedActivity: ActivityRecord{f00 u0 com.android.launcher3/.Launcher t2}" \
  run_smoke_timeout
expect_fail "timeout-wrong-foreground" "前景 resumed activity 不是"

# 10d. timeout＋runtime crash → fail closed
FAKE_TAIL_LOG=crash run_smoke_timeout
expect_fail "timeout-crash" "runtime 例外"

# 10e. ok／timeout 以外的任何 Status 仍必須直接失敗（strict path 未放寬）
set +e
FAKE_RESOLVE="$good_resolve" FAKE_LAUNCH_STATUS="unable-to-resolve" \
  SMOKE_STARTUP_WAIT=0 \
  PATH="$work:$PATH" timeout 15 bash "$smoke" "$work/app.apk" >"$work/out" 2>&1
status=$?
set -e
expect_fail "launch-status-not-ok" "啟動失敗"

echo "install-smoke fake-adb 迴歸 OK：正向通過；wrong-owner／chooser／crash／ClassNotFound／post-launch adb 卡死（launcher-alive、callback-start、logcat 精確 stage）／SMOKE_ADB_TIMEOUT 非法值／launcher Status timeout 健康檢查（健康放行、無 PID／錯前景／crash／其他狀態 fail closed）全數符合預期"
