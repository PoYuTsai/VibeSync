# Analyze v2 本機黑箱

真模型、v2 契約（`noSendDecisions`）、essential 五風格，直接跑
`handleAnalyzeStream` 本體（system prompt、情境 atoms、發散計畫影子都是 production
程式碼），只 stub DB store 與 supabase telemetry。真呼叫會產生費用，跑前要 Eric
明確授權。

## Sonnet 5 → 5.5 A/B（2026-10-02）

臂（`ab.ts` 的 `ARMS`）：

- **A**：`claude-sonnet-5`，production 原樣（`thinking:{type:"disabled"}`）。
- **B**：`claude-sonnet-5-5`，在 fetch 層改回舊 helper 的 `thinking:{type:"between_tools"}`＋
  `output_config.effort:"medium"`，max_tokens 不加。
- **C**：`claude-sonnet-5-5`，production helper（`_shared/model_request_params.ts`）原樣送
  adaptive thinking（`display:"omitted"`）＋effort `low`＋max_tokens +4000（`maxTokensFor`）。

設定 C 上線後（`analysis-sonnet55-switch`）C 臂就等於 `ANALYZE_STREAM_SONNET_55=true` 的 production；`--refusal-probe` 改跑 C 臂。
旗標只換 v2 合約串流（舊版 client 的 v1 照舊 Sonnet 5）；免費版兩種風格（4500＋4000）沒有單獨跑過黑箱。

預設 **dry-run**：列每案交錯順序與估價，不讀 key、不打模型。估價用官方價：輸出吃滿
max_tokens；system prompt 第一次以 cache 寫入價、同案同臂的重複以讀取價（同案的幾次
在 5 分鐘內連著跑）；另列完全不中 cache 的最壞值。評審估價每次 4000 token 輸入（實測約
2k）。

```sh
# dry-run（0 次模型呼叫）
deno run --allow-env --allow-read --allow-run=git \
  tools/analyze-v2-blackbox/run_blackbox.ts --arms=A,B,C --repeat=A:2,B:2,C:1

# 真跑：五個旗標缺一個就拒絕；out/<tag> 已存在也拒絕（不覆寫）
deno run --allow-env --allow-read --allow-run=git \
  --allow-write=tools/analyze-v2-blackbox/out --allow-net=api.anthropic.com \
  tools/analyze-v2-blackbox/run_blackbox.ts --arms=A,B,C --repeat=A:2,B:2,C:1 \
  --run --confirm-paid --max-calls=105 --budget-usd=15.5 --tag=2026-10-02-ab
```

旗標：`--arms=A,B`（預設）；`--repeat=N` 或 `--repeat=A:2,B:2,C:1`；`--only=a,b`；
`--refusal-probe`（只跑 C 臂、只跑下列曖昧／邀約案）。付費閘：計畫次數要 ≤
`--max-calls`、估價要 ≤ `--budget-usd`；跑的時候每次呼叫前先打 count_tokens（免費）拿
輸入 token（Anthropic 文件說是估計值，所以再加 10%＋200 token），以「輸入全按 cache 寫入價＋輸出吃滿
max_tokens」的上界檢查已花費（不是供應商保證的嚴格上界，停損可能有極小誤差），查不到
或超過就停，已跑的結果照寫。已花費＝每次呼叫前先記上界，只有 message_start 帶了 input usage、且收到帶 output_tokens 的最終
message_delta（正常 stop、沒有 error 事件）才換成實際費用；斷線或最終 usage 沒到就以上界計
（已回報費用比上界高時取已回報費用）。
備援鏈關閉（`allowModelFallback:false`），失敗就記失敗，不讓 4.6 混進來；critic 影子關閉。

2026-10-02 dry-run（commit bffc668c 上的工作樹）：A,B×2＝84 次 $9.85＋評審 68 次 $0.86；
C×1＝21 次 $4.23＋評審 17 次 $0.21；合計 $15.15（不中 cache 最壞 $17.80＋評審 $1.07）。
`--refusal-probe`：10 次 $1.61＋評審 6 次 $0.08。

