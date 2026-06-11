# AI Arbitration Queue

> Shared live queue for Eric, Bruce, Claude, and Codex.
> Keep newest OPEN item on top. This is not a changelog.

## Status Values

- `OPEN`
- `IN_REVIEW`
- `WAITING_ON_ERIC`
- `APPROVED`
- `CLOSED`

## Rules

- One queue item = one decision, handoff, or blocker.
- Update the existing item instead of appending every tiny round.
- Claims about "safe", "better", or "fixed" need evidence: file path, commit, test/log, or runtime observation.
- Product taste and business priority are Eric-final.
- If the result becomes a durable rule, move it into `docs/shared-agent-rules.md`, `docs/bug-log.md`, or `docs/decisions.md`.

---

## Live Queue

## [2026-06-11] ADR #19 字數合併計費 — Codex 設計把關（實作前）
Status: OPEN
Request-Type: review
Raised-By: Claude
Owner: Codex (design review) → Claude (實作) → Codex (實作雙審) → Eric (關閉)
Scope: quota / Edge schema / AI cost（高風險區）— 設計階段，無 code 變更
Branch/Commit: `main` @ ADR #19（`docs/decisions.md`）

Eric 拍板（2026-06-11）：analyze-chat 扣費改全對話字數合併 `ceil(總字數/200)`、整次最少 1。
本 item 是**實作前設計把關**。

**Round 1（2026-06-11）= REVISE_REQUIRED**：
- [P1] 原 fallback「缺 `previousAnalyzedCharCount` 即整段全額計費」使 server-first 不安全（舊 client 補 5 字可能被扣 11 則 / 觸 429）。
- 其餘：quotedReplyPreview 計費定義缺失、UTF-16 需明寫不 normalize、recognizeOnly 日上限需 server-side atomic gate、單一 helper + requestMessages baseline 前提。

**Claude 修訂（同日）**：ADR #19 規格 #1 改三層 fallback（新欄位 → 舊欄位推導 baseline 只扣字數差 → 全缺失才全額+log）、#4 補 normalization/zero-width 定義 + mirror tests、#5 安全論證改依賴推導 fallback、新增 #7 quotedReplyPreview 不計費、#8 單一 helper + baseline 對應 requestMessages、recognizeOnly 閘門明寫 server-side atomic + vision 前擋。

**Round 2（2026-06-11）= REVISE_REQUIRED（剩 1 P1）**：
- [P1] summary/clipped payload：舊 client 長對話壓縮後 requestMessages 可能只剩 10 則但 N=30，原規格把 N>payload.length 當越界全額——對舊 client 是合法路徑，仍會隱形多扣。
- Codex 確認其餘 r1 修訂全部到位（UTF-16/quotedReplyPreview/helper 單一化/requestMessages baseline/recognizeOnly atomic gate）。

**Claude 修訂（同日）**：規格 #1 fallback 加 clipped 分支——N>payload.length 且有 `conversationSummary`/clipped 訊號 → user-safe：baseline=當次 payload 全字數、只扣 floor 1、log `legacy_count_exceeds_payload_clipped`；無訊號才全額+log。已驗證 client clipped 路徑存在（`analysis_service.dart:1080-1287`）。測試矩陣同步加 clipped 案。

**Round 3 確認（2026-06-11）= 設計把關通過，無剩餘 P0/P1**：
> Codex 確認 ADR #19 @ `ee20949`：r2 P1 已補到位，clipped/summary 舊 client 路徑改為 user-safe floor 1 + log；無剩餘 P0/P1。設計綠燈，Claude 可開實作；實作後另跑高風險雙審。

