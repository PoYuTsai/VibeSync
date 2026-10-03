# VibeSync 踩坑整理（給 Bruce）

> 適用範圍：對話分析（analyze-chat，也就是分析聊天截圖並建議回覆的功能）的 prompt 清理、串流體驗與結構刀，以及可能會碰到的開場救星（Opener）、新話題（New Topic）、教練（Coach）、練習室（Practice）。
> 來源標〔vault〕的條目出自 Eric 的 Dev Brain（Obsidian 筆記庫）的 `20_踩坑紀錄/`，**以 vault 為最新真相**。Bruce 的 agent 讀不到 vault，需要全文時請 Eric 貼出來。其他來源都是 repo 路徑。
>
> 先講幾個內部用語：
> - **黑箱**：用真模型批次跑固定輸入的付費評測工具，放在 `tools/*-blackbox` 等資料夾。
> - **守門**：模型輸出產生後，由程式做的檢查。
> - **結構刀**：品質問題不加規則，改用改輸入、拆步驟、換決策機制的方式解決。
> - **claim**：在帳本裡原子性地認領一個請求編號，避免重複扣費。
> - **主審**：R2/R3 改動需要的那一次獨立審查，由沒寫過這段程式的模型家族做。
> - **旗標／開關**：伺服器環境變數，用來控制新功能開或關。

---

## 一、改 prompt／AI 品質時

**1. Eric 原則第一條：沒用到的 prompt 規則越刪越好，不要一直堆，也不要鑽研 regex**
- 會看到：契約區塊寫到十幾條後，排在後面的條件式規則完全不會觸發。把配額規則移到最上面，被禁止的行為反而 15 次裡中 15 次。在 system、證據區、逐字稿前各加一句規則重跑，三種位置的差異都還在雜訊範圍內。
- 原因：規則之間會互相稀釋注意力，條件式規則還要模型先判斷條件是否成立，最容易失效。提高某個行為的顯眼度，模型反而更常做它。逐字稿和規則衝突時，模型會選逐字稿。
- 怎麼避免：預設方向是刪。伺服器算得出來的條件就搬進程式，成立時才注入當下唯一相關的一句話。品質問題走結構刀：改模型拿到的輸入、拆成規劃／撰寫／挑選三步，或讓模型輸出結構化標籤，再由伺服器用固定規則決定。判準是「付費用戶會不會原封不動送出這句」。分析的 prompt 本體在 `analyze_prompt/system_prompt.ts` 和 `stream_prompt.ts`。
- 來源：〔vault〕prompt規則堆太多後面幾條會被模型直接忽略；docs/bug-log.md:13-23、1004-1034

**2. 輸出僵硬或空泛時，刪示範句、砍規則才有效**
- 會看到：五句開場白都是「A 但 B」同一個骨架，加「句式要不同」沒有效果。加「每則都要帶東西」之後句子變長，短句比例從 48% 掉到 32%。
- 原因：示範句會被原封不動抄走，打 ❌ 的反例也一樣。模型不會數自己的輸出。正向要求最便宜的達成方式就是多寫字。
- 怎麼避免：合併、砍量，只留單一、具體、能二元判定的規則。刪掉提供內容的示範句，只描述形狀。想同時要 A 和 B，就直接指定同時滿足兩者的內容型態。
- 來源：〔vault〕輸出僵硬時加規則無效刪範例與砍規則才有效；對LLM下正向規則模型會用加字達成

**3. 繁中 regex 沒有詞邊界，用來判語意必然連環誤判**
- 會看到：「看來我這關過了」被判成邀她來家裡。Game Hint（練習室的提示功能）上線後幾乎每次都 503，「這段路」被當成地名、「回她」被當成人名，連修五輪都沒修好。
- 原因：中文沒有詞邊界，N 字規則會在跨詞的地方誤命中。低信心的 regex 握有直接擋掉輸出（fail-closed）的權力，真陽性卻是零。
- 怎麼避免：不要再加語意 regex。語意交給模型輸出結構化標籤，程式只做逐字就能確定的檢查。低信心的候選只做觀測、不擋。`hint_fact_ledger.ts` 不要再往裡加 pattern。
- 來源：〔vault〕繁中正則分類器沒有詞邊界會連環誤判；docs/bug-log.md:217-257

**4. 純函式層用字面判高語意，每輪審查都會被反例打穿**
- 會看到：「不是不想去，下週可以」被判成永久拒絕。開場救星兩段式也曾用 regex 判斷用戶補充的內容是目標還是背景。
- 原因：高語意本來就無法從字面判斷，自己算門檻等於多出一套跟既有狀態機平行的真相。
- 怎麼避免：只消費呼叫端算好的結構化證據（stage、mood、狀態機旗標）。有歧義就不下結論。
- 來源：〔vault〕純函式訊號層硬判高語意會被獨立審查逐條打只消費結構化證據或交給模型