輸出 `out/<tag>/`：

- `records.json`：每次呼叫一筆（每案寫一次）：臂、模型、`providerCalls[]`（fetch 層實際送出
  的 max_tokens／thinking／output_config、served model、HTTP 狀態、`stopReason`、
  `stopDetails.category`、usage 四格、provider 耗時、費用）、端到端 `latencyMs`、
  `result`（evaluate／critic 讀的那份）。
- `arm-A.json`／`arm-B.json`／`arm-C.json`：舊 artifact 形狀，直接餵 `evaluate.ts` 與
  `run_critic.ts`。
- `summary.md`：每臂 evaluate 通過數與失敗 gate、max_tokens 次數、拒答次數與類別、HTTP
  錯誤、p50／p95 延遲、平均 input／cache 寫／cache 讀／output token、費用。語料全是正常
  聊天，任何拒答都算誤擋。
- `blind.md`＋`blind-reveal.json`：固定種子 20261002 挑 10 案，每案 A／B 第 1 次隨機排成
  甲／乙給 Eric 盲選；對照表另檔。

2026-10-02 結果（`out/2026-10-02-ab/`，主跑 $6.35＋評審約 $0.31）：

| 臂 | evaluate | 評審 rewrite | p50／p95 | 平均 output | 每次費用 |
|---|---|---|---|---|---|
| A | 37/42 | 8/29 | 30.5s／41.0s | 2847 | $0.058 |
| B | 33/42 | 5/26 | 18.5s／24.3s | 2377 | $0.054 |
| C | 19/21 | 2/14 | 17.7s／21.6s | 2212 | （cache 排列不同，不可比） |

- 5.5 兩臂 63 次 0 拒答、0 max_tokens。
- **擋上線的回歸**：`thin_opening`（我「嗨」她「哈囉」）5.5 三次都 `do_not_send`（理由「硬接只會變成查戶口或尬聊」），Sonnet 5 兩次都 send。
- B 臂同開頭 4、問句超額 3（A 是 3、0）；C 臂只剩 thin_opening 與一次超 cap 枝，但只跑一次。
- 拒答探針沒另跑：探針十案都在主語料裡，B 臂已各跑兩次。

`out/2026-10-02-c-fix/`（commit 0fa60fe5，只修低投入 12 字地板，C×3＝63 次 $2.60＋評審）：thin_opening 仍 3/3
`do_not_send`（hold 指引已不在，5.5 把「哈囉」標 `略`）；evaluate 49/63，question_budget 9（Sonnet 5 在
2026-10-02-ab 是 0/42）；評審 rewrite 11/39，與 A 臂 8/29 同一水準，第一輪 C 的 2/14 是小樣本。後續
6e378964 改成伺服器沒量到低投入時選單裡沒有 `do_not_send`。

`out/2026-10-02-c-gate/`（commit 57e41eae，C×2＝42 次 $1.93＋評審約 $0.12）：thin_opening 2/2 send，冷淡兩案照樣
`do_not_send`；evaluate 37/42（A 臂 37/42）；p50 16.2s、p95 20.8s；評審 rewrite 5/26。新回歸：
first_message_after_match 2/2 `need_context`（理由是不知道照片在哪拍），推測是受限版本換上的 need_context 範例
帶偏，42ec3d25 已拿掉範例、未重驗。盲選（`blind_pair.ts`，A 臂 vs 本輪，兩份表各 21 題）：兩位 Claude 審查員
5.5 勝 16、Sonnet 5 勝 8、差不多 18；Codex（`blind-r*-codex.txt`）5.5 勝 21、Sonnet 5 勝 6、差不多 15。
兩家只在「缺用戶事實時判 need_context 還是編地點」相反。5.5 已知弱點：被問「你覺得呢」時五張都反問不表態。

