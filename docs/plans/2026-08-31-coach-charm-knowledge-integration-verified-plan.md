# 「問教練」魅力知識導入：規格驗證報告與修正後實作計畫

> 狀態：已完成程式碼逐條驗證的實作計畫；本 PR 只含文件，不含任何 runtime 變更。
> 日期：2026-08-31
> 驗證基準：`main` @ `c7292848469c03f11eec378815c888a852490d4a`（與原規格研究基準同一 commit）。
> 來源材料：
> - 原始規格：`docs/plans/2026-08-31-coach-charm-knowledge-integration-spec.md`
> - 知識庫：`docs/research/2026-08-31-charm-chat-knowledge-base.md`

---

## 0. 結論先行

1. **原規格的六大根因診斷，逐條在現行程式碼上成立**（§2 附檔案與行號證據）。核心方向確認採用：先修決策、再修文案；讓「不傳訊息」「先補上下文」成為正式、可展示、不可被文案生成覆蓋的成功結果。
2. 驗證另外發現 **8 個規格未涵蓋或需要修正的點**（§4），其中 3 個直接影響批次切法：
   - **voice contract 的互動風格資料來源已不存在**：2026-08-04 拍板已把「關於我」的互動風格選擇區塊從 UI 移除，`interactionStyle`/`secondaryStyle` 欄位仍在實體與 resolver，但已無收集入口。規格 §8.2 要「帶入主/副風格」前，需先由 Eric 決策資料來源（§8）。
   - **inviteHistory 沒有任何現成資料通道**：現行 wire schema 沒有欄位承載「兩次邀約未承接」。原規格把「兩次未承接後禁止再邀」放在 Batch A、卻把承載它的 `inviteHistory` 放在 Batch B 的 `InteractionSnapshotV2`——批次有內部依賴矛盾，本計畫把硬閘門移到 Batch B（§5）。
   - **`no_message` 可先用現行 `do_not_send` 落地**：`rewriteDecision` enum 已有 `do_not_send`、`suggestedLine` 已可為 null（`schemas.ts:48-53,196`），缺的只是「do_not_send ⇒ suggestedLine 必為 null」的硬一致性與 UI 的正面呈現。Batch A 不必等 `CoachAnswerV2`。
3. 重切後的 **Batch A 全部項目都可在現行 wire schema 內完成**（不動 Edge request/response 形狀），且每一項都有既有機制先例可循（motive_drift 詞表閘門、全域首輪釐清閘門），風險可控。

---

## 1. 驗證方法與範圍

逐檔精讀（非抽樣）比對規格主張與 `c729284` 實際程式：

| 層 | 已驗證檔案 |
|---|---|
| Coach Edge | `supabase/functions/coach-chat/`：`prompts.ts`（296 行）、`clarification_policy.ts`（40）、`generation.ts`（982）、`schemas.ts`（246）、`validate.ts`（140）、`quality_smoke_test.ts`（結構） |
| Analyze Edge | `analyze-chat/analyze_prompt/reasoning_core.ts`、`conversation_policy.ts`（節錄）、`ball_inventory.ts`、`opener_prompt.ts`（五風格段） |
| Flutter | `coach_chat_providers.dart`（559）、`effective_style_prompt_builder.dart`（130）、`effective_style.dart`、`resolve_effective_style.dart`、`about_me_screen.dart`（風格區段）、`global_coach_screen.dart`（434）、`coach_surface.dart`（1599） |
| 文件 | `docs/plans/2026-07-08-social-knowledge-integration-design.md`、`docs/research/`、`assets/learning/ebooks/`（7 本存在） |

七張截圖本身不在 repo，無法重放；但每案對應的程式路徑（partner scope 無逐字對話、fallback 造題、placeholder 無閘門）都已找到，與截圖現象一致。

---

## 2. 規格六大根因逐條驗證

