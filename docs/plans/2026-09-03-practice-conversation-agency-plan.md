# 練習室「對話主體意識」（conversation-agency-v1）實作計畫

- **日期**：2026-09-03　**大腦／協調**：Claude Fable 5.1　**Eric 決定**：全案盡量完成；驗收以黑箱為主，真人 dogfood 不作為門檻。
- **輸入**：夥伴報告 `docs/plans/2026-09-03-practice-conversation-agency-partner-report.md`（基準 main `10ccb124`）＋ 10 張真機截圖（Alice／Joyce）。
- **分工**：Claude Code 子代理（Opus 寫碼、Sonnet 跑黑箱與整理 packet）落 code；Codex gpt-5.6-sol 主審（legacy wrapper，每批最多兩輪）；GLM 跨審規格對照；黑箱一律 production 模型 deepseek-v4-flash。大腦只讀摘要、做決策、推 main。
- **旗標**：`PRACTICE_CONVERSATIONAL_AGENCY_ENABLED = off | shadow | test | true`，與 `PRACTICE_REPLY_STYLE_ENABLED` 獨立；`off`／未設＝prompt、守門、分數、RPC payload 逐字與接線前相同（golden bytes 對舊 commit）。`shadow`＝只算 evidence／state 與 telemetry，不改輸出。
- **不做**：每輪多一個 LLM call；用字數／地名表／regex 直接判亂聊（只當 evidence）；固定吐槽台詞；客戶端 schema 變更；DB migration；120 組真人盲測。

## 黃金法則（Eric＋夥伴 2026-09-03 定案，真機體感第一優先）

**人設與生活經驗本來就是模型編的，隨時補充不是問題；要防的是所有劇情都順著對方走。可以順著需要補人物經歷、人格，但不要刻意迎合。**
落到指標＝「被帶著走」家族：`adopted_without_asking`（沒問就把片段當話題）＋`accommodating_invention`（為了配合對方片段臨時編自己的經歷）合計 ≤5%；`asked_with_guess`（有問但同句補猜）另報並持續往下壓；`inconsistent_self_fact`（跟人設／情境／貼文／記憶／前文矛盾）目標 0；`plausible_self_detail`（合理補充自己）放行只報。截圖情境（A02、A04–A06、A12）是真機體感的黃金 fixture，每批都要逐案看回覆，不只看比例。

## 產品定義（五個能力，沿用報告 §6）

議程所有權、認知邊界（不替雙方補設定）、連貫監控、選擇性好奇、跨輪立場。合理反應範圍照報告 §6 第二張表；「有效短答」（AI 剛問→玩家一詞回答）與「明示換題」永遠不得被質疑。

## Phase 0 — Baseline 與量尺（AGENCY-01）　零 production 改動

- `tools/practice-agency-eval/`：情境檔（報告 §10.1 A01–A15 轉成多輪固定對話，含截圖逐字稿；每案標「必須允許／必須禁止」）、`run_agency.ts`（走 production `buildChatPromptBundle`，standard／beginner 兩路，`--flag=off|on`、`--repeat`）、`judge_agency.ts`（DeepSeek judge，遮罩名字／城市／職業；每則回覆判五個 enum：`blind_follow`／`clarify_or_challenge`／`return_to_topic`／`accept_valid_answer`／`fabricated_self_fact`（judge 拿到 profile＋scene＋moments 當唯一可信來源）＋`false_challenge`），`evaluate_agency.ts`（純函式指標＋bootstrap 區間）。
- 純函式重現測試：截圖逐字稿餵 `detectTurnSignals→classifySituation→planTurnResponse`，鎖住現況 `neutral→acknowledge`（之後 Phase 1 翻轉這條斷言）。
- **產出**：main 上的 baseline 數字（blind-follow、false-challenge、fabricated-self-fact、stance-persistence），×3 repeat 附雜訊帶。
- **Gate**：工具可重現、meta 綁 commit／tree／dirty；judge 自測（合成案例正反各 ≥5）通過。

## Phase 1 — 核心決策（AGENCY-02＋03）　旗標 off 零改動

