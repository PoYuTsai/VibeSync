# 回覆風格微調設計文件（AI 推薦回覆「再調一下」）

日期：2026-07-28
分支：`claude/reply-style-refinement-j6br3y`
現況基準 SHA：`c7cefb4405bcacd1bb127e56e6e5e8b46fd145af`
狀態：**設計鎖定用，無任何 runtime code 變更**

> 白話版（給夥伴 review）：`2026-07-28-reply-refinement-plain.md`
> Codex 審查包：`../reviews/2026-07-28-reply-refinement-design-review-packet.md`
> 本檔為單一真相源；另外兩份不得夾帶本檔沒有的決策。

## 0. 白話摘要（給 Eric / Bruce）

- 使用者反映 AI 推薦回覆「太油」或不像自己說話時，沒有地方講——只能整份重新產生，或自己動手改。
- 目前決定語氣的只有兩層：設定頁「關於我」預先勾的風格，加上 AI 自己在五種風格裡挑。**兩層都不是看到結果當下能改的。**
- 提案：每張回覆卡加一顆「再調一下」，可按快捷（太油了自然一點／短一點／更直接／溫和一點／換個說法）或自己打一句要求，出新版本後還能接著調。
- 每次成功微調扣 1 則，**全部用戶都能用**；草稿潤飾器維持 Essential 不變。
- 同一種要求用滿 3 次會問要不要記進「關於我」，之後所有分析／開場白／新話題自動照做——這是把兩個功能接起來、也是「教 AI 講人話」行銷素材的完整弧線。
- 風險帶：付費邊界、quota、exactly-once、prompt 安全。**不需要任何 migration**，沿用草稿潤飾器已跑兩個月的帳本。

## 1. 現況評估

決定「回覆長什麼樣」的其實有兩層，而且兩層都不是即時的。

### 1.1 關於我 — 靜態、全域、預設式

- `lib/features/user_profile/domain/entities/user_profile.dart`：Hive typeId 9，欄位為主/副互動風格（穩重／直接／幽默／溫柔／有玩心）、練習目標 ≤3、常聊話題 ≤5、自訂話題 ≤60 字、想讓 AI 知道的事 ≤100 字。**純本機，沒有任何 Supabase 表。**
- 每對象覆寫 `PartnerStyleOverride`（typeId 13），由 `lib/features/user_profile/domain/services/resolve_effective_style.dart` 把主副風格當原子對合併。
- `lib/features/user_profile/domain/services/effective_style_prompt_builder.dart` 是唯一把設定翻成 prompt 文字的層（`buildForAnalysis` 上限 900 字），輸出走 wire 欄位 `effectiveStyleContext`。
- Edge 端 `supabase/functions/analyze-chat/index.ts:7377-7385` 以 `## User Voice & Coaching Preferences` 注入，並明寫「只調語氣與教練方向，當前對話／userDraft 意圖／同意安全／投入對等優先」。
- 結論：**設定一次、全域套用**的粗粒度調校。使用者無法在看到結果的當下說「這句太油」。

### 1.2 Analyze-chat 的回覆風格 — 固定五槽、模型自選、tier 決定看得到幾張

- 固定 enum `extend / resonate / tease / humor / coldRead`。`index.ts:582-603` 的 `TIER_FEATURES` 讓 Free 只拿 `extend`＋`tease`，付費五種；`supabase/functions/analyze-chat/tier_sync_contract.ts:55` 的 `streamReplyStylesForTier` 把清單寫進 streaming system prompt。
- 一次串流全部產出，`finalRecommendation.pick` 由模型自己挑。
- **wire 上完全沒有 tone / style / refine 欄位。** `analysis_stream_runs.selected_style` 是輸出、不是輸入。
- 現有「重來」只有兩種：`StreamingAnalyzeNotifier.retryFull()`（同 run、不重扣，專供失敗）與升級後的 `_refreshPremiumReplies()`（整份重跑）。兩者都不是針對單一句子的調整。

