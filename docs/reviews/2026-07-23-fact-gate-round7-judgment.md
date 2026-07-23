# 第 7 輪 eval 被拒候選全量判定（2026-07-23T04-47-01-941Z.json）

方法：`tools/practice_single_shot_eval/replay_rejected.ts`（取代一次性 replay_r6.ts，
本輪起落 repo 常駐；deno 直接 import 現行 gate 模組——hint.ts / hint_fact_ledger.ts /
practice_visible_quality.ts / debrief_card.ts / visible_text_guard.ts，以 eval 同款
parseOptions＋fixture context 逐筆重放，並逐欄輸出 unsupported claim 錨點、
grounding 失敗欄與洩漏詞最小命中子串）。7 發帶被拒候選（9 筆 code）**全數重現
recorded code**。

判定口徑同前三輪：**FP**＝自然措辭被 heuristic 誤判；**TP**＝候選確實捏造/違規；
**TP-機械/機制**＝gate 照規格正確執行；新增 **裁決內**＝round6 四型分治裁決明文
不豁免的形狀（質問型回應句），打回是刻意設計不是缺陷。

本輪盤面：80 發＝first_shot 74、second_shot 4、503 2；served 側詞表洩漏 0。
新手 hint 100%/0、game debrief 95%/0 首次轉綠。round6 立案七家族（invite_route
單字動詞詞中匹配、裸「傳」假人名、進行貌 current_location、pet 未然句、
疑問補語 schedule、8 句窗、分析欄詞面 grounding）本輪 **0 重現**——大掃除有效。

## 1. 逐筆判定表（9 筆）

### game_hint（5 筆）

| # | 筆 | code | 觸發欄位＋錨點 | 候選關鍵句 | 判定 | 理由 |
|---|---|---|---|---|---|---|
| 1 | gh1 r1 c1 | not_grounded | steady 全窗零重疊 | 「還好啦，只是那天剛好沒事就一口氣看完，妳這種慢慢看的步調感覺也不錯」 | **FP（殘留）** | 回應她「效率也太高，我還停在第三章」的謙遜否認句，語意扣題但天然零詞面重疊；非四型豁免、非質問型，回應句家族殘餘 |
| 2 | gh3 r0 c1 | not_grounded | warmUp＋steady 全窗零重疊 | 「哪有，我這句是限量款，只對敢應戰的人講」「被抓包了，其實我對別人都很客氣」 | **裁決內** | 回應她質問「是不是對每個女生都嗆一樣的話」；round6 裁決質問型不豁免＝推模型引用原話反打，本候選整句換新詞、照規打回 |
| 3 | gh3 r0 c2 | invite_route | steady 判 soft；P3 allowed=build | 「**下次吃飯有機會一起試試**，看誰先投降」 | **TP-機械** | 真邀約語意超出 P3 速約階梯（只准鋪墊），政策 gate 照規格擋（同 round6 #7）；本發兩攻皆敗成 503 |
| 4 | gh3 r3 c1 | not_grounded | steady 全窗零重疊 | 「被抓包了，不過這句是專屬妳的，其他人我還沒捨得拿出來嗆」 | **裁決內** | 同 #2 |
| 5 | gh5 r0 c1 | venue:located_at | coaching「別急著報路」located_at conf=high；伴生「帶路」venue_named | coaching「**別急著報路**名（逐字稿沒給地點就別編）。用「**帶路**」把資訊需求轉成兩人行程」 | **FP** | 候選明確教「別編地點」反被殺；「報路」不在 NON_PLACE_COMPOUND_TAIL、引號「帶路」穿透 coaching 豁免（looksLikeLocationAnchor 沒吃 compound tail）——字尾「路」切割家族（round6 #12/#24 同款）殘洞 |

### debrief（4 筆）