**Round 4 = r3 參數修訂 + 定案（2026-06-11 PM~晚，夥伴新需求 → Eric 全數拍板，規格凍結）**：
- 公式改 `clamp(ceil(字數/40), 1, 10)`、400~2000 緩衝帶一律 10 則、**>2000 一律固定 20 則需確認**（乙案）。
- 預覽改靜態區間文案「依對話複雜度使用 1–10 則」（不再 pre-flight 精確值）；分析後顯示實扣。
- 月額度 30/300/800 不調（cap 10 推理：各層保證次數均高於舊制，原「燒快 5 倍」係忽略 cap 的誤導）。
- 邊界 4 條：額度檢查先於確認框 / client 預警+server 守門（`confirmation_required` + `confirmedOvercharge` 旗標）/ 舊 client >2000 → user-safe cap 10 + log `legacy_over2000_capped` / soft_cap 每次分析各自算。
- r2 三層 compat fallback、字數定義（UTF-16、quotedReplyPreview 不計費）**全部保留不重開**。
- 全文見 `docs/decisions.md` ADR #19 🔴 r3 + 🟢 r3 定案區塊。

**Round 5 = Codex r3 把關第一輪（2026-06-11 晚）= REVISE_REQUIRED（0 P0 / 3 P1 / 2 P2）**：
- [P1-1] 缺 client capability contract：首次分析無 baseline 欄位，新 client >2000 可能被誤判 legacy cap 10、繞過確認。
- [P1-2] legacy cap 10 與 r2 clipped floor 1 有 precedence 衝突，可能把 1 抬成 10、重開隱形多扣。
- [P1-3] `confirmedOvercharge` 未綁 payload、無 idempotency → 確認後內容變更/重送可錯扣或重扣 20。
- [P2] 40/400 邊界重疊；保證次數文字須限定 ≤2000。

**Claude 修訂（同日）**：定案 #6 加 capability contract（`billingProtocolVersion: 3` 必送、無訊號才算 legacy）+ legacy precedence 三段順序（clipped floor 1 永不被 cap 覆蓋）；定案 #5 加確認綁定 `billableChars`/hash（不符回新 `confirmation_required`）+ idempotency key；公式改整數閉區間；保證次數加 ≤2000 前提 + 禁止 pricing/送審文案裸引用。

**Round 6 = Codex r3 把關第二輪（2026-06-11 晚）@ `ad10718` = APPROVED，設計綠燈**：
> 3 P1（capability contract / legacy precedence / 確認綁定+idempotency）+ 2 P2（閉區間 / ≤2000 前提）全數確認解除，無新問題。實作建議：確認綁定優先 payload hash（已記入 ADR 定案 #5）。註：本輪未審 worktree 既存 code 草稿（index.ts / billing.ts）。

**APPROVED 後補遺（2026-06-11 晚 · 夥伴終確認）**：補 **4000 字硬上限**（4001+ 一律 reject「請分批」不扣費、新舊 client 一視同仁；20 則帶收窄為 2001~4000）。背景：pricing-final 原寫 5000 但 code 從未實作（grep 驗證），原緩衝帶上不封頂 = 成本洞。屬風險收斂、無新計費路徑，不重開設計輪，**實作雙審一併驗收**；實作 commit 同步把 pricing-final 5000 改 4000。

**Round 7 = 實作 land（2026-06-11 · Claude）**：

