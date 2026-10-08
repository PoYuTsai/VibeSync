# 新話題成對評測（改前 vs 改後）

比較同一組情境下，**改前**（base）和**改後**（cand）的 production 寫出來的五題，給規格 `docs/plans/2026-10-02-new-topic-natural-lines-implementation-spec.md` §6 的盲測與驗收門檻用（ADR #51）。nt3 之後（2026-10-06）盲測改成一份逐句勾選的表 `blind.md`（規格 §6.4）。

預設是 dry-run：不打模型、不讀金鑰、不連網；會跑 git（`rev-parse`、`archive`）取出改前版本。要花錢的真跑，必須 Eric 當次說「跑」之後才下指令。

## 兩臂

| 臂 | 是什麼 | 提示詞從哪來 |
|---|---|---|
| `base` | 改前的 production，預設 `7c5cc523`（ADR #51 之前的 main） | 用 `git archive` 把那一版的 `supabase/functions` 取到暫存目錄，照當時 handler 的路由組：沒帶 `topicContext` 走 `NEW_TOPIC_PROMPT`＋`buildNewTopicUserPrompt`（外洩守門 `hasAnalyzeChatPromptLeak`、不套紅燈收尾），帶了走進階 v1 |
| `cand` | 目前工作樹的 production | `planNewTopicPrompt`：handler 呼叫同一個函式，所以提示詞、今天的日期、外洩守門、grounding、紅燈收尾規則都跟線上一致；「今天」用 `--now` 固定時間 |

- 同一案例同一次重複的兩臂用**同一個 requestId**。角度照各自那一版的清單選，基準保留改前真實的角度清單。
- 模型與參數照 production 主呼叫：`NEW_TOPIC_MODEL`、`maxTokensFor(...)`、`modelRequestParams(...)`（Sonnet 5 thinking 關閉）、system 用快取區塊、同一組 header。`run_test.ts` 會攔下 `fallback.ts` 第一跳實際送出的 body 和 header，跟 `requestBody` 比對。
- 不做修格式那一次呼叫、不串流、不走備援，也不經 Edge、DB、扣費。格式失敗照實記成「不可交付」。
- **只壞在解釋欄**（標題、為什麼現在有效、她回了之後、推薦理由不合格，開場句本身沒問題）：production 修格式會逐字保留這五句開場句，用戶看得到，所以：
  - 五句照樣進盲測；★ 用主呼叫自己的推薦（production 修格式那一次會重選，可能不同）。
  - 可交付率不算它；開場句的機械指標算它。
- `--arms=base` 或 `--arms=cand` 可以只跑一臂（沒有盲測）。`--base-ref` 只收 commit SHA。

## 案例（`cases.json` v2，22 組）

| 組 | 模式 | 看什麼 |
|---|---|---|
| B1、B2 | 基本，什麼都不選 | 最常見；B2 是工作資訊多、沒有互虧依據（最接近截圖） |
| B3 | 基本，只選想更靠近 | 作戰板寫「聊天常互虧」：玩笑要還在 |
| B4 | 基本，只選冷掉了 | 沒有對象資料、不提空窗 |
| B5、B6 | 基本，只選狀況 | 還在聊接不下去；剛約完會（不編約會細節、不約下次） |
| N1、N2 | 進階，素材「幫我想」 | 不硬編；投入普通時輕、好接 |
| J1 | 進階，你們之間的梗 | 有依據時玩笑對抗仍可用 |
| T1 | 進階，冷掉了＋看到想到她的東西 | 自然的問句不被改成判斷 |
| E1–E3、C1–C5、S1、D1、D2、W1 | 進階 | 提案的例子、各種冷掉追問、燈號、五種素材；E2、W1 是紅燈收尾 |

對象資料用三份固定的人工作戰板，格式照 `NewTopicPartnerContextBuilder`；B4、C3 沒有對象資料。「關於我」已停用，一律不送。每個案例都先過 production 的 `sanitizeNewTopicRequest` 與 `hasNewTopicMaterial`。

## dry-run（不花錢）

在 repo 根目錄（WSL）執行：

```sh
deno run --no-prompt --allow-read --allow-write --allow-run=git,tar \
  tools/new-topic-two-stage-eval/run.ts --tag=nt4-dry --repeat=2
```

在 `out/<tag>/` 寫 `manifest.json`（兩臂的 HEAD、提示詞與案例 sha256、模型參數、估算）、`system-prompts.json`（每份系統提示詞全文，以 sha256 為鍵）、`prompts.json`（每次呼叫的使用者提示詞），最後印出呼叫數與費用估算。同名輸出目錄已存在會拒絕執行，不覆寫任何證據。

