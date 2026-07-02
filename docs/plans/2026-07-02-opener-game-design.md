# Opener prompt Game 化（Batch 3）設計定稿

> 2026-07-02 brainstorming 逐節確認（§1 單獨 OK、§2-4 合併 OK，Eric 拍板 scope＝對齊版）。
> 前情：`2026-06-12-voice-game-system-design.md`（analyze-chat Game 體系已 ship 四關全過）；
> Codex adversarial 既有 1 high＝OPENER_PROMPT 仍含玩咖/PUA；Eric 拍板本案必加全 prompt 常數 blocking 掃描。

## 0. 定性

- 對齊版：①Apple 三層線清理＋全 prompt 常數 blocking 掃描 ②技巧名可見標注（詞彙表子集＋開場專屬詞）。
- 不做：few-shot 範例素材工程（真實高手開場局轉寫另案）、schema/client 變更、計費行為變更。
- 純 server-side（`supabase/functions/analyze-chat/index.ts` OPENER_PROMPT 常數），push 即 prod 生效，現有 TF build 直接吃到。

## 1. Apple 三層線清理

只改寫 `OPENER_PROMPT` 本體；其他 5 個常數（`OPENER_REPAIR_PROMPT`／`OCR_RECOGNIZE_ONLY_SYSTEM_PROMPT`／`SYSTEM_PROMPT`／`OPTIMIZE_MESSAGE_PROMPT`／`MY_MESSAGE_PROMPT`）不改寫、只納入掃描。

清理對照（語意保留、行為不變，只換詞）：

| 現況（2026-07-02 行號） | 轉寫方向 |
|------|---------|
| 「人格可以比 1:1 教練更偏玩咖」(2174) | 刪標籤留定義：「更鬆、更敢：鬆弛、有觀察、敢丟小框架」 |
| 「保留什麼玩咖感」(2186)／「有一點玩咖感」(2214)／「像玩咖但有邊界」(2270)／「玩咖推拉」(2324)／「抓反差、畫面和玩咖感」(2383) | 統一轉「有點壞但有邊界的鬆弛感」類描述，各處貼語境微調 |
| 「借鑑約會聊天高手、把妹高手、alpha 男的優點」(2241) | 「借鑑實戰聊天高手的優點」，優點列表不動 |
| 「不能貶低、羞辱或 negging」(2247) | 「不能貶低、羞辱、或用打壓她自尊的玩笑」 |
| 「不要 PUA 話術」(2374) | 沿 SYSTEM_PROMPT 前例（index.ts:1832）轉類別描述：「不要操控式、油膩的罐頭話術」 |

Blocking 掃描：新契約測試掃 `index.ts` 全部 6 個 prompt 常數，黑名單複用既有 18 詞（含玩咖）＋IOI/IOD regex（`index_test.ts:1480` 同款）。其他 Edge Function（coach-chat／coach-follow-up／practice-chat）prompt 實作時盤點一次：乾淨就一併鎖進測試；有正當用法（如 practice 遊戲用語）就披露再定，不硬鎖。

## 2. 詞彙表（7 詞＝子集 4＋專屬 3）

放「先讀資料，再開場」節旁，格式同 analyze-chat §6（名稱→一句定義→何時用→一個反例）。

子集（同名同定義照抄 10 詞表）：
1. **吐槽冷讀** — opener「輕微挑戰」型鉤子即此（素材＝她的自介）
2. **失格** — opener「輕自嘲」即其開場形態（定義行加註「＝輕自嘲式降壓」；10 詞表裡出口最弱的詞，開場是主場）
3. **不自證** — 「不要證明式開頭『我有認真看完自介』」直接對應
4. **框架維持** — 平等框架／非乞求感／不把自己放被審核位置

開場專屬（新增，僅入 OPENER_PROMPT）：
5. **雙球** — 一次丟兩顆球讓她選（一球微拉/畫面、一球冷讀）；twoBallPlan 欄位天然出口
6. **旁路冷讀** — 從資料旁邊長出不明說的推測（prompt 已有專節，補名字）
7. **好奇心鉤子** — 傘詞，五型（二選一/小反差/輕自嘲/畫面感/輕微挑戰）維持型名；標注寫「好奇心鉤子：二選一」

不拿：模糊邀約／合作框架／約會幻想／價值展示／推／懸念鉤（開場前用不到，或易誤導模型首句推進）。

## 3. 顯現規則（硬指令）

- `openingStrategy` 與 `recommendation.reason` 用到表內技巧**必標名＋一句為什麼**；`twoBallPlan` 建議雙球時標「雙球」。
- **openers 五句本體、talkingPoints、先鋒備案零技巧名**（可直接貼出的文字不夾教學詞）。
- 反向禁令照抄 analyze-chat：**不得為了標名而出招**；線索不足走安全開場時整份輸出零標籤完全合格。
- 既有 inline 目標質感句就地標注（「妳感覺蠻會唱歌」→旁注「旁路冷讀」；「我先把查戶口題庫刪掉」→「失格」），從示範學行為，不引進新範例素材。

## 4. 驗收四關＋成本

1. **TDD 契約**：黑名單掃全 6 常數＋詞彙表 7 詞錨＋顯現規則錨＋「openers 本體不得含技巧名」錨；既有 `opener_prompt_test.ts` 不退。
2. **Anchor smoke**：Bruce golden case bio（毛茸犬）實跑 prod，驗標注自然出現＋開場句乾淨。
3. **Eric＋Bruce 目檢**：雙向——看得到體系／不硬標。
4. **Codex 雙審**（opener＝高風險區）。

成本：詞彙表＋顯現規則約 +500-700 input tokens、清理轉寫近零和；opener 單次呼叫增量約 +$0.002，計費零改動。
