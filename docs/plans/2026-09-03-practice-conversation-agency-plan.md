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

- `tools/practice-agency-eval/`：情境檔（報告 §10.1 A01–A15 轉成多輪固定對話，含截圖逐字稿；每案標「必須允許／必須禁止」）、`run_agency.ts`（走 production `buildChatPromptBundle`，standard／beginner 兩路，`--flag=off|on`、`--repeat`）、`judge_agency.ts`（DeepSeek judge，遮罩名字／城市／職業；每則回覆判五個 enum：`blind_follow`／`clarify_or_challenge`／`return_to_topic`／`accept_valid_answer`／`accommodating_self_fact`（judge 拿到 profile＋scene＋moments 當唯一可信來源）＋`false_challenge`），`evaluate_agency.ts`（純函式指標＋bootstrap 區間）。
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
- 2026-09-04：`agency-phase12` 分支（branch 自 `agency-eval-split` / `4bb83428`）處理完 Codex round-1 對 Phase 1 的全部 P1／P2 挑錯（長度／無前文 forced 判斷拿掉、A07/A09 結構免疫、agency 與 reply-style 解耦、golden 範圍擴到 hint／debrief／完整 RPC params、prompt ≤80,150 直接量、明示換題否定／引用排除、evidence window 非交替修正、澄清豁免補 primaryAct===clarify），加上難度門檻（報告 §7.4）、Phase 2（分類器 `coherence`／`aiChallengedLastTurn`＋delta cap，報告 §8）、`accommodating_self_fact` 三標籤拆分（Eric 拍板）、認知邊界與 ask/challenge 文案改版、eval runner `--mode=game`／`--state=1`、新增 `classifier_replay.ts`。1,737 支測試綠，golden／fmt／lint／check 全過。黑箱（新程式碼、新 judge schema，跟舊區塊不能逐位元組比）：頭條 gate（`adopted_without_asking + accommodating_invention` ≤5%）standard 22.1→15.1%、beginner+state 15.7%、difficulty easy/challenge 19.4/19.8%、game 24.0→17.2%，**全部未過 ≤5%**；`inconsistent_self_fact` 目標 0 已達（0.0–0.1%）；`accommodating_invention` 未歸零（1.6–6.1%）；Phase 2 delta cap 的「disconnected／repetitive 不得正 heat」gate 過（0/556），但 coherence 分類器對隱性話題延續（A09 型）判準有落差；style 比值 1.95（repeat=2，雜訊帶內）。跟同 schema 重算的舊 Phase 1 分支比，這輪 agency-on 頭條數字（15.1%）略高於舊分支（12.1%），推測是拿掉「無前文裸片段 forced」與「A07/A09 式 bounded」之後中間地帶失去 nudge——見 README 誠實解讀與待辦。**`main` 已領先本分支 4 個 doc-only commit（`dfca52af`／`d94ec706`／`20e5c980`／`4e4b1114`，規劃 Phase 2.5 角色立場規則但未落地程式碼），merge 前需人工整合本節與 main 的「進度」節，不是單純 fast-forward。**
- 2026-09-05：`agency-phase25` 分支（branch 自 `agency-phase12`，已 rebase 到 `main` `4e4b1114`）完成 Phase 2.5 ＋ Codex round-2 全部 P1／P2。內容：system prompt 換成瘦身替換稿（旗標開才套，off 逐字不變；同一案例 8,422→7,120 code units，少 1,302，門檻 ≥1,000）、夥伴五條規則落地、**拿掉 evidence／shape／policy 裡所有字數條件**（`bare_fragment` 改成「每個結構線索都不存在」，40 字裸敘述照樣是片段、2 字有效短答不是）、無前文片段在一般／挑戰／Game 改 forced `ask_intent`（一則、只問句、不接話題）、`priorChallengeIssued` 在 standard 不再用假旗標、delta cap 改以分類器 coherence 為準且重複同詞才是結構硬壓、thread `recent_facts` 以讀回來的那份為底覆寫。1,739 支測試綠、旗標 off golden bytes 不變、fmt／lint／check 全過。黑箱（23 情境含 A20–A23）：頭條 gate（≤5%）standard off 18.5%→on **11.8%**、beginner+state **11.1%**、game off 22.1%→on **11.7%**、easy **13.2%**、challenge **18.4%**——**全部未過**，但每一格比 2026-09-04 好 3–6 個百分點。五條規則第一次量：規則 1（回溯承認）與規則 4（興趣巧合）**0% 過**，規則 5（助理式軟化）30.0%（≤3% 未過）、規則 3（鋪台階）25.4%（≤10% 未過）。誤質疑 0%、跟設定矛盾 0%、查戶口 0%、style 比值 2.33（≥2.0 過）、分類器回放 A01＋A09 連貫 99.2%（Phase 2 是 62.5%）、cap 後正 heat 0%。誠實的退步：分類器 JSON 解析失敗 1.1%→3.0%。頭條分母的已知缺陷（13 個探針的 mustAllow 本來就允許順著聊，佔頭條一半以上）與 attempt 2「只換規則順序＝零效果」的負面結果都記在 `tools/practice-agency-eval/README.md`。
- 2026-09-06：`agency-phase26` 分支（branch 自 `agency-phase25`）做兩件事：Codex round-1 的五個 P1＋P2 全部處理（flag-off `recent_facts` 分岔、flag-off classification 多兩個欄位、有欠債的有效短答被結構保證質疑、`aiChallengedLastTurn` 差一輪改成 `aiChallengedThisTurn`、解析失敗的 fallback 繞過 delta cap；P2 的 schema 對稱、judge 三選一互斥、規則 2 的 A24 情境與指標、`deltaCapApplied` 只在真的改動時才記），以及**評測效度優先**。最重要的發現是「Phase 2.5 的頭條有一大半是判準造成的」：同一份 artifact 只換 judge 判準，頭條（分子分母同集合）standard-on 從 11.0% 變 1.4%、off 從 10.9% 變 3.6%；但新判準被自己抓到過鬆（A04「東東是誰→阿布達比」的 accept 從 6.7% 衝到 26.7%），已再收緊成 v2，**v2 的黑箱數字在餘額見底前沒跑完，所以本輪不宣稱頭條 gate 通過**。分類器 JSON 解析失敗 3.0%→**0.0%**（真正的失敗形態是 `partnerMood:"confused"`，不是 coherence），delta cap 正 heat 0%、A01/A09 connected 95.0%，都過。`asked_with_guess` 的 policy 拆解顯示主要來源是 bounded（18.1%）不是 forced ask_intent（15.0%），據此延伸的形狀刀**測不出效果**（8.6%→10.0%，區間重疊），標記未證實。規則 3／5 搬進 turn plan **測不出效果已整條退回**——對照組證明規則 3 從 25.4% 掉到 0% 是 A22 fixture 修正的功勞，規則 5（41.7%）對規則放哪裡不敏感。1,745 支測試綠、旗標 off golden 不變、fmt／lint／check 全過。**完整黑箱沒有跑**（開跑前餘額 $3.16 已低於 $4 門檻；本輪共花 $2.89，剩 $0.27）。數字、判準版本與誠實解讀在 `tools/practice-agency-eval/README.md`。
- 2026-09-04（Phase 2.7）：`agency-phase27` 分支（branch 自 `agency-phase26`）把「旗標關＝對 `main` 零影響」變成**機器可檢查**的契約，並修完 Codex round-2 的全部挑錯。新增 `supabase/functions/practice-chat/agency_flag_off_equivalence_test.ts`：174 案矩陣（chat：模式 3 × style 2 × thread 狀態 3 × 分類器回覆 3 × 聊天回覆 3；hint／debrief：模式 3 × style 2 × 2），每案抓四個可觀測面——每一次 DeepSeek／Claude 呼叫的messages、原始 Response bytes、每一次 RPC 的 fn＋完整 params、以及每一行 `console.log`／`console.warn` JSON（完整 telemetry 形狀）；golden 由 printer 在 `7f1d6d6c` 的拋棄式 checkout 印出（程序寫在檔頭，`AGENCY_EQUIV_PRINT_GOLDEN=1`）。未設／off／亂填四面全等，shadow 只准 telemetry 不同（另有一條反過來要求它真的不同），旗標 true 必須每一個 chat 案例都不同。harness 一上線就抓到三個舊 golden 看不到的洩漏，全部改程式不改 golden：P0-1 `parsePartnerMood` 的 `confused`→neutral repair 無條件套用（旗標關時 main 會 throw 走 fallback）、P0-2 telemetry 的 `deltaCapApplied`／`conversationAgency` 旗標關時仍存在（填 "none"／null）、P0-3 旗標 off／shadow 會把讀回來的 agency 狀態原樣寫回 `recent_facts`；順帶抓到舊 hint／debrief golden 其實在對拍 403 錯誤回應（空洞相同）。P1 另修五項：跨輪立場行只在 forced hold／challenge 印（不再偏壓 bounded 短答輪）、`repeatedExactToken` 收成「最後一次 repair 之後、最多往回 3 則」、`priorChallengeIssued` 在 repair／有效短答時歸零、第一個無前文片段在每個難度都降成 bounded {acknowledge, ask_intent}（forced 只留同詞重複與欠債到門檻）、delta cap 的 fallback 改傳 null 讓「未解 ≥2」的結構退路真的接得上；另補 agency 開時遺漏的「貼文與最新逐字稿衝突以逐字稿為準」、judge parser 的三組互斥驗證，並在 `conversation_agency.ts` 檔頭把四支 regex 的「只認句法標記」界線寫成明文（附回歸測試釘住12 code unit 的 `userQuestionStreak` 門檻影響不到 agency）。Edge 全套 3,360 支測試綠、eval 工具 29 支綠、等價 harness 4 條綠、fmt／lint／check 全過；**本輪零模型呼叫**（DeepSeek 餘額見底），所以沒有任何新的黑箱數字。
- 2026-09-04（Phase 2.8）：`agency-phase28` 分支（branch 自 `agency-phase27`）修完 Codex round-1（新項）在 on-path 的四個 P1，並把等價 harness 從 174 案擴到 179 案。P1-1：handler 寫回 agency 狀態的閘門是 `agencyDecision?.applied`，而修復輪（有效短答、分類器判 connected、一般分享／問句）恰好全是 `applied=false`，所以 `priorChallengeIssued` 的歸零在正式路徑從來沒跑過，舊 episode 的質疑旗標會一路污染下去；改成旗標 on 就一定推進狀態，`applied` 只剩 telemetry 語意。P1-2：`topic_shift_v1` 的候選清單補回 `acknowledge`——normal／challenge 的 `topicShiftAt` 是 1，第二句完整、連貫的第三人稱敘事舊版會被 deterministic 地禁止順著接；forced 仍只有同詞重複與欠債到門檻兩格。P1-3：`applyCoherenceDeltaCap` 改成純上界（`Math.min(delta, capMax)`），舊版 `ambiguous → 0/0`／`disconnected → clamp[-1,0]` 會把同一輪 pushy／defensive 已經算出的負分往上拉，等於 agency 層發安全處罰免罰卡。P1-4：現實錨定的來源優先序不再自相矛盾——總則拿掉「來源順序也是這個順序」（把貼文／記憶摘要排在對話前面），改成「關於你自己的事，以這段對話裡你最新說過的為準」，與 memorySummary／herRecentMoments 尾巴同方向；瘦身稿 §2／§3 同步，瘦身 ≥1,000 code unit 的 gate 仍過。harness 補五個**形態**案（非空 herRecentMoments ×2、hint prefetch、draw_status request handler、配額 RPC 失敗 → 4xx），Response digest 納入 `statusText`（空字串不寫進 head，既有 174 列digest 逐位元組不變），`*DurationMs` 仍只 scrub 值並加一條測試斷言 key 真的存在且不隨旗標改變；新增 5 列 golden 照檔頭程序在 `7f1d6d6c` 的拋棄式 checkout 上重跑 printer 產生。practice-chat 全套 1,761 支綠（Phase 2.7 的 1,754 ＋7）、eval 工具 29 支綠、等價 harness 5 條綠，fmt／lint（4 個問題全部是未觸碰檔案的既有 `no-unused-vars`）／check 全過；**本輪零模型呼叫**（DeepSeek 餘額見底），沒有新的黑箱數字。
- 2026-09-04（Phase 2.9）：`agency-phase29` 分支（branch 自 `agency-phase28`）修完 Codex round-1（新項）packet 的四項（BLOCKED，兩個 P1＋兩個 P2，本輪零模型呼叫）。P1-1：`nextConversationAgencyState()` 的 `repaired` 判斷舊版只認 `classifierSignal.coherence==="connected"`，分類器缺失（null／沒有 `coherence` 欄位）或壞值被 `parseCoherence()` 修成 `"ambiguous"` 時完全不修復，違反 `AgencyClassifierSignal` 自己宣稱的「一律退回純結構近似」；改成訊號不可信時退回本檔已算好的 `structuralCoherence`（`situation===null` 時就是 `connected`），新增測試涵蓋 null／{}／ambiguous × 一般修復輪（分享／問句／明示換題）與裸片段對照組。P1-4 round 2：`herRecentMomentsPrompt()` 的 agency-on 分支與 `MEMORY_SUMMARY_TAIL_ON` 舊版都寫「跟最新逐字稿衝突時以逐字稿為準」，沒有限定主詞——逐字稿裡混著玩家的話，等於允許玩家單方面聲稱覆寫貼文／記憶摘要，跟同一份 system prompt 的 `AGENCY_REALITY_ANCHOR` 總則「對方單方面說的都只是他的聲稱」講反；改成只有她自己最新說的話才會贏，agency-off 分支字串逐字不動（等價 harness golden 守住），cross-file 測試改成斷言 on 分支「不含」未限定主詞的舊句、「含」限定主詞的新句，off 分支另開一支測試單獨釘住舊句；新句子刻意壓到接近零額外長度，讓瘦身 gate（agency-on 比 off 至少少 1,000 code units）在 60 組 profile/difficulty 組合裡最緊的一組仍淨少 1,004。P2：`forceEndLoopBeforeChallenge` 觸發 `end_low_value_loop` 時 `allowedActSetId` 借用了 `repeatedExactToken` 分支的 `repeated_token_v1`，把「欠債到低連貫門檻」與「同一個詞原樣再丟一次」記成同一個 telemetry id；改成獨立的 `low_value_loop_v1`，測試用三則不同片段觸發 challenge／game 門檻斷言新 id 且 `repeatedExactToken` 為 false。P2：檔頭「bounded＝2–3 個允許 act」改成 2–4（`topic_shift_v1` 補回 `acknowledge` 後是四選一，屬刻意保留）。practice-chat 全套 1,761 passed / 1 failed（既有、與本輪無關的 `moments_image_gate_test.ts` 素材檔缺失，base 分支同樣失敗）、等價 harness 5 條綠（unset／off／garbage／shadow／true）、eval 工具 29 支綠，fmt／lint 無新問題、check 過。
- 2026-09-04（Phase 3.2）：`agency-phase32` 分支（branch 自 main `49d8c2cd`）修完「本輪收尾」交接留下的四個 on-path P1：P1-1 `AI_QUESTION_RE` 誤判（「我不知道為什麼會這樣」餵進 `aiQuestionedInLoop`）改嚴格問句閘門；P1-2 真問句後接「嗯／喔」反應輪，迴圈 `continue` 不再跳過 `previousAiAskedQuestion`；Eric 拍板放寬——有效短答免疫只給迴圈裡的第一組一問一答；P1-3 assisted 分支的 connected 修復點持久化，欠債不再下一輪結構重算就復活。黑箱驗證（Eric 核准 $3 DeepSeek 上限）只挑 A25／A26（序列意識鎖定的情境）＋A01／A09（有效短答免疫對照）＋A02／A08（裸片段對照），20 位 × repeat 3，跟 3.0／3.1 同規模：360 場、1,380 次生成、零失敗，judge 960 筆（解析失敗 4／0.4%，全是 `deepseek_max_tokens`）。**真正能跟 3.0 同分母比大小的三格──序列意識──全部落在 3.0 區間內，沒有動**：`sequenceChallenge` 89.2%→86.7%、`sequenceHoldBlindFollow` 21.4%→20.2%、`sequenceRepairAccepted` 95.8%→96.7%，三者區間全部重疊；forced-stop 佔探針比例維持 3.8%（跟 3.0／3.1 一樣，證明四個 P1 修的是判準正確性，不是擴大 forced 觸發範圍）。誤質疑（A01/A09）、查戶口、跟設定矛盾、附和現編四項全部維持安全側。花費：$20.25→$19.72（估算落在 $1.5–2 量級），沒有觸到 $3 上限，也沒有跑 game／難度軸／style／classifier_replay（本輪範圍外）。數字與誠實解讀在 `tools/practice-agency-eval/README.md`「Phase 3.2」節；3.1 留下的槓桿（放寬「何時算強制停」）這一輪仍未動，是下一輪第一個候選項。同分支之後又收了 Codex round-1（`ca345bda`：嚴格問句判準子集化、放寬改鍵回寬鬆訊號、修復點定位不到就不傳）與 round-2（`69ddc4fd`＝最終 HEAD：重複視窗起點不得跨回修復點之前、connected 舊相容退路收斂成只對沒有 marker 的 row 生效；round-2 幾項先判 BLOCK、同一輪修完，未開第三輪覆核，覆核輪數上限本來就是兩輪）；HEAD 上追加一次小額黑箱只驗有效短答免疫（A01/A03/A07/A09、standard on、20 位 × repeat 2、n=160、$0.29），誤質疑仍是 0.0%（0/160）、forced-stop 全部 `no_override`，四支修復沒有動到免疫安全側；記錄兩個休眠風險：`repairedAtUserTurns` 是絕對玩家輪序號，client 端 `kPracticePromptRecentTurns=80` 遠大於單場約 40 則所以現行路徑不會截短，萬一截短過期 marker 會被判超出逐字稿則數而整個丟棄、改從可見起點重算；以及 round-2 BLOCK 項目未經第三輪覆核即收斂。
- 2026-09-04（Phase 3.3）：`agency-phase33` 分支（HEAD `ef635c20`，接手 Phase 3.3 的 `--shape=off|prompt|truncate` 三臂旋鈕接線）新增情境 A27（`f0701067`：裸社群帳號／ID，玩家丟 `debby1993wu`／`ig: chen.yun_`／`@kevin_lin88`，正解是不能宣稱認識這人或有共同朋友——Eric 手機真機回報的「這是我们朋友」共同記憶捏造，沿用既有 `accommodating_invention`／`accommodating_self_fact` 標籤，不需要新標籤），並加一個 runner 級 `shapeDropped` 逐輪 telemetry（`bd888002`，供 truncate 臂事後統計丟了幾則泡泡）；34 支測試綠。三臂黑箱（Eric 核准 $3.50 上限）：`A25,A26,A27,A02,A08`、standard、`--agency=on --style=1`、20 位 × repeat 1（估算若用 repeat=2 會落在 $5–6 超過上限，照指示降 repeat 不砍情境）；三臂各 100 場、480 次生成、零失敗，judge 各 340 筆（解析失敗 0／1／0，皆 <0.5%）。**真正的信號**：`sequenceHoldBlindFollow`（第 3 則以後仍盲目跟題，Phase 3.0／3.1／3.2 三輪唯一沒動過的格）在 truncate 臂第一次出現方向一致的下降——25.8%（off）→19.3%（prompt）→13.3%（truncate），off／truncate 的信賴區間只在邊緣重疊（16.7–18.3），機制上說得通（truncate 是生成後結構截斷，直接砍掉她破案後追加的無來源經歷），但 n=120、repeat=1 還不足以下定論，下一輪建議只對 truncate 單臂加碼 repeat=3 驗證。頭條與 `accommodating_invention`／`asked_with_guess` 三臂互相落在信賴區間內，分不出差異。**A27 誠實結論**：三臂逐字稿都重現了 Eric 回報的行為（「我想起來了」「你是咖啡店那個客人吧」），但 judge 的 `accept_valid_answer` 先決條件（她問過、玩家這句回答到那個問題）把 A27.p2 大多數回覆（off 18/20、prompt 17/20、truncate 15/20）判離 `accommodating_invention` 的審查範圍之外，這是評測本身的已知限制，不是產品行為結論——下一輪要嘛改 A27.p1 的腳本前文、要嘛收緊判準先決條件。安全側維持（`inconsistent_self_fact`／`interrogation` 三臂皆 0%）。花費：$19.22→$18.44（估算落在 $0.78，遠低於 $3.50 上限）。數字、逐句對照與誠實解讀在 `tools/practice-agency-eval/README.md`「Phase 3.3」節。 **確認跑（同分支，未改程式碼）**：只留 off／truncate 兩臂放大到 20 位 × repeat 3（`A25,A26,A27`），180 場 × 2 臂、1,260 次生成 × 2、零失敗，judge 各 900 筆（解析失敗 3／0）。`sequenceHoldBlindFollow` 的 truncate 信號在 3 倍樣本下**站住**——off（20.6%、17.8–24.5）與 truncate（12.5%、9.7–16.1）信賴區間完全分開；`sequenceChallenge`／`sequenceRepairAccepted` 點估計略降但區間跟 off 重疊，沒有可歸因給 truncate 的回歸（`sequenceChallenge` 的 truncate 下緣貼著 80% gate，值得下一輪繼續盯）。同輪先修了 A27.p2 的量測缺口（p1/p2/p4 間插腳本化填充輪，讓 p2 上下文不再吃到 p1 真實生成的『你是？』），但確認跑顯示**判準本身還是沒修到**——`accept_valid_answer` 依然吃掉八成左右的 A27.p2 回覆（off 81%、truncate 83%），`accommodating_invention` 命中率沒有變化（2%／0%）；唯一乾淨可比的是沒有腳本前文的A27.p1。**本輪花費 $2.89，超出 Eric 核准的 $2.00 上限約 $0.89**——估算沿用了混合5 情境的平均單價，低估了 A25／A26／A27 這種隨則數累加上下文的長情境成本，是流程上的估算失誤，已在 README 誠實記錄。數字與逐字對照在 README「Phase 3.3 確認跑」節。**2026-09-04 A27 重跑（封閉語境，$0.70 硬上限）**：Codex R1 修完兩個 A27 量測缺口（`95cc242e` 填充對話改真封閉、`04cee378` Game 修復優先輪截斷免疫）之後，只重跑 A27（off／truncate 各 20 位 × repeat 3，60 場、180 生成、零失敗，judge 各 180 筆，解析失敗 0／1）驗證修正效果；stop-loss 依協定算出的兩個估算法（call-count $0.40、token 估價 $0.84）都被同一時間點的實測餘額差（臂 1 實測僅 $0.22）證偽為過度保守（估算未計入 DeepSeek prompt 快取），改用實測數字判斷後繼續跑完臂 2，兩臂合計實際花費 **$0.31**，遠低於上限，估算方法的落差已在 README 記錄供下一輪校準。**診斷結果**：A27.p2 的 `accept_valid_answer` 灰色地帶從修正前 81%／83%（off／truncate）降到修正後 **43%／33%**，方向正確且降幅顯著，但沒有掉到低——判準本身仍會把「回答了問題」與「回答的內容裡塞了一段查無來源的具體情節」混在一起（`accommodating_invention` 全體仍是 0/180、0/179，逐字覆核 practice_girl_018「那天在酒吧真的很吵」仍被判成 `accept_valid_answer`＋`plausible_self_detail`）；關鍵字粗篩（我想起來／認識／朋友／客人／那天）人工複核後，off 5 則、truncate 3 則是明確的「無中生有共同際遇」捏造，兩臂都還在，封閉語境修正沒有讓行為消失，只是讓 judge 更少誤判。下一輪要收緊的仍是 `accept_valid_answer`／`plausible_self_detail` 判準本身。數字、逐探針表與逐字對照在 README「2026-09-04 A27 重跑（封閉語境）」節。
- 2026-09-04（Phase 3.4 評測）：`agency-phase34-eval` 分支（branch 自 main `bafd61f8`）分兩部分，只動評測工具，不動 production 程式碼。**Part 1（judge 判準 v3）**：`accommodating_invention` 加黃金法則例外——她的回覆宣稱認出玩家本人、共同過去相遇、共同朋友，即使玩家那句話字面上「回答到了問題」也算，不再被 `accept_valid_answer` 的先決條件免責；`plausible_self_detail` 明文排除涉及玩家本人或共同過去的內容；parser 移除 `accept_valid_answer` 與 `accommodating_invention` 的互斥檢查（`adopted_without_asking` 那兩條互斥不變）。`evaluate_agency.ts` 未改動——headline 本來就是 `adopted_without_asking || accommodating_invention`，A27 的 `mustAllow` 從未含 `accept_valid_answer`。新增 judge 測試釘住新 prompt 文字與 parser 接受新組合，`deno test` 35 passed（原 34 + 1）。**Part 2（A27 v3 重評，零新生成，只重判既有 artifact）**：對「A27 重跑（封閉語境）」的 off／truncate artifact 各 180 探針用 v3 judge 重評（`--out` 另存 `-judge-v3.json`，不覆蓋 v2），DeepSeek $14.20→$14.16，兩臂合計花費 $0.04，遠低於 $0.40 stop-loss。頭條隨之如實升高（off 11.1%→15.0%、truncate 13.4%→17.4%），`accommodating_invention` 從全 0 變成 off 3/180、truncate 1/178——**不是行為變差，是量測缺口變窄**。上一節人工複核找到的 5＋3 則共同記憶捏造，v3 抓到 4/8（含一則親眼驗證 `accommodating_invention` 與 `accept_valid_answer` 同時成立），剩下 4 則是兩類誠實殘留缺陷：p1 位置（沒有腳本前文）模型完全沒往下檢查內容；truncate 臂用「…對吧」這種問句形式提出捏造前提時，模型讀成單純確認／質疑而不是宣稱。下一輪具體目標：prompt 補一句「問句形式提出的捏造共同熟人前提，一樣算」。數字與逐則對照在 README「A27 v3 重評」節。分支未推、未合併 main。
- 2026-09-05（Phase 4.0）：`agency-phase40` 分支（branch 自 main `e54885ce`）落地 `ConversationAgencyProfile` 四欄位與四個 planner／threshold consumer，`strangerCuriosity` 併入既有 `questionHabit`、80 位走 preset 預設；1,826 支測試綠（＋18）、等價 harness golden 未重印、離線回放證明三個 consumer 在 A28 真實逐字稿上點火且未擾動 Phase 3.8。本輪零模型呼叫，沒有新的黑箱數字。詳見本檔「Phase 4.0」節。
- 2026-09-05（Phase 4.2）：`agency-phase42` 分支三件事，**零模型呼叫**。(A) 跨輪立場 85.0% 的 15 個失敗探針**逐泡泡**診斷（denominator=100、successes=85、failures：adopted_only 1／asked_with_guess_only 14／both 0）：15/15 的候選組都沒有無條件 `acknowledge`，但第一顆就給猜測有 6 筆、整則零質疑有 2 筆，所以只能說「候選選擇層沒有授權無條件接住」；照 production 的 `truncateAgencyShape` 離線重放＝**改善 1／不變 12／惡化 2**（機器輸出 `out/2026-09-05-p42-stance-bubbles.json`），撤回「truncate 是唯一結構出口」。**不動程式**。(B) `forceAskUser` 排除純反應詞輪，窗口語意改成「玩家**給了內容**的回合數在 [2,6] 內」＋第 10 個 user 回合硬上限（Eric 2026-09-05 拍板「規則綁對方給了什麼，不綁第幾回合」）；七支狀態軌跡／邊界／classifier 差分測試釘住，離線重建 A29.p2 forced **38/40 → 0/40**、A28.p3 仍 36/40、主矩陣 forced 315 → 315 逐格不變。(C) `run_agency.ts` 新增 `--thread-salt`（預設空＝thread id／prompt／生成行為不變，artifact meta 多 `fixture.threadSalt`）。評測指標：`stance_persistence_conditional` 改名 `_strict_conditional`（改回直接讀導出的 `blind_follow`，與舊實作逐字相同）並新增 `stance_persistence_adopted_only`（on 99.0%／off 91.7%）；`curiosity_within_six_content_turns` 真的逐場數前六個內容輪（on 50.0%／off 7.5%）。1,855 支測試綠（＋7）、eval 工具 44 支綠（＋8）、等價 harness 6 綠且 off golden 未重印。Codex R1／R2 兩輪 BLOCKED 的全部 P1／P2／P3 與 Uncertain 已處置（含「對」「是啊」的反應詞邊界契約、truncate 營運風險留給 Eric），詳見本檔「Phase 4.2」節。
- 2026-09-05（Phase 4.3）：`agency-phase43` 分支（branch 自 `d26008c3`，已 rebase 到 `main` `3cadc008`），Eric 定調「第二、三輪對方打很奇怪無關的東西，正常女生會回『？』，這條邊界要死守」。**零模型呼叫**。刀 1＝`agencyPolicyFor` 在欠債輪的 `holdAt` 強制格之後補一格 forced `challenge_relevance`（`clarify_ignored_easy_v1`／`_v1`／`_cold_v1`，難度只調口氣），三道結構閘門是 `answer_candidate` ＋ `aiQuestionedInLoop`（嚴格）＋ `!precedingUserContext`；肯定／否定純短詞（「對」「不是」「沒有」）補進 `REACTION_RE`。**沒有**用 brief 指定的 `lastAgencyAct`（黏住＋記不進去，理由寫在 4.3 節），**沒有**新增 state 欄位。刀 2＝新增 `isQuestionTextTolerant`（剝句尾裝飾後走同一支 `QUESTION_RE`，`isQuestionText` 的真超集），只換 `truncateAgencyShape`——`isQuestionText` 本身被 off 路徑的 `detectTurnSignals` 消費，不能動。離線重建（`replay_plan.ts`，base 用同一份新腳本在 `d26008c3` 拋棄式 worktree 跑）：A06.p2/p3、A10.p1、A12.p1、A14.p2/p3、A25／A26 的 hold 探針與無探針輪共數百格從 bounded 升成 forced，**A01／A03／A05／A07／A09／A11／A13／A15／A25.p9／A26.p9／A28／A29 逐格不變**，`askUserFocus` forced 與 `p4:forcedAskIntent` 總數 base＝HEAD；4.2 那 15 筆有 **7 筆**落進新 forced（另 8 筆卡在 `aiAskedQuestionStrict` 對無標記問句的既有天花板）；truncate 三分從 **1／12／2 變成 5／8／2**（淨效果由負轉正）。1,860 支測試綠（＋5）、eval 工具 49 綠、等價 harness 6 綠且 off golden 未重印、fmt／check／lint 與 base 相同。**未跑黑箱與真機**：只能宣稱結構層不再授權無條件接住、點火位置正確，不能宣稱模型輸出已達成效果；production 旗標 `true`＋`truncate` 全開，本輪直接影響 Eric 真機。
- 2026-09-05（Phase 4.3 R1）：Codex R1 判 **BLOCKED**（兩個 P1 互相牽制）。**已查證** production 分類器在 chat 生成之後才跑（`buildChatPromptBundle` L4391 → `judgeLearningState` L4552，且它吃 `assistantReply`），當輪 coherence 拿不到，所以改用**上一輪已持久化**的分類器判斷。刀 1 閘門重寫成 `unresolvedCount ≥ 1 ∧ answer_candidate ∧ aiQuestionedInLoop ∧ priorCoherence ≠ connected ∧ (有分類器訊號就只認「她上一則真的在澄清」＝新 state 欄位 `aiClarifiedLastTurn`；沒有訊號才退回 `!precedingUserContext` 的保守近似)`——assisted 因此**拿掉**了 P1-2 指出的八回合豁免，而 P1-1 的五輪反例（想去日本）在分類器說她問的是內容問題時**不再被強制**。不共用 `priorChallengeIssued`（那是含 planner 強制過的黏住 OR）。刀 2 擴展到 `utteranceShapeOf`（問句與反應詞都容忍句尾裝飾，`TAIL_DECORATION_RE` 補 ZWJ／VS／keycap），`isQuestionText` 仍不動（off 路徑的 `detectTurnSignals` 在用）。回放工具加 `--ai-clarified=1|0` 夾上下界、狀態推進改成與 handler 對齊。三個臂的重建：`false` 臂新強制格全 0、`null` 與 `true` 臂逐格相同（現有 artifact 全是純丟詞情境，`precedingUserContext` 本來就 false，所以**這兩張表分辨不出新舊閘門**，分辨它的是單元測試）；A28／A29／A25.p9／A26.p9 四臂逐格不變（**A28 的保護來自既有狀態機，不是 `!precedingUserContext`**，R1 前的理由已撤回）。1,869 綠（＋14）、eval 49 綠、harness 6 綠且 off golden 未重印。**殘留成本**：分類器只判得到上一輪，所以「她真的澄清過＋他這輪其實是正當回答」第一次仍會被質疑一次，下一輪才恢復——這是程式的已知成本，不是 Eric 的授權。
- 2026-09-05（Phase 4.3 R2，兩輪用盡）：Codex R2 三個 P1 全在程式面，已修。(1) **撤回** 4.3 加進 `REACTION_RE` 的肯定／否定短詞——它在看她上一句是哪種問題之前就把「是非題→不是」與「澄清→不是」一起免疫，而後者根本沒回答（4.2 那張反應詞契約表因此**回復原狀**）。(2) `aiClarifiedLastTurn === null`（standard／分類器缺席或解析失敗）**一律不強制**，`!precedingUserContext` 退路整條拿掉——**死守邊界只在 assisted（beginner／game）成立**，standard 維持既有二選一。(3) 新增 `EXPLANATION_RE`（因為／意思是／就是說／是說）判成 `self_share`，讓「因為下個月要去首爾出差」這種澄清後的完整解釋不落 `answer_candidate`（成對反例：同一格丟「清邁」仍強制）。另修 U-8（state parser 接受字面 `null`，不再整份作廢）、P2-4（judge prompt 補 `aiChallengedThisTurn` 的反例定義與互斥條款＋prompt／parser 測試）、P3-7（前文 1～8 位改成完整交替並斷言嚴格交替）。離線重建：**`null` 與 `false` 兩臂與 base 逐鍵逐值完全相同**——沒有分類器訊號時整個 Phase 4.3 在全矩陣上是零改動；`true` 臂維持 R1 的分佈（A06／A10／A12／A14／A25／A26 與無探針輪），A28／A29／A25.p9／A26.p9 四臂逐格不變，15 筆仍是 7/15。1,872 綠（＋17）、eval 49 綠、harness 6 綠且 off golden 未重印。**未解的天花板**：沒有解釋標記也沒有第一人稱的正當回答，在分類器判 true 的那一輪仍會被強制一次（生成前沒有能判當前回覆語意的訊號）；整刀的產品效果現在完全繫於分類器 `aiChallengedThisTurn` 的準確率，**只有黑箱量得到**。三個 replay 臂**不是** production 上下界，只是固定假設分支（R2 P2-5）。
- 2026-09-05（Phase 4.1）：`agency-phase41` 分支（branch 自 main `21b43a5c`）落地 Hint／Debrief P2——教練指得出「沒有回答她、連續丟詞」，且她的補救不算玩家得分。新檔 `agency_coaching.ts` 兩支純函式＋21 支測試，hint／prompt 各一個選填參數，門檻與 chat 路徑同源（難度／isGame／角色 agency profile），旗標 `on` 才進 prompt；1,848 支測試綠（＋22）、等價 harness off／shadow golden 未重印且新增白名單釘住「旗標 on 時 11 個 hint／debrief 案例必須不同」。本輪零模型呼叫，沒有新的黑箱數字。Codex R1 BLOCKED（三個 P2＋四個 U）已全數處置，R2 **APPROVED_WITH_RISK**（撤銷 R1 的 P1、無 P0/P1/P2）的一個 P3 與三個 U 也已修完，HEAD `977ec7e8`。詳見本檔「Phase 4.1」節。
- 2026-09-05（Phase 4.4）：`agency-phase44` 分支（branch 自 main `4b381189`）把 Phase 4.3 三臂黑箱的結論搬進 production——新旗標 `PRACTICE_CHAT_MODEL_ROUTING=mixed` 時，**只有她真的要介入的那一輪**改打 Claude Haiku 4.5，其餘維持 DeepSeek；條件與黑箱 runner 的 `--chat-model=mixed` 臂逐字相同（`chatModelFor`）。Claude 失敗當輪退回 DeepSeek 重生並記 `chatModelFallback`；`practice_chat_succeeded` 多 `chatModel`／`chatModelUsage`，旗標不是 `mixed` 時整組 key 不存在。runner 的 haiku 呼叫端改成直接呼叫 production 的 `callClaude`（刪掉自己抄的那份對映），並用一支測試斷言兩邊送出的 request body 逐位元組相同。Codex R1 判 BLOCKED 的兩個 P1（成本觀測失真、證據範圍）、一個 P2、兩個 P3 與四個 U 已全數處置：usage 改整輪累加＋`chatModelCalls`、`standard` 排除在路由外、`onUsage` 搬到 content 驗證之後、mixed telemetry 改逐欄位比對、runner 選模入口直接呼叫 `chatModelFor`。另依 Eric 同日拍板，**越界輪**（`situation === "boundary"`，agency 恆未介入的那一格）也走 Haiku，是獨立於介入輪的第二個入口——這一格沒有黑箱數字，是安全側的產品判斷。Codex R2 的 P1（fallback 事件契約）／P2（200 但丟錯的成本）／P3（原始 bytes 比對）／U1（practiceMode 權威）也已處置。1,897 支測試綠（＋25）、等價 harness 9 綠且 **off golden 未重印**（多枚舉一維 routing env）、eval 工具 56 綠。**本輪零模型呼叫**，沒有新的黑箱數字；旗標預設關，開之前 production 行為逐位元組不變。詳見本檔「Phase 4.4」節。
- 2026-09-05（Phase 4.5a）：`agency-phase45a` 分支（branch 自 main `22c9ef90`）落地 Eric 拍板的三刀——(1) 她問是非題、他回「對／不是」就算回答了（`answeredYesNo`，NO_OVERRIDE ＋ 欠債不累加）；(2) 挑戰／Game 的收尾格與連續越界允許只回一則「（已讀）」（planner `readOnlyAllowed` ＋ 守門白名單）；(3) 不收斂階梯（`lowValueStreak`／`checkedOut` → `check_out` → `read_only` 不打模型 → `cold_return` 冷回且溫度 delta 上限 0）。R1（CTO 依 Eric「持續不收斂」原意）再把 streak 入口擴成「任何 forced agency act，只有 `ask_intent` 不算」、`cold_return` 給獨立 `AgencySituation`、`applyCoherenceDeltaCap` 改 options 物件。practice-chat 1,907 綠（base 1,897＋10）、tools 111 綠、fmt／lint／check 全過、prompt 瘦身 gate 餘裕從 1,012 變 1,027（刀 2 是**取代**形狀行）。離線重建零模型呼叫：A01/A03/A07/A09、A28、A29 三個新 act 兩個界都 0；上界（`--ai-clarified=1`）p43-mixed 740 輪 `check_out` 40／`read_only` 102（A25.p5 17/20、A26.p5 13/20），p4full 1,920 輪 `cold_return` 23（全在 A15）。R2 修完 Codex R1 的三個 P1（守門授權過大、新手沒有硬性不結束、是非問句誤判）與兩個 P2，並連帶補掉一個既有漏洞——守門在最後一次 attempt 丟錯時被拒絕的文字照樣送出去。practice-chat 1,910 綠。真機未驗；Game 在 `check_out` 直接進 debrief 需要 client 配合，本輪不做。

