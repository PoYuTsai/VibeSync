# 共用模型呼叫層：5.5 備援鏈、拒答類別與先於逾時、白名單與價格表（ADR #55）審查紀錄

- 本機分支 `claude/shared-model-55-chain`，base 是 main `38ab7dbb`。程式由 Claude（Anthropic）撰寫。
- Eric 交辦（2026-10-12）：對對話分析改版三項決定回「預設同意」，第三項含「5.5 備援鏈拿掉 Haiku」；開場救星與新話題 session 轉述 Eric 回「跑」、其中一項是共用那一刀先做不等 PR #97，本 session 再用選項直接問 Eric，Eric 選「現在先做（建議）」。
- R2：共用模型呼叫層（開場救星、新話題、對話分析都會用到）的備援鏈、拒答與期限的處理、ai_logs 記錄、測試帳號可指定的模型、成本記錄用的價格表。不動提示詞、扣費、DB、migration、App。
- **主審（關卡）**：Codex（OpenAI）唯讀，`codex exec --sandbox read-only --skip-git-repo-check`，預設兩輪（全範圍一輪＋修正後差異複核一輪）。送審封包是純檔案樹＋format-patch＋測試紀錄＋審查範圍說明；封包 sha256 是封包內全部檔案依路徑排序的 sha256 清單（`SHA256SUMS.txt`）的 sha256，Codex 兩輪都回報清單核對通過。

| 輪 | 範圍（base → head） | packet manifest sha256 | 回覆 sha256 | 結論 |
|---|---|---|---|---|
| 主審 1 | `38ab7dbb` → `790188978ea0013885ada2bfacef84e56ef9ee7a` | `2fd4e94478bdb60cc7a142ac42d5f5aa9434a0d015d797ba636023fda3d04a33` | `a6b05b7462e36c35db185ba83486338b68e8c5ed4f04619a15d0a14b7e9302c8` | APPROVED（兩項 P3） |
| 主審 2（差異複核） | `79018897` → `92e95e0c8637e1c184ce38e3f1282dd2b4fd6f55` | `a96b1b134c62f3f865d18cbc2b68649fa38c4d94b4cf67330020dfdba762666d` | `908f34416831b92f3648dcf6689aa9bc7bc9d6d574ca612c0ba43a9c0a9d011f` | APPROVED（兩項 FIXED） |

## 主審 1 的發現與處置

| # | 等級 | 發現 | 處置 |
|---|---|---|---|
| 1 | P3 | 串流若已先有別的錯誤，之後才到的拒答類別不會記進 ai_logs。 | 兩個 catch 都先合併拒答類別，再照舊只在沒有錯誤時設定錯誤事件；錯誤代碼仍用先到的那個，類別只交給 `markFailed`。補測試（扣額度失敗之後才被拒答），修正前會失敗。 |
| 2 | P3 | ADR 把「含主模型共 3 次」寫成無條件；`maxRetries: 2` 且沒有呼叫預算時，非串流最多會打六次。 | 核實正式呼叫點 7 處都設 `maxRetries: 1`，沒有超額呼叫。ADR 與 `model_fallback_chain.ts` 註解寫明前提，並說明設更多重試時有無呼叫預算的差異。 |

- 主審 1 的更正：封包說明寫「`model_call_budget_test.ts` 不在 CI 白名單」是錯的，它在 `flutter-ci.yml` 的名單裡。已核實並更正分支 STATE。
- 主審 1 列的範圍外殘餘風險：(a) 開場、新話題 handler 在 catch 裡先用目前時間判斷期限，共用層照實回的拒答若在期限後才回來，仍會被當逾時處理（一律釋放、不扣，用戶看到逾時而不是請調整內容）；已轉告該分支的 session。(b) `streaming_fallback.ts` 的 `prependFirstChunk`：呼叫端拿到第一塊就結束迭代時，內層沒有關閉，cleanup 與呼叫記錄可能不跑；這是既有問題，這一刀沒有引入，留待之後處理。

### 主審 1 回覆全文

````text
審查範圍：`38ab7dbb..79018897`。未發現 P0／P1／P2；有兩項不擋的 P3。

- [P3] 已有串流錯誤時會漏記後續拒答類別 — `supabase/functions/analyze-chat/stream_handler.ts:343` — 若 reframer 先產生 `analysis.error`，之後 provider 才送出拒答，`pendingError` 已存在，便不會執行 `upstreamLogDetails(error)`，導致 ai_logs 缺少拒答類別。可保留原本錯誤優先序，但將類別擷取移到條件外；目前新增測試只涵蓋直接拒答。
- [P3] ADR 將三個模型寫成無條件三次呼叫 — `docs/decisions.md:1404` — 非串流設定 `maxRetries: 2` 且未提供 budget 時，最多仍會呼叫六次；提供 budget 則第三次後停止，可能尚未走到 4.6。應註明三次成立的前提。快照內正式 handler 均指定 `maxRetries: 1`，未見本次造成超額呼叫。

