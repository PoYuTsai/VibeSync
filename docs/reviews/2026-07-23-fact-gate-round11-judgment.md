# 第 11 輪 eval 被拒候選全量判定（2026-07-23T07-56-40-908Z.json）

方法同 round8~10（replay_rejected.ts＋jq 抽候選原文＋scratchpad deno probe 逐
flag 實測）。7 發帶被拒候選、10 筆候選全數離線重現。盤面：**bd 100%（四輪連
綠）**、gd 95%、洩漏**五輪連續 0**、bh 95%（round10 預測回 100% 差 1 筆＝
invite 新變體）；紅＝gh 75%＋3×503（not_grounded×5 爆發＝回應句家族過門檻、
invite×1、located_at×1、game_contract×1）。

## 1. 逐筆判定（10 筆＝FP 修 3／FP 回應句家族 5（過門檻→上教學句）／TP·WAI 2）

| # | 筆 | code | 關鍵句 | 判定 | 根因 |
|---|---|---|---|---|---|
| 1 | bh2 r3 c1 | invite | steady「妳現在**走路**還會抖嗎？」 | **FP（修）** | GENERIC_PROPOSAL 語尾問句型：「走」＋≤18字＋「嗎」——「走路」是行走本身不是同行提案（warmUp「下次爬山記得找有纜車的山」全鏈 none，非觸發源） |
| 2 | gh1 r0 c1 | invite | warmUp「先**跟妳**說一聲，妳要慢慢**看**」＋steady「妳**看下來**感覺如何？」 | **FP（修）** | 兩洞：ADDRESSEE_PLAN_CUE「跟妳＋動詞」窗 `.{0,10}` 跨逗號湊對；「看下來」體感補語被 GENERIC_PROPOSAL 當提案（看的 lookahead 擋掉後改由裸「來」分支咬中「下來」的來） |
| 3 | gh1 r0 c2 | not_grounded | steady「我懂，有時候就是要找對節奏才能接著讀…」 | **FP（回應句家族）** | 回她「還停在第三章」的共感句＋轉問選書，零詞面重疊（warmUp 有「第三章」過，steady 敗） |
| 4 | gh3 r0 c1 | not_grounded | steady「被抓包了嗎哈哈，不過這句是專屬妳的…」 | **FP（回應句家族）** | 質問反打句：「這句」回指她的原話但零字面複用（她句中「嗆」是單字詞，詞面比對吃不到） |
| 5 | gh3 r0 c2 | not_grounded | coaching「這是**P3**測試」 | **TP** | replay 加測 coaching 抓到 internal_label_leak（P3 內部階段代碼）——無論 grounding，此候選都該死；拒得對 |
| 6 | gh3 r3 c1 | not_grounded | steady「其實我只對「先嗆我」的人才會這樣回，妳算特例」 | **FP（回應句家族）** | 同 #4：「嗆」單字詞 bigram 比對不中 |
| 7 | gh5 r1 c1 | unsupported venue:located_at | warmUp「還沒仔細記**那區**怎麼走」anchor=「還沒仔細記那區」conf=high | **FP（修）** | 指示詞「那區」回指她問的「哪一區」，被路名 pattern 當新地名主張（「一路」假地點的孿生：指示詞＋字尾）；諷刺點＝這正是 contract 教的「不編地址」正確打法。steady「地址我一時說不上來…帶妳去」另中回應句家族 |
| 8 | gh5 r1 c2 | game_contract | coaching 全文無 階段/窗口/這輪 任一字 | **TP（WAI）** | 機械契約：coaching 必含 game心法＋速約任務＋階段詞——「Game 心法」帶空格 compact 後可過，真缺的是階段詞彙；契約教學面 WAI 不鬆 |
| 9 | gh5 r3 c1 | not_grounded | warmUp「哈其實我也是路過發現的，還沒細研究過地址…」 | **FP（回應句家族）** | 誠實迴避＋轉邀約＝教的正確打法，零詞面重疊（她問「在哪一區」無「地址」字眼） |
| 10 | gd3 r0 c1 | suggested_line_not_grounded | 「哈哈也對，換我說：我週末比較常到處走走看展，妳呢？」 | **FP（回應句家族，debrief 側殘 1）** | 她說「你也可以說說你自己」，建議句正確照做但零字面複用；round8 教學句已收斂到 20 shot 僅 1 筆，續觀察 |

## 2. 隨判定落地的修復（本 commit）

1. `practice_invite.ts` GENERIC_PROPOSAL：`走(?!路)`＋看|吃|喝|玩 補
   `(?!(?:起來|下來))`＋裸「來」補 `(?<!下)`（體感補語三路全堵；「約起來嗎」
   不受影響仍 direct）→ #1、#2 後半。
2. `practice_invite.ts` ADDRESSEE_PLAN_CUE：「跟妳＋動詞」窗 `.{0,10}` 改
   `[^，,。！？!?；;]{0,10}` 禁跨標點；同時補 `[妳你]下來` 進呼喚式清單
   （堵 #2 的 `(?<!下)來` 讓真邀約「妳下來嗎」漏接的缺口）→ #2 前半。
3. `hint_fact_ledger.ts` 路名 anchor 排除：`/(?:那|這)(?:一)?(?:條|個)?(?:區|站|街|帶)$/`
   （指示詞回指非地名；真地名「信義區/民生一路」前一字是專名構詞，回歸守住）→ #7。
4. **回應句家族 hint 側過門檻（round9=2→round10=3→round11=5 > 3，依 round10
   拍板）**：`hint.ts` visibleGameHintContract 補「callback＝詞面扣回」通則
   教學一行（warmUp/steady 各自至少複用對話一個具體字眼）——對齊 round8
   debrief 版教學（gd 75→95 的同款解法），gate 不鬆 → #3/#4/#6/#9 收斂待
   round12 驗證。
5. 回歸測試：practice_invite_test 新增 round11 家族 4 句＋4 真陽性守門、
   hint_fact_ledger_test 新增 那區/這站/那條街＋真地名保留；prompt_test
   Hint 預算 5050→5150（教學句固定 bytes）；全套 Deno **1020 綠**；
   修後重放 round11：**invite×2 全轉 PASS、located_at 消失**（gh5 r1 c1 殘
   not_grounded＝回應句家族，走教學不鬆 gate），round8~10 樣句測試無回退。

**不修觀察**：game_contract 階段詞契約 1 筆（#8，WAI）；debrief 側回應句
殘 1 筆（#10）；「框架」leak 本輪 0（守門詞 WAI 持續）。
既存行為註記：「我們約中山站碰面」HEAD 本來就不抽 located_at（policy
寧可放行），非本輪回歸。

## 3. 下一步

第 12 輪：gh 看教學句對回應句家族收斂幅度（5→? 筆）＋invite/located_at 修復
驗證；bh 預期回 100%；bd/gd 維持。三軸全綠→Batch I Codex 雙審（附 round6~11
**六**份判定表＋relax 清單鬆緊審查）→Eric 真機。
