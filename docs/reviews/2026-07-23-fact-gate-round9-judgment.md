# 第 9 輪 eval 被拒候選全量判定（2026-07-23T06-03-14-030Z.json）

方法同 round8（replay_rejected.ts＋jq 抽候選原文＋deno 實測分級）。9 發帶被拒
候選、13 筆 code 全數重現。盤面：bd 100%/0（三輪連綠）、gd **95%/0**（75→95，
round8「扣回原話」教學生效：unsupported 3→0、grounding 3→1）、洩漏三輪 0；
紅＝bh 90%（invite×3）、gh 70%（invite×3/not_grounded×3/venue_named×2/bossy×1）。

## 1. 逐筆判定（13 筆＝FP 9／TP·TP-機械 3／裁決內 1）

| # | 筆 | code | 關鍵句 | 判定 | 根因 |
|---|---|---|---|---|---|
| 1 | bh2 r0 c1 | invite | steady「…應該還是覺得爬對了吧？」 | **FP** | 完成態確認句「V了吧」被 GENERIC 當提案（實際中招動詞是「看到」＋18 字 gap 兜句尾吧） |
| 2 | bh2 r0 c2 | invite | warmUp「下次還會想去嗎？」 | **FP** | 意圖問句家族殘洞：round8 剝除式要求「再」，此句無「再」逃過 |
| 3 | bh3 r3 c1 | invite | warmUp「不如就順順地喝下去吧」 | **FP** | 持續貌「V下去」被當提案（勸她繼續自己的習慣） |
| 4 | gh1 r0 c1 | invite | steady「會想繼續看下去嗎？」 | **FP** | 同 #3（她自己的閱讀意願） |
| 5 | gh1 r0 c2 | not_grounded | steady「我懂…那妳最近在忙什麼」 | **FP（殘留）** | 回應句家族 hint 側 |
| 6 | gh3 r1 c1 | not_grounded | 「這句是專屬妳的…」 | **裁決內** | 質問型（round6 裁決不豁免） |
| 7 | gh3 r1 c2 | invite | 「這週末有家麻辣鍋，要不要組隊實測」 | **TP-機械** | 真 direct 邀約超 P3 階梯 WAI |
| 8 | gh3 r3 c1 | invite | steady「妳先想好辣到冒煙那攤要喝什麼吧」 | **TP-機械（邊界）** | 預設共同麻辣鍋行程＝軟窗口語意，steady 降階 WAI |
| 9 | gh4 r2 c1 | bossy | warmUp「先預約播放權…放給妳聽聽」 | **TP-機械（觀察）** | 單方安排句式，1/80 頻率留觀察 |
| 10 | gh5 r1 c1 | venue_named | warmUp「那間，**只是**路過聞到黑膠味就記下來了」＋coaching「這**週一起**去」 | **FP（新）** | ①命名 pattern「那間…是」把「只是」的「是」當命名系詞，整句切成店名；②「這週一起」被 SCHEDULE_DAY 切成「週一」→假 available_at |
| 11 | gh5 r1 c2 | venue_named | coaching「妳說的店**是**真實的、妳是認真的」 | **FP（新）** | 同 #10 ①：「店是＋形容詞」判斷句被當命名，捕獲「真實的妳是認真的」 |
| 12 | gh5 r3 c1 | not_grounded | steady「地址我還真沒特別記…要不要哪天一起去找」 | **FP** | 回應句家族：誠實迴避＋轉邀約＝coaching 教的正確打法（同 round8 #14） |
| 13 | gd3 r0 c1 | suggested_line_not_grounded | 「換我說：我週末也喜歡到處走走」 | **FP（殘留）** | 回應句家族 debrief 版唯一殘筆（教學把 4+→1，此候選未遵循扣回原話） |

## 2. 隨判定落地的修復（本 commit）

1. `practice_invite.ts` GENERIC_PROPOSAL：動詞群補 `(?!下去|對了|錯了)`＋
   `(?<!下)去`＋語尾助詞前 `(?<!了)`（V了吧/了嗎＝完成態確認非提案）→ #1/#3/#4。
2. `practice_invite.ts` INTENT_QUESTION_CLAUSE：`(?:還會想?再?|會想?再)`——
   「還」在場時「再」可省 → #2。
3. `hint_fact_ledger.ts` 命名 pattern：「是」補 lookbehind（只/還/就/但/可/也/
   算/而）＋捕獲類排「、的妳你我」＋尾 `(?!的)`（判斷句「店是真實的」不是命名）→ #10①/#11。
4. `hint_fact_ledger.ts` SCHEDULE_DAY：週[一~日]補 `(?!起)`（「這週一起去」≠週一）→ #10②。
5. 回歸測試各補一組；全套 Deno 1016 綠；修後重放 round9 6/13 轉 PASS
   （5 FP＋bh2 c1）、round8 重放 7 PASS 無回退，TP/裁決內全數照舊。

**不修觀察**：回應句家族殘 4 筆（#5/#12/#13＋質問 #6 裁決內）——hint 側無教學
槓桿可加（gh5 型誠實迴避句是 coaching 教的正確打法，被 grounding 殺屬已知
張力，round7 拍板觀察）；bossy 1/80。

## 3. 下一步

第 10 輪：bh 預期回 100%（3 FP 全修）、gh 看 invite/venue 修復（預期 +3~5 發）
＋回應句/質問輪間頻率、gd 續驗教學收斂。三軸全綠→Batch I Codex 雙審
（附 round6/7/8/9 四份判定表＋relax 清單鬆緊審查）→Eric 真機。
