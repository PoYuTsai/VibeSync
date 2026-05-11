# Spec 5 — Coach Follow-up v1 Design

> Status: design REVISED_AND_APPROVED post Codex spec review. NO code yet.
> Date: 2026-05-02
> Depends on: Spec 1-4 (all SHIPPED at HEAD `0d7ff06`)
> Supersedes scope of: `2026-04-30-memory-coach-spec5-proactive-coach-loop-draft.md`
> (Draft remains as future roadmap; this doc binds v1 only.)
> Authors: Claude (draft) → Codex (spec review @ `3d8dd3a`) → Claude (revision)
> Codex review file: `docs/reviews/2026-05-02_spec5-coach-follow-up-design_codex-review.md`

---

## 0. Quick Read — What v1 Is and Isn't

**Is**:
- 三個固定 flow（準備邀約 / 約會前提醒 / 約會後復盤），共用一個 prompt builder、一個 response schema、一個結果卡 widget。
- 入口在 partner detail 頁面新增「教練跟進」區塊。
- 用戶點選為主、文字選填；觸發後呼叫**獨立** `coach-follow-up` Edge Function（不掛 `analyze-chat` mode 分支），成功生成扣 1 message credit。
- 每個 partner 只保存最近一次結果。重生成即覆蓋。

**Isn't**:
- 不做 chatbot（單輪 in / 單輪 out，不可追問）。
- 不做 push notification（v1 純 in-app）。
- 不做歷史列表（一個 partner 只有一張卡）。
- 不寫入 `partnerSummary` / `partnerTraits` / Spec 1 long-term memory / Spec 2 partner override。
- 不掛 `analyze-chat` 任何 code path（OCR 紅線隔離；獨立 Edge function）。
- 不自動建立提醒 / 不自動判定階段（AI 只能 hint，必須用戶確認）。
- 不做 Spec 5 draft 裡的 5D（intimacy aftercare） / 5E（short-term maintenance） / 5F（fit reflection） — 全部留 v2+。
- 不做第 4 個 phase「她回覆變慢」（Q-Eric-2 defer，v2 候選）。

---

## 1. UX Design

### 1.1 Entry Point — Partner Detail「教練跟進」區塊

固定區塊插入位置：`partner_detail_screen.dart`，建議排序：

```text
1. AppBar（已存在）
2. PartnerHeatHeroCard（已存在）
3. PartnerDataQualityBanner（Spec 3, conditional）
4. PartnerRadarSummaryCard（已存在, paid only）
5. PartnerTraitsCard（已存在）
6. ▶ CoachFollowUpSection（新增）
7. Conversations list（已存在）
8. FAB → NewConversationSheet（已存在）
```

區塊 default state（無已生成結果時）：

```text
┌──────────────────────────────────────────┐
│ 教練跟進                                  │
│ 想練什麼？選一個情境，AI 幫你拆解下一步。  │
│                                          │
│  ┌────────┐  ┌────────┐  ┌────────┐    │
│  │ 準備邀約 │  │ 約會前  │  │ 約會後  │    │
│  │         │  │ 提醒    │  │ 復盤    │    │
│  └────────┘  └────────┘  └────────┘    │
│                                          │
│  💡 看起來你最近聊到見面，可以試「約會前提醒」 │
│  （AI hint，可選顯示）                    │
│                                          │
│  ⓘ 生成會使用 1 則額度                    │
└──────────────────────────────────────────┘
```

區塊 with-result state：

```text
┌──────────────────────────────────────────┐
│ 教練跟進  ·  最近一次：約會前提醒          │
│                                          │
│  [Follow-up Result Card 內容]             │
│                                          │
│  ╭──────────────╮  ╭────────────╮        │
│  │ 重新生成      │  │ 換情境      │        │
│  ╰──────────────╯  ╰────────────╯        │
│  ⓘ 重新生成會再扣 1 則額度                │
└──────────────────────────────────────────┘
```

**設計原則（硬規則）**：
- 三個 flow chip **永遠可選**，AI hint 只是建議不是強制（「低壓確認入口」）。
- AI hint 是 **client-side derivation**，不額外吃 credit（從既有 partner 狀態推）。
- 沒有 hint 信號時 chip 平展示，不顯示 hint 行。
- 結果卡只有「重新生成」（同 phase 重做）/「換情境」（回到 chooser）。沒有「儲存到歷史」（不做歷史）。
- 任何「會扣額度」的觸發點，UI **必須**顯示「生成會使用 1 則額度」字樣（Codex Q6 條件）。