| # | 規格主張（§3） | 結果 | 程式證據 |
|---|---|---|---|
| 3.1 | Coach 與 Analyze Chat 是知識孤島；Coach 只收簡化 snapshot | **成立** | `AnalysisSnapshotSchema` 恰好只有 heatScore/stage/summary/nextStep/coachActionType/keySignals（`coach-chat/schemas.ts:78-85`）；`SYSTEM_PROMPT_BASE` 獨立於 analyze-chat 知識模組（`prompts.ts:56-132`），五階段/投入/球/動作詞彙只存在於 `analyze-chat/analyze_prompt/reasoning_core.ts:28-91` |
| 3.2 | partner scope 沒有逐字對話仍可產個案戰術 | **成立** | 只有 conversation scope 讀 conversation（`coach_chat_providers.dart:191-205`）；partner scope 送出 `recentMessages: const []`、`conversationSummary: null`、`analysisSnapshot: null`（`:253-258`），只帶 name＋unionTraits(5)＋customNote（`:532-548`） |
| 3.3 | 釐清政策只保護 global scope | **成立** | `mustClarifyFirstRound` 硬性要求 `scope?.type === "global"`（`clarification_policy.ts:21-31`）；conversation/partner scope 零證據也不會被擋 |
| 3.4 | 輸出契約把「寫一句」放在決策前；suggestedLine 與 boundaryReminder 分開驗證 | **成立** | schema 無任何 suggestedLine × boundaryReminder / rewriteDecision 交叉一致性驗證（`schemas.ts:187-235`）；UI 把 suggestedLine 做成白底卡＋「複製這句」按鈕（`coach_surface.dart:935-963`） |
| 3.5 | validator 只驗「可解析」不驗「值得傳」；fallback 仍是 conversation-rescue | **成立** | 閘門清單：schema、banned tokens、prompt leak、raw payload、13 個時間詞、5 個負面動機詞、explicit_no_question、語言守門、釐清上下限（`generation.ts:90-111,189-194`）。無 placeholder／自貶／過度配合／空鉤子／邀約歷史／矛盾檢查。fallback 文案即「把球丟回一個好回答的小問題」，且內建一句**腦補對方狀態**的罐頭建議句「感覺你今天真的有點累…」（`generation.ts:645,653-655`） |
| 3.6 | 使用者真實風格沒有完整進 Coach | **成立＋需修正前提** | `buildForCoachFollowUp` 只讀 stuckPoints/practiceGoals/notes（`effective_style_prompt_builder.dart:49-86`）；`findCompatiblePartner` 語意確為「保持開放、不要急著篩選或設限」（`:122`）。**但**互動風格 UI 已於 2026-08-04 拍板移除（`:9-13` 決策註解；`about_me_screen.dart` 僅剩 draft 資料管線、無選擇區塊；presentation 層已無任何 `PartnerStyleOverride` 編輯點）→ 見 §4.1 |
| 3.7 | 舊 Coach 建議會自我強化、無 provenance 分流 | **成立** | `_staleSessionDigestTurns` 把「當時建議這樣說：…」以 coach `answer` turn 注回（`coach_chat_providers.dart:448-481`）；server 端 `assertSuggestedLineGrounded` 的來源**包含全部 activeSessionTurns**（含教練舊建議，`generation.ts:499`）——教練上次的時間詞可替下一句背書。對照：語言守門已刻意只算 user turns（`generation.ts:531-535`），證明「AI 舊輸出不得替新輸出背書」在本 codebase 已有先例，只是沒套到事實 grounding |

---

## 3. 其他主張驗證

| 規格主張 | 結果 |
|---|---|
| §12.1 現有負評分類為 too_direct / unnatural / too_long / wrong_style / other | 成立（`coach_surface.dart:1456-1462`） |
| §14 檔案級實作地圖 | 檔案全部存在、職責描述正確。**修正一處**：回覆卡的呈現主體不在 `global_coach_screen.dart` 而在 `coach_surface.dart`（`CoachChatResultView`），三種 messageDecision 的 UI 改動落點應是後者；見 §4.6 |
| §14 對 2026-07-08 舊設計文件的定性（「Coach 最後才做、只盤點生活素材」不足以修現況） | 準確：舊文件 Coach 部分只有 Batch E「生活素材盤點」，且推薦順序把 Coach 放最後 |
| §5.3 partner scope 補最近對話的可行性 | 成立：`conversationsByPartnerProvider`、`partnerAnalysisRecordsProvider` 已存在（`partner_providers.dart:56,69`），`global_coach_screen.dart` 的作戰板開場泡泡已在用同一條資料路徑 |
| §6.2 釐清不扣正式次數 | **現況已滿足**：clarifyingQuestion 一律 `costDeducted=0`（`schemas.ts:232-235` transform＋UI 綠標）。新增的 `clarify_user` 決策只需沿用此語意，Batch A 無需重做計費 |
| 知識庫文件對現行程式的描述 | 全部對上：opener 五風格 extend/resonate/tease/humor/coldRead（`opener_prompt.ts:16,40-51`）、五階段（`reasoning_core.ts:84-91`）、收/接/延伸/篩選/邀約/暫停動作詞彙（`:30`）、Go/Slow/No-Go（`:28`）、球盤點接/併/略（`ball_inventory.ts`）、1.8x 護欄（`conversation_policy.ts` §1、`coach-chat/prompts.ts:112`）、自嘲 vs 自貶（`reasoning_core.ts:57-62`）、7 本 ebooks、其引用的 GitHub 檔案清單全部存在。「失格拆兩鍵」（DISQUALIFY_OTHER / SELF_DISQUALIFY）的提醒有效 |
| §16.5「不要只換模型」 | 一致：coach-chat 現用 `claude-sonnet-5`（`generation.ts:122`），問題確實不在模型層 |

