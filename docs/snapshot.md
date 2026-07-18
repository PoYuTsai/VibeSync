# VibeSync Snapshot

> Rewrite when the project phase changes. This file is the current-state anchor for Claude/Codex sessions.

## 2026-05-14 Current Focus Guardrail

Rotate / new sessions must treat this file plus `git log --oneline -15` as the source of truth.
Old chat memory, Claude persisted output, and terminal screenshots are supporting context only.

Do not revive archived roadmap labels or old planning tracks unless Eric explicitly asks.

Current state:

- Coach 1:1 is shipped into dogfood and is part of the core product.
- Older spec discussions are product fuel, not active task labels.
- Consumer-facing headline: `你專屬的 AI 約會教練`.
- Internal moat: VibeSync remembers the person, conversation, user intent, and coaching context, then helps users converge on a better next action.
- We are in TestFlight dogfood / App Review readiness stabilization.

Default priority:

1. P0/P1 dogfood bugs from Eric/Bruce.
2. Subscription, quota, RevenueCat, 429, paywall upgrade/downgrade safety.
3. Opener, analyze-chat, Coach 1:1 quality and UX stability.
4. App Review / launch-readiness cleanup.
5. Workflow tooling such as `!cc-rotate` and `!codex`.

## Recent Stabilization Train

Recent commit themes, newest first:

- Analyze 串流與進度 UX 穩定化（2026-07-19）：Essential 五風格在 Sonnet 5 上沿用舊 `3200` output cap，真機輸出剛好寫滿後被標成 `STREAM_MAX_TOKENS`；Free 兩風格維持 `3200`，付費五風格提高為 `6000`，production `analyze-chat` v285（`verify_jwt=false`）同步記錄 120 秒 timeout／3 次 provider attempt。101 則訊息的 live contract smoke 完成五種核心風格與 `analysis.done`，用量 2546/6000、未扣 quota。App 端分析時「跟到最新」會持續顯示，點擊後跟隨目前串流，使用者往回滑即停止；中斷後保留「查看中斷」。OCR 左右歸屬提示改為延遲 650ms、示範 3.6 秒，之後保留靜態圖例。Practice v200 與 DeepSeek-first 路徑未變。驗證：Analyze Edge 643/643、相關 widget 69/69、OCR widget 28/28、Flutter 全套 2265 passed／4 skipped／0 failed、`flutter analyze` 0 issue，獨立複查 0 blocking/P2。

- Build 334 Sonnet 5 穩定化（2026-07-18）：Build 333 升級 Sonnet 5 後，OCR／文字串流未適配其預設 adaptive thinking；隱藏思考可能吃完共用 output budget，舊 OCR 又只讀第一個 content block，造成長等、空回應與重試風暴。OCR 現在遍歷可見 text blocks、使用 structured output 並限制為單次 provider／client 嘗試；Sonnet 5 文字串流則明確關閉 thinking，4.6／Haiku 行為、Free 兩風格、付費五風格、quota 與扣費均不變。Production `analyze-chat` v277 雙圖 OCR 一次成功（18 則、28.5 秒），v278 付費五風格 stream 一次完成（15 events、32.4 秒、2175/3200 output tokens）；Edge 617/617、Flutter analysis 69/69，兩輪獨立 review 均 0 P0/P1/P2。Build 333 不再作為測試基線，下一個真機候選為 `1.0.1+334`。

- Build 333 產品校準（2026-07-17）：Free `analyze-chat` 回覆從單一延展改為固定產出延展＋調情兩種，保留共鳴／幽默／冷讀作為付費完整五種差異；Free Opener 仍只有延展。對方這次的投入度在完成回應層統一改為 `ceil(AI 原分 × 0.9)`（例 82 → 74），不改 prompt、AI 理由或回覆選擇。OCR 確認視窗每次開啟都會自動播放一次左右滑動教學；長 OCR 等待以準備／上傳／讀圖／辨識訊息／校對說話者／整理結果狀態切換，不傳輸中間分析內容。原定 Build 332 實際由舊 `main@1c4992be` 建置，未包含本輪功能；第一個完整 binary 改為 Build 333，release preflight 會拒絕 source version 與 run number 不一致的 ref。