**5. 輸入資料髒了，prompt 攔不住，要在資料層收口**
- 會看到：用戶把自己的目標打進描述對方的「對象備註」，模型就捏造出「你之前說要約見面」。prompt 連修三刀都擋不住。
- 原因：中文意圖句常常沒有主詞，第三人稱欄位開放自由文字後，模型把整欄都當成對方的事實。
- 怎麼避免：這個欄位已經改成主詞明確的選項 chips。改欄位時要 grep 所有入口。日期、照片內容這類模型答不出來的硬事實，要由伺服器注入欄位，不能只寫「絕不捏造」。
- 來源：〔vault〕餵LLM的第三人稱欄位開自由文字會主詞錯位且prompt攔不完；docs/bug-log.md:26-60

**6. `stream_prompt.ts` 裡「伺服器會退回」是刻意保留的假威嚇**
- 會看到：選中的風格接滿 4/4 顆球（對方訊息裡該回應的點），其他風格只接 3/4，而且各自挑不同的球。telemetry 只記數量，看不出問題。
- 原因：伺服器其實只記 log、不擋也不重試，模型只服從字面列出的違規線。
- 怎麼避免：約第 227 行的註解寫明這句刻意保留，而且不可據此加回硬擋。要刪或改這句必須先跑黑箱重驗，不要順手刪，也不要把威嚇清單越列越長。telemetry 要記球的編號，用集合驗證。
- 來源：〔vault〕LLM對prompt威嚇只服從到字面違規線；stream_prompt.ts:227

**7. 往共用守門清單加詞，就是改所有用戶的 production 行為**
- 會看到：prompt 沒改、golden 全綠，沒開旗標的用戶卻開始被多攔一種正常句子。
- 原因：清單是所有路徑共用的。「零改動」的證明只涵蓋 prompt，沒涵蓋後處理和重試條件。
- 怎麼避免：優先刪沒用到的清單項目。真的需要時改成呼叫端選擇性帶入（參考 `visible_text_guard.ts` 的 `extraChineseLabels`）。宣稱零改動時，prompt、後處理守門、重試條件三層都要涵蓋。
- 來源：〔vault〕守門清單全域新增就是production行為改動要opt-in

**8. 守門會安靜丟掉品質最好的候選**
- 會看到：用戶永遠拿得到結果，但被擋下的其實是教科書級的句子，送出去的是備援模型比較平的版本。
- 原因：只看錯誤碼，看不到被丟掉的內容，離線重放的重試邊界也和 production 不一致。
- 怎麼避免：重放腳本要 dump 被擋下的原始輸出，重試邊界照抄 production。先看被擋的是什麼，再決定要不要放寬。
- 來源：〔vault〕LLM守門會安靜殺掉品質最好的候選

**9. JSON 固定形態的手誤已經由伺服器窄修補，不要改用 prompt 規則**
- 會看到：約 1/6 的發散計畫（分析先規劃各回覆方向的那段 JSON）出現 `"sourceIndex1"`，或把 method 填成 exaggeration。加「絕不寫…」反而變出新形態。
- 原因：這是解碼層的重複結構手誤，加上兩套值域重疊，不是語意誤解。
- 怎麼避免：`divergence_contract.ts` 已經有精確形態的修補和映射表，不要拿掉，也不要把「絕不寫」規則加回 prompt。新 enum 第一版就讓值域不相交。
- 來源：〔vault〕模型在重複結構的第三筆會出固定形態的JSON-key手誤只對精確形態repair-first

**10. prompt 測試逐句鏡像措辭，刪規則時會打紅一大片**
- 會看到：`index_test.ts` 約有 530 處 `source.includes` 斷言，其中約 300 處逐字照抄分析 prompt，`baseline_contract_test.ts` 還鎖住 rendered bytes。
- 原因：測試把措辭當成契約。
- 怎麼避免：只保留契約級斷言（欄位名、錯誤碼、安全與法遵措辭），其他改成改寫後也還在的語意錨點。不要為了讓測試變綠，就把斷言改成現在的樣子。`baseline_fixtures.json` 只在已核准的規格變更時才更新。
- 來源：〔vault〕prompt測試寫成逐句鏡像會讓prompt重構成本爆炸

