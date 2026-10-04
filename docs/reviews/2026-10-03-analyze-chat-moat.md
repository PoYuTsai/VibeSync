# 對話分析跟「把聊天貼進 ChatGPT」差在哪，哪些是別人抄不走的

全程唯讀。沒有改 repo 或 vault，沒有呼叫付費 API，也沒有查 production。

## 結論

- **護城河不在 prompt 裡。** 那份 48,842 字元的 prompt 有九成以上，ChatGPT 加一段好 prompt 在一天內就能做出來。它裡面最值錢的「判斷」能力，也已經有一部分搬到伺服器去了。
- **真正抄不走的東西都在 prompt 外面：** 伺服器決定的「不回」選單、跨片段的對象記憶、「建議送出後她怎麼反應」的結果記錄、分析、教練、陪練、48 小時提醒串成的迴圈，還有評測和人工校準資料。
- **這些多半只接了一半。** 分析本身既讀不到結果記錄，也讀不到用戶本人的事實，記憶在畫面上也幾乎看不到。
- **砍 prompt 不會傷到護城河，反而會把它露出來。** prompt 只需要留一層薄薄的「怎麼讀懂這些結構化輸入、怎麼把判斷寫成標籤」，其他都可以搬到 registry、伺服器或刪掉。

這裡要分清楚兩種對手：
- **用戶自己貼進 ChatGPT：** 下面第 (2) 類大多數他都做不到。
- **有工程團隊的競品：** 程式碼本身幾週就能抄，抄不動的只有資料和迴圈，而這兩樣我們目前也還沒累積起來。

---

## (1) 光靠 prompt 就給得出的東西（一天內可複製）

| 項目 | 位置 | 為什麼守不住 |
|---|---|---|
| 台灣口語、短句、不說教的語氣 | reply_voice.ts、prompt 第 62 行「正常人說話原則」 | ChatGPT 被要求「用台灣口語回」就做得到。第三方評的「繁中語感」是相對於簡轉繁的鍵盤類而言（competitors-zh-tw-2026-08.md:101），比不過 GPT 本身 |
| 五種風格（延展、共鳴、調情、幽默、冷讀） | stream_prompt 第 1043 行 | Sydney 視角 4/10。實際只有三個分支，冷讀幾乎固定是「我猜…對嗎？」（附錄 B，thin_opening 的 styleBranchIds） |
| 12 個以上情境矩陣、10 詞技巧表、1.2 到 1.8 的細則、70/30 法則 | conversation_policy.ts（16,090 字元），prompt 第 93–535 行 | 就是一堆技巧。教法一致性被評 3.5/10，有四套決策順序互搶優先，問句規則互相矛盾（:337 對 :386、:405） |
| 人設八條（富裕心態、情緒穩定…） | prompt 第 31–81 行 | 純文字，複製即得 |
| 熱度分數、五維度雷達、心理訊號、gameStage | prompt 第 513–543 行、report_contract.ts | 任何模型都會打分數。同一次回應還會出現兩個熱度（78 對 71），「她話裡的意思」在 23 案裡有 20 案是空的（reframer.ts:1398-1433） |
| 散文 few-shot、完整範例三份 | examples_legacy.ts、prompt 第 874–950 行 | 範例句會被模型逐字抄進輸出（健檢報告 §5：「被妳發現了…」出現 3 次，e2e C 有 3/23 抄進輸出）。vault 坑「輸出僵硬時加規則無效，刪範例與砍規則才有效」的實測：刪掉示範句後，「照抄 prompt」從 8/15 降到 0/15 |
| 「伺服器會擋並重試」的威嚇句 | stream_prompt.ts:238 | 這句是假的，伺服器其實不會擋（F10）。vault 坑「LLM 對 prompt 威嚇只服從到字面違規線」 |

**小結：** 這一類是 prompt 債的主體，也是目前 prompt 變重的原因。它們不構成任何差異。

## (2) 來自結構、資料或迴圈的東西（難複製）

依「ChatGPT 做不到」的強度排序。

