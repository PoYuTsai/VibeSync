# 第 5 輪 eval debrief 側 rejectedCandidates 全量判定（2026-07-23T01-11-35-559Z.json）

方法：`replay_debrief.ts`（deno，import 專案 gate 模組，以 eval 同款 context 逐欄重放：
temperature leak 詞定位＋ledger claim 錨點＋grounding 逐欄），full output＝`replay_debrief_out.txt`。
debrief 側共 **76 筆**被拒候選（38 shots × 每 shot 2 attempts 全滅；beginner 18 shots、game 20 shots，bd2 r2/bd3 r2 兩發成功故缺席）。
另補判 hint 側 `invite_route`（結論：**原文未被記錄**，見 §4）。

判定口徑同 round4：FP＝自然措辭被誤判；TP＝候選確實違規/捏造；TP-機械＝gate 照規格正確執行（非 heuristic 誤判）。

## 1. Gate 彙總（recorded code 口徑）

| gate | 總數 | FP | TP/該擋 | FP 率 | 一句話根因 |
|---|---|---|---|---|---|
| field_not_grounded | 20 | 20 | 0 | **100%** | 分析欄位＝後設評語（投入度/單向/缺自揭），詞面 n-gram 檢查天生不適用；且證據窗只取最後 8 句，引用前段對話照殺 |
| suggested_line_not_grounded | 11 | 8 | 3 | 73% | latestOnly 詞面重疊；引用較早輪次/語意轉述被殺。3 筆該擋＝meta 句混進貼句（「下次見面時，可以說：…」）＋捏造使用者近況 |
| temperature_leak | 11 | 1 | 10 | 9%* | 10 筆「框架」＝gate 照詞表正確執行，但 9/10 在 game route、**源頭＝prompt 自己把禁詞列字＋FSM 策略行注入**；1 筆「篩選法」（挑片標準）＝多義詞語言誤殺 |
| unsupported:third_party:name:is_named | 6 | 6 | 0 | **100%** | 同 round4 根因：給/丟/發/傳＋抽象詞→假人名（沙發→「發」、丟的測試、給的球、傳給妳） |
| unsupported:user:pet:has_pet | 6 | 6 | 0 | **100%** | 引用她的「養狗…」原話/用「你」稱呼她 → 無主詞「養狗」預設 owner=user，與她的既有寵物事實衝突判捏造 |
| unsupported:world:venue:located_at | 5 | 5 | 0 | **100%** | 同 round4 字尾詞中切割：「市集」→「…市」、「街道」→「出街」；gd5 市集在逐字稿裡本來就有 |
| unsupported:partner:schedule:available_at | 4 | 4 | 0 | **100%** | 逐字稿真有「我這週六下午剛好有空」；anchor 粒度不一致（這週 vs 週六下午 vs 週六）＋「沒有立即確認」的「沒有」翻 polarity（probe 實證） |
| unsupported:partner:preference:likes | 4 | 4 | 0 | **100%** | 「她喜歡的X」所有格被捲進錨點（「的」「的旅行」「的場景感」），profile 明載的興趣比對不上 |
| game_breakdown_missing_fields | 5 | 0 | 5 | 0% | TP-機械：模型整包沒給 gameBreakdown；**全集中在失敗局 gd3×3、gd4×2** |
| unsupported:partner:preference:favorite | 1 | 1 | 0 | 100% | 「導演優先」（逐字稿）→「她的最愛導演」語意同源但識別不匹配 |
| unsupported:shared:residence:lives_in | 1 | 1 | 0 | 100% | **幻影錨點「台北」**：「那我們幾點在展覽附近碰面」命中「我們…在…附近」同住 commonality 規則→掛上 profile 的 partner 台北→shared 無雙邊支持判捏造 |
| unsupported:user:schedule:available_at | 1 | (1) | (1) | 政策爭議 | 「我週三晚上有空」＝邀約提案語（她嗆「排進我的行程」）；機制如實但政策上封死所有具體邀約句 |
| overlong | 1 | 0 | 1 | 0% | TP-機械：summary 124 字 > 120（微超） |
| **合計** | **76** | **56** | **20** | **74%** | |

*temperature_leak 的 FP 率以「語言誤殺」計；「框架」10 筆屬 gate 正確、prompt 自傷（修 prompt 不修 gate）。

## 2. temperature_leak 懸案定位（優先項）