**11. 其他 prompt 小坑**
- 兩段指令方向相反時，模型會含糊帶過而不是報錯：優先刪掉其中一段。來源：〔vault〕prompt裡兩段指令互相矛盾時小模型會含糊其辭而不是報錯
- 自創的分隔符號（例如「｜」）會被模型當成輸出格式照抄：改用「」或「第 N 則：」這類明說的標記。來源：〔vault〕LLM輸出的格式標記會被模型當成內容抄走
- 偶爾夾雜的俄文等外語由 `post_process.ts` 整個子句刪掉，不要在 prompt 加「不要輸出外語」。來源：〔vault〕LLM中文輸出偶發外語token洩漏清洗要丟整子句
- 用同一份 prompt 重試修不了服從率，第二發要注入具體的違規原因。候選先放在區域變數，守門全過才寫回外層。來源：〔vault〕結構後檢查用同一份prompt重試修不了模型服從率要注入針對性改寫指令或改模板
- 如果沒有任何好輸出能通過某個守門，就降級成偏好。把白名單改成黑名單時，parse 之後的守門也要一起改。來源：〔vault〕守門把合格輸出打回時該降級成偏好而不是否決權
- prompt、provider schema、parser 的 enum 共用同一個 helper。來源：docs/bug-log.md:112-124
- LLM 分類器的判準寫成「明顯 X」，會全部判成 false。先 grep prompt 組裝函式，確認模型真的看得到那個欄位。來源：〔vault〕LLM分類器判準用明顯X讓模型自己下定義會全判false要拆成可核對的結構條件

---

## 二、量品質、跑評測、花 AI 錢時

**1. 付費黑箱或真的打 Anthropic API 之前，先報次數和估價，等 Eric 明確說「跑」**
- 會看到：為了驗 prompt 直接跑黑箱，燒掉預期外的費用。
- 原因：本機有 key 只是方便，不代表已經授權。前一句話聽起來像授權也不算。
- 怎麼避免：先乾跑，列出次數、估價和 `--max-calls`／`--budget-usd` 上限。單元測試一律加 `--deny-net`。
- 來源：AGENTS.md；Eric 的 agent memory（paid-generation-needs-explicit-go）

**2. 沒先量過指標本身的雜訊帶，「有降」全是誤差**
- 會看到：連改五晚，每晚都「小幅改善」。同一份 prompt 連跑六批才發現指標自己就會晃 ±5～6。
- 原因：量雜訊帶要花 n 倍的錢，所以總是被跳過。temperature 0 也不保證結果固定。
- 怎麼避免：A/B 之前，同條件連跑三批以上，把極差寫進 harness 檔頭。效果沒有明顯大於極差，就當沒量到。
- 來源：〔vault〕指標沒量過自己的雜訊帶就不能拿它比大小

**3. 指標說變好、Eric 看了說變差時，採信肉眼**
- 會看到：各項指標全面改善，Eric 的判斷卻是「其實都蠻差的」。
- 原因：指標量的是平均，人看的是一組裡最差的那一句。字面計數也不等於語意通過。
- 怎麼避免：逐筆讀輸出，結論附上分母。指標和肉眼對不上時，把原因當成下一輪的題目。
- 來源：〔vault〕指標有降但肉眼判定更差代表優化落在無感帶寬

**4. 評測工具用的模型或膠水程式跟生產不同，整串結論作廢**
- 會看到：跑了十批優化，換回生產模型 claude-sonnet-5 重跑，待修的問題根本不存在。
- 原因：harness 寫死舊模型名稱，模擬器手抄的 production 邏輯沒有跟著更新。
- 怎麼避免：直接 import production 的函式和呼叫器，request body 要逐位元組相同。驗證結果跟修改前一模一樣時，先懷疑量測工具。
- 來源：〔vault〕prompt評測跑在非生產模型上會讓整串優化結論作廢

**5. 改分析 prompt 時，Sonnet 5 和 5.5 兩個模型都要驗**
- 會看到：只用 5.5 驗了新 prompt，production 的 Sonnet 5 行為卻變了。
- 原因：開關 `ANALYZE_STREAM_SONNET_55` 預設關閉，兩個模型共用同一份 prompt。
- 怎麼避免：兩個模型都要量。設定這個 secret 每次都要 Eric 核准。
- 來源：docs/decisions.md ADR #49；analyze_stream_handler.ts:85-96

