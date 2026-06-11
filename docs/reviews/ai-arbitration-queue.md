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

## [2026-06-12] #12 一球一回 replySegments 實作 — Codex 實作雙審
Status: OPEN
Request-Type: review
Raised-By: Claude
Owner: Codex (實作雙審) → Eric/Bruce (APPROVED 後 dogfood)
Scope: analyze-chat prompt/schema + sanitizer（高風險區）— **server only，client 零變更**
Branch/Commit: `main` @ `1fd4f5c` + `a6bc654` + `4143895` + `b91ee77` + `0a39621`；計畫 `docs/plans/2026-06-12-reply-segments-implementation.md`；設計 `docs/plans/2026-06-11-reply-segments-one-ball-one-reply-design.md`（設計把關 r2 APPROVED @ `435e6a1`，cap 3）

**實作內容（依設計七點規格）**：

1. **Sanitizer 三層缺 source 規則**（`1fd4f5c` + `a6bc654`）：`post_process.ts` 新增 `extractPartnerBallList`（球清單 = trailing partner run，1-based；vision 優先 `result.recognizedConversation.messages`；run 空時回退最近 10 則對方訊息）+ `enforceReplySegmentSourceContract`（①sourceIndex 缺/越界 → sourceMessage 正規化文字回查修復（exact → 雙向 substring、≥4 字门槛）②修不回 → drop 該段 ③全 drop → content 回退 drop 前換行合併版，絕不空 source 流出）。接線 `ensureNonEmptyAnalysisOutput` + `postProcessAnalysisResult` Step 3 兩處輸出點；`index.ts` 三呼叫點（:6395 full / :6677 stream markDone / :7159 legacy+vision）傳 `requestMessages`。contract 只在 `!recognizeOnly && !isMyMessageMode` 啟用。球清單不可得時防衛路徑只驗形狀（sourceIndex≥1 + sourceMessage 非空）不驗範圍。
2. **SYSTEM_PROMPT 條件式 → 強制式**（`b91ee77`）：§1.5 改「一球一回」——≥2 顆值得接的球**必須**分開回、每球一段、cap 3 挑互動價值最高、每段必填 sourceIndex（她這輪連發第幾句，1-based，與 server 球清單同語意）+ sourceMessage、各段獨立成立、content 仍填換行合併版（規格 #4）；「同一情緒/生活片段算同一顆球」防過度拆段。§1.2 範例消滅兩球串一句示範；§1.3 加指向 + 五句連發=同一行程球註記；§1.5 範例升級三球三段（Bruce golden case 同構）；vision Multi-Message Reminder（:1135）鏡射強制式；schema 範例擴 2 段。
3. **Stream contract 堵 compact 掉段**（`0a39621`）：偵察發現 streaming（現行產品路徑）segments 唯一通道 = `analysis.done.finalResult`，而舊 contract「compact finalResult」是反向拉力 → 明定多球時 `finalResult.finalRecommendation.replySegments` REQUIRED、Never omit to save tokens。
4. **規格 #4 已存在**：content 換行 join 本來就在（`post_process.ts` 兩處 `join("\n")`），新增測試上鎖。

**測試證據**：Deno 全套 **335 passed**（新增 sanitizer 7 + 接線 2 + 換行 join 1 + stream contract 1 + index_test 字串鎖更新）；style-pair 鎖 `effective_style_prompt_builder_test.dart` **10/10 原樣通過**——本案只動 server prompt，client builder 一字未碰，**byte-for-byte 鎖實際未破**（比設計文件保守假設的「知情破鎖重立基準」更強，如實記載）；quick mode 測試零變更通過（quick 用獨立 `QUICK_SYSTEM_PROMPT`，規格 #3 天然成立）。

**過程透明**：`a6bc654` 曾帶著 index_test 一個紅燈 push（字串鎖釘舊接線 `replySegments: safeRecommendationSegments`），同分鐘內 `4143895` 修復——紅燈期間僅字串鎖測試紅，無行為缺陷；prod 部署的 code 本身一致。

**審查重點建議**：

