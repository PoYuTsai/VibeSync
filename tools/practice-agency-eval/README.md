# 練習室「對話主體意識」評測（conversation-agency-v1 Phase 0／1）

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
  flags：`--profiles`、`--scenarios`、`--repeat`、`--mode`、`--style`、`--agency`、
  `--difficulty`、`--concurrency`。`--agency=on|shadow|off`（預設 off）就是
  production 的 `PRACTICE_CONVERSATIONAL_AGENCY_ENABLED`，走 handler
  同一條路徑餵 `buildChatPromptBundle`；standard
  的短期狀態從逐字稿現推（不帶持久化）。
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
- **評審歧義（Phase 0 實測到、Phase 1 已修）**：A03「對了
  講到韓國…」這種明示換題， 評審曾經仍標 `blind_follow`（它自己在 `player_msg`
  寫「有可辨識的意思」卻沒套用 互斥規則）。判準補上「『跟上一句無關』不是
  blind_follow 的判準」之後 A03 從 30% 降到 2%。**判準改過，所以 Phase 0
  記錄的第一版數字與之後的不可比**，下面「重跑 judge」那一節是新的 baseline。
- 每個探針只評一次，重複靠 `--repeat`；單一情境 n
  小時區間會很寬，看區間不要看點值。
- Alice／Joyce 截圖只有各一位角色，`--repeat`
  之外沒有樣本可加，屬於個案佐證不是統計。

## 結果紀錄

### 2026-09-03 Phase 0 baseline（commit `fba9e7aa`，20 位代表角色 × 17 情境 × repeat 3）

兩支 run 都是 `--style=1`（reply-style 旗照 production
現況開著），一般難度；截圖情境 自己釘死角色與難度。各 906 場、1,866
次生成、**零失敗**；judge 各 1,026 筆。

| 指標                                               | 報告 §11 門檻 | standard                    | beginner                    |
| -------------------------------------------------- | ------------: | --------------------------- | --------------------------- |
| 盲目跟題 `blind_follow`（裸片段 n=486）            |           ≤5% | **38.3%（35.4–43.2）**      | **37.2%（33.7–40.7）**      |
| 誤質疑 `false_challenge`（有效短答 n=240）         |           ≤3% | **0.0%（0.0–0.0）**         | **0.0%（0.0–0.0）**         |
| 虛構自身經歷 `fabricated_self_fact`（全體 n≈1025） |           <1% | **17.5%（15.1–19.7）**      | **15.9%（14.8–19.7）**      |
| 跨輪立場 `stance_persistence`                      |          ≥95% | **81.8%（69.1–90.9）** n=55 | **72.3%（59.6–85.1）** n=47 |
| 查戶口 `interrogation`（全體）                     |           ≤5% | **0.0%**                    | **0.0%**                    |
| 違反 `mustForbid`                                  |             — | 26.3%（23.6–28.0）          | 25.0%（22.5–26.1）          |
| 滿足 `mustAllow`                                   |             — | 52.4%（50.2–54.1）          | 52.6%（50.4–56.2）          |

跑動數字：standard p50 774ms／p95 1145ms、守門退回 2、旁白修補 7、最長 prompt
8,608； beginner p50 785ms／p95 1201ms、守門退回 0、旁白修補 10、最長 prompt
7,824。 生成 wall 各約 200s、judge 各約 220s（concurrency 8）。judge 解析失敗
standard 1／ beginner 0；固定形態 key 手誤（`blind_focus`）repair-first 各救回
7／1 筆。 artifact sha256 前 8 碼：standard `6d7dd553`（judge
`385e8856`）、beginner `a7b29ee4` （judge `78322cc0`）。beginner 的
`worktreeDirty=true` 只是因為 standard 的 artifact 已經寫進未追蹤的
`out/`，兩支都綁在同一個 commit `fba9e7aa`。

每情境（standard｜beginner，blind／fabricate）：

