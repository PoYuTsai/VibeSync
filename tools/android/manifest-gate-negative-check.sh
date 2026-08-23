#!/usr/bin/env bash
# merged manifest 語意守門的可執行負向驗證，必須擋：
#   1. activity-alias 持有 OAuth／Email URI（alias ownership）
#   2. 自訂 dispatcher activity 搶走凍結 OAuth URI
#   3. activity-alias 持有 MAIN/LAUNCHER
#   4. OAuth／Email callback data 帶任何額外 URI 限制
#     （port/path/pathPrefix/pathPattern/pathAdvancedPattern/pathSuffix）
# 先跑正向基準證明合法 manifest 通過，避免「守門壞掉全紅」的假陰性。
# 凍結值取自兩份 machine-readable contract（與守門同一真相源）。
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
gate="$here/assert-merged-manifest.py"
read -r scheme host callback_activity < <(python3 -c '
import json, sys
c = json.load(open(sys.argv[1]))
print(c["scheme"], c["host"], c["androidCallbackActivity"])
' "$here/../../contracts/auth-callback.json")
read -r email_scheme email_host email_activity < <(python3 -c '
import json, sys
c = json.load(open(sys.argv[1]))
print(c["scheme"], c["host"], c["androidCallbackActivity"])
' "$here/../../contracts/email-auth-callback.json")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

good="$work/good.xml"
cat > "$good" <<XML
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.vibesync.app">
  <application>
    <activity android:name="com.vibesync.app.MainActivity" android:exported="true">
      <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
      </intent-filter>
      <intent-filter>
        <action android:name="android.intent.action.VIEW"/>
        <category android:name="android.intent.category.DEFAULT"/>
        <category android:name="android.intent.category.BROWSABLE"/>
        <data android:scheme="$email_scheme" android:host="$email_host"/>
      </intent-filter>
    </activity>
    <activity android:name="$callback_activity" android:exported="true">
      <intent-filter>
        <action android:name="android.intent.action.VIEW"/>
        <category android:name="android.intent.category.DEFAULT"/>
        <category android:name="android.intent.category.BROWSABLE"/>
        <data android:scheme="$scheme" android:host="$host"/>
      </intent-filter>
    </activity>
  </application>
</manifest>
XML

python3 "$gate" "$good" > /dev/null || {
  echo "::error::正向基準失敗：合法 merged manifest 竟被守門擋下"
  exit 1
}
echo "正向基準 OK：合法 merged manifest 通過守門"

expect_gate_fail() {
  local label="$1" file="$2"
  if python3 "$gate" "$file" > "$work/gate.log" 2>&1; then
    cat "$work/gate.log"
    echo "::error::負向驗證失敗：$label 應被守門擋下卻通過了"
    exit 1
  fi
  echo "負向驗證 OK：$label 被正確擋下"
}

# 1) activity-alias 也持有 OAuth URI → 擁有者不再唯一，必須擋
sed "s|</application>|<activity-alias android:name=\"com.vibesync.app.HijackAlias\" android:targetActivity=\"com.vibesync.app.MainActivity\" android:exported=\"true\"><intent-filter><action android:name=\"android.intent.action.VIEW\"/><category android:name=\"android.intent.category.DEFAULT\"/><category android:name=\"android.intent.category.BROWSABLE\"/><data android:scheme=\"$scheme\" android:host=\"$host\"/></intent-filter></activity-alias></application>|" \
  "$good" > "$work/alias-owner.xml"
expect_gate_fail "activity-alias 持有凍結 scheme" "$work/alias-owner.xml"

# 1b) 第二個 activity 只宣告 OAuth scheme → Android 會匹配任意 host，必須擋
sed "s|</application>|<activity android:name=\"com.vibesync.app.SchemeOnlyOAuthActivity\" android:exported=\"true\"><intent-filter><action android:name=\"android.intent.action.VIEW\"/><category android:name=\"android.intent.category.DEFAULT\"/><category android:name=\"android.intent.category.BROWSABLE\"/><data android:scheme=\"$scheme\"/></intent-filter></activity></application>|" \
  "$good" > "$work/oauth-scheme-only.xml"
expect_gate_fail "OAuth scheme-only activity 搶走 callback" "$work/oauth-scheme-only.xml"

# 1c) 分拆 data 的 scheme／host 仍會被 Android 合併，必須擋
sed "s|</application>|<activity android:name=\"com.vibesync.app.SplitOAuthActivity\" android:exported=\"true\"><intent-filter><action android:name=\"android.intent.action.VIEW\"/><category android:name=\"android.intent.category.DEFAULT\"/><category android:name=\"android.intent.category.BROWSABLE\"/><data android:scheme=\"$scheme\"/><data android:host=\"$host\"/></intent-filter></activity></application>|" \
  "$good" > "$work/oauth-split-data.xml"
expect_gate_fail "OAuth split scheme/host activity 搶走 callback" "$work/oauth-split-data.xml"

# 1d) Android leading-* hosts are broad matches, including bare * and suffix
# patterns. Any competitor that can claim the frozen OAuth host must fail.
for wildcard_host in '*' '*callback'; do
  sed "s|</application>|<activity android:name=\"com.vibesync.app.WildcardOAuth${wildcard_host//\*/Any}Activity\" android:exported=\"true\"><intent-filter><action android:name=\"android.intent.action.VIEW\"/><category android:name=\"android.intent.category.DEFAULT\"/><category android:name=\"android.intent.category.BROWSABLE\"/><data android:scheme=\"$scheme\" android:host=\"$wildcard_host\"/></intent-filter></activity></application>|" \
    "$good" > "$work/oauth-wildcard-${wildcard_host//\*/star}.xml"
  expect_gate_fail "OAuth wildcard host $wildcard_host 搶走 callback" \
    "$work/oauth-wildcard-${wildcard_host//\*/star}.xml"
done

# 2) 自訂 dispatcher activity 搶走凍結 OAuth URI → 偏離凍結契約，必須擋
sed "s|</application>|<activity android:name=\"com.vibesync.app.AuthCallbackDispatcherActivity\" android:exported=\"true\"><intent-filter><action android:name=\"android.intent.action.VIEW\"/><category android:name=\"android.intent.category.DEFAULT\"/><category android:name=\"android.intent.category.BROWSABLE\"/><data android:scheme=\"$scheme\" android:host=\"$host\"/></intent-filter></activity></application>|" \
  "$good" > "$work/custom-dispatcher.xml"
expect_gate_fail "自訂 dispatcher 搶走凍結 scheme" "$work/custom-dispatcher.xml"

# 3) activity-alias 持有 MAIN/LAUNCHER → launcher 不再唯一是 MainActivity
sed "s|</application>|<activity-alias android:name=\"com.vibesync.app.LauncherAlias\" android:targetActivity=\"com.vibesync.app.MainActivity\" android:exported=\"true\"><intent-filter><action android:name=\"android.intent.action.MAIN\"/><category android:name=\"android.intent.category.LAUNCHER\"/></intent-filter></activity-alias></application>|" \
  "$good" > "$work/alias-launcher.xml"
expect_gate_fail "activity-alias 持有 MAIN/LAUNCHER" "$work/alias-launcher.xml"

# 4) OAuth CallbackActivity data 帶額外 URI 限制屬性 → 窄化深連結比對，必須擋
for attr in \
  'android:port="8080"' \
  'android:path="/callback"' \
  'android:pathPrefix="/cb"' \
  'android:pathPattern=".*"' \
  'android:pathAdvancedPattern=".*"' \
  'android:pathSuffix="callback"'; do
  sed "s|android:host=\"$host\"|android:host=\"$host\" $attr|" \
    "$good" > "$work/restricted.xml"
  expect_gate_fail "CallbackActivity data 帶 $attr" "$work/restricted.xml"
done

# 5) Email URI 被第二個 activity 搶走 → MainActivity 不再是唯一 owner
sed "s|</application>|<activity android:name=\"com.vibesync.app.EmailHijackActivity\" android:exported=\"true\"><intent-filter><action android:name=\"android.intent.action.VIEW\"/><category android:name=\"android.intent.category.DEFAULT\"/><category android:name=\"android.intent.category.BROWSABLE\"/><data android:scheme=\"$email_scheme\" android:host=\"$email_host\"/></intent-filter></activity></application>|" \
  "$good" > "$work/email-owner.xml"
expect_gate_fail "Email callback 被第二個 activity 搶走" "$work/email-owner.xml"

# 5b) Email scheme-only activity 也可能匹配任意 Email host，必須擋
sed "s|</application>|<activity android:name=\"com.vibesync.app.SchemeOnlyEmailActivity\" android:exported=\"true\"><intent-filter><action android:name=\"android.intent.action.VIEW\"/><category android:name=\"android.intent.category.DEFAULT\"/><category android:name=\"android.intent.category.BROWSABLE\"/><data android:scheme=\"$email_scheme\"/></intent-filter></activity></application>|" \
  "$good" > "$work/email-scheme-only.xml"
expect_gate_fail "Email scheme-only activity 搶走 callback" "$work/email-scheme-only.xml"

# 5c) Email split scheme/host data 也會被 Android 合併，必須擋
sed "s|</application>|<activity android:name=\"com.vibesync.app.SplitEmailActivity\" android:exported=\"true\"><intent-filter><action android:name=\"android.intent.action.VIEW\"/><category android:name=\"android.intent.category.DEFAULT\"/><category android:name=\"android.intent.category.BROWSABLE\"/><data android:scheme=\"$email_scheme\"/><data android:host=\"$email_host\"/></intent-filter></activity></application>|" \
  "$good" > "$work/email-split-data.xml"
expect_gate_fail "Email split scheme/host activity 搶走 callback" "$work/email-split-data.xml"

# 5d) Wildcard Email hosts are also competitors; do not allow a chooser or
# ambiguous ownership for the independent MainActivity callback.
for wildcard_host in '*' '*callback'; do
  sed "s|</application>|<activity android:name=\"com.vibesync.app.WildcardEmail${wildcard_host//\*/Any}Activity\" android:exported=\"true\"><intent-filter><action android:name=\"android.intent.action.VIEW\"/><category android:name=\"android.intent.category.DEFAULT\"/><category android:name=\"android.intent.category.BROWSABLE\"/><data android:scheme=\"$email_scheme\" android:host=\"$wildcard_host\"/></intent-filter></activity></application>|" \
    "$good" > "$work/email-wildcard-${wildcard_host//\*/star}.xml"
  expect_gate_fail "Email wildcard host $wildcard_host 搶走 callback" \
    "$work/email-wildcard-${wildcard_host//\*/star}.xml"
done

# 6) Email callback data 帶額外 URI 限制 → 也必須 fail closed
sed "s|android:host=\"$email_host\"|android:host=\"$email_host\" android:path=\"/wrong\"|" \
  "$good" > "$work/email-restricted.xml"
expect_gate_fail "Email callback data 帶額外 URI 限制" "$work/email-restricted.xml"

echo "manifest gate 負向驗證全部通過：OAuth／Email ownership（含 wildcard）、自訂 dispatcher、alias launcher、URI 限制屬性都會被擋"