### 1.2 Click-First Input Flow

點擊 chip 後進入該 phase 的 input sheet。每個 phase 有 1-3 個 multiple-choice 問題 + 1 個 optional 文字框。所有問題必須 multiple-choice 為主、可跳過。

#### 準備邀約 Input

```text
Q1（必選）：你想用什麼方式邀？
  □ 模糊邀約（看看她要不要）
  □ 具體邀約（時間 + 活動都明確）
  □ 還沒想好

Q2（選填）：你最擔心的是？
  □ 被拒絕
  □ 顯得太急
  □ 找不到合適理由
  □ 不知道怎麼開口

Q3（選填，free-text，最多 80 字）：補充想說的
```

#### 約會前提醒 Input

```text
Q1（必選）：什麼時候見？
  □ 今天 / 今晚
  □ 明天
  □ 三天內
  □ 一週內

Q2（選填）：見面活動？
  □ 吃飯
  □ 喝東西 / 咖啡
  □ 一起做某件事（電影 / 展覽 / 運動）
  □ 還沒定

Q3（選填，free-text，最多 80 字）：你現在最緊張 / 想練的點
```

#### 約會後復盤 Input

```text
Q1（必選）：整體感覺？
  □ 比預期好
  □ 還可以
  □ 卡卡的
  □ 不確定

Q2（必選）：對方有沒有主動延續？
  □ 有（主動找下一次 / 主動延續話題）
  □ 還在禮貌回應
  □ 變慢或變淡
  □ 還看不出來（剛結束 / 訊息還沒回 / 太早判斷不出）

Q3（選填，free-text，最多 80 字）：哪個瞬間最想復盤
```

「產生跟進建議」按鈕 disabled until 所有必選題都選完，且**生成期間維持 disabled**（client-side debounce，避免 double-spend / 結果競態，Q2 verdict）。

### 1.3 Follow-up Result Card

固定 5 欄位，schema 名（程式 / 測試）vs 中文 UI 標籤分離：

| Schema 名 | UI 標籤 | 內容軸 | 字數規格 | Required |
|-----------|---------|--------|---------|---------|
| `headline` | （粗體無標籤） | 一句話定位這次跟進的核心（例：「不是話術問題，是節奏問題」） | ≤ 30 字 | ✅ |
| `observation` | 我看到的重點 | AI 對局面的低壓觀察（不下判斷） | ≤ 80 字 | ✅ |
| `task` | 這次建議你做 | 這次只練這一件事（具體動詞 + 對象） | ≤ 30 字 | ✅ |
| `suggestedLine` | 可以這樣說 | 「示意」訊息範本，提示**不是要她直接複製** | ≤ 80 字 | optional (nullable) |
| `boundaryReminder` | 邊界提醒（負面情境可作「先不要…」） | 自我邊界提醒；強迫每次都產生（避免 AI 偷懶） | ≤ 60 字 | ✅ **required** |

**對照 Spec 4 CoachActionCardData**：Spec 4 是 6 欄含 `learningLink`，Spec 5 v1 不掛 Learning（v2 候選），故 5 欄。Spec 4 的 `avoid` 在 Spec 5 由 `boundaryReminder`（必填）承擔。

### 1.4 Loading / Error States

| 狀態 | 行為 |
|------|------|
| Loading（生成中） | 結果卡區塊顯示 skeleton + 「教練思考中…」（重用 Spec 4 / opener 的 loading style） |
| 網路 / Edge 失敗 | 顯示「生成失敗，credit 未扣，請再試」+ 重試按鈕。**Credit 必須未扣**（沿用 opener 的「成功才扣」契約）|
| Tier cap reached | 顯示 paywall sheet（重用既有 monthly/daily cap UI） |
| 同一 partner 重複點擊 | 第二次點擊 button disabled until 第一次回傳（client-side debounce） |
| Response schema 違規（字數超出 / required 欄位 missing） | Server hard truncate 字數；required 欄位 missing 直接 5xx，**不扣 credit**，client 顯示重試 |

---

## 2. Backend Architecture

### 2.1 New Independent Edge Function: `coach-follow-up`

**架構決策（Codex Q-Codex-1 verdict）**：開**獨立** Edge function，不掛 `analyze-chat` mode 分支。