漏詞統計：**「框架」10 筆／「篩選」1 筆**（再無其他詞）。分佈：game 9、beginner 2。

洩漏樣句：「框架清晰，投入度適當」「框架穩定」「框架成立」「框架需重建」「聊天框架」「邀約框架」「時間框架」（gd1×3、gd2×2、gd3×2、gd4×1、gd5×1、bd3×1）；「妳這套導演+預告的**篩選**法我要學起來」（bd4，她的挑片標準＝日常中文，非機制語→純誤殺）。

源頭（兩個，皆 prompt 注入）：

1. **禁詞清單本身列字**：`supabase/functions/practice-chat/prompt.ts:229`
   「所有欄位一律白話：絕不出現內部詞（frozen/cold/…、推拉、篩選、賦格、可得性、**框架**；唯「框架掉了」可用）」——
   這行**只接在 GAME_DEBRIEF_SYSTEM_PROMPT 上**（beginner prompt 沒有），把 10 個禁詞逐字餵給模型（粉紅大象效應）。
   對照組完美：有這行的 game route 20 shots 洩 9 筆；沒這行的 beginner 18 shots 只洩 2 筆（且其一是「篩選法」多義誤殺）。
   模型還學會了 sentinel：gd3 r2c2 的 dateChanceReason 寫「框架掉了」（合法放行）——證明模型就是從這行學到「框架」語彙。
2. **FSM persona 策略行殘留機制詞**：game debrief prompt 經 `prompt.ts:577`（`phaseRelevantGameStrategyPrompt`，:540）注入
   gameStrategy 行，其中 cool_rational 的 tensionStyle＝「用**穩定框架**和聰明留白做張力」（`game_fsm.ts:1196`）、
   testStyle＝「冷靜**篩選**測試…」（`game_fsm.ts:1180`）；另有「一點不**可得性**」（`game_fsm.ts:1103`）。
   gd3（cool_rational）的 2 筆框架洩漏與此對得上。

結論：gate 本身照詞表正確執行；要止血得改 prompt——禁詞指令改成不列字（或只列 Latin 詞），並清洗 game_fsm 策略行的機制詞。

## 3. 逐筆判定表（76 筆，依 fixture 排）

格式：fixture r# c#｜recorded code｜觸發欄位＋錨點/漏詞｜判定｜關鍵句。
（詳細逐欄 evidence 見 replay_debrief_out.txt 同名區塊）

