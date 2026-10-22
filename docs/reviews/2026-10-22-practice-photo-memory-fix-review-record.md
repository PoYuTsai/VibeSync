# 審查紀錄：練習室的她把自己的大頭照講成「你拍的」（PRACTICE_PHOTO_MEMORY_FIX）

- 日期：2026-10-22
- 範圍：origin/main `88ecf45d` 之後的 10 個 commit：`21b85bd3`（旗標與五段文字）、`ca2765df`（bug-log）、`e67db0c9`（主審 1 修正）、`3234e9f0`（主審 2 修正）、`10b8f729`（評測工具）、`15ce6b7d`（工具審查 1 修正）、`822eeeee`（拿掉「我那張」）、`dcc10900`（bug-log 與工具測試跟著改）、合併 `4dc9a9f9` 與本紀錄。分支 base 是 `b36614c7`；合併前 main 多了 PR #111（只改題庫檔），兩邊沒有重疊的檔案。
- 風險等級：R2（送給 AI 的練習室提示）。沒有資料庫 migration、Response 形狀、計費或額度改動。旗標預設關，關著時送給模型與回給 App 的內容逐位元組不變（等價 harness 保證）。
- 撰寫：Claude（Anthropic）；主審：Codex `gpt-6-astra`（OpenAI，唯讀，reasoning high）。

## 決定依據

- Bruce 2026-10-22〈練習室：她把自己的大頭照講成「你拍的」——實作規格〉與原型 diff（Eric 轉來）。
- Eric 2026-10-22「照預設」：做法與兩段新認識立場文字照 Bruce；由 Claude 實作、Codex 主審；評測多加一組「只刪不加」對照，付費前先乾跑；教練提示與檢討不動，評分器另案；Eric iPhone 驗收過才全開。
- Eric「照預設」：第 3 輪例外，只改 Game 例外句與它的測試，判 BLOCKED 就停。
- Eric「跑」：第 1 次付費評測；接受兩個限制：Tina 那題是重建不是逐字重播（結果單列），美元上限是估算。
- Eric「儲值了/A/跑」：只刪大頭照行的「提到它就說「我那張」。」，其他照 Bruce；第 4 輪例外，範圍只有這半句與它的測試，判 BLOCKED 就停；重量修正版。

## 改了什麼（白話，旗標開著時）

| 你傳什麼 | 舊版常見 | 修正版 |
|---|---|---|
| 「嗨 我是那天在路上跟你要IG的」 | 每 100 次約 9 次反過來考你：「你那天穿什麼」「先考你一下 當時我手上拿什麼」 | 720 次裡 1 次 |
| 「那天在夜店你喝很多欸」 | 約兩成會自己編那天的細節（「被朋友拉去的」「我只喝一點」） | 兩次量測 11%、17%，多是同類小細節 |
| 「那張是我幫你拍的吧」 | 否認 | 否認 |
| 正確描述她的大頭照 | 承認 | 承認 |
| 問她的大頭照在哪拍 | 照照片回答 | 照照片回答，主詞明確是她自己 |

- 五段文字：大頭照行明講「照片裡的人是你」，誰拍、哪天拍、他在不在場不硬編；現實錨定第一條補窄例外（認識當天的細節與照片沒拍到的事，系統沒給就是不知道，她前面講過的也不算）；街頭搭訕、夜店改用不要求他講出當天畫面的立場；記憶摘要「不能單獨證明」多列認識當天的細節；Game 例外句改成「系統沒給的認識當天細節與照片資訊，就算她前面說過也還是不知道」。
- 旗標 `PRACTICE_PHOTO_MEMORY_FIX`：`true`＝全部、`test`＝只有測試帳號、其他＝關；只在 agency `on` 生效；生效時 `practice_chat_succeeded` telemetry 多 `photoMemoryFix: true`。

## 主審（production 改動）

### 第 1 輪（全範圍）

