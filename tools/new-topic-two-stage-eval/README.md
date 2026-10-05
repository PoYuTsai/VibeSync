# 新話題成對評測（改前 vs 改後）

比較同一組情境下，**改前**（base）和**改後**（cand）的 production 寫出來的五題，給規格 `docs/plans/2026-10-02-new-topic-natural-lines-implementation-spec.md` §6 的盲測與驗收門檻用（ADR #51）。

預設是 dry-run：不打模型、不讀金鑰、不連網；會跑 git（`rev-parse`、`archive`）取出改前版本。要花錢的真跑，必須 Eric 當次說「跑」之後才下指令。

## 兩臂

| 臂 | 是什麼 | 提示詞從哪來 |
|---|---|---|
| `base` | 改前的 production，預設 `7c5cc523`（ADR #51 之前的 main） | 用 `git archive` 把那一版的 `supabase/functions` 取到暫存目錄，照當時 handler 的路由組：沒帶 `topicContext` 走 `NEW_TOPIC_PROMPT`＋`buildNewTopicUserPrompt`（外洩守門 `hasAnalyzeChatPromptLeak`、不套紅燈收尾），帶了走進階 v1 |
| `cand` | 目前工作樹的 production | `planNewTopicPrompt`：handler 呼叫同一個函式，所以提示詞、今天的日期、外洩守門、grounding、紅燈收尾規則都跟線上一致；「今天」用 `--now` 固定時間 |

- 同一案例同一次重複的兩臂用**同一個 requestId**。角度照各自那一版的清單選，基準保留改前真實的角度清單。
- 模型與參數照 production 主呼叫：`NEW_TOPIC_MODEL`、`maxTokensFor(...)`、`modelRequestParams(...)`（Sonnet 5 thinking 關閉）、system 用快取區塊、同一組 header。`run_test.ts` 會攔下 `fallback.ts` 第一跳實際送出的 body 和 header，跟 `requestBody` 比對。
- 不做修格式那一次呼叫、不串流、不走備援，也不經 Edge、DB、扣費；格式失敗就照實記失敗，另外標出「只壞在解釋欄」的（production 修格式會逐字保留開場句）。
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
  tools/new-topic-two-stage-eval/run.ts --tag=nt3-dry --repeat=2
```

在 `out/<tag>/` 寫 `manifest.json`（兩臂的 HEAD、提示詞與案例 sha256、模型參數、估算）、`system-prompts.json`（每份系統提示詞全文，以 sha256 為鍵）、`prompts.json`（每次呼叫的使用者提示詞），最後印出呼叫數與費用估算。同名輸出目錄已存在會拒絕執行，不覆寫任何證據。

**費用估算方式**（保守、不算快取折扣）：input＝（系統＋使用者提示詞字數）×1.5；output 一般每次 1,200、最壞每次 `max_tokens` 全滿。單價取 `_shared/model_pricing.ts` 的 `SONNET_5_PRICING`（$2/M in、$10/M out）。22 組 × 2 次 × 2 臂＝88 次呼叫，一般約 $2.38、最壞約 $3.97。

## 真跑（要 Eric 當次說「跑」）

```sh
deno run --no-prompt --allow-read --allow-write --allow-run=git,tar \
  --allow-env=HOME --allow-net=api.anthropic.com \
  tools/new-topic-two-stage-eval/run.ts --tag=nt3 --repeat=2 \
  --run --confirm-paid --max-calls=88 --budget-usd=4.5