**6. 評測方法的小坑**
- LLM 評審的判準如果寫成「有沒有提到 X」，而合格輸出本來就會提到 X，判準就永遠成立。改成增量式的判準。來源：〔vault〕LLM評測員的判準寫成有沒有提到X在X必然出現時會恆真
- 先離線確認指令有進 prompt、觸發了幾場，再看模型服從幾成。來源：〔vault〕量prompt指令效果前先離線重建plan確認指令有進prompt並觸發幾場再看服從率
- 一次只改一個變因，會讓互相依賴的兩個改動單獨測起來都無效，例如「刪示範句」和「補替代方向」。來源：〔vault〕一次只改一個變因會讓互為條件的兩個改動都測起來無效
- 中文 token 的本機估算會低估一到兩成，`stop_reason` 是 max_tokens 一律當失敗、不快取。來源：〔vault〕Anthropic中文語料本機token估算會低估一到兩成…

---

## 三、對話分析／開場救星／新話題的執行期

**1. `callClaudeWithFallback` 的 maxRetries 是「嘗試次數」，傳 0 等於一次都不呼叫**
- 會看到：注入假模型的單元測試全綠，production 卻空轉到 `DEADLINE_EXCEEDED`，而且照樣扣額度。新話題的格式修復曾經這樣壞了兩個多月。
- 原因：`fallback.ts:224` 的迴圈條件是 `attempt <= maxRetries`。注入假模型的測試完全繞過這段。
- 怎麼避免：只試一次就明寫 `maxRetries: 1`，不想換模型就另設 `allowModelFallback: false`。每條新的呼叫路徑至少留一個 stub `globalThis.fetch` 的測試，斷言恰好送出 N 次請求。
- 來源：〔vault〕callClaudeWithFallback的maxRetries是嘗試次數傳0會同步空轉到截止零次呼叫

**2. 換 Sonnet 5.5 不能只改模型名稱**
- 會看到：回 HTTP 400；或者 HTTP 200 但 `stop_reason` 是 refusal，正常的戀愛內容被擋；或者思考 token 吃光 max_tokens，JSON 被截斷。
- 原因：5.5 移除了 disabled thinking 和強制工具，新增了安全過濾，而且思考 token 也算在 max_tokens 裡。
- 怎麼避免：thinking、temperature 和 max_tokens 的餘裕只交給 `_shared/model_request_params.ts` 決定，`fallback.ts` 和 `streaming_fallback.ts` 兩條路徑一起檢查。refusal 和截斷都當錯誤處理。
- 來源：〔vault〕Sonnet5.5不能直接換名字thinking-disabled和強制工具會回400且新安全過濾會擋正常內容

**3. 輸出 token 上限不夠已經發生過三次**
- 會看到：付費用戶的五種風格只出了一種，或者約 42 秒時顯示「串流中斷」。開場救星同一張圖偶發 502。
- 原因：schema 或風格變多時，上限沒有跟著調，而短對話的 smoke 測試碰不到上限。
- 怎麼避免：預算看 `stream_budget.ts`，加了輸出區塊就要加預算。要用接近 production 的長對話驗證 `analysis.done` 有出現、token 留有餘量。
- 來源：docs/bug-log.md:140-148、671-747、807-829

**4. 串流的「模型完成」「結果入庫」「client 收到 done」是三個獨立狀態**
- 會看到：後端已經完成也扣了額度，App 卻顯示「無法再重試」，斷線後還可能並行生成第二次。
- 原因：client 把傳輸中斷當成最終失敗，retry 不回放已經存好的結果，也沒有取得進行中的租約。
- 怎麼避免：以 analysisRunId 和資料庫帳本為準，有 `final_result_json` 就優先回放。retry 要原子性地取得租約。這一區屬於 R2。
- 來源：docs/bug-log.md:78-90、647-669

**5. 缺少必備風格時不能當成功存檔，也不能外洩付費風格**
- 會看到：付費用戶只看到一張推薦卡，或 Free 用戶在串流途中看到付費風格。
- 原因：送出 done 之前沒有檢查方案應有的風格是否到齊。
- 怎麼避免：用 `reframer.ts` 的 `findMissingRequiredReplyStyles` 檢查，缺了就回 `STREAM_INCOMPLETE_REPLY_OPTIONS`。
- 來源：docs/bug-log.md:721-747

**6. 輸出數量上限有三處副本**
- 會看到：上限從 3 放寬到 5，App 還是只顯示 3 段，沒有任何錯誤。
- 原因：prompt、`post_process.ts`、`analysis_models.dart` 各寫了一份。
- 怎麼避免：三處一起 grep，每一處都要有鎖住新上限的測試。
- 來源：docs/bug-log.md:336-345

