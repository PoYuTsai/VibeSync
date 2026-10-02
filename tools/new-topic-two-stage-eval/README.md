# 新話題兩段式評測

比較同一組情境下，新話題的**舊版**（只送狀況）和**兩段式**（先問局面＋素材再生成）寫出來的五題。對應提案 `docs/plans/2026-09-29-new-topic-two-stage-plain.md` §10「怎麼算成功」。

預設是 dry-run：不打模型、不讀金鑰、不連網、不跑 git。要花錢的真跑，必須 Eric 說「跑」之後才下指令。

## 兩臂

| 臂 | 系統提示詞 | 使用者提示詞 | 看得到什麼 |
|---|---|---|---|
| `legacy` | `NEW_TOPIC_PROMPT` | `buildNewTopicUserPrompt` | 對象資料＋狀況（沒有局面追問、沒有素材） |
| `two_stage` | `NEW_TOPIC_TWO_STAGE_PROMPT` | `buildNewTopicTwoStageUserPrompt` | 對象資料＋狀況＋局面＋素材 |

- 預設兩臂都跑；`--arms=two_stage`（或 `legacy`）只跑一臂，呼叫數與費用跟著減半，沒有盲測。
- 提示詞全部從 `supabase/functions/analyze-chat/` import，沒有複製；改 production 就是改這裡。
- 每個案例先過 production 的 `sanitizeNewTopicRequest`，組合不合法（例如冷掉了卻帶燈號）會直接報錯。
- 同一案例同一次重複的兩臂用同一個 requestId，所以拿到同一個「本輪內容素材」角度（兩段式有素材原文時不送角度，跟 production 一樣）。
- 模型 `claude-sonnet-5`、`max_tokens` = `NEW_TOPIC_MAX_TOKENS`、thinking 關閉（production 對 Sonnet 5 的契約）、不用 prompt cache。
- 整理結果走跟 handler 一樣的 `parseJsonObjectFromText` → `normalizeNewTopicModelPayload`（grounding policy 逐欄同 handler 的 `newTopicGroundingPolicy`：`allowsNewTopicSharedFrame`＋兩段式帶 `userMaterialText`＝素材原文，用戶自己寫的內部代碼字如 stuck 不算外洩；legacy 的 topicContext 是 null，沒有這個豁免）→ 外洩檢查 → 兩段式臂再套 production 的紅燈收尾保證 `enforceNewTopicRedClose`（還在聊／想更靠近＋她常只回哈哈、嗯時推薦固定第一題、拿掉理由；legacy 臂照模型）。records 的 `recommendationIndex` 是用戶實際看到的推薦，`modelRecommendationIndex` 是模型自己推的那題。**不做修格式那一次呼叫**，格式失敗就照實記失敗。
- 不經 Edge、DB、串流、扣費；只有模型呼叫是真的。

## 案例（`cases.json`，12 組）

E1–E3 是提案 §7 的三個例子；其餘每種狀況、各種燈號／冷掉追問、五種素材（含「沒有，幫我想」）都至少一組。對象資料用三份固定的人工作戰板，格式照 `NewTopicPartnerContextBuilder`；C3 刻意沒有對象資料。「關於我」已停用，一律不送。

## dry-run（不花錢）

在 repo 根目錄（WSL）執行：

```sh
deno run --no-prompt --allow-read --allow-write=tools/new-topic-two-stage-eval/out \
  tools/new-topic-two-stage-eval/run.ts --repeat=1 --tag=dry-run-r1
```

只跑兩段式臂、只看紅燈收尾兩組（E2、W1）重複兩次＝4 次呼叫：

```sh
deno run --no-prompt --allow-read --allow-write=tools/new-topic-two-stage-eval/out \
  tools/new-topic-two-stage-eval/run.ts --tag=dry-red --only=E2,W1 --repeat=2 --arms=two_stage
```

會印出兩份系統提示詞全文、每次呼叫的使用者提示詞全文，最後是呼叫數與費用估算；另在 `out/<tag>/` 寫 `manifest.json`、`prompts.json`。同名輸出目錄已存在會拒絕執行，不覆寫任何證據。

