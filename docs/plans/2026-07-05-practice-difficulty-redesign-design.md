# 練習室難度分級重設計（2026-07-05）

## 問題

三檔難度（輕鬆／一般／挑戰）體感無鑑別度，全部偏簡單（Eric dogfood 回報）。

根因（已查證）：
- 難度唯一作用＝往女生 system prompt 塞一段 2~3 句「內在判斷尺度」軟描述（`practice_persona.ts:241-263`）。
- 好感度計算（`temperature.ts`）、每日翻牌（`draw_decision.ts`）、hint、輪次上限全部不看難度（grep 零引用）。
- LLM 預設人格偏友善配合，「你可以冷處理」這種授權式軟指令拉不動整份人設 prompt。
- UI 三個 chip 無任何文案說明，使用者無從感知差異。

關鍵機制事實：
- 溫度（heat/familiarity 雙軸）只在 **beginner 模式**存在；standard 模式無任何數值系統。
- 溫度是規則式 delta（LLM 分類器 → 矩陣查表），初始 30/0，clamp 0–100。
- 「約成功」無數值門檻，只有 debrief 的 `dateChance`（low/medium/high，LLM 質性）。
- 無敗北狀態；結束只有 20 則 AI 上限與 3 輪 thread 上限。

## 拍板決定

1. 鑑別度＝**過程口感＋結果差異雙軌**都要。
2. 曲線錨點：**現狀行為 ≈ 新的輕鬆**；一般、挑戰往上拉。
3. 本期**不加**高難度獎勵誘因（不碰剛上線的 gacha 權重）；誘因另案。
4. 重心壓在槓桿 B（prompt 行為規格重寫），A/C 為配套——因 standard 模式只有 prompt 可用。
5. 驗收不靠體感，走腳本化 bakeoff。

## 設計：三支槓桿

### 槓桿 A：DIFFICULTY_TUNING 調參表（機械，僅 beginner 生效）

| | 輕鬆 | 一般 | 挑戰 |
|---|---|---|---|
| 起始溫度 | 35 | 28 | 20 |
| 正向 delta 倍率 | ×1.25 | ×1.0 | ×0.7 |
| 負向 delta 倍率 | ×0.75 | ×1.0 | ×1.3 |

- 表放 `practice_persona.ts`，`temperature.ts` 計分管線吃倍率（scaleByQuality 之後、clamp 之前）。
- deterministic、可單元測試；挑戰從 cold band 起步、升溫慢、犯錯掉更快。

### 槓桿 B：難度行為規格重寫（prompt，兩模式都吃，主力）

`DIFFICULTIES` 的 prompt 從氛圍描述改為四欄規格：

1. **開場姿態**：輕鬆＝友善接球（≈現狀）；一般＝中性禮貌、≤2 句、第一輪不主動反問；挑戰＝冷淡短回（10 字內）、不反問、不加 emoji。
2. **回覆形狀配額**：一般＝對方訊息無資訊量時你的回覆必須比他短；挑戰＝每 3 輪至少 1 次句點/敷衍短回（該輪對方高品質訊號除外）、絕不主動開新話題。
3. **觸發條件表**（if X then 必須 Y）：連續兩輪只問不分享 → 一般變短／挑戰句點；讚外貌或太快邀約 → 一般降溫／挑戰吐槽或已讀式回覆；對方訊息超過你三倍長 → 挑戰照樣短回。
4. **few-shot 例句**：每檔 2~3 條示範回覆（挑戰示範句點、吐槽、轉話題口吻）。

順手修：
- 砍 `prompt.ts:112` 全難度共用、寫死「easy」字樣的混淆句，改引用當場難度。
- 難度規格區塊移到 prompt 尾端高權重位置。

### 槓桿 C：約成功判準分級

- 女生 prompt 邀約 checklist：輕鬆 1~2 個正向訊號／一般 2~3 個／挑戰 4 個以上高品質訊號（接住興趣＋自然調情＋具體低壓場景＋無壓迫感），缺一保留。
- debrief prompt 的 `dateChance` 判準同步分級：挑戰拿 high 必須表現完整，防「難聊但好約」。

### UI 文案（最小改動）

難度 chip 選中時顯示一行副標：
- 輕鬆「她今天心情不錯，願意給你空間」
- 一般「真實交友軟體體感，會已讀、會變短」
- 挑戰「高標準對象，不救場、會句點你」

## 驗收：bakeoff（上線 gate）

固定 3 組 user 訊息腳本（爛開場查戶口型／普通型／高品質型），三難度各跑數場，量：
1. AI 回覆平均長度
2. 句點/敷衍輪占比
3. （beginner）溫度終值與軌跡
4. debrief dateChance 分布

**過關標準：挑戰 vs 輕鬆在「回覆長度」與「dateChance」兩項拉開明顯差距**，否則回頭調規格、不上線。

## 改動清單

1. `supabase/functions/practice-chat/practice_persona.ts`：DIFFICULTIES 規格重寫＋DIFFICULTY_TUNING 表
2. `supabase/functions/practice-chat/temperature.ts`：起始值與正負倍率吃調參表（beginner only）
3. `supabase/functions/practice-chat/prompt.ts`：砍混淆句、難度區塊移位、debrief 判準分級
4. `lib/.../practice_chat_screen.dart`：難度 chip 副標文案

風險：非高風險區（不碰訂閱/quota/計費）；出貨前照慣例 Codex review。