1. 球清單語意：trailing partner run + 空 run 回退最近 10 則——「我已回一半再分析」案例的 sourceIndex 語意是否可接受（index 對 run 計，回退清單時可能與模型認知偏移；display 主鍵是 sourceMessage，`analysis_screen.dart:4372`）。
2. Contract 誤殺風險：文字回查的 ≥4 字 substring 門檻、短訊息（「好啊」「哈哈」）球的修復成功率；防衛路徑（球清單空）只驗形狀是否夠保守。
3. 三層回退與既有 precedence 互動：`replies[pick]` 優先於 segment 合併版（既有行為，測試已釘）；全 drop 時 content 用 drop 前合併版的位置（ensureNonEmpty :segmentMappedContent / Step 3 :segmentRecommendationContent）是否漏。
4. Prompt 一致性：§1.2/1.3/1.5/vision reminder/schema 範例五處同步後有無殘留反向拉力（「精簡」「一句總回」類指令）；§1.3 ✅ 範例與強制式的「同一片段=同一球」調和是否清楚。
5. Stream contract 措辭是否會讓模型在單球時硬湊多段（regression 方向：N=1 不變）。
6. Golden case（行程/電量/吃飯三球 → 3 段）為 **TF 行為驗收**，單元測試只能鎖 prompt 字串與 sanitizer——server-only 變更已隨 push 自動部署，**現有 TestFlight build 即可測**（client 零變更，無需新 build）。

**Round 1（2026-06-12）= REVISE_REQUIRED（0 P0 / 0 P1 / 2 P2）**：
- [P2a] 規格 #4 claim 不成立於常見路徑：Step 3 `replies[pick]` 優先於 segment join——模型 replies 仍逗點大句而 segments 正常時，舊 client content 還是逗點串；原測試用 `recognizeOnly: true` 繞過常見路徑，證據力不足。
- [P2b] source contract 漏交叉驗證：`sourceIndex` 合法時不檢查 `sourceMessage` 是否真屬該球——錯位引用/幻覺引用可流出（UI 引用主鍵是 sourceMessage）。
- Codex 驗證成立的 claims：球清單三模式抽取 / contract gating / 三呼叫點接線 / prompt 五處同步無殘留反向拉力 / quick 獨立不動 / Deno 335 全綠（Codex 自行重跑）。Flutter style-pair 鎖因 sandbox 唯讀無法重跑，採實作方證據。

**Claude 修訂（同日 `b14ea0c`）**：
- P2a：兩輸出點（ensureNonEmpty + Step 3）改「contract 後 ≥2 段且 pick 未 remap → content = 段落換行 join」；單段維持既有 precedence（守規格 #2 N=1 現狀）。contract 段只可能來自 pick 未 remap 的 preferred segments 或 safe pick 自己的 replyOptions messages，無 pick 錯配風險。
- P2b：indexValid 時交叉驗證——message 與 index 球不符 → 回查別球修 index（message 是 UI/#13 主鍵，信 message）；全都匹配不到（幻覺）→ 以 index 球 canonical 回填 sourceMessage。兩方向都保證流出真實引用。
- 測試：新增 5 案（P2a 多球 join + N=1 guard；P2b 修 index / canonical 回填 / fragment guard）；全套 **340 passed**。

Close Condition: Codex 實作雙審 APPROVED + golden case Bruce TF 實測（一球一回體感）+ Eric 確認。APPROVED 前不得對 Bruce 說 dogfood safe。

---

## [2026-06-11] Smoke 兩修（quota 429 分流 + 實扣常駐）— Codex 實作雙審
Status: APPROVED（Codex r2 2026-06-11 — 0 P0/P1/P2；r1 兩 P2 驗證解除。可回 Bruce；⚠️ client 修須新 TestFlight build 才測得到）
Request-Type: review
Raised-By: Claude
Owner: Codex (實作雙審) → Eric/Bruce (APPROVED 後 dogfood)
Scope: quota / paywall / 429 / analyze UI（高風險區）— client only，server 免改
Branch/Commit: `main` @ `de7b1bb`（P1）+ `12b5895`（P2）；計畫 `docs/plans/2026-06-11-smoke-quota-display-fix.md` @ `d8604ae`

**P1（de7b1bb）quota 429 分流升級卡**：
- 根因鏈：retryFull 撞 429 保留 preview → failedAfterRecommendation → `_streamRetriesRemaining` 對 upgrade 落 0 → 「無法再重試」；legacy `_runFull` generic catch 同病。
- **計畫外發現**：ADR #19 `buildQuotaExceededPayload` 無條件雙 limit，client 三處 429 解析 `dailyLimit != null` 先判 → 月爆誤報日。修法：收斂單一 `_quotaExceptionFrom429`，雙 limit 用 `monthlyRemaining < quotaNeeded` 判別（server 月先查），無法判別偏 monthly；exceptions 補 `remaining`/`quotaNeeded`。
- notifier `QuotaExceededInfo` 入 state（兩條失敗路捕獲、全清空點配對）；UI 分流 `QuotaExceededUpgradeCard`（剩 N/需 M + 查看方案接 `_showPaywall`）。