**費用估算方式**（保守）：
- input token＝（系統＋使用者提示詞字數）×1.5。本機沒有 tokenizer，這是估計值，不是實數。
- input 全部用四種 input 單價裡最高的「快取寫入」價計算（system 開了 ephemeral 快取，第一次寫入是一般 input 的 1.25 倍）。
- output 一般每次 1,200，最壞每次 `max_tokens`（3,000）全滿。
- 單價取 `_shared/model_pricing.ts` 的 `SONNET_5_PRICING`：input $2/M、快取寫入 $2.5/M、output $10/M。
- 22 組 × 2 次 × 2 臂＝88 次呼叫：一般約 $2.75、最壞約 $4.33（提示詞 v2.4）。

## 真跑（要 Eric 當次說「跑」）

```sh
deno run --no-prompt --allow-read --allow-write --allow-run=git,tar \
  --allow-env=HOME --allow-net=api.anthropic.com \
  tools/new-topic-two-stage-eval/run.ts --tag=nt4 --repeat=2 \
  --run --confirm-paid --max-calls=88 --budget-usd=4.5
```

守門：

- `--run --confirm-paid --max-calls --budget-usd` 少一個就拒絕啟動。這些是技術守門，不能取代 Eric 的授權。
- 追蹤檔有未提交修改就拒絕（結果要能對應工程 HEAD）。金鑰讀 `~/.config/anthropic/key`。
- **每次送出前預留最壞情況**：估計 input token 全部用快取寫入價、output 用 `max_tokens` 全滿。已花費＋這次預留超過 `--budget-usd`，或到 `--max-calls`，就整批停；剩下的記 `NOT_RUN_CAP_OR_STOP`。
- **每字 token 數會校正**：一開始用 1.5。每次回來用實際 usage（一般＋快取寫入＋快取讀取）換算；比 1.5 高就改用實測值，之後的預留跟著變大，不會變小。
- **預算不是嚴格上限**：token 數是估的。第一次呼叫還沒有實測值，若實際 token 比字數×1.5 多，那一次的實付可能超過預留，總額可能略超過 `--budget-usd`。
  - 每次的預留與「實付是否超過預留」都記在 `requests.jsonl`、`records.json`。
  - `summary.md` 列出超過幾次。
- API 失敗或沒回 usage：成本當預留額計入，並停止後續呼叫，不當免費。
- 送出前後都寫 `requests.jsonl`，每次回來就重寫 `records.json`，中斷不會靜默重送。

輸出在 `out/<tag>/`（已 gitignore）：

| 檔案 | 內容 |
|---|---|
| `records.json` | 每次呼叫的使用者提示詞、模型原文、usage（含快取）、預留與實付、整理結果、字面計數 |
| `summary.md` | 費用、正式驗收資格（資料完不完整）、兩臂（全部／基本／進階）的機械指標、規格 §6.5 第 5、6 項門檻 |
| `blind.md` | 給 Bruce 的盲測表：每組兩版依 seed 打亂成甲／乙，附對象資料與用戶的回答；逐句勾選，不標 ★ |
| `reveal-map.json` | 解盲表（哪一版是甲、乙）；**不要跟盲測表一起給 Bruce** |
| `manifest.json` | 跑完後另加實際呼叫數、費用、校正後的每字 token 數、正式驗收資格與指標 |

## 模型對照（`--compare=model`，Eric 2026-10-08）

同一份提示詞只換模型，先看 Sonnet 5.5 能不能處理已知問題，再決定要不要加第二次審稿呼叫。這是已知問題的小型診斷，**不是 §6.5 驗收，也不是沒看過的案例測試**；`tally.ts` 會把它列為不能驗收。

- 兩臂都用目前工作樹的 `planNewTopicPrompt`（同 `cand`，「今天」用 `--now` 固定），同案例、同 requestId、同重複次數。不取改前版本，所以不收 `--base-ref`。
- `base`＝production 的 `NEW_TOPIC_MODEL`；`cand`＝Sonnet 5.5。模型參數由 `_shared/model_request_params.ts` 依模型決定，跟 `fallback.ts` 每一跳送的一樣（`run_test.ts` 兩個模型都比對）：

