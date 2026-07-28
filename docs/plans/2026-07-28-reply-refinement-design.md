# 回覆風格微調設計文件（AI 推薦回覆「再調一下」）

日期：2026-07-28（v2，雙審後修訂）
分支：`claude/reply-refinement-design-v2`（v1 為 `claude/reply-style-refinement-j6br3y`）
現況基準 SHA：`c7cefb4405bcacd1bb127e56e6e5e8b46fd145af`
狀態：**設計鎖定用，無任何 runtime code 變更**

> 白話版（給夥伴 review）：`2026-07-28-reply-refinement-plain.md`
> 雙審結果與證據：`../reviews/2026-07-28-reply-refinement-review-results.md`
> 本檔為單一真相源；另外兩份不得夾帶本檔沒有的決策。

---

## 0. v2 相對 v1 改了什麼

v1 經兩位獨立審查（Codex／Claude，各自回原始碼核對）後**未通過 gate**，兩份審查獨立指出同一個結構性問題。v2 依 Eric 2026-07-28 的拍板重寫。

| 項目 | v1 | v2 |
|---|---|---|
| 草稿潤飾器付費邊界 | 維持 Essential | **拆除，對全部用戶開放**（D-4） |
| 微調扣費 | 每次扣 1 | **每天前 10 次免費，之後每次扣 1**（D-5） |
| 微調粒度 | 單句或整組合併 | **只作用於單句**（D-6） |
| 安全鐵律 | prompt 條款 | **加上實際的輸出守門**，否則降級稱 best-effort |
| 不需要 migration（P1） | 主張成立 | **視實作路線而定**，見 §2.2 |
| Phase 2（回寫關於我） | 納入本次設計 | **整段延後**，定義不足 |

---

## 1. 現況評估（v1 已驗證，v2 保留並修正三處事實）

決定「回覆長什麼樣」的有兩層，兩層都不是即時的。

### 1.1 關於我 — 靜態、全域、預設式

- `lib/features/user_profile/domain/entities/user_profile.dart`：Hive typeId 9，主/副互動風格、練習目標 ≤3、常聊話題 ≤5、自訂話題 ≤60 字、想讓 AI 知道的事 ≤100 字。**純本機，沒有任何 Supabase 表。**
- 每對象覆寫 `PartnerStyleOverride`（typeId 13），`resolve_effective_style.dart` 把主副風格當原子對合併。
- `effective_style_prompt_builder.dart` 是唯一把設定翻成 prompt 文字的層（`buildForAnalysis` 上限 900 字），輸出走 wire 欄位 `effectiveStyleContext`。
- Edge 端 `analyze-chat/index.ts:7377-7385` 以 `## User Voice & Coaching Preferences` 注入。
- 結論：**設定一次、全域套用**的粗粒度調校。使用者無法在看到結果的當下說「這句太油」。

### 1.2 Analyze-chat 的回覆風格 — 固定五槽、模型自選

- 固定 enum `extend / resonate / tease / humor / coldRead`。`index.ts:582-603` 的 `TIER_FEATURES` 讓 Free 只拿 `extend`＋`tease`，付費五種。
- 一次串流全部產出，`finalRecommendation.pick` 由模型自己挑。
- **wire 上完全沒有 tone / style / refine 欄位。** `analysis_stream_runs.selected_style` 是輸出、不是輸入。
- 現有「重來」只有 `retryFull()`（同 run、不重扣，專供失敗）與 `_refreshPremiumReplies()`（整份重跑）。都不是針對單句的調整。

### 1.3 唯一已存在的「調」＝草稿潤飾器 `optimize_message`

- 使用者貼**自己的**草稿 → 一次性 `optimizedMessage{original, optimized, reason}`。
- 目前 Essential only，雙閘：client `optimize_message_request_session.dart:12` `canSendOptimizeMessageRequest`，server `index.ts:7121-7142` 403 `FEATURE_NOT_AVAILABLE`。**v2 要拆掉這兩道，見 §2.1。**
- 固定扣 1（`optimize_message_billing.ts:3`）、`OPTIMIZE_MESSAGE_PROMPT`（`index.ts:2165`）、`OPTIMIZE_MESSAGE_MAX_TOKENS = 700`、非串流。
- 已有完整 exactly-once：client `OptimizeMessagePendingRequest`（Hive 持久化 requestId，7 天窗）＋ server `computeOptimizeMessageInputHash` ＋ `settle_optimize_message_request` RPC ＋ `optimize_message_requests` 表。

