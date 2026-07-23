# 第 8 輪 eval 被拒候選全量判定（2026-07-23T05-25-32-053Z.json）

方法：`tools/practice_single_shot_eval/replay_rejected.ts` 逐筆重放（15 發帶被拒
候選、22 筆 code 全數重現 recorded code），invite 筆另以 deno 直接 import
`practice_invite.ts` 逐句實測分級＋逐 flag debug，並以 `invite_maturity.ts` /
`game_fsm.ts` 重算各 fixture 當下 allowed 階。判定口徑同 round7：
**FP**＝自然措辭被 heuristic 誤判；**TP/TP-機械**＝候選確實違規或 gate 照規格
執行；**裁決內**＝round6 四型分治明文不豁免的形狀。

本輪盤面：80 發＝first_shot 65、second_shot 8、503 7；beginner_debrief 100%/0
連兩輪綠、served 側詞表洩漏連兩輪 0。紅＝beginner_hint 85%（invite_route×5）、
game_hint 65%、game_debrief 75%。

## 0. 交接兩疑點的答案（先講結論）

- **① beginner_hint invite_route×5 是既有 FP 波動還是新家族？** 都對一半：
  4 FP 全有明確機械成因，其中兩個是**已立案家族的殘洞**（疑問補語「評估
  要不要出發」＝round6 疑問補語家族 invite 變體；「打算」的「打」被
  GENERIC_PROPOSAL 當提案動詞＝round6 單字動詞構詞家族殘洞），兩個是
  **新邊角**（意圖問句「還會(想)再爬/去嗎」問她自己的重複意願被當提案）。
  第 1 筆（bh2 r0 c1「下次鐵腿換我陪妳一起懷疑人生」）是真 soft 窗口，
  not_ready 階擋下＝TP-機械。非隨機波動，可修（已修）。
- **② game_hint invite×4 是「複用她原話字眼」教學的副作用嗎？** **證實，
  但機制與猜想不同**：不是複用「要不要/一起」邀約詞推高階，而是複用她
  原話「勉強可以跟你多聊**一點**」時，「一點」被 CONCRETE_TIME 的
  `[數字]{1,3}[點時]` 當成「一點鐘」→ 軟邀約（改天/下次）被高判成
  direct。gh4 的 FSM 實測 direction=soft_invite_probe、warmUp allowed=
  **soft**——去掉「一點」實測分級回 soft＝本來會過。結論：**該修 gate 的
  假時鐘，不該回退教學句**（教學方向正確，round8 gh3 質問型打回也從
  3 筆降到 2 筆）。

## 1. 逐筆判定表（22 筆）

### beginner_hint（5 筆，全 invite_route；bh2/bh3 maturity 實測＝not_ready→allowed none）

| # | 筆 | 觸發 | 候選關鍵句 | 判定 | 理由 |
|---|---|---|---|---|---|
| 1 | bh2 r0 c1 | warmUp 判 soft（下次＋一起） | 「下次鐵腿換我陪妳一起懷疑人生哈哈」 | **TP-機械** | 玩笑式未來共同活動仍是 soft 窗口，not_ready 階梯 WAI |
| 2 | bh2 r0 c2 | steady 判 soft（下次＋GENERIC「再爬嗎」） | 「下次還會想再爬嗎？」 | **FP（新邊角）** | 意圖問句：問她自己還會不會再爬，非提案 |
| 3 | bh2 r1 c1 | warmUp 判 soft（MUTUAL 裸「要不要」） | 「找教練陪你評估要不要出發啦哈哈」 | **FP** | 疑問補語家族（round6）invite 變體：「評估」的補語非邀約 |
| 4 | bh2 r1 c2 | warmUp 判 soft（「再去嗎」） | 「下次還會再去嗎？」 | **FP** | 同 #2 意圖問句 |
| 5 | bh3 r3 c1 | warmUp 判 **direct**（GENERIC 中「打算」的「打」＋句尾吧） | 「妳這是打算跟咖啡過一輩子了吧？」 | **FP** | round6 單字動詞構詞家族殘洞：lookbehind 只排被/挨，沒 lookahead 排「打算/打卡」 |

### game_hint（9 筆）