- base `b36614c767a3b4640d7ca81599c0db50a8dc21ab` → head `ca2765dfa2805b953cfd9ac40fd454fe5e7fb77e`（tree `84b352f896eb131806b02fc7265e8dd203e9f2ae`）。
- 封包 SHA256SUMS.txt sha256 `293521eeebe427dafb770556f8eff6478a2aa98ba8a9208fc7b73a692d1fd0ed`；changes.patch sha256 `d8e289c95fa60cd6615d91300ded5676224dd1c806cab12e480ae29616f28505`。
- 回覆 sha256 `84b4747dbbde3288547a7f8b1a187d3b85a2dea2e4b76196630a9c8afe2c55a1`，`VERDICT: APPROVED_WITH_RISK`：P2 規格原本的 Game 例外句沒有「系統沒給」的限定，會讓系統給的工作、住處、今天活動也變成不知道；P3 等價 harness 只看合併 digest。
- 處理 `e67db0c9`：Game 句只管系統沒給的事；等價斷言改看送給模型的內容，standard 與 assisted 各至少一案要變、test 帳號比 messages。

### 第 2 輪（差異）

- base `ca2765df` → head `e67db0c9dfa177be222068d1e11d50f983704c66`（tree `0529f44a`）。
- 封包 sha256 `9ae68fdf87d908a6dfe9603889a6522e5532edec36d36543ef40a532e9f0d8e3`；changes.patch sha256 `f082af1f83afb42f5b75d1877cdd35ddc3a756e63a584fd11a4f501bb14ad152`。
- 回覆 sha256 `76cdc9bea04e1520d3b85fe31f5f6816f5bf0c62eb78dc4665980d60d04bb0d3`，`VERDICT: APPROVED_WITH_RISK`：第 1 輪都修好；新的殘餘 P2：Game 句把「誰拍、什麼時候拍」一律當不知道，跟照片描述已經寫明的拍攝資訊衝突。

### 第 3 輪（Eric 例外輪，差異）

- base `e67db0c9` → head `3234e9f08650ee506d5396cd59f5ff718217c4d1`（tree `5cbb476b`）。
- 封包 sha256 `66dcd62cf1db99469203f7ca5ec70a416c4da971ac03e361a4a48f36d9ccb8b9`；changes.patch sha256 `f99c37a7aa6cf7a07378db24fad8f092cbf4f749c328fe17eb9e215a3c8ef78f`。
- 回覆 sha256 `aa39e8dacd9ca8ce6d11e8e698694622fa840c625b576f6e775ea3a047c595ed`，`VERDICT: APPROVED`：照片已知資訊衝突已修，沒有新的 P0–P3。

### 第 4 輪（Eric 例外輪，差異）

- base `15ce6b7d` → head `dcc109001b26cf5fd27d4b426d12090302f67c64`（tree `05836f0b3e5764229d2834fde66cdbfc1d40f07f`）；`3234e9f0` 到 `15ce6b7d` 之間只有兩個工具 commit，另外審過。
- 封包 sha256 `bc38d421cd9bd4a96ba2b11e4963c7c330b3a6fa932947f6083be92ee30a74c0`；changes.patch sha256 `9bfe4adf87d0e4a2fb760f269c5df20133bcabc8170a55f29d79b4fa68b6a460`。
- 回覆 sha256 `b17fe3b81412f20d4d35e8007abe0214be6b30a1dddc884f169ea6a0aa139155`，`VERDICT: APPROVED`：沒有新的 P0–P3；主審獨立算出固定句 90 code units。

## 工具審查（只動 tools/）

- 第 1 輪：base `3234e9f0` → head `10b8f72904fea8f769181f7f8a86eb4b4aa61272`（tree `cf3fe895`），封包 sha256 `dc0fa16aac6c1f146421da419c801c4b21041b81b4345571f80072da7fe6941b`，changes.patch sha256 `2d6189659118189d01a4fad406d4a3a66f7bd01521dca1042adfdd3cec90b0cb`，回覆 sha256 `3b2a439b1e6d319513e113d5f5ae2f39055022fd891d2e18993f3e2909e3864b`，`VERDICT: BLOCKED`：P1 分類器繞過付費守門；P2 Haiku 沒回 usage 時以零結算；P2 兩題的必須項會把合法回答算成沒做到；P2 照片情境沒跑 Game、沒有 Tina 重播。
- 處理 `15ce6b7d`：四項都修（分類器也預留、沒 usage 保留預留額、那兩題不宣告必須項、補 Game 照片情境與 Tina 重建 A34R）。
- 第 2 輪：base `10b8f729` → head `15ce6b7d1da2e2981cd35d4597564c7e2e0eba32`（tree `cd7b7091`），封包 sha256 `f71bd67be29161afb69382dfbb83881d65320e518cbfb4aba15069c6ede63681`，changes.patch sha256 `dbf58c9a5a2563a24ed1b98c0843622ab5118949f858b44cb27a4a32a9b4446f`，回覆 sha256 `3750be9c65387f274f176f4fed5f7ad1465c5d459300c4c2adddbd33d14db81b`，`VERDICT: APPROVED_WITH_RISK`：A34R 是重建，美元上限是估算；Eric 回「跑」時接受這兩項。

