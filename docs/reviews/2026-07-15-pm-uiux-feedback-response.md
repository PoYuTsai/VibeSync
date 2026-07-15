# 回覆：PM「VibeSync UI/UX 實測優化建議清單」（2026/7/14 實測）

> 對 PM 七項建議的逐項回覆。每項含：現況核實（對照程式碼）、採納度與優化方向、風險註記。
> 文末集中「向 PM 的提問清單」。本文件為評估回覆，尚未動任何產品程式碼。

## 總覽

| # | PM 建議 | 回覆結論 |
|---|---------|----------|
| 1 | 健康分數飆升過快 | **觀察成立**：全鏈路確實無樣本量降權。採納，先加「初步評估」提示（低風險），降權分數列中期評估 |
| 2 | 教練跑很久只回一句 | **等待問題成立**（coach 無 streaming）；「只回一句」是刻意設計非 bug，需先釐清是哪個介面再談 prompt |
| 3 | 空狀態頁資訊過載 | **大方向同意**；此頁已重構過一輪（雷達圖已摺疊），但大圓圈與重複 CTA 仍在。PM 的 React demo 不在 repo，需索取 |
| 4 | 教練文案落落長 | **採納**：標題全是前端硬寫、欄位本就分離，「一句結論＋展開」純前端可做，低風險 |
| 5 | 加入 vs 另存差異不明 | **觀察成立但成因不同**：兩者其實都有說明文案，只是一次只顯示選中那個。採納同時顯示 |
| 6 | 截圖單張上傳＋等待久 | **兩個獨立問題**：單張是 picker 用了單選 API（quick win 可修）；等待久受「圖片強制 Sonnet」品質決策約束，先做進度提示 |
| 7 | 追問／調整語氣提案 | **高度可行**：coach-chat 已有多輪 session 基礎可直接承載；需 PM 拍板扣費政策與快捷選項 |

---

## 1. 對話健康分數飆升過快（高）

### 現況核實

PM 的質疑成立。分數的產生鏈路是：

- 分數是 AI 模型在 `analyze-chat` Edge Function 直接輸出的 `enthusiasm.score`（`supabase/functions/analyze-chat/index.ts:1743`），prompt 只有質性判讀指引（回覆長度、emoji、主動提問等，`index.ts:1520-1525`），沒有量化公式。
- **全鏈路沒有任何「訊息量／輪數」的降權或信心度機制**。prompt 裡的 `confidence` 欄位只作用在 coachActionHint／quick reply，不影響分數。
- 「升溫中」是 client 端純門檻貼標：61–80 分 →「升溫中」（`lib/features/partner/presentation/widgets/partner_heat_hero_card.dart:24-40`，門檻常數 `lib/core/constants/app_constants.dart:9-11`）。
- 所以「4 輪 7 則就 65 分升溫中」＝ AI 直接給了 65＋65 落在 61–80 分桶，中間沒有樣本量守門。

### 採納度與優化方向

採納，建議分兩段：

1. **短期（低風險，建議先做）**：PM 提的「初步評估，訊息量增加後會更準確」提示文字。輪數／訊息數 client 端已現成（`PartnerAggregateView.totalRounds/totalMessages`，`lib/features/partner/domain/extensions/partner_aggregates.dart:61-64`），只需改兩張分數卡（`partner_heat_hero_card.dart`、`lib/shared/widgets/score_hero_card.dart`）與呼叫端傳參，並更新對應 widget 契約測試。
2. **中期（高風險，另案）**：樣本不足時對分數做決定性降權。建議走 client 端（`partner_aggregates.dart:70` 算 `latestHeat` 處向中性收斂），不走 prompt——AI 對量化指引遵從度不穩。此改動影響核心賣點數字呈現，屬高風險區，實作時需 Codex 審。

### 風險註記

分數行為屬「AI prompt／分析品質」高風險區。提示文字改法不動分數本身，風險最低，建議先出。

---

## 2. AI 教練跑很久卻只回一句話（高）

### 現況核實

這項需要先釐清一個介面歧義——畫面上有**兩個不同來源**的「一句話」：