1. **「不回」選單由伺服器決定，選單外的決定在扣額度前就擋下**
   - 程式在 `no_send_decision.ts:57-73` 的 `offeredNoSendDecisions()`。它看的是確定性的事實：誰最後發言、用戶發過幾則、伺服器自己量的低投入訊號（`knowledge_selector.ts:220-235`）。
   - 不回時有完整的下一步：等待條件、收尾句、「我還是想回」的最低壓力句、直達新話題的按鈕（ADR #49 第 4、6 點；`analysis_banners_section.dart:197-245`）。
   - 實績：23/23 決定正確，8 個不回情境全對（ADR #49；e2e/arm-C.json）。
   - ChatGPT 的訓練目標是「有用地產出回覆」，被問「怎麼回」幾乎一定給你一句。可可、戀聊這類鍵盤 App 的商業模式也給不出「別回」。
   - **這是目前唯一已經交付、又能對外主打的差異。**
   - 對工程團隊來說，程式只有約 20 行。抄不走的是「判斷是一等輸出」這個產品承諾，以及背後 23 案的驗證。

2. **建議送出後的結果記錄（目前唯一真正的資料迴圈）**
   - 分析頁、開場救星會記下用戶怎麼處理建議（原封送、改了送、沒送）和她的反應（熱絡、冷淡、沒回、負面）。相關程式在 `coaching_outcome_capture_card.dart`、`coaching_outcome_follow_up_bar.dart`、`analysis_screen.dart`。
   - 彙整成 `CoachingOutcomeDigest`（`coaching_memory/domain/entities/coaching_outcome_digest.dart`）之後，送進教練的 `outcomeInsightLines` 和 `inviteHistory`。後者用來壓制重複邀約（`coach-chat/schemas.ts:121-168`、`prompts.ts:30,49`）。
   - 事件也會去識別化上傳（`coaching_outcome_uploader.dart` 經由 submit-feedback）。
   - ChatGPT 不知道你送出後發生了什麼，這是結構上的差距。
   - 但這份資料目前是空的，因為還沒有真實用戶（vault VibeSync.md:147）。

3. **跨片段、跨平台的對象記憶**
   - `PartnerSummaryBuilder`（`partner_summary_builder.dart`）把歷次分析的興趣、性格、備註和用戶確認的資料，合成最多 1,500 字的背景。另外有上次階段當弱先驗（`stage_prior.ts`）。
   - 每次分析存成一筆獨立、加密、可按對象和平台找回的紀錄（ADR #20）。
   - 競品表上，「長期對象記憶」在繁中市場沒有對手（competitors:22,99）。
   - 但 ChatGPT 本身有記憶和專案功能，英文市場也已有記得對象的教練 App（Texting Wingman、Kizuna）。所以這條只對繁中鍵盤類算護城河，而且要等它在畫面上被看見才算數，見第 (3) 類。

4. **跨功能迴圈**
   - 分析快照會帶進教練（`coach-chat/prompts.ts:46`）。
   - 分析完成後會排 48 小時跟進提醒（`follow_up_plan.dart:33`）。
   - 陪練室和其他功能共用同一個教練大腦（`practice-chat/coaching_rubric.ts`）。
   - ChatGPT 不會主動提醒你，也沒有一個「同一個她」的練習場。

5. **知識 registry 和確定性選擇器**
   - `_shared/social/knowledge_registry.ts` 有 62 個 atom，分析和教練共用。每次請求只挑 6–10 條、最多 1,400 字元（`knowledge_adapter.ts:35-46`、`analyze_stream_handler.ts:525-545`）。
   - 這是把教法編碼成資料的骨架。條文本身抄得走，抄不走的是「依情境訊號挑選」加上伺服器政策。
   - **它也正是 16K 對話政策應該搬過去的地方。**

6. **評測和人工口味資料**
   - 黑箱語料 24 案、critic、盲選工具（`tools/analyze-v2-blackbox/`）、逐輪輸出（out/ 底下約 20 輪）。
   - Bruce 的人工盲測校準（`tools/opener-plan-write-eval/bruce_calibration.json`，612 行，含逐題願意送、最佳和理由）。
   - 這給的是「安全迭代的速度」，不是用戶看得到的價值。語料是人造的，校準目前只用在開場白。

