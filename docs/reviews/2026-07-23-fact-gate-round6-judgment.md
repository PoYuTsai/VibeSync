# 第 6 輪 eval 被拒候選全量判定（2026-07-23T02-43-11-260Z.json）

方法：`replay_r6.ts`（deno，直接 import 現行 gate 模組——hint.ts / hint_fact_ledger.ts /
practice_visible_quality.ts / debrief_card.ts / visible_text_guard.ts，以 eval 同款
parseOptions＋fixture context 逐筆重放），26 筆被拒候選 **26/26 重現 recorded code**；
另用 `probe_invite.ts` 分解 invite 分類器旗標與正確 allowedRoute。本輪 eval 跑在
2debf3e7（大掃除）之後，殘餘打回全是修後真殘留；**invite_route 記錄儀缺口已補**
（round5 §4），本輪首次有原文可判。full output＝`replay_r6_out.txt`（scratchpad）。

判定口徑同前兩輪：**FP**＝自然措辭被 heuristic 誤判；**TP**＝候選確實捏造/違規；
**TP-機械/機制**＝gate 照規格正確執行（結構缺欄、詞表命中、政策階梯）。

本輪盤面：80 發＝first_shot 62、second_shot 10、503 8；served 側詞表洩漏 0。
round5 已立案的七大家族（給X假人名、8 句窗、分析欄詞面 grounding、polarity 回頭翻、
這週六粒度、我們…附近同住、likes 所有格）本輪 **0 重現**——大掃除有效。

## 1. 逐筆判定表（26 筆）

### hint 側（13 筆）

| # | 筆 | code | 觸發欄位＋錨點 | 候選關鍵句 | 判定 | 理由 |
|---|---|---|---|---|---|---|
| 1 | bh1 r3 c1 | invite_route | warmUp 判 direct（GENERIC_PROPOSAL=「看到讓妳暫時忘記開會的當機感嗎?」）；allowed=not_ready | 「…好看到讓妳暫時忘記開會的當機感**嗎**？」 | **FP** | 詞中「看」＋句尾「嗎」被當提案句；全句零邀約語意 |
| 2 | bh2 r1 c1 | invite_route | warmUp 判 soft（SOFT_TIME「下次」＋GENERIC=「爬山還敢跟嗎?」）；allowed=not_ready | 「**下次**爬山還敢**跟嗎**？」 | **FP（邊界）** | 語意是追問她敢不敢再挑戰（她被朋友拖去爬山），非使用者邀約；詞形上帶「下次…跟」政策面模稜 |
| 3 | bh2 r1 c2 | third_party:name:is_named | steady「神了哈哈」conf=high | 「懷疑人生這三個字太**傳神了哈哈**」 | **FP** | 裸「傳」pattern 負向 lookahead 缺「神」→ 切出假人名「神了哈哈」；語氣詞（了/哈）沒被人名形態檢查擋 |
| 4 | bh3 r3 c1 | invite_route | warmUp 判 direct（GENERIC=「來的清醒感也算划算吧?」）；allowed=not_ready | 「咖啡因**換來**的清醒感也算划算**吧**？」 | **FP** | 「換來」的「來」＋句尾「吧」被當提案 |
| 5 | gh2 r3 c1 | invite_route | warmUp 判 direct（GENERIC=「打回票要重拍嗎?」）；allowed=build（P2） | 「被**打**回票要重拍**嗎**？」 | **FP** | 自嘲交作業梗被「打…嗎」切成提案；照 round4 裁決放行的示弱玩笑又被另一個 regex 殺 |
| 6 | gh3 r2 c1 | not_grounded | steady 與全逐字稿零 2/3/4-gram 重疊 | 「被抓包了嗎哈哈…只對敢應戰的人講，妳算第一個接招的」 | **FP** | 回應她「是不是對每個女生都嗆一樣的話」的指控句，語意扣題但天然不複讀她的詞面；全窗化後 gh3 型仍是系統性死角 |
| 7 | gh3 r2 c2 | invite_route | warmUp 判 direct（ADDRESSEE「帶妳去」）、steady 判 soft（「改天一起去」）；allowed=build（P3） | 「麻辣鍋那家我可以**帶妳去**試試」「**改天一起去**」 | **TP-機械** | 真邀約語超出速約階梯（P3 只准鋪墊），政策 gate 照規格擋 |
| 8 | gh3 r3 c1 | not_grounded | steady 零詞面重疊 | 「哈哈被抓包…只跟嘴硬又吃得下辣的人講，妳算特別版」 | **FP** | 同 #6 |
| 9 | gh5 r1 c1 | venue_named | warmUp「還沒實際去過」（asksPlace pattern3，reply 嚴格模式）；伴生 steady「說到區」located_at conf=high | 「我也是聽朋友提的，**還沒實際去過**欸」「**說到區**我還真的答不上來」 | **FP** | 候選刻意不報地點；「還沒實際去過＋欸」被語尾助詞 lookahead 當店名、「說到區」被字尾「區」切割（lookahead 只擋「區域」） |
| 10 | gh5 r1 c2 | venue_named | coaching「實際確認」（asksPlace pattern1「位置(是)X」） | coaching「她問**位置是實際確認**，不是拒絕」 | **FP** | 教學轉述句被「位置是X」報點 pattern 吃掉；coaching 地點形態豁免只掛 pattern 0/3，pattern1 沒有 |
| 11 | gh5 r2 c1 | not_grounded | steady 零詞面重疊 | 「地區我一時想不起來，怕講錯帶妳撲空…一起去晃晃找答案？」 | **FP** | 誠實「想不起來」迴避句天然無重疊（附帶：「帶妳撲空」讓 steady 被分類 direct，修掉 grounding 也會卡 steady 槽降階） |
| 12 | gh5 r3 c1 | partner:current_location:is_at | coaching「幫你把邀約鋪好路」；伴生「但可以帶路」located_at conf=high | coaching「她**在幫你把邀約鋪好路**」「不知道確切位置**但可以帶路**」 | **FP** | 進行貌「她在＋VP」被當「她在某地」（PLACE_VALUE 無地名形態）；「帶路」被字尾「路」切割 |
| 13 | gh5 r3 c2 | venue_named | coaching「邀約信號」（pattern1） | coaching「她問**位置是邀約信號**」 | **FP** | 同 #10（附帶：steady「這週五或六下午有空嗎」=direct，超 steady 槽允許的 soft） |