> **事實修正 1（v1 錯誤）**：v1 白話版稱這套扣費／防重複機制「已跑兩個月」。實際上 `optimize_message_billing.ts` 與整套 fixed-charge exactly-once 是 `4b624617`（**2026-07-16**）才加入的，到今天 **12 天**。功能本身較早，帳本很新。

### 1.4 Coach 1:1 已經有來回，但不在同一個地方

`CoachChatMode.replyCraft`、`activeSessionTurns`（≤12）、24 小時 resume window、**3 次免費釐清**後才強制扣 1（`coach_chat_providers.dart:93`）。機制已證明可行，但沒掛在回覆卡上，使用者得離開結果去打字問教練。

### 1.5 評估結論

缺口是真的，位置很明確——**夾在「一次生成五張卡」與「跟教練長談」之間，沒有一個便宜、就地、只針對這一句的「再調一下」。**

---

## 2. Phase 1 設計

定位：**不是新功能塊，是 `optimize_message` 的一個參數。**

### 2.1 付費邊界：拆除潤飾器的 Essential 閘門（D-4）

**為什麼必須拆**：`deriveRequestType` 由請求形狀推導（`quota_usage.ts:3-27`），server **無法分辨 `userDraft` 是我們產的建議還是使用者自己打的**。分析回覆是串流產出，卡片文字沒有進任何 server 端可回查的地方。因此「微調對 Free 開放、潤飾維持 Essential」在技術上不可能同時成立：Free 使用者貼自己的草稿加一句「自然一點」就繞過去了。

三條收斂路都走不通：最短長度／字元類別（打四個字就過）、client 顯式旗標（不是憑證）、綁 `analysisRunId + cardKey` 回查（會殺掉多輪迭代與潤飾結果續調，自我矛盾）。

唯一技術上成立的保牆方式是 **stateless HMAC capability**（server 產生文字時簽發、綁 user＋原文 hash＋來源＋效期，每輪再簽發），但它要改 analyze **串流**輸出的 wire 契約以帶下每張卡的簽章，Phase 1 規模約翻倍。

**Eric 拍板（2026-07-28）：拆牆。** 理由：兩者邊際成本都是 1 則，Essential 的價值在額度上限與五張風格卡，不在潤飾器這顆按鈕；維持一道人人可繞的牆，代價是每個實作者都得繞著它寫條件判斷。

實作要點：

- Server `index.ts:7121-7142`：移除 optimize 分支，**`isMyMessageMode` 的 Essential 閘門保留不動**。
- Client `optimize_message_request_session.dart:12` `canSendOptimizeMessageRequest`：移除 `isEssential` 條件。
- **付費 CTA 文案必須同步清掉**：任何指向「草稿潤飾僅限 Essential」的升級提示、鎖頭、上鎖卡都要移除，否則使用者會看到一個已經免費的功能被標成「升級解鎖」。**這是本次最容易漏、且使用者一定看得到的一項。**
- `index.ts:7144-7148` 的 replay 刻意繞閘門邏輯在拆牆後成為死碼，可保留但要註記，不要當成仍在保護什麼。

### 2.2 扣費：每天前 10 次免費（D-5）

**為什麼不是「每句前 2 次免費」**：per-sentence 計數只能由 client 宣告輪次，server 無從驗證。改機 client 永遠宣告「第 1 輪」即可無限免費呼叫模型。per-user-per-day 計數由 server 自己數，偽造不了。

- 免費額度 `REFINE_FREE_DAILY = 10`（Edge 常數，可調）。
- 計數沿用 `increment_model_usage`（`20260703170000_model_call_rate_limit.sql`）的 `(user_id, scope)` 複合鍵，新增 scope 字串 `refine_free`。**該表的 scope 是自由 text（只有 `char_length BETWEEN 1 AND 32` 的 CHECK，沒有值白名單），上限權威在 Edge，因此新增 scope 不需要 migration。**
- 語意調整：超過額度時**不是拒絕**，而是轉為扣 1 則走既有 `optimize_message` 帳本。因此呼叫端要把該 scope 的 daily RAISE 解讀為「免費額度用完」而非「節流」，**不得回傳 429**。
- **免費那幾次不寫 optimize ledger、不佔 quota，但仍受 §2.12 的 `analyze` 節流保護。**
- 扣費那幾次完全沿用現有 `OPTIMIZE_MESSAGE_COST = 1` 與 `settle_optimize_message_request`，不新增計費路徑。