## 離線評測

工具 `tools/practice-agency-eval`，評審 DeepSeek，同一套 production `buildChatPromptBundle`；Game 用 20 位 SR 角色；Standard 另加 18 位自拍角色與 Fiona 的照片題；每格連跑 3 批。比率不含 A34R（Tina 重建，另列）。

### 第 1 次（`15ce6b7d`，三臂）

| 指標（Haiku Game／DS Game／Haiku Std／DS Std） | off | 修正版（含「我那張」） | 只刪不加 |
|---|---|---|---|
| 考題率 | 4.4／5.6／5.6／6.7% | 0／0／0.8／0% | 0.8／0.6／0.6／0% |
| 主詞錯置 | 全 0 | 全 0 | 全 0 |
| 自編當天細節 | 3.2／8.1／3.6／6.6% | 1.9／6.5／2.3／2.7% | 3.2／5.1／1.7／5.1% |
| 照片講對承認 | 100% | 100% | 100% |
| 照片題回覆含「我那張」 | 0 | 3/18、5/18、46/171、14/171 | 0 |

- 門檻（規格 §9.5）：考題率 Wilson 上界 ≤5% 四格都過；降幅大於批間極差：Standard 兩個模型過，Game 兩個模型 on 六批全 0、off 六批全 >0，但 off 自己的極差（5.8、6.0 個百分點）大於平均降幅，照嚴格規則算沒量到。主詞錯置 off 也是 0，這批情境沒重現，只能證明沒變差。
- 「只刪不加」的考題降幅跟修正版差不多、沒有「我那張」，夜店自編細節較多（19% 對 11%）。
- 副作用：修正版在照片題把「我那張」硬塞成口頭禪（「對啊，我那張」）→ Eric 拍板拿掉那半句。

### 第 2 次（`dcc10900`，最終版）

| 指標（Haiku Game／DS Game／Haiku Std／DS Std） | 最終版 |
|---|---|
| 考題率 | 1/359、0/360、2/360、0/360（Wilson 上界都 ≤2.0%） |
| 主詞錯置 | 0（DS Std 有 1 則是評審把反話「最好是」當承認，人工核對是否認） |
| 自編當天細節 | 3.8／5.6／1.5／4.4% |
| 照片講對承認 | 100% |
| 照片題回覆含「我那張」 | 0/18、0/18、0/171、0/171 |

- 舊題回歸（A01–A33＋兩題截圖，DeepSeek，Standard 與 Game 各一批）：最終版對 off 沒有一項變差到 95% 區間不重疊。
- 長對話旁白：A25 Game 合併 80 場，off 與最終版各有 2 場因為兩次都寫出旁白被擋而失敗；不是這次改動造成。
- A34R（Tina 重建，題目已經寫在逐字稿裡）：兩次、各臂都沒有說「你拍的」；但題目已經出了之後，新舊版都常拿大頭照裡的奶茶回答自己的考題。修正版擋住的是第一題。

### 花費

- 第 1 次：Haiku US$19.451（API 回報的用量）；DeepSeek 把跟正式環境共用的帳戶餘額用完（-0.01），儲值前正式環境練習室的 DeepSeek 呼叫可能失敗（未核實是否有用戶碰到），Eric 儲值後恢復。之後的評測腳本每格開始前查餘額，低於 US$15 就停。
- 第 2 次：Haiku US$6.523；DeepSeek 約 US$5.15（餘額 19.98→14.83，含同時段正式環境用量）。工具裡的 DeepSeek 觀測單價（評審 $0.0002027／次）明顯偏低，估費要另外校正。

