# VibeSync AI 鍵盤高風險 Review Packet

Status: READY_FOR_INDEPENDENT_CODEX_REVIEW

## Scope

- Base: `5f12c1b4`
- Range: `5f12c1b4..c2ca42eb`
- Branch: `codex/vibesync-keyboard`
- Commits:
  - `34007c57` 新增鍵盤單則回覆服務與五風格契約
  - `01f0cd4b` 新增 VibeSync iOS AI 鍵盤 Extension
  - `ec96950d` 新增鍵盤共享登入與首次啟用教學
  - `ca4f8320` 補強鍵盤扣額逾時與登入競態保護
  - `c2ca42eb` 補齊鍵盤額度導流與真機簽章設定

## Review Focus

1. Auth：App Group Keychain 只共享 access token／userId／expiry；不共享 refresh token。事件寫入序列化、登出先刪 token；兩 target 均宣告同一 Keychain access group。
2. Quota／計費：成功回覆驗證後才固定扣 1；扣前重查 quota，`increment_usage` 鎖內再守；所有生成／格式失敗不扣。RevenueCat 只允許升級式 refresh。
3. Timeout：server 最多兩輪 8s，keyboard client fence 20s，避免可預期的「server 已扣、client 先 timeout」。
4. Privacy：extension 只在使用者點「載入」後讀剪貼簿；不讀 `documentContext` 作 prompt、不保存聊天文字、不記 raw prompt／response。
5. App Review：未開完整取用仍有 ABC／標點／空白／換行／退格與地球切換；extension 內無購買流程。quota 429 只寫一次性旗標，回到 containing app 才 push paywall；模型限流不寫旗標。
6. Prompt／schema：獨立 `keyboard-reply`，不 import／修改 analyze-chat；五風格、正體中文、100 字與 raw JSON／banned token guard。
7. Xcode project：extension target、embed phase、bundle id、App Group entitlements、Info.plist open-access 設定。

## Validation

- `deno check supabase/functions/keyboard-reply/index.ts`
- `deno test --allow-read supabase/functions/keyboard-reply supabase/functions/_shared/model_rate_limit_test.ts supabase/functions/_shared/quota_test.ts` → 63 passed
- 原始鍵盤／route/settings targeted suite → 29 passed；quota signal／setup／route 追加回歸 → 5 passed
- `flutter analyze` → no issues
- `deno fmt --check`／`git diff --check` → clean
- pbxproj 24-hex reference、括號平衡與三份 plist XML 靜態驗證 → passed
- `AGENTS.md`／`CLAUDE.md` SHA-256 → synchronized

## Pending External Gates

- Windows 無 Xcode：尚未編譯／Archive iOS target，也未驗證實機鍵盤記憶體高度、App Group Keychain、設定 deep link 與 LINE 插入。
- Apple Developer Portal 必須讓主 App 與 `com.poyutsai.vibesync.keyboard` 共用 App Group `group.com.poyutsai.vibesync` 與 Keychain group `TTQHTVG8CC.group.com.poyutsai.vibesync`，並建立／更新 provisioning profile。
- `keyboard-reply` 尚未 deploy，未跑 production auth／fresh success／quota 429／rate 429 smoke，1–2 秒 p50 也尚未量測。
- 本版沒有跨網路重試的 durable requestId。若 `increment_usage` 成功後連線斷掉，使用者可能收不到已扣的結果；目前沒有自動 retry，手動再點視為新一次生成。請 reviewer 判斷是否需在 dogfood 前升級為 exactly-once。

## Required Verdict

高風險 auth／quota／Edge schema／prompt 變更。未取得獨立 Codex `APPROVED`、Mac build 與 production smoke 前，不宣稱 dogfood safe。
