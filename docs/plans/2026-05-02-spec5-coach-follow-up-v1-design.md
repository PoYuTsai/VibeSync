# Spec 5 — Coach Follow-up v1 Design

> Status: design draft, not implementation plan. NO code yet.
> Date: 2026-05-02
> Depends on: Spec 1-4 (all SHIPPED at HEAD `0d7ff06`)
> Supersedes scope of: `2026-04-30-memory-coach-spec5-proactive-coach-loop-draft.md`
> (Draft remains as future roadmap; this doc binds v1 only.)
> Authors: Claude (draft) → Eric / Codex (review & open-question arbitration)

---

## 0. Quick Read — What v1 Is and Isn't

**Is**:
- 三個固定 flow（準備邀約 / 約會前提醒 / 約會後復盤），共用一個 Edge Function mode、一個 prompt builder、一個 response schema、一個結果卡 widget。
- 入口在 partner detail 頁面新增「教練跟進」區塊。
- 用戶點選為主、文字選填；觸發後呼叫 `analyze-chat` 新 `mode: coach_follow_up`，成功生成扣 1 message credit。
- 每個 partner 只保存最近一次結果。重生成即覆蓋。

**Isn't**:
- 不做 chatbot（單輪 in / 單輪 out，不可追問）。
- 不做 push notification（v1 純 in-app）。
- 不做歷史列表（一個 partner 只有一張卡）。
- 不寫入 `partnerSummary` / `partnerTraits` / Spec 1 long-term memory / Spec 2 partner override。
- 不污染 OCR / 主分析 prompt（獨立 prompt builder 檔，獨立 response schema）。
- 不自動建立提醒 / 不自動判定階段（AI 只能 hint，必須用戶確認）。
- 不做 Spec 5 draft 裡的 5D（intimacy aftercare） / 5E（short-term maintenance） / 5F（fit reflection） — 全部留 v2+。

---

## 1. UX Design

### 1.1 Entry Point — Partner Detail「教練跟進」區塊

固定區塊插入位置：`partner_detail_screen.dart`，建議排序（待 review）：

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
└──────────────────────────────────────────┘
```

**設計原則（硬規則）**：
- 三個 flow chip **永遠可選**，AI hint 只是建議不是強制（「低壓確認入口」）。
- AI hint 是 **client-side derivation**，不額外吃 credit（從既有 partner 狀態推）。
- 沒有 hint 信號時 chip 平展示，不顯示 hint 行。
- 結果卡只有「重新生成」（同 phase 重做）/「換情境」（回到 chooser）。沒有「儲存到歷史」（不做歷史）。

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
  □ 不確定

Q3（選填，free-text，最多 80 字）：哪個瞬間最想復盤
```

「產生跟進建議」按鈕 disabled until 所有必選題都選完。

### 1.3 Follow-up Result Card

固定 5 欄位（與 Spec 4 CoachActionCard 對齊但內容軸不同）：

| 欄位 | 內容軸 | 字數規格 |
|------|--------|---------|
| `headline` | 一句話定位這次跟進的核心（例：「不是話術問題，是節奏問題」） | ≤ 30 字 |
| `whatHappened` | AI 對局面的低壓觀察（不下判斷） | ≤ 80 字 |
| `oneThingToPractice` | 這次只練這一件事（具體動詞 + 對象） | ≤ 30 字 |
| `suggestedLine` | 可選；給一個「示意」訊息範本（不是要她直接複製） | ≤ 80 字 |
| `boundaryReminder` | 自我邊界提醒（不一定每次都有） | ≤ 60 字 |

**為什麼是這 5 欄不是 6 欄（對照 Spec 4）**：Spec 4 有 `learningLink` 因為要 deep-link 文章；Spec 5 v1 不掛 Learning（屬 v2）。Spec 4 有 `avoid` 因為是即時回覆動作；Spec 5 是節奏層，「avoid」融入 `whatHappened` 的觀察語氣裡會更自然。**OPEN Q1**：是否照搬 6 欄保留 architecture parity，還是 5 欄為精簡？