範圍外，殘餘風險：

- 既有開場／新話題 handler 仍以目前時間判斷期限，可能將共用層保留的拒答重新轉成逾時。未見因此新增扣額度或漏釋放路徑；另一分支仍須驗證對使用者的拒答訊息。
- `streaming_fallback.ts:185` 既有首塊包裝器若在第一個 chunk 後立即 `return()`，尚未進入 `yield* rest`，不會關閉內層 iterator，可能漏執行 cleanup／finish。此次未引入此問題。

**Checked and OK**

- 串流與非串流均保留原始主模型決定備援鏈；5.5 不會走到 Haiku，Sonnet 5 原鏈不變。禁止 fallback、未知模型及 budget 三次上限的分支正確。
- 非串流期限轉換僅豁免 `MODEL_REFUSAL`；拒答不重試、不換模型。成功逾期仍失敗，較短單次 timeout 語意保留。
- `cleanupOnStreamEnd` 保留既有服務錯誤物件，其他錯誤映射不變；正常耗盡與進入內層後提前結束的狀態正確，`finish` 保持冪等。
- 新增 response_body 欄位只選取失敗代碼與經過格式過濾的類別；未見 explanation 或類別被新增至 App 回應。
- 價格符合題示規格；Haiku 門檻嚴格大於 100,000，包含快取讀寫，整次套用分級。兩份價格表一致；既有保險絲使用的價格未改。
- 5.5 白名單未繞過測試帳號／TEST_MODE 限制，也未改變計費判斷。
- SHA-256 清單全部核對通過。所附紀錄為 head 1445／0、main 1423／0；本輪採靜態審查，未重跑 Deno、執行 Flutter 或呼叫外部 API。另更正：CI 已包含 `model_call_budget_test.ts`（`flutter-ci.yml:133`）；未附串流測試在舊程式上的失敗紀錄，該項未核實。

VERDICT: APPROVED
````

## 主審 2（差異複核）

兩項 P3 都標 FIXED，沒有發現修法引入新問題。

### 主審 2 回覆全文

````text
審查範圍：`79018897..92e95e0c`。兩項均已修正，未發現本輪修法引入新問題。

- **P3-1：FIXED** — `stream_handler.ts:344、357`：兩個 catch 均在判斷 `pendingError` 前合併拒答類別，保留先到的錯誤代碼。細節只傳給 `markFailed`，未混入 App 事件。`stream_handler_test.ts:535` 涵蓋扣額度失敗後拒答、原代碼保留及類別不外送。
- **P3-2：FIXED** — `docs/decisions.md:1404`、`model_fallback_chain.ts:3`：已明定每個模型只試一次的前提，ADR 另說明增加重試時有無預算的差異；與重試迴圈及三次預算限制一致。ADR 決定 2 也已補上先到錯誤與後到拒答類別的處理。

CI 更正正確：`.github/workflows/flutter-ci.yml:133` 包含 `model_call_budget_test.ts`。但提供的快照未含 STATE，故「已記入 STATE」**未核實**。

SHA-256 清單全部核對通過。所附完整測試紀錄為 **1446 passed／0 failed**，包含新增測試；修正前失敗證據僅為摘要，未附完整斷言輸出。本輪採靜態審查，未重跑測試、修改檔案、執行 Flutter 或呼叫外部 API。

快照清單 SHA-256：`a96b1b134c62f3f865d18cbc2b68649fa38c4d94b4cf67330020dfdba762666d`

VERDICT: APPROVED
````

## 合併最新 main 之後

- 主審 2 通過後，main 前進到 `0ffd8b60`（開場救星與新話題，ADR #54，已有自己的主審紀錄）。分支併入 main，兩邊只有 `docs/decisions.md` 同時改動，程式碼沒有重疊；衝突只在檔尾，依編號排 ADR #54、#55，並在 ADR #54 決定 2 補記備援鏈已改。
- 併入後 `deno test --allow-env --allow-read supabase/functions/analyze-chat supabase/functions/_shared`：1465 passed、0 failed；同指令在 main `0ffd8b60` 是 1442 passed、0 failed，差 23 條＝這一刀新增的測試。
- 主審之後新增的只有文件（合併時 ADR 檔的衝突解法、本紀錄、ADR #55 驗證數字），程式碼與主審 2 通過的版本相同。