- **(a) 分析頁的「AI 推薦回覆」卡**（`final_recommendation_card.dart`）：來自 analyze-chat 的 `recommendation.content`，**本來就設計成單一推薦句**＋推薦理由。PM 例句「妳說去哪摸？我建議先從沙發開始」語感上比較像這條。
- **(b) Coach 1:1 的回覆卡**：實際回傳是整張卡（360 字 answer＋卡點＋下一步＋教練判斷等），但 UI 把單句 `suggestedLine` 放在最顯眼的白底 bubble，造成「等半天只給一句」的體感。`suggestedLine` 短是刻意設計：prompt 要求「收斂到一個最小下一步、不要輸出選項清單」（`supabase/functions/coach-chat/prompts.ts:52-60`）＋ schema 160 字上限＋「1.8x 黃金法則」（字數不超過對方最後一句的 1.8 倍）——對方句子短，建議句就會被壓短。

「等很久」的根因明確且成立：

- coach-chat **完全沒有 streaming**：單次阻塞式生成（`maxTokens:1200, timeoutMs:60s`），失敗最多重試 3 次（`supabase/functions/coach-chat/generation.ts:84-93`），最壞情況等待數分鐘。
- 免費層走 Haiku、付費層走 Sonnet（`generation.ts:67-69`）。免費層品質天花板較低，容易產出乾句。
- 對照：analyze-chat 已是 full streaming（有整套 stream 基建＋前端進度文案），coach 流程是目前唯一「一次等到底＋不確定轉圈」的主流程。

### 採納度與優化方向

1. **等待體感（採納 PM 的「漸進式提示」）**：短期把 analyze 流程既有的分段步驟元件復用到 coach loading——`FullAnalysisPlaceholder`（分段骨架＋步驟標籤）與 `StreamingAnalysisLoader`（輪播文案），皆在 `lib/features/analysis/presentation/widgets/streaming_analysis_loading_widgets.dart`。目前 coach 只有一顆轉圈＋固定文案（`coach_chat_card.dart:1119-1177`）。中期評估 coach-chat 真 streaming（另案，動 Edge Function）。
2. **回覆品質**：prompt 屬高風險區，且「一句話」有可能是免費層 Haiku 的品質問題而非 prompt 問題。**先向 PM 確認介面與帳號層級**（見提問清單），確認後再決定是否調 prompt。若確認是 (b) Coach 1:1，可考慮的低風險改法是 UI 層面調整——讓整張卡的價值（卡點分析、下一步）更被看見，而不是只凸顯單句。

### 風險註記

coach prompt 改動屬「AI prompt 影響回覆品質」高風險區，需 Codex 審。loading UX 改動純前端、低風險。

---

## 3. 角色卡建立完成後頁面資訊量過大（高）

### 現況核實

該頁是 `lib/features/partner/presentation/screens/partner_detail_screen.dart`。**這頁其實已做過一輪 command-center 重構**（程式碼標記 "Spec 6D command-center-first"），PM 提的方向已部分落地、部分仍在：

- ✅ 詳細特質雷達圖**已預設摺疊**（`_PartnerExpandableDetailSection`，`:1162-1252`）。
- ❌ 「待分析」大圓圈仍在：`PartnerHeatHeroCard` 在 heat==null 時照樣渲染 80px 發光 orb＋大字「--／待分析」（`partner_heat_hero_card.dart:24-40, :115-156`）。
- ❌ 「+ 新增對話」CTA 確實重複：FAB（`partner_detail_screen.dart:308-328`）、空狀態內文（`:342`）、分析封存頁 FAB（`partner_analysis_archive_screen.dart:157`）。**注意**：這組字串被 ADR-15 vocabulary contract 鎖定（程式碼註解明示 copy 需 verbatim），並有 snapshot 測試（`test/widget/features/copy_sweep_snapshot_test.dart`）守著，合併 CTA 需連動契約與測試。
- ❌ 無「先練習」（練習室）入口。
- 作戰板鎖定狀態有文案「完成一次對話分析，解鎖作戰板」（`partner_mind_map_entry_card.dart:91`），但視覺上是否「明確標示鎖定」可再強化。

### 採納度與優化方向