| | `base`（`claude-sonnet-5`） | `cand`（`claude-sonnet-5-5`） |
|---|---|---|
| thinking | `{"type":"disabled"}` | `{"type":"adaptive","display":"omitted"}` |
| `output_config` | 不送 | `{"effort":"low"}` |
| `max_tokens` | 3,000 | 7,000：思考和可見文字共用的總上限（helper 在 3,000 上加 4,000，API 不會分開限制兩者） |
| temperature | 不送 | 不送（5.5 送非預設值會 400） |
| system 快取、header | 同 production | 同 production |

- 每次只送一次：不重試、不修格式、不走備援、不串流。拒答、`max_tokens` 截斷、格式壞都照實記錄、繼續下一筆；API 失敗或沒回 usage 就照預留計費並整批停。
- 費用估算：5.5 的思考 token 算在 output 裡，effort low 在新話題用多少還沒量過，一般多抓 1,000；最壞照 7,000 全滿。
- 六個案例 B4、E3、J1、S1、D1、C2 各兩次、兩臂＝24 次（dry-run 保守估計一般約 $0.92、最壞約 $1.71）：

```sh
# dry-run（不花錢）
deno run --no-prompt --allow-read --allow-write --allow-run=git,tar \
  tools/new-topic-two-stage-eval/run.ts --tag=nt5-model-dry \
  --compare=model --only=B4,E3,J1,S1,D1,C2 --repeat=2

# 真跑（要 Eric 當次說「跑」）
deno run --no-prompt --allow-read --allow-write --allow-run=git,tar \
  --allow-env=HOME --allow-net=api.anthropic.com \
  tools/new-topic-two-stage-eval/run.ts --tag=nt5-model \
  --compare=model --only=B4,E3,J1,S1,D1,C2 --repeat=2 \
  --run --confirm-paid --max-calls=24 --budget-usd=2
```

- `summary.md` 多一節「時間與費用（每臂）」：送出、有回、API 失敗的次數，停止原因（end_turn／max_tokens／refusal），等待的算術中位數、最慢與超過 45 秒（算所有實際送出的請求，含逾時失敗），output token、實付；機械指標照常列，不列 §6.5 門檻表。
- 不實、主詞與邏輯、尷尬、推薦能不能原樣傳，要看 `records.json` 逐句判斷。

## 結構方案的程式核對原型（`review_check.ts`，Eric 2026-10-08）

PR #93 結構方案（生成候選 → 獨立審稿 → 程式核對）裡「程式」那兩步的原型，只在評測工具裡，**沒有接進 handler**：
- `buildSourcePack`：從正式的使用者提示詞取出原始來源，原文照抄、編 ID（作戰板 `P*`、關於我 `U*`、局面 `S*`、素材 `M1`、今天 `T1`）。缺的就是缺；節奏分數和作戰板最後那行規則不當來源。
- `checkReview`：核對審稿輸出。
  - 每段標記帶段號和那段原文，要對得回程式切出的段；錯位、漏標、段號重複都算沒通過。
  - 標成事實的段要附範圍（事件、習慣、擁有、說過、狀態、日期）、來源 ID 和原文。原文要逐字出現在那個來源裡、跟這段至少有兩個字連著相同，而且那類來源撐得起這個範圍：用戶的事件只能來自「用戶最近遇到的事」「看到想到她的東西」，梗撐不起單次事件，「她說過」只能來自素材（作戰板不能冒充她說過的話），「今天」只撐得起日期。
  - 句子有時間詞（今天、剛、昨天、這次、這幾天…）、「我每次／我一定要…」或用戶自己的「我家、我養、我有一隻…」，就是在講事實：標成看法、猜測、一般話題或招呼都剔除，標成問題要真的在問；時間詞還要出現在附的原文裡。「我有個問題」這種開場不算。
  - 原文沒寫明的關係不能升級：
    - 講誰有什麼（我家、妳養、她有一隻…），從擁有者那個字到這段結尾都要逐字出現在附的原文裡（妳換成她，句尾語氣詞不算），標成哪個範圍都核對。「看到一隻貓」「我家附近常有一隻貓」撐不起「我家有一隻貓」，「我有一個朋友養了一隻貓」撐不起「我養了一隻貓」。這是保守做法：改寫成「我家那隻貓」也會剔除；標成擁有、句子卻沒有這種寫法（例如「我的貓」），也剔除。
    - 原文是想做、打算做或假設的事，句子就不能寫成做了、有了（句子本身也是想或假設的除外）。「想、準備、如果…」在附的原文裡，或在來源同一小句裡、附的原文前面，都算：只附「學衝浪」也看得到「她說一直想學衝浪」的「想」。
  - 「兩個字連著相同」只是初篩，擋得住完全無關的引用，不代表原文撐得起這段。
  - 有問題代碼就剔除；選的 5 句都要通過、★ 在其中，否則整筆失敗、程式不換句；交付的句子依 ID 從候選原樣複製。