> **P1 修正**：v1 主張「不需要任何 migration」。若 `refine_free` 沿用既有節流表則仍成立；若實作時改用獨立的免費額度表（語意較乾淨、不必把節流表當額度帳本用），P1 即不成立。**兩條路都可接受，但必須在實作計畫裡明確二選一，不得默認。**

### 2.3 粒度：只微調單句（D-6）

- 微調對象是**單一則回覆**，不是 `ReplyStyleCard._copyAllText` 合併後的整組。
- 理由一：整組合併後可能已數百字，多輪迭代會單調成長撞上 `MAX_USER_DRAFT_LENGTH = 1500`（`index.ts:656`）的 400。
- 理由二：整組的「短一點」語意不清（每句都短？還是少一句？）。
- 理由三：若日後改採 capability 保牆，單句是唯一乾淨的簽章粒度。
- 額外防線：server 對 refine 的**輸出**另設較小的字元上限（聊天產品合理值，實作階段定），避免「更詳細一點」把文字養大。

### 2.4 Wire 契約

- 新增選填 `refineInstruction`（trim 後 ≤80 字），與 `userDraft` 同區塊驗證（`index.ts:6591-6600` 附近）。超長回 400 且不扣額度。
- **有 `refineInstruction` 但無 `userDraft`** → 400。
- **client 明確宣告 refine 操作、但指令 trim 後為空** → **400、0 扣費**。不得默默降級成 `optimize_message`：靠形狀推導默默切換身分正是 §2.1 那個洞的根源，不該再用同一招。
- `deriveRequestType` 新增 `refine_reply`（`hasUserDraft && hasRefineInstruction`）。
- `buildQuotaUsageMetadata` 對 `refine_reply`：免費額度內回 `shouldChargeQuota: false` / `quotaReason: "refine_free_daily"`；額度用完回固定 cost 1 / `quotaReason: "refine_reply_fixed_1"`。
- Observability：`hasRefineInstruction` 與剩餘免費次數進 `requestObservability`（`index.ts:7487` 附近），**不記錄指令文字**。
- `ai_logs.request_type` 是 `TEXT NOT NULL DEFAULT 'analyze'`，**全 repo 無值白名單 CHECK**，新增 `refine_reply` 不會在 DB 層被判無效。（此點特別查證，因 2026-07-28 鍵盤事故的真因正是「改 taxonomy 但 SQL 白名單沒同步」。）

### 2.5 Prompt 與輸出安全（v1 的第二個 blocker）

**v1 的問題**：設計把安全條款寫成「Invariants（鐵律）」，但程式碼裡對應到的執行機制是零。`guardrails.ts:92` 的 `checkAiOutput` 開頭是 `if (!result?.replies) return result;`，而 `optimizedMessage` 的回應**沒有 `replies` 欄位**，所以整個輸出守門被跳過。**草稿潤飾器自 2026-07-16 上線至今從未被守門掃過**——這是既有漏洞，不是本設計造成的，但微調把「使用者可自由輸入的指令」接上這條無守門路徑，等於把靜態破口變成可被引導的破口。

v2 要求（缺一則文件必須改稱 best-effort policy，不得自稱鐵律）：

1. **不可覆蓋規則放 system prompt**，不放 user prompt。
2. **指令以 JSON 編碼注入**，不只靠文字分隔線；並剝除換行與控制字元（分隔區塊注入最典型的手法就是指令自帶假分隔符）。
3. **輸出守門實際掃描 `optimizedMessage.optimized`** — `checkAiOutput` 必須涵蓋沒有 `replies` 的形狀。
4. **adversarial fixtures**：coercion／捏造事實／越界／把「委婉拒絕」調成「答應」／假裝成另一個人，各至少一條。
5. **不加關鍵詞 blocklist**（兩位審查一致）：容易繞過，且會誤傷繁中正當需求（「不要那麼客氣」）。
6. 硬性語意 invariant（「不得改變這則訊息在對話裡的動作」）若要當保證，需要 generation 後的語意 verifier；**Phase 1 不做，因此文件對這一條只稱 best-effort。**
7. 呼應 `../research/2026-07-25-jennie-notebooklm-vibesync-analysis.md`：快捷 chip 不提供「更撩一點」這類升溫捷徑，也不做「固定生成三個版本」。