**P2（12b5895）實扣顯示常駐**：
- `AnalysisUsageSummaryLine` 常駐結果區，讀 `rawResponse['usage']`（隨快照持久化，回看顯示）；顯示條件與 SnackBar 一致；「剩餘」為快照當下值（已註記非即時）。

**測試證據**：notifier quota 6 案 + service 雙 limit 判別 3 案 + widget 升級卡 3 案 + 常駐行 6 案；targeted 全綠；`flutter analyze` 乾淨（僅既有 `test/visual_proof` info）。

審查重點建議：429 判別 heuristic 的邊界（opener 雙 limit + quotaNeeded=0、remaining 缺失 fallback）、quotaExceeded 清空點是否漏（殘留舊卡）、P2 顯示條件與 hydration 去重互動、快照 remaining 過期語意是否可接受。

**Round 1（2026-06-11）= REVISE_REQUIRED（0 P0 / 0 P1 / 2 P2）**：
- [P2] fresh-start quota 429（failedBeforeRecommendation）notifier 有設 quotaExceeded 但 screen 兩個 handler 沒鏡射 `_quotaExceededInfo` → 不顯示新升級卡（仍走舊 error 卡 + paywall，不會回到「無法再重試」，但分流不完整）。
- [P2] `_showPaywall` 無重入防護，quota 卡新增高頻入口，快速連點可 push 多個 paywall route。
- Codex 驗證成立的 claims：429 heuristic 對 server 三種 payload（單 monthly/單 daily/雙 limit）正確；opener 429 走 OpenerService 自己解析、不受影響；quotaExceeded 清空點主路徑完整；failedAfter 卡互斥正確；P2 顯示條件與 SnackBar 一致、Map round-trip 安全。

**Claude 修訂（同日）**：兩個 failedBeforeRecommendation handler（hydrate + live）quota 分流——非 null 時設 `_quotaExceededInfo` + `_resetErrorState()`（不走 generic error 卡），render gate 擴 `_fullErrorMessage != null || _quotaExceededInfo != null`；`_showPaywall` 加 `_isPaywallInFlight` guard（try/finally 復位）。targeted 42 案重跑全綠。

**Round 2（2026-06-11）= APPROVED（0 findings）**：Codex 驗證 r1-P2a/P2b 解除——before-rec 兩 handler 對稱鏡射 + `_resetErrorState` 無 banner 死路（`analysis_screen.dart:785-810/:3674-3700/:5119`）、render gate 與卡片互斥正確（:5810-5826）、`_isPaywallInFlight` guard try/finally 復位且覆蓋全部 11 個 `_showPaywall` 呼叫點（:216-227 + :271/:614/:2564/:3703/:3729/:3790/:3797/:3805/:5823/:6165/:6391）。

Close condition 達成：APPROVED → 回 Bruce。最終 commits：`de7b1bb`（P1）+ `12b5895`（P2）+ `e241471`（r1 修訂）。

---

## [2026-06-11] 候選 #12 一球一回 replySegments — Codex 設計把關（實作前）
Status: APPROVED（Codex r2 設計綠燈 2026-06-11 — 0 findings，r1 四項全數驗證解除；實作另開 item 走高風險雙審）
Request-Type: review
Raised-By: Claude
Owner: Codex (design review) → Eric/Claude (依結論定實作)
Scope: analyze-chat prompt/schema（高風險區）+ 破 style-pair byte-for-byte 鎖（eebef91）— 設計階段，無 code 變更
Branch/Commit: `main` @ `728f670`（設計定案文件）

**請 Codex 審**：`docs/plans/2026-06-11-reply-segments-one-ball-one-reply-design.md`（46 行，含七點規格 + client 現況事實 + #13 接口預留）。

審查重點（依設計文件）：

