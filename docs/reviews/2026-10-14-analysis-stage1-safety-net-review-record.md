# 對話分析第 1 階段安全網：審查紀錄

- 本機分支 `claude/analysis-stage1-safety-net`，base 是 origin/main `cd6ba9a2`。程式由 Claude（Anthropic）撰寫：三個 commit 是 10/12 在舊 main（`38ab7dbb`）寫好的參考版（本機分支 `claude/analysis-safety-net`，沒推送），這次從最新 main 開乾淨分支 cherry-pick，沒有衝突。
- Eric 交辦（2026-10-14）：對「第 1 階段安全網要不要現在開工」回「好」（預設：開工，不碰語氣和說明書；推送與付費另外問）。Bruce 在 PR #97 對第 5 點（第 1 階段安全網照原計畫）回「同意」。
- R2：對話分析的輸入閘門（會影響哪些請求被擋）、CI 與 Edge 部署流程（部署前多一道測試關卡）、提示詞測試鎖。不動 DB、migration、提示詞內容、扣費。
- **主審（關卡）**：Codex（OpenAI）唯讀，`codex exec --sandbox read-only --skip-git-repo-check -m gpt-6-astra -c model_reasoning_effort=high`。送審封包是純檔案樹＋format-patch＋背景說明＋測試證據，`SHA256SUMS.txt` 的 sha256 記在下表；封包與回覆原文留在 Claude 暫存區，回覆全文另抄在本文。

| 輪 | 範圍（base → head） | 審查 tree | packet manifest sha256 | 回覆 sha256 | 結論 |
|---|---|---|---|---|---|
| 主審 1 | `cd6ba9a2d393872b42c0612685653eb99efba3d6` → `0387e1a45f59c1fa214ae64ada006eac0ee5351a` | `73d2528dc68fc543ce189e49619f30658d6c989b` | `525452eb51d64770be85462a9dde59acc8129b974dc5a51a28dbcf41bfeaf2ec` | `bc71fbc2df634628fee7129b0cf02afd481f4998c312e2ef45078e28e7d3783c` | APPROVED |

## 變更

1. `9883cecf` F01：刪除 `guardrails.checkInput` 與入口的呼叫。它把雙方訊息串起來比對關鍵字，「她不願意吃辣，晚餐怎麼辦」這類正常對話會被擋成 400 `UNSAFE_INPUT`，App 又當成不能重試（2026-10-03 健檢唯一的 P1）。界線與拒絕交給模型的「先別回」決策，輸出端守門 `checkAiOutput` 不變。
2. `8874ca4e` F21：Edge 契約測試清單抽到 `tools/ci/edge-contract-tests.sh`，PR CI 與部署流程共用；analyze-chat 與 `_shared` 整個目錄跑；部署 Edge 前先跑同一份，任何一支失敗，這次的通用函式全部不部署（Eric 2026-10-12 核准這個代價）。
3. `0387e1a4` F19：v2 串流實際送出的提示詞上鎖：四種常見組合鎖長度與 SHA-256，最常見一組存全文快照。

## 測試（本機 WSL，deno 2.8.2，head `0387e1a4`）

- `bash tools/ci/edge-contract-tests.sh`：2,594 passed、0 failed、1 ignored。
- CI Postgres 步驟同一份清單（`deno test --allow-read` 六支）：157 passed、0 failed。
- 沒有 Flutter 變更，沒跑 `flutter analyze`；GitHub CI 未核實（還沒推送）。

## 殘餘風險（主審 1 列，不算本次缺陷）

- 提示詞鎖用的是另外組出來的變體；以後只改正式呼叫點、沒改變體時，可能鎖不到。可以補一條「正式呼叫送出的 system 跟變體相等」的測試，留到第 2 階段一起做。
- 「先別回」只在支援它的 v2 路徑有效；輸出守門不是所有模式、所有惡意語意的完整保障。這次沒有呼叫真實模型，模型的拒答能力沒有核實。

## 重播測試

設計文件第 9 節的「重播測試」不在這一輪：10/3 黑箱基準只完整保留了部分事件（推薦、報告等只留類型），不能拿來重播，要重新錄一次（付費，等 Eric 說「跑」），錄好再另外送審。

### 主審 1 回覆全文

```
本次 R2 主審未發現 base..head 範圍內的 P0–P3 缺陷，可通過審查。

- **F01：**五組回歸案例會命中舊規則；新測試從正式入口進入，確認走到舊閘門之後的模型限流 RPC 並收到 429，能證明誤擋已移除。App 僅保留 `UNSAFE_INPUT` 錯誤顯示，沒有其他流程依賴。位置：`evidence/source/supabase/functions/analyze-chat/input_gate_removed_test.ts:147`。
- **F21：**舊清單的 82 個測試入口全部仍涵蓋；四支 PGlite 排除項完整，且仍由 PR CI 的 Postgres 步驟執行。權限未放寬；部署測試先於正式密鑰步驟，失敗會阻止後續部署。位置：`evidence/source/tools/ci/edge-contract-tests.sh:15`、`evidence/source/.github/workflows/flutter-ci.yml:63`、`evidence/source/.github/workflows/deploy-edge-function.yml:38`。
- **F19：**四組變體目前與正式組法一致，變體及重產工具沒有進入正式入口的依賴鏈。我以唯讀、記憶體內診斷確認四組長度與 SHA-256 全部吻合、全文快照一致，等長替換一字也會造成雜湊不符。位置：`evidence/source/supabase/functions/analyze-chat/v2_stream_prompt_variants.ts:28`、`evidence/source/supabase/functions/analyze-chat/v2_stream_prompt_lock_test.ts:59`。

殘餘風險不列本次缺陷：提示詞鎖使用獨立組裝的變體，未來若只修改正式呼叫點，仍可能漏鎖，可補正式 `callModel.system` 與變體相等的測試。另外，「先別回」只適用支援該契約的 v2 路徑；既有輸出守門不能視為所有模式、所有惡意語意的完整保障。本次未呼叫真實模型，模型拒絕能力未核實。

封包測試紀錄為 Edge **2,594 通過、0 失敗、1 忽略**，Postgres **157 通過、0 失敗**；未重跑完整套件或核實 GitHub CI。全程未連網、未執行 Flutter、未修改檔案。

已重新計算來源樹，吻合封包宣告的 `73d2528dc68fc543ce189e49619f30658d6c989b`。審查 patch SHA-256：`8e440219d3768ca623d27f24e5f2d61ea489fdb5745e2e2101fd8856c05340a8`。

VERDICT: APPROVED
```