| # | 筆 | code | 觸發欄位＋錨點 | 候選關鍵句 | 判定 | 理由 |
|---|---|---|---|---|---|---|
| 6 | bd2 r1 c1 | third_party:name:is_named | dateChanceReason anchor=「測試句」conf=high | 「她願意玩梗、**丟測試句**，但只聊歌單」 | **FP** | 裸「丟」送收 pattern 切出假人名「測試句」（lookahead 缺口；同 round6 #3 裸「傳」家族），人名形態檢查沒擋話語單位字尾 |
| 7 | bd4 r1 c1 | temperature_leak | suggestedLine 最小命中=「篩選」 | 「妳這套「導演+預告」的**篩選**法我要學起來」 | **FP-機制（詞表 stale）** | 9fd3b8a5 去列字後 debrief 全路徑注入已不含「篩選」（probe 實測 beginner＋game 全 fixture 0 hit），裸詞守門只剩誤殺自然語；她的挑片標準（導演優先＋看預告）被總結成「篩選法」是正常中文 |
| 8 | bd4 r1 c2 | user:preference:likes | suggestedLine anchor=「挑日子看」conf=high | 「我也喜歡**挑日子看**，有次看完凌晨一點才散場」 | **FP（邊界）** | 使用者本人原話就是「這種後勁強的片要挑**對**日子看」——一字之差（對）讓 textual support 落空；likes 家族近匹配盲點，非捏造 |
| 9 | gd3 r1 c1 | third_party:name:is_named | missedVariable anchor=「資訊題」conf=high | 「沒有給她任何情緒或內容，只**丟資訊題**」 | **FP** | 同 #6 裸「丟」家族；伴生 suggestedLine「那換我，我週末通常會找新開的店」回應她「你也可以說說你自己」＝回應句家族，名字修掉後 grounding 仍會打回（次發已救回，記錄供觀察） |

## 2. Gate 彙總

| gate | 總數 | FP | TP/裁決內 | 一句話根因 |
|---|---|---|---|---|
| not_grounded（hint） | 3 | 1（gh1 謙遜否認） | 2 裁決內（gh3 質問型） | 回應句家族：質問型照裁決不豁免；gh1 型為殘留 |
| invite_route | 1 | 0 | 1 TP-機械 | 真邀約超 P3 階梯，WAI |
| venue（located_at/venue_named） | 1 | 1 | 0 | 動賓「路」複合詞（報路/帶路）字尾切割 |
| third_party:name | 2 | 2 | 0 | 裸「丟」切話語單位（測試句/資訊題）成假人名 |
| temperature_leak | 1 | 1 | 0 | 裸詞「篩選」詞表 stale（注入已去列字） |
| user:preference:likes | 1 | 1 | 0 | 「挑日子看」vs 原話「挑對日子看」一字之差 |

## 3. 交接問題的答案

- **新手 debrief 95→90 是雜訊還是新家族？** 都不是全新家族：bd2＝裸「丟」假
  人名（round6 裸「傳」家族的新變體）、bd4＝詞表 stale＋likes 近匹配（round5
  likes 家族邊角）。已知家族的新邊角，非隨機雜訊。
- **temperature_leak 去列字後仍現的漏詞是啥？** 「篩選」。不是注入殘漏——
  是守門表殘留：注入側已去列字，詞表沒跟著收，殺到純自然語。
- **誠實迴避豁免繞道（Minor ①）？** 本輪 3 筆 not_grounded 全數無「我哪知道」
  式 admission 措辭＝無繞道證據，維持觀察不收窄。
- **pet irrealis 12 字窗（Minor ②）？** 本輪 0 重現，維持不擴窗。

## 4. 隨判定落地的修復（本 commit 系列）

1. `hint_fact_ledger.ts`：人名形態排除補話語單位字尾（句/題/梗）→ #6/#9 修。
2. `hint_fact_ledger.ts`：NON_PLACE_COMPOUND_TAIL 補 報路/認路/指路；
   `looksLikeLocationAnchor` 前置吃 compound tail（堵 coaching 豁免穿透）→ #5 修。
3. `visible_text_guard.ts`：摘除裸詞「篩選/筛选」、回列複合詞「資格篩選/资格筛选」
   （1.2 原詞無自然語用法）→ #7 修。
4. `hint.ts` 質問教學補「反打句必須複用她原話字眼」——對齊裁決刻意設計
   （gate 不豁免＝推模型引用原話），從 prompt 側收斂 #2/#4 打回率；
   prompt 上限 5000→5050（prompt_test 註記）。

**不修**（記錄供觀察）：#1 gh1 謙遜否認型（1/20 不破 95%，擴豁免有繞道風險）、
#3 invite TP（WAI）、#8 likes 一字差（#7 修後 bd4 首發即 serve，此筆成 moot；
近匹配家族再現才開案）、#9 伴生 grounding（次發可救）。

修後重放驗證：#5/#6/#7 三筆 FP 轉 PASS；#2/#3/#4/#8 照舊（裁決內/TP/觀察）；
#9 假人名修掉後浮出伴生 grounding code（預期）。全套 1012 測試綠。