### 1.4 Loading / Error States

| 狀態 | 行為 |
|------|------|
| Loading（生成中） | 結果卡區塊顯示 skeleton + 「教練思考中…」（重用 Spec 4 / opener 的 loading style） |
| 網路 / Edge 失敗 | 顯示「生成失敗，credit 未扣，請再試」+ 重試按鈕。**Credit 必須未扣**（沿用 opener 的「成功才扣」契約）|
| Tier cap reached | 顯示 paywall sheet（重用既有 monthly/daily cap UI） |
| 同一 partner 重複點擊 | 第二次點擊 button disabled until 第一次回傳，避免 double-spend（OPEN Q2：要不要做 client-side debounce？） |

---

## 2. Backend Architecture

### 2.1 New Edge Mode: `coach_follow_up`

`supabase/functions/analyze-chat/index.ts` 新增第三條 mode 分支，鏡射 `isOpenerMode` pattern：

```text
const isCoachFollowUpMode = rawMode === "coach_follow_up";

if (isCoachFollowUpMode) {
  // Independent path:
  // 1. Validate input shape (phase + answers)
  // 2. Cost check: cost = 1, same daily/monthly gate as opener
  // 3. Build prompt via dedicated builder (see §2.3)
  // 4. Call Claude with separate response_format / tool schema
  // 5. Validate response shape
  // 6. Deduct credit (only on success)
  // 7. Return CoachFollowUpResult JSON
  // EXIT — do NOT fall through to default analyze path
}
```

**硬約束**：
- 此分支 **不讀** `partnerSummary` 也 **不寫**（Eric 硬規則）。
- 此分支 **不執行** OCR / 不接受 `images` 欄位（v1 純文字）。如果 client 不小心傳 images，後端 reject `400 invalid_input_for_mode`。
- 此分支 **不繼承** `analyzeMode` / `recognizeOnly` / 任何主分析的 flag。

### 2.2 Request Schema (client → Edge)

```jsonc
{
  "mode": "coach_follow_up",
  "phase": "prepareInvite" | "preDateReminder" | "postDateReflection",
  "answers": {
    "q1": "string (必選 enum value)",
    "q2": "string | null (選填 enum value)",
    "q3": "string | null (選填，最多 80 字 free text)"
  },
  "partnerHint": {
    "name": "string (display only, 不入 prompt 推理)",
    "heatScore": 0-100 | null,
    "gameStage": "string | null",
    "lastConversationSummary": "string | null (≤ 200 字 OPEN Q3)"
  }
}
```

**OPEN Q3**：`partnerHint.lastConversationSummary` 要不要傳？
- (a) 傳 → AI 跟進品質提升，但跨越「不寫長期 memory」邊界？（讀不算寫，但用戶可能感覺被「記得」）
- (b) 不傳 → 純粹用 phase + answers 生成，等於 generic coaching template
- (c) 傳但截斷 ≤ 200 字 + 不傳對方原話，只傳 AI summary → 折衷
- 我的推薦：**(c)**。理由：用戶在這個入口的期待是「教練懂我這段關係」，不傳會像通用文案；但只傳 summary（已是 AI 提煉過、不含對方逐字訊息）能保留隱私邊界。

### 2.3 Prompt Builder — File Layout

**獨立檔，絕不污染**：

```text
supabase/functions/analyze-chat/coach_follow_up/
  prompts.ts            # buildCoachFollowUpPrompt(phase, answers, hint) → string
  schemas.ts            # CoachFollowUpRequest / CoachFollowUpResult zod schema
  validate.ts           # validateRequest / validateResponse
  README.md             # phase semantics + tone rules
```

`index.ts` 的新分支只 import 這四個檔，**完全不**呼叫 `buildAnalysisPrompt` / `buildOpenerPrompt` / OCR helpers。

### 2.4 Response Schema (Claude → Edge → client)

