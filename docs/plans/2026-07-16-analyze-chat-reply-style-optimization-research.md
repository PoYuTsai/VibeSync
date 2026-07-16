# Analyze-chat 五風格回覆：產出機制研究＋自然度/可用性優化提案

> 日期：2026-07-16 · 狀態：研究完成，優化未實作 · 性質：純研究文件，未動任何 prompt / 程式碼
> 前置脈絡：仲裁佇列 OPEN「2026-06-12 主 prompt 全面 few-shot 化（voice 判輸）」、OPEN「2026-06-12 方案二 Golden 形狀重構」、2026-06-13 球數案硬版 SHIPPED（後 fail-soft `f417bd8`）

## 一、五種回覆是根據什麼產出的（機制盤點）

1. **風格清單硬編碼**：`extend / resonate / tease / humor / coldRead`，`supabase/functions/analyze-chat/stream_events.ts:5-11`（`STREAM_STYLES`）。free 只允許 `extend`（`index.ts:527`、`tier_sync_contract.ts:55-61`），付費五風格全出。
2. **內容規則來源＝`SYSTEM_PROMPT`**（`index.ts:1029-2351`，約 1,300 行），對五張卡直接起作用的段落：
   - §1.8 五種回覆品質契約（`index.ts:1441-1481`）：每風格一條「A＋B＋C」公式定義（如 extend＝接住具體話題＋補生活畫面＋丟低壓小問題）；每卡須過「接球三步」；**五風格必須圍繞同一個 catchablePoint**（1449）；禁報告腔句型清單；一組絕命毒師 ❌/✅ 單句範例（1473-1480）。
   - 一球一回／分段引用（`index.ts:1394-1415`）：連發 ≥4 則時 replySegments 通常 ≥3，段段綁 sourceIndex/sourceMessage。
   - AI 人設 8 特質（1059-1109）、場景觸發矩陣（1121-1254）、技巧詞彙表＋顯現規則（1261-1286）、備用技巧工具箱（1548-1740）。
   - voice few-shot 完整範例僅 2 組（1845-1990：熟絡局 callback／陌生冷開局）＋ 1 組 JSON schema 範例（1742-1843）。
3. **串流契約再加一層**（`stream_prompt.ts` `buildStreamSystemPrompt`）：先 emit `analysis.inventory`（接/併/略盤點）→ decision → recommendation → **每個允許的風格各一個 `analysis.reply_option`（選中先出）**；選中風格 segments ≥ min(3, 接+併球數)，且「**選中風格不得寫得比其他風格短**」（43-44 行）。floor 自 2026-06-13 起 fail-soft：只是 prompt 壓力語，server 不 reject（39-42 行註解明令不得重新硬化、改字串須黑箱重驗）。
4. **模型與參數**：`selectModel`（`index.ts:4305-4334`）— free 預設 Haiku 4.5、約 30% 條件升 Sonnet；starter/essential 一律 Sonnet 4.6；含圖強制 Sonnet。**所有 analyze 呼叫皆未設 temperature**（API 預設）。stream `max_tokens=3200`（`index.ts:4302`）需涵蓋盤點＋決策＋推薦＋全部風格卡＋metrics＋報告段；prompt 明示「輸出太長先砍報告段」。
5. **Server 後處理只驗證、不改寫**：reframer 組裝 segments（`\n` join 成 legacy `replies`，`reframer.ts:1382-1389`）；`post_process.ts` 補欄位＋剝 tier 外 key；`guardrails.ts` 僅安全命中時整組換罐頭安全回覆；`ball_inventory.ts`／`anchor_drift.ts` log-only。**沒有任何環節會把不自然的措辭改好——語感 100% 取決於模型一次生成。**
6. **Client 呈現**（`lib/features/analysis/presentation/widgets/reply_style_card.dart`）：五張橫滑卡（🔄延展/💬共鳴/😏調情/🎭幽默/🔮冷讀），每卡列 approach＋segments（最多顯示 3 段，逐段可複製、可整組複製），AI 推薦卡另有徽章。

## 二、「不自然、可用性偏低」根因分析（依證據強度排序）