**理由**：
1. **OCR 紅線**：`analyze-chat` 是 OCR-stable baseline 路徑，任何 deploy 都增加 OCR 回歸風險（CLAUDE.md 規定 OCR 變動不得與 security/cache/parser/prompt/multi-agent 改動混 commit）。新增 mode 即使邏輯隔離，也共享 deploy artifact。
2. **隔離**：Spec 5 的 request schema / response schema / prompt builder / telemetry / failure mode 都跟主分析不同；獨立 function 給 reviewer 清楚邊界，避免意外掉進 `recognizeOnly` / `analyzeMode` / `images` / `partnerSummary` 任何既有 path。
3. **Cost machinery**：可以萃取小型 quota helper 共用，或最小範圍 copy 既有 cost check / deduct 序列 + 補測試；複製少量 quota 邏輯的成本 < 把新功能耦合上 OCR baseline 的風險。

**File layout**：

```text
supabase/functions/coach-follow-up/
  index.ts        # Auth check / quota gate / dispatch / response
  prompts.ts      # buildCoachFollowUpPrompt(phase, answers, hint) → string
  schemas.ts      # CoachFollowUpRequest / CoachFollowUpResult zod schema
  validate.ts     # validateRequest / validateResponse + truncate helpers
  README.md       # phase semantics + tone rules + boundary list
```

`index.ts` **絕對不**：
- import 任何 `analyze-chat` 內檔（包括 prompt helpers / OCR helpers / `PartnerContextResolver`）
- 接受 `images` 欄位（傳了即 reject `400 invalid_input_for_mode`）
- 讀 / 寫 `partnerSummary` / `partnerTraits` / About Me / Partner Style Override
- 寫任何 long-term memory / Spec 1 layer 持久層
- log 用戶 free-text answers 或 prompt 全文（telemetry 限定欄位見 §7）

### 2.2 Request Schema (client → Edge)

呼叫 `POST /functions/v1/coach-follow-up`：

```jsonc
{
  "phase": "prepareInvite" | "preDateReminder" | "postDateReflection",
  "answers": {
    "q1": "string (必選 enum value)",
    "q2": "string | null (選填 enum value)",
    "q3": "string | null (選填，最多 80 字 free text)"
  },
  "partnerHint": {
    "name": "string (display only — prompt 不可從 name 推測 personality)",
    "heatScore": 0-100 | null,
    "gameStage": "string | null",
    "lastConversationSummary": "string | null (≤ 200 字, conversation-level only)"
  }
}
```

**約束（Codex Q3 verdict）**：
- `partnerHint.lastConversationSummary` 必須是 **conversation-level summary**（單一對話 ConversationSummary 提煉），**不**接受 cross-conversation aggregate / partnerSummary / 任何 traits / 任何原始訊息文字。
- 上限 200 字；超出由 client 截斷後送出（server 收到後再 hard cap 一次保險）。
- **若 Spec 3 `dataQualityFlagProvider(partnerId).isFlagged == true`，client 必須 omit `lastConversationSummary`**（資料品質有疑慮時，coach 不該根據可能錯誤的 context 給節奏建議）。
- `partnerHint.name` 純粹拿來 display（例：「跟 Candy 約會前的提醒」標題），**prompt builder 不得**用 `name` 推測對方性格 / 文化背景 / 任何屬性。

`mode` 欄位**不存在**（function path 已決定是 coach-follow-up，不需 redundant flag）。

### 2.3 Response Schema (Claude → Edge → client)

```jsonc
{
  "phase": "prepareInvite" | "preDateReminder" | "postDateReflection",
  "card": {
    "headline": "string ≤ 30 字 (required)",
    "observation": "string ≤ 80 字 (required)",
    "task": "string ≤ 30 字 (required)",
    "suggestedLine": "string ≤ 80 字 | null (optional)",
    "boundaryReminder": "string ≤ 60 字 (required, NEVER null)"
  },
  "model": "claude-haiku-4-5-... | claude-sonnet-4-...",
  "generatedAt": "ISO8601"
}
```

**驗證規則**：
- 字數超出 → server hard truncate + log warn（不阻擋回應，避免 white screen）。
- Required 欄位 missing / null（含 `boundaryReminder`） → 5xx + 不扣 credit + client 顯示重試。
- 多餘欄位（AI 自作主張） → strip silently，log warn。

### 2.4 Tone & Safety Rules（寫進 prompt）