---

## 4. 規格未涵蓋的發現（修正與補充）

### 4.1 voice contract 的資料來源缺口（影響 Batch D）

規格 §8.2 假設把 `interactionStyle`/`secondaryStyle` 帶進 Coach 即可。實況：欄位存在（`effective_style.dart`、`resolve_effective_style.dart:26-29` 原子配對合併邏輯都在），但 2026-08-04 拍板後**全域與對象層都沒有 UI 在收集這筆資料**。Batch D 前需 Eric 決策資料來源（§8 決策 1），否則 voice contract 只能先建立在 stuckPoints/practiceGoals/notes/avoidPhrases 上。

### 4.2 `no_message` 的最小落地路徑已存在（重切 Batch A）

`rewriteDecision=do_not_send` 已是 schema 合法值、prompt 已教（`prompts.ts:111`）、UI 已有「先不要送」標籤（`coach_surface.dart:1076`）。缺的是三件小事：(a) server 硬規則 `do_not_send ⇒ suggestedLine=null`；(b) UI 對 do_not_send/null suggestedLine 給正面的「這輪先別傳」卡（目前只是不顯示複製卡，沒有判斷展示）；(c) prompt 把「不傳是合法成功輸出」講成正式契約。**不需要等 `CoachAnswerV2`。**

### 4.3 grounding 來源需做 priorAdvice 分流（Batch B 的具體落點）

規格 §3.7 的修法落點就是 `assertSuggestedLineGrounded` 的 source 清單（`generation.ts:495-505`）：比照語言守門（`:531-535`）改為只採 user turns＋對方訊息，教練舊 turn 全部降級為 priorAdvice（只用於避免重複，不得作事實來源）。同時 `_staleSessionDigestTurns` 注入的「當時建議這樣說」需帶明確標示。

### 4.4 inviteHistory 無資料通道（Batch A→B 移項）

「兩次未承接邀約後禁止再邀」的硬閘門需要 `inviteHistory`（結構化邀約結果），現行 wire 沒有這筆資料；`coachingOutcomeDigest` 只有去識別化統計句，不含逐次邀約結果。現行唯一相關防線是 prompt 層「邀約被拒四格」軟規則（`prompts.ts:126`）。硬閘門移到 Batch B，隨 `InteractionSnapshotV2` 一起上。

### 4.5 partner scope 強制 clarify 的 UX 依賴（Batch A 風險標註）

Server 端閘門本身很小：把 `mustClarifyFirstRound` 的條件從 `global` 放寬為 `global | partner`（零逐字證據時），機制、fallback、重試提示全部有現成同構物（`clarification_policy.ts`、`generation.ts:407-414,450-457,681-699`）。但行為變化大：partner scope 的個案問題會全部先進免費釐清。Batch A 若不含規格 §11.1 的「選擇最近對話」按鈕，釐清卡只能用文字引導使用者切 conversation scope 或貼上對方最後幾則——體驗降級但止血正確。與 Batch B「partner scope 補最近對話」（§5.3）會直接解除此釐清的大部分觸發，兩批間隔不宜太久。

### 4.6 實作地圖補正：`coach_surface.dart` 與 evidence chips 雛形

規格 §11.2 的 evidence chips 不必從零做：`_CoachMemorySourceStrip`（`coach_surface.dart:442-487,1132-1186`）已渲染「教練參考：本段對話／舊摘要／最新分析／你的風格／對象資料／只看本段」。Batch D 把它從「來源類別」升級為「證據句」（她有反問／近 3 輪變短／只有 Profile 無逐字對話）即可。§14 地圖的 `global_coach_screen.dart` 列應改為 `coach_surface.dart`（含回饋分類 enum 也在此檔）。

