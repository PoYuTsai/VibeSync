# 第 4 輪 eval hint 側 rejectedCandidates 全量判定（2026-07-22T20-21-43-206Z.json）

方法：用 deno 重放 gate（`replay_gates.ts`，直接 import `hint_fact_ledger.ts` / `practice_visible_quality.ts`，
以 eval 同款 `hintTrustedFactualEvidence` + fixture turns 重建 context），逐筆定位觸發欄位與 claim 錨點，
再對照 fixture 對話判定真/假陽性。共 30 筆（打回代碼帶在 candidate 上；hint gate 順序＝bossy(parse 期) → fact ledger → grounding，
記錄到的 code＝第一個炸的 gate）。

判定口徑：
- **假陽性（FP）**＝候選沒有捏造/違規，自然措辭被 heuristic 誤判。
- **真陽性（TP）**＝候選確實捏造了逐字稿沒有的具體事實。
- **TP-結果/FP-機制**＝候選確實有捏造、該擋，但實際觸發的是另一個誤判錨點，真正的捏造反而沒被抽取到。

## 逐筆判定表

| # | fixture | 打回代碼 | 觸發欄位＋錨點 | 候選關鍵句 | 判定 | 理由 |
|---|---------|----------|----------------|------------|------|------|
| 1 | bh1 r1 | unsupported:third_party:name:is_named | coaching「接納感」 | 「…自我調侃，**給接納感**；」 | **FP** | 「給＋抽象名詞」被當「送東西給某人＝人名」；候選全文零第三方人名 |
| 2 | bh2 r1 | unsupported:partner:schedule:available_at | coaching「今天」 | 「適合**她今天能**量沒那麼高時使用」 | **FP** | SCHEDULE_STATUS 含單字「能」，匹配到「能量」的「能」→「她今天能」被抽成 partner 今天有空 claim |
| 3 | bh3 r0 | unsupported:third_party:name:is_named | coaching「認同」 | 「順著她的邏輯**給認同**」 | **FP** | 同 #1，「給認同」→ 人名「認同」 |
| 4 | bh3 r2 c1 | unsupported:third_party:name:is_named | coaching「予認同」 | 「**給予認同**，展現理解」 | **FP** | 同 #1，「給」+「予認同」；連「給予」都會被切出假人名 |
| 5 | bh3 r2 c2 | unsupported:user:preference:likes | warmUp「咖啡」 | 「我之前也想過要戒…乾脆就接受自己是**咖啡愛好者**」 | **TP** | 替用戶捏造自我揭露（用戶從未說過自己想戒咖啡/是咖啡愛好者）；抽取正確、符合 gate 設計意圖 |
| 6 | bh3 r3 | unsupported:third_party:name:is_named | coaching「予理解」 | 「給予理解」 | **FP** | 同 #4 |
| 7 | bh5 r2 | unsupported:third_party:name:is_named | warmUp「現的」 | 「妳怎麼**發現的**，是隔天鐵腿才知道嗎」 | **FP** | 送收動詞「發」匹配到「發現」的「發」→「現的」被當人名 |
| 8 | gh1 r0 | not_grounded | steady | 「妳通常怎麼破解這種『卡住』的狀態？」 | **FP** | steady 把「還停在第三章」語意轉述成「卡住」，與最新 ai 句無逐字 2-gram 重疊；語意完全接住最新句 |
| 9 | gh2 r0 c1 | bossy_pasteable_reply | steady | 「我還沒**交作業**就想放棄了」 | **FP** | 裸 `/交作業/` 不分方向；此處是用戶自嘲要交作業給她（呼應她「我可是很嚴格的」），不是指使對方 |
| 10 | gh2 r0 c2 | not_grounded | steady | 「有妳這個**標準**在，我應該會認真一點」 | **FP** | 「嚴格」→「標準」的自然轉述，無逐字重疊 |
| 11 | gh2 r1 c1 | bossy_pasteable_reply | steady | 「挑一張最不糊的**交作業**」 | **FP** | 同 #9（另 warmUp「拍出師才敢嗆」還被抽成 hometown claim，bossy 先炸） |
| 12 | gh2 r1 c2 | not_grounded | steady | 「妳說的『天空有燒起來就是賺到』…」 | **FP** | 逐字引用對話第 2 句，但 latestOnly 只認最後一句 ai；有憑有據被判 not grounded |
| 13 | gh2 r2 c1 | bossy_pasteable_reply | steady | 「那我等等就去**交作業**」 | **FP** | 同 #9 |
| 14 | gh2 r2 c2 | not_grounded | steady | 「妳下班路上都在哪邊拍？」 | **FP** | 接對話第 2 句「下班路上隨手拍」，非最新句 → 被殺 |
| 15 | gh2 r3 c1 | bossy_pasteable_reply | steady | 「挑一張最不糊的先**交作業**」 | **FP** | 同 #9 |
| 16 | gh3 r0 c1 | not_grounded | warmUp+steady | 「只對敢嗆我的人才這樣…」 | **FP** | 直接回應她「你是不是對每個女生都嗆一樣的話」，但無逐字片段重疊 |
| 17 | gh3 r0 c2 | not_grounded | warmUp | 「我確實常常這樣，但妳是第一個直接戳我的」 | **FP** | 同 #16 |
| 18 | gh3 r1 c1 | unsupported:user:residence:hometown_is | warmUp「比吃辣的」 | 「留給敢跟**我比吃辣的人**」 | **FP** | 「(我)…(X)人」籍貫句型把「比吃辣的」抽成地名 → user 籍貫 claim |
| 19 | gh3 r1 c2 | not_grounded | warmUp | 「妳這招我認。不過我真的沒在套話…」 | **FP** | 同 #16 |
| 20 | gh3 r2 | not_grounded | 三欄全掛 | 「這句話我可是留給敢跟我拼辣的人限定的」 | **FP** | 同 #16；連 coaching 都沒逐字重疊 |
| 21 | gh3 r3 c1 | not_grounded | warmUp+steady | 「這句嗆話是限量版…」 | **FP** | 同 #16 |
| 22 | gh3 r3 c2 | not_grounded | warmUp | 「妳這句話我認，確實有點通用」 | **FP** | 同 #16 |
| 23 | gh5 r0 c1 | unsupported:world:venue:located_at | steady「哈哈區」(conf=high) | 「**哈哈區**域不算太隱密啦」（賣關子、未報地點） | **FP** | 地名字尾「區」匹配到「區域」一詞中間 →「哈哈區」被當專名地點；候選刻意不報地點 |
| 24 | gh5 r0 c2 | unsupported:third_party:name:is_named | coaching「地點」 | 回覆「北邊，靠近捷運站」；coaching「先**給地點**」 | **TP-結果/FP-機制** | 候選確實捏造「北邊靠捷運站」該擋；但觸發的是「給地點」→假人名，真捏造「北邊/捷運站」逃過 venue extractor |
| 25 | gh5 r1 c1 | unsupported:world:venue:venue_named | steady「市區」 | 「**在市區**啦」 | **TP（弱）** | 「在市區」是模糊但仍屬未給定的地點宣稱；抽取位置正確 |
| 26 | gh5 r1 c2 | unsupported:world:venue:located_at | warmUp/steady「西門町」(conf=high) | 「**西門町**那間」 | **TP** | 明確捏造地點（fixture 從未給唱片行位置）；gate 教科書式命中 |
| 27 | gh5 r2 c1 | unsupported:world:venue:venue_named | coaching「這週半小時」 | 回覆兩句都賣關子未報地點；coaching「丟出『這週/半小時』的具體窗口」 | **FP** | 最新句問「在哪一區」→ asksPlace 啟動，coaching 引號片段被 contextualDirectAnswerClaims 當成「直接報地點的答案」 |
| 28 | gh5 r2 c2 | unsupported:user:schedule:available_at | warmUp/steady「下週」 | 「南邊，靠近捷運站，**我下週**可以帶妳去」「我下週有空」 | **TP-結果/機制存疑** | 候選確實捏造「南邊靠捷運站」（coaching 還宣稱『不編造，用已知的南邊』＝幻覺出處）該擋；但實際觸發的是「我下週有空」＝用戶自己的邀約措辭（政策上是否該擋有爭議），真捏造地點又逃過 venue extractor |
| 29 | gh5 r3 c1 | unsupported:world:venue:located_at | coaching「時候答區」(conf=high) | 回覆兩句都不報地點（我帶路）；coaching「這**時候答區**域反而洩氣」 | **FP** | 同 #23，「區域」被字尾切出「時候答區」當專名地點 |
| 30 | gh5 r3 c2 | unsupported:world:venue:venue_named | coaching「老闆推薦卡黑膠味道」 | 回覆「北邊，騎車 10 分鐘左右」 | **TP-結果/FP-機制** | 候選確實捏造「北邊＋騎車10分鐘」該擋；但觸發錨點是 coaching 裡「老闆推薦卡/黑膠味道」（對話裡真有的元素被壓縮黏成假店名），真捏造再次逃過 extractor |