承襲 Spec 5 long-form draft §3.D 的 avoid list，並額外明訂：

- 絕不教使用者裝冷淡 / 用話術逃避責任 / 用承諾綁住對方。
- 絕不出現 `收割 / 控住 / 壞女人 / 玩咖 / 高分妹 / 攻略 / PUA` 字眼。
- 失敗 / 拒絕情境必須降低焦慮、不製造焦慮（draft §6 frequency rule 的精神）。
- `postDateReflection` 「卡卡的」/「變慢變淡」/「還看不出來」案例：先安撫 + 觀察 + 一個小動作建議；**不**催促重訊息轟炸。
- `boundaryReminder` 必填，意圖：強迫 AI 每次都產出邊界視角，避免變成單純「教你怎麼追」工具。

---

## 3. Data Storage

### 3.1 Latest-Result Persistence — Independent Hive Box

**架構決策（Codex Q4 verdict）**：用獨立 Hive box `coach_follow_up_results`，key = `partnerId`，對齊 Partner Style Override / Data Quality 既有分離 box pattern。

理由（Codex 認可）：
- 與 `PartnerStyleOverride` (`partner_style_repository.dart`) / `PartnerDataQualityState` (`partner_data_quality_repository.dart`) 同 pattern，新進開發者一眼看懂。
- Partner entity 不再膨脹（typeId=8 next free index 7 維持給未來真正屬於 Partner 本體的欄位用）。
- 之後刪除 partner 的 follow-up 結果（cascade）邏輯可獨立測試。

### 3.2 Schema (local Hive)

```dart
@HiveType(typeId: <next free, TBD by impl plan>)
class CoachFollowUpResult {
  @HiveField(0) final String partnerId;
  @HiveField(1) final String phase; // 'prepareInvite' | 'preDateReminder' | 'postDateReflection'
  @HiveField(2) final String headline;
  @HiveField(3) final String observation;
  @HiveField(4) final String task;
  @HiveField(5) final String? suggestedLine;
  @HiveField(6) final String boundaryReminder; // required, non-null
  @HiveField(7) final DateTime generatedAt;
  @HiveField(8) final String modelUsed;
}
```

「重新生成」/「換情境」**直接覆蓋**，不保留前一張。

### 3.3 Repository Surface (impl plan must provide)

`CoachFollowUpRepository` minimum surface：

```text
- get(partnerId) → CoachFollowUpResult?
- put(result)    // overwrite latest
- delete(partnerId)
- clearAll()     // 帳號刪除 / 登出時呼叫
```

### 3.4 Required Tests (impl plan must include)

- `clearAll()` 把 box 整個清空（隱私 regression test，鏡射 Spec 1 about-me clear test）
- Partner delete cascade — 刪 partner 時 follow-up box 對應 entry 同步清除
- Per-account 隔離（如有 owner_user_id 概念，要 verify per-uid 不串場）

### 3.5 What is NOT Persisted

- 用戶 input answers（q1/q2/q3）— **不存**（Codex Q5 verdict）。原因：避免「上次你說最擔心被拒絕」這種記憶感讓用戶被綁定，並維持「latest card only」隱私模型誠實。
- AI 對局面的觀察 — **不寫回** `partnerSummary` / `partnerTraits`。
- 不寫入 Spec 1 long-term memory（about-me）。
- 不寫入 Spec 2 partner-style override。
- 重新生成時 **不預填** 上次 answers，從空白選擇起步。

---

## 4. Credit & Rate Limit

| 項目 | 規則 |
|------|------|
| 成本 | 1 message credit / 次成功生成 |
| 扣款時機 | 成功才扣（鏡射 opener pattern, line 3732 `monthly_messages_used + openerCost`） |
| 失敗（網路 / Edge 5xx / response invalid） | **不扣**，client 顯示重試 |
| Cap 檢查 | 與主分析共用 `monthly_messages_used` / `daily_messages_used` 欄位（不開獨立 quota） |
| Tier 可用性 | **Free 開放**（Codex Q6 verdict） |
| UI 揭露 | 任何「會扣額度」觸發點必須顯示「生成會使用 1 則額度」字樣 |

### 4.1 Free Tier 開放理由（Codex 採納）

- 需要 demand signal 才能決定要不要做成付費差異化。
- 1 credit / 次 + 共用 daily/monthly cap，Free 月 30 / 日 15 已天然防濫用。
- 過早 paywall 會讓產品感覺像「報告工具」而非「教練產品」。
- Failed / invalid 不扣（既有 opener 契約已驗證）。

