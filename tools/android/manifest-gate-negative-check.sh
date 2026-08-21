#!/usr/bin/env bash
# Round1 P2 可執行負向驗證：merged manifest 語意守門必須擋
#   1. activity-alias 持有凍結 scheme（alias ownership）
#   2. activity-alias 持有 MAIN/LAUNCHER
#   3. dispatcher data 帶任何額外 URI 限制
#     （port/path/pathPrefix/pathPattern/pathAdvancedPattern/pathSuffix）
# 先跑正向基準證明合法 manifest 通過，避免「守門壞掉全紅」的假陰性。
set -euo pipefail

gate="$(cd "$(dirname "$0")" && pwd)/assert-merged-manifest.py"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

good="$work/good.xml"
cat > "$good" <<'XML'
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.vibesync.app">
  <application>
    <activity android:name="com.vibesync.app.MainActivity" android:exported="true">
      <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
      </intent-filter>
    </activity>
    <activity android:name="com.vibesync.app.AuthCallbackDispatcherActivity" android:exported="true">
      <intent-filter>
        <action android:name="android.intent.action.VIEW"/>
        <category android:name="android.intent.category.DEFAULT"/>
        <category android:name="android.intent.category.BROWSABLE"/>
        <data android:scheme="com.poyutsai.vibesync" android:host="login-callback"/>
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

# 1) activity-alias 也持有凍結 scheme → 擁有者不再唯一，必須擋
sed 's|</application>|<activity-alias android:name="com.vibesync.app.HijackAlias" android:targetActivity="com.vibesync.app.MainActivity" android:exported="true"><intent-filter><action android:name="android.intent.action.VIEW"/><category android:name="android.intent.category.DEFAULT"/><category android:name="android.intent.category.BROWSABLE"/><data android:scheme="com.poyutsai.vibesync" android:host="login-callback"/></intent-filter></activity-alias></application>|' \
  "$good" > "$work/alias-owner.xml"
expect_gate_fail "activity-alias 持有凍結 scheme" "$work/alias-owner.xml"

# 2) activity-alias 持有 MAIN/LAUNCHER → launcher 不再唯一是 MainActivity
sed 's|</application>|<activity-alias android:name="com.vibesync.app.LauncherAlias" android:targetActivity="com.vibesync.app.MainActivity" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity-alias></application>|' \
  "$good" > "$work/alias-launcher.xml"
expect_gate_fail "activity-alias 持有 MAIN/LAUNCHER" "$work/alias-launcher.xml"

# 3) dispatcher data 帶額外 URI 限制屬性 → 窄化深連結比對，必須擋
for attr in \
  'android:port="8080"' \
  'android:path="/callback"' \
  'android:pathPrefix="/cb"' \
  'android:pathPattern=".*"' \
  'android:pathAdvancedPattern=".*"' \
  'android:pathSuffix="callback"'; do
  sed "s|android:host=\"login-callback\"|android:host=\"login-callback\" $attr|" \
    "$good" > "$work/restricted.xml"
  expect_gate_fail "dispatcher data 帶 $attr" "$work/restricted.xml"
done

echo "manifest gate 負向驗證全部通過：alias ownership、alias launcher、6 種 URI 限制屬性都會被擋"
