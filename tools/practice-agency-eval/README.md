# 練習室「對話主體意識」評測（conversation-agency-v1 Phase 0／1／2）

計畫：`docs/plans/2026-09-03-practice-conversation-agency-plan.md`；
夥伴報告：`docs/plans/2026-09-03-practice-conversation-agency-partner-report.md`。

問題不是「她講話不好聽」，而是**最新一個名詞就是她的議程**：沒有上下文的裸詞會被
補成一個合理話題，她還會順手編出自己的具體經歷。既有的 reply-style 評測量得出
「不同角色講話不一樣」，量不出「她是不是有自己的立場」——這支工具補的就是這一段。

每一輪都是真實 DeepSeek 呼叫（prod 同款 `deepseek-v4-flash`，Eric 2026-09-02
授權隨意調用）。20 位角色 × 17 情境 × repeat 3 約 1,870 次生成、1,030 次評審
（主情境）；Phase 2 另加 4 個腳本化質疑情境（A16–A19，20 位 × repeat 3 ×
off／on／standard／beginner 四支）。

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
  挑戰難度）＋ Phase 2 新增的 A16–A19（腳本化質疑，見下）。每個情境是一串 固定
  turn；`ai` turn 是寫死的前文（截圖重播、A01
  的「她先問一句」、A04 的「她問東東
  是誰」、A16–A19 的「她已經質疑過」），**她的回覆是腳本的那一輪不打模型也不進
  judge**，逐字稿才不會多出一則不 存在於截圖的回話。只有標了 `probe` 的 user
  turn 會被評審，並宣告 `kinds`（＝指標 分母）、`mustAllow`、`mustForbid`。
  - **A16–A19（`scripted_challenge_followup`）**：AI
    的質疑句（例：「你是在報地名嗎」）是情境檔寫死的固定前文，不是模型自己前一輪
    判斷出來的，讓「跨輪立場」有固定分母才能跨 `--agency=on/off`
    直接比大小（見下面 `evaluate_agency.ts` 與結果紀錄）。A16／A17
    之後接無關片段（正確＝`hold_position`，禁止 `blind_follow`）；A18／A19
    之後接玩家的合理解釋再丟一個有效答案（正確＝`accept_valid_answer`，禁止
    `false_challenge`）。
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
  興趣／生活／自介／職業＋生活情境＋記憶摘要＋朋友圈）。九個標籤（`JUDGED_LABELS`）：
  `adopted_without_asking`、`asked_with_guess`、`clarify_or_challenge`、
  `return_to_topic`、`accept_valid_answer`、`hold_position`、
  `fabricated_self_fact`、`false_challenge`、`interrogation`。**`blind_follow`
  不在這裡**——Phase 0／1 的 blind_follow
  把「完全不問就跟題」跟「有問但同一則又夾帶猜測」擠在同一個標籤，兩種判準互相
  污染；Phase 2 拆成 `adopted_without_asking`（完全不問就把片段當新話題聊下去）
  與 `asked_with_guess`（有問關聯／意圖，但同一則裡又給了一個猜測），
  `blind_follow` 改在 `evaluate_agency.ts` 導出＝兩者的
  OR，只為了跟舊報告與 mustAllow／mustForbid 連續可比。輸出先寫三句判讀
  （`player_msg`／`answered`／`self_facts`）再寫九個布林，強制它先決定「玩家這句在
  這段對話裡有沒有可辨識的意思」。嚴格驗證：九個布林一個都不能少、型別錯整筆判失敗，
  只對**逐字列在 `KNOWN_KEY_TYPOS`** 的固定形態 key 手誤做 repair-first（目前登記
  `adopted_with_asking`→`adopted_without_asking`，Phase 2 重跑時三個不同 run
  各觀察到一次）。
  遮罩用**帶型別的佔位符**（（她的名字）／（她的城市）／（她的職業）／（她的年齡）），
  只套在她的回覆與可信來源上，不套玩家訊息——玩家說「我在台中做設計」是玩家的事實，
  遮掉會毀掉 A11／A12 的題意；統一換成同一個＊則會讓職業欄位假裝背書城市聲稱。