`out/2026-10-02-c-noexample/`（commit 2ec3ebaf，拿掉範例，C×2＝42 次 $1.95＋評審）：照片題 2/2 恢復 send，但
thin_opening 改判 `need_context` 2/2（「只有嗨和哈囉，硬寫只會查戶口」）；evaluate 36/42；評審 rewrite 4/26。結論：
拿掉一個不回出口 5.5 就換另一個，開場要在結構上釘住。後續 commit 改成伺服器開選單（`offeredNoSendDecisions`）：
用戶只傳過一句且最後是她時只留 `acknowledge_and_stop`；語料加 `opening_boundary`（開場就說有男友）。

`out/2026-10-02-c-menu/`＋`-retry/`（commit d0d6acba，22 案 C×2＝44 次 $1.84＋補跑 8 次 $0.38＋評審約 $0.13）：
主跑有 8 次是 Anthropic 串流中途 `overloaded_error`（0 token、$0），同案同參數補跑 8/8 通過。合併後 44/44 決定
正確（thin_opening 2/2 send、照片題 2/2 send、opening_boundary 2/2 收尾、冷淡兩案先別回），evaluate 41/44
（question_budget 3）；評審 rewrite 5/30。盲選（A 臂 vs 合併結果，`records-merged-with-retry.json`）：兩位 Claude
審查員 5.5 勝 27、Sonnet 5 勝 5、差不多 10；Codex 5.5 勝 21、Sonnet 5 勝 5、差不多 16。仍有的弱點：被問「你覺得呢」
多半不表態、問句超額。

`out/2026-10-02-e2e/`（整合分支 867e0799，A／C 各 23 案×1＝46 次 $3.49＋評審約 $0.13，C＝production helper 原樣）：
C 22/23、決定 23/23 正確（含 user_waiting_after_reply 先別回、opening_boundary 收尾），p50 16.6s、p95 20.9s；A（旗標關時的
production）20/23，其中 defer_polite_reason 的 `acknowledge_and_stop` 漏 `closingMessage` 被 reframer 擋成
STREAM_MALFORMED_RECOMMENDATION（未扣）——舊 prompt 下 A 的收尾 8/8 都有附，n 太小，待補跑確認。三案先別回的備用句兩臂都有、
皆無問號。評審 rewrite：A 1/15、C 3/15。
`out/2026-10-02-ack-a/`（A 臂五個收尾案×3＝15 次 $0.73）：defer_polite_reason 3 次又漏 1 次 closingMessage（前後 4 次漏 2 次），
其餘四案 12/12 有附。之後改成收尾決定沒附句子不再失敗，App 顯示通用收尾提醒。

拒答探針案（`corpus.ts` 的 `REFUSAL_PROBE_IDS`；語料沒有露骨性內容）：
`first_message_after_match`、`soft_reject_after_invite`、`defer_vague_busy`、
`defer_with_alternative`、`defer_polite_reason`、`she_invites_first`、
`after_meetup_followup`、`logistics_confirm`、`she_teases_him`、`boundary_friend_hint`。

評審固定 Sonnet 5（`run_critic.ts` 不接受別的 `--model`），每臂各跑一次：

```sh
deno run --allow-env --allow-read --allow-write=tools/analyze-v2-blackbox/out \
  --allow-net=api.anthropic.com tools/analyze-v2-blackbox/run_critic.ts \
  tools/analyze-v2-blackbox/out/<tag>/arm-B.json \
  tools/analyze-v2-blackbox/out/<tag>/critic-B.json \
  --run --confirm-paid --max-calls=40 --budget-usd=0.6
```

結果檔每案另存完整 client NDJSON（`clientText`）供外洩判定獨立複核，模型原始 JSONL
（`rawLines`）一律保留（評審靠它重建選中卡）。21 案涵蓋開場、熱絡、冷淡、邀約前後、
婉拒、反問、長對話；改 `corpus.ts` 加案。

歷史結果（`out/`）：run2＝18 案 2a 影子基線；run3＝延後變體×3；run9＝2b 迭代中
的失敗樣本（method 混用、sourceIndex 手誤）；run10＝2b 驗收。舊 run 用的是
`run_blackbox.ts <out.json> [--raw=1]` 單臂介面，已換成上面的 A/B 介面。

## Phase 3a 評測器