```jsonc
{
  "phase": "prepareInvite" | "preDateReminder" | "postDateReflection",
  "card": {
    "headline": "string ≤ 30 字",
    "whatHappened": "string ≤ 80 字",
    "oneThingToPractice": "string ≤ 30 字",
    "suggestedLine": "string ≤ 80 字 | null",
    "boundaryReminder": "string ≤ 60 字 | null"
  },
  "model": "claude-haiku-4-5-... | claude-sonnet-4-...",
  "generatedAt": "ISO8601"
}
```

字數超出 → server-side hard truncate + log warn（不阻擋回應，避免 white screen）。

### 2.5 Tone & Safety Rules（寫進 prompt）

繼承 Spec 5 draft §3.D 的 avoid list：

- 絕不教使用者裝冷淡 / 用話術逃避責任 / 用承諾綁住對方。
- 絕不出現 `收割 / 控住 / 壞女人 / 玩咖 / 高分妹 / 攻略 / PUA` 字眼。
- 失敗 / 拒絕情境必須降低焦慮、不製造焦慮（draft §6 frequency rule 的精神）。
- 對 `postDateReflection` 「卡卡的」/「變慢變淡」案例：先安撫 + 觀察 + 一個小動作建議；**不**催促重訊息轟炸。

---

## 3. Data Storage

### 3.1 Latest-Result Persistence

每個 partner 只存最近一次結果。**Hive box 設計**：

**OPEN Q4**：用哪種儲存方式？

- (a) 新 HiveField on `Partner` entity（typeId=8, next free index 7）
  - ✅ 簡單，一個欄位
  - ❌ Partner entity 越塞越胖，違反 Spec 3 / Style Override 的「分離 box」既有 pattern
- (b) **獨立 Hive box** `coach_follow_up_results`（key = partnerId, value = `CoachFollowUpResult`）
  - ✅ 對齊 `partner_data_quality_state.dart` / `partner_style_override.dart` 的 repo pattern
  - ✅ 之後要刪整個 partner 的 follow-up 也好做
  - ❌ 多寫一個 repo + provider
- 我的推薦：**(b)**。一致性比一次性節省重要。

### 3.2 Schema (local Hive)

```dart
@HiveType(typeId: <next free, TBD by impl plan>)
class CoachFollowUpResult {
  @HiveField(0) final String partnerId;
  @HiveField(1) final String phase; // 'prepareInvite' | 'preDateReminder' | 'postDateReflection'
  @HiveField(2) final String headline;
  @HiveField(3) final String whatHappened;
  @HiveField(4) final String oneThingToPractice;
  @HiveField(5) final String? suggestedLine;
  @HiveField(6) final String? boundaryReminder;
  @HiveField(7) final DateTime generatedAt;
  @HiveField(8) final String modelUsed;
}
```

「重新生成」/「換情境」**直接覆蓋**，不保留前一張。Eric 硬規則。

### 3.3 What is NOT Persisted

- 用戶的 input answers（q1/q2/q3） — **不存**。原因：避免「上次你說最擔心被拒絕」這種記憶感讓用戶被綁定。
- AI 對局面的觀察 — **不寫回** `partnerSummary` / `partnerTraits`。
- 不寫入 Spec 1 long-term memory（about-me）。
- 不寫入 Spec 2 partner-style override。

**OPEN Q5**：那如果用戶兩天後重點開「重新生成」，要不要把上次的 answers 預填？
- (a) 不預填（純 stateless，符合上面「不存」精神）
- (b) 只在記憶體裡保留當次 session 的 answers，App 重啟即清空
- 我的推薦：**(a)** for v1。複雜度交換不划算。

---

## 4. Credit & Rate Limit

| 項目 | 規則 |
|------|------|
| 成本 | 1 message credit / 次成功生成 |
| 扣款時機 | 成功才扣（鏡射 opener pattern, line 3732 `monthly_messages_used + openerCost`） |
| 失敗（網路 / Edge 5xx / response invalid） | **不扣**，client 顯示重試 |
| Cap 檢查 | 與主分析共用 `monthly_messages_used` / `daily_messages_used` 欄位（不開獨立 quota） |
| Tier 可用性 | **OPEN Q6** ↓ |

**OPEN Q6**：Free tier 可不可以用 coach_follow_up？