- **Server** `f6e8eec`：billing.ts 全改寫（分段帶閉區間 / capability contract / legacy precedence：clipped floor1 永不被 cap 覆蓋 / legacy >2000 cap10+log）+ index.ts 閘門順序「則數 → 4001+ reject(400 不扣費) → 額度 429 → 功能 403 → 確認 409」+ overcharge_claims.ts idempotency（claim-at-gate，失敗方向 = 用戶免費 user-safe；RPC 不可用 fail closed 503 不扣費）+ migration `20260611120000`（claim RPC，INSERT ON CONFLICT 原子、60min replay window）。pricing-final/cost-optimization 同 commit。死碼清除：index.ts 舊 countMessages + index_test.ts 殭屍複本。
- **Client** `f095603`：MessageCalculator 鏡像 + JS/Dart 共用 fixture 對拍（`test/fixtures/adr19_billing_mirror_vectors.json`，生成器 `tools/billing/`，含 sha256("abc") 外部常數釘）+ 靜態區間預覽 / >2000 確認框（精確 20、額度先行、Free 日上限 15<20 自然擋）/ >4000 本地擋 / 實扣 toast + Hive `lastAnalyzedCharCount`(field 16) + `billingProtocolVersion:3` 全請求必送（wire-contract tests）。
- **測試證據**：Deno 323 passed（billing 41 + claims 5 含內）；Flutter calculator 17 + dialog 13 + notifier/hydration 61 + analyze modes 29 全綠。
- **設計取捨（雙審重點）**：①hash mismatch 不做 client auto-rebind，409 fail-loud 要求重按分析（防拿舊確認綁新內容；mirror 漂移屬 bug 須 fail loud）②4000 上限作用對象 = billableChars（計費字數差），payload 總長另有既有 20000 守門 ③Dart/JS trim 對 U+0085 行為差異 = 已知接受（409 自癒路徑）④replay 時 messagesUsed 回 0（該次呼叫實扣 0，原確認已扣 20）。
- **部署順序**：edge 已隨 push 自動部署（舊 client 走 user-safe legacy 路徑，server-first 安全 = 規格 #5）；**migration 必須在新 App 上架前手動 `supabase db push`**——未套用前新 client 送確認會收 503 不扣費（fail closed，無扣費風險）。

**狀態**：**實作 land DONE → 待 Codex 實作雙審（高風險 quota 區），APPROVED 前不得說 dogfood/build safe**。

Close Condition: Codex r3 設計把關通過 + 實作 land + 實作雙審 APPROVED + Eric 確認後關閉。

---

## [2026-06-10] Style Pair（主+副互動風格）— Codex 把關
Status: OPEN
Request-Type: review
Raised-By: Claude
Owner: Codex (review) → Eric (確認後關閉)
Scope: AI prompt 行為（高風險區）+ Hive schema 演進
Branch/Commit: `main` @ `eebef91`

依 `docs/plans/2026-06-10-style-pair-design.md` 全鏈落地（一個 commit `eebef91`）。
動到高風險區 `EffectiveStylePromptBuilder` → 需 Codex review evidence 才能說 dogfood/build safe。

Review 重點（按風險排序）:

1. **Prompt 回歸**：主-only 輸出 byte-for-byte 不變（`effective_style_prompt_builder_test.dart` 有完整字串快照鎖）；主+副 新格式「以X為主、Y為輔；主全力 prompt。副點綴 prompt」+ 降權措辭是否會被 LLM 平均掉。
2. **Hive 零遷移**：UserProfile field 6 / PartnerStyleOverride field 5；legacy write-only adapter 測試證明舊 binary 讀出 secondary=null。
3. **原子合併**：partner 有主 → (主,副) 整組贏，含「partner 主-only 時全域副不得漏入」防混搭 case。
4. UI 點擊狀態機 5 規則 + 不變量（`style_pair_draft_test.dart`）。

Evidence: 177 targeted tests green（user_profile unit+widget+integration spec2）、`flutter analyze` clean。

Close Condition: Codex review APPROVED + Eric 確認。

---

## [2026-06-09] Pre-Launch UI Audit Round 1 — follow-ups
Status: CLOSED
Request-Type: handoff
Raised-By: Claude
Owner: Eric (decided) / Claude (next-session execution)
Scope: copy / UX / paywall / onboarding / analyze-chat error contract
Branch/Commit: `main` @ `352aebb`

Closed by Eric (2026-06-09): A-01 onboarding wiring DONE + Codex APPROVED (`295bd2d`); P2 analyze.error sanitize DONE + Codex APPROVED (`1a085f4`). 需 TestFlight rebuild 後 dogfood；無 Edge deploy。

Round 1 (low-risk cleanup) DONE + pushed (`b2b6f6c..58ebf71`), all `flutter analyze` clean, 81 targeted tests green:

- COPY-01 額度訊息去「免費」; COPY-02 分析/串流錯誤全去工程語彙; DATA-01 opener 錯誤不漏原始例外; DATA-02 opener loading 教練口吻; B-01 opener SafeArea; C-01 image picker 深底對比; H-03 booster 工程語彙。
- Codex evidence: 3 rounds. `task-mq6hawar` + `task-mq6hf9ct` REVISE_REQUIRED (COPY-02 漏網串流字串) → 已全清。

Eric decisions (2026-06-09):

- **G-03 = CLOSED false positive.** 雷達圖實際存在且 gated Starter/Essential (`analysis_screen.dart:5702`, `// 五維度剖析 (Starter / Essential only)` + `subscription.isPremium`); `dimension_radar_chart.dart` / `partner_radar_summary_card.dart` 渲染; pricing-final/paywall 承諾正確。audit G-03 grep 只搜 `lib/features/report` 故誤判。不改 code/docs。
- A-01 onboarding + analyze.error sanitize 不混入本輪低風險 cleanup。

Action Items (next session, each its own scoped task + Codex review):

- [x] **A-01 onboarding wiring** — DONE @ `295bd2d` (pushed). post-login first-run，未登入 auth gate 維持同步不變。redirect 決策抽成純函式 `resolveAppRedirect`（`routes.dart:34`）+ `OnboardingService.isCompletedSync` 記憶體快取（`main()` 啟動時 `load()` 預載，避免回訪用戶冷啟動被誤導回 onboarding）。Tests: 17 redirect-matrix unit + 6 router widget 全綠；`flutter analyze` clean。Codex read-only review = **APPROVED (no P0/P1/P2)**，逐項驗證 5 條 invariant + 無 redirect loop + 快取 ordering 正確。（注：`onboarding_test.dart` demo enthusiasm label 失敗為既有 stale rot，clean main 亦失敗，非本次 regression。）
- [x] **P2 analyze.error 伺服器 message sanitize** — DONE @ `1a085f4` (pushed)。`analysis.error` 串流事件改走既有 `_isReadableUserMessage` 閘門（含中文才顯示，與 HTTP 路徑 `_mapAnalysisHttpError`、opener DATA-01 同一套），非中文/工程字串回固定繁中 fallback「這次分析沒順利完成，請稍後再試一次。」；raw message 改走 `_debugLog`（僅 kDebugMode），不進 UI。只重寫 `message`，`code`/`recoverable`/`retriesRemaining` 原封不動，quota/paywall 路由不被誤吃。未改 Edge Function、未改 quota 邏輯、未加「不扣額度」承諾。Tests: 既有 `'Quota failed'` 測試改為驗 fallback + 保留 code/retries，另加 可讀中文原樣／JSON 片段→fallback／缺 message→fallback 共 4 分支，全綠（28 passed）；`flutter analyze` clean。Codex read-only review (`task-mq6m4gzz-airaso`, scope `23cc3a0..1a085f4`) = **APPROVED (no P0/P1/P2)**，逐項驗證 sanitizer + 測試 + Edge emitter/contract（`analyze-chat/index.ts`、`stream_handler.ts`、`reframer.ts`）。（注：`analysis_error_widget_test.dart:135` `parses RATE_LIMITED code` 失敗為既有 stale rot，clean `23cc3a0` 亦失敗，非本次 regression。）

Close Condition:

- 兩個 action item 各自 land + Codex 評估，Eric 確認後關閉。

---

## [2026-06-07] Preflight Secret Gap + 409 Coverage (C5/C6)
Status: OPEN
Request-Type: decision
Raised-By: Codex
Owner: Eric (decided) / Claude (carry follow-ups)
Scope: subscription / 429 / ops / launch-hardening
Branch/Commit: `main` @ `9cf72ad`

Decision (Eric-final, 2026-06-07):

- **C1 (P1)** — fixed in `9cf72ad`. No remaining code-level P0/P1 per CC second review.
- **C5** — Eric accepts short-term option (a): GitHub secret smoke + Supabase secret-name check + manual GitHub ↔ Supabase sync discipline.
- This is **accepted debt, not "safe / launch-safe"**: the shipped preflight still cannot verify the Supabase live secret *value*.
- **C6** — handler-level 409 integration test deferred as **P2**. Helper / source / stream tests pass; the 409 gate still lacks handler-level coverage.