**不算護城河、只算基本功：** 扣費只扣一次、「資料不夠」免扣（ADR #49 第 5 點）、免費權益由伺服器強制（ADR #25）。這些是信任的保健因素，競品團隊可以照做。

## (3) 宣稱了但還沒交付的

| 宣稱 | 位置 | 實況 |
|---|---|---|
| 「有記憶的 AI 約會教練」 | prompt 第 1 行（`reasoning_core.ts:3`） | 分析只拿到興趣、性格、備註和上次階段。封存紀錄不回流（ADR #20 第 8 點），結果記錄也沒接進分析（只有 coach-chat 吃）。畫面上看不到記憶（附錄 B weaknesses）。而且「約會教練」是已經退役的品類詞（positioning.md） |
| 「分析＋教練＋陪練＋記憶的完整迴圈」 | positioning.md §二 | `coach-follow-up/README.md` §1 明寫「Never reads/writes partnerSummary… or any long-term memory layer」。分析頁的 Sydney 只是底部一顆按鈕（`analysis_followup_section.dart:75`），口吻是「AI 推薦回覆」（`reply_zone_section.dart:388,443`） |
| 「帶你約出來」、北極星「時機成熟時推進邀約」 | `reasoning_core.ts:5` | 邀約時機 4/10。送出案裡寫「先不邀約」的比例：e2e C 是 6/15，c-gate C 是 11/26。她說「我這週末想去」，選中卡還是寫「週末我也可能過去」 |
| 「尊重用戶個性」、個人化原則、至少一張卡要 stretch | prompt 第 75 行、669–686 行、1047 行 | 「關於我」被刻意排除在分析之外（`effective_style_prompt_builder.dart:9-25`、`analysis_providers.dart:143-146`）。所以 stretchLevel 和個人化規則都在空轉（F17） |
| 不編造用戶的事 | `reasoning_core.ts:15` | 沒有用戶事實可用，結果只能編、填空或閃：「我做軟體相關的」「（填你實際拍照的地方）」「工作這題我晚點正經回妳」（critic-*.json）。照用戶視角的估計，需要回覆的分析大約每 4 次就有 1 次送不出去 |
| 每卡至少 3 段，伺服器會擋 | stream_prompt.ts:238 | 伺服器不會擋（F10） |
| 五種風格等於五種選擇 | — | 實際是三個分支湊出來的 |
| 資料護城河 | — | 結果上傳的管線有了，但沒有真實用戶，複製率也沒記錄 |

---

## prompt 必須留的薄層，和可以搬出去的部分

**原則：** prompt 只負責「讀懂結構化輸入」和「把判斷寫成標籤、附上她的原句」。決策用伺服器規則，教法用 registry，格式用 TS 常數。目標大小參考稽核估的 10–14K 字元（附錄 A promptMap 第五節）。陪練室的 coaching rubric 只有約 8 行，卻共用於四條生成路徑，可以當「薄層做得到」的現成證據（`practice-chat/coaching_rubric.ts`）。

### 必須留在 prompt（表達護城河的那一層）

1. **一句任務，加上只寫一次的衝突順序：** 安全 > 證據 > 投入 > 階段 > 選球 > 組句 > 聲音。這會取代現在四到五套互搶優先的決策順序。
2. **輸入契約，也就是「記憶怎麼用」：** 每個 user 段落只描述一次。
   - 對象背景、手動資料不是她這次說的話，不能當成要接的球，也不能引用成她的原話。
   - 上次階段只是弱先驗。
   - 結果記錄（之後接上時）只用來調整建議。
   - 用戶本人可用的事實清單。
   - 記憶抄不走，但模型要正確讀它，這幾行就是記憶的出口。
3. **判斷用標籤，而且附逐字證據：**
   - `messageDecision`：選單由伺服器注入，prompt 只定義選單裡有的項目，這點已經是現況。
   - 球的處置、`sourceIndex` 和 `sourceMessage`。「每段附她的原句」是用戶眼中最強的「它看懂了」訊號（`reply_zone_section.dart:617-620`）。
   - 要新增的標籤：邀約準備度、她的問題類型（例如問意見就要先表態）、`needsUserFact`。