### beginner_debrief（38 筆）
| # | 筆 | code | 觸發 | 判定 |
|---|---|---|---|---|
| 1 | bd1 r0c1 | field_not_grounded | strengths[0]「跟我一樣/賴床」在第 3 句（8 句窗外）＋評語欄無詞面重疊 | FP |
| 2 | bd1 r0c2 | third_party:name | suggestedLine「家裡沙**發**還是床上」→發+「還是床上」假人名 | FP |
| 3 | bd1 r1c1 | field_not_grounded | dateChanceReason 投入度評語 | FP |
| 4 | bd1 r1c2 | field_not_grounded | summary/strengths/dateChanceReason 評語無重疊 | FP |
| 5 | bd1 r2c1 | field_not_grounded | dateChanceReason/nextInviteMove 評語 | FP |
| 6 | bd1 r2c2 | suggested_line | 「有時候什麼？…」接第 10 句（非最新句） | FP |
| 7 | bd1 r3c1 | field_not_grounded | summary/dateChanceReason/nextInviteMove | FP |
| 8 | bd1 r3c2 | field_not_grounded | 同上＋watchouts | FP |
| 9 | bd2 r0c1 | third_party:name | watchouts「**丟**的測試」→「的測試」、dateChanceReason「丟**回來投入**」 | FP |
| 10 | bd2 r0c2 | third_party:name | suggestedLine「週一**傳給妳**」→「給妳」假人名（傳給對方本人！） | FP |
| 11 | bd2 r1c1 | third_party:name | summary「她開玩笑**丟測試**」→「測試」（排除清單只有「小測試」） | FP |
| 12 | bd2 r1c2 | partner:preference:likes | nextInviteMove「用她喜歡**的**『美食、旅行…」→錨點「的」 | FP |
| 13 | bd2 r3c1 | overlong | summary 124>120 | TP-機械 |
| 14 | bd2 r3c2 | suggested_line | 「等我整理好，先分享給妳…」（接歌單驗貨語境、非最新句詞面） | FP |
| 15 | bd3 r0c1 | field_not_grounded | nextInviteMove 評語 | FP |
| 16 | bd3 r0c2 | partner:preference:likes | watchouts「她喜歡**的旅行**」（profile 明載興趣） | FP |
| 17 | bd3 r1c1 | suggested_line | 「等妳成功那天，不如烤好帶一個出來…」接她成功照約定（前段） | FP |
| 18 | bd3 r1c2 | suggested_line | 「下次可以先說你自己最近在做什麼，或問她…」＝**meta 建議句混進貼句欄** | **TP-結果**（該擋，但該由 meta_line gate 抓） |
| 19 | bd3 r3c1 | field_not_grounded | watchouts 評語 | FP |
| 20 | bd3 r3c2 | temperature_leak | watchouts「邀約**框架**還很虛」 | TP-機制（詞表 WAI；beginner 無 prompt 注入＝模型自帶行話） |
| 21 | bd4 r0c1 | temperature_leak | suggestedLine「導演+預告的**篩選**法」＝挑片標準日常語 | **FP**（多義詞誤殺） |
| 22 | bd4 r0c2 | partner:preference:likes | strengths「她喜歡**的場景感**」 | FP |
| 23 | bd4 r1c1 | field_not_grounded | summary/watchouts/dateChanceReason（「她提到的旅行美食」＝profile 興趣，措辭小errant） | FP |
| 24 | bd4 r1c2 | suggested_line | 「我最近也想找部後勁強的片…」（後勁強在第 6 句） | FP |
| 25 | bd4 r2c1 | venue:located_at | strengths「延伸**出街**道氛圍」→字尾「街」切進「街道」 | FP |
| 26 | bd4 r2c2 | field_not_grounded | watchouts/dateChanceReason 評語 | FP |
| 27 | bd4 r3c1 | field_not_grounded | summary/watchouts 評語 | FP |
| 28 | bd4 r3c2 | preference:favorite | nextInviteMove「她的最愛**導演**」vs 逐字稿「導演優先」 | FP |
| 29-34 | bd5 r0c1,r0c2,r1c1,r1c2,r2c1,r2c2 | user:pet:has_pet ×6 | 「**養狗**之後回不去我信」（引用她原話）／「**你**平常放假都帶布丁去哪」（你＝她被歸 user）→user 有狗 claim 與她的柯基衝突 | FP ×6 |
| 35 | bd5 r3c1 | field_not_grounded | summary/strengths/watchouts 評語 | FP |
| 36 | bd5 r3c2 | suggested_line | 「我也想試試被狗逼著早起…一起走一圈？」語意接最新句、無詞面重疊 | FP |