Explicit non-claims:

- Do NOT claim safe dogfood / safe build from this code review alone.

Action Items (deferred to launch / App Review final hardening — do NOT open in red zone):

- [ ] Add post-deploy **live runtime probe** that verifies the Supabase live secret value (closes the C5 gap).
- [ ] Add **handler-level 409 integration test** (C6, P2).

Close Condition:

- Both follow-ups landed and Eric confirms launch-hardening for this scope is complete.

---

## [2026-05-14] Dogfood Frontline Stabilization
Status: OPEN
Request-Type: handoff
Raised-By: Codex
Owner: Claude
Scope: bug / ops / review
Branch/Commit: `main` @ latest

Question:

- Eric and Bruce are dogfooding TestFlight. Claude/CC should handle first-line bug reports, while Codex provides read-only review for high-risk fixes.

Current Product Truth:

- Coach 1:1 is shipped into dogfood.
- Current phase is TestFlight dogfood / App Review stabilization.
- Do not treat archived roadmap labels or old planning tracks as current default work unless Eric explicitly asks.

Recent Context:

- Opener, paywall, quota, RevenueCat, and subscription sync have had repeated P0/P1 fixes.
- 2026-05-15 Eric accepted keeping the `restorePurchases()` paid-to-free snapshot guard during dogfood; do not "fix" it without an explicit new decision. See `docs/integrations/revenuecat.md`.
- 2026-05-15 auth/logout/delete-account local cleanup patches were reverted after repeated Codex `REVISE_REQUIRED` loops. Do not patch that scope again without a design/failure matrix.
- 2026-05-15 Support URL finding was closed by live evidence: `curl -I -L https://vibesyncai.app/support` returns 301 -> 200 OK.
- `!cc-rotate` is implemented for mobile session rotation.
- `!codex` Phase 1 is implemented as a read-only Discord review gate.
- WSL Codex CLI may still need one-time `codex login --device-auth`; verify with `!codex setup`.

High-Risk Areas:

- subscription / paywall / quota / RevenueCat / 429
- auth / account deletion / Hive persistence
- `analyze-chat` / opener / OCR / Edge response schema
- AI prompt changes affecting quality, safety, token/cost, or App Review stability

Operating Rules:

- If Bruce or Eric reports a bug, acknowledge the reporter and ask for missing repro details if needed.
- For screenshots: inspect and fix if repro is clear.
- For videos: ask for key screenshots, timestamps, expected vs actual, and steps before deep judgment.
- If Eric says "queue it", append the pending intake under this item instead of inventing root cause.
- After a high-risk hotfix commit/push, trigger Codex review before saying it is safe to build/test.

Evidence:

- `docs/snapshot.md`
- `docs/shared-agent-rules.md`
- `git log --oneline -30`
- `docs/bug-log.md` newest 2026-05 entries
- `tools/cc-rotate/README.md`
- `tools/codex-bridge/README.md`

Open Risks:

- RevenueCat sandbox and product mapping still need real-device matrix smoke after each paywall/subscription change.
- Free users must be able to use opener/analyze/coach until quota is actually exhausted.
- Opener/analyze must never show raw JSON.
- Format failure must not charge quota.
- Auth/logout/delete-account/local Hive isolation remains baseline behavior and needs design-first treatment before launch hardening.

Action Items:

- [ ] Keep first-line dogfood bug intake here when Eric is mobile.
- [ ] For high-risk fixes, run Codex review on the actual hotfix range, not blindly `latest`, and record the job/result.
- [ ] Close this item only after Eric says the current dogfood stabilization window is complete.

Close Condition:

- Eric confirms the current TestFlight dogfood bug wave is stable enough to move on.

---

## Recently Closed / Reference

Closed items before 2026-05-14 were intentionally pruned from this live queue. Use git history and `docs/reviews/` files for older review records.