同意沿用 PM 的設計方向（合併重複 CTA、移除零資訊大圓圈、鎖定狀態卡片化、加「先練習」入口）。但有一個 blocker：**PM 提到的 Before/After Demo（React 元件）不在 repo 內**——搜遍 `*.tsx/*.jsx/*.html` 與 `docs/` 皆無此檔。需請 PM 提供檔案或設計稿，拿到後另開實作案（含 ADR-15 契約與 copy snapshot 測試的同步更新）。

### 風險註記

純 UI 改版、不碰 AI／quota，但字串契約與測試連動範圍不小，建議拿到 demo 後一次規劃、避免多輪返工。

---

## 4. 分析結果／教練建議文案落落長（中）

### 現況核實

PM 看到的段落標題（「我理解你的真實想法」「這輪卡點」「你現在卡在」「這次先做」「教練判斷」）**全部是 client 端硬寫的排版標籤**（`lib/features/coach_chat/presentation/widgets/coach_chat_card.dart:829-886` 的 `_InfoLine`），值來自本就分離的 schema 欄位（`userTruth`、`frictionType`、`userState`、`nextStep`、`rewriteDecision` 等）。**改排版不需要動 Edge Function。**

### 採納度與優化方向

採納「一句結論＋展開看更多」：

- headline／`suggestedLine` 當結論層，其餘 `_InfoLine` 收進摺疊區（同檔已有 `ExpansionTile` 用例可沿用，`:530-558`）。
- 排版範式可參考 `coach_follow_up_result_card.dart` 的 5 欄精簡卡（「我看到的重點／這次建議你做／可以這樣說／邊界提醒」）。
- 純前端、可獨立出貨，建議與問題 2 的 loading 改善併成一個「Coach 呈現優化」小案。

### 風險註記

低。不動 prompt、不動 schema、不動扣費。

---

## 5. 「加入目前對話」vs「另存成新對話」差異不明（中）

### 現況核實

PM 觀察成立，但成因和「沒寫說明」不同——**兩種模式其實都有說明文案**（`lib/features/analysis/domain/services/screenshot_recognition_helper.dart:377-406`，append 分支還會依信心度／引用框／混串給不同提醒），問題是 UI 只顯示「當前選中模式」的一行動態說明（`screenshot_recognition_dialog.dart:1016-1026`）。預設選中「加入目前對話」，所以 PM 只看到前者的說明。

兩者實際行為差異（`analysis_screen.dart`）：

- **另存成新對話**：建立一筆新的 Conversation 並繼承來源對話的 partnerId（`:2380-2431`），不污染現有紀錄。
- **加入目前對話**：把辨識訊息 append 到現有對話尾端（`:2434` 起）。

### 採納度與優化方向

採納：

1. 把兩個選項的說明**同時顯示**（每顆 chip 下各附一行固定說明，動態警示照舊）。
2. PM 提議的命名（「繼續分析這段對話」vs「開始一段新的分析」）方向可以評估，但建議先只補說明、命名另議——這組選項語彙可能牽動其他頁面文案一致性。

### 風險註記

此確認頁是近期 OCR 匯入安全 UX 的重點面（截圖匯入確認頁承擔「側別誤判兜底」職責）。說明文字改動本身低風險，但**必須保留混串偵測警示邏輯**，不可在改版時弱化確認摩擦。

---

## 6. 截圖只能單張上傳、生成等待過久（中）

### 現況核實

這是兩個獨立問題：

1. **單張上傳**：上限確實是 3 張（`opening_rescue_screen.dart:826-834` 傳 `maxImages: 3`），但 `lib/shared/widgets/image_picker_widget.dart:63-79` 用的是 `pickImage`（單選 API）——**每次點加號只能選一張，放 3 張要重複操作 3 次**。這就是 PM 說的「單次操作限制」。
2. **等待過久**：開場救星帶圖走 analyze-chat 的 `mode:'opener'` 分支（`opener_service.dart:310-371`），只要帶圖就強制升 Sonnet＋OCR（產品品質決策），且此路徑**無 streaming**。現有「進度」是本地計時的 staged 文案（`opener_generation_progress.dart`，每 3 秒換一句、推到最後一句就停住）——等待真的久時，用戶會看到假進度卡在「快好了」。

### 採納度與優化方向