- `evaluate_agency.ts`：純函式指標＋bootstrap 95%（1000 次、確定性
  LCG）。分母一律 來自 `scenarios.ts` 宣告的 `kinds`（結構事實），分子一律來自
  judge 的標籤（語意）：
  - `blindFollow`＝`adoptedWithoutAsking || askedWithGuess`，`no_context_fragment`
    探針上的盲目跟題率（報告 §11 門檻 ≤5%）；`adoptedWithoutAsking`／
    `askedWithGuess` 是它的兩個子指標，同一個分母、各自的 bootstrap CI。
  - `falseChallenge`＝`valid_short_answer`
    探針（A01／A03／A07／A09）上的誤質疑率（≤3%）
  - `fabricatedSelfFact`＝全體探針（大樣本 <1%）
  - `stancePersistenceConditional`（原
    `stancePersistence`）＝同一場裡「前一個探針她真的質疑過」的配對中，下一個
    `stance_followup` 探針沒有回去盲目跟題的比例；分母是條件式的，agency
    開關會改變配對數，**不能跨組直接比大小**（見下面結果紀錄）。
  - `stancePersistenceScripted`（Phase 2 新增）＝`scripted_challenge_followup`
    探針（A16–A19）滿足 mustAllow 且沒中 mustForbid 的比例；分母固定＝情境數 ×
    profiles × repeat，不受模型自己前一輪判斷影響，**可以直接跨 `--agency=on/off`
    比大小**。
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
- **`hold_position` 幾乎不會單獨成立（Phase 2 實測到）**：A16／A17（腳本化質疑後
  丟無關片段，正確答案是 `hold_position`）的 `allowSatisfied`
  在四支 run 上都是 0%，即使 `clarify_or_challenge`
  有六成以上成立。judge 的 `hold_position` 判準是「維持先前已經表達過的懷疑」，
  但腳本化的質疑句是**情境檔寫死的固定前文**，不是她自己在前一輪探針裡說的話，
  評審似乎不把「延續一句她沒親口說過的懷疑」算成 hold_position，只把玩家這輪的新
  反應算 `clarify_or_challenge`。這代表 `stancePersistenceScripted`
  的低分主要是 A16／A17 兩格拖累，不是 A18／A19 那種「該接就接」的部分——見下面
  結果紀錄的逐情境表。**下一輪如果要用這個分母定門檻，要嘛把 mustAllow 換成
  `clarify_or_challenge && !blind_follow`，要嘛先把 hold_position
  的判準改成也承認情境檔寫死的質疑。**

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

### 2026-09-03 Phase 2：拆分 blind_follow ＋腳本化固定分母跨輪立場（commit `ffe1898b`）

沿用 Phase 1 的四支主情境 artifact（`run1`／`run2` off、`run3`／`run4`
on，commit `fba9e7aa`／`7144f405`），**只重跑 judge**（新的九標籤 schema），
加上新生成的 4 個腳本化質疑情境 A16–A19（`run5`–`run8`，20 位 × repeat 3、
`--scenarios=A16,A17,A18,A19`，commit `ffe1898b`，off／on 各一支 standard／
beginner，共 4×240＝960 場、1,440 次生成、**零失敗**）。下表每格＝主情境
（1,026 探針）＋對應的 A16–A19（240 探針）合併後的指標，n
是合併後的分母。