### debrief 側（13 筆）

| # | 筆 | code | 觸發欄位＋錨點 | 候選關鍵句 | 判定 | 理由 |
|---|---|---|---|---|---|---|
| 14 | bd5 r1 c1 | user:pet:has_pet | suggestedLine anchor=「狗」 | 「我**超怕自己養狗會**被牽著跑，妳都怎麼訓練布丁聽話的？」 | **FP** | 假設/恐懼語氣（怕…會…）被當 user 自陳養狗；2debf3e7 修了無主詞與 coaching「你」，漏了第一人稱未然句 |
| 15 | gd2 r0 c1 | suggested_line_not_grounded | suggestedLine＋nextFirstLine 零詞面重疊 | 「那**週三晚上**這場，我直接卡進去，妳留個位置給我？」 | **FP** | 提案句天然引入新時間詞；語意緊扣她「排進我的行程」的挑戰；fact 層裁決①已放行 user 提案，詞面 gate 又殺回來 |
| 16 | gd2 r2 c1 | suggested_line_not_grounded | suggestedLine 零重疊（nextFirstLine 因「見識」重疊過關） | 「那週三晚上我先卡好，妳排一下，輸了請妳吃東西」 | **FP** | 同 #15；同卡片內引用她原詞的貼句過、沒引用的死，顯示 gate 判準與捏造無關 |
| 17 | gd2 r2 c2 | partner:schedule:available_at | nextInviteMove anchor=「下週三晚上」 | 「先提一個具體的日期或時段（「下禮拜三晚上」），再**問她能不能**配合」 | **FP** | 「問她能不能配合」疑問補語被第三式 schedule pattern（時間…她…能）抽成「她下週三晚上有空」的事實宣稱 |
| 18 | gd3 r0 c1 | game_breakdown_missing_fields | gameBreakdown=字串 `"\n<parameter name=\"phaseReached\">…"`＋missedVariable/failureState/nextFirstLine/inviteDirection 逸出頂層 | — | **TP-機械** | gate 照規格擋非物件；**但不是整包省略**——五欄內容全在，是 Sonnet 把 tool_use 巢狀物件拍平成 `<parameter>` 語法（見 §3） |
| 19 | gd3 r0 c2 | temperature_leak | gameBreakdown.failureState 漏詞=框架 | 「這是直接的**框架**反饋」（summary/dateChanceReason 的「框架掉了」×2 合法放行） | **TP-機制** | 詞表 WAI；詞源＝temperature.ts 禁詞清單仍列字＋「框架掉了」例外教學（見 §2）；本筆為 Haiku 重試候選 |
| 20 | gd3 r2 c1 | game_breakdown_missing_fields | 同 #18 拍平型 | — | **TP-機械** | 同 #18 |
| 21 | gd3 r3 c1 | game_breakdown_missing_fields | 同 #18 拍平型 | （伴生：suggestedLine「上次差點被一間排隊店騙走一小時」捏造使用者軼事，grounding 也會殺） | **TP-機械** | 同 #18 |
| 22 | gd3 r3 c2 | suggested_line_not_grounded | suggestedLine＋nextFirstLine 零重疊 | 「我最近也在**計畫下個月去日本**，邊泡溫泉邊看楓葉」 | **TP-結果** | 捏造使用者近況（round5 #58 同款「上次去的地方」家族）；該擋，grounding 湊巧攔對 |
| 23 | gd4 r3 c1 | game_breakdown_missing_fields | 同 #18 拍平型 | — | **TP-機械** | 同 #18 |
| 24 | gd5 r2 c1 | world:venue:located_at | gameBreakdown.nextFirstLine anchor=「老地方巷」conf=high | 「那星期六下午三點，**老地方巷口**等妳」 | **TP-結果（弱）/FP-機制** | 兩人沒有「老地方」＝輕度憑空生出碰面點，擋掉不冤；但錨點「老地方巷」是字尾「巷」切進「巷口」的切割產物（同筆 suggestedLine「星期六下午市集見」已被市集 lookahead 正確放行） |
| 25 | gd5 r2 c2 | temperature_leak | gameBreakdown.missedVariable 漏詞=框架 | 「只有『星期六下午』的**框架**」 | **TP-機制** | 同 #19；Haiku 重試候選 |
| 26 | gd5 r3 c1 | game_breakdown_not_grounded | nextFirstLine 零詞面重疊（suggestedLine 因「週六下午」重疊過關） | 「好啊一言為定，那我們約幾點碰面？我先抓個時間傳給妳」 | **FP** | 順勢收尾允諾句，直接回應她「說好了，你負責幫我把關殺價」；零捏造 |

