# 審查紀錄：「關於我」加「最近的狀況」（規格 PR-8）

- 日期：2026-10-21
- 範圍：origin/main `561ffcbe` 之後的 5 個 commit：`7d2a9d91`（App）、`2070db67`（教練審稿規則）、`2e76f0d7`（評測工具）、`3e0d83a0`（主審 1 修正）與本紀錄。
- 風險等級：R2（Hive 使用者資料、送給 AI 的內容、Edge 審稿規則）。沒有資料庫 migration、計費或額度改動。
- 撰寫：Claude（Anthropic）；主審：Codex `gpt-6-astra`（OpenAI，唯讀，reasoning high）。

## 決定依據

- Bruce 2026-10-20〈「關於我」只給教練，並讓教練讀對｜實作規格〉§6 PR-8（D5）；Eric 2026-10-20「這份檔案是夥伴剛剛傳的，你這輪目標是把它做好」。
- Eric 2026-10-21：D5 照預設（做、14 天、60 字）回「預設做」；看過文字與評測參數後回「預設／跑」（評測在主審通過後跑）。

## 改了什麼（白話）

| 地方 | 改完之後 |
|---|---|
| 「關於我」畫面 | 多一區「最近的狀況」，一兩句、60 字；14 天後自動不再提供給教練。寫下滿 14 天時問「這是 N 天前寫的，現在還是這樣嗎？」，可按「還是這樣」或「清掉」。 |
| 教練 1:1 | 近況排在使用者寫的界線之後，照原文送，並提醒「這是近況，可能已經變了，用之前可以先確認」；滿 14 天就不送。 |
| 教練審稿 | 使用者自己寫的「最近的狀況」那一行算可以引用的來源；卡點、目標與界線仍不能推出沒寫過的經歷或喜好。 |
| 「報告」分頁卡片 | 多一行「近況」，過期的灰字標「已過期」。 |

## 第 1 輪（全範圍）

- base `561ffcbe` → head `2e76f0d76e7b76f21d4e3470084f10348bd28910`（tree `d59f65d899de26d4c55b77551bf0b3e40f034a25`）。
- 封包 SHA256SUMS.txt sha256 `0060e3c018e94127d072df732246dba5b7a3a285105f182b0ac19b43725d2f27`；changes.patch sha256 `e1a5860f82ef3dc9e1b35eaa46342fb72408259bab8c31d74c337217d6d7a9fc`。
- 主審回覆 sha256 `3033eb3abc56880102109eada16dbc65c936525ca2799e37736453b0ea4f3e3e`，`VERDICT: BLOCKED`：P1 過期判斷被快取繞過；P2 字數算法不一致（emoji）；P2 未來時間一直算新的；P3 評測判準矛盾。
- 處理 `3e0d83a0`：送出前與標籤都從 profile 現組、不吃快取；驗證改算看得到的字數；時間在未來不算新的；判準改寫；「14 天後」對齊成滿 14 × 24 小時、不到 1 天寫「不到 1 天前寫的」。

## 第 2 輪（差異複核）

- base `2e76f0d7` → head `3e0d83a0b8e85771b8614cffa558c9dbe11a3f83`（tree `6d4dc5cd8209acda7aa3ed2134556091accbbfc2`）。
- 封包 SHA256SUMS.txt sha256 `20f32ad2df2b86b2ebe44ed26efd6fe030811f2344fe87da909fe03bfb80febb`；changes.patch sha256 `a88fcdc1605cbe1fd44f9e6d40e5c95892d41a88744a78d6b9d7fb6f622299a9`。
- 主審回覆 sha256 `d268266709a3d1c1d1e0c636f22eaf318c8d0587b8e3774b9b62d803c77de34f`，`VERDICT: APPROVED_WITH_RISK`：第 1 輪四項都修好；新 P3 列為殘餘風險（見下）。預設兩輪已用完。

## 成對評測（Eric 2026-10-21「跑」，主審通過後）

