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
cmd="${1:-}"; shift || true
case "$cmd $*" in
  *"${FAKE_HANG:-__none__}"*) exec sleep 300 ;;
esac
case "$cmd" in
  logcat)
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
  shell)
    case "$*" in
      *resolve-activity*) echo "$FAKE_RESOLVE" ;;
      *pidof*) echo 1234 ;;
      *"am start"*) echo "Status: ok" ;;
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

# --- 6. post-launch adb 卡死（API24 smoke 掛滿 45 分鐘 job timeout 迴歸）---
# 最小區間重現：MainActivity am start -W 回 Status ok 之後，逐一（單變數）讓
# 一個 post-launch adb 邊界永不返回：pidof、callback am start（-a 只中
# callback、不中 launcher 的 -n）、logcat。smoke 必須「自己」以 exit 1
# fail closed 並點名精確 stage；掛到外層 timeout 15（exit=124）或 stage
# 對不上都判紅。
for spec in "pidof|launcher-alive" "am start -W -a|callback-start" "logcat|logcat"; do
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

# --- 7. SMOKE_ADB_TIMEOUT 驗證（GNU timeout 0＝停用上限，必須 fail closed）---
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

echo "install-smoke fake-adb 迴歸 OK：正向通過；wrong-owner／chooser／crash／ClassNotFound／post-launch adb 卡死（launcher-alive、callback-start、logcat 精確 stage）／SMOKE_ADB_TIMEOUT 非法值 全數 fail closed"