### 4.2 Model Selection

沿用 ADR #11 規則：
- Free → Haiku (`claude-haiku-4-5-20251001`)
- Starter / Essential → Sonnet (`claude-sonnet-4-20250514`)
- v1 **不接受** images，所以「有圖片強制 Sonnet」規則不適用。

---

## 5. AI Hint（低壓確認入口的 client-side derivation）

**完全在 client，不額外吃 credit**。從既有 partner state 推：

| Signal source | Hint phase |
|---------------|------------|
| `gameStage.current == '邀約'` 且 `heatScore >= 61` | `prepareInvite` |
| 最近 conversation 含關鍵詞（明天/今晚/週末/見面/約/碰面） | `preDateReminder` |
| 最近 conversation `updatedAt` 比此 partner 平均間隔長 1.5x，且最近一輪有見面語意 | `postDateReflection` |
| 以上皆無 | 不顯示 hint，三 chip 平展示 |

**位置（Codex Q7 verdict）**：純 Dart pure function，路徑：

```text
lib/features/coach_follow_up/domain/coach_follow_up_hint_resolver.dart
```

對齊 Spec 4 `CoachActionPolicy` 的 deterministic-policy 風格，必須有 unit test。Widget 只 consume，不內嵌 trigger logic。

---

## 6. Privacy

承諾欄位：

- 用戶 input answers 只在 request body in-flight 期間存在；Edge Function **不寫 DB、不寫 log**（log 限制見 §7）。
- 結果卡只存本地 Hive。雲端**沒有**任何 follow-up 歷史。
- `partnerHint.lastConversationSummary` 在送出前 client 套 200 字 hard cap；Spec 3 flagged 時 omit。
- 刪除帳號 / 登出 → client local cleanup，呼叫 `CoachFollowUpRepository.clearAll()`（Codex Q8 verdict）；既有 `delete-account` flow 不需新加 server-side hook，但 client 在帳號清理路徑上必須觸發此 box clear，**並寫 regression test 鏡射 Spec 1 about-me `clearAll()` 測試**。

---

## 7. Telemetry / Observability

最小集合（**絕不**記用戶 free-text、Q3 內容、prompt 全文、AI 原始 response 文字）：

```text
coach_follow_up_invoked      { phase, tier, hasOptionalText: bool }
coach_follow_up_succeeded    { phase, tier, model, latencyMs, costDeducted: 1 }
coach_follow_up_failed       { phase, tier, errorClass } // errorClass = enum, 不記 errorMessage
coach_follow_up_regenerated  { phase, tier, secondsSinceLast }
coach_follow_up_phase_switched { fromPhase, toPhase, hadResultBefore: bool }
```

走既有 Edge log path（`logInfo` / `logWarn` / `logError`）。命名 prefix `coach_follow_up_*` 與 `opener_*` / `analyze_*` 不撞。

---

## 8. Out of Scope (v1, 明確不做)

- ❌ Push notification / 主動 nudge / dormant reminder（Spec 5 draft §5G / 5A）
- ❌ Intimacy aftercare（draft §5D） / short-term maintenance（5E） / fit reflection（5F）
- ❌ Chatbot 多輪對話 / 在 result card 上追問
- ❌ 結果卡歷史列表 / 跨 partner 比較
- ❌ Learning tab deep link（Spec 5 v2 候選；v1 result card 不掛文章）
- ❌ 寫入 partnerTraits / partnerSummary / about-me / partner override
- ❌ 接受截圖 input（v1 純點選 + 文字）
- ❌ 跨 partner aggregate（「你最近三個對象都 …」）
- ❌ Calendar integration / 約會時間提醒鬧鐘
- ❌ 同 partner 多 phase 結果並存（永遠只留最近一次）
- ❌ 第 4 個 phase「她回覆變慢」（Q-Eric-2 defer，v2 候選）

---

## 9. Architectural Parallels & Departures from Spec 4