**7. 「1.8 倍」是節奏參考，不是字數上限；「併」球不該多拆一段**
- 會看到：回覆被最後一句短句卡住長度，修好後又逐條點名，讀起來像客服。
- 原因：1.8 倍被寫成硬上限，而段數下限把「併」也算成獨立的一顆球。
- 怎麼避免：連同 `ball_inventory.ts` 和段數下限一起查（現在只有「接」會增加下限）。注意 `coach_action_policy.dart` 仍寫著「控制在 1.8 倍內」。
- 來源：docs/bug-log.md:126-138

**8. 失敗要用旗標宣告，不能叫模型「原樣返回」**
- 會看到：草稿潤飾遇到亂碼時，回傳「看不懂這段草稿…」被當成正常結果顯示，還扣了額度。
- 原因：prompt 的要求互相矛盾，伺服器又靠欄位內容判斷失敗。
- 怎麼避免：照 `optimize_message_prompt.ts` 的 `unusable` 旗標模式做：失敗時不寫帳、不扣費、回專屬錯誤碼。
- 來源：〔vault〕叫模型原樣返回它會把說明塞進資料欄要用旗標宣告失敗

**9. 各模式用各自的窄 prompt，只有服務中斷才降級**
- 會看到：草稿潤飾跑不出結果；有些路徑仍在用舊模型。
- 原因：當時潤飾共用了完整分析的 `SYSTEM_PROMPT`，模型路由也散落在各個分支。
- 怎麼避免：每種模式有自己的 prompt、JSON 和預算。只有逾時、429、5xx 才降級到備援模型。沒有持久化的 requestId 就不自動重送。client 的逾時要大於 server 的逾時。
- 來源：docs/bug-log.md:150-162、600-623

**10. 付費刷新被後來補上的「我說」擋住**
- 會看到：升級後重新分析，仍然顯示「先不預測她可能怎麼回」。
- 原因：pending-outgoing guard 在權限檢查之前就提早返回。
- 怎麼避免：依 `lastAnalyzedMessageCount` 只重跑已分析過的那段。改 guard 時要列出所有共用 `_runAnalysis` 的入口。
- 來源：docs/bug-log.md:323-334

**11. 開場救星與新話題**
- 用字面重疊判斷「有沒有採用素材」，會把語意目標逼成字面。要把「要不要求採用」和「什麼算採用證據」分開處理。來源：〔vault〕字面採用檢查會把語意目標逼成字面放寬時要把要求與證據分開
- 新增可選卡型時，要同步刪掉衝突的全域規則。可選卡寫不出來只拿掉那一張，不讓整組 502。來源：〔vault〕新增可選卡型的規則跟全域規則衝突模型會留空當成必交欄位就整組失敗
- 付費結果先存進加密 Hive，不要自動恢復全域結果，已有結果時鎖住生成鈕。來源：docs/bug-log.md:404-427、775-912
- 真機驗收 prompt 改動時要按重新生成，舊草稿不會重新計算。來源：Eric 的 agent memory（opener-confidence-tone）
- 截圖的單張、總量、請求本體三種上限要一起算，並把 base64 膨脹算進去。來源：docs/bug-log.md:1568-1610
- client 不要用字數比例觸發教練判斷（`coach_action_policy.dart`）。來源：docs/bug-log.md:751-773、1036-1065

---

## 四、扣費、額度、付費

**1. 功能開關要擋在原子 claim 之後，拒絕時不釋放**
- 會看到：開關翻轉時，系統說「本次不扣額度」，其實已經扣了，或者還在進行中的原請求之後照常結算。
- 原因：唯讀查帳擋不住進行中的 claim，release 又會把請求編號還回去。
- 怎麼避免：照抄 `new_topic_handler.ts:396-415` 和 `opener_flow_handler.ts:400-405` 的寫法：claim 成功後才查開關，回 422 且不 release。
- 來源：〔vault〕功能開關擋在原子claim之前會讓本次不扣額度在開關翻轉時失真要先claim再查開關且不釋放

**2. 失敗不扣費，也不能偽裝成付費牆**
- 會看到：罐頭萬用句被當成成功結果並扣了一次，或者額度還沒用完就跳出付費牆。
- 原因：所有失敗都被導進同一條成功或付費牆的分支。
- 怎麼避免：只有額度真的用完（429）才導向付費牆。格式失敗、模型上限、逾時都回可重試的錯誤，不寫快照、不扣費。錯誤文案在來源就中文化，開付費牆要 await 它關閉。
- 來源：AGENTS.md Critical Gotchas；docs/bug-log.md:259-279、347-402