## Gate 彙總

| gate 代碼 | 總數 | FP | TP（含結果面） | FP 率 |
|-----------|------|----|----|------|
| hint_quality_invalid_not_grounded | 10 | 10 | 0 | **100%** |
| unsupported_detail:third_party:name:is_named | 6 | 5 | 1（#24 結果面） | **83%**（機制面 6/6＝100% 誤觸） |
| hint_bossy_pasteable_reply | 4 | 4 | 0 | **100%** |
| unsupported_detail:world:venue:located_at | 3 | 2 | 1（#26 西門町） | 67% |
| unsupported_detail:world:venue:venue_named | 3 | 1 | 2（#25 弱、#30 結果面） | 33% |
| unsupported_detail:partner:schedule:available_at | 1 | 1 | 0 | 100% |
| unsupported_detail:user:preference:likes | 1 | 0 | 1（#5） | 0% |
| unsupported_detail:user:residence:hometown_is | 1 | 1 | 0 | 100% |
| unsupported_detail:user:schedule:available_at | 1 | 0 | 1（#28 結果面/機制存疑） | 0%（結果面） |
| **合計** | **30** | **24** | **6** | **80%** |

機制面更嚴：30 筆中僅 3 筆（#5 咖啡愛好者、#25 市區、#26 西門町）是「觸發錨點＝真捏造本體」；
另外 3 筆 TP-結果（#24/#28/#30）全靠別的誤判錨點湊巧攔下，真捏造（北邊/南邊/靠捷運站/騎車10分鐘）本身逃過 venue extractor。