| 維度 | Spec 4 (Coach Action Card) | Spec 5 v1 (Coach Follow-up) |
|------|----------------------------|------------------------------|
| 觸發 | Auto on every analyze 結果 | User-triggered only |
| 計算 | Pure-Dart deterministic policy | **Independent Edge function** AI generation (Claude) |
| Edge function | 0（純 client） | `coach-follow-up`（**獨立**，不掛 `analyze-chat`） |
| 成本 | 0 credit | 1 credit / success |
| 失敗模式 | 不會（pure function） | Network / 5xx / invalid response（client 重試） |
| Schema 來源 | Local view model | Edge response schema（外部固定 contract） |
| 持久化 | 不存（每次 derive） | Local Hive box, latest-only |
| Card 欄位 | 6 (含 `learningLink`) | 5 (無 `learningLink`，`boundaryReminder` 必填) |
| Learning link | 7/9 actionType 接文章 | v1 不接（v2 候選） |
| OCR 互動 | 0 | 0（拒收 images） |
| 主分析 prompt 污染 | N/A | 0（**獨立 Edge function** 物理隔離） |

「成本不同 → 失敗模式不同 → 持久化必要 → schema 必須對外固定 → Edge function 獨立」這條因果鏈是 Spec 5 跟 Spec 4 最大的工程差異。

---

## 10. Open Questions — All Resolved

| # | 問題 | Verdict | 來源 |
|---|------|---------|------|
| Q1 | Result card 5 欄 vs 6 欄；命名收斂 | **5 欄**；`headline / observation / task / suggestedLine? / boundaryReminder`；`boundaryReminder` 必填 | Codex |
| Q2 | 重複點擊「產生」要 client-side debounce | **Yes**（button disabled until response） | Codex |
| Q3 | `partnerHint.lastConversationSummary` 傳不傳 | **Yes**，但 (i) 限 conversation-level summary、(ii) ≤ 200 字、(iii) Spec 3 flagged 時 omit、(iv) 不傳 partnerSummary / traits / 跨對話 aggregate / 原始訊息 | Codex |
| Q4 | Latest result 存 Partner HiveField vs 獨立 box | **獨立 box** `coach_follow_up_results`；含 `clearAll()` + cascade delete + 隱私 regression test | Codex |
| Q5 | Re-generate 時要不要預填上次 answers | **不預填** | Codex |
| Q6 | Free tier 可用嗎 | **Free 開放**；UI 必須顯示「生成會使用 1 則額度」 | Codex |
| Q7 | AI hint 偵測邏輯放哪 | **Pure Dart pure function**，`coach_follow_up_hint_resolver.dart`，含 unit test | Codex |
| Q8 | 刪帳時 local box 清理路徑 | **Client local cleanup**，`CoachFollowUpRepository.clearAll()`；含 regression test | Codex |
| Q-Codex-1 | analyze-chat mode vs 獨立 Edge function | **獨立 `coach-follow-up` Edge function** | Codex |
| Q-Eric-1 | postDateReflection Q2 是否加「太早看不出」 | **加**，命名「還看不出來（剛結束 / 訊息還沒回 / 太早判斷不出）」取代「不確定」 | Codex 建議 + Eric 同意 |
| Q-Eric-2 | 是否加第 4 個 phase「她回覆變慢」 | **Defer 到 v2**（避免 v1 UI 與 prompt scope creep） | Codex 建議 + Eric 同意 |

---

## 11. Validation Before Implementation Plan

寫 implementation plan（下一個 doc）前，**必須**先有：

- [x] Eric 對 Q-Eric-1（加「還看不出來」） + Q-Eric-2（defer 第 4 phase）拍板
- [x] Codex 對 Q-Codex-1 + 全 doc 給 spec review verdict（REVISED_AND_APPROVED @ `3d8dd3a`）
- [x] 所有 Q1-Q8 + Q-Codex-1 全部 resolved
- [ ] **Eric 最終 read-through**（確認本 revision 沒走偏 Codex verdict）
- [ ] 確認 `analyze-chat` 沒有 in-flight refactor 會跟新 function 衝突（doc 已用獨立 function 隔離，此風險顯著降低）
- [ ] 確認 Partner Hive typeId 預留 / 新 typeId（給 `CoachFollowUpResult`）尚未被佔用
- [ ] 確認 telemetry log 命名 `coach_follow_up_*` 與既有 `opener_*` / `analyze_*` 不撞

### 11.1 CI/CD Note (Codex 點名)

`.github/workflows/deploy-edge-function.yml` 目前只 deploy `analyze-chat`（且必須帶 `--no-verify-jwt`）。Implementation plan 必須：