**3. 方案權限要在 server 回應邊界過濾**
- 會看到：直接呼叫 API 時，Free 用戶的回應裡帶著付費風格。
- 原因：權限只在 Flutter 端過濾。
- 怎麼避免：扣費前依 allowedFeatures 過濾。client 的讀取和交接一律走 `visibleForAccess`／`bestOpenerTextForAccess`。方案不確定時一律當 Free。
- 來源：docs/bug-log.md:375-449

**4. 付費狀態對不上時逐層比對，不要直接改程式**
- 會看到：App 顯示 Essential，分析卻只回一種風格。
- 原因：曾經是 production 少了 `REVENUECAT_IOS_API_KEY`，client 本身沒有錯。
- 怎麼避免：依序比對 UI、RevenueCat 身分與權益、subscriptions 資料列、請求內容、Edge secret 與部署版本、webhook。
- 來源：docs/operational-learnings.md:5-65

**5. 跨週期的額度加成不能在 Edge 先讀後扣**
- 會看到：一次性的贈送額度，被橫跨台北中午 12:00 重置點的兩個請求各用了一次。
- 原因：Edge 層先讀再扣，兩個週期的請求各自讀到「尚未使用」。
- 怎麼避免：判定和消耗放在同一個資料庫交易裡，用 row lock 排隊，冪等重放檢查放在任何判定之前。
- 來源：〔vault〕額度加成在Edge先讀後傳會跨重置窗雙花

---

## 五、資料庫與 migration

**1. 永遠不跑 `supabase db push`，production migration 交給 Eric**
- 會看到：歷史上漂移、版本重複的 migration 被一起推上 production。
- 原因：migration 帳本本來就有歷史落差，`scripts/setup-supabase.sh:41` 裡就是被禁止的 push。
- 怎麼避免：PR 合併前 migration 保持待上狀態，由 Eric 依 `docs/shared-agent-rules.md` 的 targeted 流程處理。本機驗證用拋棄式的 initdb 加 `psql -1`。
- 來源：AGENTS.md；docs/shared-agent-rules.md

**2. migration 要先套好、驗證完，才能推依賴它的 Edge 程式**
- 會看到：Edge 新版已經上線，資料表或 RPC 卻還不存在。
- 原因：推 main 會立刻部署 Edge，不會等 migration。
- 怎麼避免：migration 先上線並驗證，而且要對目前已部署的版本向後相容。
- 來源：docs/shared-agent-rules.md

**3. JSONB 欄位整包覆寫時，旗標關閉就省略 key 等於刪掉既有狀態**
- 會看到：重新打開旗標後，先前累積的狀態全部消失。
- 原因：RPC 用 `EXCLUDED` 整包覆寫，不是合併。
- 怎麼避免：先確認 RPC 是覆寫還是合併，旗標關閉時把讀到的既有值原樣帶回。
- 來源：〔vault〕JSONB整包覆寫欄位加旗標key時關旗標必須原樣帶回否則等於清空

---

## 六、Edge 部署、CI、測試

**1. CI 的 Deno 測試是白名單，analyze-chat 82 支裡有 68 支不在 CI**
- 會看到：PR CI 全綠，開場救星、新話題、計費相關的測試其實已經壞了。
- 原因：`flutter-ci.yml` 逐檔列出要跑的測試。
- 怎麼避免：從 repo 根目錄跑 `deno test -A --deny-net supabase/functions/analyze-chat`，新測試加進白名單。註解不要寫在 `run: >-` 清單裡，否則 `#` 之後的測試會全部被吃掉。
- 來源：.github/workflows/flutter-ci.yml:49-50

**2. 本機驗證範圍比 CI gate 窄，真回歸會直接推上 main**
- 會看到：子目錄測試全綠，Build & Distribute 卻是紅的。
- 原因：行為級測試放在 `test/widget/features/`。
- 怎麼避免：推之前跑 `flutter analyze --no-fatal-infos` 和完整的 `flutter test --concurrency=1`（本機約 3.5 分鐘）。
- 來源：〔vault〕驗證範圍窄於CI-gate會把真回歸直接推上main

**3. 「輸出不變」或「旗標關閉零改動」拿新碼比新碼是假綠**
- 會看到：回歸鎖全綠，審查者卻連續三輪各抓到一處關閉時的洩漏。
- 原因：兩邊都走新程式碼，會一起漂移；prompt golden 只涵蓋模型訊息、Response bytes、RPC、log 四面裡的一面。
- 怎麼避免：golden 從舊 commit 產生（`baseline_contract_test.ts` 就是這種鎖）。旗標類改動參考 `agency_flag_off_equivalence_test.ts`，跑五種旗標狀態。
- 來源：〔vault〕回歸鎖測試比較新碼自己跟自己是假綠