### R1 公式填空效應（有正式紀錄）
風格定義是公式、few-shot 只有 2 組場景 → 模型在「填模板」而非「說人話」。仲裁佇列 2026-06-12 已記錄：Eric 同截圖對比免費 ChatGPT，VibeSync 結構對但回覆是「禮貌模板、零 callback」，voice 主觀判輸；驗收標準「不求贏、至少不輸」。刀 1-4 已上線但項目仍 OPEN——**此問題已知未結案，本次用戶回饋是同一根因的再現**。

### R2 結構壓力壓過語感
segment floor＋「選中風格不得比其他風格短」＋「有內容的球預設都接（上限5）」→ 主推回覆固定攤成 3+ 段。真人聊天多為 1-2 則短訊；為滿足 floor 硬出的段讀起來像逐條回作業。06-13 為救「吞球」上的閘，副作用是把「回好」壓成「回滿」。

### R3 五卡同質化
契約 1449 要求五風格全綁同一 catchablePoint、又共用同一批接/併球 → 五張卡像同句話的五種改寫，用戶體感可挑選項只有一兩張，「5 種風格」名不符實。

### R4 強制五風格全出
局勢不適合調情/幽默（剛認識、低熱度、嚴肅話題）時模型仍必須硬擠 tease/humor → 油/尬的爛卡拉低整體可用性印象。prompt 只約束「tease 只做微拉」，沒有「本輪不適用」的出口。

### R5 模型與 token 負載
free 大宗流量走 Haiku 4.5，跑同一份 1,300 行 prompt（其中 2069-2351 opener 段落與分析路徑無關）；3,200 tokens 全家桶下每卡實際預算被擠壓。小模型＋巨量規則＝規則遵循優先於語感。

## 三、優化提案（分三階段）

### Phase 1：prompt-only 語感優化（低風險，建議先做）
1. **few-shot 擴充**：每風格補 2-3 組跨場景（冷開局/升溫/熟絡/低熱度救場）golden 範例，重點示範 callback、口語節奏、短句；沿用「刀」迭代＋盲測流程與 10 詞彙表。
2. **鬆綁長度壓力**：「選中風格不得比其他短」改為「涵蓋 floor 即可」；「有內容的球預設都接」改為「積極併球、預設 1-2 則訊息」，floor 保留但鼓勵 `併`（不碰 fail-soft 機制本身）。
3. **降低同質化**：只要求選中風格綁 catchablePoint，非選中風格允許換球點/角度切入。
4. **分析路徑 prompt 瘦身**：analyze 呼叫剝除 opener 段落（2069-2351）。⚠️ ADR#19 曾提 main-prompt byte-lock 疑慮＋prompt caching 影響，動之前先確認。

### Phase 2：schema 相容的適應性（中風險）
- 每卡增output `styleFit`（高/中/低）或一句「什麼情況用這張」；client 依 fit 排序、低適配卡摺疊。free/paid schema 不變、事件 known-optional（守 06-13 軟版先例）。
- 低熱度/嚴肅場景允許模型宣告某風格「本輪不適用」＋一句替代說明，取代硬擠爛卡。

### Phase 3：策略意圖重構（高風險，另立專案）
- 呼應 ADR#19 方案二：從 5 個固定修辭風格改為依局勢生成的策略選項（懸念鉤/模糊邀約/角色反轉…）。需 Edge schema＋UI 改動＋計費面重評。

## 四、紅線與驗收（任何階段皆適用）

- **紅線**：不得重新硬化 fail-soft（`stream_prompt.ts:39-42`）；不碰 `sanitizeReplySegments` 丟段路徑、計費時序（INV-H1/H2/H5）；client 段數上限與 server 同步（`analysis_models.dart:242-245`）。
- **驗收 gate**：黑箱重打 golden（prod curl stream，`tools/voice-benchmark/cases/`）＋盲測 vs 免費 ChatGPT baseline；單元測試只是護欄。AI prompt＝高風險區，Codex 雙審 APPROVED 前不得宣稱 dogfood-safe。
- **回退**：Phase 1 為純 prompt diff，回退＝revert 單一 commit＋黑箱復測。
