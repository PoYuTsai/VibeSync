#!/usr/bin/env bash
# install-smoke.sh 的 fake adb 迴歸（P1-1＋Round1 P0），全部情境確定性重現：
#   1. 正向：resolver 唯一解析到 dispatcher，而 am start -W 把最終 drawn
#      activity 報成 MainActivity（transient dispatcher 不出現在 -W 輸出）
#      → smoke 必須通過（不得再要求 -W 報 dispatcher）。
#   2. wrong-owner：resolver 解析到別的 activity → 必須 fail closed。
#   3. chooser：resolver 回 ResolverActivity → 必須 fail closed。
#   4. crash：全量 log 有本 package 的 AndroidRuntime 例外 → 必須攔下。
#   5. cnf：ClassNotFoundException 命中行後跟遠超 64KB pipe buffer 的
#      非命中 payload——舊寫法（adb logcat -d | grep | grep -q，
#      set -o pipefail）命中後上游 SIGPIPE 141 會漏報；修正版先完整擷取
#      再單次掃描，必須攔下並非零退出（fail closed）。
# 無外部依賴，純 bash，可直接進 CI。
# 用法：tools/android/install-smoke-negative-check.sh
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
smoke="${SMOKE_SCRIPT:-$here/install-smoke.sh}"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

printf 'not-a-real-apk' > "$work/app.apk"

cat > "$work/adb" <<'FAKE'
#!/usr/bin/env bash
# 極簡 fake adb：只回答 install-smoke.sh 會問的問題，行為由環境變數控制。
#   FAKE_RESOLVE  — cmd package resolve-activity 的輸出（預設 dispatcher）
#   FAKE_TAIL_LOG — clean|crash|cnf：全量 logcat 的異常內容
cmd="${1:-}"; shift || true
case "$cmd" in
  logcat)
    case "$*" in
      *-c*) ;;
      *VibeSyncAuthRoute*)
        # route log 一次備齊，wait_for_log 立即命中、不空轉
        printf '%s\n' \
          "08-21 00:00:00.000  1234  1234 I VibeSyncAuthRoute: dispatcher route=main host=login-callback" \
          "08-21 00:00:00.001  1234  1234 I VibeSyncAuthRoute: MainActivity route=cold host=login-callback" \
          "08-21 00:00:00.002  1234  1234 I VibeSyncAuthRoute: MainActivity route=warm host=login-callback"
        ;;
      *)
        case "${FAKE_TAIL_LOG:-clean}" in
          crash)
            echo "08-21 00:00:01.000  1234  1234 E AndroidRuntime: FATAL EXCEPTION: main"
            echo "08-21 00:00:01.001  1234  1234 E AndroidRuntime: Process: com.vibesync.app, PID: 1234"
            ;;
          cnf)
            # 命中行在前；之後 2 萬行「有 ClassNotFoundException、無 package」
            # 的行，讓舊寫法第一層 grep 在 grep -q 早退後必吃 SIGPIPE
            echo "08-21 00:00:01.000  1234  1234 E art: java.lang.ClassNotFoundException: com.vibesync.app.Boom"
            yes "08-21 00:00:01.001  1234  1234 E art: java.lang.ClassNotFoundException: com.other.junk" \
              | head -n 20000
            ;;
          *) echo "08-21 00:00:01.000  1234  1234 I chatty: benign line" ;;
        esac
        ;;
    esac ;;
  shell)
    case "$*" in
      *resolve-activity*)
        echo "${FAKE_RESOLVE:-com.vibesync.app/.AuthCallbackDispatcherActivity}" ;;
      *pidof*) echo 1234 ;;
      *force-stop*) ;;
      *dumpsys*)
        echo "    Hist #0: ActivityRecord{deadbeef u0 com.vibesync.app/.MainActivity t42}" ;;
      *"am start"*)
        # 合法 redirect 的真實 -W 輸出：transient dispatcher 不出現，
        # 最終 drawn activity 是 MainActivity
        echo "Status: ok"
        echo "Activity: com.vibesync.app/.MainActivity"
        ;;
    esac ;;
  *) ;;  # wait-for-device / install → 成功
esac
exit 0
FAKE
chmod +x "$work/adb"

status=0
run_smoke() {  # $1=FAKE_RESOLVE（空＝預設 dispatcher） $2=FAKE_TAIL_LOG
  set +e
  FAKE_RESOLVE="${1:-}" FAKE_TAIL_LOG="${2:-clean}" \
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

# --- 1. 正向：resolver=dispatcher、-W drawn=MainActivity → 必須通過 ---
run_smoke "" clean
if [ "$status" -ne 0 ]; then
  cat "$work/out"
  echo "::error::合法 redirect（resolver=dispatcher、am -W 報 MainActivity）應通過，卻失敗（exit=$status）"
  exit 1
fi

# --- 2. resolver 解析到錯的 owner ---
run_smoke "com.vibesync.app/.MainActivity" clean
expect_fail "wrong-owner" "唯一擁有者契約被打破"

# --- 3. resolver 回 chooser ---
run_smoke "android/com.android.internal.app.ResolverActivity" clean
expect_fail "chooser" "chooser"

# --- 4. runtime crash ---
run_smoke "" crash
expect_fail "crash" "runtime 例外"

# --- 5. ClassNotFound（SIGPIPE payload）---
run_smoke "" cnf
expect_fail "ClassNotFound" "ClassNotFoundException"

echo "install-smoke fake-adb 迴歸 OK：正向（MainActivity drawn）通過；wrong-owner／chooser／crash／ClassNotFound 全數 fail closed"
