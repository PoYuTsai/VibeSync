# 對話分析第 1 階段第二部分「重播測試」：審查紀錄

- 本機分支 `claude/analysis-stage1b-replay`，base 是 main `e9388b19`（第 1 階段第一部分，已上線）。程式由 Claude（Anthropic）撰寫。
- Eric 交辦（2026-10-14）：「第 1 階段安全網開工」回「好」；重播錄音的付費（23 案，上限 US$4.7）回「跑」。錄音用正式設定（Sonnet 5.5、production helper），實花 US$1.628，0 拒答、0 截斷、0 HTTP 錯誤。
- R2：對話分析的測試安全網（之後改串流處理時靠它擋回歸）、CI 與部署前會跑的測試。不動正式執行的程式、提示詞、DB、扣費。
- **主審（關卡）**：Codex（OpenAI）唯讀，`codex exec --sandbox read-only --skip-git-repo-check -m gpt-6-astra -c model_reasoning_effort=high`。送審封包是純檔案樹＋format-patch＋背景說明＋測試證據，`SHA256SUMS.txt` 的 sha256 記在下表；封包與回覆原文留在 Claude 暫存區，回覆全文另抄在本文。

| 輪 | 範圍（base → head） | 審查 tree | packet manifest sha256 | 回覆 sha256 | 結論 |
|---|---|---|---|---|---|
| 主審 1 | `e9388b1961327327f075baadcae5c31283a86691` → `f98b225e291f0dd3ba36c52e7d8b74148fb207a0` | `2c123bac09f1083f97c7e6d6979fb85bfd1744b9` | `a76c9758de66a0846f3b4d4edb23b125fd16cdf587daf75e154b7c18ef44bc94` | `27d57b29827fb22146256c596b1a3730ddd3c940ee0e2b1cddaa3b007eac8e9b` | APPROVED_WITH_RISK |
| 主審 2（差異複核） | `f98b225e` → `ba9432489709aea5b42c6ba7d56d6e1d1812e98b` | `fa14e1f14a81920b9defcb026398d2ef2964192c` | `505858384d0a714b07691646e210ef9a0d2c7d496f015281f6107a75f970cfbb` | `88352a3fce3b2bd301d72ad1a6c2fc07d5297351070042249f6db4efcd5088f1` | APPROVED |

## 主審 1 的發現與處置

| # | 等級 | 發現 | 處置（`ba943248`） |
|---|---|---|---|
| 1 | P2 | 重播每行都補換行，但錄音最後一行沒有換行，完成事件沒走到正式的串流結尾處理。 | `replayChunks()` 照原文一字不差切塊（最後一行沒有換行就照樣沒有、空行照送），新增切塊測試，23 案原文逐一驗證。重產後事件沒有因此改變。 |
| 2 | P2 | 從現有測試資料重產時，會換成語料裡現在的對話。 | 沿用並驗證封存的對話；語料不同只提醒、不換掉。新錄音才從語料取。 |
| 3 | P2 | 扣額度只記「有呼叫」，沒比對參數；測試帳號本來就免扣。 | 記下每次扣額度的參數並比對；重播改用一般付費用戶。23 案都是扣 1 則；改成 2 則測試會失敗。 |
| 4 | P2 | 涵蓋檢查只比筆數，漏案抓不到。 | 逐一核對寫死的 23 個案例名稱、拒絕重複；只留 3 案時測試會失敗。 |

主審 2 確認四項都已修正，沒有新發現。

## 測試（本機 WSL，deno 2.8.2，head `ba943248`）

- `bash tools/ci/edge-contract-tests.sh`：2,619 passed、0 failed、1 ignored（重播測試 25 條）。
- 改一張卡的一個字、扣額度則數改成 2、只留 3 案：重播測試都會失敗；還原後全過。用測試資料本身重產，輸出逐位元組相同。
- 原始錄音檔（`tools/analyze-v2-blackbox/out/2026-10-14-replay-rec/`）不進 repo；測試資料本身帶著錄好的原始輸出與封存的對話。

### 主審 1 回覆全文