| 情境             |   n | blind    | fabricate |   | 情境              |     n | blind             | fabricate       |
| ---------------- | --: | -------- | --------- | - | ----------------- | ----: | ----------------- | --------------- |
| A01 有效短答     |  60 | 0%｜0%   | 40%｜38%  |   | A09 健身→hyrox    |    60 | 12%｜15%          | 5%｜10%         |
| A02 裸名詞       |  60 | 65%｜53% | 12%｜7%   |   | A10 亂詞→hyrox    |    60 | 23%｜27%          | 10%｜5%         |
| A03 明示換題     |  60 | 30%｜35% | 2%｜10%   |   | A11 自我揭露      |    60 | 0%｜7%            | 8%｜7%          |
| A04 沒回答澄清   |  60 | 25%｜18% | 5%｜8%    |   | A12 清邁          | 59/60 | 51%｜50%          | 64%｜58%        |
| A05 repair       |  60 | 8%｜12%  | 20%｜10%  |   | A13 壽司郎        |    60 | 28%｜20%          | 38%｜28%        |
| A06 連三地名     | 120 | 34%｜42% | 25%｜28%  |   | A14 跨輪立場      |   120 | 34%｜34%          | 18%｜13%        |
| A07 諧音有上下文 |  60 | 0%｜2%   | 3%｜3%    |   | A15 道歉回題      |    60 | 0%｜2%            | 2%｜3%          |
| A08 諧音無上下文 |  60 | 58%｜47% | 3%｜2%    |   | 截圖 Alice／Joyce |  各 3 | 33%／0%｜67%／33% | 33%／0%｜0%／0% |

怎麼讀：

- 報告的診斷在大樣本上成立：**沒有上下文的裸詞有三分之一以上被直接接成新話題**
  （A02 65%、A08 58%），而**有上下文的諧音與有效短答幾乎不會被誤判**（A07 0%、
  A01 0%、A15 0%）——她不是「太敏感」，是「完全不設防」。
- 虛構自身經歷是第二個大洞：A12（人物卡只寫「喜歡旅行」）**六成**會講出「上次去清邁」
  這類設定外經歷，A13（壽司郎）近三成，連 A01 這種正常短答輪都有四成順手補一段
  「去過首爾兩次」。報告 §P1-1 說的缺口是量得到的。
- `false_challenge` 與 `interrogation` **baseline 都是
  0**：現況根本不質疑、也不連問 戶口，所以這兩個指標在這批資料裡沒有正例，只有
  judge 自測的合成案例證明它們判得 出來。Phase 1
  之後它們才會有實際鑑別力；在那之前不要拿「0%」當成守住了。
- standard 與 beginner
  的差距全部落在區間內：**難度／模式沒有改變主體意識**，符合 報告
  §P0-4「難度只調投入度，沒調 agency」。

### 2026-09-03 judge 判準修正後重跑 baseline（同一批生成 artifact，只重跑 judge）

Phase 0 記錄過一個評審歧義：A03「對了 講到韓國…」這種明示換題，評審自己在
`player_msg` 寫「有可辨識的意思」卻仍標 `blind_follow`。Phase 1 把判準補成
「**『跟上一句無關』不是 blind_follow
的判準，『她替玩家補上他沒說的意圖』才是**」，
並逐字列出宣告轉場的詞。判準一改，舊數字就不可比，因此拿 **同一份生成 artifact**
（`run1`／`run2`，commit `fba9e7aa`）只重跑 judge：

| 指標                   | 舊判準 standard | 新判準 standard        | 舊判準 beginner | 新判準 beginner        |
| ---------------------- | --------------: | ---------------------- | --------------: | ---------------------- |
| 盲目跟題（n=486）      |           38.3% | **28.0%（25.1–31.7）** |           37.2% | **31.9%（27.4–35.8）** |
| 誤質疑（n=240）        |            0.0% | **0.0%**               |            0.0% | **0.0%**               |
| 虛構自身經歷（n≈1026） |           17.5% | **16.9%（15.5–19.6）** |           15.9% | **16.0%（14.5–19.3）** |
| 跨輪立場               |           81.8% | **90.6%（81.1–98.1）** |           72.3% | **85.2%（74.1–94.4）** |
| 查戶口                 |            0.0% | **0.0%**               |            0.0% | **0.0%**               |