- AI 鍵盤恰一次結算（2026-07-17）：extension 以共享 Keychain 分指紋原子保存、綁 user＋文字＋風格的 durable UUID（重試資格約 23 小時，多筆／多帳號在途不互蓋）；`keyboard-reply` 先以 DB claim／lease 序列化模型呼叫，再由原子 RPC 同交易保存結果與扣 1。Server replay window 為 24 小時、每小時清理，input identity 使用 user-bound server-keyed HMAC。Production 已依 DB migration `20260717120000` → 32-byte HMAC secret → JWT-verified Edge v6 順序部署，live contract、DB transaction 與測試帳號 fresh／replay／mismatch smoke 通過且零殘留。發布仍 blocked 於 signed iOS keyboard、非測試 quota／HTTP 並行與 lost-response、公開隱私更新，以及 LINE／Instagram／Messages Full Access 真機矩陣。

- Sonnet 5 production 主路由定案（2026-07-18）：所有客戶可見 Claude primary（Free／付費 Analyze、Opener、Coach／Follow-up、Keyboard 與圖片）都使用 Sonnet 5。`analyze-chat` 的 4.6 → Haiku 只在上游 timeout／429／5xx 等真正中斷時降級；截斷、拒答與 context-window stop 一律 fail closed。Practice 明確不改，仍以 DeepSeek 為第一供應商並保留既有 tiered Claude failover／reviewer。Production Analyze v283／Coach v62／Follow-up v55／Keyboard v6 已部署，Practice v200 未動；Opener／Quick／Coach／Follow-up、stream 與 OCR 1–3 張 live smoke 全綠。Keyboard 使用 24s server／30s client／45s lease；一般分析與 OCR 沒有 durable requestId 時不做背景重送，避免 lost-response 重複扣額。
- 已知非阻斷營運債（2026-07-18）：管理端成本圖目前只從 `ai_logs` 彙總；Coach／Follow-up／Keyboard 尚未寫入 Anthropic token usage，因此總 AI 成本會低估。另 Coach／Follow-up 尚無 durable requestId＋結果 replay，扣額後若網路中斷可能遺失卡片，手動重送仍可能再扣；這兩項不得被描述成已完成 exactly-once／完整成本監控。

- Fable 5 回饋收斂（2026-07-16）：當次互動分數改成投入度語意；Coach 回答層級收合並改為只串流真實系統進度；空白對象／截圖續接與 Opener 三圖流程已修正。「我幫你修」成功固定扣 1，並以 owner-scoped durable requestId、原子 result/charge 與 7 天 live replay 防止新版 App 重複扣費。獨立 review、線上隱私政策、migration、Edge 與 live fresh/replay/mismatch smoke 均完成；同 commit 的 iOS／Android staging build 已成功上傳 Firebase App Distribution，下一關是真機 dogfood。舊 App 無 durable requestId，仍只有固定扣 1、沒有 exactly-once 保證。
- Analyze-chat 獨立分析紀錄（2026-07-15 起）：主畫面只顯示 current／pending 片段，舊成功案例由對象頁／分析頁右上封存入口開啟；每筆 owner-scoped、自足快照、無 FIFO、手動刪除。`metVia` 與每筆 `sourcePlatform` 分開；未知來源留在「全部」但不露出「未分類」，平台篩選只在至少兩種已知來源時出現。原整段封存改稱「已收起的對話」並降為抽屜次入口。cleanup marker＋tombstone 保護刪除，冷啟動 repair 失敗時禁止覆寫 canonical snapshot。AI request、prompt、quota、billing 不變；client-only，不需 Edge／DB deploy。

- Practice Hint／Debrief generated-only train（2026-07-11，branch `codex/no-canned-practice-ai`）：Beginner＋Game 共用 DeepSeek 12s → Claude 12s、逐欄品質閘與 Hint decision lineage；雙失敗不再把 fallback 當成功、不扣費不計次。local Deno 746/746、Flutter 516/516，SQL／client／兩路 backend gate 皆 0/0/0；等待 Edge-first deployment 與 TestFlight。
- Analyze-chat full streaming is the current product path. The old user-visible two-stage quick/full plan is superseded; frontend legacy naming cleanup landed in `d12009e`. Backend `quick/full` compatibility remains hidden rollback / old-client support only.
- `!codex` Phase 1 read-only Discord review gate: `dfde5f2`, `ec84bb0`.
- `!cc-rotate` external/mobile session rotation and bootstrap hardening: `80ce48a` through `abd8200`.
- CC dogfood handoff, queue, and current-state correction: `8b748c4`, `050f50e`, `e111550`, `128879f`, `2f72839`.
- Opener/paywall/quota/RevenueCat P0 fixes:
  - `6b18863` Free quota thresholds.
  - `4184c75`, `7c19994`, `1f49470` opener/analyze malformed JSON protection.
  - `26790b4` format failure no quota charge.
  - `4954581` paid tier cannot regress to Free on transient RevenueCat miss.
  - `a01cb0f`, `6dc38a2`, `54c0906` Paywall package mapping/fallback fixes.
  - `f0546c0`, `ce4aa9e`, `e660bcd` RevenueCat client key and paid quota sync.
  - `5f267c5` opener draft/save path.