## 殘餘風險

- 主詞錯置在評測裡新舊版都是 0，修正版只證明沒變差；2026-10-21 那種講法要靠 iPhone 驗收與 telemetry 確認。
- 題目已經在對話裡時（例如旗標開之前就聊過的舊 thread），她仍可能拿大頭照內容回答自己的考題。
- 夜店那題兩次量測差很多（11%、17%），自編的小細節（「被朋友拉去的」）沒有穩定減少；Game × DeepSeek 自編率仍約 5～6%。
- 「含『我那張』」是字串計數，不完全等於不自然。
- 規格 §9.4 的「每格抽 30 則給 Eric 盲看」沒有做；Claude 逐字讀過各臂的命中與照片題回覆，「我那張」問題就是這樣抓到的。

## 上線步驟

1. 推 main（旗標未設，行為不變）→ Build & Distribute 與 Deploy Edge Function；確認 practice-chat 換版。
2. Eric 核准後設 `PRACTICE_PHOTO_MEMORY_FIX=test`，用測試帳號在 iPhone 照規格 §10.1 驗收六項。
3. 觀察幾天有 `photoMemoryFix: true` 的 telemetry，Eric 核准後改成 `true`。
4. 回滾：把 secret 改成 `off` 或刪掉，不用改程式、不用重新部署。

## 測試證據

- 合併 `4dc9a9f9` 上：`tools/ci/edge-contract-tests.sh` 3293 通過、0 失敗、1 略過；PGlite 那步六檔 174 通過；`deno test -A supabase/functions/practice-chat` 2099 通過、0 失敗、1 略過；評測工具 120 通過。沒有改 Dart，沒有跑 `flutter test`（Build & Distribute 會跑）。
- `dcc10900` 上：清單權限（`--allow-env --allow-read`）跑 prompt_test＋等價 harness 145 通過；`deno check` 通過；`deno fmt` 差異跟改前相同。
- mutation：每輪都把關鍵改動改回去，對應測試會失敗（第 4 輪：把「我那張」半句加回去，兩支失敗）。
- 送出範圍 `ops scan`（gitleaks）clean；課程 12 字比對 0。

### 主審 1 回覆全文

```
本輪判定為附風險通過：旗標接線與規格一致，但有一項 P2 提示衝突需 Eric 明確接受風險或交回修正，尚不能視為啟用驗收通過。

1. **P2｜Game 新句可能把系統已知事實也排除。**  
   `evidence/source/supabase/functions/practice-chat/prompt.ts:278–279` 無條件要求照片沒呈現的事情維持未知，缺少中文錨定第 460 行的「系統沒給」限定。例如 Tina 的工作、住處與當下活動已由系統提供，卻不在便利商店自拍中；新句與同段允許 `profile`、`sceneContext` 支持事實的規則衝突。這是已確認的指令矛盾，實際造成失憶或否認的頻率**未核實**。  
   建議限縮為「系統未提供的認識當天細節，以及該張照片的拍攝背景細節」，明確保留其他可信事實。實作雖逐字符合規格 §5.8，仍違背 §5.5「工作、住處、今天狀態照舊」的意圖；既有字串存在性測試抓不到這項衝突。

2. **P3｜等價測試的生效判斷可能只測到 telemetry。**  
   `evidence/source/supabase/functions/practice-chat/agency_flag_off_equivalence_test.ts:2292–2305、2323–2336` 用四面合併 digest 不同判定生效。若日後移除 handler 兩處 `photoMemoryFix` 傳參、保留 telemetry，這些條件仍能成立；直接呼叫 builder 的單元測試也無法抓到 handler 斷線。  
   建議對 standard 與 assisted 的成功生成案例，分別斷言模型 `messages` 確實改變；測試帳號的 `test` 分支也比對 messages。**目前兩處接線正確，這是回歸測試缺口。**

其餘核對結果：

- 旗標值解析、agency 二次限制、位置參數，以及未生效時省略 telemetry key，均正確；未見本次改動造成關閉分支差異。harness 的亂填、shadow、一般帳號 `test` 等比較確實接到新維度。
- 兩個 `replace` 的搜尋文字各命中一次；新測試會檢查替換結果。照片「講對就承認」與認識管道「不需要他證明」均保留。
- 穩定前綴與當輪尾巴的切分未變。新測試名稱宣稱完整串接等價，實際只驗 `startsWith`；目前原碼確實直接串接，沒有現行功能錯誤。
- Game 預算測試使用同管道 off 對照，修正版套用「至少短 1,000」及「≤80,300」兩道門檻。
- 我以唯讀計算核實 standard 增量：夜店 +60、其他管道 +71、街頭 +79 code units；有摘要再加 8，最高 +87。有認識管道的 Game 例外句縮短 142。
- 夜店刪除的是「對上當天畫面才自然接話」條件；半信半疑、朋友拉去及酒精界線仍保留。hint、debrief、朋友圈與評分器未被額外修改。

殘餘風險與驗證限制：

- 聚會管道「接上那天的場合」仍可能引出考題，屬規格明確保留的既有風險。「我那張」是否變口頭禪、照片承認率是否退步，以及已知事實是否被否認，仍需兩種模型的行為評測。
- 作者證據記載全套 **2099 passed／0 failed／1 ignored**，部署清單兩檔 **145 passed／0 failed／1 ignored**；本輪未重跑 Deno、Flutter 或模型評測，也未連網核實 CI。
- manifest 全部項目校驗通過；六個修改檔的 head blob，以及在記憶體反向套用 patch 後的 base blob，均與 patch 索引一致。封包沒有完整 Git 物件，未獨立重算 commit／tree。未修改任何檔案。

審查綁定：第 1 輪，head `ca2765dfa2805b953cfd9ac40fd454fe5e7fb77e`。  
`SHA256SUMS.txt` SHA-256：`293521eeebe427dafb770556f8eff6478a2aa98ba8a9208fc7b73a692d1fd0ed`。  
`changes.patch` SHA-256：`d8e289c95fa60cd6615d91300ded5676224dd1c806cab12e480ae29616f28505`。

VERDICT: APPROVED_WITH_RISK
```