## 2. Gate 彙總

| gate | 總數 | FP | TP/該擋 | FP 率 | 一句話根因 |
|---|---|---|---|---|---|
| invite_route（首次有原文） | 5 | 4（含 1 邊界） | 1（gh3 真邀約超階） | **80%** | GENERIC_PROPOSAL 單字動詞詞中匹配（看/來/打）＋句尾「嗎/吧」即成提案 |
| not_grounded（hint） | 3 | 3 | 0 | **100%** | 全窗化後仍殺「回應質問句/誠實迴避句」——這類句天然零詞面重疊 |
| venue_named | 3 | 3 | 0 | **100%** | asksPlace pattern1「位置是X」無 coaching 豁免＋pattern3 reply 嚴格模式吃迴避句 |
| suggested/breakdown_not_grounded（debrief） | 4 | 3 | 1（日本捏造） | 75% | 提案/允諾句天然引入新詞面；TP 純屬湊巧攔對 |
| game_breakdown_missing_fields | 4 | 0 | 4 | 0% | TP-機械；真相＝巢狀物件被拍平，**非內容省略**（§3） |
| temperature_leak | 2 | 0 | 2 | 0% | TP-機制；詞源＝temperature.ts 第二處禁詞列字沒去（§2） |
| third_party:name:is_named | 1 | 1 | 0 | 100% | 裸「傳」lookahead 缺「神」＋人名形態不擋語氣詞 |
| partner:current_location:is_at | 1 | 1 | 0 | 100% | 進行貌「她在＋VP」；PLACE_VALUE 無地名形態 |
| user:pet:has_pet | 1 | 1 | 0 | 100% | 第一人稱假設句「怕自己養狗會…」無 irrealis 豁免 |
| partner:schedule:available_at | 1 | 1 | 0 | 100% | 「問她能不能配合」疑問式被當 availability 宣稱 |
| world:venue:located_at（debrief） | 1 | （機制面 1） | 1（弱） | — | 「老地方巷口」：內容輕捏造、錨點是字尾切割 |
| **合計** | **26** | **17** | **9** | **65%**（機制面誤觸 18/26≈69%） | |

FP 率走勢：round4 80% → round5 74% → **round6 65%**；且絕對量 106→26 筆。
真捏造被正確攔下 2 筆（#22 日本、#24 老地方-弱）；gh5 round4 立案的「方位詞/捷運站」FN 補抓
（2debf3e7）本輪無真捏造樣本可驗，但沒有產生新誤殺。

## 3. game_breakdown_missing_fields 懸案破案（優先項）