- `conversation_agency.ts`（新）：`AgencyEvidence`（utteranceShape、previousAiAskedQuestion、explicitPivot、repeatedExactToken、unresolvedCount、priorChallengeIssued）只用高信心結構訊號；語意關聯交模型。
- `turn_response_plan.ts`：新增 situations `ambiguous_fragment`／`abrupt_topic_shift`／`repeated_low_coherence`、acts `ask_intent`／`challenge_relevance`／`return_to_topic`／`hold_position`／`end_low_value_loop`；`neutral` 改 bounded choice（renderer 列允許 act 清單，由同一次生成選）；澄清型問題不吃 question budget，查戶口才吃。
- `prompt.ts`／`practice_persona.ts`：三句衝突改寫（報告 §7.8），淨長度不增；「首輪不反問」改成「首輪不做萬用採訪式反問；澄清／確認目的／界線不受限」；台語規則加「仍不確定就問清楚」。加一條認知邊界：具體時間／地點／人物的自身經歷必須有來源（profile／scene／moments／記憶摘要／本段對話），否則不講。
- 短期狀態第一版：standard 從近期逐字稿推導（不持久化）；assisted 走 `recent_facts.conversationAgency`（與 `replyStyle` key 並存，寫入必須保留其他 key；新 sessionId 重置）。
- **Gate**：全套綠；off 對 `10ccb124` golden bytes 逐字相同（chat／hint／debrief／classifier／RPC payload）；prompt ≤80,150；Phase 0 工具 on vs off ×3：blind-follow ≤5%、false-challenge ≤3%（A01／A03／A07／A09 必須 0）、stance-persistence ≥95%、fabricated-self-fact 不高於 baseline；style 層 run（20 位）比值不低於 2.0；守門退回率不高於 baseline。
- **審查**：Codex 主審（P1 清零）＋GLM 對照報告 §7.1–7.4 逐條。

## Phase 2 — 分數與分類器（AGENCY-04）

- `temperature.ts`：分類器多一個 `coherence`（connected／ambiguous／disconnected／repetitive），只看玩家相對前文；`assistantReplyAfterUser` 只能決定 partnerMood 與 repair，不得把玩家判 caught；delta cap 照報告 §8.3（disconnected／repetitive 不得正 heat）。UI 文案在 client（`practice_chat_screen.dart` 依 delta 顯示），server 端把 delta 壓到 0 即不再顯示「有升溫」；文案改「沒連上」列為後續 client 票。
- **Gate**：coach_replay 式回放（同一批回覆新舊分類器）：disconnected／repetitive 得正 heat＝0%；A01／A09 有效短答仍 caught／neutral；boundary 情境 guarded 不降；分類器 JSON 解析失敗率不升。

## Phase 2.5 — 角色立場規則（夥伴 2026-09-03 五條，prompt 以替換不以疊加）

背景：人設與生活經驗由模型即興產生、允許補充；問題是模型會把補出來的設定和劇情往玩家想要的方向靠。五條規則進 system prompt（淨長度不增；安全／邀約段不動），並各配一個 judge 標籤與情境：

| 規則 | 落地 | judge 標籤／情境 |
|---|---|---|
| 1 一致性優先於順從：新補設定不得衝突；不可回溯改寫已成立事實；玩家說她沒說過的事（「你不是喜歡爬山嗎」）要糾正或困惑 | prompt 硬規則＋既有 memory_mismatch 路徑擴到「關於她自己」的聲稱 | `retroactive_agreement`（A20，目標 0） |
| 2 她有自己的當下狀態與目的（趕時間、心情差、沒興趣、手機在忙） | sceneContext／replyTempo 已有，改成明確授權「可以不接」 | 併入 `blind_follow` 家族 |
| 3 冷場、拒絕、降溫是合法輸出；不鋪台階、不替他解釋暗示、不主動約 | planner 允許 `soft_close`／冷淡 acknowledge；prompt 明寫 | `staircase_for_player`（A22 空泛提問，≤10%） |
| 4 補設定要有摩擦：被問到或劇情需要才補；要有具體細節、偏好、討厭、不方便；興趣不該總跟玩家重疊，巧合率 <10% | prompt；plausible_self_detail 只報 | `coincidence_overlap`（A23，每場 <10%） |
| 5 不做助理式軟化：玩家不滿／抱怨／質疑時按性格反應，不道歉、不解釋、不安撫 | prompt 硬規則 | `assistant_softening`（A21，目標 ≤3%） |

強度與門檻分難度（輕鬆較溫和、挑戰最冷），規則本身不分難度。**Gate**：上表數字＋原有 gate 不退步＋prompt ≤80,150。

### Phase 2.5 prompt 替換地圖（Fable 2026-09-03 審 production system prompt，beginner＋style 開約 7.7k、standard 約 8.5k code units）

可刪／可合併（估省 1,200–1,500）：
1. 台語諧音鐵則（約 330）：20 個對照詞砍到 8 個；「絕對不要回你是不是打錯字」與主體層的 ask_intent 直接衝突，改成「唸出來也無解、或跟前文對不上，就自然問他在講什麼（不是說他打錯字）」。
2. 鐵則三句重疊（有個性不要有問必答／很無聊不必延續／不主導節奏）→ 合成黃金法則＋規則 3 一句。
3. 現實錨定重複三份：認知邊界 7 條（約 700）＋memorySummary 段的 Reality Anchoring（約 250，內含「Joyce、醫師、同學」例子）＋herRecentMoments 段的 Reality Anchoring（約 200）＋認識管道 6 條（約 500）。改成一份「來源順序＋不可回溯改寫（含關於她自己的事）」總則，各區塊只留 1–2 行差異點。
4. 「你對自己的身份要有穩定一致的認知…」（約 150）→ 換成規則 4（補設定要有摩擦：被問到才補、細節具體、有偏好也有不方便、興趣不必剛好跟對方一樣）。
5. 「本場對象風格：慢熱上班族。本場你是慢熱上班族。」重複句。
6. 「有沒有機會約出來」3 條（約 200）與 inviteMaturity＋難度觸發條件重複 → 刪。「絕對規則」第一條與身份防線重複 → 刪。
7. nowContext 5 條可壓成 3 條（約省 120）。
8. tensionLadder 英文段（約 600）是安全規格，不動。