- `preReviewProblems`：審稿前刷掉亂碼、控制字元、一句兩問。

`review_check_test.ts` 用 Eric 列的 nt5-model 正反例當測資，審稿輸出是手寫的。除了審稿照規則標的情況，也測審稿標錯時程式必須擋下的：事件標成看法、拿「每次」的習慣證明「今天」、挪用無關的原文、原文沒有的時間、日期撐天氣、看到或「我家附近」「朋友養的」撐擁有（改標狀態、說過也一樣）、想做或假設撐做了（附的原文沒截到「想」也一樣）、標記錯位。它只證明程式核對的流程；審稿模型會不會這樣標，要付費的審稿回測才知道。

程式還擋不住的（字面規則抓不到，要靠付費回測量）：
- 沒有上面那些字的事件或習慣被標成看法，例如「朋友直接笑我」。
- 附的原文跟這段有關、卻撐不起多加的細節，而審稿沒標「加細節」，例如「硬走到櫃台才發現」引用「才發現走錯分店」。
- 用別的寫法講擁有，例如「我的那隻貓」標成狀態、「妳有男朋友」（「有」後面沒接數量）。
- 問句裡夾著用戶自己的事，例如「我今天點的飲料妳猜是什麼？」：程式當成真的在問。

## 盲測與驗收

### 盲測表（`blind.md`）

每組是同一個情境的兩版（甲、乙），各五句，上面附對象資料、用戶的回答與用戶寫的那句（「不實」要對照它）。Bruce 只改方框和「＿」：

```text
### 甲
- 甲1 [x]會傳 [ ]尷尬 [ ]不實｜剛路過一家超浮誇的甜點店，第一個想到妳
- 甲2 [ ]會傳 [x]尷尬 [ ]不實｜…
…
- [x] 甲有一句有趣或有個性

- 十句裡最想傳（填代號如「乙3」；都不想傳填「都不要」）：甲1
- [x] 這組評完了（沒勾＝未評，整組不計分）
```

- 每一句三格各自判斷：**會傳**（照原樣直接傳）、**尷尬**、**不實**（寫了資料沒有的事、主詞或誰說誰做弄反，或越界）。
- 「沒有」和「未評」分開：評完的組裡沒勾＝沒有；沒勾「這組評完了」的整組算未評，不計分，正式驗收就是「未完成」。
- 表上不標 ★：推薦句的會傳、尷尬，解盲後由 tally 從逐句勾選取，位置用 records 裡用戶看到的推薦（紅燈收尾改推第一題的，取改推後的）。評分時不知道哪句被推薦，不會被影響。
- 甲乙順序只由 seed 決定，跟模型輸出無關，所以 seed 預設每次隨機，記在 `manifest.json`。manifest 跟解盲表一樣，評完才給評分的人。nt3 用的舊預設 `20261001` 位置已公開，不要再用；要重現某一次的表才用 `--seed` 指定。
- ★ 解釋（標題、理由）的人工評分這輪暫緩、未評（Eric 2026-10-06）；6a、6b 的機械檢查照常。

### 計分與完整度

1. 把 `blind.md` 給 Bruce 填。全部評完才看 `reveal-map.json`。
2. 執行 `deno run --allow-read --allow-write tools/new-topic-two-stage-eval/tally.ts --tag=nt4`。方框或「最想傳」看不懂、勾了評完卻沒填最想傳，就整個拒絕，不會猜。
3. **完整度**：`manifest.json`、`records.json`、`reveal-map.json` 與 `blind.md` 要一起對得上完整的 22 組 × 2 次 × 兩臂。下列任何一種都列進「資料不完整」：
   - 評測沒跑完、只跑部分案例或一臂、每組不是 2 次。
   - 案例檔換過、評測時工作樹不乾淨。
   - 模型呼叫不是 88 次；有呼叫沒跑到或 API 失敗。
   - records、解盲表或盲測表的組別缺少、重複或多出來。
   - 解盲表的甲乙不是一邊基準、一邊候選。
   - 有組沒評完；表上的句子跟 records 不一樣（改過字或拿錯表，那組不計分）。

   資料不完整時，`acceptance.md` 整份標「未完成」（每一項都不給 ✓／✗），指令以失敗結束，不能當正式驗收。