4 筆 raw 全長這樣：`"gameBreakdown": "\n<parameter name=\"phaseReached\">還在互相認識…"`，
且 `missedVariable/failureState/nextFirstLine/inviteDirection` **以頂層 key 存在、內容完整**。
即：模型（4 筆全是 Sonnet 首發）把 tool_use 巢狀物件寫成 tool-call 的 `<parameter>` 拍平語法——
phaseReached 內容黏在 gameBreakdown 字串裡、其餘四欄逸出到頂層。
`parseGameBreakdown`（debrief_card.ts:255）見非物件即丟 missing_fields，機械上正確。

結論：**b7871ab3 加的「失敗局五欄必填」prompt 強調對症不對藥**——模型沒有省略，是巢狀
序列化失敗（集中在 gd3/gd4 失敗局＝分析內容最長的卡）。修法在 schema/repair 層不在 prompt：
- 甲案（repair）：parseGameBreakdown 前偵測「gameBreakdown 為字串且以 `<parameter` 開頭＋頂層存在五欄」→ reparent 組回物件再走原 gate；
- 乙案（schema）：DEBRIEF_TOOL_SCHEMA_GAME 拍平成 `gb_phaseReached` 等頂層欄位，服務端組回巢狀——一勞永逸移除巢狀物件。

## 4. temperature_leak 懸案定位（優先項）

漏詞皆為「框架」×2（#19 框架反饋、#25 星期六下午的框架），兩筆都是 Haiku 重試候選；
gd3 候選同卡還正確使用「框架掉了」sentinel ×2 獲放行——模型顯然仍被教了「框架」語彙。

源頭：**b7871ab3 只根治了 prompt.ts:229，漏了第二處注入點**——
`temperature.ts:166-171`（`temperatureBandDebriefInstruction`）仍逐字列出
「…推拉、篩選、賦格、可得性、框架（唯一例外：「框架掉了」可用）」，
且經 `prompt.ts:742-743` 注入**每一張** assisted debrief prompt（beginner＋game 都有）。
粉紅大象效應同 round5 診斷；「框架掉了」例外行本身就是「框架」一詞的教材。

修法（修 prompt，不修 gate）：temperature.ts:168-171 比照 b7871ab3 去列字
（「絕不出現英文內部標籤與教練行話，改用白話」即可）；若移除「框架掉了」教學行，
visible_text_guard.ts:159 的 sentinel 可一併評估退場。11→2 筆的降幅證明去列字路線正確，
收尾就差這一處。

## 5. 假陽性 heuristic 根因清單（對現行程式碼，檔案:行號）

1. **GENERIC_PROPOSAL 單字動詞詞中匹配**（#1/#2/#4/#5，invite_route 4 筆）
   `supabase/functions/practice-chat/practice_invite.ts:23-24`——
   `/(?:去|來|吃|…|打|唱|約|碰面|見面)[^，,。！？!?；;]{0,18}(?:吧|嗎|…)$/`：
   「好**看**到…嗎」「換**來**的…吧」「被**打**回票…嗎」「**爬**山還敢跟嗎」全中。
   單字動詞無詞邊界概念，配上 beginner not_ready／game build 的全面封鎖
   （hint.ts:827-839/:885-897），閒聊反問句直接陣亡。修法：單字動詞後要求
   非構詞環境（前一字不得為 好/換/被/起 等）或要求動賓結構＋語尾距離收窄。
2. **not_grounded 詞面 n-gram 對「回應句」的結構性盲區**（#6/#8/#11/#15/#16/#26，7 筆）
   `practice_visible_quality.ts:239-273`（全窗版）＋呼叫點 hint.ts:2333-2339、
   debrief_card.ts:1431-1446。全窗化已救回「引用較早輪次」型（round4 主因），
   剩下的是更深一層：回應她的質問（gh3）、誠實承認不知道（gh5）、提案新時間
   （gd2）、收尾允諾（gd5）——這四型句子的功能就是「回應」而非「複讀」，
   任何詞面比對都殺。修法方向：最新句為問句/確認句時，第一二人稱回應句式
   給語意豁免；或接受為 fixture 天然死角、確保兩次 attempt 不會同型雙殺。
3. **asksPlace pattern1「位置(就?是)X」無 coaching 豁免**（#10/#13）
   `hint_fact_ledger.ts:2547`；地點形態豁免（:2613-2620）只掛 patternIndex 0/3。
   coaching 慣用句「她問位置是實際確認/邀約信號」永遠中槍。修法：pattern1 納入
   同一豁免，或「(她|他|對方)問」前導時視為轉述跳過。