### 主審 2 回覆全文

```
本輪判定為附風險通過：原 P2 對工作、住處與當下活動的過度限制已修正，P3 測試缺口已補上，但照片已知資訊仍有一項 P2 殘餘風險。

以下程式檔案位於 `evidence/source/supabase/functions/practice-chat/`。

1. **P2｜殘餘風險：照片拍攝資訊仍被無條件列為未知。**  
   `prompt.ts:281–282` 的「系統未提供」限定只修飾認識當天細節；後面的 `who took your photo, when, or whether he was there` 仍一律要求未知。可是 `practice_persona.ts:1401` 已明寫 Tina 的照片是「晚上……拍的自拍」。若玩家問「這是妳晚上自拍的吧」，新句可能與人物設定及「講對就承認」互相衝突。**指令衝突可確認，實際否認頻率未核實。**  
   建議照片部分也限定為「系統未提供的拍攝資訊」，並保留已知時段與自拍事實。依本輪規則，此項列為殘餘風險，不追加阻擋。

2. **原 P2｜一般事實與認識當天細節的邊界已修正。**  
   `prompt.ts:281、286` 已移除廣泛的 `anything your photo doesn't show`，保留一般事實的來源清單；工作、住處、今天活動及朋友圈不再被這句全面排除。認識經過仍只能來自管道資料，未提供的當天細節不能靠她先前說過的話升格為事實，未見重新允許補造的缺口。

3. **原 P3｜handler 接線回歸測試已修正。**  
   `agency_flag_off_equivalence_test.ts:2299、2312–2320、2339–2354` 分別要求 standard 與 assisted 的模型 messages 改變，測試帳號也直接比較 messages。依目前資料流，移除 `handler.ts:5009` 或 `5040` 任一處傳參，對應群組便無 messages 差異，斷言會失敗，telemetry 無法掩蓋。  
   `.some()` 不依賴案例順序；`.find()` 只在已確認有差異的案例中取樣，每次呼叫建立獨立 fake，未見新增順序污染。`test` 分支仍只抽一案，並非兩條路徑完整覆蓋。

`prompt_test.ts:3628–3657` 的改名與新增斷言符合實際檢查內容：穩定前綴成立，記憶摘要與 Game 指定句位於前綴之外。