| # | 筆 | code | 候選關鍵句 | 判定 | 理由 |
|---|---|---|---|---|---|
| 6 | gh2 r1 c1 | not_grounded | steady「好啊那就這麼說定了，妳先幫我訂個及格標準」 | **FP（殘留）** | 回應句家族：接她「我可是很嚴格的」挑戰，天然零詞面重疊（同 round7 #1） |
| 7 | gh2 r1 c2 | invite_route | steady「我們一起出去拍？」 | **TP-機械** | 真邀約；P2 實測 direction=no_invite_build_investment→allowed none；coaching 自己都寫「這輪先不硬約」（同 round7 #3） |
| 8 | gh3 r0 c1 | not_grounded | 「這句只對敢嗆我的人講，妳算稀有物種」 | **裁決內** | 質問型不豁免（round6 裁決）；教學句收斂部分生效（3→2 筆），候選仍整句換新詞 |
| 9 | gh3 r1 c1 | not_grounded | 「哈只對敢接招的人才這樣講話」 | **裁決內** | 同 #8 |
| 10 | gh4 r0 c1 | invite_route | warmUp「下次見面當開場曲，改天一起聽？」 | **FP（新家族：假時鐘）** | 引她原話「多聊**一點**」→CONCRETE_TIME 判一點鐘→soft 高判 direct；P4 allowed=soft 本來會過 |
| 11 | gh4 r2 c1 | invite_route | warmUp「該再加**一點**？…改天請妳喝咖啡」 | **FP** | 同 #10；去「一點」實測=soft=allowed |
| 12 | gh4 r2 c2 | invite_route | warmUp「好幾首**在等妳**的評分」＋steady「下次一起聽新歌」 | **TP-機械（複合）** | warmUp＝FP（「(在\|到)…等妳」設計抓到場等人，被擬人「在等妳的◯◯」誤中，已修）；但 steady 真 soft 邀約超 steady 降階（build）獨立致死＝候選層級 TP |
| 13 | gh5 r1 c1 | game_contract | coaching 寫「低壓邀約**階**」 | **TP-機械（邊界）** | 八個階段關鍵詞（階段/開場/測試/投入/熟悉/安全/窗口/這輪）全缺，契約字面 WAI；**潛伏 FP**＝warmUp「只知道**路過**」被切出 located_at 錨點「只知道路」（「路」家族第三邊角，已修） |
| 14 | gh5 r2 c1 | not_grounded | steady「位置我一時說不準…我直接帶妳去比較快」 | **FP** | 回應句家族：她問「哪一區」→誠實迴避＋轉邀約＝coaching 教的正確打法，零重疊被殺；另含「一時」假時鐘潛伏（已隨 #10 修）；admission 措辭屬合法誠實迴避，非 Minor ① 繞道 |
| 15 | gh5 r2 c2 | game_contract | coaching 寫「**遊戲**心法」 | **TP-機械** | 非字面「Game心法」，契約 WAI |

### game_debrief（7 筆）

| # | 筆 | code | 候選關鍵句 | 判定 | 理由 |
|---|---|---|---|---|---|
| 16 | gd1 r0 c1 | venue:located_at | suggestedLine「週六下午約**市區**某展場附近」 | **TP（輕）** | 逐字稿有展覽/週六下午有空/請飲料，沒有「市區」；「某」有遮但仍添逐字稿外地點資訊，合約內 |
| 17 | gd2 r1 c1 | third_party:name | missedVariable「是**丟球給你接**」 | **FP** | 裸「丟」假人名家族（round7 #6）第四字尾：切出「球給你接」；修＝人名不含與格「給」＋字尾補「球」 |
| 18 | gd2 r1 c2 | suggested_line_not_grounded | 「下週三晚上七點，我們那邊球館，你來試試？」 | **FP** | 回應句家族 debrief 版：她指名要「行動證明」「排進我的行程」→具體時間提案天然零重疊（round7 #9 預警擴散證實）；註：「我們那邊球館」夾帶輕度新事實，修 grounding 後此句仍可能被 ledger 收 |
| 19 | gd2 r3 c1 | game_breakdown_not_grounded | nextFirstLine「這週六下午找場地，我們單挑一場如何？」 | **FP** | 同 #18 |
| 20 | gd3 r1 c1 | suggested_line_not_grounded | 「換我說，我週末通常是耍廢跟找店吃飯，妳呢？」 | **FP** | 回應她「你也可以說說你自己」＝round7 #9 伴生預言精準命中；自我揭露句無從重疊 |
| 21 | gd3 r2 c1 | suggested_line_not_grounded | 「那我先說：我週末通常會亂晃找新開的店，妳咧？」 | **FP** | 同 #20 |
| 22 | gd3 r2 c2 | user:lifestyle:does_activity | 「我最近也在計畫**週末小旅行**，妳上次去哪裡？」 | **TP** | 捏造使用者事實＋預設她有旅行（她原話「大多在家休息」），gate 正確 |

## 2. Gate 彙總（22 筆＝FP 13／TP·TP-機械 7／裁決內 2）