## 假陽性 heuristic 根因（檔案:行號）

1. **「給＋抽象名詞」→ 第三方人名**（#1/#3/#4/#6/#7/#24，6 筆）
   `supabase/functions/practice-chat/hint_fact_ledger.ts:1085`——thirdPartyNamePatterns 送收語境
   `/(?:(?:傳|發|送|丟)(?:給)?|轉給|交給|給)\s*([漢字]{2,20})(?=標點)/`：
   - 裸「給」直接吃 coaching 慣用語「給接納感/給認同/給予理解/給地點」；
   - 「發」匹配「發現」的「發」→ 切出「現的」。
   `looksLikePersonName`（同檔 :595）名詞黑名單沒涵蓋這些抽象詞 → conf=high fail-closed 硬殺。
   排除清單 `THIRD_PARTY_SEND_CONTEXT_LOW_CONFIDENCE_TOKENS`（:627）只有 8 個歷史詞條，蓋不住。

2. **not_grounded＝純詞面 n-gram ∩ 只認最後一句**（10 筆全 FP）
   `supabase/functions/practice-chat/practice_visible_quality.ts:239-269`（`assertPracticeTextGroundedInTurns`，
   latestOnly 在 :246-248 只取最後一句 ai；`evidenceFragments` :192-231 取 2/3/4-gram 逐字比對）。
   兩種誤殺型態：
   a. 語意轉述無逐字重疊（「還停在第三章」→「卡住」、「很嚴格」→「標準」、回應質問句）；
   b. 逐字引用了「較早輪次」的對話（gh2 #12/#14 引用第 2 句）照樣被殺——有憑有據但輪次不對。
   gh3 六筆全是「回應她的指控句」本質上不需要複讀她的用詞，是此 gate 最系統性的盲區。