## Phase 4.2 — 立場持久診斷、停滯輪不強制問、評測 salt（2026-09-05）

三個關切：(A) 跨輪立場 85.0% → 95%、(B) 停滯輪的強制問法捏造共同經歷、(C) `initiative` 分支量不到。**零模型呼叫**，全部用既有 artifact 離線重建。Codex R1 判 **BLOCKED**（兩個 P1、一個 P2、三個 P3），逐項處置寫在本節末。

### (A) 跨輪立場：15 個失敗探針逐**泡泡**診斷 → 不動程式

分母出處：`out/2026-09-05-p4full-beginner-on-judge.json`（A01–A15、20 位、repeat 3）。指標＝同一場裡「前一個探針她真的 `clarify_or_challenge` 過」的相鄰配對，成功＝這一輪沒有 `blind_follow`。

**denominator = 100｜successes(strict) = 85｜failures = 15**，拆解：`adopted_without_asking` 只有 1、`asked_with_guess` 只有 14、兩個同時成立 0。15 筆全部落在 `A06.p3`（第三個地名「淺草」）7 筆＋`A14.p3`（「馬尼拉」）8 筆。

結構層在這 15 輪給的候選清單只有兩種，**沒有一筆含無條件 `acknowledge`**：`answer_or_challenge_v1`（10 筆，`["accept_if_answered","challenge_relevance"]`）與 `answer_or_challenge_persist_v1`（5 筆，多一個 `return_to_topic`）。15 筆的 `policyMode` 全是 `bounded`、`situation` 全是 `abrupt_topic_shift`、`unresolvedCount` 全是 2。`accept_if_answered` 是**條件式**接受，不是無條件的 `acknowledge`。

#### 逐泡泡 ordered acts ＋ truncate 離線重放

**機器可重現輸出**：`tools/practice-agency-eval/out/2026-09-05-p42-stance-bubbles.json`（由 `stance_bubbles.ts` 產生，零模型呼叫），每筆含 `{beforeBubbles, firstBubbleQuestion, afterBubbles, dropped, orderedActs, classification}`＋`allowedActSetId`／`policyMode`／`utteranceShape`／`unresolvedCount`，檔頭有 `truncateTally`。

泡泡標籤是**人工閱讀**（challenge＝點破他沒回答／在跳題；guess＝替他補一個意圖；accept＝順著接；other＝自述或語氣詞），不是 judge 輸出——artifact 的 `note` 欄位明寫哪些欄位是機器算的、哪些是人工標的。truncate 欄位是照 production 的 `truncateAgencyShape` 真的跑一次（條件：`isAgencyShapeExperimentTurn` ∧ 泡泡數 > 1 ∧ `isQuestionText(第一顆)`，而 `QUESTION_RE` **錨在句尾**——句尾接 emoji 或「喔」都不算問句）。

| # | 情境／角色／rep | 逐泡泡 ordered acts | truncate 後 | 分類 |
| --: | --- | --- | --- | --- |
| 1 | A06／064／3 | b1 **challenge＋guess 同一顆**「你一直丟地名給我…是玩猜謎嗎 哈哈」 | 單顆，不截斷 | 不變 |
| 2 | A06／**083／1** | b1 **guess**「所以你是要約我去淺草？？」／b2 challenge「還是你只是無聊在報地名啊大哥」 | 只留 b1 | **惡化**（砍掉質疑、留下猜測） |
| 3 | A06／083／3 | b1 guess「阿你是在測試我懂不懂地名喔」／b2 guess「還是要我排行程」／b3 challenge「說清楚一點我比較好接」 | b1 句尾「喔」不算問句 → 不截斷 | 不變 |
| 4 | A06／**004／1** | b1 **guess**「你是想問我有沒有去過淺草嗎」（**整則零 challenge**） | 單顆，不截斷 | 不變 |
| 5 | A06／089／3 | b1 guess「你該不會是在玩地名接龍吧」（**整則零 challenge**） | 單顆，不截斷 | 不變 |
| 6 | A06／006／3 | b1 challenge「你話題跳太快了啦 😅」／b2 other「我剛上完課有點累耶」／b3 guess「你是想約我去玩還是怎樣」 | b1 非問句形狀 → 不截斷 | 不變 |
| 7 | A06／**091／1** | b1 **guess**「你是要約我去淺草玩哦？」／b2 challenge「突然說地名我有點跟不上啦」 | 只留 b1 | **惡化**（砍掉質疑、留下猜測） |
| 8 | A14／064／2 | b1 challenge「你在報地名嗎😂」／b2 other「我沒去過馬尼拉啦」／b3 guess「是要聊旅遊還是單純亂講的」 | 「嗎」後接 emoji → 不截斷 | 不變 |
| 9 | A14／007／3 | b1 other「馬尼拉勒」／b2 challenge「你是要把我當導航是不是」／b3 challenge「一路報城市名喔😂」 | 不截斷 | 不變（judge 判 `adopted_without_asking`＝誤判） |
| 10 | A14／002／1 | b1 challenge「你是在玩地名接龍嗎😂」／b2 challenge「一下好市多一下曼谷現在又馬尼拉」／b3 guess「好啦我猜你想自助旅行？」 | emoji 結尾 → 不截斷 | 不變 |
| 11 | A14／002／2 | b1 guess「你是在測試我有沒有在看喔」／b2 challenge「連三個地名是勒創啥」／b3 guess「還是你想約我去哪一個 我先說我沒錢啦」 | b1 句尾不符 → 不截斷 | 不變 |
| 12 | A14／083／2 | b1 challenge「你是在考我地名嗎」／b2 guess「還是想約我出國」 | 只留 b1 | **改善** |
| 13 | A14／012／2 | b1 challenge「…到底想表達什麼啦😆」／b2 guess「是最近有在規劃旅行嗎？」 | emoji 結尾 → 不截斷 | 不變 |
| 14 | A14／013／2 | b1 challenge「你是要把東南亞城市名唸一輪嗎😂」／b2 guess「還是其實想約我去旅行」／b3 other「不過我明天還要上班勒」 | 不截斷 | 不變 |
| 15 | A14／061／3 | b1 challenge「你是一直在報地名嗎😆」／b2 other＋guess「我沒去過馬尼拉耶，你這是想找我聊旅遊，還是純粹報站名」 | 不截斷 | 不變 |

**ordered acts 統計**：第一顆是 challenge **7 筆**、第一顆是 guess **6 筆**、第一顆是 other **1 筆**、challenge 與 guess 擠在同一顆 **1 筆**。**整則完全沒有 challenge 泡泡：2 筆**（A06／004／1、A06／089／3）。

**truncate 三分統計**：**改善 1 筆**（A14／083／2）、**不變 12 筆**、**惡化 2 筆**（A06／083／1、A06／091／1——第一顆就是猜測且帶問號，截斷正好留下猜測、砍掉後面的質疑）。