### game_debrief（38 筆）
| # | 筆 | code | 觸發 | 判定 |
|---|---|---|---|---|
| 37 | gd1 r0c1 | partner:schedule | phaseReached「她主動說出**週六下午**有空」（逐字稿事實！anchor 粒度 這週≠週六下午） | FP |
| 38 | gd1 r0c2 | partner:schedule | watchouts「她說『**這週**六下午有空』後**沒有**立即確認」→「沒有」翻 polarity | FP |
| 39 | gd1 r1c1 | shared:residence:lives_in | nextFirstLine「那我們幾點**在展覽附近**碰面」→commonality 規則誤判同住→掛 profile 台北 | FP |
| 40 | gd1 r1c2 | temperature_leak | summary「**框架**清晰」 | TP-機制（源＝prompt.ts:229 注入） |
| 41 | gd1 r2c1 | partner:schedule | watchouts「她說**週六**有空時」 | FP |
| 42 | gd1 r2c2 | temperature_leak | summary「**框架**穩定」 | TP-機制（同上） |
| 43 | gd1 r3c1 | partner:schedule | inviteDirection「接住她給的『**週六下午**有空』」 | FP |
| 44 | gd1 r3c2 | temperature_leak | summary「**框架**成立」 | TP-機制（同上） |
| 45 | gd2 r0c1 | third_party:name | watchouts「**丟出小測試**」（繞過排除詞「小測試」）＋failureState「丟**回她那邊**」 | FP |
| 46 | gd2 r0c2 | temperature_leak | missedVariable「低壓邀約**框架**」 | TP-機制（同上） |
| 47 | gd2 r1c1 | suggested_line | 「行動證明？那這週六約妳打一場…」接她第 10 句挑戰（非最新句） | FP |
| 48 | gd2 r1c2 | user:schedule | suggestedLine「我**週三晚上**有空，妳那時段剛好嗎」＝邀約提案語 | 政策爭議（機制如實；封死具體邀約句） |
| 49 | gd2 r2c1 | field_not_grounded | summary/phaseReached 評語 | FP |
| 50 | gd2 r2c2 | suggested_line | 「那週三晚上怎樣，我找場地…」回應她「排進我的行程」 | FP |
| 51 | gd2 r3c1 | third_party:name | summary「沒接住她**給的球**」→「的球」假人名 | FP |
| 52 | gd2 r3c2 | temperature_leak | inviteDirection「時間**框架**」 | TP-機制（同上） |
| 53 | gd3 r0c1 | breakdown_missing | gameBreakdown 整包缺 | TP-機械 |
| 54 | gd3 r0c2 | temperature_leak | summary「**框架**需重建」＋dateChanceReason「互動**框架**不適」 | TP-機制（cool_rational 另有 game_fsm.ts:1196「穩定框架」注入） |
| 55 | gd3 r1c1 | breakdown_missing | 整包缺 | TP-機械 |
| 56 | gd3 r1c2 | partner:preference:likes | dateChanceReason「沒有接住**旅行**興趣」（profile 載明）＋inviteDirection hometown 亂錨 | FP |
| 57 | gd3 r2c1 | breakdown_missing | 整包缺（另 watchouts「未**給自我揭露**」假人名為伴生） | TP-機械 |
| 58 | gd3 r2c2 | suggested_line | 「我最近也在規劃週末出去走走，**上次去的地方**景色不錯」＝捏造使用者近況 | **TP-結果** |
| 59 | gd3 r3c1 | field_not_grounded | strengths/nextInviteMove 評語 | FP |
| 60 | gd3 r3c2 | temperature_leak | nextInviteMove「聊天**框架**」＋inviteDirection「修復聊天**框架**」 | TP-機制（同上） |
| 61 | gd4 r0c1 | breakdown_missing | 整包缺 | TP-機械 |
| 62 | gd4 r0c2 | suggested_line | 「**下次見面時，可以說：**『…』」＝meta 前綴非貼句 | **TP-結果** |
| 63 | gd4 r1c1 | breakdown_missing | 整包缺 | TP-機械 |
| 64 | gd4 r1c2 | field_not_grounded | summary/watchouts/phaseReached/missedVariable 評語 | FP |
| 65 | gd4 r2c1 | field_not_grounded | summary/watchouts/nextInviteMove 評語 | FP |
| 66 | gd4 r2c2 | field_not_grounded | dateChanceReason/missedVariable/failureState 評語 | FP |
| 67 | gd4 r3c1 | field_not_grounded | watchouts 評語 | FP |
| 68 | gd4 r3c2 | temperature_leak | missedVariable「有時間**框架**的小場景」 | TP-機制（同上） |
| 69 | gd5 r0c1 | venue:located_at | suggestedLine「星期六下午**市**集門口見」→「星期六下午市」字尾切割（市集在逐字稿！） | FP |
| 70 | gd5 r0c2 | field_not_grounded | nextInviteMove/phaseReached 評語 | FP |
| 71 | gd5 r1c1 | venue:located_at | summary「聊到底片**市**」、strengths「順著**市**」等 | FP |
| 72 | gd5 r1c2 | temperature_leak | summary「**框架**清晰」＋missedVariable「模糊**框架**」 | TP-機制（同上） |
| 73 | gd5 r2c1 | venue:located_at | summary「順勢帶出**市**」 | FP |
| 74 | gd5 r2c2 | suggested_line | 「那我們先約看看…」回應她「說好了」無詞面重疊 | FP |
| 75 | gd5 r3c1 | venue:located_at | summary/suggestedLine「星期六下午約在**市**」 | FP |
| 76 | gd5 r3c2 | field_not_grounded | nextInviteMove 評語 | FP |

## 4. hint 側 invite_route ×6：原文未被記錄（記錄儀缺口）

第 5 輪 `hint_quality_invalid_invite_route` 出現 6 次（attemptFailureCodes）：
bh2 r1（×2→503）、bh2 r3（×2→503）、bh3 r2（×1）、gh1 r1（×1）——但這些 shots 的 `rejectedCandidates` 全是空的。