| 家族 | 筆數 | FP | 一句話根因 |
|---|---|---|---|
| 假時鐘「一點/一時」（新家族） | 2＋2 潛伏 | 2 | 程度副詞/慣用語被 `[數]{1,3}[點時]` 當報時，soft 高判 direct；「複用原話」教學放大觸發面 |
| 意圖問句「還會(想)再V嗎」（新邊角） | 2 | 2 | 問她自己的重複意願被 GENERIC_PROPOSAL 當提案 |
| 疑問補語「評估要不要」 | 1 | 1 | round6 家族 invite 變體 |
| 構詞切割「打算」 | 1 | 1 | round6 單字動詞家族殘洞 |
| 擬人「在等妳的◯◯」 | 1（複合筆） | 1 | 「(在\|到)…等妳」缺賓語檢查 |
| 回應句家族（grounding） | 6 | 6 | 她的挑戰/請求指定要新內容（行動證明/說說你自己/報位置），合法回應天然零重疊；**本輪最大 FP 家族且擴散到 debrief 建議句** |
| 裸「丟」假人名 | 1 | 1 | round7 #6 家族第四字尾「球」＋與格「給」 |
| 邀約超階（invite TP） | 3 | 0 | 速約階梯 WAI（P2 真邀約、not_ready soft 窗口、steady 降階） |
| game_contract 字面 | 2 | 0 | 「遊戲心法」≠「Game心法」、「邀約階」缺八關鍵詞；契約 WAI，2/80 頻率留觀察 |
| unsupported TP | 2 | 0 | 「市區」添地點、「週末小旅行」捏造且與她原話矛盾 |

## 3. 隨判定落地的修復（本 commit 系列）

1. `practice_invite.ts` CONCRETE_TIME/CLOCK_TIME：裸「一點/一時」不當時鐘
   （僅「一點半/鐘/整」入報時；真報時幾乎必帶時段詞而時段詞本身已中）→ #10/#11 修、#14 潛伏防。
2. `practice_invite.ts` INTENT_QUESTION_CLAUSE：剝「還?會想?再V…嗎」
   （子句含「我」不剝）→ #2/#4 修。
3. `practice_invite.ts` MUTUAL_CUE：「要不要」前置認知動詞（評估/考慮/決定/
   研究/糾結/煩惱）lookbehind → #3 修。
4. `practice_invite.ts` GENERIC_PROPOSAL：「打」補 lookahead（算/工/字/掃/卡/
   招呼/氣/擊）→ #5 修。
5. `practice_invite.ts` ADDRESSEE_PLAN_CUE：「(在|到)…等妳」補 `(?![的回])` → #12 warmUp 分支修。
6. `hint_fact_ledger.ts`：人名候選含「給」即排除＋字尾補「球」→ #17 修。
7. `hint_fact_ledger.ts`：兩處地名 pattern「路」lookahead 補「過」＋
   NON_PLACE_COMPOUND_TAIL 補「知道路」→ #13 潛伏修。
8. `prompt.ts` debrief 建議句教學補「必須扣回原話：至少複用她最後幾句的一個
   具體字眼」（與 round7 hint 質問教學同招，從 prompt 側收斂回應句家族
   debrief 版）；Debrief+Hint prompt 上限 6000→6100（prompt_test 註記）。
9. 回歸測試：`practice_invite_test.ts` round8 六 FP 樣句＋真報時/軟邀約回歸、
   `hint_fact_ledger_test.ts` round8 丟球/路過兩案。

**不修**（記錄供觀察）：#1/#7/#12(steady)/#13/#15 invite 與 contract TP（WAI）；
#16/#22 unsupported TP（gate 正確）；#6 hint 側回應句殘留（round7 拍板觀察，
hint 側本輪僅 1 筆不破盤）；game_contract 字面違規 2/80（模型漂移，教學已夠
明確，再現升頻才考慮 prompt 強化）。

## 4. 修後重放驗證

7 筆 FP 轉 PASS（#2/#3/#4/#5/#10/#11/#17）；#12 warmUp 分支清除（候選仍死於
steady TP，符合預期）；#13 潛伏 unsupported 錨點消失（僅剩 contract code）；
回應句家族 6 筆重放照舊被拒——修在 prompt 教學側，只對**新生成**生效，
重放舊候選翻不了屬設計內。其餘 TP/裁決內全數照舊。全套 Deno 1014 綠
（1012＋新增 2 回歸測試）。

## 5. 下一步

第 9 輪三軸目標：beginner_hint 回 100%（4 FP 已修＋1 TP 屬模型偶發）、
game_hint 看假時鐘修復＋教學句雙效（不確定因素＝回應句殘留與質問型裁決內
打回的輪間頻率）、game_debrief 看「扣回原話」教學能否把建議句 grounding FP
壓下去。連同 round6/7/8 三份判定表與 relax 清單進 Batch I Codex 雙審。