#### 能成立的結論（Codex R1 P1，前一版寫過頭）

1. **候選選擇層沒有授權無條件接住**：15/15 的 allowed-act set 都沒有無條件 `acknowledge`。這**不等於**結構層已經充分約束混合輸出——第一顆就給猜測、或整則只有猜測，候選清單擋不到。
2. **`truncate` 不是「唯一結構出口」**：在這 15 筆上 1 改善／12 不變／2 惡化，淨效果為負，且 `QUESTION_RE` 錨句尾讓它在中文語氣詞／emoji 結尾的泡泡上大量失效。前一版「唯一結構出口是 truncate」是錯的推論，已撤回。
3. 剩下的失敗**不是候選清單問題**，但也**不是單一原因**：有服從率（先質疑再補猜測）、有形狀（猜測排在第一顆）、有判準（見下）。本輪不下第二刀。

#### 判準：兩條指標並列，不改舊指標（Codex R1 P2）

Codex 的反駁成立：「好歹有問一句」通過廣義盲從指標，不代表通過「上一輪已質疑、這一輪是否守住」的嚴格指標；直接改分子＝改尺過 gate。所以**舊公式一字不動**，只做兩件事：

- 改名 `stance_persistence_conditional` → **`stance_persistence_strict_conditional`**（公式與 Phase 1 以來的歷史數字逐字相同、可直接比大小）。
- 新增 **`stance_persistence_adopted_only`**（同一批配對、同一分母，失敗只算 `adopted_without_asking`＝Eric 2026-09-03 拍板的頭條定義）。

Phase 4 主矩陣重算（`evaluate_agency.ts`，零呼叫）：

| 指標 | on（n=100） | off（n=48） |
| --- | --- | --- |
| `stance_persistence_strict_conditional` | **85.0%**（78.0–93.0） | **77.1%**（66.7–87.5） |
| `stance_persistence_adopted_only` | **99.0%**（97.0–100） | **91.7%**（83.3–97.9） |
| failures_by_label | adopted_only 1、asked_with_guess_only 14、both 0 | adopted_only 4、asked_with_guess_only 7、both 0 |

兩條線的 on 都優於 off。**release gate 用哪一條由 Eric 決定，本輪不改 gate**（計畫 Phase 4 節的 ≥95% 仍掛在嚴格那條）。

### (B) 停滯輪不強制問他認識管道（結構修）

Phase 4 完整黑箱：A29（玩家只回「哈哈」「嗯嗯」）on 臂 `A29.p2` forced ask **38/40**，同一探針位置兩輪獨立黑箱累積 `accommodating_invention` **4/80**。玩家這句沒給任何內容，卻被 planner 逼著問「他是從哪裡看到你的」，模型只能自己補一個共同場景出來。

**兩處改動**（`turn_response_plan.ts`）：

1. `forceAskUser` 多一個 `agency.decision.evidence.utteranceShape !== "reaction"`——純反應詞輪不強制問。用的是 Phase 4.0 `initiative` 分支同一個結構訊號（`REACTION_RE`），不新增偵測器、不判語意。
2. **窗口語意改成「玩家給了內容的回合數在 [2,6] 內」**（`ASK_USER_WINDOW_USER_TURNS` 現在數的是內容輪，不是原始回合序號），原始 user 回合數只留一條硬上限 `ASK_USER_WINDOW_MAX_USER_TURNS = 10` 防呆。

第 2 點是 **Codex R1 P1**：只做第 1 點的話，第 2～6 回合全是「哈哈」「嗯嗯」時，第 7 回合他終於講了東西也會因為 `userTurnCount > 6` 而**永遠不再強制**，Phase 3.8 的保證在純反應場次整場失效。

> **契約修訂（Eric 2026-09-05 拍板）**：「規則綁對方給了什麼，不綁第幾回合；回合數只當上限防呆。」Phase 3.7／3.8 文案裡的「**六回合內問到他**」自本節起改讀成「**對方給內容後六輪內問到他**」；純反應詞輪不消耗窗口，第 10 個 user 回合是硬上限。

`askedAboutUser` 不會因跳過而黏住——跳過的輪次 `askUserFocus` 是 `undefined`，狀態推進不會標成「問過了」。

**軌跡測試（照 handler 逐輪推進 state，`walkAskUserTrajectory`）**：

| 軌跡 | 腳本 | forced 逐輪 | `askedAboutUser` 逐輪 |
| --- | --- | --- | --- |
| **a** | 第 1 回合分享、第 2～6 回合全反應詞、第 7 回合分享 | `F,F,F,F,F,F,`**`T`** | `F,F,F,F,F,F,`**`T`** |
| **b** | 第 1 回合分享、第 2 回合反應詞、第 3 回合有內容 | `F,F,`**`T`** | `F,F,`**`T`** |
| 硬上限 | 第 1 回合分享、之後 11 個反應詞、第 13 回合才有內容 | 全 `F`（超過第 10 個 user 回合） | 全 `F` |

**離線重建（`replay_plan.ts`，零呼叫）**：

| 探針 | base forced | HEAD forced |
| --- | --: | --: |
| **A29.p2** | **38/40** | **0/40** |
| A29.p1 | 0/40 | 0/40（`why:reaction`） |
| A28.p3（有內容的分享輪） | 36/40 | **36/40** |
| A28.p4 | 1/40 | 1/40 |
| A28.p2／p5／p6 | 0 | 0 |

**主矩陣（A01–A15、20 位 × repeat 3）forced 總數 base 315 ＝ HEAD 315，逐探針差集為空**——這兩處改動只碰得到含純反應詞輪的場次。

`evaluate_agency.ts` 同步加一條 **`curiosity_within_six_content_turns`**：逐場依 `PROBE_ORDER` 排序 `cooperative_turn` 探針、丟掉純反應詞輪（用 production 同一支 `utteranceShapeOf` 判），**只取前六個**（上界直接吃 planner 的 `ASK_USER_WINDOW_USER_TURNS`，不另寫一份會漂掉的 6）；第七個內容輪才問到＝失敗。舊的 `curiosityWithinSix`（整場 OR）保留可比。

> **Codex R2 P1 修正**：前一版只排除 reaction 就把整場 OR 起來，第 7 個內容輪才問也會判成功——名稱與公式不符。已補反例測試（同場七個內容輪、只有第七個 `asked_about_user` → 新指標失敗、舊指標成功；另一支證明插在前面的反應詞輪不佔窗口格）。

專屬矩陣重算（A25/A26/A28/A29，20 位 × repeat 2）：

| 指標 | on | off |
| --- | --- | --- |
| `curiosityWithinSix`（整場 OR） | **50.0%**（35.0–65.0，n=40） | **7.5%**（0.0–17.5，n=40） |
| `curiosity_within_six_content_turns` | **50.0%**（35.0–65.0，n=40） | **7.5%**（0.0–17.5，n=40） |

現行情境檔裡兩條相等：A28 只有 5 個 `cooperative_turn` 探針（都是內容輪），唯一的純反應詞探針 A29.p1／p2 的 kind 是 `stalled_reaction`，本來就不在這個分母裡。差別要在情境檔擴充到七個以上內容輪、或 `cooperative_turn` 出現反應詞時才會顯現——那正是上面兩支反例測試鎖住的格。

### (C) 評測工具：`--thread-salt`，讓 `initiative` 量得到

`seedKey ＝ profileId|visiblePracticeThreadId`（`prompt.ts`），而 `run_agency.ts` 一直傳固定的 `BAKEOFF_THREAD_ID`，所以 `fnv1a(seedKey|回合|initiative) % 5` 在同一位角色的同一個探針位置**永遠是同一個值**——Phase 4.0（repeat 1）與 Phase 4 完整矩陣（repeat 2）都量到 `p4:selfDisclose` 0/40，加大 repeat 沒用。

- 新旗標 `--thread-salt=<字串>`。預設空＝`saltedThreadId("", n) === BAKEOFF_THREAD_ID`，**thread id、prompt 與生成行為都與加旗標前相同**；但 **artifact JSON 不是逐位元組相同**——`meta.fixture` 無條件多一個 `threadSalt` 欄位（Codex R1 P3）。
- `replay_plan.ts` 用 `threadSaltOfArtifactMeta(art.meta)` 讀回（缺欄位／型別不對一律退回空字串），走**同一支** `saltedThreadId` 重建。有一支測試直接讀真的舊 artifact（`out/2026-09-04-p36-mini-artifact.json`，`meta.fixture` 只有 `now`／`threadId`）驗這條退路。
- **不改 production 的 seedKey 算法**：`prompt.ts`／`handler.ts` 零改動。
- initiative 測試改成 **5 個不同的 salt**（不是同一個 salt 配 repeat 1–5），斷言寫成 deterministic fixture：無鹽那一面是 `false`（＝兩輪黑箱 0/40 的來源），5 個鹽裡**已知有命中也有不命中**（證明換鹽真的換骰面）。不再寫任何機率保證。

**沒做**：沒有用新旗標跑黑箱，所以 `initiative` 仍然**沒有任何語意輸出證據**，只是從「量不到」變成「量得到」。而且 salt 會改變整個 `seedKey`，之後若要宣稱語意差異來自 initiative，必須按 `optionalAct` 分層，不能只比 salted／unsalted 總體（Codex R1 Uncertain）。

### 反應詞邊界契約：「對」「是啊」目前**不是** reaction（Codex R2 Uncertain）

`REACTION_RE` 有 `嗯+`／`喔+`／`好+(的|喔|啊)?`／`哈+`／`了解` 等，但**沒有「對」「是啊」**。實測（`agencyThresholdsFor("normal", false)`，單一來回 fixture，零模型呼叫）：

| 玩家這句 | 前一句＝陳述（「我今天差點睡過頭…」） | 前一句＝是非問句（「你今天也很累嗎？」） | 消耗內容窗口 |
| --- | --- | --- | --- |
| **對** | `bare_fragment` → `ambiguous_fragment`／`fragment_no_context_v1`（**她會問意思**） | `answer_candidate` → `situation=null`（有效短答免疫，不介入） | **會** |
| **是啊** | 同上 | 同上 | **會** |
| ~~**對／是啊（4.3 之後）**~~ | ~~`reaction`~~ | ~~`reaction`~~ | ~~**不會**~~ |
| **對，我剛下班** | `self_share` → `situation=null` | `self_share` → `situation=null` | **會** |
| 嗯嗯（對照） | `reaction` → `situation=null` | `reaction` → `situation=null` | **不會** |

`utteranceShapeOf(text, false)`（歷史計數與內容窗口用的那一支）對「對」「是啊」都回 `bare_fragment`，所以**三者都消耗內容窗口**；`decision.evidence.utteranceShape`（planner 當輪用的那一支）只有在前一句是是非問句時才把它們升成 `answer_candidate`。

**契約（4.2 釘的現況；4.3 一度翻面，Codex R2 判定違約後**已整批撤回**，所以下面兩條**仍然成立**）**：

1. 純肯定短詞（「對」「是啊」）**算內容**，會消耗「六個內容輪」窗口。
2. 前一句是**陳述**時，單獨一個「對」會被判成裸片段，她**會問意思**——這是目前的行為，不是本輪引入的。
3. **4.3 曾把肯定／否定短詞納入 `REACTION_RE`，Codex R2 P1-1 判定那違反頂層契約並已撤回**：`utteranceShapeOf` 在看 `previousAiAskedQuestion` 之前就把它們歸成 reaction，等於「你是說韓國嗎？→ 不是」與「你在說什麼？→ 不是」一起免疫，但後者根本沒回答。要分辨兩者是語意，本檔不做。詳見「Codex R2」節。
4. 「契約釘樁」測試（`turn_response_plan_test.ts`）維持釘這張表的現況；4.3 R2 只把標題改成「契約維持」，斷言值與 4.2 相同。

### Codex R2（BLOCKED，評測指標）逐項處置

| 項 | 內容 | 處置 |
| --- | --- | --- |
| **P1** | `curiosity_within_six_content_turns` 沒有限制六個內容輪 | **已修**：逐場依 `PROBE_ORDER` 排序、丟掉 reaction、`slice(0, ASK_USER_WINDOW_USER_TURNS[1])`；兩支反例測試（第 7 個內容輪才問＝失敗；反應詞不佔格）。數字重算見上表 |
| **P2**（等價） | 「舊嚴格公式一字不動」與 diff 不符 | **已修**：改回直接讀導出的 `cur.labels.blind_follow`（就在同一支函式上面由 OR 算出），與 Phase 1 舊實作逐字相同。實測 `out/` 底下 **55 份 judge artifact、41,350 筆有標籤探針、0 筆帶 `blind_follow` key**（它是 `evaluateAgency` 的導出值，`RawAgencyLabels` 型別本身就排除它）；不變量鎖進 `judge_agency_test.ts`（`JUDGED_LABELS` 不含導出欄位、prompt 不出現、parser 就算收到也不吐回） |
| **P2**（truncate 營運風險） | 已開啟的 truncate 與診斷結論的落差 | **不改程式**，見下面「truncate 營運風險」段 |
| **P3**（軌跡） | 不是完整 handler 等價 | **已修**：`walkAskUserTrajectory` 收 classifier signal 參數，描述改成「照 handler 的**結構狀態順序**、classifier 固定值」；新增 `connected`／`disconnected`／`connected+aiChallengedThisTurn` 三個差分，斷言第 7 回合的 forced 與 `askedAboutUser` 逐格相同 |
| **P3**（邊界） | 缺四個邊界 | **已修**：原始第 10 回合可問／第 11 不可（`ASK_USER_WINDOW_MAX_USER_TURNS`）、第 6 個內容輪可問／第 7 個不可（`ASK_USER_WINDOW_USER_TURNS[1]`）。中間輪用「分享＋問句」當內容輪——它消耗窗口但玩家在問她所以不強制，正好把強制推到指定那一格 |
| **P3**（salt） | 沒覆蓋 CLI 典型形態 | **已修**：補「固定 salt `p42`、repeat 1～5」的 deterministic bucket，斷言同時含命中與不命中 |
| **U**（「對」「是啊」） | 契約未定 | **已量、已釘樁**，見上面的表；4.3 接手 |
| **U**（逐泡泡缺可重現輸出） | 只有人工表 | **已修**：`stance_bubbles.ts` ＋ `out/2026-09-05-p42-stance-bubbles.json`（15 筆、`truncateTally` 改善 1／不變 12／惡化 2，與人工表逐筆相符） |
| **U**（自報數字） | 禁工具呼叫無法獨立確認 | 本輪數字仍是自報；命令與 artifact 路徑都寫在本節，可在最終 SHA 上重跑 |

### truncate 營運風險（Codex R2 P2，**留給 Eric 決定**）

**現況**：production `PRACTICE_AGENCY_SHAPE_EXPERIMENT=truncate` **已開**，依據是 Phase 4 的獨立黑箱——A25／A26 上 `sequenceHoldBlindFollow` **22.5% → 14.2%**（見 main `f5368f74` 的重驗）。

**本輪的診斷不推翻那個依據**：4.2 (A) 的 15 筆是**跨輪立場失敗**這個特定切片（A06.p3／A14.p3），在這 15 筆上 truncate 是改善 1／不變 12／惡化 2，淨效果為負。**不得把這 15 筆外推成整體效果**——兩者量的是不同情境、不同指標。

**負淨效果的根因**：`QUESTION_RE` **錨在句尾**，所以「你在報地名嗎😂」「…到底想表達什麼啦😆」「你是在測試我有沒有在看喔」都判不出問句 → 12 筆根本沒被截斷；而真的被截斷的 3 筆裡有 2 筆第一顆就是帶問號的猜測 → 留猜測、砍質疑。

**處置**：`QUESTION_RE` 的句尾錨定由 **4.3 刀 2** 修；**production truncate 維持開**，是否維持由 Eric 決定（本輪不動旗標、不動 `QUESTION_RE`）。

### Codex R1（BLOCKED）逐項處置

| 項 | 內容 | 處置 |
| --- | --- | --- |
| **P1-1** | 連續反應詞會把強制提問延到窗口外且不補問 | **已修**：窗口改成內容輪計數＋硬上限 10；三支軌跡測試（見上表）。契約修訂已由 Eric 2026-09-05 拍板 |
| **P1-2** | (A) 的「14 筆都先點破跳題再補猜測」與表格不符；truncate 主張錯 | **已修**：改成逐泡泡 ordered acts ＋ 真的跑 `truncateAgencyShape`；統計改善 1／不變 12／惡化 2；結論收窄成「候選選擇層沒有授權無條件接住」，撤回「唯一結構出口」 |
| **P2** | 不能藉「定義矛盾」把 85% 改算成 99% | **已修**：舊公式不動，改名 `stance_persistence_strict_conditional`；另立 `stance_persistence_adopted_only` 並列；gate 用哪條由 Eric 決定 |
| **P3-1** | 預設空 salt 不是「artifact 逐位元組舊行為」 | **已修**：程式註解、README、本節都改成「thread id／prompt／生成行為相同，`meta.fixture` 多一個 `threadSalt`」 |
| **P3-2** | initiative 測試的「5 個 salt」描述不實且帶機率誤導 | **已修**：真的用 5 個不同 salt，斷言改成 deterministic fixture（有命中也有不命中），拿掉機率語 |
| **P3-3** | 「分子只剩 1 筆」與前文公式相反 | **已修**：改成 `denominator=100｜successes=85｜failures_by_label`（指標輸出本身也多印這一行） |
| **U** | A14／007／3 疑似 judge 誤判 | 逐泡泡表已列出 b2／b3 都是質疑；**未取得 judge rationale 重判**，仍標為疑似誤判 |
| **U** | `agency.enabled=true、applied=false` 時 `decision.evidence` 是否所有入口都可得 | `computeAgencyDecision` 一律回傳完整 `decision`（含 `evidence`），與 `applied` 無關；Phase 4.0 的 initiative 分支已在同一條路徑消費 |
| **U** | `base|salt|repeat` 的 `|` 分隔碰撞 | 只進 `fnv1a`，沒有任何 consumer 對 `seedKey` 做 `split("|")`；salt 只存在於評測 runner |
| **U** | salt 改變整個 seedKey，不只 initiative | 已寫進上面「沒做」段 |
| **U** | 舊 artifact 相容沒有直接測試 | **已修**：新增讀真實舊 artifact 的測試 |

### Gate（實測數字）

- practice-chat 全套：**1,855 passed / 0 failed / 1 ignored**（base 1,848／0／1；＋7 支 `turn_response_plan_test.ts`）。
- 等價 harness：**6 passed / 1 ignored**，**off golden 未重印**。
- `tools/practice-agency-eval/`：**44 passed / 0 failed**（base 36；＋8 支）。
- `deno fmt --check`（本輪觸碰的 `.ts`）過；`deno check` 全過；`deno lint` **與 base 逐檔逐行相同**。
- prompt 瘦身 gate 仍過（本刀只會讓 on 更短）。

### 風險與未做

- (A) 沒有動程式；`stance_persistence_strict_conditional` 下輪重跑仍會是 85% 上下。`truncate` 在這 15 筆上淨效果為負，但**那不足以推翻它在 A25／A26 上的正效果**——處置見上面「truncate 營運風險」段（production 維持開，根因由 4.3 修，由 Eric 決定）。
- (B) 只有離線 planner 證據與軌跡測試，**沒有生成證據**證明 `accommodating_invention` 4/80 真的下降。反方向：純反應詞多的場次她會**更晚**問到他的事（窗口改成內容輪計數已經把「永遠不問」堵掉，但第 10 個 user 回合的硬上限仍可能讓極端場次整場不問）。
- (C) `--thread-salt` 未在任何真跑用過。
- production agency 旗標是 `true`（全開），(B) 兩處改動會直接影響 Eric 真機。


## Phase 4.3 — 澄清後再丟詞就強制、問句判定容忍表情符號（2026-09-05，Eric 定調）

Eric 原話：「第二、三輪對方打很奇怪無關的東西，正常女生會回『？』『你在講什麼』或直接冷淡，不可能尬聊。**這條邊界要死守。**」兩把刀，**零模型呼叫**，全部用既有 artifact 離線重建。branch 自 4.2 `d26008c3`，收尾時 rebase 到 `main` `3cadc008`。

### 刀 1（主刀）：`clarify_ignored` 強制格　※ **R1 前的版本，閘門已作廢，最終形見本節末「Codex R1 逐項處置與規則最終形」**

**要補的洞**：Phase 3.0 的強制格有一道 `bare_fragment` 閘門（Codex round-1 P1-c：她剛問完、他回一句沒有結構線索的話時，結構層分不出那是不是答案，「你喜歡什麼動物」→「貓」），所以 `answer_candidate` 那一格**永遠不 forced**。Phase 4.2 逐泡泡診斷的 15 筆跨輪立場失敗（A06.p3／A14.p3）**全部**落在這裡：`policyMode` 全 bounded、`situation` 全 `abrupt_topic_shift`、`unresolvedCount` 全 2。

**最終規則**（`agencyPolicyFor`，放在欠債輪的 `holdAt` 強制格**之後**、bounded 之前，所以既有 forced 輪一格都沒被蓋掉）：

```
unresolvedCount >= 1                       ← 外層既有條件
∧ utteranceShape === "answer_candidate"    ← bare_fragment 由上面的 holdAt 格接走，不重疊
∧ aiQuestionedInLoop                       ← 她在這段未解迴圈裡真的送出過帶句尾標記的問句（嚴格判準）
∧ !precedingUserContext                    ← 最近 8 則玩家訊息裡他一次都沒給過真內容
→ forced challenge_relevance
  allowedActs = ["challenge_relevance"]
  situation   = "abrupt_topic_shift"
  allowedActSetId = clarify_ignored_easy_v1 | clarify_ignored_v1 | clarify_ignored_cold_v1
```

回覆形狀走既有 clarify-only（`isAgencyClarifyOnlyTurn` 自動成立＝1 則、只做這一件事），truncate 的適用格（`isAgencyShapeExperimentTurn`）也自動成立，兩處都沒有新增分支。

**三處刻意偏離 brief**（都寫在程式碼註解裡）：

1. **訊號用 `aiQuestionedInLoop`，不是 `agencyState.lastAgencyAct`。** brief 指定後者，但它有兩個致命性質：(a) **黏住的**——只有 forced 那一輪覆寫，bounded 輪沿用舊值，所以一旦點火過，之後每一個裸詞都吃到同一個訊號，連她問內容問題那輪也一樣；(b) **記不進去**——現行 bounded 候選組沒有任何一組是「全澄清型」（`answer_or_challenge_v1` 含 `accept_if_answered`、`fragment_no_context_v1` 含 `acknowledge`），照 brief 的「候選組全是澄清型才算」寫下去等於死碼，Eric 那條序列的第 2 輪就已經拿不到訊號。`aiQuestionedInLoop` 是逐字稿的地面真相、不吃 thread state（standard 也算得出來），而且早就是 `holdAt` 強制格的閘門。因此**沒有**新增 state 欄位，`lastAgencyAct` 的寫入規則一字未改。
2. **`allowedActSetId` 拆成三個**（brief 只指定 `clarify_ignored_v1`）。難度口氣要分檔就得有難度資訊，而 `agencyActsLine` 只吃 `AgencyApplication`。既有慣例就是把難度編進 set id（`answer_or_challenge_easy_v1`），照抄一次比新增參數／欄位小，telemetry 也直接看得出來是哪一檔。口氣行沿用 `AGENCY_SET_LINE`，接在既有 act 說明後面（forced 分支現在也會查一次 `AGENCY_SET_LINE`；既有 forced set id 都不在表裡，逐字不變）。
3. **easy 那句不寫範例句**。brief 給的是「可以溫和一點，像『你在說什麼呀？』」，但本檔的既有界線是「刻意不寫任何範例句，不然 100 位角色會共用同一句口頭禪」（報告 §13 第 8 點），所以改成「語氣可以溫和一點，但還是不要接他丟的詞」。challenge／Game 的「可以只回一個『？』」保留——那是 Eric 指名的產品行為本身，不是台詞範例。