### 1.3 唯一已存在的「調」＝草稿潤飾器 `optimize_message`

- 使用者貼**自己的**草稿 → 一次性 `optimizedMessage{original, optimized, reason}`。
- Essential only，且是雙閘：client `lib/features/analysis/data/services/optimize_message_request_session.dart:12` 的 `canSendOptimizeMessageRequest`，server `index.ts:7121-7142` 的 403 `FEATURE_NOT_AVAILABLE`。
- 固定扣 1（`optimize_message_billing.ts:3` `OPTIMIZE_MESSAGE_COST`）、`OPTIMIZE_MESSAGE_PROMPT`（`index.ts:2165`）、`OPTIMIZE_MESSAGE_MAX_TOKENS = 700`（`index.ts:2163`）、非串流。
- 已有完整 exactly-once：client `OptimizeMessageRequestIdSession`（Hive 持久化 requestId，7 天窗）＋ server `computeOptimizeMessageInputHash` ＋ `settle_optimize_message_request` RPC ＋ `optimize_message_requests` 表。
- 缺的正好只有三件事：**輸入不能是 AI 產的建議、沒有指令欄位、不能連續迭代。**

### 1.4 Coach 1:1 已經有來回，但不在同一個地方

- `CoachChatMode.replyCraft`（幫你接話）、`activeSessionTurns`（≤12）、`sessionId`、24 小時 resume window、**3 次免費釐清**後才強制扣 1（`lib/features/coach_chat/data/providers/coach_chat_providers.dart:93` `maxNoChargeClarificationTurns`，server 端 schema transform 強制 `costDeducted`）。
- 「像跟朋友討論台詞」的機制在 Coach 已經證明可行，但沒掛在回覆卡上。使用者得離開結果、打字問教練，成本與心理門檻都高。

### 1.5 評估結論

缺口是真的，位置很明確——**夾在「一次生成五張卡」與「跟教練長談」之間，沒有一個便宜、就地、只針對這一句的「再調一下」。** 而所需的基礎建設（扣費、冪等、同意、prompt 契約）已經在 `optimize_message` 上跑了兩個月，不必從零開始。

## 2. Phase 1 設計：「再調一下」

定位：**不是新功能塊，是 `optimize_message` 的一個參數。**

### 2.1 Wire 契約

- 新增選填 `refineInstruction`（trim 後 ≤80 字），與 `userDraft` 同區塊驗證（`index.ts:6591-6600` 附近）。超長回 400 且不扣額度；沒有 `userDraft` 卻單獨出現也回 400。
- `supabase/functions/analyze-chat/quota_usage.ts:3` 的 `deriveRequestType` 新增 `refine_reply`（`hasUserDraft && hasRefineInstruction`）。
- `index.ts` 現有 13 個 `isOptimizeMessageMode` 使用點改為涵蓋兩種 requestType 的 `isOptimizePathMode`，**唯一保留窄判斷的地方是 7121-7142 的 Essential 閘門**。逐點清單見審查包 Q-2。
- `isOptimizeMessageRequestShape`（`index.ts:4711`）與 `responseMode !== "legacy"` 的拒絕路徑（`index.ts:4719-4730`）同步涵蓋 refine。
- `buildQuotaUsageMetadata` 對 `refine_reply` 回固定 cost 1、`quotaReason: "refine_reply_fixed_1"`。
- Observability：`hasRefineInstruction` 進 `requestObservability`（`index.ts:7487` 附近），**不記錄指令文字**。

### 2.2 Prompt 契約（安全核心）