| 指標 | baseline standard | baseline beginner | agency-on standard | agency-on beginner |
| --- | --: | --: | --: | --: |
| 盲目跟題 `blind_follow`（n=605，agency-on beginner n=604） | **48.9%（43.6–53.7）** | **46.6%（43.1–51.2）** | **36.4%（32.9–41.5）** | **36.4%（32.5–40.7）** |
| 　├ 完全不問就跟題 `adopted_without_asking` | 28.4%（25.8–32.2） | 26.4%（23.0–29.6） | 15.9%（13.9–18.7） | 12.6%（9.6–15.6） |
| 　└ 有問但夾帶猜測 `asked_with_guess` | 20.5%（16.7–23.1） | 20.2%（17.4–24.3） | 20.5%（18.2–23.6） | 23.8%（21.0–27.6） |
| 誤質疑 `false_challenge`（n=240） | 0.0% | 0.0% | 0.0% | 0.0% |
| 虛構自身經歷 `fabricated_self_fact` | 12.6%（10.9–15.0） | 11.7%（10.4–12.6） | 8.4%（7.7–10.3） | 7.8%（6.2–9.0） |
| 跨輪立場（條件式分母）`stance_persistence_conditional` | 72.5%（60.9–82.6）n=69 | 63.9%（52.8–75.0）n=72 | 64.9%（55.7–75.3）n=97 | 69.5%（61.0–77.1）n=105 |
| 跨輪立場（固定分母）`stance_persistence_scripted`（n=240，agency-on beginner n=237） | **12.9%（8.3–18.3）** | **12.1%（7.9–16.3）** | **10.4%（6.3–13.8）** | **11.4%（7.6–15.6）** |
| 查戶口 `interrogation` | 0.0% | 0.0% | 0.0% | 0.0% |
| 違反 `mustForbid` | 29.3%（25.5–32.1） | 27.7%（24.7–31.1） | 22.1%（17.4–23.8） | 21.2%（18.5–22.3） |
| 滿足 `mustAllow` | 56.6%（54.8–59.1） | 57.4%（54.5–58.9） | 64.2%（60.4–66.3） | 66.8%（64.3–69.5） |

judge：主情境每支 1,026 筆（解析失敗 standard-off 2、beginner-off
1、standard-on 1、beginner-on 1，均 <0.2%，本輪 wall 226–231s）；A16–A19
每支 240 筆（解析失敗 0／0／0／3，本輪 wall 54–56s、3
筆是模型漏欄位不是手誤，正確判失敗不進分母）。九標籤 schema
下唯一觀察到的固定形態手誤是 `adopted_with_asking`（漏「out」），standard-off／
beginner-off／standard-on 各救回 1 筆，已登記進 `KNOWN_KEY_TYPOS`（見
judge_agency.ts）；**因為重跑 judge 途中撞到 DeepSeek 帳號餘額 402（本輪光生成
＋judge 就打了約 6,500 次 API），沒有回頭用新登記的手誤表重跑那 3
支既有 artifact 補救——3/4,104 主情境探針的量級遠低於任何一格的
bootstrap 區間寬度，不影響上表任何結論，下次重跑會自動吃到這筆修補。**

A16–A19 逐情境（standard｜beginner，blind／allow✓；每格 n=60，除了
agency-on beginner 那三格 A17／A18／A19 因 run8 的 3 筆解析失敗降到
n=59）：

| 情境 | off blind | off allow✓ | on blind | on allow✓ |
| --- | --- | --- | --- | --- |
| A16（腳本質疑→無關片段，正解 hold_position） | 42%｜38% | 0%｜0% | 37%｜35% | 0%｜0% |
| A17（同上，另一種質疑句） | 65%｜62% | 0%｜0% | 55%｜64% | 0%｜0% |
| A18（腳本質疑→repair→有效答案，正解 accept_valid_answer） | 15%｜17% | 13%｜7% | 18%｜25% | 5%｜7% |
| A19（同上，另一種質疑句） | 38%｜37% | 38%｜42% | 35%｜36% | 37%｜39% |

怎麼讀（誠實版，Phase 2）：