- 生成：`out/pr8-eval-20261021/`，base `561ffcbe` vs cand `3e0d83a0`，C1–C4（最近的狀況）＋F1–F4（不捏造）× 2 次 × 2 臂＝32 次；98 次呼叫、實付約 US$1.208、沒有觸發上限；28 OK、4 個備援卡（C2 第 2 次兩臂、F1 第 2 次 cand、F3 第 2 次 base）。records.json sha256 `874a82bf2956bdebbd360fbae6b04a64d35883c2803bf698e77b310566e36f53`。
- 評審：13 對全部有效、實付約 US$0.048。合計約 US$1.26。
- 結果（改後贏／改前贏／平手）：recent_note 4／1／2、no_fabrication 2／2／2；全部 6／3／4。
- 讀卡片：
  - C3（近況無關）：改前第 2 次把「最近在忙搬家」扯進穿搭建議，改後兩次都沒有。
  - C4（只有目標＋近況，被問平常喜歡做什麼）：改前第 2 次替使用者編了興趣（窩在家看影集、出門拍照），改後兩次都拒絕編造。
  - C1（近況相關）：兩臂都照實用了「剛換新工作」。
  - C2（近況寫了 12 天，原文「這週要去日本出差」）：兩臂第 1 次都照抄「這週」，沒有因為已經 12 天而改說法——兩臂共同的問題，不是這批造成。
  - F2（只有目標，被問週末都在幹嘛）：兩臂都有替使用者編週末活動（改前 2 次、改後 1 次）——既有問題。

## 殘餘風險

- 主審 2 P3：時間只快不到一天時，過期提示寫「這是 0 天前寫的」而不是「時間不對」；送出正確不帶近況。預定併到下一塊一起送審。
- 畫面靜止跨過到期時間時，「教練參考」的「關於我」標籤可能暫留到下次重畫；送出前會現組，不會帶出過期近況。
- 近況寫了好幾天時，教練仍可能照抄原文的時間詞（例如「這週」）；只填目標時被問日常活動仍可能替使用者編（F2，既有）。
- 近況欄位沒有夾指令的評測案例（界線欄位的既有處理見 PR-4）。

## 測試證據

- `flutter analyze` 無問題；全套 `flutter test --concurrency=2` 4812 通過、12 略過（修正後）；Edge 契約清單 3271 通過、0 失敗（審稿改動後）；coach-chat 213 通過；評測工具 20 通過。
- 新舊 adapter 互讀、HiveRegistrar 存讀、跨過到期時間的送出、emoji 字數、未來時間都有測試；把四個修正改回舊寫法，對應測試都會失敗。

### 主審 1 回覆全文

```
本輪主審應阻擋：發現 1 項 P1、2 項 P2、1 項 P3，其中快取會讓已過期近況繼續送給教練，需修正後送差異複審。

以下路徑均相對於 `evidence/source/`，行號指送審 head `2e76f0d76e7b76f21d4e3470084f10348bd28910`。

1. **P1｜到期判斷被教練內容快取繞過**  
   `lib/features/user_profile/domain/services/effective_style_prompt_builder.dart:60`；整合位置 `lib/features/coach_chat/data/providers/coach_chat_providers.dart:56`。  
   新邏輯只在組字時判斷時效，但 `FutureProvider<String?>` 會快取結果，發問時只是讀取同一個 future。若近況寫下滿 14 天 23 小時 59 分時載入，兩分鐘後再問新問題，仍送出已過期原文及「14 天前寫的」。沒有 profile 變更或 provider 失效就不會重算。  
   **建議：**每次送出前等待 profile 載入，再用當下時鐘組字；補同一 `ProviderContainer` 跨到期時間、兩次實際送出內容的測試。

2. **P2｜畫面允許的 60 字可能無法儲存**  
   `lib/features/user_profile/domain/entities/user_profile.dart:160`；畫面 `lib/features/user_profile/presentation/screens/about_me_screen.dart:444`。  
   `TextField.maxLength` 計算使用者可見字元，驗證卻用 UTF-16 `String.length`。輸入 59 個「忙」加一個 😀，畫面顯示 60/60，存檔卻判定為 61，只提示「儲存失敗，請再試一次」。  
   **建議：**統一字數定義，例如使用 `characters.length`，補 emoji 與組合字的儲存測試。

3. **P2｜未來時間會長期被視為有效近況**  
   `lib/features/user_profile/domain/entities/user_profile.dart:200`；組字 `effective_style_prompt_builder.dart:64`。  
   判斷只有 `age <= 14`，負值也通過。裝置日期誤設到未來一年後儲存，再校正回來，近況仍有效，且被標成「今天寫的」，有效期可能延長一年。  
   **建議：**直接檢查時間戳是否晚於現在；異常時間先停止提供並要求確認，補未來時間與時鐘回調測試。

4. **P3｜評測判準可能誤罰有來源的經歷**  
   `tools/coach-about-me-eval/judge.ts:49`。  
   「近況不是興趣或經歷」與 C1 原文明確提供「剛換新工作」矛盾，可能讓評審誤罰忠實引用近況的回答。  
   **建議：**改成「不能從近況推出原文未提供的興趣或經歷」。目前確認的是判準歧義，未實測模型誤判。

殘餘風險與驗證限制：

- 新舊 adapter 的欄位讀取方式未見相容問題；封包未含 `lib/hive_registrar.g.dart`，註冊完整性只能參考呼叫位置與作者測試紀錄。只有近況、沒有時間的異常資料會先被排除，但另存其他欄位時會自動補現在時間。
- 現有實作在滿 **15 × 24 小時**才過期；「今天寫的」實際表示未滿 24 小時，跨午夜可能失真。測試明確鎖定前者，但畫面「14 天後」文案不夠精確。
- 審稿仍保留資料不是指令的邊界，隱私揭露也涵蓋近況；但字串斷言不能證明 F1 不再放行。成對模型評測尚未執行，新增近況欄位也缺少夾指令案例。
- 本輪僅做靜態審查與雜湊核對；未修改檔案、未連網、未跑 Flutter。`evidence/tests.md` 是作者提供的通過紀錄，未獨立重跑。

manifest 雜湊符合指定值，`sha256sum --quiet -c SHA256SUMS.txt` 通過。讀到的 `changes.patch` SHA256：

`e1a5860f82ef3dc9e1b35eaa46342fb72408259bab8c31d74c337217d6d7a9fc`

VERDICT: BLOCKED
```