**`!precedingUserContext` 是實測加上去的**（brief 沒有這一條）。沒有它時，A28（配合型玩家六個普通來回，`mustForbid` 含 `false_challenge`）的 p5「感覺是妳會喜歡的那種地方」／p6「對啊 有機會再多聊」各有 **2/40** 被強制質疑——他前面明明講過內容，只是最後兩則剛好沒有第一人稱標記。加上之後那 4 筆歸零，而**全矩陣的真陽性一筆都沒少**（下表兩份重建逐格相同）。已知天花板：窗口是最近 8 則玩家訊息，所以「先正常聊很久、後來才開始丟詞」的場次要等前面的內容滑出窗口才會強制；要放寬就是拿掉這一條，代價是 A28 型的 4/80。

**肯定／否定純短詞補進 `REACTION_RE`**（`對／對啊／不對／是／是啊／不是／沒有／沒錯`，錨定 compact 後的整則）。她問「什麼意思」他回「不是」是**回答**，不是又丟一個詞。連帶兩個效果：不再累積欠債／不介入，也**不再消耗** Phase 4.2 的「六個內容輪」窗口——這翻掉了 4.2「反應詞邊界契約」表的前兩條，該節已改寫。

**有效短答免疫一字未動**：`answer_candidate` ＋ `unresolvedCount === 0` 在 `agencyPolicyFor` 最上面就 `NO_OVERRIDE`，A01／A03／A07／A09 全部走那條，這把刀碰不到（三個難度都有斷言）。

#### 離線重建（`replay_plan.ts`，零模型呼叫；base＝4.2 `d26008c3` 的拋棄式 worktree 跑**同一份**新版腳本）

`out/2026-09-05-p4full-beginner-on.json`（A01–A15、20 位 × repeat 3）：

| 探針 | base bounded → HEAD | 新 forced `clarify_ignored_v1` | 探針類型 |
| --- | --- | --: | --- |
| A06.p2 | 60 → 39 | **21** | `no_context_fragment` |
| A06.p3 | 57 → 29 | **28** | `no_context_fragment`＋`stance_followup` |
| A10.p1 | 60 → 32 | **28** | `no_context_fragment`＋`stance_followup` |
| A12.p1 | 60 → 49 | **11** | `fabrication_probe` |
| A14.p2 | 60 → 48 | **12** | `no_context_fragment` |
| A14.p3 | 58 → 38 | **20** | `no_context_fragment`＋`stance_followup` |
| 無探針輪（`p1` 桶） | 408 → 358 | **50** | — |
| **其餘全部探針** | — | **0** | 含 A01／A03／A05.p1／A07／A09／A11／A13／A15（`mustForbid` 含 `false_challenge` 的那批） |

`out/2026-09-05-p4spec-beginner-on.json`（A25／A26／A28／A29 專屬矩陣）：

| 探針 | base bounded → HEAD | 新 forced | 探針類型 |
| --- | --- | --: | --- |
| A25.p2／p3／p5／p8 | 40→21／40→18／34→14／40→10 | **19／22／20／30** | `sequence_challenge`／`sequence_hold` |
| A26.p2／p3／p5／p8 | 40→30／40→18／35→7／35→3 | **10／22／28／32** | 同上（非地名對照組） |
| A28.p2–p6 | 逐格不變 | **0** | `cooperative_turn`（`mustForbid` 含 `false_challenge`） |
| A29.p1／p2 | 逐格不變 | **0** | `stalled_reaction` |
| A25.p9／A26.p9 | 逐格不變 | **0** | `repair_accept`（`mustForbid` 含 `false_challenge`） |

兩份都驗到：**強制問他一件事（`askUserFocus`）的總數 base＝HEAD**（315／37），**`p4:forcedAskIntent` 總數 base＝HEAD**（240／48）——Phase 3.7／3.8／4.0 的軌跡一格沒動。

#### Phase 4.2 那 15 筆的落點

逐場（scenario｜profile｜repeat）比對：**7 筆落進新 forced**（A06 的 064/3、083/3、004/1、006/3、091/1；A14 的 012/2、061/3），**8 筆維持 bounded**。8 筆全部同一個原因：那一場她在**前一個探針**的回覆沒有句尾問句標記，`aiQuestionedInLoop`（嚴格判準）不成立（逐筆 `askedLoop=false` 已列印確認；`precedingUserContext` 15 筆全 false，不是它擋的）。這是 `aiAskedQuestionStrict` 的既有天花板（中文無標記問句拿不到強制格，Phase 3.2 P1-1 刻意選的安全方向），不是本刀漏接。

#### Eric 真機序列 fixture（挑戰 Game，`conversation_agency_test.ts`）

| 輪 | 玩家 | 她上一則 | 結果 |
| --: | --- | --- | --- |
| 1 | 韓國 | —（開場） | bounded `fragment_no_context_v1`（維持 Phase 2.7） |
| 2 | 日本 | 你在說什麼？ | **forced `challenge_relevance`／`clarify_ignored_cold_v1`** ← Eric 要守的那一格 |
| 3 | 清邁 | 日本還是韓國？（**內容**問題） | **forced `challenge_relevance`**（見下） |
| 4 | 哈哈 | 你到底想說什麼 | `reaction` → 不介入（Phase 4.2 停滯輪界線） |
| 5 | 阿布達比 | 嗯 | forced `end_low_value_loop`（既有 Phase 3.0 行為，沒被蓋掉） |

**第 3 輪與 brief 不符，這是刻意的。** brief 要求「清邁那輪維持既有行為」，理由是她上一則問的是內容問題。結構層**做不到這個區分**：「她問了問題 → 他又丟一個沒有結構線索的詞」在句法上完全同形，唯一能分辨的是她那句的**語意**（澄清 vs 內容），而本檔的界線是不做語意判斷。用 brief 指定的 `lastAgencyAct` 也一樣分不出來（它在第 2 輪已被寫成 `challenge_relevance` 並黏住，第 3 輪照樣點火）。所以第 3 輪也強制，並把它寫成回歸鎖。**代價**：她在迴圈中途問內容問題、他真的用一個沒有第一人稱標記的短句回答（「想去」），會被一起質疑；`!precedingUserContext` 把這個代價壓在「他從頭到尾沒給過真內容」的場次裡。

### 刀 2：問句判定容忍句尾表情符號／裝飾

4.2 的發現：`QUESTION_RE` **錨在句尾**，而她的回覆幾乎都以 emoji 收尾，「你在報地名嗎😂」判成不是問句，`truncateAgencyShape` 因此在 15 筆裡有 12 筆整個失效。

新增 `isQuestionTextTolerant`：先剝掉句尾裝飾（**重用**強制問句判準已經在用的 `TAIL_DECORATION_RE`：空白／emoji／`~～`／`…`／`!！,，.。、`）再走**同一支** `QUESTION_RE`，所以它是 `isQuestionText` 的**真超集**（剝掉的字元永遠不是 `QUESTION_RE` 認的標記）。語助詞「喔／啦／耶」**刻意不剝**——那不是問句標記，剝了會把「好喔」判成問句。

**與 brief 不符的一點**：brief 說「只在 agency on 路徑被消費，確認 off 路徑沒有 consumer」。實查**不成立**——`isQuestionText` 同時被 `detectTurnSignals` 的 `userIsQuestion`／`userQuestionStreak`（`turn_response_plan.ts`）消費，那條路徑旗標 off 也會跑，直接改它會動 golden。所以改成新開一支，只換 `truncateAgencyShape` 這一個 consumer；`utteranceShapeOf` 也不換（換掉會整批改變玩家訊息的形狀分佈，不在本刀範圍，是下一刀的候選）。

**重放 4.2 那 15 筆的 truncate 三分**（`isQuestionText` vs `isQuestionTextTolerant` 對每一筆真實回覆的第一顆泡泡）：

| | 4.2（base） | 4.3（HEAD） |
| --- | --: | --: |
| 改善 | 1 | **5** |
| 不變 | 12 | **8** |
| 惡化 | 2 | **2** |

新增命中的四筆是 A14 的 064/2「你在報地名嗎😂」、002/1「你是在玩地名接龍嗎😂」、013/2「你是要把東南亞城市名唸一輪嗎😂」、061/3「你是一直在報地名嗎😆」——第一顆都是**質疑**泡泡，截斷後正好只留質疑。惡化的兩筆（A06 083/1、091/1）第一顆本來就是**猜測**且帶問號，base 就會截斷，本刀沒有改變它們。淨效果從負轉正。

### Gate（實測數字）

- practice-chat 全套：**1,860 passed / 0 failed / 1 ignored**（rebase 後 base 1,855／0／1；＋5 支）。刀 1 那個 commit 單獨跑也是綠（1,858）。
- 等價 harness：**6 passed / 1 ignored**，**off golden 未重印**（`git status` 全程沒有 golden 檔）。
- `tools/practice-agency-eval/`：**49 passed / 0 failed**（rebase 後 base 相同）。
- `deno fmt --check`：本輪觸碰的 5 支 `.ts` 全過；repo 既有的 4 個未格式化檔（兩份 artifact JSON、README.md、`hint_debrief_spotcheck.ts`）base 與 HEAD **相同**，未動。
- `deno check` 全過；`deno lint` **5 個問題，與 base 完全相同**（皆為未觸碰檔案的既有 `no-unused-vars`／`no-explicit-any`／`ban-unused-ignore`）。
- prompt 瘦身 gate（`prompt_test.ts` 的 ≤80,150 與 agency-on 比 off 少 ≥1,000）仍過——口氣行只多約 15 code units，而且只在 `clarify_ignored_*` 那一輪印。

### 風險與未做

- **黑箱／真機未跑**：本輪只有結構層的離線證據，**沒有任何生成證據**證明模型真的照 forced `challenge_relevance` 回、也沒有量到 `blind_follow`／`false_challenge` 的實際變化。宣稱僅限「結構層不再授權無條件接住，而且點火位置正確」。
- **production 旗標是 `true`＋`truncate` 全開**，兩把刀直接影響 Eric 真機。刀 1 讓 bounded 大量改成 forced（主矩陣無探針輪 50/408、A25／A26 的 hold 探針近半），體感上她會**明顯更常直接質疑**。回滾＝改旗標。
- **誤質疑方向的殘留**：A12.p1（`fabrication_probe`，`mustForbid` **不含** `false_challenge`）11/60 落進強制格；A28 型已用 `!precedingUserContext` 壓到 0，但那是最近 8 則的窗口，不是結構保證。
- **8/15 沒接到**：`aiAskedQuestionStrict` 對中文無標記問句判 false 的既有天花板；要接就得放寬強制格的問句判準，那是另一把刀（會同時放寬 `holdAt` 格，風險更大）。
- 刀 2 只換 `truncateAgencyShape`，`utteranceShapeOf` 仍用錨句尾的判準——玩家自己打「所以你是說我很閒嗎😂」目前仍會被判成低資訊形狀。未修。

### Codex R1（BLOCKED）逐項處置與規則最終形　※ **閘門已再次更新，最終形見下面「Codex R2」節**

R1 判 BLOCKED：兩個 P1 互相牽制（P1-1 說純結構閘門會確定性擊穿有效短答免疫；P1-2 說 `!precedingUserContext` 讓死守邊界最多被延後八個回合）。CTO 定案「結構層分不出『想去日本』與『清邁』，這是語意，交給模型不硬判」。以下是重寫後的內容，**上面「刀 1」節的舊規則已作廢**。

#### 前置查證：當輪分類器拿不到（協調者指定的分岔點）

`buildTurnClassifierMessages`（`temperature.ts`）吃 `assistantReply`——它判的是**她已經生成出來的那一則**。`handler.ts` 的順序是 `buildChatPromptBundle`（L4391）→ 生成 → `judgeLearningState`（L4552）→ 分類器。所以**當輪的 `coherence`／`aiChallengedThisTurn` 在 `computeAgencyDecision`／`agencyPolicyFor` 時結構上拿不到**。走協調者指定的替代路徑：用**上一輪已持久化**的分類器結果。

#### 規則最終形

```
unresolvedCount >= 1                        ← 外層既有（他上一則玩家訊息就已經沒解決）
∧ utteranceShape === "answer_candidate"     ← bare_fragment 由 holdAt 強制格接走，不重疊
∧ aiQuestionedInLoop                        ← 她在這段未解迴圈裡真的送出過帶句尾標記的問句
∧ priorCoherence !== "connected"            ← 協調者指定的顯式閘門
∧ ( aiClarifiedLastTurn === null
      ? !precedingUserContext                 ← 沒有分類器訊號（standard／分類器失敗）的保守近似
      : aiClarifiedLastTurn )                 ← 有訊號：只認「她上一則真的在澄清／指出跳題」
→ forced challenge_relevance
  allowedActSetId = clarify_ignored_easy_v1 | clarify_ignored_v1 | clarify_ignored_cold_v1
```

- **`aiClarifiedLastTurn` 是新的 state 欄位**，來源是分類器讀完她實際生成文字後回報的 `aiChallengedThisTurn`（judge prompt 原文：「assistantReplyAfterUser 是不是真的在問清楚意思或指出跳題／不相關，不是隨口帶過」）。
- **不共用 `priorChallengeIssued`**：那個欄位是 `forcedAct ∈ {challenge_relevance, hold_position} || 分類器` 的 OR，也就是 **planner 強制過就算數**——但「強制過」不等於「她真的照做」，而且它跨輪黏住。這裡要判的是很窄的一件事：她**上一則**到底是在澄清，還是在問一個內容問題。
- **`false` 與缺席意思不同**：`false` ＝分類器說她沒在澄清（→ 不強制）；缺席 ＝ standard 沒有分類器／分類器呼叫失敗（→ 退回保守的結構近似）。parser 與 writer 都區分兩者。
- **`!precedingUserContext` 只留在缺席那條**（P1-2）。assisted 有訊號時完全不看「他前面聊得多好」。

**`priorCoherence !== "connected"` 今天是冗餘的**，有測試證明：分類器判 connected 會寫下 `repairedAtUserTurns`（或走舊 row 的歸零退路），欠債因此是 0，上游的有效短答免疫格就已經接走。留在條件式裡是為了把契約寫明白，不是靠另一個檔案的副作用。

#### 已知差距（**這是本刀最重要的殘留風險**）

分類器在生成之後才跑，所以它只能判**上一輪**。他這一輪的正當回答要到**下一輪**才會被判成 connected 並歸零欠債。也就是說：她上一則真的在澄清、他這一則其實是正當回答時，**第一次仍然會被質疑一次**，從下一輪起才恢復。要消除它只有兩條路，兩條都不在本輪範圍：(a) 生成前多一次分類器呼叫（計畫檔「不做」清單明列禁止「每輪多一個 LLM call」）；(b) 放棄 forced，改用非確定性的 bounded 形狀刀（等於退回 Phase 3.0 的 15/100 失敗率）。**這是程式的已知成本，不是 Eric 的授權**——舊版註解寫「Eric 接受」是錯的宣稱（Codex R1 指正），已刪除。

#### 三張離線重建表（`replay_plan.ts`，零模型呼叫；base ＝ `main` `3cadc008` 拋棄式 worktree 跑**同一份**新腳本）

回放預設沒有 `aiChallengedThisTurn`（artifact 是生成後才有分類器，沒有記當輪值），所以用 `--ai-clarified=1|0` 夾出上下界。`null` ＝缺席（走 standard 近似）、`true` ＝她每一輪都真的在澄清、`false` ＝她每一輪都只是問內容問題。

`out/2026-09-05-p4full-beginner-on.json`（A01–A15、20 位 × repeat 3），格式＝`forced 總數(其中新 clarify_ignored)`：

| 探針 | base | null | true | false |
| --- | --: | --- | --- | --- |
| A06.p2 | 0 | 21(21) | 21(21) | **0(0)** |
| A06.p3 | 3 | 31(28) | 31(28) | **3(0)** |
| A10.p1 | 0 | 28(28) | 28(28) | **0(0)** |
| A12.p1 | 0 | 11(11) | 11(11) | **0(0)** |
| A14.p2 | 0 | 12(12) | 12(12) | **0(0)** |
| A14.p3 | 2 | 22(20) | 22(20) | **2(0)** |
| 無探針輪（`p1` 桶） | 192 | 242(50) | 242(50) | **192(0)** |
| 其餘全部探針 | — | 0 | 0 | 0 |

`out/2026-09-05-p4spec-beginner-on.json`（A25／A26／A28／A29）：

| 探針 | base | null | true | false |
| --- | --: | --- | --- | --- |
| A25.p2／p3／p5／p8 | 0／0／6／0 | 19(19)／22(22)／26(20)／30(30) | 同 null | **0／0／6／0，全 0 新增** |
| A26.p2／p3／p5／p8 | 0／0／5／5 | 10(10)／22(22)／33(28)／37(32) | 同 null | **同 base，全 0 新增** |
| A28.p2–p6 | 逐格不變 | 逐格不變 | 逐格不變 | 逐格不變 |
| A29.p1／p2、A25.p9、A26.p9 | 逐格不變 | 逐格不變 | 逐格不變 | 逐格不變 |

三份都驗到 `askUserFocus` forced 總數（315／38）與 `p4:forcedAskIntent` 總數（240／48）在 base 與三個臂**完全相同**。

**兩件要誠實說的事**：

1. **`null` 與 `true` 兩個臂在這兩份 artifact 上逐格相同**，因為 A06／A10／A12／A14／A25／A26 全都是「他從頭到尾只丟詞」的情境，`precedingUserContext` 本來就是 false。所以**這兩張表證明不了新舊閘門的差別**；證明它的是單元測試（Codex 五輪反例在 `false` 下 bounded、`true` 下 forced）。`false` 臂則證明新閘門真的是開關：分類器說她沒澄清，強制格一格都不開。
2. **A28.p5／p6 在四個臂都完全沒有 `p43:*` 計數**（＝agency 根本沒介入），跟 R1 之前的重建（各 2/40 誤強制）不同。原因是 `replay_plan.ts` 這輪把狀態推進改成與 production 對齊（旗標 on 就推進，不是只在 `applied` 時）。也就是說 **A28 的保護來自既有的狀態機，不需要 `!precedingUserContext`**——R1 之前用它當理由是建立在一份與 production 不一致的回放上，該理由已撤回。

#### Phase 4.2 那 15 筆的落點（新規則下）

`null` 與 `true` 兩臂都是 **7/15**（A06 的 064/3、083/3、004/1、006/3、091/1；A14 的 012/2、061/3）。8 筆維持 bounded，逐筆列印確認全部是 `askedLoop=false`——那一場她在前一個探針的回覆沒有句尾問句標記，`aiAskedQuestionStrict` 的既有天花板（Phase 3.2 P1-1 刻意選的安全方向）。

#### Eric 真機序列 fixture（挑戰 Game）

| 輪 | 玩家 | 她上一則 | 分類器 | 結果 |
| --: | --- | --- | --- | --- |
| 1 | 韓國 | —（開場） | — | bounded `fragment_no_context_v1` |
| 2 | 日本 | 你在說什麼？ | 澄清＝true | **forced `challenge_relevance`／`clarify_ignored_cold_v1`** |
| 3 | 清邁 | 日本還是韓國？（內容問題） | 澄清＝false | **bounded**，接受回答的路留著 |
| 3′ | 清邁 | 同上逐字稿 | 澄清＝true | **forced** |
| 4 | 哈哈 | 你到底想說什麼 | — | `reaction` → 不介入 |
| 5 | 阿布達比 | 嗯 | — | forced `end_low_value_loop`（既有 Phase 3.0 行為） |

第 3 輪從「一律 forced」改成「跟著分類器走」，就是 Codex R1 P1-1 的修正：結構層分不出「清邁」與「想去日本」，所以不硬判。

#### Codex R1 逐項處置

| 項 | 內容 | 處置 |
| --- | --- | --- |
| **P1-1** | 有效短答免疫可被確定性擊穿（五輪反例） | **已修**：閘門改吃分類器的 `aiChallengedThisTurn`；五輪反例＋「想去日本／日本／比較喜歡韓國」三個等價案例在 `false` 下必須 bounded 且保留接受路徑，`true` 下必須 forced；另加涵蓋欠債 0／1／2 × 有無前文的產品不變量測試 |
| **P1-2** | `precedingUserContext` 讓死守邊界失效 | **已修**：assisted 有訊號時整條拿掉；測試把那句真內容放在最近第 1～8 個玩家位置，第二個無關詞全部要被攔下（gap ≤5 時同時斷言 `precedingUserContext` 仍為 true，證明強制不是靠它滑出窗口）。standard 保留為保守近似並寫明 |
| **P2-3** | 兩處測試把安全邊界改成相反結果 | **已修**：`maybeAnswer`、Phase 3.2 `second`、難度門檻 `second` 三處各補「她問的是內容問題（分類器 false）／`priorCoherence=connected`／她沒問過」的 bounded 對照 |
| **P2-4** | `REACTION_RE` 全域語意變更、序列副作用未封 | **已修**：5 個 token × 1～4 次重複 × 陳述／是非問句／開放問句共 60 組，斷言形狀、`situation`、欠債、`forcedAct`、內容窗口與下一輪狀態；另加「reaction 不是修復」的夾心對照。同時讓反應詞容忍句尾標點／emoji |
| **P2-5** | 刀 2 只修輸出截斷 | **已修**：查證 `utteranceShapeOf` 的 caller 全在 agency ≠ off 之後，把容忍版套進去；等價 harness 四面全等、off golden 未重印 |
| **P2-6** | 重建要在新閘門下重跑 | **已修**：三個臂的表見上；無探針輪與 A12 的筆數列出來了 |
| **P3-7** | forced set id 缺快照 | **已修**：七個 forced set id 的快照，只有三個 `clarify_ignored_*` 附加 set 級文字 |
| **P3-8** | 裝飾 fixture 缺舊判準對照 | **已修**：同一組 fixture 同時斷言 `isQuestionText` false、`isQuestionTextTolerant` true |
| **U-9** | 複合 emoji 剝除未測 | **已修**：`TAIL_DECORATION_RE` 補 ZWJ／VS／keycap combining；ZWJ 家庭、膚色、VS、emoji 後接標點都測到；剝完只剩空字串就直接算 reaction（比在 `REACTION_RE` 再抄一次字元類小）。keycap 的數字是內容，仍不算純短詞 |
| **U-10** | 連續同一個新 reaction 詞的 `repeatedExactToken` | **已修**：「不是／沒有／對啊」連 2～3 次都不介入；對照組（真正的裸詞原樣再丟）仍 forced `end_low_value_loop` |