**4. Deno 測試的執行細節**
- 串流測試要先替換 `globalThis.fetch`，再動態 import handler，因為 `streaming_fallback.ts:71` 在模組載入時就抓住了 fetch。
- 從 repo 根目錄跑並帶 `-A`。`--filter` 遇到全形字要寫成 `/片段/`，並確認測試數不是 0。
- 用 tail 精簡輸出前要先 `set -o pipefail`，否則失敗會被偽裝成成功。
- 來源：streaming_fallback.ts:69-72；〔vault〕shell管線接tail未開pipefail會把測試失敗偽裝成成功

**5. 合進 main 等於 production 發布**
- 會看到：以為只是給 TestFlight 內測，Web 版和 Edge 卻已經對所有用戶上線。
- 原因：推 main 會同時跑 distribute、deploy-edge-function、deploy-web（vercel --prod），部署 workflow 還會重新部署所有 generic 函式。
- 怎麼避免：推之前比對所有沒審過的 Edge 變更。不要改 `--no-verify-jwt` 旗標，也不要手動部署。agent 不觸發 `release.yml`。
- 來源：AGENTS.md；.github/workflows/deploy-edge-function.yml:13-60

**6. 綠燈不等於線上已經換版**
- 會看到：部署 run 全綠，production 卻還是舊行為；真機上少了一整批功能。
- 原因：CLI 印出 Deployed，但 version 沒變；release 是從舊的 main 建置的。
- 怎麼避免：查 Management API 的 functions version，以及設定頁顯示的 `GIT_SHA`。版本沒換時，是否重派由 Eric 決定。
- 來源：〔vault〕Supabase推主線觸發的Edge部署印Deployed且run綠但版本沒換要查functions-API的version；docs/bug-log.md:164-176

**7. CI 工具鏈與相容性**
- 所有 workflow 都釘在 Flutter 3.47.0，本機要對齊。foundation 層的符號要明確 import `package:flutter/foundation.dart`。來源：〔vault〕CI卡在GenerateCode不動是Flutter換版撞舊analyzer而非程式問題
- 舊版 App 還在用戶手上，optional 欄位太長時 server 要截斷，不要回 400。來源：docs/bug-log.md:1428-1463

---

## 七、Flutter／iOS／App 狀態

**1. 新 worktree 要先跑 `flutter pub get` 和 `dart run build_runner build`**
- 會看到：一片找不到 `.g.dart` 的錯誤。
- 原因：產生的程式碼不進 git。
- 怎麼避免：先跑這兩步，`supabase/.env` 自己準備，不要 commit。
- 來源：Eric 的 agent memory（testflight-build-number-mapping）

**2. autoDispose AsyncNotifier 的 build 寫成 async，第一幀會被誤讀成「動作進行中」**
- 會看到：什麼都還沒送出，就閃出「正在送出問題」。
- 原因：async build 的第一幀一定是 loading。
- 怎麼避免：底層讀取是同步的，就改成同步的 build（參考 `coach_chat_providers.dart:172`）。「動作進行中」不要共用 `isLoading`。測試要在單幀 `pump()` 之後斷言。做串流 UX 時特別注意。
- 來源：〔vault〕autoDispose AsyncNotifier掛async build首幀loading會被UI誤讀成動作進行中

**3. 存完對話要 invalidate `conversationProvider(id)`**
- 會看到：補了「她說」再按分析，結果沒有反映新訊息。
- 原因：當時只 invalidate 了列表 provider。
- 怎麼避免：新增寫入入口時，一律走 `conversation_write_controller.dart`。
- 來源：docs/bug-log.md:1104-1132

**4. 轉圈或不可關閉的 dialog 底下 await 網路，一定要設 timeout**
- 會看到：畫面永遠卡住。Apple 曾以 2.1(b) 拒審。
- 原因：只有 try/catch，網路卡住時沒有出口。
- 怎麼避免：加 `.timeout()`，參考 `paywall_screen.dart` 的 `_purchaseTimeout`。
- 來源：docs/bug-log.md:281-289

**5. 模型的自由文字、raw JSON、英文 key 不能直接顯示**
- 會看到：畫面上出現 `{"subtext":...}`，或標籤顯示 recommended。
- 原因：client 直接把模型輸出顯示出來。
- 怎麼避免：標題用寫死的文案，key 在 client 對照成中文，未知內容寧可不顯示。
- 來源：docs/bug-log.md:178-190、693-719

