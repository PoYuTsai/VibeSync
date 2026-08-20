#!/usr/bin/env bash
# P1-1 迴歸防護：install-smoke.sh 的 ClassNotFound 掃描必須 fail closed。
# 用 fake adb 走完整條 happy path，但全量 log 塞「命中行在前、大量非命中
# ClassNotFoundException 行在後（遠超 64KB pipe buffer）」的 payload——
# 舊寫法（adb logcat -d | grep | grep -q，set -o pipefail）命中後上游
# SIGPIPE 141 會讓 pipeline 判失敗而漏報；修正版先完整擷取再單次掃描，
# 必須攔下並非零退出。無外部依賴，純 bash，可直接進 CI。
# 用法：tools/android/install-smoke-negative-check.sh
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
smoke="${SMOKE_SCRIPT:-$here/install-smoke.sh}"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

printf 'not-a-real-apk' > "$work/app.apk"

cat > "$work/adb" <<'FAKE'
#!/usr/bin/env bash
# 極簡 fake adb：只回答 install-smoke.sh 會問的問題（happy path），
# 唯一的異常是全量 log 裡的 ClassNotFoundException。
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
      *AndroidRuntime*) ;;
      *)
        # 命中行在前；之後 2 萬行「有 ClassNotFoundException、無 package」
        # 的行，讓舊寫法第一層 grep 在 grep -q 早退後必吃 SIGPIPE
        echo "08-21 00:00:01.000  1234  1234 E art: java.lang.ClassNotFoundException: com.vibesync.app.Boom"
        yes "08-21 00:00:01.001  1234  1234 E art: java.lang.ClassNotFoundException: com.other.junk" \
          | head -n 20000
        ;;
    esac ;;
  shell)
    case "$*" in
      *pidof*) echo 1234 ;;
      *force-stop*) ;;
      *dumpsys*)
        echo "    Hist #0: ActivityRecord{deadbeef u0 com.vibesync.app/.MainActivity t42}" ;;
      *"am start"*)
        echo "Status: ok"
        case "$*" in *VIEW*) echo "cmp=com.vibesync.app/.AuthCallbackDispatcherActivity" ;; esac ;;
    esac ;;
  *) ;;  # wait-for-device / install → 成功
esac
exit 0
FAKE
chmod +x "$work/adb"

set +e
PATH="$work:$PATH" bash "$smoke" "$work/app.apk" >"$work/out" 2>&1
status=$?
set -e

if [ "$status" -eq 0 ]; then
  cat "$work/out"
  echo "::error::install-smoke 應因 ClassNotFoundException 非零退出，卻回報通過（掃描 fail open）"
  exit 1
fi
grep -qF "ClassNotFoundException" "$work/out" || {
  cat "$work/out"
  echo "::error::install-smoke 非零退出，但原因不是 ClassNotFound 掃描"
  exit 1
}
echo "install-smoke negative check OK：ClassNotFound 掃描 fail closed（exit=$status）"