```

守門：

- `--run --confirm-paid --max-calls --budget-usd` 少一個就拒絕啟動。這些是技術守門，不能取代 Eric 的授權。
- 追蹤檔有未提交修改就拒絕（結果要能對應工程 HEAD）。金鑰讀 `~/.config/anthropic/key`。
- 每次送出前用最壞情況（字數×1.5＋`max_tokens` 全滿）預檢，超過預算或次數上限就整批停，剩下的記 `NOT_RUN_CAP_OR_STOP`。
- API 失敗或沒回 usage：成本當最壞情況計入，並停止後續呼叫，不當免費。
- 送出前後都寫 `requests.jsonl`，每次回來就重寫 `records.json`，中斷不會靜默重送。

輸出在 `out/<tag>/`（已 gitignore）：

| 檔案 | 內容 |
|---|---|
| `records.json` | 每次呼叫的使用者提示詞、模型原文、usage（含快取）、費用、整理結果、字面計數 |
| `summary.md` | 費用、兩臂（全部／基本／進階）的機械指標、規格 §6.5 第 5、6 項門檻 |
| `blind_ab.md` | 給 Bruce：每組兩版依 seed 打亂成甲／乙，只露五句和 ★，附評分欄 |
| `blind_star.md` | 給 Bruce：同一組只看 ★ 那一句（Free 只看得到這一句） |
| `explanations_blind.md` | 給 Bruce：★ 那一題的標題、為什麼現在有效、她回了之後、推薦理由 |
| `reveal-map.json` | 解盲表（哪一版是甲、乙）；**不要跟盲測檔一起給 Bruce** |
| `manifest.json` | 跑完後另加實際呼叫數、費用與指標 |

## 盲測與驗收

1. 把三份盲測檔給 Bruce，每個「＿」換成答案（甲乙之間用全形分號「；」）。全部填完才看 `reveal-map.json`。
2. 執行 `deno run --allow-read --allow-write tools/new-topic-two-stage-eval/tally.ts --tag=nt3`。任何一格沒填或格式不對就拒絕，不會把沒填的當通過。
3. `out/<tag>/acceptance.md` 會列出規格 §6.5 每一項：
   - 第 1–4 項來自盲測：捏造／越界、尷尬句、★ 尷尬、願意直接傳、★ 會直接傳、有趣，以及 B3、J1、E3 必須有趣。
   - 第 5、6 項來自 `records.json` 的機械計數。
   - 第 1 項另要逐筆看 `records.json`。

## 機械指標

只看可交付的輸出；失敗會列在「可交付／輸出」，也算進素材比率的分母，不從分母偷偷刪掉：

- **規格 §4.6 的六項字面計數**：問句、一則兩個以上問句、假設情境、安排角色、貼標籤或說她是哪種人、比能力。另外觀察宣告套話（「我有個…」「這點我不退讓」）。五題全算一次，★ 那一題另外算。
- **開場句字數**：中位數、P90、超過 35 字的句數。
- **近似重句**：同案例第 1、2 次之間的句子對，二字詞 Jaccard ≥ 0.5 算一對。
- **★ 標題的手法字**、**★ 解釋夾英文**：素材或作戰板原本就有的英文名稱不算。
- **production 稽核同一套規則**：推薦題用到素材、她沒回我提空窗、我沒回她同題道歉超過一次、紅燈／冷掉了／基本模式的邀約字眼（D9）、在嗎類開場、紅燈收尾（模型自己推第一題、伺服器改推）。

這些是字面計數，只看趨勢，不是語意判定；用戶講自己的句子也可能被算進去。「不捏造」「願意直接傳」「有趣」要靠盲測。

## 測試

```sh
deno check tools/new-topic-two-stage-eval/run.ts tools/new-topic-two-stage-eval/tally.ts
deno test --allow-env --allow-read tools/new-topic-two-stage-eval/run_test.ts
```

`run_test.ts` 不打模型、不跑 git、不寫檔。它測：
- 參數守門。
- 22 組案例都合法。
- 候選路由等於 `planNewTopicPrompt`。
- 基準路由照改前 handler（用工作樹裡還留著的舊版函式驗規則）。
- 請求 body 與 header 等於 `fallback.ts` 實際送出的。
- 外洩與紅燈收尾。
- 只壞在解釋欄的判定。
- 字面計數、近似重句、機械門檻。
- 盲測打亂與計分。

這支測試在 PR CI 的 Edge contract tests 裡。