驗證與限制：

- manifest 全部項目校驗通過；三個修改檔的 head blob，以及記憶體反向套用 patch 後的 base blob，均符合 patch 索引。
- 作者證據記載全套 **2099 passed／0 failed／1 ignored**、兩檔 **145 passed／0 failed／1 ignored**，以及三項 mutation 均失敗。我未重跑 Deno 或 mutation，未執行 Flutter、連網或修改檔案。
- 未獨立重算 commit／tree，未驗證模型行為或線上 CI。此結論是封包差異複核；若接受上述 P2 風險繼續啟用，仍需 Eric 明確接受。

審查綁定：第 2 輪，head `e67db0c9dfa177be222068d1e11d50f983704c66`。  
`SHA256SUMS.txt` SHA-256：`9ae68fdf87d908a6dfe9603889a6522e5532edec36d36543ef40a532e9f0d8e3`。  
`changes.patch` SHA-256：`f082af1f83afb42f5b75d1877cdd35ddc3a756e63a584fd11a4f501bb14ad152`。

VERDICT: APPROVED_WITH_RISK
```

### 主審 3 回覆全文

```
本輪差異複核通過：第 2 輪的照片已知資訊衝突已修正，未發現新增 P0–P3 問題。

以下路徑相對於 `evidence/source/supabase/functions/practice-chat/`。

1. **原 P2 已解決。** `prompt.ts:282–283` 將照片資訊限定為「系統沒給才未知」，因此 `practice_persona.ts:1401` 已提供的「晚上」「自拍」不再被無條件排除；與大頭照行「講對就承認、不硬編」一致。
2. **事實來源邊界保留。** `prompt.ts:287` 仍允許 profile／sceneContext 等來源支撐事實，工作、住處、今天活動與朋友圈未被新句全面排除。`prompt.ts:282` 仍限定認識管道來源，並禁止先前自編的未知細節升格為事實，與中文錨定 `prompt.ts:464` 一致。
3. **測試與預算未見回歸。** `prompt_test.ts:3539–3549` 檢查新句、排除舊句並保留事實來源規則；`prompt_test.ts:3657` 更新當輪尾巴檢查。唯讀計算確認有／無認識管道的例外句分別縮短 **33／14 個字元**，既有預算門檻未放寬。

殘餘風險與驗證限制：

- 字串測試不能證明模型實際遵循；自拍與時段承認率、自編記憶是否停止延續，仍須行為驗收。
- 作者證據記載全套 **2099 passed／0 failed／1 ignored**、指定兩檔 **145 passed／0 failed／1 ignored**，以及回退舊句的 mutation 測試失敗；我未重跑。
- manifest 全數校驗通過；兩個修改檔的 head blob，以及記憶體反向套用 patch 後的 base blob，均符合 patch 索引。未獨立重算 commit／tree，未連網、執行 Flutter 或修改檔案。

審查綁定：第 3 輪，head `3234e9f08650ee506d5396cd59f5ff718217c4d1`。  
`SHA256SUMS.txt` SHA256：`66dcd62cf1db99469203f7ca5ec70a416c4da971ac03e361a4a48f36d9ccb8b9`。  
`changes.patch` SHA256：`f99c37a7aa6cf7a07378db24fad8f092cbf4f749c328fe17eb9e215a3c8ef78f`。

VERDICT: APPROVED
```

### 主審 4 回覆全文

```
第 4 輪差異複核通過，未發現本輪新增 P0–P3 問題；模型實際表現仍須完成評測與真機驗收。

以下路徑相對於 `evidence/source/`：

1. **語意與主詞完整。** `supabase/functions/practice-chat/prompt.ts:793` 保留「照片裡的人是你」，刪句後仍要求照照片回答、不硬編、講對就承認；與現實錨定及 Game 例外一致。`tools/practice-agency-eval/judge_agency.ts:105` 允許自然使用「我那張」，並未要求使用，沒有衝突。
2. **關閉分支未受影響。** `prompt.ts:1031` 仍要求 agency 為 `on` 且旗標開啟；舊照片常數、等價 harness 與 golden 均不在本輪差異內。未見新增的字面依賴。
3. **測試鎖住刪句決定。** `prompt_test.ts:3526、3667` 分別檢查不含「我那張」及固定句長度。我獨立計算前後綴合計 **90 UTF-16 code units**，較原版少 11；既有預算門檻未放寬，`prompt.ts:1188` 的穩定前綴組裝方式未改。
4. **註解與文件符合所附證據。** `prompt.ts:790`、`docs/bug-log.md:19、21` 的約 8～28%，與評測表的 14/171 至 5/18 相符；評測工具清單同步移除該字串，符合本輪範圍。

