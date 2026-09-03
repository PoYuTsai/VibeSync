# 練習室「對話主體意識」評測（conversation-agency-v1 Phase 0）

計畫：`docs/plans/2026-09-03-practice-conversation-agency-plan.md`；
夥伴報告：`docs/plans/2026-09-03-practice-conversation-agency-partner-report.md`。

問題不是「她講話不好聽」，而是**最新一個名詞就是她的議程**：沒有上下文的裸詞會被
補成一個合理話題，她還會順手編出自己的具體經歷。既有的 reply-style 評測量得出
「不同角色講話不一樣」，量不出「她是不是有自己的立場」——這支工具補的就是這一段。

每一輪都是真實 DeepSeek 呼叫（prod 同款 `deepseek-v4-flash`，Eric 2026-09-02
授權隨意調用）。20 位角色 × 17 情境 × repeat 3 約 1,870 次生成、1,030 次評審。

## 四支檔案

```bash
export DEEPSEEK_API_KEY=...   # 或放 supabase/.env（gitignore，不要 commit）

# 1. 產生 artifact（standard 路徑）
deno run --allow-env --allow-read --allow-write --allow-run=git --allow-net=api.deepseek.com \
  tools/practice-agency-eval/run_agency.ts \
  tools/practice-agency-eval/out/<date>-<label>.json \
  --mode=standard --style=1 --repeat=3 --concurrency=8
# beginner 路徑（handler 的 assisted 分支：帶 practiceMode＋溫度 40／熟悉度 10）
#   --mode=beginner

# 2. 多標籤 judge（寫 <file>-judge.json）
deno run --allow-env --allow-read --allow-write --allow-net=api.deepseek.com \
  tools/practice-agency-eval/judge_agency.ts tools/practice-agency-eval/out/<file>.json \
  --concurrency=8

# 3. 指標（純函式，不打網路）
deno run --allow-read tools/practice-agency-eval/evaluate_agency.ts \
  tools/practice-agency-eval/out/<file>-judge.json

# 自測
deno test --allow-read --allow-env tools/practice-agency-eval/
```

- `scenarios.ts`：報告 §10.1 的 A01–A15 ＋ 兩段真機截圖逐字稿（Alice
  `practice_girl_001` 一般難度、Joyce `practice_girl_026`
  挑戰難度）。每個情境是一串 固定 turn；`ai` turn 是寫死的前文（截圖重播、A01
  的「她先問一句」、A04 的「她問東東
  是誰」），**她的回覆是腳本的那一輪不打模型也不進
  judge**，逐字稿才不會多出一則不 存在於截圖的回話。只有標了 `probe` 的 user
  turn 會被評審，並宣告 `kinds`（＝指標 分母）、`mustAllow`、`mustForbid`。
- `run_agency.ts`：prompt 走 production `buildChatPromptBundle`（含 difficulty
  bakeoff 那份固定 context fixture：2026-08-28 20:30、固定
  thread、記憶摘要、一則 貼文），回覆後處理照 handler 同序（繁體→內部標籤守門→L4
  守門→style 開時剝括號 旁白）。`--mode=standard` 不帶 `practiceMode` key
  與分數、`partnerState` 為 null； `--mode=beginner` 走 assisted 分支。artifact
  meta 綁 commit／tree／dirty／prompt policy version／模型／常數，並存一份去重的
  `trustedSources`（judge 的唯一可信來源）。
  flags：`--profiles`、`--scenarios`、`--repeat`、`--mode`、`--style`、`--difficulty`、
  `--concurrency`。
- `judge_agency.ts`：DeepSeek 多標籤評審（temperature
  0）。評審看到遮罩後的逐字稿
  （只到探針那一句）、她這一則回覆、以及她的**唯一可信自身事實來源**（人物卡
  興趣／生活／自介／職業＋生活情境＋記憶摘要＋朋友圈）。八個標籤：`blind_follow`、
  `clarify_or_challenge`、`return_to_topic`、`accept_valid_answer`、`hold_position`、
  `fabricated_self_fact`、`false_challenge`、`interrogation`。輸出先寫三句判讀
  （`player_msg`／`answered`／`self_facts`）再寫八個布林，強制它先決定「玩家這句在
  這段對話裡有沒有可辨識的意思」。嚴格驗證：八個布林一個都不能少、型別錯整筆判失敗，
  只對**逐字列在 `KNOWN_KEY_TYPOS`** 的固定形態 key 手誤做 repair-first。
  遮罩用**帶型別的佔位符**（（她的名字）／（她的城市）／（她的職業）／（她的年齡）），
  只套在她的回覆與可信來源上，不套玩家訊息——玩家說「我在台中做設計」是玩家的事實，
  遮掉會毀掉 A11／A12 的題意；統一換成同一個＊則會讓職業欄位假裝背書城市聲稱。
- `evaluate_agency.ts`：純函式指標＋bootstrap 95%（1000 次、確定性
  LCG）。分母一律 來自 `scenarios.ts` 宣告的 `kinds`（結構事實），分子一律來自
  judge 的標籤（語意）：
  - `blindFollow`＝`no_context_fragment` 探針上的盲目跟題率（報告 §11 門檻 ≤5%）
  - `falseChallenge`＝`valid_short_answer`
    探針（A01／A03／A07／A09）上的誤質疑率（≤3%）
  - `fabricatedSelfFact`＝全體探針（大樣本 <1%）
  - `stancePersistence`＝同一場裡「前一個探針她真的質疑過」的配對中，下一個
    `stance_followup` 探針沒有回去盲目跟題的比例（≥95%）
  - `interrogation`＝全體探針；另有 `mustForbid` 違反率與 `mustAllow`
    滿足率、每情境表

## 設計上的取捨與已知限制

- **TypeScript 不判語意。**
  情境檔只宣告結構事實（哪一輪是探針、屬於哪個分母、前一則 AI
  是不是問句）；「這句話有沒有關聯／有沒有虛構」全部交給評審模型。
- `looksLikeQuestion` 是給 judge 的提示與
  metadata，不是判定：中文問句常常不帶問號 （「東東是誰」），只看標點會
  systematically 判錯並把錯的前提餵給評審。
- **評審歧義（實測到的）**：A03「對了 講到韓國…」這種明示換題，評審有時仍標
  `blind_follow`（它自己在 `player_msg`
  寫「有可辨識的意思」卻沒套用互斥規則）。這不 影響頭條數字（A03 只進
  `false_challenge` 分母），但代表 `blind_follow` 在**可辨識**
  訊息上偏高，跨分母比較時要小心。
- 每個探針只評一次，重複靠 `--repeat`；單一情境 n
  小時區間會很寬，看區間不要看點值。
- Alice／Joyce 截圖只有各一位角色，`--repeat`
  之外沒有樣本可加，屬於個案佐證不是統計。

## 結果紀錄

（見下方各 run；artifact 在 `out/`。）
