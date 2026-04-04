# Security Hardening Status

最後更新：2026-04-05

用途：
- 這份文件用來快速說明 VibeSync 目前的資安/隱私硬化進度。
- 它不是完整架構設計，完整背景仍看 `docs/security-architecture.md`。
- 這份更偏「現在做到了哪、還差什麼」。

## 目前已完成的硬化

### 1. 機密資料留在後端

- `CLAUDE_API_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- RevenueCat 伺服器端 API key

這些都只應存在：
- Supabase secrets
- GitHub Actions secrets
- 其他受控部署環境

不應出現在：
- Flutter client
- repo 內的硬編碼 fallback

### 2. 本地對話資料有加密

- 對話、settings、usage 目前都使用 Hive + `HiveAesCipher`
- 加密金鑰存放在：
  - iOS Keychain
  - Android secure storage / keystore 對應層

### 3. AI 日誌已做敏感欄位遮罩

`ai_logs` 不會直接存完整：
- messages
- content
- images
- conversation
- userDraft
- sessionContext

而是會做 redaction / truncate。

### 4. User-facing Edge Functions 改回平台級 JWT 驗證

目前這些 function 部署時應使用 Supabase 預設 JWT 驗證：
- `analyze-chat`
- `delete-account`
- `sync-subscription`
- `submit-feedback`

只有 `revenuecat-webhook` 因為是第三方 webhook，才維持 `--no-verify-jwt`。

### 5. RevenueCat webhook 不再整包保存 raw payload

`webhook_logs` 現在只保存精簡後的欄位，例如：
- type
- app_user_id
- product_id
- new_product_id
- entitlement_ids
- transferred_from / transferred_to
- expiration_at_ms
- environment

目的：
- 降低不必要的資料留存
- 保留營運排查需要的核心欄位

### 6. 移除 repo 內 RevenueCat server key fallback

`sync-subscription` 現在若沒設定 RevenueCat API key，會直接回 server misconfigured，
不再偷偷使用 repo 內 fallback。

## 目前仍存在的風險 / 技術債

### 1. Anthropic API retention 仍需誠實揭露

目前產品敘事不能寫成「聊天內容絕對不會離開裝置」。

更精準的說法應該是：
- App 本身不長期保存聊天內容於自家伺服器
- 但分析時會把必要內容傳到 Anthropic API 處理
- Anthropic API 的商業產品預設有資料保留期（官方目前標準為 30 天，除非另有 zero retention agreement）
- 官方也說商業/API資料預設不拿來訓練模型

所以：
- Privacy Policy
- App Store disclosure
- App 內文案

都應該用一致、誠實的寫法。

### 2. `auth_diagnostics` 仍可由 anon insert

這讓註冊/忘記密碼前的診斷 log 能成立，
但也代表這張表理論上可被濫灌。

後續可考慮：
- 改成 Edge Function 寫入
- 加速率限制
- 加定期清理 / retention

### 3. 還缺正式 retention policy

目前建議至少定義並執行：
- `auth_diagnostics`
- `webhook_logs`
- `ai_logs`

的保留週期與清理方式。

### 4. 部署權限仍偏集中

目前官網部署在夥伴個人 Vercel，
短期可接受，但中長期應避免：
- domain
- env
- deploy 權限

只綁定單一個人帳號。

## 現在的安全等級判斷

如果以「獨立開發 + 早期產品」來看：

- 已經比很多純 vibe coding 直接上線的產品更安全
- 但還不到高信任、高合規等級

目前判斷：
- 早期公開測試 / limited launch：可接受
- 若要強調高度隱私與高度安全：還需要繼續補強

## 下一輪最值得補的 5 件事

1. 為 `auth_diagnostics` 加 rate limit / retention
2. 定義 `webhook_logs` / `ai_logs` / `auth_diagnostics` 保留週期
3. 將隱私政策與 App Store disclosure 明確寫出 Anthropic API 處理與 retention 事實
4. 整理正式 incident response SOP（密鑰輪替、停用 function、通知流程）
5. 將官網 / 後台 / 部署權限從單人帳號模式改成團隊可交接模式