### 2.6 UI

- 底部面板 `lib/features/analysis/presentation/widgets/reply_refine_sheet.dart`（新檔）：目前版本文字 ＋ 快捷 chip ＋ 自由輸入（≤80 字）＋ 版本堆疊。
- 快捷 chip 常數化：「太油了，自然一點」「短一點」「**白話一點**」「語氣溫和一點」「換個說法」。
  - v1 的「更直接一點」改為「白話一點」（Codex 建議）：「更直接」容易被讀成「改變承諾／邀約／界線的方向」，與 §2.5 的安全條款正面衝突。
- **面板內必須顯示今天還剩幾次免費微調**，額度用完時明確告知「接下來每次使用 1 則」。使用者不該在不知情的狀態下開始被扣。
- 迭代：上一輪的 `optimized` 直接變成下一輪的 `userDraft`。
- 版本堆疊是本機 UI state，**不寫進 `AnalysisRecord`**（片段快照依 `AnalysisFragmentPolicy` 不可變，`analysis_screen.dart:8394`）。
  - **但採納 Codex 建議**：最後一個成功版本應存進既有的加密本機暫存並保留 24 小時，避免「調了三輪、關掉畫面全沒了」。這不污染不可變的 `AnalysisRecord`。
- 入口三處：`analysis_screen.dart:7222-7273`（AI 推薦回覆）、`reply_style_card.dart`（五張風格卡）、`analysis_screen.dart:7914-8001`（草稿潤飾結果，可續調）。

### 2.7 扣費與冪等

- **Q-8 前提修正（v1 錯誤）**：v1 主張「同 draft ＋ 同指令 ＝ replay ＝ 不扣費」。實際上 `optimize_message_request_session.dart:262` 的 `markSuccess` 在成功顯示後就會清掉 pending，下一次動作會產生**新的 UUID** → 重新生成 → 重新扣。**replay 只覆蓋同一次進行中請求的網路重試，不覆蓋使用者的下一次點擊。**
  - 因此「再換一版」按鈕**可以安全提供**：新動作用新 requestId，網路重試才沿用舊的。
  - 也因此，若沒有 §2.2 的免費額度，使用者的每一次點擊都會扣 1，且沒有任何緩衝。
- **Hash 向後相容（最關鍵）**：`optimize_message_billing.ts:39-48` 的 server hash 與 `optimize_message_request_session.dart:295-340` 的 client fingerprint，都**只在指令非空時才 append**，讓沒帶指令的舊請求序列化結果一個 byte 都不變。
  - **兩側陣列長度本來就不同**：server 8 元素（含 `forceModel`），client 7 元素（不含）。**兩側各自獨立計算，絕不可拿來互相對齊**——照「對齊兩側」去改 client 陣列，才會真的把 7 天窗內所有 pending 炸成 `REPLAY_MISMATCH`。（v1 審查包 F3 的敘述有誤，已修正。）
  - 鎖法：**兩側各一條 golden hex vector**（固定輸入 → 硬寫死的 SHA 常數）。shape 測試擋不住 `normalizedOptional` 之類正規化行為被改動，golden vector 擋得住。另需一條「舊 client pending 可被新版正確 replay」的測試。
- 同意：沿用 `AiDataSharingConsent.optimizeReplayConsentKey`（資料流完全相同），`featureLabel` 改為「微調回覆」。

### 2.8 必須抽出來、不能複製貼上的一段

`analysis_screen.dart:4916-5088` 的 `_optimizeMessage()` 裡塞著整套 exactly-once：`beginAttempt` → 送出 → `_clearOptimizePendingAfterVisibleFrame`（等 Flutter 真的畫出付費結果才清 pending）→ mismatch 時 `reset`。微調面板必須走同一段，所以**要先把它抽成共用方法／service**。複製一份等於複製一份扣費 bug 的機會。