- (a) Free 開放（一致性：跟主分析一樣按 message count 算）
  - ✅ 入口 + 留存體驗
  - ❌ Free 月配額 30，加上這條會更早撞上限
- (b) Starter+ only（與雷達圖、報告 tab 同檔次）
  - ✅ 給訂閱戶差異化價值
  - ❌ 影響新用戶探索
- (c) Free 限定 phase（只能用「準備邀約」其餘鎖）
  - ❌ 太奇怪、UX 複雜
- 我的推薦：**(a) Free 開放**。理由：v1 要先驗證 follow-up 這個產品形態本身有沒有 demand，鎖 tier 會讓信號變模糊。等 v2 確定價值再加 paywall。

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

**OPEN Q7**：hint 的偵測邏輯放哪？
- (a) 純 Dart pure function `lib/features/coach_follow_up/domain/hint_resolver.dart`（呼應 Spec 4 `CoachActionPolicy` 的 deterministic-policy 風格）
- (b) 內嵌在 widget 裡（簡單但不可測）
- 我的推薦：**(a)**。Spec 4 已建立 deterministic-policy + unit-test 的工法，沿用降低認知負擔。

---

## 6. Privacy

承諾欄位：

- 用戶 input answers 只在 request body in-flight 期間存在，Edge Function **不寫 DB**、不寫 log（log 只記 phase + cost + success/fail）。
- 結果卡只存本地 Hive。雲端**沒有**任何 follow-up 歷史。
- 刪除帳號（`delete-account` Edge）需一併清空本地 `coach_follow_up_results` box（**OPEN Q8**：刪帳的清理是 client 自處還是 Edge 推 signal？— 既有刪帳流程是 Edge 主導 server side，但這個 box 在 local，所以實際就是 client-side 一併清；確認既有刪帳 flow 有沒有觸發 local clear 的 hook）。

---

## 7. Telemetry / Observability

最小集合（不打用戶私訊）：

```text
coach_follow_up_invoked      { phase, tier, hasOptionalText }
coach_follow_up_succeeded    { phase, tier, model, latencyMs, costDeducted: 1 }
coach_follow_up_failed       { phase, tier, errorClass } // 不記 errorMessage 細節
coach_follow_up_regenerated  { phase, tier, secondsSinceLast }
coach_follow_up_phase_switched { fromPhase, toPhase, hadResultBefore: bool }
```

跟 Spec 4 / opener 一樣走既有 Edge log path（`logInfo`）。

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

---

## 9. Architectural Parallels & Departures from Spec 4

| 維度 | Spec 4 (Coach Action Card) | Spec 5 v1 (Coach Follow-up) |
|------|----------------------------|------------------------------|
| 觸發 | Auto on every analyze 結果 | User-triggered only |
| 計算 | Pure-Dart deterministic policy | Edge AI generation (Claude) |
| 成本 | 0 credit | 1 credit / success |
| 失敗模式 | 不會（pure function） | Network / 5xx / invalid response |
| Schema 來源 | Local view model | Edge response schema |
| 持久化 | 不存（每次 derive） | Local Hive box, latest-only |
| Card 欄位數 | 6 | 5 (待 Q1 拍板) |
| Learning link | 7/9 actionType 接文章 | v1 不接（v2 候選） |
| OCR 互動 | 0 | 0（拒收 images） |
| 主分析 prompt 污染 | N/A | 0 — 獨立 builder + schema |

「成本不同 → 失敗模式不同 → 持久化必要 → schema 必須對外固定」這條因果鏈是 Spec 5 跟 Spec 4 最大的工程差異。

---

## 10. Open Questions Summary（給 Eric / Codex 拍板）