```sh
deno run --allow-read tools/analyze-v2-blackbox/evaluate.ts <artifact.json> [--json]
```

語料在 `corpus.ts`（每案帶可確定性判定的期望值）。評測器不打網路，對照 §19.3 可
確定性判定的 gates 打分：決策在期望集合、no-send 零卡、send 五 key 唯一、同開頭
≥4 張（§6.3 字面）、問句／新話題預算、風格實際用到的枝不得超 cap、歸因 unresolved、
client 無計畫本文、延遲 ≤60s、輸出 ≤6500 token；任一 gate 失敗 exit 1。同開頭 1–3 張、
pool 裡未用到的超 cap 枝、缺欄 invalid 只是度量。基線：run12 17/21、run13 18/21
（剩：用到超 cap 枝 1–2、四張同開頭 1、問句 1、延遲 1）。3b 實驗：加「開頭規則」對
同開頭無效（4 vs 3 案）已撤。

## Phase 3c candidate guard（只度量）

`_shared/social/candidate_guard.ts` 把 §15.2 第一層硬 gates 統一成 violation 清單，
production 隨 `stream_phase0_observability.candidateGuard` 出（只記不擋）。評測器每案印
`guard=<codes>`、彙總 `guard {...}`，不影響 pass／exit code。新 artifact 直接讀 telemetry；
舊 artifact 從 `rawLines` 重建（guardrail 前的模型原始輸出；run12／run13 的 rawLines 沒留
盤點球，球面四道出不來，之後的 run 會留）。run12：question_budget 1、semantic_distance_cap 1
（與既有 gate 同案）；run13：card_source_mismatch 4（三案，與 phase0
`fiveCardSourceDivergence` 同判）、semantic_distance_cap 2。

## Phase 3d critic 離線評測（付費）

```sh
deno run --allow-env --allow-read --allow-write=tools/analyze-v2-blackbox/out \
  --allow-net=api.anthropic.com tools/analyze-v2-blackbox/run_critic.ts \
  <artifact.json> tools/analyze-v2-blackbox/out/<date>-critic-<label>.json \
  [--only=a,b] [--run --confirm-paid --max-calls=N --budget-usd=X]
```

（2026-10-02 起預設 dry-run、評審固定 Sonnet 5、輸出檔已存在就拒絕。）

對 artifact 的 send 案只審「選中卡」：證據＝語料訊息＋重建的盤點／決策／計畫（只帶
用到的枝）＋3c guard 碼；rubric 在 `_shared/social/semantic_critic.ts`（Coach 九碼改成
回覆卡語境＋Analyze 十三碼＋繁中句型＋Alpha Guard 判準）。輸出每案 verdict／violations／
token／延遲與 tally；不重跑主分析、不動 runtime。每案一次真呼叫，跑前要 Eric 明確授權。
production 影子（`analyze-chat/critic_shadow.ts`）預設關閉，觸發條件／模型待 Eric 定。

首輪結果（2026-09-03，Sonnet 5，`out/2026-09-03-critic-sonnet5-run12.json`／`-run13.json`）：
run12 14 案 5 rewrite、run13 16 案 4 rewrite，invalid 0，延遲 1.2–4.4s，每案約 2k 輸入 token
（約 0.5 美分）。對得上的：thin_opening 連續兩問（與 guard question_budget 同案）、
first_message_after_match 編造照片地點（run13 抓到「九份」，run12 的「陽明山」漏掉）、
hobby_common_ground 兩輪都沒回答她的直接問題（goal／ball_mismatch）、
she_asks_personal_question 先問貓再答工作（答案該在前）。有爭議：warm_question_back
non_actionable（只說「可以丟妳一部」沒真的給）、cold_one_word_replies 三段對一字回覆
（investment_mismatch 對，topic_spray 勉強）、she_returns_after_silence goal_mismatch
（她給了空窗，卡片只平淡回答）。明顯誤判：she_returns_after_silence 零問句卻標
question_density（1 次）。guard 有違規的案只覆蓋 critic 找到的 1/5，所以影子要開
`always` 才量得到。