#### Gate（R1 修正後實測）

- practice-chat 全套：**1,869 passed / 0 failed / 1 ignored**（`main` `3cadc008` base 1,855；＋14）。
- 等價 harness：**6 passed / 1 ignored**，**off golden 未重印**。
- `tools/practice-agency-eval/`：**49 passed / 0 failed**。
- `deno fmt --check` 本輪觸碰的 6 支 `.ts` 全過；`deno check` 0 error；`deno lint` **5 個問題與 base 完全相同**。

#### 仍未做

- **黑箱與真機未跑**：沒有任何生成證據證明模型照 forced `challenge_relevance` 回，也沒量到 `blind_follow`／`false_challenge` 的實際變化。
- **`null` 與 `true` 臂在現有 artifact 上無法分辨**，所以新閘門的產品效果只有單元測試層級的證據。要分辨得跑一次帶分類器的真黑箱。
- 8/15 沒接到的那批仍卡在 `aiAskedQuestionStrict` 對中文無標記問句的天花板。

### Codex R2（BLOCKED，兩輪用盡）逐項處置與規則最終形

R2 判 BLOCKED，三個 P1 全在程式面。CTO 定案這是最後一批修，之後直接在分支上跑黑箱。**上面 R1 那節的規則已再次更新**，最終形以本節為準。

#### 規則最終形（R2 後）

```
unresolvedCount >= 1                        ← 外層既有
∧ utteranceShape === "answer_candidate"     ← bare_fragment 由 holdAt 強制格接走
∧ aiQuestionedInLoop                        ← 她在這段迴圈裡送出過帶句尾標記的問句
∧ priorCoherence !== "connected"            ← 顯式閘門（今天冗餘，有測試證明）
∧ aiClarifiedLastTurn === true              ← **只認分類器明確說「她上一則真的在澄清」**
→ forced challenge_relevance / clarify_ignored_{easy_,,cold_}v1
```

與 R1 版的三個差別：

1. **`REACTION_RE` 的肯定／否定短詞整批撤回**（P1-1）。`utteranceShapeOf` 在看 `previousAiAskedQuestion` **之前**就把它們歸成 reaction，等於不管她上一句是「你是說韓國嗎？」還是「你在說什麼？」都一律免疫——但「不是」回得了前者、回不了後者，要分辨就是語意。撤回後回到 4.2 的判定：她問內容是非題且沒有欠債＝既有有效短答免疫；她澄清之後再回「不是」＝走 `clarify_ignored`；連續丟同一個詞會累積欠債並落既有的重複收尾格（`end_low_value_loop`）。句尾裝飾容忍（「嗯嗯!!」「好喔😅」「👨‍👩‍👧‍👦」）留著，那是刀 2 的範圍、不碰哪些詞算反應詞。
2. **`null` 退路整條拿掉**（P1-2）。`!precedingUserContext` 讓同一份逐字稿只因為是 standard 或分類器暫時失敗就改變安全邊界，R1 的兩個 P1 都會從那裡漏回來。**代價：死守邊界只在 assisted（beginner／game）成立**；standard 沒有分類器，維持既有的「接得上就接受、接不上就直說」二選一。這一條寫進程式註解與本節。
3. **解釋標記**（P1-3）。`EXPLANATION_RE = /(因為|意思是|就是說|是說)/`（「我是說」含「是說」、「我的意思是」含「意思是」，不必逐一列），與 `FIRST_PERSON_RE` 同一層級判成 `self_share`。所以「因為下個月要去首爾出差」在她澄清後**不強制**，同一格丟「清邁」**仍然強制**。純字面標記，不判語意、不看字數；只在 agency ≠ off 的路徑被消費。

#### 三張離線重建表（R2 規則下）

| 探針 | base（`main` `3cadc008`） | null 臂 | true 臂 | false 臂 |
| --- | --: | --- | --- | --- |
| A06.p2 / p3 | 0 / 3 | **0 / 3** | 21(21) / 31(28) | **0 / 3** |
| A10.p1 / A12.p1 | 0 / 0 | **0 / 0** | 28(28) / 11(11) | **0 / 0** |
| A14.p2 / p3 | 0 / 2 | **0 / 2** | 12(12) / 22(20) | **0 / 2** |
| 無探針輪 `p1`（full / spec） | 192 / 73 | **192 / 73** | 242(50) / 193(120) | **192 / 73** |
| A25.p2/p3/p5/p8 | 0/0/6/0 | **同 base** | 19(19)/22(22)/26(20)/30(30) | **同 base** |
| A26.p2/p3/p5/p8 | 0/0/5/5 | **同 base** | 10(10)/22(22)/33(28)/37(32) | **同 base** |
| A28.p2–p6、A29.p1/p2、A25.p9、A26.p9 | — | **逐格不變** | **逐格不變** | **逐格不變** |

括號＝其中新的 `clarify_ignored_*`。三份都驗到 `askUserFocus` forced（315／38）與 `p4:forcedAskIntent`（240／48）四臂全等。

**最強的一條**：`null` 臂與 base **逐鍵逐值完全相同**（不是只有 forced 欄位，是整份 counter JSON 相等），`false` 臂也是。也就是說**沒有分類器訊號時，整個 Phase 4.3 在全矩陣上是零改動**；所有行為變化都掛在「分類器明確說她上一則在澄清」這一個布林上。

**這三個臂不是 production 的上下界**（Codex R2 P2-5，已接受）：`replay_plan.ts` 把單一 CLI 值套到每一輪，production 是逐輪 `true／false／缺席` 的混合序列，而每輪結果會回寫 state 影響後續欠債與 forced act，系統不是已證明的單調函式。所以三表只證明**固定假設下的分支差異**，不能宣稱夾住任意混合序列。要證明得用逐輪實際 classifier 訊號回放，或枚舉短場次的混合序列——本輪未做。

**`replay_plan.ts` 與 handler 的等價也未完整證明**（R2 U-9）：本輪只把推進頻率改成與 handler 一致（旗標 on 就推進），但沒有逐輪比對兩邊序列化後的 state，也沒有用 handler 的逐輪訊號。

#### Phase 4.2 那 15 筆（R2 規則下）

`true` 臂 **7/15**（與 R1 相同）；8 筆維持 bounded，逐筆確認全部是 `askedLoop=false`（`aiAskedQuestionStrict` 對中文無標記問句的既有天花板）。`null`／`false` 臂 0/15。

#### 四種來源對同一批逐字稿（P1-2 的驗證步驟）

四份逐字稿 ×（澄清問題／內容問題）×（有無前文），四個來源臂：

| 逐字稿 | true | false | null | standard |
| --- | --- | --- | --- | --- |
| 澄清後丟詞 | **forced challenge** | bounded | bounded | bounded |
| 澄清後丟詞＋前文 | **forced challenge** | bounded | bounded | bounded |
| 內容問題後的短答 | **forced challenge** | bounded | bounded | bounded |
| 內容問題後的短答＋前文 | **forced challenge** | bounded | bounded | bounded |

`null` 與 `standard` 兩欄在 `policyMode`／`forcedAct`／`allowedActSetId` 三個欄位上逐格相同（測試直接斷言相等，不是各自比對常數）。

**要誠實說的**：`true` 臂在四份逐字稿上都會強制，包含「內容問題後的短答」。這正是本刀唯一的判別器——結構層分不出「日本」是回答還是跳題，所以完全跟著分類器走。**邊界的安全性因此等於分類器把「日本還是韓國？」判成 `false` 的準確率**；judge prompt 已補反例定義與互斥條款（`temperature.ts`，並有 prompt／parser 測試釘住），但**真實準確率要黑箱才量得到**。

#### Eric 真機序列 fixture（挑戰 Game，R2 後）

第 1 輪 韓國 bounded；第 2 輪 日本（她澄清＝true）**forced `clarify_ignored_cold_v1`**；第 3 輪 清邁（她問內容問題＝false）**bounded**、同一格改成 true 則 forced；第 4 輪 哈哈 reaction 不介入；第 5 輪 阿布達比 forced `end_low_value_loop`（既有 Phase 3.0）。

#### Codex R2 逐項處置

| 項 | 內容 | 處置 |
| --- | --- | --- |
| **P1-1** | `REACTION_RE` 違反「問過什麼意思後又丟裸詞要質疑」 | **已修**：整批撤回。60 組序列測試改成釘撤回後的行為（第 1 次欠債 0、第 2 次起累積）；U-10 改成斷言連續「不是」會累積欠債並落 `end_low_value_loop`；Codex 列的三個對照（是非題→不是＝免疫、澄清→不是＝攔截、連兩次不得永久免疫）逐條有斷言 |
| **P1-2** | 缺分類器時 R1 的兩個缺陷仍在 | **已修**：`null` 一律不強制，`!precedingUserContext` 拿掉。四來源 × 四逐字稿的表見上，`null` 與 `standard` 直接斷言相等 |
| **P1-3** | 新訊號只描述她上一句，不判玩家這一句 | **部分修**：加解釋標記讓「澄清後的完整解釋」不落 `answer_candidate`（成對案例有測試）。**仍未解**：沒有解釋標記、也沒有第一人稱的正當回答（例如純名詞的正確答案）在 `true` 臂仍會被強制一次——生成前沒有能判當前回覆語意的訊號，這是本刀的結構天花板，見上面「要誠實說的」 |
| **P2-4** | judge 只有正向定義 | **已修**：補反例定義與互斥條款；`buildTurnClassifierMessages` 與 `parseTurnClassification` 各一支測試（含非布林 repair 成 false 並留痕）。實際分類器語意準確率仍待黑箱 |
| **P2-5** | true／false 臂不是上下界 | **已修（改成誠實描述）**：本節寫明它們只是固定假設分支 |
| **P3-6** | `priorCoherence` 是脆弱的跨檔案耦合 | **未加 property test**（兩輪用盡）。現況：條件式留著、有兩支 fixture 測試證明今天冗餘；本節記為待驗風險 |
| **P3-7** | 前文 1～8 位不是完整交替逐字稿 | **已修**：每個玩家訊息之間都插一則她的回覆，並在測試裡直接斷言逐字稿嚴格交替 |
| **U-8** | parser 不接受字面 `null` | **已修**：字面 `null` 視同缺席；round-trip 測試涵蓋缺席／false／true／null／型別錯，並確認欠債與修復點不會被一起丟掉 |
| **U-9** | replay 未完整證明等價 handler | **已寫進本節**，未做 |
| **U-10** | Gate 是實作者自報 | 屬實；命令與 artifact 路徑都在本節，可在最終 SHA 重跑 |

#### Gate（R2 修正後實測）

- practice-chat 全套：**1,872 passed / 0 failed / 1 ignored**（base `3cadc008` 1,855；＋17）。
- 等價 harness：**6 passed / 1 ignored**，**off golden 未重印**。
- `tools/practice-agency-eval/`：**49 passed / 0 failed**。
- `deno fmt --check` 本輪觸碰的 `.ts` 全過；`deno check` 0 error；`deno lint` **5 個與 base 相同**。

#### 仍未做

- **黑箱與真機未跑**（下一步就是在這個分支上跑）。整刀的產品效果現在完全繫於分類器 `aiChallengedThisTurn` 的語意準確率，那只有黑箱量得到。
- P3-6 的 property test、U-9 的 handler／replay 逐輪 state 對拍。
- 8/15 沒接到的那批仍卡在 `aiAskedQuestionStrict` 的中文無標記問句天花板。

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

## Phase 3.4 — 捏造的共同過去（`sharedPastClaim`，2026-09-04）

- **問題**（Eric 真機）：玩家只丟一個 IG handle（`debby1993wu`），她回「這是我們朋友」「喔是你喔 我想起來了／那天在酒吧真的很吵」——宣稱逐字稿與可信自我來源裡都不存在的共同熟人／共同際遇。黃金法則明文禁止，但 prompt 攔不住、結構層（`utteranceShape`／`unresolvedCount`）看不到（純語意）。A27 重跑的逐字覆核也證實兩臂都還在。
- **做法**：沿用 assisted（beginner／game）既有的每輪分類器（它本來就讀完整逐字稿），只加一個欄位 `sharedPastClaim`，走跟 `coherence`／`aiChallengedThisTurn` 完全相同的旗標閘門——旗標 `on` 才進 prompt／schema／parser／telemetry，`off`／`shadow` 逐字不變。消費端只有兩個：delta cap（`Math.min` 上界壓成 0/0，只壓正分不抬負分，`deltaCapApplied` 記 `"shared_past_claim"`）與 telemetry。**不**餵進 `nextConversationAgencyState`／結構層，**不**改生成模型的 prompt，**不**重寫重試。
- **範圍外**：standard 沒有分類器，這條路上這個欄位恆為缺席；要涵蓋 standard 得另外想機制（不加第二次 LLM call 的前提下）。
- **未量 → 已量（2026-09-04）**：`agency-phase34` 分支付費黑箱（beginner＋state=1、shape=truncate、A25/A27、20 位 × repeat 2、$0.14）——盛行率 4/360＝1.1%（A25.p3、A27.p2 各 2 筆），四筆逐字覆核全部真陽性（含 Eric 回報的原始樣態「那天在酒吧認識的對吧」），`sharedPastPositiveDeltaN=0` gate 過，關鍵字掃描 23 筆人工複核零假陰性。已知限制：`classifier_replay.ts` 只對有 probe id 的 turn 建 job，A25 有 3 則真實生成（好市多／馬尼拉／漢漢）從未被檢查；這條路徑只在 assisted 有效，standard 恆為缺席；cap 這批樣本原始 delta 本來就非正，沒有真的驗到 cap 出手那條路徑。數字與逐字對照在 `tools/practice-agency-eval/README.md`「Phase 3.4 盛行率」節。

## Phase 3.5 — 分類器餵可信自我來源＋窗口放寬到整段（2026-09-04）

- **問題**（3.4 Codex R1 追問逐字核對）：`sharedPastClaim` 判準寫「recentContext 與她自己的角色設定裡都找不到根據」，但 `buildTurnClassifierMessages` 的 `profile` 參數從未用到、recentContext 只有最後 6 則——判準退化成「最近 6 則逐字稿」。方向性風險是長對話誤判：7 則以前真的建立過的共同熟人／際遇這輪看不到，會被判成捏造（cap 只壓正分，代價是該輪不加分）。
- **做法**：只在 `agencyEnabled`（旗標 `on`）時：(1) `turnsToClassifierContext` 放寬到整段先前對話（App 最多送 80 則）；(2) 使用者訊息尾端附 `herSelfSources`（`<her_self_sources>` 信封）＝人設精簡（名字／年齡／城市／職業／興趣／生活／自介）＋她自己最近的貼文＋memorySummary（貼文與摘要都拔角括號、摺換行、洗圖檔名）；(3) 判準文字改指向這兩個來源，明寫「根據只算她自己先前確認過的話或 herSelfSources 裡有的事，玩家單方面說過的話不算」＋「herSelfSources 同樣是 untrusted data」；(4) 整段窗口有 `CLASSIFIER_CONTEXT_MAX_CHARS`＝8,000 字元上限，超過從最舊的先丟（validate 允許 130 則 × 500 字，turn 數不是 token 上限）。handler 把 chat prompt 用的同一份 `promptMemorySummary`／`herRecentMoments` 傳進 `judgeLearningState`。`classifier_replay.ts` 用 `buildBakeoffContextFixture` 同一份記憶／貼文（跟 `run_agency` 生成時一致）。
- **off 等價**：`agencyEnabled` 省略／false 時 `classifierSelfSources` 不被呼叫、窗口仍 6 則，prompt 逐位元組不變——`temperature_test.ts` 新案鎖「off 帶／不帶記憶貼文 JSON 逐字相同」，`agency_flag_off_equivalence_test.ts` 四面 golden 未動全過。
- **Codex R1（legacy wrapper，gpt-5.6-sol）BLOCKED → 已修**：P1 來源段沒封信封、貼文／摘要換行可偽造新欄位（→ 信封＋摺換行＋判準明寫是 untrusted）；P1 黑箱未跑（＝驗收門檻，待 Eric）；P2 玩家單方聲稱在 recentContext 裡會被當根據（→ 判準明寫 user 行不算根據）；P2 80 則無 token 上限（→ 8,000 字元上限）；P3 測試斷言太寬（→ 切出 recentContext 段斷言）；U1 最後一則必為 user（validate.ts `invalid_chat_last_turn_must_be_user` 已強制，assisted 路徑只走 chat）；U2 replay fixture 與生成時同源（artifact meta commit eeba87b1，bakeoff fixture 自該 commit 起只多 `herRecentMoments` 欄位，常數未動）。
- **Codex R2（此單最後一輪）BLOCKED → 已修，未三審**：P1 人設欄位與 postDate 未過 seal（上游雖是 `GIRL_PROFILES` 靜態目錄與 `isoDateOf` 切 10 碼的常數，仍一律 seal；測試注入 `</her_self_sources>` 於 selfIntro／interestTags／postDate，斷言開／關標籤各只一次）；P2 coherence 判準沒指向來源（→ 加一句「玩家接的是她自己貼文的話題也算 connected」）；P2 「整段先前對話」措辭與 8,000 上限不符（→ 改「先前對話，最舊的可能被截掉」）；P2 herSelfSources 只證明她自己的事、不能證明「一起」（→ 判準改寫：根據只認 recentContext 裡她自己說過或確認過的話；她講自己單獨經歷不算、講成跟玩家一起才算）；P3 上限改算渲染後的行（含前綴與換行）且最新一則永遠保留；P3 注入測試補全欄位。Codex 明言黑箱未跑只是 dormant merge 的驗收風險，不是 BLOCKED 原因。
- **已知風險**：被 8,000 字元截掉的早期確認若之後再被提起，會被判成捏造（同 3.4 的 6 則窗口問題，只是門檻從 6 則變 8,000 字元）。memorySummary 是模型生成的摘要，這裡標成「只證明先前聊過的話題；不能單獨證明她認識玩家、有共同朋友或一起經歷過什麼」——跟 chat prompt 的 Reality Anchoring 同方向，但 DeepSeek 會不會照這句判要靠黑箱驗。整段窗口讓分類器 prompt 最長多到 8,000 字元（token 成本上升，未量）。
- **驗證**：deno check／fmt／lint 過；`temperature_test`＋`learning_state_test`＋`agency_flag_off_equivalence_test`＋`moments_memory_test` 89 過；practice-chat 全套 1802 過（唯一失敗 `moments_image_gate_test` 的資產路徑案在 main 基線同樣失敗，與本改動無關）；tools 44 過。**付費黑箱未跑**：要用既有 beginner artifact 跑 `classifier_replay.ts` 對比 coherence／sharedPastClaim 分佈（約 $0.3），等 Eric 說「跑」。

## Phase 3.6 — 自傳守門走分類器欄位（`accommodatingSelfFact`，2026-09-04，Eric 選 A）

- **問題**：3.2 殘留病「點破同一則夾帶自編經歷」（「你是說阿布達比嗎／我剛從那邊飛回來耶」「清邁我去過」），prompt 行「不要順口講你自己跟這個詞有關的經歷」（2.5）量到無效；計畫原本的 `practice_chat_semantic_guard.ts`（第二 attempt 重寫）Eric 不選——3.1 量到重試 86% 仍犯，且分類器是回覆送出後才判。
- **定義（Eric 2026-09-04 糾正，照夥伴 Bruce 的兩條）**：人設與生活經驗本來就是模型即興補的，隨時補充不是問題，「去過／沒去過」都不算錯。要抓的只有兩種：(1) **矛盾**——新補的設定跟已建立的（人設、職業生活、貼文、記憶、她自己先前說過的話）衝突（「一致性優先於順從」）；(2) **迎合**——補出來的設定明顯是為了順著玩家剛丟的詞走（玩家沒頭沒尾丟「清邁」→「清邁我去過」；「你不是喜歡爬山嗎」→「對啊我常去」但來源沒寫）。她自由補的、跟玩家的話無關、也不衝突的細節（我剛下班、今天門診很累）不算。第一版寫成「查無根據就算」是錯的，已改。
- **做法（A）**：assisted 每輪分類器加欄位 `accommodatingSelfFact`；閘門、parser（repair-first、壞值退 false）、telemetry（`accommodatingSelfFact`＋只在修過時存在的 `accommodatingSelfFactRepaired`）、delta cap（0/0 只壓正分，`deltaCapApplied="accommodating_self_fact"`；與 `sharedPastClaim` 同時為真記先壓到的那條）全部與 `sharedPastClaim` 相同；rule／stub／schema 只在 agency `on` 時存在，off／shadow 逐位元組不變。herSelfSources 人設行加「職業生活：professionPrompt」（平均 59 字），讓分類器看得到她合法的職業日常。`classifier_replay.ts` 摘要多 `accommodatingSelfFactN／ExplicitN／RepairedN／Rate`、`accommodatingPositiveDeltaN`（gate＝0）。
- **黑箱**：對既有 beginner artifact（360 探針，A25 地名序列＋A27 裸帳號）回放，看盛行率、gate，true 的筆數全部人工看；關鍵字底稿（我去過／剛從／飛回來…）13/360 命中、人工約 5 筆是迎合式（阿布達比剛飛回來、清邁去過一次、曼谷剛回來、曼谷去過一次），其餘（我剛下班、朋友去拍照）是假陽性對照。
- **Codex R1（legacy wrapper，gpt-5.6-sol，對第一版定義）APPROVED_WITH_RISK → 已處理**：P2 判準對「職業日常」同時落在 true／false 兩條 → 加職業生活素材＋定義改寫後「自由補充不算」已是主句；P3 `requireCoherence` 註解「旗標 ≠ off」誤導 → 全部改「旗標 on（shadow 同 off）」，接線本來就是 `agencyMode === "on"`；U shadow 逐位元組不變＝`agency_flag_off_equivalence_test` 四面 golden（含 telemetry）已鎖且全過；U 既有 fixture 補齊＝三個 Phase 2 時代的 index_test fixture 補 `sharedPastClaim`／`accommodatingSelfFact`；U 語意成效＝黑箱待 Eric「跑」。
- **Codex R2（此單最後一輪，對改名後的定義）APPROVED_WITH_RISK → 已處理，未三審**：P2 中性直接問答（「你去過清邁嗎」→「有，去年去過一次」）沒被明寫成不算 → 判準加這一句；P2 「不可回溯改寫」沒明寫 → 加「改口（我剛才講錯了其實去過）也算矛盾；事情有新進展（上週終於去了）不算」；P3 測試註解殘留舊「來源沒寫」理由 → 改成「迎合」；U 新語意未經黑箱＝待 Eric「跑」（回放要看：5 筆迎合案例是否 true、8 筆對照是否 false，另加中性問答／改口／新進展三類邊界）；U 早期自傳事實被 8,000 字元截掉又沒進摘要時偵測不到＝已知限制（同 3.5）。
- **黑箱（2026-09-04，Eric「跑」）**：第一版判準 360 探針 **0 true**——人工確認的 5 筆迎合案例全放過（判準寫「明顯迎合」讓模型自己下定義＋不算清單太長）。判準改寫成可核對的兩點（經歷掛鉤玩家剛丟的詞 × 來源與她先前的話都沒有；正反例各一句；不算清單縮短），關鍵字命中的 8 場 45 探針小規模重測：**5/5 迎合案例判 true、7/7 對照判 false**、gate 0、repair 0（約 $0.04）。改寫後的判準未跑完整 360（約 $0.3，待 Eric）；判準改寫在 Codex 兩輪之後，未三審。數字與逐字在 `tools/practice-agency-eval/README.md`「Phase 3.6 分類器回放」節。
- **完整 360（第二版判準，Eric 第二次「跑」）**：**5/360＝1.4%，5/5 真陽性、非關鍵字回覆 0 誤判**；對人工 5 筆底稿召回 4/5（「好啦那我有去過曼谷一次」這次 false，mini 時 true＝temperature 0 仍抖動）；gate 0，3 筆 cap 真的把 +1 壓到 0（3.4 的 sharedPast 從沒真的壓到過，這是 cap 第一次出手）。**發現**：coherence 判準逐字相同的兩次跑，逐探針分佈差到 ±7/40——3.5 宣稱的「coherence 變嚴 3–6%」在雜訊帶內，不算效果；之後比 coherence 要同 prompt ≥3 次。