- 新增 `coach-follow-up` 的獨立 deploy step
- **不可**用 broad「deploy all functions」蓋掉 analyze-chat 的 `--no-verify-jwt` 旗標
- `coach-follow-up` 的 JWT 設定獨立決定（v1 預設 **要**驗 JWT，因為 client 必呼叫已登入用戶才能扣 credit）

---

## 12. References

- **Codex spec review (this doc)**：`docs/reviews/2026-05-02_spec5-coach-follow-up-design_codex-review.md` @ `3d8dd3a`
- **Spec 5 long-form draft**：`docs/plans/2026-04-30-memory-coach-spec5-proactive-coach-loop-draft.md`（v2+ 北極星，本 doc 不超過其 v1 scope）
- **Spec 4 final impl plan**：`docs/plans/2026-05-01-spec4-phase1-coach-action-card-impl.md`（card field convention 對照）
- **opener mode 範例**（cost / quota machinery 來源）：`supabase/functions/analyze-chat/index.ts:3352, 3606+, 3732`
- **Partner detail screen**：`lib/features/partner/presentation/screens/partner_detail_screen.dart`（區塊插入位置）
- **Partner entity**：`lib/features/partner/domain/entities/partner.dart`（typeId=8, next free index 7）
- **既有獨立 box pattern**：`lib/features/user_profile/data/repositories/partner_style_repository.dart`、`lib/features/user_profile/data/repositories/partner_data_quality_repository.dart`
- **既有 deploy workflow**：`.github/workflows/deploy-edge-function.yml`
- **CLAUDE.md OCR 紅線**（不混 commit / 不 multi-agent / `--no-verify-jwt` 部署規則）
- **ADR #11 模型選擇**：Free=Haiku / Paid=Sonnet
- **ADR #16 Spec 4 Phase 1 SHIPPED**

---

## 13. Next Step

不動 code。流程：

1. **Eric** 最終 read-through 確認本 revision 完整對應 Codex verdict（沒漏哪一條、沒走偏哪一條）。
2. （可選）**Codex** 再看一輪 revised doc 給 final ACK（如果信任 CC revision quality 也可省）。
3. 雙方 ACK 後，新開 implementation plan doc：`docs/plans/2026-05-XX-spec5-coach-follow-up-v1-impl.md`，內含 task-by-task TDD plan、CI/CD deploy step、Hive typeId 分配、subscribe regression test list。
4. Implementation plan 自身先過 Codex spec review 才開工 code。

本 doc 在 implementation 開始前**不**進 ADR、**不**進 snapshot 階段更新。

---

## 14. Codex Review Log

### 2026-05-02 — REVISED_AND_APPROVED @ `3d8dd3a`

Codex 接受 product shape，要求三項硬修改：

1. **架構**：analyze-chat mode → 獨立 `coach-follow-up` Edge function（OCR 紅線 + 隔離）。
2. **Card schema**：`whatHappened` → `observation`、`oneThingToPractice` → `task`、`boundaryReminder` 從 optional 升級為 **required**。
3. **Q3 約束**：`lastConversationSummary` 限 conversation-level summary ≤ 200 字、Spec 3 flagged 時 omit、絕不碰 partnerSummary / traits / 跨對話 aggregate。

剩餘 8 個 OPEN questions 全部 resolved（見 §10），含 Eric Q-Eric-1（加「還看不出來」）、Q-Eric-2（defer 第 4 phase v2）。

本次 revision 保留章節結構，主要 delta：
- §0 / §2.1 / §2.2 / §9 / §10：架構從「mode 分支」改寫為「獨立 Edge function」
- §1.3 / §2.3 / §3.2：欄位 rename + `boundaryReminder` 升級 required
- §1.2：postDateReflection Q2「不確定」→「還看不出來（剛結束 / 訊息還沒回 / 太早判斷不出）」
- §2.2：`lastConversationSummary` Spec 3 flagged omit 條件 + conversation-level only 約束
- §3.3 / §3.4：新增 repository surface + 必備測試清單
- §4：Free tier UI 揭露字樣（「生成會使用 1 則額度」）
- §6 / §7：privacy 與 telemetry 強化（不 log free-text，clearAll() regression test）
- §11.1：CI/CD deploy step 新增（不可被 broad「deploy all」蓋掉 analyze-chat `--no-verify-jwt`）
- §14：本日誌（新增）

Diff target: `git diff 625b13d HEAD -- docs/plans/2026-05-02-spec5-coach-follow-up-v1-design.md`