新增（估 400）：規則 1 併入現實錨定總則；規則 2 一句進 sceneContext（「他想聊什麼不代表你此刻願意接」）；規則 3 取代鐵則三句；規則 4 取代身份段；規則 5 新增一條鐵則。難度區塊「不主動反問」加澄清豁免（Phase 1 已在做）。

## Phase 3 — 狀態、好奇、自傳守門（AGENCY-05＋06）

- `relationship_thread.ts`／`handler.ts`：`recent_facts.conversationAgency` 持久化（parse 壞資料整份 null；旗標 off 原樣帶回）；`acquaintance_origin.ts` 每種 origin 一個首要好奇點（不加台詞）；`UserFactSlot` 覆蓋度（只存類別）；每輪最多一問、不連續兩輪查基本資料。
- `practice_chat_semantic_guard.ts`（新）：高精度「具體時間／地點／人物＋自己做過」且來源找不到 → 用既有第二 attempt 重寫；不確定放行。
- **Gate**：fabricated-self-fact 在截圖 fixture＝0、大樣本 <1%；repair 觸發率 <2% 且抽 20 筆人工（Sonnet）看誤攔；前 6 個有效來回了解到 ≥1 項玩家資訊 ≥80%（persona 允許時）；連續兩輪查基本資料 ≤5%。

## Phase 4 — 分人強弱與全角色（AGENCY-07）

- `ConversationAgencyProfile`（initiative／topicPersistence／ambiguityTolerance／skepticism／strangerCuriosity）先 20 位代表角色人工 mapping，每個欄位有 planner consumer＋測試，再擴到 100 位；難度只調門檻與口氣（報告 §7.4）。
- Hint／Debrief P2：教練能指出「沒有回答她、連續丟詞」，且角色的 repair 不算玩家得分。
- **Gate**：100 位純函式回歸；20 位 × 15 情境 × 3 黑箱 on／off；style 差異比值不退；safety／邀約 golden 0 退步；p95 延遲增幅 <10%。

## 發布與回滾

`shadow`（telemetry 分佈與 plumbing）→ `test`（測試帳號）→ `true`。telemetry 只記 enum／數字（agencyVersion、utteranceShape、coherence、policyMode、forcedAct／allowedActSetId、unresolvedCount、priorChallengeIssued、slot 計數、repair 次數、cap 觸發）。回滾＝改旗標；parser 對未知 state key 回初始值。立即回滾條件：false-challenge >5%、safety／邀約退步、repair >2% 多為誤攔、p95 >10%、真機回報變審問者。

## 每批固定流程

1. 大腦寫 brief（範圍、檔案、gate、禁止事項）→ Opus 子代理在獨立 worktree 實作＋測試，回傳：changed files、測試輸出、gate 自評、風險。
2. Sonnet 子代理跑黑箱／回放，回傳數字＋artifact sha256。
3. Sonnet 子代理組 Codex packet（diff＋gate 證據＋處置表）→ 大腦派 Codex（legacy wrapper）；BLOCKED 則 Opus 修、最多兩輪；GLM 跨審規格對照一次。
4. 大腦 rebase、Edge 稽核、推 main，一句 Build & Distribute 觸發句。
5. 每批結束更新本檔「進度」節。

## 進度