4. `out/<tag>/acceptance.md` 列出規格 §6.5 每一項，數字都附分母：
   - 1：候選 0 句不實。被勾不實的候選句子逐句列出，要對照輸入確認。
   - 2a：尷尬句數候選 ≤ 基準一半。2b：★ 尷尬次數（44 次產出）候選 ≤ 基準，而且至多 1 個情境（22 個情境，同情境兩次任一次算）。
   - 3a、3b：會傳句數、★ 會傳次數候選 ≥ 基準。3c：基本、進階分開看，任一邊退步就標「需交代」，不能寫「全部通過」。
   - 4a：有一句有趣的版本數候選 ≥ 基準八成。4b：B3、J1、E3 兩次都要有候選的評分，而且有一句有趣；缺一組也不算過。
   - 5、6：`records.json` 的機械計數。
   - 參考：全部／基本／進階分開的會傳、尷尬、不實、★、有趣、最想傳，以及十句都不想傳的組數。

## 機械指標

開場句的指標算「開場句可評」的輸出（可交付＋只壞在解釋欄）；★ 解釋的兩項只算可交付。失敗會列在「可交付／輸出」「開場句可評／輸出」，也算進素材比率的分母，不從分母偷偷刪掉：

- **規格 §4.6 的六項字面計數**：問句、一則兩個以上問句、假設情境、安排角色、貼標籤或說她是哪種人、比能力。另外觀察宣告套話（「我有個…」「這點我不退讓」）。五題全算一次，★ 那一題另外算。
- **開場句字數**：中位數、P90、超過 35 字的句數。
- **四種尷尬句型合計**（第 5 項）：候選要小於基準；基準已是 0 時，候選也是 0 就算過（ADR #51 產品裁決 4）。
- **近似重句**：同案例第 1、2 次之間的句子對，二字詞 Jaccard ≥ 0.5 算一對。
- **★ 標題的手法字**、**★ 解釋夾英文**：素材或作戰板原本就有的英文名稱不算。
- **production 稽核同一套規則**：推薦題用到素材、她沒回我提空窗、紅燈／冷掉了／基本模式的邀約字眼（D9）、在嗎類開場、紅燈收尾（模型自己推第一題、伺服器改推）。
- **我沒回她：道歉、解釋或提空窗的句子**（ADR #51 產品裁決 5，這三種都不寫）：道歉、提空窗用 production 稽核的樣式，另加「斷線」「比較忙」「晚回」這類解釋。

這些是字面計數，只看趨勢，不是語意判定；用戶講自己的句子也可能被算進去。「不實」「會傳」「有趣」要靠盲測。

## 測試

```sh
deno check tools/new-topic-two-stage-eval/run.ts tools/new-topic-two-stage-eval/tally.ts tools/new-topic-two-stage-eval/review_check.ts
deno test --allow-env --allow-read tools/new-topic-two-stage-eval/run_test.ts tools/new-topic-two-stage-eval/review_check_test.ts
```

`run_test.ts` 不打模型、不跑 git、不寫檔。它測：
- 參數守門。
- 22 組案例都合法。
- 候選路由等於 `planNewTopicPrompt`。
- 基準路由照改前 handler（用工作樹裡還留著的舊版函式驗規則）。
- 請求 body 與 header 等於 `fallback.ts` 實際送出的。
- 估算與預留：快取寫入價、usage 怎麼分都不超過預留、每字 token 數校正、送出前守門。
- 外洩與紅燈收尾。
- nt3 失分的案例（E1、C5、B6、D2、E3、J1、T1）都帶到 v2.4 的對應規則。這只證明規則送到了，模型照不照做要看盲測。
- 只壞在解釋欄：五句進盲測、★ 用主呼叫自己的推薦、不算可交付。
- 模型對照：兩臂同一份提示詞只換模型、不收 `--base-ref`；5.5 的 body 等於 `fallback.ts` 送 5.5 那一跳；估算與預留照各自模型的 `max_tokens`；摘要寫明不是 §6.5 驗收；`tally.ts` 把它列為不能驗收。
- 字面計數、近似重句、我沒回她的道歉／解釋、機械門檻（含基準為 0）。
- 盲測表：打亂、不露臂名、不標 ★；逐句勾選的解析（看不懂就拒絕）、未評和沒有分開、★ 從 records 取（含紅燈收尾）、句子對不上 records。
- 門檻：★ 尷尬的兩個分母、基本／進階退步標「需交代」。
- 完整度：只跑一部分時「未完成」；全部齊、每組評完才可能通過；缺、重複、多出、未評、只跑部分都列出來。

這支測試在 PR CI 的 Edge contract tests 裡。