原因：`tools/practice_single_shot_eval/run_eval.ts` 的 validate 內，`rejected.push` 只包住
`parseHintResult`（:206-215 的內層 try）；`invite_route` 是之後 `buildHintDecision`
（:219-233；gate 本體在 `supabase/functions/practice-chat/hint.ts:839`（game）/:897（beginner））丟的，
逸出記錄儀 → **無法對這 6 筆做真偽判定**。同缺口也涵蓋 `semantic_invite_move`。
修法（eval 工具側）：把 decision 建構包進同一個 try，或在 validate 最外層 catch 統一 push。

旁證（非判定）：bh2＝爬山話題、familiarity 20 的 beginner，steady 槽 allowedRoute 再降一級；
候選大概率是「下次一起去爬山」類軟邀約被 not_ready 路由擋——屬政策 gate 而非 regex 誤判，但無原文不能下結論。

## 5. 順帶：第 5 輪 hint 側其他 24 筆（replay_gates_r5.ts 掃過）

全部落在 round4 已立案的根因家族，無新型態：
not_grounded 12（gh2/gh3 詞面重疊）、交作業 bossy 2、給妳/的角色感→假人名 2、
asksPlace 垃圾錨點（「一起去被推薦」「這週末改天」「診斷」）、真捏造被抓 2（「西門町」「北區捷運站」conf=high 教科書命中）。
新樣本強化兩個 round4 結論：「傳給妳」都會被抓成第三方人名；「妳如果這週有空」條件問句被抓成 partner schedule claim。

## 6. 新增根因清單（debrief 側新發現，檔案:行號）

1. **禁詞清單列字入 prompt（temperature_leak 主根因）**：`supabase/functions/practice-chat/prompt.ts:229`（只掛在 game debrief prompt）。
2. **FSM 策略行含機制詞**：`supabase/functions/practice-chat/game_fsm.ts:1196`（穩定框架）、:1180（冷靜篩選測試）、:1103（不可得性）；經 `prompt.ts:577`（phaseRelevantGameStrategyPrompt :540）注入 game debrief prompt。
3. **temperature_leak 詞表多義誤殺**：`supabase/functions/practice-chat/visible_text_guard.ts:143-152`（INTERNAL_MECHANISM_PHRASES 含「篩選」，殺掉「挑片篩選法」日常用語）。
4. **8 句證據窗＋評語型欄位詞面 grounding**：`practice_visible_quality.ts:239-269`（`turns.slice(-8)`＝:248）；debrief fixture 10-16 句，前段引用照殺；分析欄位本質是後設評語，n-gram 檢查天生高誤殺。
5. **無主詞「養X」預設 owner=user**：`hint_fact_ledger.ts:1223,1231`（pet 抽取）＋「你」一律歸 user（ACTOR 表 :111-112）——引用對方原話（「養狗之後回不去」）或用「你」稱呼她即中槍。
6. **SCHEDULE_DAY 交替序吃掉「這週六」**：`hint_fact_ledger.ts:121-124`（這週 排在 週六 前→「這週六下午」抽成「這週」）；候選寫「週六下午」即 identity 不匹配。probe 實證。
7. **polarityAt 負詞誤翻**：「她說『這週六下午有空』後**沒有**立即確認」→ claim polarity=negative（「沒有」修飾「確認」非「有空」）。probe 實證。
8. **「我們…在X附近」commonality 誤判同住**：`hint_fact_ledger.ts:2315-2318`（domains 含 residence）＋`addFromEvidence` 掛 profile 錨點（partnerFactClaimsFromProfile :1938-1942 的 city=台北）→「在展覽附近碰面」變 shared:lives_in:台北。
9. **likes 抽取吃所有格**：「她喜歡的旅行/的場景感/的」畸形錨點（likes 區 :1159-1214），profile 載明興趣也比對不上。
10. **eval 記錄儀缺口**：`tools/practice_single_shot_eval/run_eval.ts:206-233`——decision 階段（invite_route/semantic_invite_move）的被拒候選不進 rejectedCandidates。

工具：`replay_debrief.ts`、`replay_gates_r5.ts`、`probe_gd1.ts`、`probe_taipei*.ts`（皆只讀）。