- **拆分證實了 Phase 1 自己寫的猜測。** Phase 1 的「怎麼讀」已經定性描述過「她問了
  但同一則裡又夾帶猜測」這個殘留問題；現在有分開的數字：agency
  開關幾乎只治 `adopted_without_asking`（standard 28.4%→15.9%、beginner
  26.4%→12.6%，接近腰斬），對 `asked_with_guess`
  完全沒有壓下去（standard 20.5%→20.5% 打平、beginner 20.2%→23.8%
  反而略升）。合併後的 `blind_follow`（36.4%／36.4%）之所以看起來還在同一個檔次，
  是因為兩個子指標一好一平／一升互相抵銷——**只看合併值會低估 agency
  旗標實際做到的事，也會誤以為它對「問了又猜」這個模式有效。**
- **`stance_persistence_scripted` 揭穿了舊分母的樂觀偏誤。**
  舊的條件式指標（`stance_persistence_conditional`）落在 64–73%，感覺還過得去；
  固定分母版只有 10–13%，四支 run 幾乎打平（agency
  開關看不出差異）。差距不是評測壞掉，是舊分母只算「她自己選擇要質疑」的那些
  探針——她會挑比較容易維持立場的時機質疑，這批自選樣本天生分數就高。固定分母
  逼她在情境檔指定的每一次都要接得住，數字直接掉了 5 倍，這才是「她能不能真的守住
  立場」的誠實估計。
- **低分幾乎全部來自 A16／A17，不是 A18／A19。**
  逐情境表看得很清楚：A16／A17（正解 hold_position）的 `allowSatisfied`
  四支 run 全部 0%；A18／A19（正解 accept_valid_answer）還有
  5–42%。這不代表她完全不會 hold 立場——`clarify_or_challenge`
  在 A16／A17 有 60–72%——而是 judge 的 `hold_position`
  判準要求「延續**先前已經表達過**的懷疑」，腳本化的質疑句是情境檔寫死的，不是她
  自己在前一輪探針裡說的話，評審沒有把「延續一句她沒親口說過的懷疑」算成
  hold_position。**這是評測本身的已知限制（見上面「設計上的取捨」），不是產品
  行為的結論**：下一輪要嘛換 mustAllow、要嘛改 judge 判準，才能把 A16／A17
  的訊號讀正確。
- 誤質疑、查戶口兩項延續 Phase 0／1：上表的 `false_challenge`（分母只算
  `valid_short_answer`，即 A01／A03／A07／A09）四支 run 全部
  0%。逐情境原始表另外看得到一筆例外：A19（off-standard）60
  筆裡有 1 筆（2%）被標了 false_challenge——玩家在腳本化質疑後給出合理答案，
  評審仍質疑；其餘三支 run 的 A19 都是 0%，n=60 下 1 筆屬於雜訊量級，不是系統性
  模式。

### 2026-09-04 Codex R1 修正＋Phase 2（coherence／delta cap）round：新程式碼、新標籤 schema

這一輪把 Codex round-1 對 Phase 1 分支的 P1／P2 挑錯全部處理（拿掉長度／無前文
的 forced 判斷、A07/A09 結構免疫、agency 與 reply-style 解耦、golden 範圍擴到
hint／debrief／完整 RPC params、prompt ≤80,150 直接量、難度門檻），加上 Phase 2
（分類器 coherence／aiChallengedLastTurn、delta cap）與
fabricated_self_fact 三標籤拆分（inconsistent_self_fact／
accommodating_invention／plausible_self_detail，Eric 2026-09-03
拍板）。**這批數字是新程式碼＋新 judge schema，跟上面所有舊區塊都不能逐位元組比，
只能看方向。**

跑法（照 README 開頭的三支工具，`--mode=game` 需要 SR 角色 id、`--state=1` 是
跨輪 agency state 的結構層模擬——見 `run_agency.ts` 檔頭註解）：

```
deno run --allow-env --allow-read --allow-write --allow-run=git --allow-net=api.deepseek.com \
  tools/practice-agency-eval/run_agency.ts tools/practice-agency-eval/out/<file>.json \
  --mode=standard --style=1 --agency=off --repeat=3 --concurrency=10
```

一樣的指令把 `--agency` 換成 `on`／`--mode` 換成 `beginner --state=1`／`--mode=game`
（`--profiles` 帶 20 個 rarity==="sr" 的 profileId）／`--difficulty=easy|challenge`。