3. **裸 `/交作業/` 不分方向**（4 筆全 FP）
   `supabase/functions/practice-chat/hint.ts:1404`（bossyPatterns）＋ softenedRepairPatterns（:1385-1390）只豁免
   「不用/別…交作業」。gh2 fixture 她自己立了「我可是很嚴格的」評審框架，模型順勢說「我去交作業」＝
   用戶向她示弱的玩笑，方向與 bossy（指使對方交答案）完全相反。`/及不及格/` 同型風險。

4. **地名字尾在詞中間切割：「區域」→「哈哈區」「時候答區」**（#23/#29）
   `supabase/functions/practice-chat/hint_fact_ledger.ts:1741-1745`（namedPlacePatterns 字尾表 `站|路|街|巷|區|…`）
   ＋ `isLikelyProperPlaceAnchor`（:659）stem≥2 即判專名 → conf=high。字尾匹配沒有防「後一字仍是漢字構詞
   （區域/站著/山頂）」的 lookahead。

5. **asksPlace 啟動後，coaching 任意引號/片語被當「直接報地點的答案」**（#27，及 #24/#28/#30 的伴生垃圾錨點）
   `supabase/functions/practice-chat/hint_fact_ledger.ts:2396`（`contextualDirectAnswerClaims`）、asksPlace :2445、
   candidatePatterns :2461-2469——最新句一問「在哪一區」，候選 coaching 中的引號片段（「一起去被推薦」
   「這週/半小時」）與壓縮黏連片語（「老闆推薦卡黑膠味道」「確認可行性」「心動後的具體好奇」）全被抽成
   venue claim。`isNonAssertiveCoachingVenueMention`（:2411）只豁免帶「附近/旁邊」的子句，蓋不住。

6. **「(我)…X人」籍貫句型吃修飾子句**（#18）
   `supabase/functions/practice-chat/hint_fact_ledger.ts:887-890`（residenceParaphrases 第三式
   `(ACTOR)…(?:是)?(PLACE_VALUE)人`）——「敢跟我比吃辣的人」→ ACTOR=我、地名=「比吃辣的」。
   PLACE_VALUE（:114）允許「的」等功能字，無地名形態檢查。

7. **SCHEDULE_STATUS 含單字「能」，詞中匹配「能量」**（#2）
   `supabase/functions/practice-chat/hint_fact_ledger.ts:125-126`（SCHEDULE_STATUS 含 `能|可以`）＋
   directSchedulePatterns（:1370-1394）——「她今天能量沒那麼高」→「她/今天/能」抽成 partner available_at。

## 真陽性清單（該擋的捏造）

- **#5 bh3**：替用戶捏造自我揭露「我之前也想過要戒（咖啡）…接受自己是咖啡愛好者」——逐字稿中用戶從未談自己的咖啡史。
- **#26 gh5**：捏造唱片行在「西門町」（fixture 從未給位置）——唯一教科書式正確命中。
- **#25 gh5**：捏造「在市區」（弱、但仍是未給定的位置宣稱）。
- **#24/#28/#30 gh5**：捏造「北邊靠近捷運站」「南邊靠近捷運站（coaching 還謊稱『用已知的南邊』）」「北邊騎車 10 分鐘」——
  三筆都該擋，但 venue extractor 全沒抓到這些方位句（「北邊/南邊」無地名字尾），是靠別的 FP 錨點湊巧攔下。
  → extractor 對「方位詞＋捷運站/騎車 N 分鐘」型捏造存在**漏抓**（false negative）盲區。

## 附帶觀察

- gh5 fixture 本身把模型逼進死角：最新一句就是「唱片行在哪一區？」，而 fixture 從未給位置。模型只有
  「捏造地點（真違規）」或「迴避/賣關子（被 asksPlace 垃圾錨點誤殺）」兩條路，8 發全部至少被打回一次。
  eval 層面可考慮在 fixture 給 sceneContext 供地點出處，或接受此 fixture 天然高 reject 率。
- debrief 側（40 發）零 rejectedCandidates。
- 附帶漏抓：#11 warmUp「拍出師才敢嗆」也被抽成 hometown claim（bossy 先炸才沒記錄）——根因同 #18。

重放工具：`scratchpad/replay_gates.ts`（deno，只讀不改專案檔）。