殘餘風險與驗證限制：

- 評測只有摘要，未附原始回覆供逐筆核對；「含該字串」不能完全等同「不自然口頭禪」。本輪 Haiku 結果支持刪句，DeepSeek 結果尚未完成；主詞錯置為零也不能保證真實對話不復發。
- 作者記載全套 **2099 passed／0 failed／1 ignored**、指定兩檔 **145 passed／0 failed／1 ignored**、評測工具 **120 passed／0 failed**，以及加回半句會使兩項測試失敗；我未重跑。
- manifest 的 **166 項全部校驗通過**；四個修改檔的 head blob，以及記憶體反向套用 patch 後的 base blob，均符合 patch 索引。未獨立重算完整 commit／tree；未修改檔案、連網或執行 Flutter。

審查綁定：第 4 輪，head `dcc109001b26cf5fd27d4b426d12090302f67c64`。  
`SHA256SUMS.txt` SHA256：`bc38d421cd9bd4a96ba2b11e4963c7c330b3a6fa932947f6083be92ee30a74c0`。  
`changes.patch` SHA256：`9bfe4adf87d0e4a2fb760f269c5df20133bcabc8170a55f29d79b4fa68b6a460`。

VERDICT: APPROVED
```

### 工具審查 1 回覆全文

```
本輪有付費守門漏洞與評測覆蓋缺口，建議修正後再進行付費評測；結論為 **BLOCKED**。

審查綁定指定 head `10b8f72904fea8f769181f7f8a86eb4b4aa61272`。Manifest 雜湊符合提供值，全部檔案校驗通過，七個改動檔的 Git blob 雜湊也符合 patch。

以下行號皆相對於 `evidence/source/tools/practice-agency-eval/`。

1. **P1｜`run_agency.ts:1519`、`:1595`：分類器繞過呼叫次數與預算上限。**  
   新守門只包住聊天生成；`--state=1` 的兩條分類器路徑仍在第 914、941 行直接呼叫 DeepSeek。例：設定 `--max-calls=1 --concurrency=1`，第一輪生成成功後仍會送出第二次、未記帳的分類器請求；其他 worker 觸發停止後，已完成生成的 worker 也可能繼續送分類器。建議將分類器納入同一個 `PaidBudget`，並讓預算停止錯誤中止後續呼叫；補上端到端假呼叫測試。

2. **P2｜`run_agency.ts:1515`：成功回覆缺少 usage 時，預留費用被沖成零。**  
   `callHaikuChat` 第 1407 行把 usage 初始化為全零；若 API 回傳有效文字但未附 usage，這裡仍以零元結算，違反第 362 行「沒回 usage 時保留預留額」的承諾。連續發生時，美元上限無法反映已送出的請求。建議明確區分「缺少 usage」與「實際零用量」，缺少時保留預留額，並補回歸測試。

3. **P2｜`scenarios.ts:1139`、`:1169`：合法回答會被判為未滿足要求。**  
   A35.p2、A37.p1 強制要求 `clarify_or_challenge`，但 `judge_agency.ts:71` 的定義只涵蓋語意澄清、跳題或未回答問題。例如「不是，是我自己自拍的」及「那晚喝多少我不記得了」都符合情境要求，卻不符合該標籤，會拉低總體與逐情境的 `allowSatisfied`。建議調整正向判準，並以這兩種合法回答驗證；單純清空 `mustAllow` 也須處理 evaluator 的空集合語意。

4. **P2｜`README.md:3988`、`scenarios.ts:1093`：執行矩陣缺少原始故障的重要覆蓋。**  
   指令與乾跑把 A35／A36 全放在 standard，未執行規格 §9.3 要求的 SR Game 照片情境；自拍 SR 007、036 的 Game 路徑因此沒有量到。Game 又有獨立修改的例外句，standard 結果不足以替代。另外，A34 只有泛化三句，未見規格要求的 Tina 真機逐字重播。建議補齊情境與執行矩陣，重新乾跑及估價；A35 已固定角色名單，不能只靠 `--profiles` 縮成 SR 子集。