## Phase 3.7 — 認識管道的首要好奇點（AGENCY-05 第一刀，2026-09-04，Eric「好 繼續」）

- **範圍**：Phase 3「她會主動好奇」那一半的最小一刀。「每輪最多一問、不連續兩輪查基本資料」reply-style 的 `questionBudget` 已經在管（連續反問歸零、normal／challenge 首輪不反問、澄清型不吃預算），本輪不重做；`UserFactSlot` 覆蓋度狀態不做（YAGNI：生成模型看得到整段逐字稿，「問過或他講過就別問」由它自己核對）。
- **做法**：`acquaintance_origin.ts` 十種管道各加 `curiosityFocus`（≤60 字，不是台詞：交友軟體問自介哪一點吸引他、IG 陌生私訊問從哪看到你、朋友介紹問跟介紹人怎麼認識但不猜名字…）；`prompt.ts` `acquaintanceOriginPrompt` 只在 agency 分支加一行「想先知道：…。自然碰到才問、一輪一句；問過或他講過就別問」，標題與後兩行併短以守住 agency prompt 淨少 ≥1,000 的既有 gate（餘量 1,012 → 加行後只剩 944，併短後回到 ≥1,000）；off 分支逐字不變（harness 全過）。
- **量尺**：judge 加正向標籤 `asked_about_user`（她這則有沒有問他一件關於他本人的事；問意思／指出跳題／拉回前一題不算；查戶口仍由 `interrogation` 抓）；`ProbeKind` 加 `cooperative_turn`；新情境 **A28**＝配合的玩家六個普通來回、從不自我介紹；`evaluate_agency` 新指標 `curiosityWithinSix`＝**以場為分母**，前六回合至少一則 asked_about_user 的比例（gate ≥80%）。
- **黑箱（A28 on／off，20 位 × 2，$≈0.5）＝負面結果**：`curiosityWithinSix` off 25%（10/40）→ on 30%（12/40），gate 80，區間重疊。根因是結構：34/40 場的 questionHabit 是 rare／selective／reciprocal，planner `questionBudget` 多半 0、每輪計畫印「這輪不反問」，一行好奇點壓不過；curious 型也只 3/6 場問到他。prompt 臂再次零效果（同 3.3）。**建議下一刀＝結構刀**：agency on、前六回合、連貫且非問她、她上一則沒問、本場未問過（state 加布林）→ 強制 `questionBudget=1` 且計畫行印「這輪問他一件事：X」。數字在 `tools/practice-agency-eval/README.md`「Phase 3.7 黑箱」節。
- **Codex R1（legacy wrapper，gpt-5.6-sol）BLOCKED → 處置**：P1 黑箱 gate 未過＝成立（30% vs 80）；P1 每個 curiosityFocus 是兩三題、一句問完就是查戶口＝成立 → 全部改成單一問題；P1 `curiosityWithinSix` 可跨 mode 混算＝理論成立、實務上 on／off 是分開的 artifact（key 裡的 `mode` 是 practiceMode），加 evaluator 測試鎖「以場為分母、同場多探針 OR」並在 README 分臂報；P2 泛用「你呢」也算＝接受（廣義 gate，管道命中另做人工抽查）；P2 併短丟了「不一次複述」＝prompt 臂整段刪除後不存在；P2 `asked_about_user` 與 `interrogation` 手寫案例暗示互斥 → 改成可同時成立並加案例；U 管道是 session 維度＝是（`buildAcquaintanceOrigin` 由 profile×threadId 決定，fixture 固定 thread）。**決定（Fable）**：prompt 臂零效果，照 3.3 先例刪掉、`acquaintanceOriginPrompt` 恢復與 main 逐字相同；`curiosityFocus`（單題）、judge 標籤、A28、指標保留給結構刀。


## Phase 3.8 — 「這場問他一次」結構刀（AGENCY-05，2026-09-04，Eric「好」）

- **做法**：3.7 的好奇點資料不進 prompt，改由 planner 消費。`planTurnResponse` 在 agency 旗標 on、第 2～6 個 user 回合、玩家這句連貫（agency 沒介入）且不是在問她（situation neutral／share）、她上一則沒在問（aiQuestionStreak 0）、這場還沒問過（thread state `askedAboutUser`）、act 不是界線／收尾時，把 `questionBudget` 強制 1 並在 plan 帶 `askUserFocus`；`renderTurnPlan` 把「最多問一句」換成「這輪問他一件事：X，一句就好」。`nextConversationAgencyState` 多一個參數把 `askedAboutUser` 黏住（一場只強制一次；之後多常問回到 persona 習慣）。handler 傳 `responsePlan.askUserFocus !== undefined`；telemetry `conversationAgency.askUserForced`（布林）。runner 在強制那一輪也推進狀態。
- **開關**：`ASK_USER_EXCLUDED_HABITS`（預設空；要讓最冷的角色一場都不問，放 "rare"）、`ASK_USER_WINDOW_USER_TURNS=[2,6]`。
- **off 等價**：bundle 只在 `agencyPrompt`（on）時傳 `askUserFocus`，planner 的 `forceAskUser` 另外還要 `agency.enabled`；off／shadow plan 逐字不變（harness 全過）。
- **黑箱**：A28 on（state=1）對 3.7 的 off 臂（off bytes 未變，直接沿用），看 `curiosityWithinSix`（gate ≥80）與 `interrogation`。
- **黑箱（A28 on＋state=1，20 位 × 2；off 沿用 3.7 臂）**：v1 計畫行「這輪問他一件事：X，一句就好」→ judge 場級 35%（off 25，gate 80）；結構規則「問到管道好奇點」**0/40 → 10/40**、p3（強制點）她問他 5→18/40、interrogation 0。另一半強制輪她把那一問花在眼前話題（晚餐）。v2 綁緊措辭「只有這件事…別問其他問題」→ 好奇點 **2/40** 更差，已退回 v1。judge 標籤 `asked_about_user` 雜訊大（同句有時 true 有時 false），場級 35% 不可信；v1 vs v2 的 10 vs 2 未量雜訊帶。**gate 未過。**
- **Codex R1（legacy wrapper，gpt-5.6-sol）BLOCKED**：P1 gate 未過＝成立（產品結果，非程式）；P2-1 混合句「我剛下班，妳今天呢？」→ situation 已是 question 但再明寫 `!signals.userIsQuestion`＋測試；P2-2 runner 與 handler 狀態軌跡不等價（runner 只在介入／強制輪推進、classifier signal 傳 null）＝既有 3.0 以來的近似，寫明為 runner 已知限制；P3 好奇點空白 → trim；U2 shadow telemetry 多 `askUserForced:false`＝shadow 契約允許只多 telemetry（harness「shadow 唯一可不同的是 telemetry」）；U3／U5 未處理（forcedAsk 互斥靠 `!agency.applied`；口語問句 streak 偵測）。
- **v3 形狀刀（Eric「A」）＝沒有更好，退回 v1**：管道好奇點 6/40（v1 10）。離線重跑 planner 證明 v1／v3 的強制都在 p3 觸發 36/40 場，形狀行有進 prompt；瓶頸是生成模型對「問指定問題」的服從率（一半會問他、一到兩成問到指定的事）。**3.8 停在 v1**：對使用者是正向（管道問題 0→10/40、零查戶口）但 gate 80 未過；判準與雜訊帶都還沒量。剩下的路：生成後檢查＋重試（3.1 先例 86% 仍犯）、或 planner 給台詞（違反「不加台詞」）——都不建議現在做。

## Phase 4.0 — ConversationAgencyProfile（2026-09-05）

- **做法**：新檔 `supabase/functions/practice-chat/agency_profile.ts`，四欄位 0–4 的 `ConversationAgencyProfile`（`initiative`／`topicPersistence`／`ambiguityTolerance`／`skepticism`，型別本體放 `conversation_agency.ts` 以維持「不 import reply_style」的依賴單向）。`AGENCY_BY_PRESET` 14 個 preset 各一筆、`AGENCY_BY_PROFILE_ID` 前 20 位代表角色逐位人工定值，其餘 80 位走 preset 預設，查不到回中性 `{2,2,2,2}`；`agencyProfileFor(profileId)` 只吃 profileId（`STYLE_BY_PROFILE_ID` 是純資料表，與 `PRACTICE_REPLY_STYLE_ENABLED` 無關，維持 agency／reply-style 解耦）。
- **`strangerCuriosity` 不新增欄位**：報告 §7.3 的第五個欄位值域（rare／selective／reciprocal／curious）跟既有 `ReplyStyleProfile.turnTaking.questionHabit` 完全相同，且 Phase 3.8 已經在消費它（`questionBudget` 的 habit 分支、`ASK_USER_EXCLUDED_HABITS`）；再開一個同義欄位只會製造兩份會漂掉的真相。`preferredCuriosityTargets` 同理不做——Phase 3.7 的認識管道好奇點已經供應 `askUserFocus`。
- **80 位走 preset 的決定**：報告要求「先 20 位代表角色人工 mapping，再擴到 100 位」；擴的方式是 preset 級預設（14 筆人工配置）而不是再手寫 80 筆，因為 preset 本身就是人工配置的行為維度，逐位重寫只會複製 preset 的值又多 80 個漂移點。
- **四個 consumer**（都只在旗標 ≠ off 時生效，off 路徑逐位元組不變）：`ambiguityTolerance ≤1` → 無前文裸片段的 `firstFragmentActs` 收回 forced `["ask_intent"]`（Phase 2.7 把三個難度全降成 bounded，這裡只讓低容忍的人收回來，範圍不變、有效短答免疫不受影響）；`skepticism ≥3` → `holdAt = max(1, base−1)`、`≤1` → `min(3, base+1)`（`forceEndLoopBeforeChallenge` 仍只由難度決定）；`topicPersistence ≥3` → 欠債輪候選多一個 `return_to_topic`，`allowedActSetId` 換成 `answer_or_challenge_persist_v1`／`_easy_v1`（`AGENCY_SET_LINE` 前半段逐字不變、句尾加「或直接把話拉回你上一題」）；`initiative ≥3` → `planTurnResponse` 在 agency on、`!applied`、**`utteranceShape==="reaction"`（停滯輪）**、`situation==="neutral"`、`optionalAct===null`、非 cautious、非玩家問句、第 2 個 user 回合起，以 `fnv1a(seedKey|回合|initiative) % 5 < initiative−2` 的機率（3＝1/5、4＝2/5）把 `optionalAct` 設成 `self_disclose`。難度表仍是 base，profile 只做位移；§7.4 的口氣文案本輪不動。
- **接線**：`agencyThresholdsFor(difficulty, isGame, profile?)` 第三參數選填（省略＝逐字舊行為）、`computeAgencyDecision` 加 `agencyProfile?` 透傳、`AgencyApplication` 多一個唯讀 `profile`，`prompt.ts` bundle 在 off 也算（純函式、無輸出效果），planner 只在 `agencyPrompt`（on）時吃。telemetry `conversationAgency.profile` 記四個數字（旗標 off 時整個 key 本來就不存在，所以沒有重印 golden）。
- **planner 消費以 reply-style 旗標開為前提**：`prompt.ts` 的 `const responsePlan = style ? planTurnResponse(...) : null` 是 Phase 3.8 以來的既有結構，所以 **3.8 的 forced ask 與 4.0 的 initiative 在 `PRACTICE_REPLY_STYLE_ENABLED` 關掉時都不會跑**（production 實測為 `true`，本輪不重構）。**門檻的三個 consumer 不受此限**——`ambiguityTolerance`／`skepticism`／`topicPersistence` 走 `computeAgencyDecision`，與 style 無關，旗標關掉照樣位移難度表。這條界線寫在 `prompt.ts` 該段註解，並由 `agency_profile_test.ts` 的 style-off bundle 測試釘住（Mia `tol=0` 仍 forced `ask_intent`、Zoe `tol=4` 同一句仍 bounded、`responsePlan === null`）。
- **Gate**：practice-chat 全套 1,808 → **1,826 passed / 0 failed / 1 ignored**（新增 18 支 `agency_profile_test.ts`；ignored 是既有的 `moments_image_gate_test.ts` 素材缺失，base 相同）；等價 harness 5 passed / 1 ignored（golden 未重印）；`tools/practice-agency-eval/` 36 passed；`deno fmt --check`／`deno check` 過；`deno lint` 4 個問題與 base 完全相同（皆為未觸碰檔案的既有 `no-unused-vars`／`no-explicit-any`）。prompt 瘦身 gate（agency-on 比 off 少 ≥1,000 code units）仍過。
- **離線回放（零模型呼叫，`replay_plan.ts`）**：
  - **既有 artifact `out/2026-09-04-p38-a28-on.json`（A28、40 場）**：`p4:forcedAskIntent` p1 **base 0 → HEAD 16/40**（低容忍角色的第一個裸片段）、`p4:persistSet` p5／p6 **base 0 → HEAD 各 1**。同一份 artifact 用**同一份新版 `replay_plan.ts`** 在 base `e54885ce` 的拋棄式 worktree 上跑過（Codex R1 P3 要的對照），Phase 3.8 軌跡兩邊逐格相同（p3 forced 39/40、每個 `why:` 計數一字不差）。
  - **停滯輪 fixture（100 位 × 3 探針，合成逐字稿，非模型輸出）**：A28 的腳本裡**沒有任何一則玩家回覆是 `reaction` 形狀**（掃過 `out/` 全部 artifact，零命中），所以收緊後的 initiative 在既有 artifact 上一次都不觸發（`p4:selfDisclose` 12 → 0），改用合成 fixture 量：停滯輪（「哈哈」）`p4:selfDisclose` **base 0 → HEAD 7/100**；對照的有內容分享句（「今天超熱的 我剛下班」）兩邊都是 **0/100**；第 1 個 user 回合那一列兩邊都是 **23/100**（那是既有 style `responseBiases` 的自曝，回合數 1 進不了 initiative 分支，正好證明計數器沒有把舊行為算進來）。
- **未跑**：黑箱（DeepSeek／Claude 一律零呼叫，本輪無新產品指標）；Hint／Debrief 是 Phase 4.1，不在本輪。
- **Codex R1（legacy wrapper）BLOCKED**：**P0＝Phase 4 明列的黑箱 Gate 完全未跑**（20 位 × 15 情境 × 3 的 on/off、style 差異、安全／邀約 golden、p95 <10%、A02／A04–A06／A12 逐案覆核），等 Eric 核准後才跑，本輪不處理。已修：**P1-1**（`situation==="neutral"` 不等於停滯）→ initiative 加結構條件 `utteranceShape==="reaction"`，並補「有內容的分享句任何 seed 都不觸發」的反例測試；報告的另一半「有自身興趣」沒有結構訊號可用（本檔界線只認句法標記），不做並在註解寫明。**P1-2**（style 旗標關時 initiative 死路）→ 不重構 `responsePlan = style ? … : null`，改成把界線明寫進 `prompt.ts` 註解與本節，並補 style-off 的 bundle 級測試證明門檻 consumer 活著。**P2**（共用骰子）→ initiative 改用獨立 hash 域，加測試斷言命中場的 `bubbleCount` 不是常數。**P3-1**（`reserved_repairer` 註解「最不主動」與 `initiative:1` 矛盾）→ 改「很少主動開題」。**P3-2**（p1 沒有 base 對照）→ 用同一份新版 `replay_plan.ts` 在 base 重跑，數字見上。未處理的 Uncertain 三項（forceAskUser＋self_disclose 同輪的生成證據、persist 句尾的服從率、`strangerCuriosity` 替代設計的聯合測試）都要黑箱或生成輸出才能判，隨 P0 一起等。

**Codex R2（2026-09-05，第二輪＝最後一輪）：BLOCKED。** 處置：
- P0「整個 Phase 4 的 gate（20 位 × 15 情境 × 3、style 比值、邀約 golden、p95）未跑滿」：本刀是 AGENCY-07 的第一片（資料＋consumer），只跑 8 情境 × repeat 1（$0.96）；是否以 dormant（production 維持 shadow）併入、把完整矩陣留到 Phase 4.1 之後一次跑，由 Eric 決定。Codex 自己也寫「若限定為 shadow-only dormant merge，可由 Eric 明確接受風險」。
- P0「黑箱跑在 `06f22540`、受審 HEAD 是 `6ed608bf`」：`git diff 06f22540..6ed608bf` 只有 README 與四個 artifact JSON，`supabase/` 與 `tools/practice-agency-eval/*.ts` 逐位元組相同（已驗）。
- P1「五欄位只做四欄、planner 依賴 reply-style 旗標」：設計決定（`strangerCuriosity`＝`questionHabit`；planner 在 style 層是 3.8 以來的前提，production `PRACTICE_REPLY_STYLE_ENABLED=true`），記為 Eric 接受的契約修訂，不另做 consumer。
- P1「四個 consumer 沒有都拿到輸出層證據」（skepticism 分組 n=4、initiative 0/40 固定 thread id 擲骰沒中、persist 只證 set id）：記風險，留給 Phase 4.1 之後的完整矩陣；initiative 要用不同 thread id 才量得到。
- P1「A29 Lumi 一則 `accommodating_invention`（你那天怎麼會出現在我工作的那邊）」：來自 3.8 forced ask 的既有行為（on 臂 A29.p2 forced 17/20），非本刀引入；n=1，記入已知殘留病。
- P1「replay `p4:selfDisclose` 計數混入 style 層自曝」：已修 `45ca48c6`（只認 agency on＋reaction 形狀＋initiative≥3）；重跑 on artifact：A25.p9／A26.p9 從 4/20 歸 0，A29 仍 0。
- P2 統計措辭（Wilson 不含 judge 誤判與角色群聚）、P2 獨立 hash 只證非完全綁定、production thread id 分布未證、forceAskUser＋self_disclose 共存無生成證據：全部記風險，未三審（兩輪上限）。
## Phase 4.1 — Hint／Debrief 指出「你沒回答她」（2026-09-05）

夥伴報告 §P0-7（評分把低品質中性輪誤當關係成長）與 §11 表格 P2 那列；Phase 4 節的「Hint／Debrief P2」。

- **新檔 `supabase/functions/practice-chat/agency_coaching.ts`**（兩支純函式，只消費 `conversation_agency.ts` 已算好的結構證據，不做語意判斷、不加 regex、不看字數，也不 import `hint.ts`／`prompt.ts`，維持依賴單向）：
  - `hintAgencyCoachingFor(turns, agencyState)` → `{ kind: "answer_her_question" | "stop_dropping_words" | "none", unresolvedCount }`。第一道閘門是 `agencyPolicyFor(detectAgencyEvidence(...)).situation !== null`——結構層自己認定玩家上一則沒接上才點火，所以有效短答（她剛問完、他答了、零欠債）在上游就被 `NO_OVERRIDE` 接走，永遠回 `none`。接著「欠債 ≥2 或同詞重複」→ `stop_dropping_words`，否則「她剛問了／狀態 `lastAgencyAct ∈ {ask_intent, challenge_relevance, return_to_topic}`」→ `answer_her_question`。
  - `debriefAgencyLedgerFor(turns)` → `{ fragmentTurns, topicShiftTurns, loopTurns, repairTurns }`；逐則玩家訊息重走 `detectAgencyEvidence → agencyPolicyFor`，狀態用 `nextConversationAgencyState` 推進。
- **渲染**：`hint.ts` 在既有 stageGuidance 後面補**一行**（不重寫既有段落）；`prompt.ts` 仿 `appliedHintTurns` 的 `hintAssistedTurns` 寫法，接在 hintAccountability 後面渲染一段 `agencyStructuralLedger(hidden evidence)`，明寫「這些**需要她補救的**輪次不算他的分：dateChance 與 highlights 不得把『她接住了』寫成他的表現；改進建議至少一條要具體引用其中一則」。兩者在省略／`none`／全 0 時都不渲染，prompt 逐字不變。debrief tool schema 未改。
- **`shadow` 的契約是「只多記 telemetry」，不是「console JSON 也逐位元組相同」**（Codex R1 P1 是 packet 把契約寫錯，程式未改）。以 `agency_flag_off_equivalence_test.ts` 為準：只有**未設／`off`／亂填**是四面全等（該檔第 1293–1299 行的 `for (const env of [undefined, "off", "亂填"])` 對 `observableDigest` 整份比對），`shadow` 走的是同檔第 1300–1316 行——註解明寫「shadow 的契約是『只多記 telemetry，不動任何對外行為』」，只斷言 `messages`／`response`／`rpc` 三面等於 golden，`telemetry` 刻意不比；同檔第 1337 行另有一支反向測試要求 shadow 的 telemetry **必須**與 golden 不同。所以 hint／debrief 在 `shadow` 多一個 `conversationAgency` key 是契約允許的，與 chat 路徑（Phase 2.7 起）同一個慣例。
- **門檻與 chat 路徑同源**（派 Codex 前補修的 P1）：兩支函式都吃一個必填的 `AgencyCoachingContext`（`difficulty`／`isGame`／`profileId`），內部走 `agencyThresholdsFor(difficulty, isGame, agencyProfileFor(profileId))`——與 `prompt.ts` 的 chat 路徑逐字同一組輸入。**刻意沒有預設值**：用預設的一般難度會讓同一場對話在 chat 與 debrief 兩層算出不同的介入輪（踩坑：同一道守門在兩端各自帶預設值會漂）。`hintAgencyCoachingFor` 今天其實**證明性地不吃門檻**（`situation !== null` 這道閘門的每一個出口都與 thresholds 無關），仍然照傳，只為了讓兩層永遠不可能各自帶一份預設值。
- **接線**：`handler.ts` hint 路徑算 `hintAgencyCoachingFor`（thread `agencyState`，讀不到＝純結構近似）、debrief 路徑算 `debriefAgencyLedgerFor`（assisted／standard 兩個 options 分支都傳），兩者都只在 `agencyMode === "on"` 時進 builder；`shadow` 算但只進 telemetry；`off` 連算都不算。兩條 `practice_chat_generation_outcome` 各多一個 `conversationAgency` telemetry（hint 記 `coachingKind`／`unresolvedCount`，debrief 記三個計數與 `repairTurnCount`；旗標 off 時整個 key 不存在，與 Phase 2.7 的 chat 慣例相同，所以沒有重印 golden）。