1. **多選（採納，quick win）**：改用 `pickMultiImage` 一次選多張（保留 3 張上限與現有壓縮流程）。低風險。
2. **等待時間**：短期不動模型——「圖片強制 Sonnet」是品質決策，降級會直接傷開場白品質。採納 PM 的「進度提示」方向，把假進度優化為**步驟式提示**（參考 `FullAnalysisPlaceholder` 的分段骨架模式），並讓最後階段文案誠實一點（不要停在「快好了」）。真 streaming 屬另案（程式碼註解已標記「真 streaming 另案」）。

### 風險註記

opener 屬高風險區（曾有 malformed JSON／quota 系列 P0），multi-pick 只動 client 選圖層、不碰生成與扣費，風險可控；仍建議實作後跑 opener service 相關測試。

---

## 7. 新增「追問／調整語氣」互動功能（功能提案）

### 現況核實

**技術基礎已經存在，成本比想像低。** coach-chat 已有完整的多輪 session 機制：

- Server：`activeSessionTurns`（上限 12 輪，role: user/coach、kind: question/clarification/supplement/answer，`supabase/functions/coach-chat/schemas.ts:47-52`），prompt 已消費對話歷史（`prompts.ts:143-206`）。
- Client：`coach_chat_providers.dart:88-258` 已建 turns 管理；UI 已有「繼續深挖／補充我的想法」追問入口（`coach_chat_card.dart:892-908`）。

也就是說，「太油了，再自然一點」「更簡短一點」的快捷 chip，可以直接掛在既有 session 機制上（把快捷語當一個 supplement turn 送出），或更精準——新增 `refineInstruction` 欄位只重寫 `suggestedLine` 而不重算整卡（回應更快、token 更省）。

注意：`coach-follow-up` 是表單式（phase＋q1/q2/q3）、無對話歷史，**不適合**承載此功能；正確載體是 coach-chat。

### 採納度與優化方向

正面回覆：同意這是差異化賣點，且可行性高。建議的實作形態：

- 在 `suggestedLine` bubble 下方加快捷 chip 列（「再自然一點」「更簡短」「更主動一點」＋自由輸入），走 refineInstruction 路線只重寫該句。
- 免費層同樣可用（配合 quota 政策），避免違反「Free 用戶核心功能可用到額度耗盡」規則。

**需要 PM／產品拍板兩件事**（見提問清單）：調整語氣要不要扣額度（目前 coach 回答一律扣 1 則；若每調一次語氣扣 1 則會被抱怨，但全免費有成本與濫用風險）、預設快捷選項清單。

### 風險註記

屬 AI prompt＋quota 高風險區，實作時需 Codex 審。建議做成獨立小案，不與其他 coach 改動混在同一 commit。

---

## 向 PM 的提問清單

1. **問題 2（教練一句話）**：截圖裡的「AI 推薦回覆」是分析頁的推薦回覆卡，還是 Coach 1:1 的回覆卡？實測帳號是免費層還是付費層？（免費層走 Haiku、付費走 Sonnet，直接影響品質判讀與修法方向。）
2. **問題 3（空狀態頁）**：先前的 Before/After Demo（React 元件）不在 repo 內，麻煩提供檔案或設計稿連結，我們以它為基準開實作案。
3. **問題 1（健康分數）**：「樣本不足」的處理，您期望只加提示文字，還是分數本身也要保守化（降權）？以及您心中「樣本足夠」的門檻大約是多少（例如 ≥10 則訊息／≥5 輪）？
4. **問題 7（調整語氣）**：每次「調整語氣」是否扣用戶額度？您期望的預設快捷選項有哪些（例如「再自然一點」「更簡短」之外還要什麼）？
5. **問題 6（單張上傳）**：跟您確認觀察到的限制是「每次點加號只能選一張、要放 3 張得點 3 次」嗎？若是，原因已定位（選圖用了單選 API），是低風險 quick win。

## 建議的執行順序（供排期參考）

低風險、可先出：#4 教練卡摺疊、#5 雙說明同顯、#6a 多選圖、#1a 初步評估提示、#2a coach loading 步驟提示
需 PM 補資訊：#2b 回覆品質（等介面／帳號層級確認）、#3 空狀態改版（等 demo）
需拍板＋Codex 審：#7 調整語氣（扣費政策）、#1b 分數降權（門檻）