A03 的 blind 從 30%／35% 降到 2%／2%，跨輪立場的假陰性也一起修掉。**下面 Phase 1
的 on vs off 對照一律用新判準這一欄當 baseline**，不要再拿 38.3% 比。judge 解析
失敗 1／0，固定形態 key 手誤 repair 各 1 筆；judge wall 249s／502s。artifact 前
8 碼 `2dbbbbe7`（standard-judge）、`e7a6d8ff`（beginner-judge）。

### 2026-09-03 Phase 1（AGENCY-02＋03）on vs off，20 位 × 17 情境 × repeat 3

`--agency=on --style=1`（`run3` standard／`run4` beginner，commit `7144f405`）。
兩支各 906 場、1,866 次生成、**零失敗**；judge 各 1,026 筆，解析失敗 0／1。

| 指標                              |   計畫門檻 | standard off → on                                    | beginner off → on                                    |
| --------------------------------- | ---------: | ---------------------------------------------------- | ---------------------------------------------------- |
| 盲目跟題 `blind_follow`（n=486）  |        ≤5% | 28.0（25.1–31.7）→ **18.7（16.3–22.0）** ❌          | 31.9（27.4–35.8）→ **14.0（10.3–16.7）** ❌          |
| 誤質疑 `false_challenge`（n≈240） |        ≤3% | 0.0 → **0.0** ✅（A01／A03／A07／A09 全 0）          | 0.0 → **0.0** ✅（同上）                             |
| 虛構自身經歷（n≈1026）            | 不高於 off | 16.9（15.5–19.6）→ **11.1（9.4–13.5）** ✅           | 16.0（14.5–19.3）→ **11.2（9.5–12.9）** ✅           |
| 跨輪立場 `stance_persistence`     |       ≥95% | 90.6（81.1–98.1）n=53 → **88.5（80.8–94.9）n=78** ❌ | 85.2（74.1–94.4）n=54 → **81.8（72.7–88.9）n=99** ❌ |
| 查戶口 `interrogation`            |        ≤5% | 0.0 → **0.0** ✅                                     | 0.0 → **0.0** ✅                                     |
| 違反 `mustForbid`                 |          — | 21.7 → **15.3**                                      | 22.8 → **12.5**                                      |
| 滿足 `mustAllow`                  |          — | 61.2 → **72.5**                                      | 62.6 → **74.7**                                      |

跑動數字（off → on）：standard p50 774→776ms／p95
1145→**1146ms**（＋0.1%）、守門退回 2→0、旁白修補 7→6、最長 prompt
8,608→8,707；beginner p50 785→790ms／p95 1201→**1212ms**（＋0.9%）、守門退回
0→0、旁白修補 10→10、最長 prompt 7,824→7,956。 生成 wall 各
266s／268s（concurrency 6），judge wall 436s／296s。artifact 前 8 碼：
`394cce00`／`a976b1bb`（standard、judge）、`a69e0a14`／`6674ef21`（beginner、judge）。

每情境（standard｜beginner，off→on 的 blind）：

| 情境             |   n | blind off → on |   | 情境              |    n | blind off → on           |
| ---------------- | --: | -------------- | - | ----------------- | ---: | ------------------------ |
| A01 有效短答     |  60 | 0→0%｜0→0%     |   | A09 健身→hyrox    |   60 | 10→5%｜10→5%             |
| A02 裸名詞       |  60 | 53→33%｜48→23% |   | A10 亂詞→hyrox    |   60 | 28→8%｜25→7%             |
| A03 明示換題     |  60 | 2→2%｜2→2%     |   | A11 自我揭露      |   60 | 3→2%｜5→7%               |
| A04 沒回答澄清   |  60 | 10→5%｜13→2%   |   | A12 清邁          |   60 | 40→27%｜38→23%           |
| A05 repair       |  60 | 13→5%｜10→7%   |   | A13 壽司郎        |   60 | 25→15%｜22→17%           |
| A06 連三地名     | 120 | 18→18%｜27→20% |   | A14 跨輪立場      |  120 | 28→16%｜25→5%            |
| A07 諧音有上下文 |  60 | 3→7%｜2→2%     |   | A15 道歉回題      |   60 | 2→0%｜2→0%               |
| A08 諧音無上下文 |  60 | 45→35%｜43→30% |   | 截圖 Alice／Joyce | 各 3 | 0→0%／0→67%｜0→0%／0→33% |