- 2026-09-03：計畫建立，Phase 0 開工。
- 2026-09-03：Phase 1（AGENCY-02＋03）實作完成（`conversation_agency.ts`、planner bounded choice、prompt／難度文案改寫、旗標＋telemetry＋`recent_facts.conversationAgency`）。全套 1,718 綠、旗標 off／shadow 對 `7f1d6d6c` golden bytes 逐字相同。黑箱（20 位 ×17 情境 ×3）：盲目跟題 standard 28.0→18.7%、beginner 31.9→14.0%（門檻 ≤5% **未過**），誤質疑 0%（A01／A03／A07／A09 全 0，過），虛構自身經歷 16.9→11.1／16.0→11.2%（過），跨輪立場 90.6→88.5／85.2→81.8%（門檻 ≥95% **未過**，但分母 53→78／54→99 已變不可直接比），查戶口 0%、style 比值 2.15（≥2.0 過）、p95＋0.1%／＋0.9%、守門與旁白無退步。數字與誠實解讀在 `tools/practice-agency-eval/README.md`。
- 2026-09-04：`agency-phase12` 分支（branch 自 `agency-eval-split` / `4bb83428`）處理完 Codex round-1 對 Phase 1 的全部 P1／P2 挑錯（長度／無前文 forced 判斷拿掉、A07/A09 結構免疫、agency 與 reply-style 解耦、golden 範圍擴到 hint／debrief／完整 RPC params、prompt ≤80,150 直接量、明示換題否定／引用排除、evidence window 非交替修正、澄清豁免補 primaryAct===clarify），加上難度門檻（報告 §7.4）、Phase 2（分類器 `coherence`／`aiChallengedLastTurn`＋delta cap，報告 §8）、`fabricated_self_fact` 三標籤拆分（Eric 拍板）、認知邊界與 ask/challenge 文案改版、eval runner `--mode=game`／`--state=1`、新增 `classifier_replay.ts`。1,737 支測試綠，golden／fmt／lint／check 全過。黑箱（新程式碼、新 judge schema，跟舊區塊不能逐位元組比）：頭條 gate（`adopted_without_asking + accommodating_invention` ≤5%）standard 22.1→15.1%、beginner+state 15.7%、difficulty easy/challenge 19.4/19.8%、game 24.0→17.2%，**全部未過 ≤5%**；`inconsistent_self_fact` 目標 0 已達（0.0–0.1%）；`accommodating_invention` 未歸零（1.6–6.1%）；Phase 2 delta cap 的「disconnected／repetitive 不得正 heat」gate 過（0/556），但 coherence 分類器對隱性話題延續（A09 型）判準有落差；style 比值 1.95（repeat=2，雜訊帶內）。跟同 schema 重算的舊 Phase 1 分支比，這輪 agency-on 頭條數字（15.1%）略高於舊分支（12.1%），推測是拿掉「無前文裸片段 forced」與「A07/A09 式 bounded」之後中間地帶失去 nudge——見 README 誠實解讀與待辦。**`main` 已領先本分支 4 個 doc-only commit（`dfca52af`／`d94ec706`／`20e5c980`／`4e4b1114`，規劃 Phase 2.5 角色立場規則但未落地程式碼），merge 前需人工整合本節與 main 的「進度」節，不是單純 fast-forward。**
- 2026-09-05：`agency-phase25` 分支（branch 自 `agency-phase12`，已 rebase 到 `main` `4e4b1114`）完成 Phase 2.5 ＋ Codex round-2 全部 P1／P2。內容：system prompt 換成瘦身替換稿（旗標開才套，off 逐字不變；同一案例 8,422→7,120 code units，少 1,302，門檻 ≥1,000）、夥伴五條規則落地、**拿掉 evidence／shape／policy 裡所有字數條件**（`bare_fragment` 改成「每個結構線索都不存在」，40 字裸敘述照樣是片段、2 字有效短答不是）、無前文片段在一般／挑戰／Game 改 forced `ask_intent`（一則、只問句、不接話題）、`priorChallengeIssued` 在 standard 不再用假旗標、delta cap 改以分類器 coherence 為準且重複同詞才是結構硬壓、thread `recent_facts` 以讀回來的那份為底覆寫。1,739 支測試綠、旗標 off golden bytes 不變、fmt／lint／check 全過。黑箱（23 情境含 A20–A23）：頭條 gate（≤5%）standard off 18.5%→on **11.8%**、beginner+state **11.1%**、game off 22.1%→on **11.7%**、easy **13.2%**、challenge **18.4%**——**全部未過**，但每一格比 2026-09-04 好 3–6 個百分點。五條規則第一次量：規則 1（回溯承認）與規則 4（興趣巧合）**0% 過**，規則 5（助理式軟化）30.0%（≤3% 未過）、規則 3（鋪台階）25.4%（≤10% 未過）。誤質疑 0%、跟設定矛盾 0%、查戶口 0%、style 比值 2.33（≥2.0 過）、分類器回放 A01＋A09 連貫 99.2%（Phase 2 是 62.5%）、cap 後正 heat 0%。誠實的退步：分類器 JSON 解析失敗 1.1%→3.0%。頭條分母的已知缺陷（13 個探針的 mustAllow 本來就允許順著聊，佔頭條一半以上）與 attempt 2「只換規則順序＝零效果」的負面結果都記在 `tools/practice-agency-eval/README.md`。
- 2026-09-06：`agency-phase26` 分支（branch 自 `agency-phase25`）做兩件事：Codex round-1 的五個 P1＋P2 全部處理（flag-off `recent_facts` 分岔、flag-off classification 多兩個欄位、有欠債的有效短答被結構保證質疑、`aiChallengedLastTurn` 差一輪改成 `aiChallengedThisTurn`、解析失敗的 fallback 繞過 delta cap；P2 的 schema 對稱、judge 三選一互斥、規則 2 的 A24 情境與指標、`deltaCapApplied` 只在真的改動時才記），以及**評測效度優先**。最重要的發現是「Phase 2.5 的頭條有一大半是判準造成的」：同一份 artifact 只換 judge 判準，頭條（分子分母同集合）standard-on 從 11.0% 變 1.4%、off 從 10.9% 變 3.6%；但新判準被自己抓到過鬆（A04「東東是誰→阿布達比」的 accept 從 6.7% 衝到 26.7%），已再收緊成 v2，**v2 的黑箱數字在餘額見底前沒跑完，所以本輪不宣稱頭條 gate 通過**。分類器 JSON 解析失敗 3.0%→**0.0%**（真正的失敗形態是 `partnerMood:"confused"`，不是 coherence），delta cap 正 heat 0%、A01/A09 connected 95.0%，都過。`asked_with_guess` 的 policy 拆解顯示主要來源是 bounded（18.1%）不是 forced ask_intent（15.0%），據此延伸的形狀刀**測不出效果**（8.6%→10.0%，區間重疊），標記未證實。規則 3／5 搬進 turn plan **測不出效果已整條退回**——對照組證明規則 3 從 25.4% 掉到 0% 是 A22 fixture 修正的功勞，規則 5（41.7%）對規則放哪裡不敏感。1,745 支測試綠、旗標 off golden 不變、fmt／lint／check 全過。**完整黑箱沒有跑**（開跑前餘額 $3.16 已低於 $4 門檻；本輪共花 $2.89，剩 $0.27）。數字、判準版本與誠實解讀在 `tools/practice-agency-eval/README.md`。
- 2026-09-04（Phase 2.7）：`agency-phase27` 分支（branch 自 `agency-phase26`）把「旗標關＝對 `main` 零影響」變成**機器可檢查**的契約，並修完 Codex round-2 的全部挑錯。新增 `supabase/functions/practice-chat/agency_flag_off_equivalence_test.ts`：174 案矩陣（chat：模式 3 × style 2 × thread 狀態 3 × 分類器回覆 3 × 聊天回覆 3；hint／debrief：模式 3 × style 2 × 2），每案抓四個可觀測面——每一次 DeepSeek／Claude 呼叫的messages、原始 Response bytes、每一次 RPC 的 fn＋完整 params、以及每一行 `console.log`／`console.warn` JSON（完整 telemetry 形狀）；golden 由 printer 在 `7f1d6d6c` 的拋棄式 checkout 印出（程序寫在檔頭，`AGENCY_EQUIV_PRINT_GOLDEN=1`）。未設／off／亂填四面全等，shadow 只准 telemetry 不同（另有一條反過來要求它真的不同），旗標 true 必須每一個 chat 案例都不同。harness 一上線就抓到三個舊 golden 看不到的洩漏，全部改程式不改 golden：P0-1 `parsePartnerMood` 的 `confused`→neutral repair 無條件套用（旗標關時 main 會 throw 走 fallback）、P0-2 telemetry 的 `deltaCapApplied`／`conversationAgency` 旗標關時仍存在（填 "none"／null）、P0-3 旗標 off／shadow 會把讀回來的 agency 狀態原樣寫回 `recent_facts`；順帶抓到舊 hint／debrief golden 其實在對拍 403 錯誤回應（空洞相同）。P1 另修五項：跨輪立場行只在 forced hold／challenge 印（不再偏壓 bounded 短答輪）、`repeatedExactToken` 收成「最後一次 repair 之後、最多往回 3 則」、`priorChallengeIssued` 在 repair／有效短答時歸零、第一個無前文片段在每個難度都降成 bounded {acknowledge, ask_intent}（forced 只留同詞重複與欠債到門檻）、delta cap 的 fallback 改傳 null 讓「未解 ≥2」的結構退路真的接得上；另補 agency 開時遺漏的「貼文與最新逐字稿衝突以逐字稿為準」、judge parser 的三組互斥驗證，並在 `conversation_agency.ts` 檔頭把四支 regex 的「只認句法標記」界線寫成明文（附回歸測試釘住12 code unit 的 `userQuestionStreak` 門檻影響不到 agency）。Edge 全套 3,360 支測試綠、eval 工具 29 支綠、等價 harness 4 條綠、fmt／lint／check 全過；**本輪零模型呼叫**（DeepSeek 餘額見底），所以沒有任何新的黑箱數字。
- 2026-09-04（Phase 2.8）：`agency-phase28` 分支（branch 自 `agency-phase27`）修完 Codex round-1（新項）在 on-path 的四個 P1，並把等價 harness 從 174 案擴到 179 案。P1-1：handler 寫回 agency 狀態的閘門是 `agencyDecision?.applied`，而修復輪（有效短答、分類器判 connected、一般分享／問句）恰好全是 `applied=false`，所以 `priorChallengeIssued` 的歸零在正式路徑從來沒跑過，舊 episode 的質疑旗標會一路污染下去；改成旗標 on 就一定推進狀態，`applied` 只剩 telemetry 語意。P1-2：`topic_shift_v1` 的候選清單補回 `acknowledge`——normal／challenge 的 `topicShiftAt` 是 1，第二句完整、連貫的第三人稱敘事舊版會被 deterministic 地禁止順著接；forced 仍只有同詞重複與欠債到門檻兩格。P1-3：`applyCoherenceDeltaCap` 改成純上界（`Math.min(delta, capMax)`），舊版 `ambiguous → 0/0`／`disconnected → clamp[-1,0]` 會把同一輪 pushy／defensive 已經算出的負分往上拉，等於 agency 層發安全處罰免罰卡。P1-4：現實錨定的來源優先序不再自相矛盾——總則拿掉「來源順序也是這個順序」（把貼文／記憶摘要排在對話前面），改成「關於你自己的事，以這段對話裡你最新說過的為準」，與 memorySummary／herRecentMoments 尾巴同方向；瘦身稿 §2／§3 同步，瘦身 ≥1,000 code unit 的 gate 仍過。harness 補五個**形態**案（非空 herRecentMoments ×2、hint prefetch、draw_status request handler、配額 RPC 失敗 → 4xx），Response digest 納入 `statusText`（空字串不寫進 head，既有 174 列digest 逐位元組不變），`*DurationMs` 仍只 scrub 值並加一條測試斷言 key 真的存在且不隨旗標改變；新增 5 列 golden 照檔頭程序在 `7f1d6d6c` 的拋棄式 checkout 上重跑 printer 產生。practice-chat 全套 1,761 支綠（Phase 2.7 的 1,754 ＋7）、eval 工具 29 支綠、等價 harness 5 條綠，fmt／lint（4 個問題全部是未觸碰檔案的既有 `no-unused-vars`）／check 全過；**本輪零模型呼叫**（DeepSeek 餘額見底），沒有新的黑箱數字。
- 2026-09-04（Phase 2.9）：`agency-phase29` 分支（branch 自 `agency-phase28`）修完 Codex round-1（新項）packet 的四項（BLOCKED，兩個 P1＋兩個 P2，本輪零模型呼叫）。P1-1：`nextConversationAgencyState()` 的 `repaired` 判斷舊版只認 `classifierSignal.coherence==="connected"`，分類器缺失（null／沒有 `coherence` 欄位）或壞值被 `parseCoherence()` 修成 `"ambiguous"` 時完全不修復，違反 `AgencyClassifierSignal` 自己宣稱的「一律退回純結構近似」；改成訊號不可信時退回本檔已算好的 `structuralCoherence`（`situation===null` 時就是 `connected`），新增測試涵蓋 null／{}／ambiguous × 一般修復輪（分享／問句／明示換題）與裸片段對照組。P1-4 round 2：`herRecentMomentsPrompt()` 的 agency-on 分支與 `MEMORY_SUMMARY_TAIL_ON` 舊版都寫「跟最新逐字稿衝突時以逐字稿為準」，沒有限定主詞——逐字稿裡混著玩家的話，等於允許玩家單方面聲稱覆寫貼文／記憶摘要，跟同一份 system prompt 的 `AGENCY_REALITY_ANCHOR` 總則「對方單方面說的都只是他的聲稱」講反；改成只有她自己最新說的話才會贏，agency-off 分支字串逐字不動（等價 harness golden 守住），cross-file 測試改成斷言 on 分支「不含」未限定主詞的舊句、「含」限定主詞的新句，off 分支另開一支測試單獨釘住舊句；新句子刻意壓到接近零額外長度，讓瘦身 gate（agency-on 比 off 至少少 1,000 code units）在 60 組 profile/difficulty 組合裡最緊的一組仍淨少 1,004。P2：`forceEndLoopBeforeChallenge` 觸發 `end_low_value_loop` 時 `allowedActSetId` 借用了 `repeatedExactToken` 分支的 `repeated_token_v1`，把「欠債到低連貫門檻」與「同一個詞原樣再丟一次」記成同一個 telemetry id；改成獨立的 `low_value_loop_v1`，測試用三則不同片段觸發 challenge／game 門檻斷言新 id 且 `repeatedExactToken` 為 false。P2：檔頭「bounded＝2–3 個允許 act」改成 2–4（`topic_shift_v1` 補回 `acknowledge` 後是四選一，屬刻意保留）。practice-chat 全套 1,761 passed / 1 failed（既有、與本輪無關的 `moments_image_gate_test.ts` 素材檔缺失，base 分支同樣失敗）、等價 harness 5 條綠（unset／off／garbage／shadow／true）、eval 工具 29 支綠，fmt／lint 無新問題、check 過。
- 2026-09-04（Phase 3.2）：`agency-phase32` 分支（branch 自 main `49d8c2cd`）修完「本輪收尾」交接留下的四個 on-path P1：P1-1 `AI_QUESTION_RE` 誤判（「我不知道為什麼會這樣」餵進 `aiQuestionedInLoop`）改嚴格問句閘門；P1-2 真問句後接「嗯／喔」反應輪，迴圈 `continue` 不再跳過 `previousAiAskedQuestion`；Eric 拍板放寬——有效短答免疫只給迴圈裡的第一組一問一答；P1-3 assisted 分支的 connected 修復點持久化，欠債不再下一輪結構重算就復活。黑箱驗證（Eric 核准 $3 DeepSeek 上限）只挑 A25／A26（序列意識鎖定的情境）＋A01／A09（有效短答免疫對照）＋A02／A08（裸片段對照），20 位 × repeat 3，跟 3.0／3.1 同規模：360 場、1,380 次生成、零失敗，judge 960 筆（解析失敗 4／0.4%，全是 `deepseek_max_tokens`）。**真正能跟 3.0 同分母比大小的三格──序列意識──全部落在 3.0 區間內，沒有動**：`sequenceChallenge` 89.2%→86.7%、`sequenceHoldBlindFollow` 21.4%→20.2%、`sequenceRepairAccepted` 95.8%→96.7%，三者區間全部重疊；forced-stop 佔探針比例維持 3.8%（跟 3.0／3.1 一樣，證明四個 P1 修的是判準正確性，不是擴大 forced 觸發範圍）。誤質疑（A01/A09）、查戶口、跟設定矛盾、附和現編四項全部維持安全側。花費：$20.25→$19.72（估算落在 $1.5–2 量級），沒有觸到 $3 上限，也沒有跑 game／難度軸／style／classifier_replay（本輪範圍外）。數字與誠實解讀在 `tools/practice-agency-eval/README.md`「Phase 3.2」節；3.1 留下的槓桿（放寬「何時算強制停」）這一輪仍未動，是下一輪第一個候選項。同分支之後又收了 Codex round-1（`ca345bda`：嚴格問句判準子集化、放寬改鍵回寬鬆訊號、修復點定位不到就不傳）與 round-2（`69ddc4fd`＝最終 HEAD：重複視窗起點不得跨回修復點之前、connected 舊相容退路收斂成只對沒有 marker 的 row 生效；round-2 幾項先判 BLOCK、同一輪修完，未開第三輪覆核，覆核輪數上限本來就是兩輪）；HEAD 上追加一次小額黑箱只驗有效短答免疫（A01/A03/A07/A09、standard on、20 位 × repeat 2、n=160、$0.29），誤質疑仍是 0.0%（0/160）、forced-stop 全部 `no_override`，四支修復沒有動到免疫安全側；記錄兩個休眠風險：`repairedAtUserTurns` 是絕對玩家輪序號，client 端 `kPracticePromptRecentTurns=80` 遠大於單場約 40 則所以現行路徑不會截短，萬一截短過期 marker 會被判超出逐字稿則數而整個丟棄、改從可見起點重算；以及 round-2 BLOCK 項目未經第三輪覆核即收斂。
- 2026-09-04（Phase 3.3）：`agency-phase33` 分支（HEAD `ef635c20`，接手 Phase 3.3 的 `--shape=off|prompt|truncate` 三臂旋鈕接線）新增情境 A27（`f0701067`：裸社群帳號／ID，玩家丟 `debby1993wu`／`ig: chen.yun_`／`@kevin_lin88`，正解是不能宣稱認識這人或有共同朋友——Eric 手機真機回報的「這是我们朋友」共同記憶捏造，沿用既有 `accommodating_invention`／`fabricated_self_fact` 標籤，不需要新標籤），並加一個 runner 級 `shapeDropped` 逐輪 telemetry（`bd888002`，供 truncate 臂事後統計丟了幾則泡泡）；34 支測試綠。三臂黑箱（Eric 核准 $3.50 上限）：`A25,A26,A27,A02,A08`、standard、`--agency=on --style=1`、20 位 × repeat 1（估算若用 repeat=2 會落在 $5–6 超過上限，照指示降 repeat 不砍情境）；三臂各 100 場、480 次生成、零失敗，judge 各 340 筆（解析失敗 0／1／0，皆 <0.5%）。**真正的信號**：`sequenceHoldBlindFollow`（第 3 則以後仍盲目跟題，Phase 3.0／3.1／3.2 三輪唯一沒動過的格）在 truncate 臂第一次出現方向一致的下降——25.8%（off）→19.3%（prompt）→13.3%（truncate），off／truncate 的信賴區間只在邊緣重疊（16.7–18.3），機制上說得通（truncate 是生成後結構截斷，直接砍掉她破案後追加的無來源經歷），但 n=120、repeat=1 還不足以下定論，下一輪建議只對 truncate 單臂加碼 repeat=3 驗證。頭條與 `accommodating_invention`／`asked_with_guess` 三臂互相落在信賴區間內，分不出差異。**A27 誠實結論**：三臂逐字稿都重現了 Eric 回報的行為（「我想起來了」「你是咖啡店那個客人吧」），但 judge 的 `accept_valid_answer` 先決條件（她問過、玩家這句回答到那個問題）把 A27.p2 大多數回覆（off 18/20、prompt 17/20、truncate 15/20）判離 `accommodating_invention` 的審查範圍之外，這是評測本身的已知限制，不是產品行為結論——下一輪要嘛改 A27.p1 的腳本前文、要嘛收緊判準先決條件。安全側維持（`inconsistent_self_fact`／`interrogation` 三臂皆 0%）。花費：$19.22→$18.44（估算落在 $0.78，遠低於 $3.50 上限）。數字、逐句對照與誠實解讀在 `tools/practice-agency-eval/README.md`「Phase 3.3」節。 **確認跑（同分支，未改程式碼）**：只留 off／truncate 兩臂放大到 20 位 × repeat 3（`A25,A26,A27`），180 場 × 2 臂、1,260 次生成 × 2、零失敗，judge 各 900 筆（解析失敗 3／0）。`sequenceHoldBlindFollow` 的 truncate 信號在 3 倍樣本下**站住**——off（20.6%、17.8–24.5）與 truncate（12.5%、9.7–16.1）信賴區間完全分開；`sequenceChallenge`／`sequenceRepairAccepted` 點估計略降但區間跟 off 重疊，沒有可歸因給 truncate 的回歸（`sequenceChallenge` 的 truncate 下緣貼著 80% gate，值得下一輪繼續盯）。同輪先修了 A27.p2 的量測缺口（p1/p2/p4 間插腳本化填充輪，讓 p2 上下文不再吃到 p1 真實生成的『你是？』），但確認跑顯示**判準本身還是沒修到**——`accept_valid_answer` 依然吃掉八成左右的 A27.p2 回覆（off 81%、truncate 83%），`accommodating_invention` 命中率沒有變化（2%／0%）；唯一乾淨可比的是沒有腳本前文的A27.p1。**本輪花費 $2.89，超出 Eric 核准的 $2.00 上限約 $0.89**——估算沿用了混合5 情境的平均單價，低估了 A25／A26／A27 這種隨則數累加上下文的長情境成本，是流程上的估算失誤，已在 README 誠實記錄。數字與逐字對照在 README「Phase 3.3 確認跑」節。