#### 頭條：standard off vs on（20 位角色×19 情境含 A16–19、repeat 3，各 1,146 場、
2,226 次生成、零失敗；judge 各 1,266 筆）

| 指標 | off（現行程式碼基準） | on |
| --- | --: | --: |
| 【頭條 gate ≤5%】被帶著走 adopted_without_asking + accommodating_invention | **22.1%（20.0–23.1）** | **15.1%（13.0–16.5）** |
| 　├ 完全不問就跟題 adopted_without_asking（裸片段 n=605/606） | 29.1%（26.4–33.1） | 14.9%（12.0–17.0） |
| 　└ 有問但夾帶猜測 asked_with_guess | 15.0%（11.6–18.0） | 18.6%（15.5–20.1） |
| 誤質疑 false_challenge（A01/A03/A07/A09，n=240） | 0.0% | 0.0% |
| 跟設定矛盾 inconsistent_self_fact（目標 0） | 0.1%（0.0–0.2） | **0.0%** |
| 為附和話題現編 accommodating_invention | 2.4%（1.4–3.2） | 1.6%（1.1–2.1） |
| 允許的小細節 plausible_self_detail（只回報） | 16.3% | 11.6% |
| 跨輪立場（固定分母）stance_persistence_scripted（n=239/240） | 8.4%（4.6–12.1） | 7.9%（4.6–10.4） |
| 查戶口 interrogation | 0.0% | 0.0% |
| 滿足 mustAllow | 55.7% | 64.2% |

artifact：`out/2026-09-04-r2-standard-off-x3(.json/-judge.json)`、
`out/2026-09-04-r2-standard-on-x3(.json/-judge.json)`。

#### beginner ＋ `--state=1`（跨輪真的帶 agency state，不是每輪傳 null；n 同上）

| 指標 | beginner on＋state |
| --- | --: |
| 頭條 gate | 15.7%（14.3–17.1） |
| adopted_without_asking | 16.2%（13.0–19.6） |
| asked_with_guess | 19.8%（16.0–22.6） |
| inconsistent_self_fact | 0.1% |
| accommodating_invention | 2.1%（1.6–2.7） |
| stance_persistence_scripted | 8.8%（5.4–12.9） |

跟 standard-on（沒有跨輪狀態，各回合 agencyState 現推）幾乎打平（15.1% vs
15.7%，區間重疊）——**這一輪測到的結構層 state 模擬（見 `run_agency.ts` 的
`stateSimulation` 註解：只用 Phase 1 的證據／政策推下一輪狀態，不是每輪真的多打
一次 classifier 拿 coherence）沒有量到跨輪狀態的額外效益**，不代表跨輪狀態沒用，
可能是這批情境檔本來就多半在 3 輪內就結束，狀態還沒累積出差異。artifact：
`out/2026-09-04-r2-beginner-on-state-x3(.json/-judge.json)`。

#### 難度軸（A02／A04／A05／A06／A12，agency on，20 位×repeat 3，各 300 場、
600 次生成、零失敗；judge 各 360 筆）

| 指標 | easy | challenge |
| --- | --: | --: |
| 頭條 gate | 19.4%（14.2–22.2） | 19.8%（16.4–22.6） |
| adopted_without_asking（n=240） | 13.3%（9.6–17.5） | 11.3%（6.3–15.0） |
| accommodating_invention | 3.9%（2.5–5.8） | **6.1%（3.9–7.8）** |
| A02（裸名詞）單獨的 blind_follow | **57%** | **13%** |