兩次收緊嘗試（pilot，standard × repeat 1、n=162，artifact
未入庫，數字留在這裡）：

1. `fragment_no_context_v1` 走 bounded `[ask_intent, acknowledge]`：blind_follow
   **18.5%（13.0–24.7）**。
2. 改成指定 `ask_intent`，並在 turn plan
   尾端加「問清楚或指出跳題時就只做那件事，
   不要同一則裡又把那個詞當成新話題聊起來」：**19.1%（13.0–25.3）**。

兩者區間幾乎完全重疊，n=162 分不出差別（而且這一輪同時改了兩個變因，本來就不能
歸因）。最後留第二版，理由是它符合報告 §6 對「沒有前文突然說韓國」的期望政策，
不是因為數字比較好。第三次嘗試會需要「只問不猜」的硬規則，那會把她推向審問語氣，
Phase 1 不做——照計畫「兩次誠實嘗試後停下來報數字」。

怎麼讀（誠實版）：

- **兩個門檻沒過，而且是同一個原因。** `blind_follow` 從 28%／32% 掉到 19%／14%
  （區間不重疊＝真的降了），但離 ≤5% 還很遠。逐筆看評審理由，剩下的幾乎都是同一
  種形態：她**問了**「怎麼突然講韓國」，卻在同一則裡順手給一個解讀（「你是要出國嗎」
  「你在追韓劇嗎」）。judge 的定義是「補上玩家沒有說的意圖」＝這就算
  blind_follow。 要壓到 5% 必須逼她只問不猜，代價是聽起來像審問——Phase 1
  不打算用固定台詞硬壓 （報告 §13 第 2／8 點）。集中在 A02（33%／23%）與
  A08（35%／30%）這兩個「一開場 就丟一個裸詞」的情境，其餘情境多半已在 10%
  以下。
- **`stance_persistence` 的分母變了，不能直接比大小。**
  這個指標只算「上一個探針她 真的質疑過」的配對；agency
  開啟後她質疑得多很多，配對數 53→78、54→99。比例 90.6→88.5、85.2→81.8
  都在彼此區間內，真正的訊號是「有立場可以延續的回合變成 1.5～1.8
  倍」。要拿它當門檻，得先把分母固定住（Phase 3／4 的票）。
- **有效短答一次都沒被誤傷。** `false_challenge` 在 on／off、standard／beginner
  四支 run 上全部 0.0%，A01／A03／A07／A09 每一個情境也都是
  0%——結構層「她剛問完＋
  前面沒有未解片段的短答」與「明示換題」直接不介入，這條是設計保證，不是運氣。
- **虛構自身經歷順帶降了三分之一**（16.9→11.1、16.0→11.2），來自 system prompt
  那一 行認知邊界。但 A12（人物卡只寫「喜歡旅行」→「清邁」）仍有
  55%／53%：她不再硬接 話題，卻還是會講「我上次去過」。這正是 Phase 3 的
  `practice_chat_semantic_guard` 要治的，Phase 1 只承諾「不高於 baseline」。
- 截圖重播 n=3，Joyce 那一格 67%／33% 是 1 筆／1 筆，別當統計看。
- 守門退回、旁白修補、p95 延遲三項都沒有退步（p95 ＋0.1%／＋0.9%，門檻 ＜10%）。