### 4.7 新增 validator 詞表有現成機制模板

Batch A 的 placeholder／自貶／無限配合閘門，機制上完全比照 `UNSOURCED_NEGATIVE_MOTIVE_TERMS`（`generation.ts:105-111`）：短白名單詞表 → assert → 針對性重試 prompt（`buildAttemptPrompt` 已有六種錯誤類別的重試模板可加第七、八種）→ 兩次失敗 fail closed。差異只在：placeholder/自貶詞不需要來源比對（無論來源都不該出現在建議句）。注意規格 §9.1 的 `\bOO+\b` regex 在中文夾雜（「去OO店」）可命中、不會誤殺 GOOD/COOL，可用；全形 `ＯＯ` 與 `(店名)`／`［地點］` 需另列。

### 4.8 建議句／boundary 矛盾偵測應拆兩段（重切 Batch A/D）

規格把「擋 suggested line 與 boundary contradiction」放 Batch A。確定性可判的只有子集：`do_not_send ⇒ suggestedLine=null`（§4.2）與「boundaryReminder 含明確『不要再邀/先不要傳』詞群時 suggestedLine 不得含邀約語意」。一般語意矛盾（IMG_5571 型）需要 §9.2 的 contextual critic——留在 Batch D，避免 regex 高誤殺。

---

## 5. 修正後分批計畫

原規格 Batch A–E 的框架保留；以下為重切後版本，粗體為與原規格的差異。

### Batch A：止血（現行 wire schema 內，不動 Edge request/response 形狀）

| 項目 | 落點 | 既有先例 |
|---|---|---|
| A1. partner scope 零逐字證據強制免費釐清（文案引導：切對話 scope／貼上她最後 3–5 則） | `clarification_policy.ts`、`generation.ts`、`prompts.ts`（partner framing 段）、釐清 fallback 分支 | `mustClarifyFirstRound` 全域首輪閘門（2026-08-31 決策分岔案）整套同構 |
| A2. `do_not_send ⇒ suggestedLine=null` 硬規則＋prompt 契約「不傳是合法成功結果」 | `schemas.ts` superRefine、`prompts.ts` 輸出原則 | schema 已有跨欄 superRefine 先例 |
| A3. UI：do_not_send／suggestedLine=null 呈現「這輪先別傳」正面判斷卡（含理由與重新開啟條件），不顯示複製卡 | `coach_surface.dart`（`CoachChatResultView`） | 釐清卡已有正面呈現模式 |
| A4. placeholder 硬擋：`__`、`OO/ＯＯ`、`(店名)`、`[地點]`、`<時間>` → 重試 → fail closed | `generation.ts` 新 assert＋`buildAttemptPrompt` 新類別 | motive_drift 機制 |
| A5. 自貶求接住／無限配合關鍵詞閘門（低誤殺短表起步：可憐、都配合你、都可以看你方便…） | 同 A4 | motive_drift 機制 |
| A6. fallback 去 conversation-rescue：移除「丟一個好回答的小問題」預設與腦補罐頭句，改為保守「先別傳／先觀察」形狀 | `generation.ts:630-737` | — |
| A7. 七案 golden regression（以 §2.1 案表重建 fixtures，驗 invariants 不驗 exact sentence） | 新 Deno test（比照 `generation_test.ts` 純函式測法） | `quality_smoke_test.ts` 驗 prompt 契約的既有模式 |
| **移出**：兩次未承接禁止再邀（→B）、一般語意矛盾偵測（→D） | | |

驗收：G-01～G-06 案 action 正確；placeholder／腦補罐頭句洩漏 0%；partner scope 零證據時 0 建議句。

### Batch B：統一資料與決策

- `InteractionSnapshotV2`（evidenceQuality／inviteHistory／balls／messageDecision）＋條件式 schema 驗證（規格 §5、§10）。
- partner scope 補最近 15–24 則逐字對話＋snapshot freshness＋`sourceConversationId` provenance（客端資料路徑已存在，§3）。
- deterministic Action Resolver（規格 §6.1），含**兩次未承接邀約 → no_message/hold**（G-07）。
- priorAdvice／conversationEvidence 分流：`assertSuggestedLineGrounded` 來源改為只採 user turns＋對方訊息（§4.3）。
- 「教練本次參考：與 X 的最近對話，最後更新 …」前台標示。