### 2.9 `isOptimizeMessageMode` 的 13 個使用點

除 Essential 閘門外全部加寬為涵蓋兩種 requestType 的 `isOptimizePathMode`。**§2.1 拆牆後，7124 那個原本唯一保持窄判斷的點會隨 optimize 分支一起移除**，因此 v2 沒有需要保持窄判斷的點。

漏改後果分級（兩位審查一致）：

| 點 | 漏改後果 |
|---|---|
| **6880** | 最嚴重。refine 拿不到 requestId／hash 綁定 → 無 exactly-once → 斷線重試重複扣費 |
| **9115 / 9119** | 格式不合約的輸出不被攔 → 落回一般 analyze 扣費路徑 → 格式失敗仍扣費，且可能結算被 coercion 的結果 |
| **8280** | `streamSupported` 沒排除 refine → 走串流 → 冪等帳本被繞過。4711 是第一道、8280 是第二道，**兩道都要改** |
| **9212** | 不寫 ledger → 落回一般 quota 路徑 → **按對話訊息數扣費**（多扣，非漏扣） |
| **7218** | `requires_confirmation` 沒排除 → refine 誤觸 cap 10 確認流程 |
| 7350 / 7484 / 8887 / 9111 | 退化成一般分析（prompt、max_tokens、後處理），輸出形狀全錯 |
| **7148** | **不會**重複扣費（settle RPC 是權威），但會白跑模型、消耗節流額度，甚至讓已付結果暫時被 429 擋住 |

`index.ts:4711` 的 `isOptimizeMessageRequestShape` 與 `responseMode !== "legacy"` 拒絕路徑（4719-4730）同步涵蓋 refine。**`5106` / `5144` 的 quota early gate 用的就是 4711 這個變數，加寬 4711 即自動涵蓋，不是獨立的編輯點。**

### 2.10 Telemetry：獨立事件（Q-7）

`_analyzeAdviceId`（`analysis_screen.dart:5531-5535`）= `'analyze:{conversationId}:{runKey}:{cardKey}'`，決定論。微調後複製會落回**同一個 adviceId**，覆寫 `suggestedMoveSummary`。

後果不只統計失真：outcome digest 會回注 coach prompt（案 1 批 4），污染的是「教練以為你上次送出了哪句話」。

**採 (c) 獨立事件**：key 用 `refine:<originAdviceId>:<requestId>`，另帶 `originCardKey`。原卡 KPI 維持連續，微調採用率獨立計算，也避開 first-write-wins。

現成先例：`cardKey == 'polish'` 已經有自己的 `_polishRunKey` 命名空間（`analysis_screen.dart:5532`），照抄一個 `_refineRunKey` 即可。

**不採 (a)「outcome 事件加維度」**（要動 schema，與 §2.2 的取捨互相牽動）；**不採 (b)「不計入」**（會白丟最有價值的樣本——調到滿意才複製的那一句）。

### 2.11 錯誤文案（Q-9）

`INVALID_OPTIMIZE_MESSAGE_REQUEST_ID`（`index.ts:6890`）與 `OPTIMIZE_MESSAGE_REQUEST_REPLAY_MISMATCH`（`6942` / `9276`）的 message 硬寫「草稿潤飾」。

- **保留 server 端穩定 code 不動**；由 client 依當前入口（polish／refine）顯示文案。
- server fallback 文案可改成中性的「回覆處理」，但**不得改動 code 字串**。

> **事實修正 2（v1 錯誤）**：審查包 F13 稱兩處 mismatch 都是 400。實際上 **preflight mismatch 是 400（`index.ts:6942`），settlement race mismatch 是 409（`index.ts:9276`）**。client 兩種都要處理。

### 2.12 速率限制（Q-5）

- Phase 1 先共用 `analyze` scope（6/分、60/日，`_shared/model_rate_limit.ts:12`）。一次分析＋三輪微調＝4 次/分，仍在預算內。
- **client 端必須加按鈕 in-flight 鎖與 debounce**，把連點源頭掐掉，而不是靠 server 節流兜底。
- 上線後依 `requestType` 監控命中率。若要拆獨立 scope，**不需要 migration**（scope 是自由 text，上限權威在 Edge）。
- 429 payload 絕不可帶 `monthlyLimit`/`dailyLimit`/`remaining`/`quotaNeeded`（`model_rate_limit.ts:45-49`），否則 client `_quotaExceptionFrom429` 會把限流誤導成升級 CTA。
- **§2.2 的「免費額度用完」不是節流，不得回 429。**