- 指令以分隔區塊當**資料**注入 user prompt，不進 system prompt。
- 只能調整語氣、長度、方向、用字；**不得改變這則訊息在對話裡的動作**（接的是哪顆球、有沒有邀約、有沒有設界線）。
- 不得新增草稿沒有的事實、興趣、承諾或自我描述。
- 不得覆蓋安全、同意、界線、低壓與「不要替使用者假裝成另一個人」。指令要求施壓／越界／性化／貶低／操弄／捏造時，忽略那一部分，並在 `reason` 用一句白話說明沒照做的地方——**軟性拒絕，不丟錯誤。**
- 呼應 `../research/2026-07-25-jennie-notebooklm-vibesync-analysis.md` 的「技巧感漏出來」與「不建議做的功能」：快捷 chip 不提供「更撩一點」這類升溫捷徑，也不做「固定生成三個版本」。

### 2.3 UI

- 底部面板 `lib/features/analysis/presentation/widgets/reply_refine_sheet.dart`（新檔）：目前版本文字 ＋ 快捷 chip ＋ 自由輸入（≤80 字，沿用 `_optimizeController` 的收鍵盤模式）＋ 版本堆疊。
- 快捷 chip 常數化（可測試、可審）：「太油了，自然一點」「短一點」「更直接一點」「語氣溫和一點」「換個說法」。
- 迭代方式：上一輪的 `optimized` 直接變成下一輪的 `userDraft`，指紋天然不同，**不需要新的 session／thread 概念**。
- 版本堆疊是純本機 UI state，**不寫進 `AnalysisRecord`**——片段快照依 `AnalysisFragmentPolicy` 是不可變的（`analysis_screen.dart:8394` 註解：「分析完成後關閉原片段；任何新內容都另開獨立片段」）。離開畫面即失去，與現行草稿潤飾行為一致。
- 入口三處：
  - `lib/features/analysis/presentation/screens/analysis_screen.dart:7222-7273`（AI 推薦回覆區塊）
  - `lib/features/analysis/presentation/widgets/reply_style_card.dart`（五張風格卡）
  - `analysis_screen.dart:7914-8001`（草稿潤飾結果，可續調）
- 多段訊息組：微調對象是「使用者會複製的那段文字」——單句，或 `ReplyStyleCard._copyAllText` 的換行合併整組；回傳一整塊純文字、不重新切段。因此 `optimizedMessage` schema **一個字都不用改**。

### 2.4 扣費與冪等

- 沿用 `OPTIMIZE_MESSAGE_COST = 1` 與現有 RPC／表，**不需要新的 migration**。
- **付費邊界變動（R2/R3 高風險）**：微調對全部用戶開放，但草稿潤飾器維持 Essential。因此 `canSendOptimizeMessageRequest` 與 `index.ts:7121-7142` 都要改成「只擋 `optimize_message`、放行 `refine_reply`」，而不是整條路徑拆閘。
- **Hash 向後相容（最關鍵的一條）**：`optimize_message_billing.ts:39-48` 的 `computeOptimizeMessageInputHash` 與 client `optimize_message_request_session.dart:295-340` 的 `fingerprintFor`，都只在指令非空時才 append 進 canonical 陣列，讓沒帶指令的舊請求 hash 一個 byte 都不變。否則部署當下，7 天內所有未結算的 pending 請求會全部變成 `OPTIMIZE_MESSAGE_REQUEST_REPLAY_MISMATCH`，使用者拿不回已付結果。兩邊各補一個「舊格式 hash 不變」的快照測試。
- **沒有「同輸入再擲一次」按鈕**：同 draft ＋ 同指令 ＝ 同 hash ＝ server replay，回同一段文字且不扣費。這對帳務是好性質，但代表「換一個版本」必須是**不同的指令字串**——所以「換個說法」是一個 chip，不是 regenerate 鍵。
- 同意：沿用 `AiDataSharingConsent.optimizeReplayConsentKey`（資料流完全相同），`featureLabel` 改為「微調回覆」。

### 2.5 必須抽出來、不能複製貼上的一段

`analysis_screen.dart:4916-5088` 的 `_optimizeMessage()` 裡塞著整套 exactly-once：`beginAttempt` → 送出 → `_clearOptimizePendingAfterVisibleFrame`（等 Flutter 真的畫出付費結果才清 pending）→ mismatch 時 `reset`。微調面板必須走同一段，所以**要先把它抽成共用方法／service，兩個入口共用**。複製一份等於複製一份扣費 bug 的機會。

