# 第 10 輪 eval 被拒候選全量判定（2026-07-23T07-30-45-501Z.json）

方法同 round8/9（replay_rejected.ts＋jq 抽候選原文＋scratchpad deno probe 逐
flag 實測）。10 發帶被拒候選、16 筆候選全數離線重現。盤面：四路首發全 85%、
洩漏**四輪連續 0**、bd 503=0（missing_fields×1＋timeout×2 皆機械重試成功）；
紅＝bh 2×503（invite×5，round9 預測回 100% 落空——同家族**新變體**非舊洞
回退）、gh 2×503（not_grounded×4＋located_at×1）、gd 2×503（is_named×1＋
temperature_leak×2＋not_grounded×1＋unsupported×1）。

## 1. 逐筆判定（16 筆＝FP 修 7／FP 殘留觀察 3／裁決內 1／TP·TP-機械 5）

| # | 筆 | code | 關鍵句 | 判定 | 根因 |
|---|---|---|---|---|---|
| 1 | bh2 r2 c1 | invite | warmUp「下次爬山前要不要先簽切結書」 | **FP（修）** | 玩笑建議：MUTUAL_CUE「要不要」後無共同行動詞仍當提案 |
| 2 | bh2 r2 c2 | invite | warmUp「下次還敢去嗎？」 | **FP（修）** | 意圖問句新變體：「敢」在動詞前，round8 語尾排「敢」與 round9「還會想去嗎」剝除式都擋不到 |
| 3 | bh2 r3 c1 | invite | steady「下次還會被拖去嗎？」 | **FP（修）** | 意圖問句被動變體：拖她去的是朋友，「被拖去」不在剝除式動詞位 |
| 4 | bh2 r3 c2 | invite | warmUp/steady「下次還會被拖去嗎」「朋友下次還會約妳嗎」 | **FP（修）** | 同 #3＋第三方主詞：「朋友…約妳」被 ADDRESSEE_PLAN_CUE「約妳」當成我在約她 |
| 5 | bh3 r1 c1 | invite | warmUp「繼續喝吧」 | **FP（修）** | 勸延續句：「繼續＋喝＋吧」被 GENERIC_PROPOSAL 當提案直判 direct（round9「喝下去吧」的孿生，繼續在動詞前） |
| 6 | gh1 r2 c1 | not_grounded | steady「妳平常看書都是慢慢咀嚼型的嗎？」 | **FP（殘留觀察）** | 回應句家族 hint 側（回她提問後轉話題，零詞面重疊） |
| 7 | gh1 r2 c2 | not_grounded | steady「我也是被妳那天的評論勾到…妳現在讀到哪邊了？」 | **FP（殘留觀察）** | 同 #6 |
| 8 | gh3 r3 c1 | not_grounded | steady「被抓包了嗎哈…妳算通過第一關」 | **裁決內** | 質問/測試反打型（round6 裁決不豁免） |
| 9 | gh5 r2 c1 | unsupported venue:located_at | coaching「**不要一路**追問她要不要去」 | **FP（修）** | 副詞「一路」被路名 pattern 當街道（「一點」假時鐘的孿生：「一路」假地點），anchor=「不要一路」conf=high |
| 10 | gh5 r2 c2 | not_grounded | steady「我也不太記得確切位置，但可以一起去探險」 | **FP（殘留觀察）** | 誠實迴避＋轉邀約＝coaching 教的正確打法（round7 拍板觀察，同 round9 #12） |
| 11 | bd1 r2 c1 | missing_fields | — | **TP-機械** | 欄位缺漏，重試即成功 |
| 12 | gd2 r1 c1 | unsupported third_party:name:is_named | watchouts「是**丟球**考驗你」 | **FP（修）** | 裸「丟」送收 pattern 把「丟球」比喻抓成第三方人名（anchor=「球考驗你」；round8 修的是與格「丟給」＋「丟出」，裸「丟球」漏網） |
| 13 | gd2 r1 c2 | temperature_leak | 「邀約**框架**」×3 欄位 | **TP（WAI）** | 「框架」＝拍板守門詞（PUA 原詞，第 6 輪 leak 源頭；唯一放行 sentinel「框架掉了」）；gate 正確擋 |
| 14 | gd3 r2 c1 | suggested_line_not_grounded | 「哈哈被抓包了，那換我…」 | **TP** | 建議句未扣回她原話字眼（round8 教學要求），gate 正確擋 |
| 15 | gd3 r2 c2 | unsupported user:lifestyle | 「我最近也在規劃**週末小旅行**，上次去花蓮」 | **TP** | 捏造用戶行程/花蓮經歷，正是 fact gate 存在目的 |
| 16 | gd5 r3 c1 | temperature_leak | 「任務**框架**」×2 欄位 | **TP（WAI）** | 同 #13 |

## 2. 隨判定落地的修復（本 commit）

1. `practice_invite.ts` INTENT_QUESTION_CLAUSE：補「還?敢再?」變體＋被動填充
   `(?:被[^我…]{0,3})?`（「被我拖去」含我不剝，仍算邀約）→ #2/#3。
2. `practice_invite.ts` 新增 THIRD_PARTY_INVITER_CLAUSE 剝除式：子句開頭
   「朋友/他她＋約|找|接|載|帶|請＋妳」整句剝（限子句開頭，「我帶朋友去找妳」
   不受影響）→ #4。
3. `practice_invite.ts` MUTUAL_CUE：「要不要」補 lookahead——12 字內必須接得上
   共同行動詞（一起/去/來/出來/吃喝看逛…/跟我/找我）才算提案 → #1。
4. `practice_invite.ts` GENERIC_PROPOSAL：看|吃|喝|玩 補 `(?<!繼續)` → #5。
5. `hint_fact_ledger.ts` 路名 anchor 排除：`/(?:^|不|別|就|還|都|但|才|又|再|要|直)一路$/`
   （真路名「民生一路」前一字是專名構詞不在此列，回歸測試守住）→ #9。
6. `hint_fact_ledger.ts` 裸「丟」lookahead 補「球」→ #12。
7. 回歸測試：practice_invite_test 新增 round10 家族 5 句＋2 真陽性守門、
   hint_fact_ledger_test 新增一路/丟球＋真路名保留；全套 Deno **1018 綠**；
   修後重放 round10：**7 FP 全轉 PASS**，round8/9 樣句測試無回退。

**不修觀察**：回應句家族 hint 側 3 筆（#6/#7/#10，round9 為 2 筆＝頻率持平
微升，仍走 prompt 教學收斂觀察）＋質問裁決內 1 筆（#8）；「框架」
temperature_leak 本輪 2 shot＝守門詞 WAI 不鬆（粉紅大象效應：不逐字入
prompt，靠 gate 擋＋重試供給，兩筆中 gd5 重試即成功）。

## 3. 下一步

第 11 輪：bh 五變體全修預期回 100%；gh 看一路修復＋回應句頻率（3 筆若續升
再議 hint 側教學句）；gd 看框架 leak 頻率。三軸全綠→Batch I Codex 雙審
（附 round6~10 五份判定表＋relax 清單鬆緊審查）→Eric 真機。