難度門檻的方向性符合設計（報告 §7.4）：A02 這種完全無前文的裸片段，easy 給
`[acknowledge, ask_intent]`（她可以直接接住，blind 57%）、challenge 只給
`[ask_intent, challenge_relevance]`（逼問或質疑，blind 13%），四倍差距。但
accommodating_invention 在 challenge 反而比 easy 高（6.1% vs 3.9%，A12
清邁那類）——**難度門檻只調了「要不要質疑無關片段」，沒有調「要不要替自己編故事」
這條規則，是兩件事**，challenge 沒有比較不會編。artifact：
`out/2026-09-04-r2-difficulty-easy(-judge).json`、
`out/2026-09-04-r2-difficulty-challenge(-judge).json`。

#### Game 模式（20 位 SR 角色、repeat 2，off／on 各 764 場、1,484 次生成、零失敗；
judge 各 844 筆，解析失敗 3／1）

| 指標 | off | on |
| --- | --: | --: |
| 頭條 gate | 24.0%（21.5–27.9） | 17.2%（14.5–18.4） |
| adopted_without_asking（n=404/403） | 32.4%（29.0–37.6） | 18.4%（15.4–21.8） |
| stance_persistence_scripted（n=160） | 8.8%（4.4–13.8） | 6.9%（3.1–10.6） |

Game 套挑戰難度門檻＋既有 Game FSM 優先權；off 基準（32.4%）比 standard-off
（29.1%）略高，符合「Game 玩家更容易丟裸詞測試」的直覺，agency on
後降到 18.4%，方向與 standard／difficulty 一致。artifact：
`out/2026-09-04-r2-game-off(-judge).json`、`out/2026-09-04-r2-game-on(-judge).json`。

#### style 比值（`--style=1 --agency=on --repeat=2`，480 場零失敗）

重心距離比值 **1.95**（≈1 代表分不出角色）；persona 內 1.28（playful_extrovert）
～2.41（slow_worker）。比 Phase 1 記錄的 2.15（agency-on，20 位×repeat 3）低，
兩次 repeat 數不同（2 vs 3）、雜訊帶本來就寬，不當退步看，但沒有達到 README
慣例的 ≥2.0 參考線；下次用 `--repeat=3` 重跑比較準。artifact：
`../practice-reply-style-eval/out/2026-09-03-agency-round2-style-ratio.json`。

#### Phase 2 分類器回放（`classifier_replay.ts`，standard-on artifact，1,266
探針、解析失敗 14）

| 指標 | 數字 |
| --- | --: |
| coherence 分佈 | connected 592／ambiguous 104／disconnected 556／repetitive 0 |
| 【gate 0%】disconnected／repetitive 套 cap 後仍有正 heat | **0/556＝0%** ✅ |
| A01＋A09 有效短答仍判 connected | 75/120（62.5%）—— A01 全部（60/60）connected，**A09 只有 25%（15/60）**，其餘判 disconnected |
| A01＋A09 的 connection 被判 defensive／overstepped | **0/120＝0%** ✅ |

**Delta cap 的 0% 正 heat gate 過了，但 coherence 分類器對「隱性話題延續」
（A09：健身前文→「hyrox」，沒有明講問句、靠常識關聯）判得不好**——A01（她剛問完
問題）100% 判對，A09（她沒問、玩家靠上下文延續）只有 25% 判 connected，其餘判成
disconnected。因為 cap 只把 disconnected 壓到 0/0（不獎不罰，不會判 defensive／
overstepped），這批案例不會被錯誤扣分，但也拿不到本來該有的正向分數——**這是
分類器判準的已知落差，不是安全問題，下一輪要嘛把 coherence 規則加一句「常識關聯
（同主題延伸詞）也算 connected，不是只有明講問答」，要嘛把 A01/A09 這類 fixture
直接餵給 judge 校準一次。**artifact：
`out/2026-09-04-r2-standard-on-x3-classifier-replay.json`。

#### Alice（practice_girl_001）截圖相鄰情境的實際回覆（agency off vs on，repeat 1）