### 兩處刻意偏離 brief（都寫在程式碼註解裡）

1. **`aiAskedQuestion`（寬鬆）取代 brief 指定的 `aiAskedQuestionStrict`**。嚴格判準是寬鬆的真子集，且刻意只認句尾標記——中文最常見的無標記問句（「東東是誰」、「阿布達比？那是哪裡」的最後一個子句）全部判 `false`，這一格會直接變死碼。錯誤方向也不同：嚴格判準守的是**強制停止解讀**的閘門（判多＝她沒問就被強制停），這裡判多只是多印一行教練指引，而且上游的 `situation !== null` 已經先確定玩家結構上沒接上。
2. **`stop_dropping_words` 比 `answer_her_question` 先判**（brief 的規則是條列順序）。欠債 ≥2 的局面她幾乎一定剛問過話，answer 先判會讓 `stop` 實質上是死碼；而「把前面那個詞講清楚或接回她的問題」本來就含「回答她」，嚴重的先判資訊量更大。

### 近似的界線

- `debriefAgencyLedgerFor` 的 `classifierSignal` 一律傳 `null`（debrief 手上沒有每一輪當時的分類器輸出），與 `tools/practice-agency-eval/replay_plan.ts --state=1` 是同一種近似。少掉「分類器判 connected」這個修復來源，方向是**偏保守**：欠債留得比正式路徑久不會憑空多出介入輪，但沒有 `repairedAtUserTurns` 時 `detectAgencyEvidence` 的舊 row 相容退路（上一輪 coherence 是 `connected` 就把欠債歸零）會生效，所以連續片段之間夾一則結構修復就會斷開帳。實測 A28 型逐字稿因此只記到 1 輪，而 hint 的逐點判斷記到 2 次點火——兩者不保證一致，這是刻意的。
- **門檻位移在真實 A25 逐字稿上算不出差別**，這是判準的既有天花板不是沒接線：`holdAt` 只在 `aiQuestionedInLoop`（**嚴格**問句判準）＋`bare_fragment` 同時成立時才打得開，而 A25 裡她的每一句反問都是中文無標記問句（「東東？誰啊」「到底在講哪個」），`aiAskedQuestionStrict` 全判 false。測試因此鎖兩件事：真實 A25 上 easy／challenge／`practice_girl_001`（skepticism 4）／`practice_girl_003`（skepticism 1）四種 ctx 的帳**完全相同**；換成她的反問帶句尾標記「呢」的同形態 fixture，一般難度第 3 則落 `loopTurns`、easy 與 skepticism 1 的角色落 `topicShiftTurns`，`repairTurns` 不變（`situation !== null` 不吃門檻，變的是 loop／shift 分帳）。
- hint 是 assisted 專用，standard 走不到；debrief 的 standard 模式沒有持久化狀態，本來就是純結構近似。
- **null-classifier 近似的風險方向（誠實修正，Codex R1 U）**：先前寫「方向偏保守、不會憑空多出介入輪」是**沒有差分證據的宣稱**。實際方向是雙向的——少掉一次 live classifier 的 `connected` 修復，欠債會留得比正式路徑久，**後續輪次因此可能被判成介入輪**（`unresolvedCount` 跨過 `holdAt`／落進 `abrupt_topic_shift`），也就是有機會**多扣分**而不是少扣分；另一方面，沒有 `repairedAtUserTurns` 時 `detectAgencyEvidence` 的舊 row 相容退路（上一輪結構 coherence 是 `connected` 就把欠債歸零）又會把帳斷開，方向相反。兩股力道誰大沒有量過。要證明得跑「中途 classifier=connected 的正式狀態回放」對「全 null 回放」的 repair-turn 差集，本輪未做（需要每一輪當時的分類器輸出，既有 artifact 沒有記）。
- **`repairTurns` 的序號基準（Codex R1 U）**：序號是「這次 `request.turns` 裡的第 N 則玩家訊息」。`debriefAgencyLedgerFor` 與 `debriefTurnsToPromptTranscript` 吃的是**同一份** `request.turns`，所以模型看到的逐字稿與序號在 server 端一致。但 client 只送最後 80 則（`kPracticePromptRecentTurns`），若 UI 同時展示完整未截斷紀錄，使用者可能把「第 1 則」理解成整場第一則。**client 端未驗**（本輪沒有超過 80 則的端到端 fixture，也沒有改 client）；真要根治是標「最近 N 則」或改用穩定 turn id／內容引用。

### Gate（實測數字）

- practice-chat 全套（worktree root 為 cwd）：**1,848 passed / 0 failed / 1 ignored**（base 1,826 / 0 / 1；＋21 支 `agency_coaching_test.ts` ＋1 支等價 harness 新測試）。
- 等價 harness：**6 passed / 1 ignored**（**off golden 未重印**）。分面寫法（Codex R2 P3；不要再用未限定觀測面的「逐位元組相同」）：**未設／`off`／亂填**＝`messages`／`response`／`rpc`／`telemetry` **四面**全等於 `7f1d6d6c` golden；**`shadow`**＝`messages`／`response`／`rpc` **三面**全等，`telemetry` 由另一支測試要求**必須不同**；**`true`**＝11 個真的走到 Claude 的 hint／debrief 案例 `messages` 必須不同，`response`／`rpc` 仍全等。舊的「非空洞檢查」只涵蓋 chat，註解寫「hint／debrief 不讀 agency 旗標」——4.1 之後不成立，所以新增一支白名單測試：旗標 `true` 時 11 個真的走到 Claude 的 hint／debrief 案例的 **`messages` 欄**必須與 golden 不同（Codex R1 P2：舊版比合成 digest，而 on 一律多一行 telemetry，歸因不到 prompt），名單外（`hint／standard` 的 403）必須相同；同一支測試順帶斷言所有 side case 的 `response` 與 `rpc` 兩欄在 on 時都不變。
- `tools/practice-agency-eval/`：**36 passed / 0 failed**。
- `deno fmt --check`（124 檔）過；`deno check` 全過；`deno lint` **4 個問題，與 base 完全相同**（皆為未觸碰檔案的既有 `no-unused-vars`／`no-explicit-any`）。
- **prompt 長度（on − off，code units，含 R1／R2 的補句）**：hint `answer_her_question` **+86**、`stop_dropping_words` **+95**；debrief 三輪介入無交集 **+186**、三輪有 Hint 交集 **+249**、序號滿 10 個（12 輪場）**+201**。目標 <300，過。

### 點火證據（零模型呼叫，逐字稿取自 `tools/practice-agency-eval/out/2026-09-05-p40-beginner-on.json`）

每場取所有「以她的話結尾」的前綴當 hint 決策點；ledger 走整場逐字稿。

| 情境 | 角色 | hint kind 分佈 | ledger（frag／shift／loop／介入輪） |
|---|---|---|---|
| A25 | 001 | answer 2、stop 6、none 1 | 1／7／0／`[1..8]` |
| A25 | 008 | answer 2、stop 6、none 1 | 1／7／0／`[1..8]` |
| A25 | 064 | answer 2、stop 6、none 1 | 1／**5**／**2**／`[1..8]` |
| A26 | 001 | answer 2、stop 6、none 1 | 1／**4**／**3**／`[1..8]` |
| A26 | 008 | answer 1、stop 6、none 2 | 1／6／1／`[1..8]` |
| A26 | 064 | answer 1、stop 6、none 2 | 1／6／1／`[1..8]` |
| A28 | 001 | answer 1、stop 1、none 4 | 1／0／0／`[1]` |
| A28 | 008 | answer 1、stop 1、none 4 | 1／0／0／`[1]` |
| A28 | 064 | answer 1、stop 1、none 4 | 1／0／0／`[1]` |
| **A01**（有效短答） | 001 | **none 2** | **0／0／0／`[]`** |
| **A01** | 008 | **none 2** | **0／0／0／`[]`** |
| **A01** | 064 | **none 2** | **0／0／0／`[]`** |
| **A09**（有效短答） | 001 | **none 2** | **0／0／0／`[]`** |
| **A09** | 008 | **none 2** | **0／0／0／`[]`** |
| **A09** | 064 | **none 2** | **0／0／0／`[]`** |

**同一情境的角色之間會不一樣**（Codex R1 P3）：A25 的 064 是 `1／5／2`、001／008 是 `1／7／0`；A26 的 001 是 `1／4／3`、008／064 是 `1／6／1`。差異來自她實際生成的回覆不同（逐字稿不同），不是 profile 門檻位移——門檻在這批逐字稿上算不出差別，理由見上面那條天花板。

（門檻改成與 chat 同源之後重跑，整張表逐格不變——原因就是上面那條天花板：這批逐字稿裡她的反問都拿不到嚴格問句判準。）

A01／A09 全 `none`／全 0 是設計上的硬條件（有效短答永遠不得被質疑，報告 §6），這裡拿真實逐字稿驗到。

### Codex R1（legacy wrapper）BLOCKED 的處置

- **P1「shadow 的 console JSON 多了 `conversationAgency`」**：packet 把契約寫錯，**程式未改**，依據見上面那條「`shadow` 的契約是只多記 telemetry」。
- **P2「on 非空洞測試只比合成 digest」**：已修，改比 `messages` 欄並加 `response`／`rpc` 不變的斷言。
- **P2「`repairTurnCount` 被 10 的上限截掉」**：已修，總數改由 `DebriefAgencyLedger.repairTurnCount`（三個分類計數之和）出，handler 直接讀；prompt 序號仍最多 10 個，12 輪 fixture 兩件事都斷言。
- **P2「`appliedHintTurns` 與 `repairTurns` 重疊」**：已修，ledger 段補「其中若有 hintAssistedTurns 也列到的輪次，照 Hint 歸責規則歸給『這輪教練路線』，不算他的缺口」，加兩集合重疊的 prompt fixture 測試。
- **U「最終 dateChance 判準會覆蓋」**：實查——`finalDateChancePrompt` 在 `hintAccountabilityPrompt`（含 ledger 段）**之前**，依 prompt 自己的「順位＝越後越終局」註解，ledger 是後者，不會被覆蓋。仍在 ledger 段補一句「上面的最終 dateChance 判準也適用這一條」並加順序斷言測試。
- **U「hint 行對上 `allowNoPasteableReply`」**：已修，措辭改成「建議句（若有）要…」（不再寫「兩顆球都要」），並補「這一行不改本輪方向與邀約判斷」；新增 `acceptsNoPasteableHint=true` × 兩種 kind 與 Game 模式交叉的 snapshot 測試。
- **U「null-classifier 風險方向」／U「client 顯示序號」**：不改程式，改成誠實描述，見上面「近似的界線」兩條。
- **P3「點火摘要省略角色差異」**：下表改成逐角色列。

### Codex R2（legacy wrapper）APPROVED_WITH_RISK 的處置

R2 正式撤銷 R1 的 P1（舊 packet 契約寫錯），無 P0／P1／P2。

- **P3「程式註解仍寫單向風險」**：已修，`debriefAgencyLedgerFor` 的註解改成與本檔一致的雙向敘述，並補「這份帳記的是結構層判定**需要**她介入，不保證她真的補救了」。
- **P3「Gate 摘要的 shadow 措辭矛盾」**：已改成上面的分面寫法。
- **U「hint 用已含最新玩家輪的持久化 state 重算」→ 實測沒有重算**。新增測試走完整 chat→state→hint：`detectAgencyEvidence`→`agencyPolicyFor` 算出欠債 1→`nextConversationAgencyState`（classifierSignal `disconnected`）→ 用那份 state 對「同逐字稿＋她的回覆」呼叫 `hintAgencyCoachingFor`，`unresolvedCount` 仍是 **1**、kind 是 `answer_her_question`（沒有被升級成 `stop_dropping_words`）。原因寫在 `detectAgencyEvidence` 既有註解：「一律從逐字稿重算，不把 `prev.unresolvedCount` 當起點——同一批 turn 會被重走，兩者相加會重複計數」。`prev` 只供應 `repairedAtUserTurns`／`priorChallengeIssued`／`lastCoherence`。
- **U「重疊輪次座標」→ 確認是兩個不同座標系，已修**。`AppliedHintTurn.turnIndex` 是**逐字稿 index**（`validate.ts` 以 `turnIndex < turns.length` 與 `turns[turnIndex]?.role !== "user"` 驗），`repairTurns` 是**第 N 則玩家訊息**（1-based）。原本只留一句「若有 hintAssistedTurns 也列到的輪次」等於要模型自己換算。改成 server 端換算：`prompt.ts` 新增 `userTurnOrdinalOf()`（兩個座標系的唯一換算點），算好交集後明列「其中第 N 則是他照 Hint 送出的…」，沒有交集就不印那一句。fixture 改用含**連續兩則 AI 訊息**的逐字稿，讓 index 5 ≠ 玩家序號 3，測試斷言印的是 3 不是 5。
- **U「ledger 記的是需要介入、不是她真的補救了」**：屬實。`debriefAgencyLedgerFor` 只看玩家輪的 `decision.situation !== null`，不檢查下一則 AI 回覆有沒有真的拉回來。渲染文字改成「這些**需要她補救的**輪次」；**不另證明實際 repair**（要證明得看下一則 AI 回覆是否 challenge／return_to_topic，那是語意判斷，本檔界線不做）。
- **殘留風險（Eric 接受才併）**：黑箱與真機未跑，所以只能宣稱「結構證據已接入 prompt」，**不能宣稱模型輸出已達成歸責效果**；Codex 建議 production 維持 `shadow`，啟用 `on` 前先排除持久化 state 重算（本輪已排除）與輪次座標（本輪已修）兩項。

### 未跑

- 黑箱（DeepSeek／Claude 一律零呼叫）：沒有任何「教練真的說出『你還沒回答她』」或「dateChance 不再把她的補救算成他的表現」的生成證據——這一刀只證明結構化證據有進 prompt、且點火位置正確。Phase 4 節列的完整矩陣（20 位 × 15 情境 × 3、style 比值、安全／邀約 golden、p95）仍與 Phase 4.0 的 P0 一起等 Eric 核准。
- 真機：未驗。

## Phase 4.4 — 混合模型路由（2026-09-05，Eric 拍板）

**根據**：Phase 4.3 三臂黑箱（見 `tools/practice-agency-eval/README.md`「Phase 4.3 三臂模型黑箱」節）——`mixed` 是唯一同時壓過頭條 gate（3.4%）與 `sequenceHoldBlindFollow`（1.7%）的臂，品質分數最高（6.5/9），成本只有純 Haiku 的 86%。Eric 拍板上 production。

### 旗標與路由

- 新旗標 `PRACTICE_CHAT_MODEL_ROUTING`（server-only，與 agency 旗標獨立）：`"mixed"` ＝開；未設／`off`／任何其他值一律關（`chatModelFor` fail-closed，與 `agencyModeFor` 同款）。
- 路由條件（runner 的選模入口 `runnerChatModelFor` 直接呼叫 production 的 `chatModelFor`，不是抄一份）：`routingFlag === "mixed"` ∧ `agencyMode === "on"` ∧ `practiceMode ∈ {beginner, game}` ∧（**介入輪** `agencyDecision.applied === true`，planner 真的注入了 guidance，不是「允許」；**或越界輪** `situation === "boundary"`）。agency `off`／`shadow`、`standard`、或兩個入口都不中 → DeepSeek。
- **越界輪也走 Haiku**（2026-09-05 Eric 拍板）：劃界線是最不能出錯的一輪。越界輪的既有 planner 優先權高於 agency（`computeAgencyDecision` 只在 `situation === "neutral"` 保留決策），所以那一輪 `applied` 恆為 false——這是**獨立的第二個入口**，不是介入輪的子集。判斷用 `chatPromptBundle.situation`（本刀新曝露的欄位，來自既有的 `classifySituation`，與 `PRACTICE_REPLY_STYLE_ENABLED` 無關；`responsePlan` 在 style 關掉時是 null，不能用）。**這一格沒有黑箱數字**：Phase 4.3 的三臂矩陣量的是介入輪，越界輪走 Haiku 是產品判斷（安全側寧可貴一點），不是評測結論。
- **`standard` 一律不進路由**（Codex R1 P1）：Phase 4.3 三臂黑箱只量過 `beginner ＋ --state=1`，standard 連分類器都沒有（4.3 的死守邊界在 standard 本來就不成立），介入率與品質都沒量過。**`game` 併入後要先跑一次小黑箱再開旗標**（Eric 安排）。
- 另外兩道現實條件在呼叫端檢查（不進純函式）：`CLAUDE_API_KEY` 存在且 `deps.callClaude` 有注入。缺任一個就當作沒開（chat 路徑本來就要求 DeepSeek key 才進得來，退路一定在）。
- 兩個入口命中時的呼叫參數：`model=claude-haiku-4-5-20251001`、`max_tokens=200`、`temperature=0.9`、`timeoutMs=30000`、system 走 `callClaude` 內建的 `cache_control: {type:"ephemeral"}`、messages ＝ `buildChatPromptBundle` 的同一份（DeepSeek 路徑吃的也是這一份）。回傳文字進**同一條**後處理：繁簡轉換、內部標籤守門、L4 守門、括號旁白剝除、`truncateAgencyShape`、重試迴圈。
- Response body 的 `provider`／`model` 照實回報（旗標關著時仍是 `deepseek`／`deepseek-v4-flash`，逐字舊行為）。client 目前不讀這兩格。

### fallback

Claude 呼叫失敗（逾時／4xx／5xx／`claude_empty_content` 等解析失敗）→ **當輪立刻退回 DeepSeek 重生**，並記一行 `practice_chat_model_fallback`（含 attempt 與錯誤訊息）。fallback 之後這一輪不再打 Claude（第二個 attempt 直接走 DeepSeek），避免同樣的失敗付兩次錢。守門層退回（旁白、標籤外洩）不算模型失敗，仍由既有重試迴圈用同一支模型重來——那是共用後處理，兩條路徑一致。

### telemetry 與成本護欄

- **telemetry 契約（R2 P1 明訂）**：旗標 `mixed` 時，`practice_chat_succeeded` 只多下列四個 key，`practice_chat_generation_failed`（整輪失敗）只多 `chatModelCalls`／`chatModelUsage`；**另外允許一個新事件 `practice_chat_model_fallback`**，只在 Claude 呼叫真的失敗時出現，payload 只有 `level`／`event`／匿名 `user`／`attempt`／`error` 五個欄位（沒有逐字稿、prompt、金鑰）。除此之外事件數與事件名都不變——有一支測試用「mixed＋agency on＋有 key＋Claude 500→DeepSeek 成功」對照同設定但 routing 未設的那一輪，剔除 fallback 事件、刪掉四個 key 後逐行逐位元組比對。
- `practice_chat_succeeded` 在旗標 `mixed` 時多四個 key：`chatModel`（最終**採用**的那一支）、`chatModelCalls`（`{haiku, deepseek}`，整輪各自真的被呼叫幾次，守門重試也算）、`chatModelFallback`（這一輪有任一次 Claude 呼叫失敗過）、`chatModelUsage`（整輪**所有成功** Claude 呼叫的四格累加：input／cache_read／cache_write／output）。旗標不是 `mixed` 時**整組 key 不存在**，flag-off golden 一個位元都不動。
- **usage 記帳時機（R2 P2 撤回 R1 的訂法）**：`callClaude` 的 `onUsage` 契約是「**只要 Anthropic 回了 `usage` 就呼叫一次**」，包含 `max_tokens`／`refusal`／內容空這些 HTTP 200 但丟錯的情況——那些 token 費用已經發生，不記的話 fallback 那一輪會顯示 `chatModelCalls={haiku:1,deepseek:1}` 但 `chatModelUsage` 是 undefined。回應沒有 `usage` 欄位才不呼叫。
- Codex R1 P1 修正前的缺陷：`chatModelUsage` 是最後一次覆寫、fallback 還會把它清成 `undefined`，所以「Claude 成功→守門拒→Claude 成功」只記後面那次、「…→Claude 失敗→DeepSeek」整筆 Claude 用量消失。現在兩個案例都有測試釘住。
- 成本護欄：`max_tokens` 與 DeepSeek 路徑同值（不高於），system prompt cache 必開（`callClaude` 既有行為）。**不做每日預算**（YAGNI）——成本用 Anthropic console 監控，異常時把旗標關掉即可。

### 反漂移

`callClaude` 補了一個 `onUsage` 回呼（不傳就零改動，hint／debrief 都不傳；只在 content 解析與驗證**之後**才響，200 但內容空時一次都不呼叫）之後，黑箱 runner 的 `callHaikuChat` 改成直接呼叫它，刪掉 runner 自己抄的 `claudeRequestMessages` 與 fetch。兩支測試分別守住兩件事：「選了 Haiku 之後送出的 request body 逐位元組相同」（同一份 bundle messages 進 handler 的呼叫端與 runner haiku 臂），以及「**何時**選 Haiku 相同」（routing × agencyMode × applied × practiceMode 全矩陣比對 `runnerChatModelFor` 與 `chatModelFor`）。

### 資料面（Codex R1 U3）

Anthropic **不是本刀新增的資料接收方**：practice-chat 的 hint／debrief 早就用同一支 `callClaude` 把同一段練習對話送給 Anthropic（`CLAUDE_API_KEY` 也是既有的）。本刀只是讓介入輪的 chat 生成多送同一份 `chatPromptBundle.messages`（與 DeepSeek 拿到的那份逐字相同，沒有多帶 telemetry、id 或金鑰）。資料留存設定、DPA／地區、隱私揭露文字是否需要更新，**由 Eric 確認後才開 production 旗標**——這一輪沒有提供也沒有宣稱這些治理證據。

### Gate（實測）

- practice-chat 全套：**1,897 passed / 0 failed / 1 ignored**（base `4b381189` 1,872；＋25）。
- 等價 harness：**9 passed / 1 ignored**，**off golden 未重印**；harness 多枚舉一維 routing env（`off`／亂填／`true` 四面等價；`mixed` 逐行解析 telemetry、刪掉允許的四個 key 後逐位元組相同，且事件數與事件名相同；沒有 Anthropic key 時三面等於「agency on ＋ routing 未設」）。
- `tools/practice-agency-eval/`：**56 passed / 0 failed**（＋7）。
- `deno fmt --check` 本輪觸碰的 `.ts` 全過；`deno check` 0 error；`deno lint` **5 個與 base 相同**（全在未觸碰檔案）。
- prompt 瘦身 gate 不受影響（本刀一個字都沒動 prompt）。
- `flutter-ci.yml` 的 Edge contract tests 名單加入 `chat_model_routing_test.ts`，不然這道 gate 在 PR CI 是死的。

### Codex R1：BLOCKED（逐項處置）