4. **一條二元的誠實底線：** 用戶的事只能用准用清單裡的事實，否則輸出 `needsUserFact`，不准編也不准閃。
   - 依據是 vault 坑「配額式規則無效、單一二元規則有效」。
   - 可以沿用開場救星的 selfFacts 綁定（`opener_pick.ts`）。
5. **價值底線，3–4 行：** 健康主動性（`reasoning_core.ts:10`）、不操控、技巧名不准出現在可見文字裡。
6. **一段聲音說明，約 2.5K 字元，不放任何示範句：** 台灣口語、短、不評論對話本身、不用術語。

### 移出 prompt

| 內容 | 去處 |
|---|---|
| 12 個情境、技巧詞彙表、備用技巧工具箱、幽默技巧 | 已存在的 knowledge registry，每次請求挑選 |
| 問句額度、覆蓋下限、emoji、stretchLevel 預設、冰點處理 | 伺服器確定性政策（vault 坑「prompt 規則堆太多，後面幾條會被模型直接忽略」） |
| 邀約該不該推、被問意見要不要表態 | 模型給標籤，由伺服器規則決定 |
| report_contract 的非串流 JSON schema、done 裡的 finalResult、重複的熱度 | 由伺服器從已送出的事件組裝 |
| 輸出 schema 和列舉 | 由 TS 常數產生，延伸 `divergence_contract.ts` 的做法；重疊的列舉要拆開（F40） |

### 直接刪除

| 內容 | 原因 |
|---|---|
| examples_legacy 全份，含串流路徑永遠用不到的 userDraft 段落 | 範例會被照抄，userDraft 段落是死碼 |
| 完整範例三份 | 範例會被照抄 |
| 人設八條 | 價值底線第 5 點已經涵蓋 |
| 「關係節奏五階段」 | 和「Stage = latest task」矛盾（F16） |
| 個人化原則 | 已經不起作用 |
| 「伺服器會擋」威嚇句 | 是假的（F10） |
| PUA 色彩範例 | `conversation_policy.ts:18,23,67-68`、`reply_voice.ts:53,73` |
| 70/30 和互相矛盾的問句規則 | 矛盾規則讓模型含糊其辭 |

### 讓護城河真正出現的工作（都不在 prompt 裡）

- 把結果記錄接進分析的輸入，畫面上加一行像「上次她也這樣延後，後來是她主動約」的對照。
- 補上用戶事實這個輸入：缺事實時先問用戶一題，或留空格讓他填好才能複製。
- 第一屏由 Sydney 講判斷，把「先別回」當主打。
- 開始記錄複製和「先別回之後還是回了」的事件，讓資料護城河從零開始累積。

要提醒的是：用戶事實、標籤由伺服器決定、搬進 registry，這三項都是 R2，要 Eric 拍板（「關於我」要不要回到分析，會碰到 2026-08-04 的決定），而且要用付費黑箱各跑至少 3 輪來驗證。這次全部沒有實作，也沒有跑。

### 主要參考檔

- 附錄 B：三方產品視角（docs/reviews/2026-10-03-analyze-chat-health-audit-perspectives.md）
- 健檢報告（docs/reviews/2026-10-03-analyze-chat-health-audit.md）
- /home/eric1/work/VibeSync/supabase/functions/analyze-chat/no_send_decision.ts
- /home/eric1/work/VibeSync/supabase/functions/_shared/social/knowledge_registry.ts
- /home/eric1/work/VibeSync/supabase/functions/analyze-chat/knowledge_adapter.ts
- /home/eric1/work/VibeSync/lib/features/partner/domain/services/partner_summary_builder.dart
- /home/eric1/work/VibeSync/lib/features/coaching_memory/domain/entities/coaching_outcome_digest.dart
- /home/eric1/work/VibeSync/supabase/functions/coach-chat/schemas.ts
- /home/eric1/work/VibeSync/supabase/functions/coach-follow-up/README.md
- /home/eric1/work/VibeSync/supabase/functions/practice-chat/coaching_rubric.ts
- /home/eric1/work/VibeSync/tools/opener-plan-write-eval/bruce_calibration.json
- /home/eric1/work/VibeSync/docs/decisions.md（ADR #20、#49）