**費用估算方式**（保守）：input＝（系統＋使用者提示詞字數）×1.5（本機估算對中文會少算 10–20%）；output 一般每次 1,200、最壞每次 `max_tokens` 全滿。單價取 `_shared/model_pricing.ts` 的 `SONNET_5_PRICING`（$2/M in、$10/M out）。1 次重複＝24 次呼叫，一般約 $0.61、最壞約 $1.04。

## 真跑（要 Eric 說「跑」）

```sh
deno run --no-prompt --allow-read --allow-write=tools/new-topic-two-stage-eval/out \
  --allow-run=git --allow-env=HOME --allow-net=api.anthropic.com \
  tools/new-topic-two-stage-eval/run.ts --tag=nt2-r1 --repeat=1 \
  --run --confirm-paid --max-calls=24 --budget-usd=1.5
```

守門：

- `--run --confirm-paid --max-calls --budget-usd` 少一個就拒絕啟動。這些是技術守門，不能取代 Eric 的授權。
- 追蹤檔有未提交修改就拒絕（結果要能對應工程 HEAD）。
- 每次送出前用最壞情況（字數×1.5＋`max_tokens` 全滿）預檢，超過預算或次數上限就整批停，剩下的記 `NOT_RUN_CAP_OR_STOP`。
- API 失敗或沒回 usage：成本當最壞情況計入，並停止後續呼叫，不當免費。
- 送出前後都寫 `requests.jsonl`，每次回來就重寫 `records.json`，中斷不會靜默重送。

輸出在 `out/<tag>/`（已 gitignore）：

| 檔案 | 內容 |
|---|---|
| `records.json` | 每次呼叫的提示詞、模型原文、usage、費用、整理結果、稽核數字 |
| `summary.md` | 費用、§10 機械檢查表、紅燈收尾表 |
| `blind_ab.md` | 給 Bruce 的盲測：每組兩版依 seed 打亂成甲／乙，只露五句 openingLine 和推薦星號 |
| `reveal-map.json` | 解盲表（哪一版是甲、乙）；**不要跟 blind_ab.md 一起給 Bruce** |
| `manifest.json` | 模型、HEAD、提示詞與案例的 sha256、單價、估算、參數 |

## §10 機械檢查

用 production 的 `auditNewTopicTwoStageTopics`（只記錄不擋的同一套字面規則）計數，只看兩段式是否過關；舊版用同一份用戶回答稽核，當對照基準：

- 有寫素材時，推薦題用到素材 ≥ 90%：分母是這一臂**所有有素材的呼叫**，沒跑到、API 失敗、格式壞、外洩都算沒用到；分母 0 顯示「未評估」，不是過關。只看可交付輸出的條件比率另列一行，僅供參考、不判過關
- 「她沒回我」：提到空窗的句子 0
- 「我沒回她」：同一題 openingLine（可能分兩則傳）裡道歉詞（抱歉／不好意思／對不起／sorry）出現超過一次的題數 0；五題是備選、不是一起傳，所以不跨題加總
- 紅燈：第一則邀約 0；冷掉了：第一則邀約 0
- 「在嗎」「最近好嗎」這類 0

## 紅燈收尾（規格 §9.4）

只算還在聊／想更靠近＋她常只回哈哈、嗯（E2、W1）的可交付輸出：模型自己推第一題幾次、第一題 openingLine 有收尾字眼（先去忙｜晚點｜改天｜下次｜再跟妳／你｜先這樣｜報告｜先睡｜先忙｜回頭再｜有空再）幾次、伺服器改推第一題幾次。legacy 欄只當對照，不套伺服器保證。第一題讀起來像不像收尾、有沒有留下次可以接的點，要人工看 records。

這些是字面計數，不是語意正確率。失敗（格式壞、外洩）不算進句數，但會列在「可交付／模型有回」，也算進素材比率的分母，不從分母偷偷刪掉。「不捏造」「不加曖昧」「願意直接傳、最想傳不輸舊版」要靠 `blind_ab.md` 人工盲測。

## 測試

```sh
deno check tools/new-topic-two-stage-eval/run.ts
deno test --allow-read tools/new-topic-two-stage-eval/run_test.ts
```

`run_test.ts` 只測純函式（參數守門、`--arms`、案例合法、兩臂提示詞、估算、§10 計數、紅燈收尾保證與計數、盲測打亂），不打模型、不寫檔。