**6. 其他狀態坑**
- 「第 N 次」這類顯示，要讀判定端用的同一個值。來源：〔vault〕顯示層的次數計數跟判定層不同源會標出假序數
- 權限只留一個真相源，不要用本機副本判斷。來源：〔vault〕本機副本當解鎖真相源會開出必敗UI且刪帳號清不乾淨
- 用普通 Provider 包 store 再同步 `.read()`，跨頁回來會顯示舊值，要改成會發出變更事件的 StreamProvider。來源：〔vault〕Riverpod用plain-Provider包同步read會跨頁stale
- 同一位置重掛 ProviderScope 要給 `UniqueKey()`。來源：〔vault〕Flutter測試同位置ProviderScope重掛會沿用第一次overrides
- lazy ListView 裡會改變自身高度的狀態要上提，測試用 400x800 的小畫面。來源：docs/bug-log.md:96-110
- 從對象頁建立的資料要帶入 partnerId。來源：docs/bug-log.md:1362-1393
- 不要對文字做 Opacity 動畫，不要無限 repeat。寫 Hive 的步驟包在 `runAsync` 裡。圓角只能用 `slop_scan.dart` 白名單裡的值。來源：〔vault〕動畫修一半與發版代跑的三個假陰性；test/lint/slop_scan.dart

---

## 八、協作與交付流程

**1. 大部分踩坑筆記在 Eric 的 vault，Bruce 的 agent 看不到**
- 會看到：文件寫「看 Dev Brain…」，卻找不到檔案，只好再踩一次。
- 原因：vault 和 agent memory 都只在 Eric 的機器上。
- 怎麼避免：以 repo 的 AGENTS.md、`docs/shared-agent-rules.md`、`docs/bug-log.md`、`docs/decisions.md` 為準，需要 vault 全文時請 Eric 貼。
- 來源：AGENTS.md

**2. analyze-chat、Opener、額度、Edge schema、AI 成本都屬於 R2/R3，需要別家模型主審**
- 會看到：自己的 AI 審過、CI 也綠了，卻被退回補主審。
- 原因：同一家族的模型審查只算預審。
- 怎麼避免：主審結論用 APPROVED／APPROVED_WITH_RISK／BLOCKED。只有 Eric 能送出正式 Approve 並合併。審查、合併、建置、真機驗收分開回報。
- 來源：AGENTS.md

**3. `deno fmt` 只點名自己改的檔案**
- 會看到：commit 混進幾十個無關檔案的排版噪音，曾經一次重排了 49 個檔案。
- 原因：repo 有大量歷史檔案沒有照 fmt 排版。
- 怎麼避免：fmt、lint、`git add` 都列出明確的檔名，不要用 `-A`。
- 來源：〔vault〕deno fmt跑整個目錄後git add -A會把無關檔案掃進commit

**4. 疊層 PR 改 base 不會觸發 CI**
- 會看到：子 PR 看起來是綠的，其實沒跑新的 CI，或合併後內容多出一段重複。
- 原因：改 base 屬於 edited 事件，CI 不聽這個事件。
- 怎麼避免：把 main 合進子分支（不要強推），並核對合併後相對 main 的改動等於子 PR 原本的改動。
- 來源：.github/workflows/flutter-ci.yml:13-15

**5. 不要順手改範圍外的既有設計**
- 會看到：真機上顏色跑掉、出現灰黑字。
- 原因：agent 傾向重寫共用元件，看 diff 審查不容易察覺視覺差異。
- 怎麼避免：沿用 `brand_kit.dart`，PR 說明列出所有視覺變動。
- 來源：Eric 的 agent memory（ebook-copy-project-review-flow）

**6. AGENTS.md 改完要開新 session**
- 會看到：規則沒有生效。
- 原因：規則檔只在 session 啟動時載入。
- 怎麼避免：pull 到規則變更後，開新的 Claude Code session 或新的 Codex task。
- 來源：〔vault〕CLAUDE.md規則只在session啟動時載入

**7. TestFlight 用 email 綁定的內部測試者身份**
- 會看到：卡片變灰，顯示「developer removed you」。
- 原因：用 public link 時是匿名身份，後台那列被刪就等於把 Bruce 移除。
- 怎麼避免：請 Eric 在 Internal Testing 群組把 Bruce 移除再加回，過程中不要刪掉手機上的 App。
- 來源：〔vault〕TestFlight誤刪publiclink匿名測試者會鎖死夥伴且同連結重加會卡住

---

另外省略了 7 條低相關的坑：Supabase log 查詢回 0 筆、prompt cache 最低長度門檻、讀本機產物的測試在 CI 失敗、release 綠燈不等於 TestFlight 能裝、匿名登入撞上 handle_new_user 觸發器、disabled 按鈕對比太低、AppBar 標題字體。