| # | 問題 | Claude 推薦 | 影響面 |
|---|------|------------|--------|
| Q1 | Result card 5 欄 vs 6 欄（保留 architecture parity） | 5 欄 | UI / response schema |
| Q2 | 重複點擊「產生」要 client-side debounce 嗎 | Yes（button disabled until response） | Spec, low risk |
| Q3 | `partnerHint.lastConversationSummary` 傳不傳 | (c) 傳 AI summary 截 200 字 | Privacy + 品質 trade-off |
| Q4 | Latest result 存 Partner HiveField vs 獨立 box | (b) 獨立 box | Schema 一致性 |
| Q5 | Re-generate 時要不要預填上次 answers | (a) 不預填 | UX / privacy |
| Q6 | Free tier 可用嗎 | (a) Free 開放 | 商業 / 信號收集 |
| Q7 | AI hint 偵測邏輯放哪 | (a) Pure Dart pure function | 可測性 |
| Q8 | 刪帳時 local box 清理路徑 | 確認既有 flow，可能 client 即可 | 隱私合規 |

**Claude 沒推薦但需要 Codex 看**：
- Q-Codex-1：`coach_follow_up/` 該放在 `analyze-chat/` 子資料夾，還是獨立成 `coach-follow-up/` Edge function？
  - 子資料夾優點：共用 auth / subscription helper / cost machinery
  - 獨立 function 優點：完全隔離，避免「OCR 改動順便壞 follow-up」的風險（OCR 紅線哲學）
  - 兩條路都成立，需要 Codex 從架構穩定性視角拍板。

**Eric 的產品判斷題（AI 不仲裁）**：
- Q-Eric-1：`postDateReflection` 的 Q2「對方有沒有主動延續」選項要不要加「太早判斷不出來」？
- Q-Eric-2：`prepareInvite` 是不是該再加一個 phase 進入點 = 「她回覆變慢，我該不該繼續邀」？（draft §5A In-App Progress Nudge 的精神）
  - 這條 v1 是否納入會影響整體 chip 數量（3 vs 4）。

---

## 11. Validation Before Implementation Plan

寫 implementation plan（下一個 doc）前，**必須**先有：

- [ ] Eric 對所有 Q1-Q8 + Q-Eric-1/2 給定方向
- [ ] Codex 對 Q-Codex-1 + 整體架構給 spec review verdict
- [ ] 確認 `analyze-chat` 沒有 in-flight refactor 會跟新 mode 衝突
- [ ] 確認 Partner Hive typeId / new typeId 預留
- [ ] 確認 telemetry log 命名跟既有 `opener_*` / `analyze_*` 不撞

---

## 12. References

- **Spec 5 long-form draft**：`docs/plans/2026-04-30-memory-coach-spec5-proactive-coach-loop-draft.md`（v2+ 北極星，本 doc 不超過其 v1 scope）
- **Spec 4 final impl plan**：`docs/plans/2026-05-01-spec4-phase1-coach-action-card-impl.md`（card field convention / opener mode pattern 參考）
- **opener mode 範例**：`supabase/functions/analyze-chat/index.ts:3352, 3606+, 3732`
- **Partner detail screen**：`lib/features/partner/presentation/screens/partner_detail_screen.dart`（區塊插入位置）
- **Partner entity**：`lib/features/partner/domain/entities/partner.dart`（typeId=8, next free index 7）
- **既有獨立 box pattern**：`lib/features/user_profile/data/repositories/partner_style_repository.dart`、`lib/features/user_profile/data/repositories/partner_data_quality_repository.dart`
- **CLAUDE.md OCR 紅線**（不混 commit / 不 multi-agent / `--no-verify-jwt` 部署規則）
- **ADR #11 模型選擇**：Free=Haiku / Paid=Sonnet
- **ADR #16 Spec 4 Phase 1 SHIPPED**

---

## 13. Next Step

不要動 code。先讓：
1. **Eric** 把 Q-Eric-1/2 + Q1-Q8 中需要產品判斷的（Q3 / Q5 / Q6）拍板
2. **Codex** 從架構穩定性視角看 Q-Codex-1，並對全 doc 做 spec review（標 APPROVED / REVISED / REVISE / DECISION-NEEDED）
3. 雙方拍板後，新開 implementation plan doc：`docs/plans/2026-05-XX-spec5-coach-follow-up-v1-impl.md`

本 doc 在拍板前**不**進 ADR、**不**進 snapshot 階段更新。