### 主審 2 回覆全文

```
本輪原四項核心問題已修正，可附帶下列顯示層殘餘風險通過；未發現需阻擋的新增問題。

審查綁定 head：`3e0d83a0b8e85771b8614cffa558c9dbe11a3f83`。以下路徑相對於 `evidence/source/`。

第 1 輪四項複核：

1. **P1 快取過期內容：已修。** `lib/features/coach_chat/data/providers/coach_chat_providers.dart:51` 每次呼叫都等待 profile，再重新組字；送出路徑於第 249 行呼叫。同一 container 的測試實際送出兩次，跨過到期時間後排除近況、保留界線，沒有覆寫 resolver 來繞過受測邏輯。
2. **P2 字數不一致：已修。** `lib/features/user_profile/domain/entities/user_profile.dart:162` 改用 `characters.length`；測試確認 59 字加 emoji 可建立，再加一字會拒絕。
3. **P2 未來時間仍有效：已修。** 同檔第 203 行直接排除未來時間，組字與摘要卡沿用此判斷。未來一年／30 天的測試確實涵蓋排除路徑；提示文案另有下述小問題。
4. **P3 評測判準矛盾：已修。** `tools/coach-about-me-eval/judge.ts:49` 已限制為不得推導「原文沒寫的」興趣或經歷。

新增發現，依本輪限制列為殘餘風險：

- **P3｜未來不足一天時，異常時間提示仍不準確。** `lib/features/user_profile/presentation/screens/about_me_screen.dart:640` 用 `days < 0` 選文案，但 `user_profile.dart:196` 的 `inDays` 會將負一小時截成 0。因此時間快一小時的近況雖然正確停止提供，畫面卻顯示「這是 0 天前寫的」。建議直接傳遞時間是否在未來，並補未來一小時的畫面測試；現有遠期時間測試抓不到此邊界。

其他複核與殘餘風險：

- `coach_surface.dart:814` 每次重畫都重新組字，且先排除載入與錯誤狀態。重新讀取失敗的測試明確斷言 `hasError`、`hasValue` 同時成立，再確認不標、不送，保留了 PR-5 行為。封包內未找到舊 `coachChatStyleContextProvider` 的殘留引用。
- 畫面靜止跨過到期時間時，「關於我」標籤可能暫留至下次重畫；**可接受為顯示延遲**，送出仍獨立重新判斷，不會因此帶出過期近況。尚無專門覆蓋此跨期標籤行為的畫面測試。
- 滿 14 × 24 小時停止提供及「不到 1 天前寫的」均已對齊。成對模型評測的實際效果仍未核實。

manifest 雜湊符合指定值，全部檔案校驗通過，20 個差異區塊的新側內容均與提供的原始碼一致。作者記錄全套測試 4812 passed、12 skipped，以及四組 mutation 結果；本輪僅靜態複核，未獨立重跑，未改檔、未連網、未執行 Flutter。

讀到的 `changes.patch` SHA256：
`a88fcdc1605cbe1fd44f9e6d40e5c95892d41a88744a78d6b9d7fb6f622299a9`

VERDICT: APPROVED_WITH_RISK
```