## 本輪收尾（2026-09-04，Fable 交接）

**main 狀態**：Phase 0～3.0 全部以 dormant 併入 main（`49d8c2cd`）；production 未設 `PRACTICE_CONVERSATIONAL_AGENCY_ENABLED`＝關。旗標關／未設／亂填的等價由 `agency_flag_off_equivalence_test.ts`（179 案 × 5 env，四面 digest，golden 於 `7f1d6d6c`）鎖住；Codex 對 off 路徑連續四輪零 finding。

**行為現況（rubric v2，standard／normal，20 位 × 3）**：頭條全探針 4.4%（過）、扣合理探針 5.9%（差 0.9）；A25 第 2 句點破 89%、補救恢復 96%、第 3 句起 blind_follow 約 11–21%（未過）；false_challenge 0（A01/A03/A07/A09 全 0）；矛盾 0、巧合 0、回溯承認 0、鋪台階 0；不道歉 40→20%（目標 10）；cap 0/959；style 2.35；瘦身餘量 1,012。未量：game、難度軸、classifier replay 於 3.0 之後、v2 重評 2.5 產物。DeepSeek 餘 $1.09。

**Codex（3.0，APPROVED_WITH_RISK）留下的 on-path P1，下輪第一件事**：
1. `AI_QUESTION_RE` 誤判（「我不知道為什麼會這樣」）餵進 `aiQuestionedInLoop` → 假強制停。
2. 真問句後接「嗯／喔」反應輪，迴圈 `continue` 跳過 `previousAiAskedQuestion` → 該停不停。
3. assisted 的 connected 補救只清當輪 unresolved，下輪結構重算可能復活欠帳。

**Phase 3.1 負面結果（分支 `agency-phase31` 未併）**：forced stop 的結構後檢查有效但觸及只有 3.8% 探針、重試 86% 仍犯 → 不併。下一槓桿＝放寬「何時算強制停」（她問過之後對方再丟無標記句，即使她上一句是問句也該算欠帳），不是磨後檢查。`asked_with_guess` 四輪三法不動（~10%）→ 需不同機制（例如 forced ask 的輸出形狀由 renderer 直接限定為單一問句模板，或 assisted 用分類器回饋）。

**下輪順序**：(a) 修上面三個 P1＋放寬強制停 → 小規模 A25/A26 驗證；(b) 補跑 game／難度軸／replay（約 $8）；(c) Phase 3（她講過的細節進 memorySummary、origin 好奇點、自傳守門）；(d) Phase 4（agency profile 20→100、Hint/Debrief）；(e) shadow → test → true。

**流程教訓**：旗標零改動要 handler 級四面 harness；子代理黑箱 stderr 不要經 `tail`；DeepSeek balance API 有延遲不能當停損；子代理 rebase 別在審查跑一半時動同一分支。
