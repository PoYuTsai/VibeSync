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