4. **asksPlace pattern3 reply 嚴格模式吃「迴避句＋語尾助詞」**（#9 warmUp）
   `hint_fact_ledger.ts:2549`——「還沒實際去過**欸**」被當直接報店名。
   修法：候選含否定/未然詞（還沒|沒有|沒去過|不知道）時跳過。
5. **地名字尾切割殘漏三型**（#9 steady、#12 伴生、#24）
   `hint_fact_ledger.ts:1812`——lookahead 已擋 區域/市集/街道，但：
   「說到**區**」（動詞短語＋字尾）、「帶**路**」（複合詞，NON_PLACE_COMPOUND_TAIL
   :660-661 未收）、「老地方**巷**口」（「巷」無任何 lookahead）。
   修法：巷(?!口|弄)；補 帶路/鋪路/領路 進 :661；「說到|提到|聊到|講到」前導跳過。
6. **進行貌「她在＋VP」誤判 current_location**（#12）
   `hint_fact_ledger.ts:1710-1717`＋`PLACE_VALUE`（:114）無地名形態——
   「她在幫你把邀約鋪好路」→ 她在「幫你把邀約鋪好路」這個地方。
   修法：「在」後接動詞（幫|做|想|等|忙|準備|處理|聊）即進行貌跳過，或
   非 isLikelyProperPlaceAnchor 一律 low。
7. **裸「傳」lookahead 缺字＋人名形態不擋語氣詞**（#3）
   `hint_fact_ledger.ts:1124`（`傳(?!給|統|說|來|開|訊|話|達|遞|真|承)`缺「神」）＋
   `looksLikePersonName`（:613-622）對「神了哈哈」放行（語氣詞 了/哈 不在排除規則）。
   修法：lookahead 補 神|聞|奇；人名形態排除含 了|哈|欸|啦|喔 的候選。
8. **pet 無 irrealis 豁免**（#14）
   `hint_fact_ledger.ts:1267-1319`——weakOwnership（:1297-1299）只涵蓋無主詞與
   coaching「你」；「我超怕**自己養狗**會…」第一人稱假設句仍 high。
   修法：match 前窗含 怕|如果|要是|假如|想像|哪天|會不會 → low。
9. **schedule 第三式吃疑問補語**（#17）
   `hint_fact_ledger.ts:1487-1493`——「（下禮拜三晚上）…問**她能**不能配合」
   匹配 `(TIME).{0,6}(ACTOR)(STATUS)`。修法：「問…能不能|可不可以|方不方便」
   疑問式跳過（同 :537 已有的問句識別可複用）。

## 6. 修復建議（分類）

**修 heuristic（gate 程式）**：根因 1（invite 4 筆，性價比最高）、3/4/5/6/7/8/9
（fact-ledger 殘漏 7 筆，全是 2debf3e7 同家族的邊角）；根因 2 的 grounding 四型回應句
建議與 Eric 對齊裁決——語意豁免 vs 接受死角。
**修 prompt**：temperature.ts:166-171 去列字（§4，temperature_leak 即可歸零）。
**修 schema/repair（非 prompt）**：gameBreakdown 拍平 repair 或 schema 拍平（§3，
missing_fields 4 筆即可歸零；再強調 prompt 無效）。
**接受為真實攔截（不動）**：#7 速約階梯擋真邀約（WAI）、#22 日本捏造、#24 老地方
（順手把錨點切割修掉即可）。
**fixture／政策觀察（Eric 裁決範圍）**：gh5 base=direct 但 steady 槽固定降一階
（hint.ts:829-833）→ P5 收尾局模型自然把明確邀約放 steady，修完 venue FP 後仍會
卡 invite_route（#11/#13 附帶）；gh3 質問局同 round4 判定＝結構性高 reject fixture。

## 7. 附帶觀察

- bd5 r1 c1（beginner）模型輸出 `"gameBreakdown":"null"`（字串）——beginner 路徑
  不解析該欄無實害，但同樣是巢狀欄位序列化不穩的旁證。
- 兩筆 temperature_leak 皆 Haiku 重試候選；Sonnet 首發本輪零洩漏——小模型對
  prompt 內列字更易照抄，與 round5 一致。
- 26 筆中 8 發最終 503：bh2 r1、gh3 r2、gh5 r1/r3、gd2 r2、gd3 r0/r3、gd5 r2——
  全部是「兩次 attempt 被同型或不同型 FP 各殺一次」，修上述根因可直接換算成 503 降幅。

重放工具：`replay_r6.ts`、`probe_invite.ts`（scratchpad，只讀不改專案檔）。