```
發現 **4 項 P2**，未見 P0／P1。風險集中在重播安全網可能漏接回歸，未發現本次直接改變正式處理行為。

1. **P2：重播沒有保留原文結尾。**  
   `evidence/source/supabase/functions/analyze-chat/analyze_replay_harness.ts:56`  
   每行都補上換行，但 23 案原始輸出全部沒有末尾換行。最後的 `analysis.done` 因此不再經過正式解析器的串流結尾處理，可能漏掉這條路徑的回歸。應保留所有原始字元，切分片段時不要補換行或刪除空行。

2. **P2：重產既有 fixture 會換掉封存對話。**  
   `evidence/source/tools/ci/regen-analyze-replay-fixtures.ts:46`  
   即使來源是既有 fixture，仍取目前 `CORPUS` 的 messages。語料修改後，舊模型輸出會被配上新對話，改變雜湊、來源索引與後處理結果；重播兩次相同也無法發現。fixture 模式應沿用並驗證封存的 `messages`。

3. **P2：扣額度斷言只確認函式曾被呼叫。**  
   `evidence/source/supabase/functions/analyze-chat/analyze_replay_harness.ts:81`  
   `chargeRun` 忽略 `chargeQuota`、`messageCount`，因此目前測試帳號實際免扣，23 案卻都記成 `charged:true`。若扣額度參數改錯、事件維持不變，測試仍會通過。應保存並比較實際參數與呼叫次數。

4. **P2：完整語料檢查無法發現漏案。**  
   `evidence/source/supabase/functions/analyze-chat/analyze_replay_test.ts:24`  
   筆數只與同檔 metadata 比較，而生成器會自動重算 metadata。只留下各代表一種決策的三案重產，完整性檢查仍成立，其餘 20 案便退出安全網。應核對預期案例 ID 集合，拒絕缺漏與重複。

已核對五個變更檔案與 patch 的 head blob 一致；正式串流與後處理確實有執行，正規化去重、fetch 還原及入口載入鏈未見新增問題。現有 23 案完整，未見金鑰。

本輪未重跑 Deno；作者提供的紀錄為 **2,618 通過、0 失敗、1 忽略**。審查綁定 head `f98b225e291f0dd3ba36c52e7d8b74148fb207a0`，patch SHA-256：`c88168c89de2a6ff2b34b36b948f447cbeedc38f233220316a050be76515d5c9`。若保留上述 P2，依專案規範需 Eric 明確接受風險。

VERDICT: APPROVED_WITH_RISK
```

### 主審 2 回覆全文

```
本輪差異複核通過。規範與需求兩軸皆未發現新增 P0–P3；前輪四項 P2 均已修正：

- **原文結尾保留**：切塊不補換行、不刪空行，最後一行可進入正式結尾處理。`evidence/source/supabase/functions/analyze-chat/analyze_replay_harness.ts:60`
- **封存對話保留**：重產先驗證並沿用 fixture 的 messages，語料不同只提醒。`evidence/source/tools/ci/regen-analyze-replay-fixtures.ts:63`
- **扣額度完整比對**：逐次保存呼叫參數，並將 charges 納入期望值比較。`evidence/source/supabase/functions/analyze-chat/analyze_replay_harness.ts:87`、`:263`
- **漏案檢查補齊**：固定核對 23 個案例名稱，拒絕缺漏與重複。`evidence/source/supabase/functions/analyze-chat/analyze_replay_test.ts:54`

已唯讀核對四個變更檔案與 patch 的 base／head blob 一致。23 案的名稱、對話及原始輸出完全未變；期望值只新增 charges 與調整額度欄位，每案記錄一次扣額度、扣 1 則。

本輪未重跑 Deno；封包測試紀錄為 **2,619 通過、0 失敗、1 忽略**，其中重播測試 25 條通過。全程未連網、未呼叫付費 API、未執行 Flutter、未修改檔案。

審查綁定 head：`ba9432489709aea5b42c6ba7d56d6e1d1812e98b`  
patch SHA-256：`a73a1a9c2c29703ba24b72cb55ffe512733a417f59d424569bd1df8a36d04b0a`

VERDICT: APPROVED
```