If a new session sees older memory claiming an archived roadmap label is the current track, override it with this snapshot.

## Active Risk Areas

High-risk changes require Codex review before telling Eric/Bruce the build is safe to test:

- subscription, paywall, quota, RevenueCat, 429
- auth, account deletion, Hive/local persistence
- `analyze-chat`, opener, OCR, Edge response schema
- AI prompt changes that affect reply quality, safety, or token/cost behavior

Free user rule:

- Free users must be able to try core features until monthly/daily quota is exhausted.
- When exhausted, show a clear quota/paywall path.
- Do not accidentally block first-use opener/analyze/coach before quota is actually consumed.

RevenueCat rule:

- App client uses public `appl_` SDK key.
- Server/Edge uses secret RevenueCat key.
- Paid tier must not be downgraded to Free just because RevenueCat temporarily returns empty or delayed entitlement data.

Paywall rule:

- Monthly/quarterly products must map by exact product/package id.
- Do not use fuzzy title matching.
- Upgrade/downgrade behavior must be safe for all Free/Starter/Essential monthly/quarterly paths.

Opener rule:

- Opener is a "pioneer" feature: generate a useful first move, cache/save the paid result, and make the next step into analyze-chat/Coach 1:1 clear.
- If AI returns raw JSON or malformed schema, repair/retry and do not show raw JSON to users.
- Format failure should not charge quota.

Coach 1:1 rule:

- Coach should be practical, grounded, non-judgmental, and on the user's side.
- It can discuss dating escalation, nightlife, sexuality, short-term intent, and safety maturely.
- It must still maintain consent, boundaries, STI/contraception, and personal safety reminders without becoming preachy.

Analyze-chat rule:

- Current analyze-chat UX is full streaming analyze. Do not revive the old two-stage quick/full UX unless Eric explicitly reopens that decision.
- Client display separates each successful analysis into a self-contained record. The current/pending fragment stays on the main screen; only older successful records appear in the top-right analysis archive.
- Records have no FIFO and require manual deletion. `metVia` is partner-level; source platform is snapshotted per record and never guessed by OCR.
- The primary archive entry is the partner page's top-right box icon (the analysis page keeps a shortcut). Unknown source records stay in All without an “uncategorized” label; deletion lives in the read-only snapshot overflow menu.
- This record feature must not alter AI request messages, prompt, quota, billing, or Edge behavior.
- Existing backend `responseMode: quick/full` and `analysis_runs` artifacts are compatibility / rollback surfaces, not the official user-visible analyze design.
- Reply suggestions should read the actual conversation.
- Prefer "接住情緒 -> 互動感 -> 順勢延伸" over summary-like suggestions.
- For multiple incoming messages, identify catchable points and when useful suggest split replies; not every point needs a reply.

## Current Workflow State

External/mobile mode:

- Discord listener runs via tmux / `~/.claude/channels/discord-vibesync/start.sh`.
- Use `!cc-rotate` to handoff and start a fresh CC session when context approaches the orange/red zone.
- `!cc-rotate` must read this snapshot, shared rules, newest OPEN queue item, latest handoff, and recent commits before taking work.
- Codex review is the read-only review gate. Codex does not edit files in external mode.
- Default 2026-06-26 workflow: Claude/CC does not self-trigger Codex as part of its own fix/feature flow. Claude/CC prepares a review packet; Eric routes it to a separate Codex review thread for the double-check. Direct `!codex review ...` from CC is opt-in only when Eric explicitly asks for that run.

Known setup note:

- Codex CLI in WSL may need one-time login: `codex login --device-auth`.
- Verify with `!codex setup`.

## Validation Baseline

Recent targeted validations have included:

- `flutter analyze` after major Flutter changes.
- opener service/cache unit tests.
- targeted Edge Function tests around schema, quota, and malformed JSON.
- local bridge tests for `!cc-rotate` and `!codex` wrappers.

Before claiming a fix is safe, state what was actually tested. Do not imply full regression if only targeted tests ran.

## Next Default Action

When Eric or Bruce reports a bug:

1. Acknowledge the specific reporter and symptom.
2. Ask for missing repro details if needed: build number, account/tier, expected vs actual, screenshots, exact steps, reproducibility.
3. Investigate root cause.
4. Fix only the scoped issue.
5. Run targeted tests.
6. Commit + push.
7. If high risk, trigger Codex read-only review before saying "safe to build/test".