### 2.6 速率限制

微調走 `analyze` scope（`supabase/functions/_shared/model_rate_limit.ts:12`，6/分、60/日）。三輪快速來回加上原本的分析＝4 次/分，仍在預算內。但要驗證 429 走的是節流文案而非 paywall——`model_rate_limit.ts:45-49` 的註解明確警告：該 payload 絕不能帶 `monthlyLimit`/`dailyLimit`/`remaining`/`quotaNeeded`，否則 client 的 `_quotaExceptionFrom429` 會把限流誤導成升級 CTA。

### 2.7 明確不做

不動五風格 enum、tier 閘門的其他部分、串流 prompt、模型路由（維持 Sonnet 5）、`AnalysisRecord` 快照結構；不新增 migration；不動 Opener／New Topic／Keyboard／Practice。

## 3. Phase 2 設計：把偏好記回「關於我」

- 同一類指令用滿 3 次（本機計數，存既有加密 settings box）→ 一次性提示「要不要把『講白話一點、不要太油』記進關於我？」
- 寫入 `UserProfile.notes`（≤100 字，`UserProfile.create` 已有驗證）透過 `userProfileControllerProvider`。notes 是唯一不需要改 Hive schema 的落點。
- 寫入後自動流進 `effectiveStyleContext` → analyze／opener／new_topic／coach 全部吃到。
- UX 要點：notes 只有 100 字，必須是**附加＋可預覽＋可取消**，不能靜默覆蓋使用者原本寫的內容。
- 這是把「關於我」與 analyze-chat 真正接起來的地方，也是「教 AI 講人話」行銷素材的完整弧線：當下微調 → 系統記住 → 之後不用再講。

## 4. Invariants（鐵律——動碼前先寫進審查包）

1. 沒帶 `refineInstruction` 的請求，client fingerprint 與 server input hash 必須與今日 **byte-identical**。
2. 一次成功微調恰扣 1；格式失敗／400／429 一律不扣。
3. 草稿潤飾器維持 Essential；放行 Free 的只有 `refine_reply`。
4. 指令永遠是資料，不能改變訊息在對話中的動作，也不能覆蓋安全／同意／界線條款。
5. 微調結果不寫入 `AnalysisRecord`，分析片段快照維持不可變。
6. 不新增 migration、不動五風格 enum、不動模型路由。

## 5. 風險與回歸清單

- 高風險面：付費邊界、quota、exactly-once、AI prompt 安全，全部落在 AGENTS.md 的 R2/R3 範圍。
- 實作階段落地前必跑：analyze-chat Deno 全套、hash 相容快照測試、Flutter widget/unit、`flutter analyze`、真機 fresh／replay／mismatch smoke（測試帳號免扣）。
- 實作階段是 Change/Fix 任務，要走獨立 cross-model review。

## 6. 建議實作順序（供下一個任務使用）

1. 抽出共用 optimize 執行路徑（純重構、行為不變，可單獨先落地）。
2. Server：`refineInstruction` 驗證＋`refine_reply` requestType＋prompt 區塊＋hash 相容＋observability。
3. Client：service 欄位＋fingerprint＋`ReplyRefineSheet`＋三個入口。
4. 資格分流（微調全開／潤飾維持 Essential）＋文案。
5. Phase 2 關於我回寫。

## 7. 本次未決、留給 review 的問題

完整清單見審查包。其中三題必須有結論才算 review 完成：

- **Q-1** 條件式 append 是否真能保證舊請求 hash byte-identical（Deno 與 Dart 兩側）。
- **Q-3** Essential 閘門只放行 `refine_reply`，是否存在繞過潤飾器付費牆的路徑。
- **Q-7** 複製微調後版本時，現有 outcome telemetry 記在原卡片 key 上會不會污染「這張卡有沒有被採用」的資料。