1. 七點規格有無設計層面的洞——特別是 #1（cap 4 溢出挑球規則是否會讓模型輸出不穩定）、#4（舊 client fallback 改換行 join 的相容性）、#5（prompt 目標式 audit 範圍是否足夠/過寬）。
2. **破鎖風險**：prompt 變更破 style-pair 主風格 byte-for-byte 鎖（2026-06-10 eebef91）。設計文件已明寫知情破鎖 + 重新驗證義務（規格 #6）；請確認驗收清單（golden case 3 球 3 段 + N=1 回歸 + quick 不變 + style-pair 重驗）是否完備。
3. #13 接口預留（每段穩定非空 `sourceMessage`/`sourceIndex`，schema 層驗證）是否足以支撐「採用回填」而不過度設計。
4. Client 現況事實已驗證（`ReplySegment` model + 分段渲染 + 每段複製鈕都已存在），本案主戰場限 server prompt/schema——請確認「幾乎不動 client」的範圍判斷沒有遺漏。

**Round 1（2026-06-11）= REVISE_REQUIRED（0 P0 / 2 P1 / 2 P2）**：
- [P1] cap 4 與現況硬衝突：既有全鏈 cap 3（client `analysis_models.dart:241` `.take(3)`、server `post_process.ts:136` `slice(0,3)`、prompt `index.ts:1464`、`index_test.ts:257`）。改 4 動四處且舊 client 掉第 4 段——「幾乎不動 client」前提不成立。
- [P1] 規格 #5 audit 範圍過窄：實際讓 cap/source 生效的是 `post_process.ts` `sanitizeReplySegments`（:130/:443/:580），只審 prompt 會漏行為決定層。
- [P2] #13 source contract 不可驗收：現況 sanitizer 只驗 `reply` 非空，`sourceIndex` 可省略、`sourceMessage` 可空（:142/:147/:155），缺 source 處理未定。
- [P2] 驗收清單缺 cap overflow + schema validation case；style-pair 重驗未明列 golden（鎖在 `effective_style_prompt_builder_test.dart:124`）。
- Codex 已實際對照 client：ReplySegment model / 解析 / 分段渲染 / 每段 copy 確認存在。

**Claude 修訂（同日，已入設計文件）**：#5 audit 範圍加 sanitizer 層；#13 補三層缺 source 規則（sourceIndex 回查修復 → drop 該段 → 全 drop 回退單段，絕不空 source 流出）；驗收清單擴充 cap overflow + schema case + 明列 style-pair byte-for-byte 鎖測試重新基準化。

**Eric 拍板（2026-06-11）**：**cap 3**——與現況全鏈對齊、client 完全不動、golden case 3 球已滿足；cap 4 增益無真實案例。規格 #1 已改寫定案。

**Round 2（2026-06-11）= APPROVED（0 P0/P1/P2）**：Codex 驗證 r1 四項全數解除——cap 3 與 `.take(3)`/`slice(0,3)`/prompt 對齊（`analysis_models.dart:241`、`post_process.ts:136`、`index.ts:1464`）；audit 範圍含 sanitizer 層（`post_process.ts:130/:443/:580`）；#13 三層 source 規則 + `quotedReplyPreview` 欄位存在（`message.dart:23`）；驗收清單完備、style-pair 鎖測試在案（`effective_style_prompt_builder_test.dart:124`）；「幾乎不動 client」在 cap 3 下成立（`analysis_screen.dart:4316/:4422`）。

Close condition 達成：設計 APPROVED。實作另開 item 走高風險雙審（規格 #6 雙軌）。

---

## [2026-06-11] ADR #19 字數合併計費 — Codex 設計把關（實作前）
Status: CLOSED（Eric 確認 2026-06-11 深夜；全 close condition 達成：設計把關 APPROVED + 實作 land + 實作雙審 APPROVED 0 findings + Eric 確認）
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

**Round 8 = Codex 實作雙審（2026-06-11 深夜）= APPROVED，0 P0 / 0 P1 / 0 P2**：

> 8 條 implementer claims 逐項確認成立（claim-at-gate user-safe / 409 不 auto-rebind / 4000 上限作用 billableChars + 20000 payload 守門 / replay messagesUsed=0 / hash+billableChars 雙比對 / TTL 60min / U+0085 已知接受 + 409 自癒 / skipPreview 仰賴 server 守門），各附 file:line 證據。測試矩陣覆蓋足夠；Codex 自行重跑 Deno billing+claims 46 passed 驗證；Flutter targeted tests 因 sandbox 唯讀無法重跑，採實作方提供之 120 全綠證據（queue R7）。

**狀態**：**實作雙審 APPROVED → WAITING_ON_ERIC（close condition 最後一關：Eric 確認後關閉）**。計費新制具備 dogfood 條件（雙審證據在案）；⚠️ 唯 migration `20260611120000` 須在新 App build 發 TF 前手動 `supabase db push`。

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