| 情境 | 玩家 | off | on |
| --- | --- | --- | --- |
| A02 裸名詞 | 韓國 | 你怎麼突然講韓國 | 嗯？韓國怎麼了 |
| A04 沒回答澄清 | 阿布達比 | 喔你說過夜站喔 | 喔你說地點喔／我剛從那邊飛回來／累 |
| A05 repair | 日本 | 日本我也愛 你排哪裡 | 日本我倒是蠻熟的 你要自助嗎 |
| A06.p2 連三地名 | 東京 | 喔 我以為你說韓國 | 蛤？ |
| A06.p3 連三地名 | 淺草 | 你現在在淺草喔 | 你到底在說甚麼😂 |
| A12 清邁 | 清邁 | 清邁不錯啊 去過兩次 | 清邁不錯 之前休假有去過 |

A04 與 A12 是兩個誠實的反例：agency on 之後她確實不再把裸片段直接聊成新話題
（A02／A06 明顯改口氣、開始問），**但 A04 反而多編了「剛從那邊飛回來」，A12 仍然
講「之前休假有去過」——accommodating_invention 在大樣本上降了（2.4%→1.6%），
不是歸零**，跟 Phase 3（practice_chat_semantic_guard）要治的缺口一致。

#### 跟舊程式碼（Phase 1 分支，`fba9e7aa`／`7144f405`）用同一套新 schema 重跑
judge（同一批舊回覆，只換 judge，不重新生成）

| 指標 | 舊程式碼 standard off | 舊程式碼 standard on | 這輪 standard off | 這輪 standard on |
| --- | --: | --: | --: | --: |
| 頭條 gate | 21.0%（18.7–22.9） | **12.1%（9.5–14.0）** | 22.1%（20.0–23.1） | **15.1%（13.0–16.5）** |

**誠實的落差**：這輪 agency-on 的頭條數字（15.1%）比舊 Phase 1 分支的 agency-on
（12.1%，同一套新 judge schema 下重算）還差，off 基準也略高（22.1% vs
21.0%，在雜訊帶邊緣但方向一致）。可能原因：item 1／4 的修正（拿掉「無前文裸片段
forced ask_intent」與「A07/A09 式有前文片段的 bounded 建議」，改成完全不介入或
不強制）把兩種原本至少會被 nudge 一下的中間地帶，改成完全不給任何結構指引——
這是 Codex round-1 明確要求的修正（不能用長度／啟發式直接決定 forced act），
拿掉的是「用不安全的方式壓低分數」，不是產品變差，但這批新 baseline 提醒
**Codex 修完 P1 的結構正確性之後，還沒有一次專門針對「頭條 gate ≤5%」重新收斂
的嘗試**——Phase 1 的兩次收斂嘗試（見上面「兩次收斂嘗試」段）也還沒套進這一輪
的門檻設計裡，這是下一輪的第一個候選項。

#### 待辦（下一輪重跑）

1. **頭條 gate（≤5%）沒過**，跟 Phase 1 一樣：這輪的 15.1%／15.7%／17.2%／19.4%／
   19.8% 全部離門檻很遠。收斂需要進一步的政策調整（例如 Phase 2.5 的角色立場
   規則，main 上已有計畫但這輪沒實作），不是靠改 judge 判準。
2. **asked_with_guess 完全沒動，甚至略升**（15.0%→18.6%，standard）：item C
   的「不要在同一句替他補上你猜的意思或話題」文案改了，但沒有測出效果——下一輪
   要嘛加結構化的第二刀（例如偵測「先問句再猜測」的兩段式輸出直接重寫），要嘛
   承認純 prompt 規則對這個模式沒用。
3. **coherence 分類器對隱性關聯（A09 型）判得不好**（75% 誤判非 connected），
   建議加一句規則或用 A01/A09 fixture 校準。
4. **main 已經領先這個分支 4 個 commit**（`dfca52af`／`d94ec706`／`20e5c980`／
   `4e4b1114`，全部只動 `docs/plans/2026-09-03-practice-conversation-agency-plan.md`，
   規劃了 Phase 2.5 角色立場規則，還沒落地程式碼）——merge 前請先讀那四個 commit，
   本檔與計畫檔的「進度」節需要人工整合，不是單純 fast-forward。