| 項 | 內容 | 處置 |
| --- | --- | --- |
| **P1** | Claude 重試成本被 telemetry 少算或抹除 | **已修**：usage 整輪累加、新增 `chatModelCalls`、fallback 不清已付掉的 usage、`chatModelFallback` 改成「任一次失敗」。兩個守門重試案例有測試 |
| **P1** | 實驗證據沒覆蓋 production 路由範圍 | **已修（縮範圍）**：`chatModelFor` 加 `practiceMode`，`standard` 一律 deepseek；game 併入前先跑小黑箱。standard／game 的補跑仍未做 |
| **P2** | `onUsage` 違反自己的契約 | **已修**：搬到 content 解析與驗證之後；`claude_test.ts` 兩支測試（空內容零次、成功恰好一次） |
| **P3** | mixed telemetry 只檢查「不同」 | **已修**：逐行解析 JSON、刪允許的四個 key 後逐位元組比 flag-off（那份已被 golden 測試釘成 `7f1d6d6c` bytes），並斷言事件數與事件名逐項相同 |
| **P3** | fake 的 usage 時序與 production 不一致 | **已修**：fake 只在非 Error 回覆時觸發 `onUsage` |
| **U1** | mixed Response 契約自相矛盾 | **已修（明訂契約）**：見本節「旗標與路由」與測試檔頭——真的採用 Haiku 的輪次允許 `provider`／`model` 值不同，key 集合不變；三種 Response 有 schema 相容測試 |
| **U2** | 沒證明 runner 與 production 的「何時選 Haiku」相同 | **已修**：runner 選模入口直接呼叫 `chatModelFor`，另有全矩陣逐項比對測試 |
| **U3** | 新增 Anthropic 資料接收方的治理證據 | **已寫進本節「資料面」**：Anthropic 不是新接收方（hint／debrief 既有），本刀只多送同一份 bundle；留存／DPA／隱私揭露由 Eric 確認後才開旗標 |
| **U4** | fallback 的 exactly-once 未被直接證明 | **已修**：四個失敗案例都斷言 `commit_practice_chat_turn` 恰好一次、learning update 與 thread 寫入各至多一次 |

### Codex R2：BLOCKED（逐項處置）

| 項 | 內容 | 處置 |
| --- | --- | --- |
| **P1** | fallback 新增整個事件，違反「只多四個 key」 | **已修（明訂契約＋補測試）**：契約改成「四個 key ＋ 一個允許的新事件」，測試檔頭與本節同步；harness 補一個真的觸發 fallback 的案例（mixed＋agency on＋有 key＋Claude 500→DeepSeek 成功），斷言該事件恰好一筆、payload 五個欄位且不含逐字稿／金鑰，剔除後逐行逐位元組相同 |
| **P2** | 200 但丟錯的呼叫成本少算；整輪失敗無成本事件 | **已修**：`onUsage` 改成「回了 usage 就記」；`practice_chat_generation_failed` 在 mixed 時多記 `chatModelCalls`／`chatModelUsage`。兩支測試（`max_tokens`＋非零 usage → fallback 成功仍記到帳；兩發 DeepSeek 全掛的整輪失敗事件帶成本） |
| **P3** | 「逐位元組相同」實際只比解析後物件 | **已修**：改存 `String(init?.body)` 原始字串比對，並多比一次 UTF-8 bytes |
| **U1** | request 與 ledger 的 practiceMode 是否一致 | **已查證＋釘住**：既有 validation 就是權威——chat 路徑在生成之前檢查 `ledger.exists ∧ lockedPracticeMode !== null ∧ !== request.practiceMode` → 409 `practice_mode_locked`（`handler.ts`）。新增「ledger=standard、request=beginner」測試斷言 409 且一次模型都不打，所以 standard 的排除繞不過去 |
| **U2** | 開旗標的產品與資料前提未成立 | **同意，未做**：列成下面的開旗標前置條件清單，全部由 Eric 決定 |

### 開旗標（`PRACTICE_CHAT_MODEL_ROUTING=mixed`）前置條件

1. **`game` 小黑箱**：Phase 4.3 只量過 beginner，game 也在路由範圍內。
2. **越界輪小黑箱**：boundary→Haiku 完全沒有數字（安全側的產品判斷）。
3. **資料治理由 Eric 確認**：Anthropic 的留存設定、DPA／地區、隱私揭露是否涵蓋「chat 生成」這個新用途與頻率（vendor 既有不等於用途既有）。
4. **首日觀察**：`chatModel` 分佈（Haiku 佔比）、`chatModelFallback` 比率、`chatModelCalls` 的重試分佈、p95 延遲、Anthropic console 總帳。
5. 隨時可回滾：把旗標拿掉即回到逐位元組舊行為。

### 仍未做／風險

- **本輪零模型呼叫**（R1 修正輪同樣零呼叫）：沒有新的黑箱數字，Phase 4.3 的三臂結論就是全部證據（20 位 × 10 情境 × repeat 1、beginner＋state）。**越界輪走 Haiku 這一格完全沒量過**（黑箱矩陣量的是介入輪），成本與品質都靠開旗標後的 telemetry 觀察。`game` 的 mixed 效果**沒有量過**（程式上已允許，開旗標前要先跑小黑箱）；`standard` 已在程式層排除。
- 真機未驗。旗標預設關，Eric 要在 Supabase 設 `PRACTICE_CHAT_MODEL_ROUTING=mixed` 才會生效。
- 成本：黑箱外推每次 Haiku 生成約 $0.003；只有介入輪才打，實際比例看 telemetry 的 `chatModel` 分佈。開了之後第一天就該看一次 Anthropic console。
- 延遲：黑箱量到 Haiku p95 比 DeepSeek 多約 57%，但只落在介入輪。fallback 那一輪等於兩次呼叫的延遲相加（逾時 30s 上限）。

## Phase 4.5a — 是非短答、（已讀）、不收斂階梯（2026-09-05，Eric 拍板）

原則（Eric 原話）：**像真人——真人不會一直陪你耗。** 三刀都在 agency 旗標
`on` 的路徑上；`off`／`shadow` 逐位元組不變（等價 harness 守門）。

### 刀 1：「對／不是」回答是非問句不算裸詞

- 判準（兩個都要成立，全部是句法標記，沒有語意判斷）：
  1. **是非問句**（`aiAskedYesNoQuestion`，Codex R1 P1-3 後三道閘門）：
     剝掉句尾裝飾（`TAIL_DECORATION_RE`）後 `aiAskedQuestion` 要成立、最後一個
     子句以「嗎／吧／嘛」結尾（與 `aiAskedQuestionStrict` 共用 `finalClauseOf`）、
     而且**「吧／嘛」還要整則出現第二人稱（你／妳）**。開放問句的「呢」刻意
     不收；「我先去忙吧」（她自己的收尾提議）、「這本來就是韓國嘛」（陳述）
     都判 false，checked-out 不會被一句「好」解開。
  2. 他這一則**整則錨定**是純肯定／否定短詞
     （對／對啊／嗯對／是／是啊／不是／沒有／沒錯／不對／不要／好／好啊），
     只容忍句尾裝飾（`isYesNoShortAnswer`）。
- 效果：`utteranceShapeOf` 判 `answer_candidate`（放在 `REACTION_RE` **之前**，
  否則「好」「好啊」會先被反應詞接走）、`AgencyEvidence.answeredYesNo=true`；
  `agencyPolicyFor` 對這一輪一律 NO_OVERRIDE（**在 `repeatedExactToken` 之前**
  ——連兩題是非題答「對」是正常對話，不是同詞重複）；欠債迴圈遇到這一句
  **不累加**、把 `told` 清成 false，但**既有欠債不歸零**（回答一題是非題不是
  結構修復）。
- 不變的邊界：她那一則是陳述句或開放問句時，逐字維持 4.3 行為
  （「你在說什麼？」→「不是」仍然走 `clarify_ignored` 強制格）；
  「對了我今天…」仍然是 `explicit_pivot`；`contentUserTurnCount` 那支 caller
  少傳一個參數＝行為與 4.3 相同，4.2／4.3 的「反應詞邊界契約」整張表不動。

### 刀 2：「（已讀）」冷回應

- 開關（`TurnResponsePlan.readOnlyAllowed`）：agency `on` ＋（`challenge` 難度
  或 `game`）＋（這一輪 forced `end_low_value_loop`，**或**
  `situation === "boundary"` 且逐字稿尾端連續兩則玩家訊息命中 `BOUNDARY_RE`）。
  easy／normal、旗標 off／shadow 一律不出現這個 key。越界輪的 agency decision
  被 `computeAgencyDecision` 清成 `situation: null`，所以那一半只能從 planner
  自己的 stance ＋逐字稿數，不能靠 agency 決策。
- 渲染：`AGENCY_READ_ONLY_SHAPE` **取代**形狀行，不是多加一行——「只回一則
  已讀」本來就是形狀指示，而且比它取代掉的 `AGENCY_CLARIFY_ONLY_SHAPE` 短
  （prompt 瘦身 gate 的餘裕因此從 1,012 變成 1,027）。
- 守門：`hasStageDirection`／`stripStageDirections` 多一個 `allowReadOnly`
  參數，只放行**整則**（去頭尾空白後）完全等於「（已讀）」或「(已讀)」兩個
  字面的回覆；多行（「（已讀）\n哈哈」「哈哈\n（已讀）」）、混括號
  （「（已讀)」）、加尾巴（「（已讀）哈哈」）一律不豁免（Codex R1 P2-1）。
  handler 的授權條件是 **agency on ＋（planner `readOnlyAllowed` 或 forced
  `read_only`）**（Codex R1 P1-1）——只看旗標等於讓 beginner／easy 的模型自己
  吐一句已讀也過關。這兩支同時被 reply-style 路徑與兩支黑箱 runner 消費，
  參數預設 false 讓 off 路徑逐位元組不變。
- telemetry：`conversationAgency.readOnlyReply`（她真的回了已讀才寫）。

### 刀 3：不收斂階梯

state 兩個新欄位（**assisted 專用**；`parseConversationAgencyState` 缺欄位／
字面 `null` 一律當 0／false，0／false 不寫 key，`lowValueStreak` 讀回來就
`Math.min(3, n)`——Codex R1 P2-2）：`lowValueStreak`（收尾格連續
輪數，clamp 在 `LOW_VALUE_STREAK_CHECK_OUT = 3`）、`checkedOut`。

| 這一輪玩家給了什麼 | 狀態 | 結果 |
| --- | --- | --- |
| 結構內容（問句／self_share／解釋標記／明示換題／回答是非題） | streak > 0 或 checkedOut | forced `cold_return`（`cold_return_v1`）：一則、短、不主動問；階梯歸零、解除 checkedOut；**溫度 delta 上限 0** |
| 結構內容 | streak 0 且未 checkedOut | 照 4.4（NO_OVERRIDE 等既有路徑） |
| 低價值（裸片段／短答候選／反應詞） | checkedOut **且**挑戰／Game | forced `read_only`（`read_only_v1`）：**不打生成模型**，直接一則「（已讀）」 |
| 低價值 | streak ≥ 3 且未 checkedOut **且**挑戰／Game | forced `check_out`（`check_out_v1`）：一句收尾、不問不約 |
| 低價值 | 其餘 | 照 4.4（這一輪如果 forced 了 agency act，streak +1） |

**streak 入口（R1，CTO 2026-09-05 依 Eric「持續不收斂」原意擴大）**：只認
**這一輪 planner 真的下的 forced act**（跟 `priorChallengeIssued` 同一個規則：
允許過 ≠ 做過），範圍是**任何 agency act**——`challenge_relevance`（含 4.3 的
`clarify_ignored_*`）、`hold_position`、`end_low_value_loop`、同詞重複那格——
**只有 `ask_intent` 不算**（第一個沒有前文的裸詞，她還沒被耗到，第一次問清楚
不該記成不收斂）。`accept_if_answered`／`return_to_topic` 只出現在 bounded 清單，
永遠不會是 `forcedAct`。

> 為什麼擴：R1 之前只認兩個收尾格，離線重建量到 p43-mixed 740 輪只觸發 1 次
> ——她多半在問問題，玩家那一則就變成 `answer_candidate`，走的是 4.3 的
> `clarify_ignored`，根本進不了收尾格。

**強制結束的難度門檻（Codex R1 P1-2）**：`check_out`／`read_only` 只在
`thresholds.forceEndLoopBeforeChallenge` 為真時成立，也就是**難度 challenge
或 practiceMode game**（`AGENCY_THRESHOLDS.challenge` 是唯一 true 的一格，
`agencyThresholdsFor` 對 `isGame` 直接套 challenge，profile 位移不動這個欄位）。
beginner 的 easy／normal：streak 照算、`cold_return` 照走，但到 3 **不結束**，
留在既有的 `hold_position`／`end_low_value_loop`（她冷但會回）。這一道是
**防禦性**的——就算 thread row 被直接種成 `lowValueStreak: 3`／
`checkedOut: true`，輕鬆難度也不得強制結束。難度因此是硬門檻而不只是口氣，
`check_out_cold_v1` 沒有第二個值可走，收成單一 `check_out_v1`。

- `cold_return` 有**自己的 `AgencySituation` 值**（不借 `ambiguous_fragment`）；
  `COHERENCE_BY_SITUATION` 仍映到 `ambiguous`（不獎不罰）。
  `agency_coaching.ts` 的修復輪帳**明確跳過它**——他終於給了內容，不是又一輪
  沒接上，算進去會讓 Hint／Debrief 多報一輪。
- 溫度不補回靠 `applyCoherenceDeltaCap` 新增的 `cold_return` 零上界（跟
  `shared_past_claim`／`accommodating_self_fact` 同一個機制：只壓正分、絕不抬
  負分），成功與分類器失敗兩條路徑都套。該函式 R1 已改成**單一 options 物件**
  （26 個呼叫點同步），fallback 路徑不再需要塞 `undefined` 佔位。
- `read_only` 那一輪 handler 完全跳過生成模型，`practice_chat_succeeded` 的
  `chatModel` 記 `"none"`、`chatModelCalls` 兩支都是 0，Response 的
  `provider`／`model` 也照實回 `"none"`（key 集合不變；2026-09-05 實查
  `lib/features/practice_chat/data/services/practice_chat_api_service.dart`
  **從來沒有讀過**這兩格，只有 coach-chat 的 service 讀它自己那條路徑的同名
  欄位，所以舊 client 不會炸）。扣額規則不動（是否扣一則仍由既有配額邏輯決定）。
- 三格的 bubbleCount 都壓到 `minB`；形狀行（`AGENCY_LADDER_SHAPE`）**優先於**
  clarify-only 形狀，因為那條是「只問清楚」的形狀，不是「冷冷接一句」。

### Game 結束訊號：查證結果（**沒有現成的，留給 Eric**）

`practice-chat` 的 chat 回應只有 `sessionComplete`，而它就是
`isSessionComplete(aiTurnCount)`＝「已達 20 則」；client
（`practice_chat_screen.dart`）在那一格印死字串「這場練習已達 20 則回覆」。
debrief 也不是 server 主動觸發的，而是 client 另外送一次 `mode: "debrief"`。
所以**沒有**可以誠實表達「她先忙了，這場結束」的既有欄位——硬把
`sessionComplete` 設成 true 會讓 UI 說一句不成立的話。本輪因此**只做**
`checkedOut` ＋ 已讀；Game 在 `check_out` 直接進 debrief 需要 client 配合
（新欄位或新文案），留給 Eric 決定。`beginner` 本來就不強制結束；
`standard` 沒有持久化狀態，整條階梯不生效。

### Gate（實測數字）

- `deno test supabase/functions/practice-chat`：**1,910 passed / 1 ignored**
  （base 1,897 ＋ 本輪 13 支）。
- `deno test tools`：**111 passed**（＝base，本輪沒動工具程式碼）。
- `deno fmt`（只跑改到的 `.ts`）／`deno lint`／`deno check handler.ts`
  ／`deno check moments_handler.ts`：全過。
- 旗標 off 等價 harness：9/9（off golden 未重印）。
- prompt 瘦身 gate（agency-on 至少比 off 少 1,000 code units）：餘裕
  1,012 → **1,027**（刀 2 取代形狀行反而更短）。

### 離線重建（`replay_plan.ts`，零模型呼叫）

`replay_plan.ts` 預設**不餵**分類器訊號（artifact 裡沒有當時的
`aiChallengedThisTurn`），所以 4.3 的 `clarify_ignored` 強制格整批不成立，
階梯幾乎踩不到；`--ai-clarified=1` 是「她每一輪都真的在澄清」的**上界**。
兩個界都列出來，production 夾在中間。

**下界（預設，分類器訊號缺席）**

| artifact | user 輪次 | `check_out` | `read_only` | `cold_return` |
| --- | --- | --- | --- | --- |
| `out/2026-09-05-p43-mixed.json` | 740 | 0 | 0 | 0 |
| `out/2026-09-05-p4full-beginner-on.json` | 1,920 | 0 | 0 | 0 |

**上界（`--ai-clarified=1`）**

| artifact | user 輪次 | `check_out` | `read_only` | `cold_return` |
| --- | --- | --- | --- | --- |
| `out/2026-09-05-p43-mixed.json` | 740 | 0 | 0 | 0 |
| `out/2026-09-05-p4full-beginner-on.json` | 1,920 | 0 | 0 | **23**（全在 A15.p1，23/60） |

兩個 artifact 的 meta 都是 `difficulty: normal`，而回放固定走 beginner，所以
Codex R1 P1-2 的難度門檻讓 `check_out`／`read_only` **在這兩份逐字稿上恆為 0**
——這正是「新手不強制結束」的離線證明。要量結束那一半，用新加的
`--difficulty=challenge` 覆寫同一批逐字稿（純診斷，零模型呼叫）：

**`out/2026-09-05-p43-mixed.json --difficulty=challenge`**

| 臂 | `check_out` | `read_only` | 分探針 |
| --- | --- | --- | --- |
| 下界 | 1 | 0 | A26.p8 1/20 |
| 上界（`--ai-clarified=1`） | **40** | **102** | A25.p5 **17/20**、A26.p5 **13/20**、A26.p8 2/20；read_only：A25.p8 **20/20**、A26.p8 **18/20**；其餘無 probe id 的輪次 8/200 與 64/200 |

`check_out` 落在 **p5**（連丟第 5 則就先忙了），之後 p8 是 `read_only`。

- **A01／A03／A07／A09、A28（配合的玩家六個來回）、A29（停滯反應詞）三個新
  act 全部 0**，每一個臂（含 `--difficulty=challenge`）都是——有效短答、明示換題、正常聊天、停滯輪都不得被
  階梯掃到。
- `cold_return` 全部落在 A15「玩家道歉並回到原題（不記仇）」——正是「他終於
  給了內容、她回來但冷」那一格。

### 風險與未做

- **真機未驗。** production 的 `agency=true`／`shape=truncate` 已開，本輪三刀
  都在 on 路徑上，合併即生效。
- **零模型呼叫**：沒有新的黑箱品質數字。刀 2／刀 3 的「她真的會照做嗎」
  （模型服從率）沒有量過——Phase 3.8 的教訓是觸發率與服從率是兩件事。
- 階梯觸發率**只在有分類器訊號時才起得來**（上下界差很多）。production 的
  assisted 每輪都有分類器，理論上靠近上界，但那是推論不是量測——真機第一天
  要看 telemetry 的 `forcedAct` 分佈確認。
- 上界量到 `read_only` 102/740（13.8%），代表她在連丟情境會有相當比例的輪次
  只回一則已讀。這是刻意的產品行為，但**沒有真人驗收過**，體感可能過冷。
- `read_only` 省下的那一次生成呼叫沒有換算成本；扣額規則沒動，所以玩家在那
  一輪仍可能被扣一則（既有配額邏輯決定）。
- Game 結束需要 client 配合（見上）。
- **連續越界只數 `BOUNDARY_RE`（Codex R1 P3-3，留 Eric 決定）**：
  `trailingBoundaryTurns()` 只看玩家訊息文字有沒有命中 `BOUNDARY_RE`。
  `situation === "boundary"` 還可以由 `gameGreasy`／`userOverEscalated` 產生
  （Game FSM 的證據，文字本身不一定命中 regex），那種連續越界目前**拿不到**
  `readOnlyAllowed`。這是刻意的窄規則（那兩個訊號不是「他又踩了一次同樣的
  界線」的直接證據），要不要一起累計由 Eric 決定。

### Codex R1：BLOCKED（逐項處置）

| 項 | 內容 | 處置 |
| --- | --- | --- |
| P1-1 | `allowReadOnly` 只看 `agencyMode === "on"`，任何 beginner／easy 輪只要模型自己吐「（已讀）」就會被放行並記 `readOnlyReply` | **已修**。授權條件收成 agency on ＋（planner `readOnlyAllowed` 或 forced `read_only`）；telemetry 改讀同一個旗標。測試：未授權輪吐已讀 → 旁白守門剝到空 → 重試；兩發都吐 → 整輪 500。 |
| P1-1（連帶） | 追這一項時發現的**既有漏洞**：每次生成直接寫進外層 `reply`，守門在最後一次 attempt 丟錯時 `reply` 仍留著被拒絕的文字，`if (reply === null)` 不成立 → 被擋下來的內容照樣送出去（L4／內部標籤／旁白三道都中） | **已修**（不在原範圍，但同一條路徑上的安全問題）：生成收在 attempt 內的 `candidate`，全部守門過了才寫回 `reply`。 |
| P1-2 | 沒有硬性落實「新手不強制結束」 | **已修**。`check_out`／`read_only` 多一道 `thresholds.forceEndLoopBeforeChallenge`（⟺ challenge 難度或 game）。beginner 的 easy／normal streak 照算但不結束；直接 seed `lowValueStreak: 3`／`checkedOut: true` 也不得結束。兩條軌跡都有測試。 |
| P1-3 | `aiAskedYesNoQuestion` 只看句尾助詞，會把「我先去忙吧」判成是非問句，玩家一句「好」就解除 checked-out | **已修**。三道閘門（剝裝飾後 `aiAskedQuestion` ＋ 最後子句助詞 ＋「吧／嘛」要有第二人稱）。第 1 關必須對**剝掉句尾裝飾後**的字串做，否則「你在報地名嗎😂」這類真人寫法會整批判漏。 |
| P2-1 | 白名單是逐行判斷，「（已讀）\n哈哈」第一行會豁免；字元類還會接受「（已讀)」 | **已修**。改成整則（trim 後）完全等於兩個完整字面之一。 |
| P2-2 | parser 沒有 clamp 3 | **已修**。讀回來 `Math.min(3, n)`，4／999 都是 3。 |
| P3-1 | read-only 的 exactly-once 與 client schema 證據不足 | **已補**。展開 commit RPC 一次、`p_charge_quota`、`aiTurnCount`、thread 只寫一次且 `checkedOut: true`、learning ≤1；`provider`／`model` 決定回 `"none"`（實查 client 從不讀這兩格）。 |
| P3-2 | 解釋標記是否真的算內容沒有證明 | **已查證＋釘測試**。`utteranceShapeOf` 的 `EXPLANATION_RE`（因為／意思是／就是說／是說）與 `FIRST_PERSON_RE` 同一個分支回 `self_share`，所以階梯本來就把它當內容；checked-out 下「因為剛剛在列旅遊清單」走 `cold_return` 不是 `read_only`。 |
| P3-3 | `gameGreasy`／`userOverEscalated` 來源的連續越界未涵蓋 | **不改，記進風險**（見上），留 Eric 決定。 |
| P3-4 | shadow 的 cold-return cap 需專門驗證 | **已補測試**。`agencyDeltaCapActive === (agencyMode === "on")`，shadow 恆 false；測試證明 shadow 與 off 的 Response（除時間戳）與溫度寫入參數逐位元組相同。 |