### 2.13 明確不做

不動五風格 enum、`my_message` 的 Essential 閘門、串流 prompt、模型路由（維持 Sonnet 5）、`AnalysisRecord` 快照結構；不動 Opener／New Topic／Keyboard／Practice。

---

## 3. Phase 2：整段延後

v1 的「同一類指令用滿 3 次 → 問要不要記進關於我」定義不足，兩位審查一致建議重寫後另案處理。已知要處理的問題：

- 只計**成功且被複製／採用**的版本，不計 attempt、retry、replay 或使用者不滿意的結果。
- 固定 chip 用穩定 category ID；自由文字第一版不要自動做語意歸類。
- 最好跨**至少兩個不同來源回覆**才觸發，避免某次異常長訊息被誤判成全域偏好。
- 必須定義時間窗、拒絕後 cooldown、重複提示上限與刪除行為。
- **不要把系統學到的偏好硬塞進 100 字的 `UserProfile.notes`**（會與使用者自己寫的內容互相排擠）。改用獨立、結構化、可刪除的加密本機 preference，再由 `EffectiveStylePromptBuilder` 這個 seam 合併輸出。

---

## 4. Invariants

1. 沒帶 `refineInstruction` 的請求，client fingerprint 與 server input hash 必須與今日 **byte-identical**；兩側各自獨立驗證，不得互相對齊。
2. 免費額度內的微調不扣 quota、不寫 ledger；額度用完後恰扣 1；格式失敗／400／429 一律不扣。
3. `my_message` 維持 Essential；`optimize_message` 與 `refine_reply` 皆對全部用戶開放。
4. 指令永遠是資料（JSON 編碼、剝控制字元），不得覆蓋安全／同意／界線條款。
   - **「不得改變這則訊息在對話中的動作」在 Phase 1 是 best-effort，不是保證**——沒有語意 verifier。
5. 微調結果不寫入 `AnalysisRecord`；最後成功版本只進 24 小時加密本機暫存。
6. 不動五風格 enum、不動模型路由。

---

## 5. 風險與回歸清單

- 高風險面：**付費邊界拆除**、quota、exactly-once、AI prompt 安全，全部落在 AGENTS.md 的 R2/R3 範圍。
- 拆牆是**對外可見的商業行為變更**，不只是工程變更：付費 CTA、方案說明頁、任何提到「草稿潤飾為 Essential 功能」的文案都要一起改。
- 實作階段落地前必跑：analyze-chat Deno 全套、**兩側 golden hex vector**、舊 client pending replay 測試、adversarial 安全 fixtures、Flutter widget/unit、`flutter analyze`、真機 fresh／replay／mismatch／免費額度用完的 smoke（測試帳號免扣，注意 `TEST_EMAILS` 會讓額度行為與正式帳號不同）。
- 實作階段是 Change/Fix 任務，要走獨立 cross-model review。

---

## 6. 建議實作順序

0. **（獨立前置，建議先落地）** 補 `checkAiOutput` 對沒有 `replies` 形狀的輸出守門。這是既有漏洞，不依賴本功能。
1. 抽出共用 optimize 執行路徑（純重構、行為不變，可單獨先落地）。
2. 拆除 Essential 閘門（server＋client＋付費 CTA 文案）。
3. Server：`refineInstruction` 驗證＋`refine_reply` requestType＋JSON 指令注入＋hash 相容＋observability。
4. Server：免費額度計數與「額度用完轉扣費」分支。
5. Client：service 欄位＋fingerprint＋`ReplyRefineSheet`＋三個入口＋剩餘次數顯示＋in-flight 鎖。
6. Telemetry 獨立事件。
7. 24 小時本機暫存。

---

## 7. 待實作階段決定（不阻擋本設計）

- §2.2 的免費額度計數走既有節流表（零 migration）還是獨立表（語意乾淨）——**必須明確二選一**。
- `REFINE_FREE_DAILY` 的實際數字（暫定 10）。
- refine 輸出的字元上限實際值。