其餘核對結果：未發現 Haiku 一般生成、重試或 `check_out` 改寫重送繞過守門；前置檢查在讀金鑰之前。只刪不加的替換位置、管道覆寫、production 名單對照、新指標聯集分母與 Wilson 算式未見錯誤。自編細節率多納入 `meeting_detail_challenge` 已於 README 說明。

驗證限制與殘餘風險：

- 未重跑 Deno 測試；封包缺少 `traditional_chinese.ts` 等必要相依檔，測試證據只有作者摘要。
- 乾跑的 `meta.commit` 均為 base；無法獨立核實執行時工作樹等同本輪 head。
- DeepSeek 使用觀測單價，Haiku 使用字數估算預留，美元數值仍有估算限制。舊 artifact 缺少新標籤時的 0% 不能解讀為沒有問題。
- 全程未修改檔案、未連網、未呼叫付費 API。

`changes.patch` SHA256：`2d6189659118189d01a4fad406d4a3a66f7bd01521dca1042adfdd3cec90b0cb`

VERDICT: BLOCKED
```

### 工具審查 2 回覆全文

```
前三項修正已通過靜態複核，Game 照片覆蓋已補齊；Tina 逐字重播仍未完成，列為 P2 殘餘風險，需 Eric 接受此限制。

審查綁定 head `15ce6b7d1da2e2981cd35d4597564c7e2e0eba32`。Manifest 雜湊符合指定值，245 個檔案校驗全部通過，五個改動檔的 Git blob 雜湊也符合 patch。

以下行號相對於 `evidence/source/tools/practice-agency-eval/`。

1. **原 P1 已修正｜`run_agency.ts:937`、`:965`、`:1632`。**  
   兩條分類器路徑在送出前使用 main 共用的 `PaidBudget`。一般生成、mixed 選模、重試與 `check_out` 改寫重送均經過預留；底層 API 呼叫沒有隱藏重試。未發現本輪範圍內仍繞過已啟用守門的付費路徑。

2. **原 P2 已修正｜`run_agency.ts:405`、`:1434`、`:1544`。**  
   缺少 usage 時回傳 `null`，保留預留費用並累計 `missingUsageCalls`；不再按零元結算。

3. **原 P2 已修正｜`evaluate_agency.ts:474`、`:542`、`:586`。**  
   沒宣告 `mustAllow` 的探針不再拉低 `allowSatisfied`，逐情境無適用探針時為 `null`。A01–A33 現有的 56 個探針皆有非空 `mustAllow`，同一批既有資料的分子、分母及 bootstrap 輸入不變。含 A35／A37 的跨版比較則須使用同一 evaluator 重算。

4. **原 P2 部分修正；保留 P2 殘餘風險｜`scenarios.ts:1140`、`:1187`；`run_agency.ts:695`。**  
   A35G、A36-007／036 已補進三個 Game 對照臂。但 A34R 將考題寫死並跳過第一輪生成，只能量「已經出題後是否繼續編造」，不能證明模型不再出第一題，也不能替代 Tina 真機逐字重播。README 已明示重建限制。建議結果單列，不將其當作自然對話發生率或真機修復證據。

驗證限制與其他殘餘風險：

- 六份乾跑都記錄本輪 head；數量與摘要相符，合計 2,745 次生成、預留估算 US$52.67。但乾跑不驗證真實模型行為。
- 未重跑 Deno 測試。封包未附環境契約與執行原始日誌，120 passed 與 mutation 結果僅有作者摘要；部分專案政策參考文件亦未附。
- DeepSeek 仍採觀測單價、Haiku 採字數估算預留，美元上限不是供應商帳單的精確硬上限。
- 全程未修改檔案、未連網、未呼叫付費 API。

`changes.patch` SHA256：`dbf58c9a5a2563a24ed1b98c0843622ab5118949f858b44cb27a4a32a9b4446f`

VERDICT: APPROVED_WITH_RISK
```