### Batch C：共享知識核心

- 從 `analyze-chat/reasoning_core.ts`、`conversation_policy.ts`、`reply_voice.ts` 抽 feature-neutral 決策核心到 `supabase/functions/_shared/social/`（該目錄現況只有 guard/quota 類共用件，無社交知識，需新建）。
- 知識原子 typed registry＋確定性 selector（62 原子規模不需向量庫，維持規格判斷）。
- L2 → L3 執行順序；L1 僅教學召回。爭議詞彙依知識庫信心分級：**C/D 級詞不進 runtime prompt**，沿用 2026-07-08 文件的安全轉譯與剔除清單（App Review 風險）。

### Batch D：風格與生成品質

- voice contract（**依 §8 決策 1 的資料來源結論**；短期以 stuckPoints/goals/notes/avoidPhrases 起步）。
- semantic critic（固定 rubric、二次重寫、fail closed；critic 不得改寫 deterministic action）。
- 一般語意矛盾偵測（§4.8 後段）。
- evidence chips 升級（`_CoachMemorySourceStrip` → 證據句，§4.6）。

### Batch E：閉迴路優化

- 負評分類擴充（`too_beta`/`interview_only`/`wrong_stage`/`should_not_send` 等 10 類；`coach_surface.dart` enum＋submit-feedback Edge 白名單同步）。
- 72+ cases eval harness（6 任務 × 4 evidence quality × 3 investment trend）。
- 三輪後投入變化追蹤；不以單次回覆率為唯一指標（規格 §12.3 全數採納）。

### 上線門檻（採納規格 §13.3，補充一項）

規格 §13.3 全表採納。補充：Batch A 先行時，G-07（邀約歷史）門檻延至 Batch B 驗收，因資料通道屬 B（§4.4）。

---

## 6. 風險與審查要求

- **高風險區映射（AGENTS.md）**：Batch A–E 全數觸及 Edge schemas、AI prompt/token/cost 行為；Batch B 的 `costDeducted`/`clarify_user` 不扣費語意觸及 quota。**每批實作 PR 需 Codex＋Claude 雙 AI 審查**；本文件 PR 為文件-only，一般單審即可。
- **quota 語意不變式**：任何批次不得改變「免費釐清最多 3 次、clarifyingQuestion 不扣費、fallback 不扣費」既有語意（`schemas.ts` transform、`generation.ts` FALLBACK_NO_CHARGE 重掛機制）。
- **App Review**：知識庫 D 級詞（The Wall、Kino、ASD、Dread）與 C 級性別敘事詞**不得進 runtime prompt 或可見文案**；只可存於 L1 教學層與設計文件。爭議詞的內部 enum（betaPattern 等）不得外露為可見文字（比照 `不要輸出：PUA…` 現行禁詞行）。
- **回歸保護**：`prompts_test.ts` 有 byte-for-byte 回歸鎖（conversation/partner 兩型 prompt），Batch A 動 partner framing 時需同步更新測試基準，屬預期內變更、需在 PR 說明。

---

## 7. 待 Eric 決策

1. **voice contract 資料來源**（Batch D 前提）：恢復「關於我」互動風格收集 UI／改由對象層 override／從使用者實際訊息萃取風格特徵。建議：Batch D 前不阻塞，先用現有 stuckPoints/goals/notes。
2. **Batch A 的 partner scope 行為變化**（§4.5）：接受「零證據個案問題一律先免費釐清」的體驗降級（止血優先），或等 Batch B 一起上。建議：A 先上，A/B 間隔壓短。
3. **釐清卡「選擇最近對話」按鈕**是否納入 Batch A（增 UI 範圍）或 Batch B。建議：B。
4. **知識庫 C 級詞在 Learning tab（L1 教學層）的可見邊界**：知識庫以四層拆解保留了爭議詞原義，Learning 內容是否呈現原詞＋失效條件，或只呈現可操作翻譯。

---

## 8. 完成狀態對照（AGENTS.md 語彙）

- 本 PR 合併後＝**文件歸檔完成**，不是 feature complete；不觸發 Edge/migration/Build & Distribute。
- 「知識全面導入」的 feature complete 依規格 §18 十項驗收定義；每個 Batch 的實作 PR 各自報告其確切完成範圍。
