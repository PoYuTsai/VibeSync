# 對話分析健檢附錄 B：三方產品視角與結構刀方案（2026-10-03）

> 主文見 [2026-10-03-analyze-chat-health-audit.md](2026-10-03-analyze-chat-health-audit.md)。下列分數是模型扮演各視角給的主觀評分，評審與受評模型同家族，只當方向參考；沒有真實用戶數據。證據裡提到的 scratchpad 腳本是審查時的一次性腳本，沒有進 repo。

## 三方視角綜合

一、三個視角都同意的地方
1. 核心價值在「判斷」，不在「代寫」。「先別回」、「先收尾」加上理由和收尾句，是鍵盤類回覆產生器給不了的東西。5.5 在 e2e 23/23 決定正確，不回案 8/8 判對。第三方顧問說它是能拿來對外主打的能力，Sydney 給判斷 8.5 分，用戶給 8 分。
2. 最大的品質破洞，是她問到用戶本人的事時，系統拿不到他的事實，於是編造、留填空或閃躲（F02）。三方都列為必修，用戶估計需要回覆的分析大約每 4 次就有 1 次送不出去，而這正好是他最焦慮的時刻。
3. 「等有點久」的最大一塊是 App 的設計造成的，不是模型。推薦卡約 8 秒就到了，卻要等約 18 秒的 done 才能複製（F03）。這是最便宜、最有感的修正，不需要動 prompt。
4. 五張風格卡是在稀釋，不是在差異化。五種風格其實只由三個分枝湊出來，冷讀幾乎都是同一個句型，壞事情境裡「調情」卡還要特別寫明「不調侃」。三方都主張改成「一張推薦卡加最多兩種相符語氣，其他點了才生成」（F09）。
5. 教練品牌和記憶在分析畫面上看不到：口吻是「AI」，Sydney 只是底部一個按鈕；「記得她」這件事在結果裡幾乎看不出來；最像教練的那句 expectedReaction 模型寫了卻從不顯示（F51）。
6. 目前沒有任何真實用戶訊號，所有品質結論只來自 23–42 案的黑箱加同家族模型的評審（F31）。

二、看法不同或各自強調的地方
- 第三方顧問：真正要贏的對手是免費、秒回的 ChatGPT 加上用戶自己的判斷，不是繁中鍵盤 App。所以差異只能來自三件 ChatGPT 做不到的事：記得她、知道什麼時候不回、教練會跟進結果。記憶這道護城河只是相對繁中鍵盤類而言，英文市場已經有記得對象的教練 App。它的市場驗證只給 2 分，可演進性給 4 分。
- Sydney 教練：最嚴厲的扣分在「邀約時機」（4 分）：她已經打開窗口，系統卻常寫「先不邀約」，送出案 6/15 到 11/26 都這樣（F29）。其次是被問「你覺得呢」時不表態（F30）。教法本身一致性只有 3.5 分：四套決策順序、互相矛盾的問句規則、帶 PUA 色彩的舊範例（F16、F18）。實際輸出的倫理和語氣倒是安全的（8 分）。它主張輸出改成教練四件套：判讀、動作、一句話、一句為什麼，並把「點出他自己的錯」（雙發、「我也差不多」、查戶口）當成一級輸出。
- 用戶視角：最在意摩擦和雜訊。開始前要 4 個確認動作；結果頁同一句推薦出現兩次，還有一堆數字和術語（冷讀、調情、61/90）；「她話裡的意思」可能是空白卡（F06，本次核實 20/23 案為空）；額度單位「則」實際是 40 字，免費額度在養成習慣前就用完了（F50）。
- 對免費方案的處理也不同：第三方顧問建議改成以「替代風格數和再調整次數」來區分付費（需要重新拍板 ADR #25）；用戶視角認為問題在於免費額度太小，「先別回」又照樣扣額度。

三、值不值得做
值得。最有價值的是判斷和不回決策，而且已經做到教練等級；回覆品質大約六成可以原封送出，失敗原因集中、可以結構性修正。但目前價值只停留在「設計上成立」，在市場上還沒被驗證。

四、能不能做到市場最好
可以拿下「繁中曖昧聊天下一步」這個利基的第一名，但取勝的不是速度，也不是五種風格。要贏的是：判讀準、一句敢原封送出的話（包括叫他別送、叫他現在約）、記得這個人。先決條件依序是：
1. 用戶本人事實的管道（F02）。
2. 首卡到了就能複製（F03）。
3. 邀約準備度和「表態」變成結構化標籤，交給伺服器政策（F29、F30）。
4. 真實的複製率與結果遙測（F31）。
5. 分析第一屏要看得到 Sydney 和記憶（F51）。
市場比較主要依靠第三方的搜尋結果，例如 YourMove 宣稱 5 秒出三句、Rizz 被抱怨在地化差、Texting Wingman 有記憶；新出現的在地競品「曖昧告解室」品質未核實。

五、Eric 問的「哪些元件可以共用、哪些要重新設計」
- 可以共用：不回決策的「伺服器給選單、模型選 enum」模式；新話題「先問再生成」的元件；送出句守門；client 等待 UI 和 NDJSON 傳輸；exactly-once 的純函式；評測工具包。
- 要重新設計：產品形態（一張推薦卡加 Sydney 的一句判斷，而不是五卡加一份報告）、user turn 編譯（加上 id、只用一套片段定義）、輸出契約（單一 JSONL、done 只當結束訊號）、分析與寫卡要不要拆開（先量 plan-off 再決定）。

六、Bruce 的擔心
「怕超大 prompt、怕 regression」有具體成因：CI 只跑約 21% 的測試，部署前完全不測（F21）；約 300 句 prompt 原文鏡像測試讓任何改寫都轉紅（F20）；v2 是在舊底座上加條件補丁，再用 SHA 鎖住（F19）；還有 2,077 行的單一函式（F24）。安全的順序是：先接好 CI，把鏡像換成語意錨點，加上零成本的重播測試和雜訊帶（F21、F20、F47、F46）；接著刪除死碼和 legacy 路徑（F17、F32、F26）；最後才動 prompt 和管線的結構刀。每一步都用黑箱、以「付費用戶會不會原封送出」作為驗收標準。

## 視角：獨立第三方消費型 AI 產品策略顧問，評估「對話分析（analyze-chat）」這個 VibeSync 核心功能。全程唯讀：讀了程式碼、ADR、黑箱真實輸出，並做了市場搜尋。沒有呼叫付費 API，也沒有查 production。

**價值判斷**：有真實價值，但目前的價值大多還只是「設計上成立」，市場上尚未驗證。

已用資料核實的部分：
- 「要不要回」這個判斷是真正的強項。Sonnet 5.5 在端到端 23 案中決定全部正確（docs/decisions.md ADR #49「驗證」段）。
- 遇到軟拒絕、冷淡、對方已劃界線時，它會給「先收尾」或「先別回」並附理由，例如 cold_one_word_replies、user_over_investing、boundary_friend_hint 這幾案（tools/analyze-v2-blackbox/out/2026-10-02-e2e/arm-C.json）。
- 市面上的回覆神器（可可、戀聊、Rizz 系）一律產生回覆，這種「教你什麼時候不回」正是它們商業模型給不出來的東西。

回覆品質大致可發送，但有一個結構性破洞：她問到用戶本人的事時，模型不知道用戶的事實，結果會：
- 編造，例如「我做軟體的」「那是在山上拍的」；
- 留下填空，例如「（填你實際拍照的地方）」；
- 或閃避，例如「工作這題我晚點正經回妳」。

以上都出自 critic-A/B/C 的 rewrite 案例。這正好落在「付費用戶會不會原封發送」的不及格區。

從三個視角看：
- **用戶視角**：值得付費的是「讀懂現在該怎麼辦」再加「一句敢直接貼的話」，不是五張卡或雷達報告。
- **Sydney 教練視角**：分析頁現在用中性的「AI 推薦回覆」口吻（reply_zone_section.dart:388、443），Sydney 只是底部一個按鈕（analysis_followup_section.dart:75）。教練品牌在核心功能裡缺席，「完整迴圈」的信任狀在畫面上看不到。
- **第三方視角**：繁中市場目前沒有同等級的對手（docs/research/competitors-zh-tw-2026-08.md）。真正的對手是免費、秒回的 ChatGPT／Gemini，2026 年調查顯示多數年輕單身族已經在用它處理約會訊息。

結論：有價值，而且最有價值的是判斷與不回決策。但產品價值完全沒有真實用戶數據支撐：vault 記載「無真實使用者、Phase 4 要真實資料才能開」，30 天 Anthropic 費用約 US$10（Dev Brain VibeSync.md 第 52、147 行）。

**能否做到市場最好**：可以成為繁中市場最好的，但取勝的軸不是速度，也不是五種風格，而是「判讀準確＋有底氣的一句＋記得這個人」。

先講速度。
- 換 5.5 之後，決定約 3 秒出現，第一張卡約 7–10 秒，全部完成約 15–20 秒（e2e/arm-C.json 的 milestonesMs，例如 she_shares_bad_day 決定 3.4 秒、首卡 7.3 秒、完成 19.8 秒）。
- 歐美競品宣稱 5 秒內給三句（YourMove，見 topai.tools）。
- 以「分析型」產品而言，10 秒內看到一句可用的話是可以接受的。
- 但目前的程式碼讓這個優勢白費：串流中的卡片沒有複製按鈕（streaming_content_section.dart 只有顯示，沒有 onTap 或複製）；複製只存在完成後才出現的 ReplyZoneSection（analysis_screen.dart:4219–4226 對照 4137）。用戶實際要等到完成那一刻才能動作。

再講五種風格。五種是由三個分支湊出來的：thin_opening 的 styleBranchIds 裡，humor 與 resonate 共用 br_2，coldRead 與 tease 共用 br_3。冷讀風格幾乎每案都是「我猜…對嗎？」的固定句型（e2e arm-C 全部 coldRead）。這是在稀釋品質，不是差異化。

要成為最好，要做到這幾件事：
1. 一張推薦卡，串流到了就能直接複製；替代風格點了才生成。
2. 補上「你自己的事」這個輸入：沿用開場救星的准用自述綁定，或者先問用戶一題再寫。
3. 分析用 Sydney 的口吻講一兩句判斷，把「先別回」當作主打賣點。
4. 讓「對象記憶」在分析結果裡看得見，例如「上次她也這樣延後，後來是她主動約」。
5. 先拿到真實用戶的複製率與回報結果。沒有這個，「最好」無從證明。

護城河提醒：英文市場已經出現有對象記憶的教練 app（Texting Wingman、Kizuna AI），所以「記憶」的抄不動期限只是相對於繁中鍵盤類而言。

| 面向 | 分數 | 理由 |
|---|---|---|
| 使用者真實價值（解決曖昧期的焦慮與「該怎麼辦」） | 7 | 「先別回／先收尾」加理由，以及下一步建議，是鍵盤類給不出的東西（ADR #49；e2e arm-C 的不回案例）。但價值還沒有真實用戶驗證。 |
| 情境判讀準確度 | 7.5 | 5.5 端到端決定 23/23 正確（ADR #49）。弱點已記錄在案：被問「你覺得呢」時常反問、不表態，偶爾問句超額（ADR #49 驗證段；critic 的 non_actionable 與 beta_pattern）。 |
| 可直接發送度（付費用戶會不會原封傳出） | 6 | 評審判定 e2e C 需改寫 3/15、ab A 需改寫 8/29。主因是編造用戶自身事實或留填空（critic-*.json 的 unsupported_fact）。冷讀風格公式化。 |
| 速度與等待體驗 | 5 | 5.5 首卡約 7–10 秒，算可接受，但串流中的卡片不能複製，等於還是要等 15–20 秒（長對話約 29 秒）。關掉 5.5 開關會退回中位數 30 秒。 |
| 差異化與護城河 | 6 | 在繁中市場，判斷＋教練＋記憶的組合沒有對手（competitors 調查）。但分析畫面沒有呈現記憶與 Sydney；英文市場已有記憶型 app；免費的 ChatGPT 是隱形主對手。 |
| 市場驗證程度 | 2 | 沒有真實用戶與 dogfood 數據（vault VibeSync.md:147「無真實使用者」「沒心力 dogfood」）。品質判斷全靠 23–42 案的黑箱與模型評審。 |
| 可演進性（能否安全迭代產品） | 4 | 串流系統 prompt 約 4.1 萬字元、91 個標題；同一支 Edge Function 承接 9 種請求。Bruce 原話「怕這個超大 prompt 很難改、怕有 regression」與這個規模一致，直接拖慢產品實驗速度。 |

**強項**

- 「不回」決策由伺服器決定可選的選單，模型只能在選單內選（ADR #49 第 4 點）。判斷可信度高，也能防止「嗨／哈囉」被誤判成先別回。這是全市場少見、可對外主打的能力。
- 情緒支持情境的回覆品質高。she_shares_bad_day 的 resonate 卡「當眾被罵又不是妳的錯…今天先什麼都不用撐，想說的話我都在」可以原封發送（e2e/arm-C.json）。
- 約會推進情境實用。defer_with_alternative 直接給出時間與二選一（「週日可以！那天晚上六點半，日式還是義式」），符合定位「帶你約出來」（docs/positioning.md）。
- 有明確的品質判準與黑箱、盲選、評審的評測基礎設施（tools/analyze-v2-blackbox/），換模型時有數據可依。
- 已經有結果回報的機制（analysis_screen.dart:3430「發出後記得回來回報結果」、3673 coachingUserAction），是做 Phase 4 結果導向的種子。
- 免費用戶的權益由伺服器強制（ADR #25），不靠前端隱藏。

**弱點**

- 她問用戶本人的事（工作、照片在哪拍、看什麼片）時，系統沒有用戶事實可用，結果是編造、填空或閃避。About Me 被刻意排除在主分析之外（analysis_providers.dart:143–146），而且 About Me 只有興趣標籤之類的晶片，沒有工作等可寫進句子的事實。
- 串流中看得到卡片卻不能複製（streaming_content_section.dart 沒有任何複製或點擊動作），把 5.5 首卡約 7 秒的優勢浪費掉。
- 五種風格由三個分支湊出，humor 與 coldRead 常在重用別張卡的分支（arm-C thin_opening 的 styleBranchIds）。冷讀幾乎固定是「我猜…對嗎？」。卡多不等於選擇多，反而增加閱讀負擔與輸出 token（五卡占輸出 35%，vault VibeSync.md:147）。
- 輸出的 25% 給了 done 事件裡的舊版報告，其中 finalRecommendation 與 gameStage 是伺服器不採用的重複輸出（vault VibeSync.md:147）。詳細分析預設收合（detailed_analysis_section.dart:38「展開詳細分析」），用戶多半不看，卻每次都付等待時間與成本。
- 分析頁的口吻是「AI」而不是 Sydney（reply_zone_section.dart:388、443；final_recommendation_card.dart:30），教練品牌與核心功能脫節。
- 每筆分析都是獨立片段，封存紀錄不回流成模型輸入（ADR #20 第 8 點）；只有 partnerSummary 與上一個階段作為弱先驗（analysis_providers.dart:175、194–212）。定位講「它認得你聊的每一個她」，在分析結果裡卻幾乎看不到。
- 沒有真實用戶數據。哪種風格被複製最多、推薦卡被採用的比例、「先別回」被遵守的比例，全部未知（vault VibeSync.md:147）。
- 已知「被問你覺得呢不表態」的弱點仍未處理（ADR #49 驗證段；she_asks_his_opinion 的 resonate 卡以反問收尾）。

**必修**

- 讓推薦卡在串流一到就能複製：在 StreamingContentCard 的 replyOption 項目加上複製動作，或讓 ReplyZoneSection 在選中卡事件後就先出現。這是最便宜、對「等有點久」最有感的改法：體感從約 17 秒降到約 7 秒，不必動 prompt。
- 補上「用戶自身事實」這個輸入，把它當結構刀而不是 prompt 規則。直接沿用開場救星的 selfFacts 綁定與 self_fact_unbound 否決（opener_pick.ts:4、14、23–24）。她問到用戶時，可以先問用戶一題（同 ADR #47 兩段式「先分析、再讓用戶補充」），或給明確標示的空格讓用戶填，不可讓模型編造。證據：critic-B「我做軟體相關的」、critic-C「（填你實際拍照的地方）」（tools/analyze-v2-blackbox/out/2026-10-02-ab/critic-*.json）。
- 在宣稱品質或改版前，先拿到真實使用訊號：記錄每次分析複製了哪個風格、是否用了推薦卡、「先別回」之後有沒有還是回了。Eric 與 Bruce 各自真機 dogfood 至少一週。目前所有品質結論都只來自 23–42 案的黑箱。
- 處理「被問你覺得呢不表態」：讓決策階段輸出一個「她在問意見→必須表態」的結構化標籤，交給伺服器檢查，不要再加 prompt 句子。這個問題已記錄在 ADR #49 待另案。

**要重新思考**

- 產品形態從「每次五張卡加一份報告」改成「Sydney 一句判斷＋一張推薦卡（可立即複製）＋兩個替代風格，其餘點了才生成」。這樣可以砍掉約三成五的五卡輸出與二成五的舊報告輸出，同時降低等待、降低成本，也讓 prompt 變小。免費／付費的差異可以改成「替代風格與再調一下次數」，不必是「看得到幾張卡」（需 Eric 重新拍板 ADR #25）。
- 把分析拆成「判斷」與「寫卡」兩段，比照開場救星的 plan／write／pick 和新話題的兩段式：判斷段（約 3 秒）只輸出結構化的決策、球的清單、分支計畫；寫卡段只拿到它需要的輸入。這是 Bruce「超大 prompt 不敢改」的根本解法，也讓三個功能共用同一套「判斷→（必要時問用戶）→寫→伺服器挑」骨架。
- 可以共用的元件：(a) 開場救星的准用自述綁定與挑選否決規則（opener_pick.ts）；(b) 「缺素材就先問用戶一題」的兩段式流程（ADR #47、new_topic_two_stage.ts）；(c) _shared/social 的 reasoning_core、reply_voice、candidate_guard、semantic_critic，作為三個功能共同的聲音與守門層；(d) 黑箱、盲選、評審的評測工具，三個功能共用同一判準。
- 「先別回」要從防禦性功能升格為主打賣點與教練時刻：用 Sydney 的口吻講為什麼不回，給等待條件，到時間提醒回來。傳播主軸「一句話救不了一段曖昧」在這裡最有說服力（docs/positioning.md 第三節）。
- 讓記憶在分析結果裡被看見：例如加一行「跟上次比，她這次主動多了」，引用作戰板的熱度與階段。否則定位上的信任狀在核心功能裡等於不存在。
- 重新思考詳細分析報告（投入度、雷達、心理訊號）：改成「點開才生成」或併入對象作戰板的趨勢，而不是每次分析都同步產生並占用等待時間。
- 對手設定要改：真正要贏的是「免費 ChatGPT 加自己判斷」。差異只能來自三件 ChatGPT 做不到的事：記得她、知道何時不回、教練跟進結果。這三件都應該出現在分析畫面的第一屏。

**證據**

- tools/analyze-v2-blackbox/out/2026-10-02-e2e/summary.md：Sonnet 5 p50 30.1s／p95 40.2s；Sonnet 5.5 p50 16.6s／p95 20.9s；23 案共 US$1.680（約每次 US$0.073）
- tools/analyze-v2-blackbox/out/2026-10-02-e2e/arm-C.json：各案的 milestonesMs（決定約 2.6–5.3 秒、首卡約 6.7–16.4 秒、完成約 5.6–28.7 秒）、五卡內容、不回理由；thin_opening 的 styleBranchIds 只有三個分支
- tools/analyze-v2-blackbox/out/2026-10-02-ab/critic-A.json、critic-B.json、critic-C.json 與 2026-10-02-e2e/critic-C.json：需改寫的比例與 unsupported_fact 例句（「我做軟體相關的」「（填你實際拍照的地方）」「我做業務類的」）
- tools/analyze-v2-blackbox/out/2026-10-02-ab/blind.md：第 1 題甲乙兩份都編造「我做軟體的」
- lib/features/analysis/presentation/sections/streaming_content_section.dart（沒有複製動作）；lib/features/analysis/presentation/screens/analysis_screen.dart:4219-4226（串流卡）對照 4137（ReplyZoneSection，有複製）
- lib/features/analysis/presentation/sections/reply_zone_section.dart:388、443（以「AI 判斷／AI 推薦回覆」為口吻）；analysis_followup_section.dart:75、108（Sydney 只在底部按鈕）
- lib/features/analysis/data/providers/analysis_providers.dart:143-146（主分析明確不帶 About Me）；lib/features/user_profile/domain/entities/user_profile.dart（只有興趣、風格等晶片，沒有可寫進句子的事實）
- supabase/functions/analyze-chat/opener_pick.ts:1-24（selfFacts 准用自述綁定、self_fact_unbound 否決，可共用）
- docs/decisions.md ADR #20（第 8 點：封存紀錄不回流成模型輸入）、ADR #25（免費兩種風格）、ADR #47（開場救星兩段式）、ADR #49（5.5 開關、伺服器決定不回選單、已知弱點）
- docs/positioning.md（定位「帶你從曖昧走到約出來」，信任狀是記憶加完整迴圈）
- docs/research/competitors-zh-tw-2026-08.md（繁中競品表：可可鍵盤月 NT$120、戀聊鍵盤月 NT$990、CMoney 2.9★、歐美系全英文）
- /mnt/d/Obsidian個人大腦/Dev Brain/40_專案筆記/VibeSync.md:52、147、59（30 天 Anthropic 約 US$10；無真實使用者；輸出 token 去向；開關已在 2026-10-03 開啟，第一筆正式分析 15.0 秒）
- 市場來源：https://topai.tools/t/yourmove（YourMove 宣稱 5 秒內出三句）
- 市場來源：https://kimola.com/reports/unlock-insights-with-our-rizz-app-review-analysis-app-store-us-149679 、https://kimola.com/reports/rizz-app-feedback-analysis-key-insights-for-success-app-store-de-157592（Rizz 的抱怨：價格、回覆不知所云、在地化差）
- 市場來源：https://apps.apple.com/us/app/texting-wingman/id6737630517 、https://www.appgoblin.info/apps/6769436247（英文市場已有記得對象、存聊天史的教練 app）
- 市場來源：https://apps.apple.com/tw/app/id6578435303（曖昧告解室，繁中，有導師、練習與每日卡片，是新發現的在地競品；評分未查）
- 市場來源：https://www.globaldatinginsights.com/news/arrows-survey-ai-sees-widespread-use-and-dislike-in-dating 、https://www.axios.com/local/kansas-city/2026/07/14/singles-want-ai-help-not-ai-partners（2026 年多數單身族已用 ChatGPT 之類的工具處理約會，代表免費通用 AI 是主對手）
- 未核實：每次分析扣幾則額度、真實用戶的複製率與風格偏好、曖昧告解室的評分與實際品質

## 視角：Sydney：頂尖戀愛教練視角（專帶台灣男生的曖昧／傳訊教練）。我用教練的標準看兩件事：一是分析和回覆是不是真正的高手會給的；二是 prompt 裡寫的教法本身通不通。真實輸出讀的是 tools/analyze-v2-blackbox/out/2026-10-02-e2e（Sonnet 5.5 的 C 臂＝現在 production；Sonnet 5 的 A 臂＝備援），另外交叉對照 c-menu、c-menu-retry 兩輪。逐案判讀了 17 個案例，其中多個案例跨輪比對過。哪些是我在檔案裡核實過的、哪些只是我的教練意見，下面都會分開標。

**價值判斷**：有真價值，但價值集中在「判斷」，不在「代寫」。

核實過的強項有三個：
- 要不要回的判斷，已經是頂尖教練等級。e2e C 臂 23/23 決定正確（tools/analyze-v2-blackbox/README.md 的 e2e 段落）。被婉拒、模糊延後、說有男友、只想當朋友、他已經回過球在她那邊、她連續一字回，這些情況都正確收手；收尾句也短、不追問、沒有問號，例如 soft_reject_after_invite「沒問題，妳先忙，有空再說」、user_waiting_after_reply 判先別回，理由是「最後一則是他自己發的，球在她手上」。一般的 AI 撩妹產生器只會一直生句子，「該停」正是它們給不了、教練最值錢的那一句。這件事 VibeSync 已經做到了。
- 她給出明確時間時，帶領力是對的。defer_with_alternative：「加班辛苦了，週日可以！那天晚上六點半，日式還是義式，妳挑一個？」這句我會直接讓學員送出。
- 偶爾會出現真正能教人的一刀。long_conversation_35 的 reminder：「前面你連續回了好幾次「我也差不多哈哈」，她每次都問「你呢」，這是在要你分享自己」，這就是教練費的價值所在。

但「付費用戶會不會原封不動送出」這個標準，在三類高頻情境明顯不及格：
- 她問他本人的事（工作、照片在哪拍、推薦什麼片）
- 她問「你覺得呢」
- 她回溫、出現邀約窗口

這三類失敗不是措辭問題，而是結構問題：系統沒有取得用戶本人事實的管道，教法也沒有把「何時該約」當成主要判斷。

總結：判斷層值得當產品核心，代寫層目前大約六成可以直接用。

**能否做到市場最好**：以下是教練意見，我沒有做競品調查，市場面屬未核實。

要在台灣戀愛教練這個類別做到最好，致勝點不是「五種風格的漂亮句子」，因為任何通用模型都生得出來。致勝點是「一個比你朋友更準的判讀＋一個你敢送的下一步，包括叫你別送、叫你現在約」。VibeSync 的不回判斷、記憶、盤點已經走在這條路上。

要做到最好，還差三件事：
1. 用戶本人事實的管道。缺事實時先問一題，或留明確的填空，不准編、也不准閃。現在 5.5 對同一個輸入，一次編「我是做軟體相關的」、一次閃「我的工作說來話長」（c-menu 的 she_asks_personal_question #1、#2）。
2. 邀約時機要變成一等判斷。現在 5.5 有約四成的 send 決定寫「不要急著邀約」，連她照他推薦去吃拉麵、還誇他品味都這樣寫。
3. 輸出從「每顆球都回、五張卡」改成「一個判讀 → 一個動作 → 一句可送的話（加一個換口氣的備案）→ 一句為什麼」。

這三件做到了，有機會成為市場最好；做不到，就只是比較謹慎的撩妹產生器。

| 面向 | 分數 | 理由 |
|---|---|---|
| 送不送的判斷（不回／收尾／先別回） | 8.5 | e2e C 臂 23/23 決定正確。婉拒、延後、有男友、當朋友、雙發、冷淡一字回都正確收手，收尾句沒有追問也沒有問號。唯一的教學缺口：cold_one_word_replies 只說她冷，沒點出他自己在查戶口（「你平常有什麼興趣嗎」）。 |
| 局勢判讀（投入度、她在給什麼） | 7 | 盤點和 coach_hint 多半讀對，例如 long_conversation_35 的 read：「是在留一個低壓窗口，不是單純問路」。但同一次回應出現兩個熱度分數（metrics 78，done 71；she_asks_his_opinion 68 對 62），有小誤讀（after_meetup_followup「到家了還特地跟我說」，其實是他先問的），也會編出沒有證據的事（thin_opening「回這麼快」）。 |
| 選中卡能不能原封送出 | 6 | 排時間、收尾、她心情差、她邀約、被吐槽這幾類很好。她問他本人的事、問意見、回溫敘舊這幾類不及格：「工作這題我晚點正經回妳，先讓妳猜一下」、「那張是我自己拍的那個地方」、「我覺得先看妳自己比較在意什麼」。這幾句我都不會讓學員送。 |
| 邀約時機與推進 | 4 | 只有她先開口（she_invites_first、defer_with_alternative）時才會推進。她照推薦去吃拉麵、看了他推薦的片、結案回來問他近況、說週末想去他講過的咖啡廳，這些都是明顯窗口，卻得到「不要急著跳邀約」或被動的「週末我也可能過去」。這違反它自己在 reasoning_core.ts:5 寫的北極星「時機成熟時自然推進邀約」。 |
| 對用戶本人事實的誠實 | 3.5 | Sonnet 5（現在的備援）會直接編：「我做業務類的」、「在山上一個步道拍的」、「最近覺得不錯的是《驅魔麗娜》」。5.5 有時候編（「我是做軟體相關的」），有時候閃（「我的工作說出來怕嚇到妳」）、或回空話（she_returns_after_silence 五張卡都是「我最近還好，沒什麼大事」）。這三種都不是教練會做的事。 |
| 可教性（理由有沒有教到東西） | 5 | 每段都附理由，但大多是重複的套話：「安全誤讀，給她好反駁的台階」、「溫和猜測，留修正空間」。重複量很大。偶爾有真正的金句（「我也差不多」那條 reminder）。五卡加逐段理由吃掉約 27% 的輸出 token（vault VibeSync.md:147），換到的教學價值卻很低。 |
| 倫理與語氣安全（實際輸出） | 8 | 這些輸出裡沒看到操控、施壓或物化。心情差的案例會主動把 tease、humor 收成陪伴語氣。只有輕微的扣分點，例如 c-menu「先猜猜看？猜對我才告訴妳」這種扣住資訊的姿態。語料沒有篩選題或刁難測試題，所以 prompt 裡那幾段 PUA 色彩範例會不會被照抄，未核實。 |
| 教法本身的一致性 | 3.5 | 同時存在四套「決策順序」：reasoning_core 七步、conversation_policy 場景判斷優先級六步、reply_voice 使用順序三步、stream_prompt Situation Knowledge 的分層順序。問句規則互相打架：70/30 聆聽、陳述優於問句，對上至少一個推進動作（反問）、兩段式第二部分要提問／冷讀。還有十二個以上的情境、十個技巧詞、從 1.2 到 1.8 的細則，是一層一層疊上去的技巧集，不是一套方法。 |
| 五種風格的實際價值 | 4 | 固定的風格分類硬套在不合適的情境：心情差時 tease 卡只能寫成「只用最溫和的陪伴語氣，不調侃」。差異化常常退化成同義詞，例如 she_returns_after_silence 的第三段在五張卡裡全是「我最近還好／日子很一般」。五卡也直接拖慢等待時間：五卡齊要 27.4s，選中卡只要 16.2s（run14）。 |

**強項**

- 要不要回的判斷是真正的差異化，而且已經做對。opening_boundary 的收尾句「了解，謝謝妳說清楚，祝妳一切順利。」、boundary_friend_hint 的 avoidThis「不要追問原因、不要說「我可以等」、不要試圖說服她改變主意」都是教科書級（e2e arm-C.json）。
- 她給出明確時間時，帶領得乾淨。defer_with_alternative：「加班辛苦了，週日可以！那天晚上六點半，日式還是義式，妳挑一個？」；logistics_confirm：「十分鐘沒問題，妳慢慢來，到了跟我說」。
- 她情緒低落時，resonate 的品質高：「我猜讓妳最難受的不是被罵，是明明沒錯還得當場忍下來」（she_shares_bad_day 的 coldRead），而且決定是「不要說教、分析主管對錯、開玩笑或急著邀約」。
- 被吐槽時不急著證明自己，又會埋下次見面的鉤子。she_teases_him 的 tease：「妳這麼不信我，要不要下次一起跑，親眼驗證一下？」
- 偶爾會點出用戶自己的壞習慣，這是教練最值錢的那一刀。long_conversation_35 的 reminder 點破他連續回了好幾次「我也差不多哈哈」。
- 5.5 大致守住「不替用戶編經歷」的底線，比 Sonnet 5 的捏造好：hobby_common_ground「說實話我只玩數位，底片機沒資格推薦，妳現在用的是哪台？」是誠實又有態度的版本。
- prompt 的價值觀底線是健康的：健康主動性要清楚表達意願、尊重對方反應、能承擔被拒絕（reasoning_core.ts:10），減法原則不收操控話術（conversation_policy.ts:137-141），技巧名不得進到訊息本身。

**弱點**

- 沒有取得用戶本人事實的管道，這是最大的品質洞。誠實規則加上缺資料，結果只會是編或閃。Sonnet 5 A 臂編了「我做業務類的」、「在山上一個步道拍的」、「《驅魔麗娜》」；5.5 在 c-menu 同一題一次編「我是做軟體相關的」、一次閃「我的工作說來話長，晚點再慢慢講給妳聽」；e2e C 臂「那張是我自己拍的那個地方」根本不是句子。分析能吃到的用戶資訊只有一欄自由文字「本次補充背景」（analyze_chat_handler.ts:927）。
- 被問「你覺得呢」時不表態。she_asks_his_opinion 三輪都是反問：「我覺得先看妳自己比較在意什麼，妳現在心裡是偏哪邊？」。她把人生抉擇丟給你，正是展現判斷和價值的時刻，給出真實立場加上尊重她的決定權，才是高手。critic 還把這張卡判成 pass（critic-C.json）。
- 系統性地不推進。e2e C 臂 send 15 次裡有 6 次、c-gate 26 次裡有 11 次，在 avoidThis 或 nextStepBody 寫了先不邀約，其中包括 she_double_texts（她照他推薦去吃拉麵、還誇「你品味不錯欸」）和 she_returns_after_silence（她道歉、結案、反問他近況）。long_conversation_35 她明說「我這週末想去」，選中卡卻是「週末我也可能過去，妳打算哪一天？」，coach_hint 還寫「不要…直接敲死時間」。
- 以「球」為中心的覆蓋率邏輯，像客服在逐條回覆，不是教練思維。stream_prompt.ts:237-238 要求每張卡至少 min(3, 接球數) 段，而且故意保留「server rejects」這句不實的威嚇（stream_prompt.ts:227-230 的註解自己承認）。結果是 she_asks_personal_question 對三句輕鬆的話，每張卡都回三則訊息；long_conversation_35 的 coldRead 為了湊段數，寫出「如果猜錯了，妳再告訴我週末是怎麼安排的」這種水段。
- 五張卡硬套固定分類。she_shares_bad_day 的 tease 卡理由寫「她情緒低，只用最溫和的陪伴語氣，不調侃」，標籤和內容不符；she_returns_after_silence 的五張卡回答「你最近怎樣」幾乎一樣。五卡加上逐段理由吃掉大量輸出，並直接拉長等待時間。
- 同一次回應給兩個熱度分數，教練判讀不一致。long_conversation_35 的 metrics enthusiasm 78，done 卻是 71；she_asks_his_opinion 是 68 對 62。topicDepth 一邊寫「Personal-oriented」、一邊寫「personal」；finalRecommendation 的 reason 和 psychology 是同一句話（e2e arm-C.json clientText）。
- 開場薄的時候會寫出後設評論或腦補。thin_opening 的 resonate「哈囉，兩邊都很簡短的開場，感覺挺自在的」、humor「我們這段開場白，加起來不到五個字，效率驚人」是在評論對話本身，不是在聊天；tease「回這麼快」是沒有證據的事。
- prompt 裡留著舊式 PUA 色彩的範例（這是對 prompt 的判斷；corpus 沒有對應情境，會不會被照抄未核實）：情境1「如果說是為了性，會不會顯得我很膚淺？」（conversation_policy.ts:18）；情境2 對方抱怨回太慢時回「你觀察蠻仔細的，晚安。」（:23）；交友軟體上她要照片時回「我五官都在該在的位置上」（:68、reply_voice.ts:53）——在交友軟體上，要照片常常是她在做安全確認，閃躲會讓人以為是假帳號；她說介意抽煙時反問「好奇這會是你的第一標準嗎？」（:67）讀起來偏對抗；還有「展現雄性極性」（reply_voice.ts:73）。
- 教法自相矛盾，直接造成問句超額：70/30 聆聽（conversation_policy.ts:386）、陳述優於問句（:405）、不要只問問題（:350），對上至少一個推進動作「反問」（:337）、兩段式第二部分「延伸/提問/冷讀」（:321-323）。黑箱 question_budget 失敗次數：c-fix 9 次、c-menu 3 次（README.md）。用戶沒有素材可以分享，70/30 只會退化成「我最近還好」。

**必修**

- 加入用戶本人事實的處理（結構刀，不是加規則）。規劃階段要標出「這一步需要用戶本人的事實」，例如她問工作、照片地點、推薦。標出之後二選一：(a) 送卡前先問用戶一題快答，比照新話題「先問兩題再生成」；(b) 卡片用明確的填空，例如「我做〔你的工作，一句話〕的，」，並在 UI 上強制他填。伺服器要逐字核對：回覆裡出現的工作、地點、作品名，必須來自用戶提供的文字或記憶，否則擋下。同時禁止閃躲式回答（「晚點再說／先猜猜看」不可以拿來回直接的真問題）。
- 邀約準備度要變成模型輸出的結構化標籤（例如 not_yet / seed / soft_invite / concrete_invite，並附逐字證據句），再由伺服器用確定性規則決定要不要強制至少一張卡或選中卡帶邀約動作。不要再靠 prompt 裡互相拉扯的「不要急著邀約」和「熱度高要推進」。
- 被問「你覺得呢」或直接要意見時，選中卡必須先給立場（一句真實看法），再尊重她的決定權。把這條加進 critic 和評測器的確定性 gate，目前 critic 判它 pass。
- 拿掉每張卡至少三段的下限，也拿掉「server rejects」這句不實威嚇（stream_prompt.ts:237-238）。段數改成跟著「這一步動作需要幾則」走：她只是輕鬆問一句，就回一兩則；只有真正獨立、略過會像沒聽到的真問題，才各自成段。
- 同一次回應只能有一個熱度分數和一套階段標籤（metrics 和 done 的 enthusiasm 不一致）。done 改由伺服器從 metrics 複製，不要讓模型寫第二次。
- 清掉 prompt 裡 PUA 色彩的舊範例：情境1 的「為了性」、情境2 的「晚安」冷處理、照片要求的閃躲、「雄性極性」、抽煙的反篩。照片要求改成「大方給一張近照」或誠實說明；遇到篩選，改成誠實陳述自己的狀況，而不是反考她。

**要重新思考**

- 輸出單位從「五種風格 × 每顆球」改成教練的四件套：一個判讀（她現在在哪、她在給什麼）→ 一個動作（回／收／答／陪／約／停）→ 一句可送的話（加一個換口氣的備案）→ 一句為什麼（一條可遷移的原則）。風格改由用戶的個性設定決定口氣，不再每次生五張；這樣也直接砍掉 Bruce 說的等待時間（五卡齊 27.4s，選中卡 16.2s）。
- 教法改成一條主軸加少量情境，取代目前的技巧大雜燴。四套決策順序合成一套：安全／界線 → 她的投入度與窗口 → 他自己的錯（雙發、查戶口、過度投入）→ 下一步動作 → 用字。懸念鉤、合作框架、callback、冷讀、推拉這些技巧，應該降成寫手階段的可選修辭，不要出現在判讀層；技巧詞彙表只拿來命名，不拿來驅動。
- 比照 Opener 的結構刀，把分析拆成規劃、寫手、挑選三段：規劃產出結構化標籤（投入度、窗口、需要的用戶事實、她的問題類型：真問題／情緒球／測試／徵詢意見），伺服器套確定性政策，寫手只寫被指定的那一步。這樣 4 萬字的 prompt 可以拆開、可以各自測，Bruce 怕的回歸也能用標籤對拍來鎖住。
- 「教到用戶」要成為一級輸出，不是附屬欄位。每次分析都要判斷一次「他自己在這段對話裡犯了什麼錯」（雙發、我也差不多、查戶口、過度關心），有就放在最前面講；目前只在 long_conversation_35 這種極端案例才偶爾出現，cold_one_word_replies 就漏了。
- 可以和 Opener、新話題共用的元件：(1) Opener 規劃的片段角色裡的 sender_fact（opener_plan.ts:22-38）和新話題的兩題前置問答，共同做成「用戶事實收集」元件；(2) 新話題的 engagement 綠／黃／紅，和分析的 enthusiasm 加五維度合成同一個投入度標籤；(3) 分析的不回選單（offeredNoSendDecisions）和收尾句，三個功能都該共用，Opener 與新話題遇到她冷掉時也該能說「先別傳」；(4) 社交知識 atoms 加上 semantic_critic，當成三個功能共用的品質閘。

**證據**

- tools/analyze-v2-blackbox/out/2026-10-02-e2e/arm-C.json（rawLines 與 clientText；Sonnet 5.5＝production）：thin_opening、opening_boundary、first_message_after_match、warm_question_back、soft_reject_after_invite、defer_vague_busy、defer_with_alternative、defer_polite_reason、cold_one_word_replies、she_invites_first、after_meetup_followup、she_shares_bad_day、she_asks_personal_question、long_conversation_35、user_over_investing、she_double_texts、logistics_confirm、she_teases_him、she_returns_after_silence、boundary_friend_hint、she_asks_his_opinion、hobby_common_ground、user_waiting_after_reply 共 23 案逐案判讀
- tools/analyze-v2-blackbox/out/2026-10-02-e2e/arm-A.json：Sonnet 5 編造用戶事實，「我做業務類的」(she_asks_personal_question)、「在山上一個步道拍的」(first_message_after_match)、「最近覺得不錯的是《驅魔麗娜》」(warm_question_back)
- tools/analyze-v2-blackbox/out/2026-10-02-c-menu/arm-C.json：she_asks_personal_question #1「我是做軟體相關的」（5.5 也會編）、#2「我的工作說來話長，晚點再慢慢講給妳聽」、「先猜猜看？猜對我才告訴妳」
- tools/analyze-v2-blackbox/out/2026-10-02-c-menu-retry/arm-C.json：she_asks_his_opinion 兩輪都只反問不表態；she_returns_after_silence 第三段五張卡都是「我最近還好／沒什麼大事」
- tools/analyze-v2-blackbox/out/2026-10-02-e2e/critic-C.json：she_asks_his_opinion、long_conversation_35 判 pass；first_message_after_match 判 unsupported_fact、generic_hook；warm_question_back 判 non_actionable；she_asks_personal_question 判 goal_mismatch、ball_mismatch
- e2e arm-C.json clientText：long_conversation_35 的 metrics enthusiasm 78 對 done 71；she_asks_his_opinion 68 對 62（同一次回應兩個熱度分數）
- 我在 scratchpad 用一次性腳本統計各輪 send 決定裡 avoidThis 或 nextStepBody 寫先不邀約的次數（腳本未留在 repo）：e2e C 6/15、c-gate C 11/26、c-menu-retry C 3/8、ab A 3/29
- supabase/functions/analyze-chat/stream_prompt.ts:227-238（故意保留不實的「server rejects」威嚇與每卡至少三段的下限）、:123-131（不回決策閘）
- supabase/functions/_shared/social/conversation_policy.ts:7-13（場景判斷優先級）、:18（為了性範例）、:23（晚安冷處理）、:67-68（反篩、照片閃躲）、:143-167（十詞技巧表）、:224（盤點強制）、:306（五卡同一組球）、:321-323、:337、:350、:386、:405（問句規則互相矛盾）
- supabase/functions/_shared/social/reasoning_core.ts:5、:10（北極星與健康主動性）、:23-31（七步決策流程）、:37（富裕心態）
- supabase/functions/_shared/social/reply_voice.ts:22-25（三步使用順序）、:49-53（自證陷阱與照片範例）、:73（雄性極性）
- supabase/functions/analyze-chat/analyze_prompt/examples_legacy.ts:76（「被妳發現了，剛好在等一個人傳訊息☺️」範例）、:80-126（userDraft 優化段落混在分析 prompt 裡）
- supabase/functions/analyze-chat/analyze_prompt/report_contract.ts:32-36（冰點建議已讀不回）、:53-178（舊版 JSON 輸出格式仍整份在 prompt 裡）
- supabase/functions/analyze-chat/analyze_chat_handler.ts:920-929（用戶事實只有「本次補充背景」一欄自由文字）
- supabase/functions/analyze-chat/opener_plan.ts:22-38（Opener 的 sender_fact 等片段角色，可共用）；supabase/functions/analyze-chat/new_topic_two_stage.ts:1-60（新話題先問兩題、engagement 綠黃紅，可共用）
- tools/analyze-v2-blackbox/README.md（e2e 決定 23/23、question_budget 失敗次數、5.5 已知弱點「被問你覺得呢多半不表態」）
- /mnt/d/Obsidian個人大腦/Dev Brain/40_專案筆記/VibeSync.md:57、:59、:147（5.5 弱點、上線狀態、run14 延遲與 token 去向、客觀評分輸出品質 6/10）

## 視角：目標用戶：25–35 歲台灣男性，正在曖昧聊天，焦慮不知道怎麼回；可能是付費訂閱者，也可能是快用完額度的免費用戶。以下依程式碼走過一遍實際流程，並讀了 tools/analyze-v2-blackbox/out/2026-10-02-e2e 裡 23 案的真實輸出（A 組＝Sonnet 5，C 組＝Sonnet 5.5，C 就是目前開著開關後的線上路徑）。秒數都是黑箱直打伺服器量到的串流里程碑，不含截圖辨識（OCR）和 App 端的額外時間（這兩段未核實）。

用戶實際旅程（C 組）：選 1–3 張截圖，按「辨識」，等 OCR（秒數未核實）。跳出確認視窗，必須先勾「我確認這些截圖都是目前這位對象」才能繼續（screenshot_recognition_dialog.dart:354、1245）。接著按浮動的「開始分析」，再跳一個額度確認框「本次將使用 N 則」（analysis_screen.dart:2200、analysis_preview_dialog.dart:57–61），按「確認使用 N 則」之後才真正開始。
- 約 3.0 秒：一張紫色卡「完整分析即時整理中」出現第一格「下一步策略＋建議＋避免」。
- 約 7.9 秒：第一張回覆以純文字格子出現，這時還不能複製。
- 約 14.7 秒：五張回覆都出齊。
- 約 18.3 秒（中位數，最長 28.7 秒）：串流卡消失，整頁換成正式版面並自動捲到回覆區，這時才第一次能複製（analysis_screen.dart:2816–2840、4223）。
- 不回的情境（先別回／先收尾）約 7.5 秒就完成。
- 舊的 Sonnet 5 路徑：能複製要等 34.7 秒，最長 40.9 秒。

**價值判斷**：有真實價值，而且核心判斷是對的。對一個焦慮的男生來說，最值錢的有三件：一句「這輪該不該回」、一句可以直接貼的回覆，以及看得到 AI 接的是她哪一句。

這三件在 C 組的真實輸出裡大多做到了。不回／收尾的判斷 8 案全部符合預期：她說有男友、「下次再看看」、她只回一兩個字、他已經連發三則關心，都被正確擋下，收尾句也自然，例如「沒問題，妳先忙，有空再說」。很多 App 只會叫用戶繼續發，這一點是明顯的差異化，也真的保護了用戶。

需要回的 15 案，我自己逐案判斷「他會不會原封不動送出」，大約 11 案可以直接送：約時間、她邀他看演唱會、她分享壞事、她吐槽他、見面後的跟進都寫得自然，是台灣口語。另有 3 案送不出去、1 案半可用。系統內建的評審（critic）結果也一致：C 組 12 通過、3 案判需改寫。

失敗有一個共同結構：她問的是只有用戶本人知道的事，模型不知道，就閃躲或延後。
- 她問照片在哪拍，回覆寫「那張是我自己拍的那個地方」。
- 她問他做什麼工作，五張卡全部寫「晚點正經回妳」或「先留個懸念」。
- 她要他推薦電影，回覆完全沒給片名，反過來問她口味，但同一輪的策略格寫著「給一個具體推薦」，自相矛盾。
- 長對話裡回覆替他編了「週末我也可能過去」。

根因已核實：analyze 完全不收用戶自己的資料。effective_style_prompt_builder.dart:9–25 寫明 2026-08-04 起「關於我」不再影響分析，buildForAnalysis 固定回傳 null。

所以這個功能的價值是真的，但目前大約每 4 次需要回覆的分析，就有 1 次給出他送不出去的句子。而這正是用戶最焦慮的時刻：她直接問他問題的時候。

**能否做到市場最好**：可以拿下「繁中曖昧聊天下一步」這個利基的第一名，但不是靠五種風格或更長的報告。能贏的方向是：判斷準、句子可以直接送、時間短、敢說「先別回」。

這幾項目前已經接近：繁中口語自然、引用她的原句、先別回／先收尾的判斷，這些是一般通用回覆產生器做不到的。差距在四個地方：
1. 遇到需要用戶本人資料的問題，句子就送不出去。
2. 從截圖到能複製要經過 4 個確認動作，再等約 18 秒以上。
3. 結果頁太吵：同一句推薦出現兩次，還有一堆指標和術語。
4. 免費額度幾乎無法讓人養成習慣。

要成為市場最好，結構上要這樣改：
- 先 3 秒給判斷。
- 如果她問了用戶自己的事，先問用戶一題（直接重用新話題「先問兩題再生成」的模式），再生成回覆。
- 預設只給一張推薦卡，另外最多兩種語氣讓他點了才看。
- 第一張卡出現就能複製。

以上是意見。市場競品的比較我沒有查，未核實。

| 面向 | 分數 | 理由 |
|---|---|---|
| 核心判斷價值（該不該回、下一步） | 8 | C 組不回／收尾 8/8 判對，先收尾卡附可複製的收尾句，先別回卡附『我還是想回』後的最低壓力句（analysis_banners_section.dart:197–245）；送出案的策略格也短而具體。 |
| 原封不動可送出率 | 6 | 需要回覆的 15 案中，我判斷約 11 案可直接送；評審（critic-C.json）12/15 通過。失敗集中在她問用戶本人的事：照片地點、工作、推薦電影；用戶資料沒有進 prompt（effective_style_prompt_builder.dart:19–25）。 |
| 等待體驗 | 5 | Sonnet 5.5：決策約 3 秒、第一張卡約 7.9 秒，但要到 done 約 18.3 秒（最長 28.7 秒）才能複製；串流中的回覆只是純文字格子（streaming_content_section.dart、analysis_screen.dart:2816）。再加上 OCR 和 4 個確認動作；也沒有分析完成通知（lib/features/analysis 裡找不到相關程式）。Sonnet 5 時只有 3 分。 |
| 結果頁清晰度／認知負擔 | 4 | done 之後一頁堆了這些：教練行動卡（裡面『試試這樣回』就是推薦句）、AI 推薦回覆卡（同一句再出現一次，coach_action_policy.dart:446–453）、說明文字『推薦訊息素材…哪顆球』、五風格輪播、用量行、問教練、詳細分析、潤飾草稿、提醒、意見回饋（analysis_screen.dart:4113–4285）。 |
| 信任訊號（它有沒有看懂她） | 6 | 每段回覆附上她的原句是很強的信任訊號（reply_zone_section.dart:617–620）。但其他地方在扣分：串流顯示的投入分數和最終分數不同（68→62），策略格跟推薦句自相矛盾（warm_question_back 案），『她話裡的意思』在 20/23 案的最終結果裡是空字串（下方 mustFix 詳述）。 |
| 用語與術語 | 5 | 風格標籤『冷讀』『調情』是把妹術語，『互動測試訊號』、『本次投入 62/90』（分母 90，app_constants.dart:17）、『推薦訊息素材』『哪顆球』、串流標籤和卡片標籤不一致（『延伸話題／輕鬆挑逗』對上『延展／調情』）。 |
| 免費到付費的價值感 | 4 | 免費版每月 30、每日 15 則（quota.ts:18–28），但 1『則』其實是 40 個字，一張截圖約 400 字就扣 10 則（billing.ts:9–13）。等於每月只有 3–8 次分析；確認框文案『依對話複雜度 1–10 則』跟實際按字數計算不符（analysis_preview_dialog.dart:61）；先別回照樣扣額度。 |
| 整體（用戶視角） | 6 | 判斷和大多數句子達到可以付費的水準，但等待、雜訊、需要用戶資料的題目送不出去、額度單位難懂這四點，會讓用戶用兩三次就流失。 |

**強項**

- 敢說『先別回』：連續冷回、他過度投入、她有男友、模糊延後等 8 案判斷全對，理由寫成白話（例：『再接話只是在替她續命』），並給出等待條件和『用新話題重新開』按鈕（analysis_banners_section.dart:197–219）。這是最有差異化、也最能建立長期信任的一塊。
- 大部分句子是自然的台灣口語，長度也像真人：『加班辛苦了，週日可以！那天晚上六點半，日式還是義式，妳挑一個？』『好，那週六三點見／十分鐘沒問題，妳慢慢來，到了跟我說』（arm-C.json 的 defer_with_alternative、logistics_confirm）。
- 情緒情境的判斷到位：她被主管當眾罵時，自動把推薦改成共鳴，避開說教和玩笑（she_shares_bad_day 案選 resonate）。
- 每段回覆附上她的原句，可以分段複製（reply_zone_section.dart:617–764）。用戶能確認 AI 接的是哪一句，這是最好的『它看懂了』訊號。
- Sonnet 5.5 的首屏速度明顯進步：決策中位數從 4.3 秒降到 3.0 秒，能複製的時間從 34.7 秒降到 18.3 秒（2026-10-02-e2e，依 arm-A.json 與 arm-C.json 計算）。
- 防呆做得多：額度不足時顯示升級卡而不是報錯（analysis_screen.dart:4238）、內容過長先擋（2190 行附近）、截圖混到別人會警告、需要補資料（need_context）每天前 3 次免扣（docs/decisions.md:1205）。

**弱點**

- 她問的是用戶本人的事時，回覆一律閃躲或寫成占位句。arm-C 實例：『那張是我自己拍的那個地方』、五張卡都『工作這題我晚點正經回妳』、她要推薦電影卻沒給片名。原因是 analyze 不收用戶資料（effective_style_prompt_builder.dart:9–25）。在需要回覆的 15 案裡，約 5–6 案牽涉用戶本人的事實。
- 要到 done 才能複製。串流中的五張卡只是紫色卡裡的唯讀文字，每張還帶『思路／對應』最多 8 行（analysis_stream_content_display.dart 的 reply_option 映射）；done 時整張卡消失、換成輪播再自動捲動（analysis_screen.dart:2828–2840），用戶正在讀的內容會跳位。
- 前置步驟太多：選圖、辨識、勾確認框、確認、開始分析、額度確認，才進入等待。焦慮時每一步都在流失用戶。
- 推薦句在同一屏出現兩次：教練行動卡的『試試這樣回』是 finalRecommendation.content（coach_action_policy.dart:446–453），下面的『AI 推薦回覆』又是同一句。教練行動卡還用 App 端自己的投入分數門檻重算一套建議（coach_action_policy.dart:310–332），跟伺服器決策（doThis/avoidThis）是兩套判斷，可能說法不一致。
- 五種風格在很多情境裡是硬湊：壞事情境的『調情』卡寫明『不調侃』，『幽默』卡寫明『不開玩笑』（she_shares_bad_day 的 reason）。免費用戶只看到延展和調情兩種（analyze_chat_handler.ts:191），偏偏在敏感情境時，第二張就是名不副實的『調情』。
- 看不懂的數字和術語：『本次投入 61/90』、串流 68 跟最終 62 不同、『冷讀』、『互動測試訊號』、話題深度標籤、『推薦訊息素材』。用戶要的是一句判斷，不是儀表板。
- 額度單位誤導：『則』聽起來是訊息數，實際是 40 字（billing.ts:9–13、CHARS_PER_MESSAGE_UNIT=40）；免費每月 30 則等於 3–8 次分析；確認框寫『依對話複雜度』，實際是看字數；『先別回』也扣額度，快用完的免費用戶會覺得花錢被叫不要回。
- 等待時沒有事可做，也沒有完成通知；他多半會切回 LINE 自己打字，回來時結果可能已經過時（App 退到背景後串流會不會中斷：未核實）。
- 驗證深度不足：vault 記錄寫『沒心力 dogfood…無真實使用者』，輸出品質自評 6/10（Dev Brain 40_專案筆記/VibeSync.md:147）。上面所有的品質判斷都來自 23 案人造語料。

**必修**

- 她問到用戶本人的事時不能交出送不出去的句子。最小可行做法：模型輸出一個結構化標籤，表示『這題需要用戶的事實』（例如 needsUserFact: 工作／地點／推薦），App 在該句留一個可填的空格或先問一題，伺服器只依標籤決定流程，不靠加 prompt 規則。這屬於改變模型的輸入，符合結構刀原則；選擇性帶入『關於我』的事實欄位也可以，但要 Eric 重新拍板 2026-08-04 的決定。
- 推薦回覆一出現就要能複製。目前 analysis.recommendation 事件已經在第一張卡的時間點送達（arm-C 約 7.9 秒），App 卻要等 done 才填 _finalRecommendation（analysis_screen.dart:2816–2830）。應該把推薦預覽（recommendationPreview，notifier 已經收到，見 streaming_analyze_notifier.dart:445–451）直接渲染成可複製的正式卡，不再等 done、也不要整頁換版面。
- 刪掉同屏重複的推薦句：教練行動卡不要再顯示 suggestedLine，或改成只顯示一句教練說明；App 端用投入分數重算的那套建議，應改用伺服器的決策欄位，避免兩套說法打架（coach_action_policy.dart:310–332、446–453）。
- 修正伺服器組裝最終結果時丟掉 psychology 的問題：absorbMetrics 只吸收 enthusiasm、dimensions、topicDepth、gameStage，沒有 psychology（reframer.ts:1398–1433），所以 C 組 23 案裡 20 案最終結果 psychology.subtext 是空字串（模型其實在 metrics 裡寫了，例如『她主動追問你的喜好並請你推薦，有投入訊號』）。『她話裡的意思』卡只要 psychology 不是 null 就會渲染（detailed_analysis_section.dart:238–256），很可能顯示空白內容（手機上未核實）。
- 改掉『則』這個額度單位的文案：確認框『依對話複雜度 1–10 則』跟實際算法不符（analysis_preview_dialog.dart:61），應改成『約 N 字，這次用掉 X 點』之類的誠實說法。免費額度能不能讓人在 7 天內至少用 5 次形成習慣，交給 Eric 決定（quota.ts:18–28）。
- 策略格不能跟推薦句矛盾：warm_question_back 案的策略格寫『給一個具體推薦』，推薦句卻沒有推薦（arm-C.json）。這是用戶看得到的自相矛盾，可以用 doThis 跟所選卡的結構化標籤（rhetoricalMove 或 needsUserFact）做一致性檢查，而不是加 prompt 規則。

**要重新思考**

- 把『五張風格卡』改成『一張推薦卡＋點了才看的換語氣』：預設只顯示推薦，另外最多兩種跟情境相符的替代語氣；不適用的風格（壞事情境的調情或幽默）不要生成。這同時處理等待（五卡齊比首卡多約 7 秒，C 組 14.7 對 7.9 秒）、輸出成本（五卡約佔輸出 35%）、雜訊和名不副實的卡。免費版也就不必用『只給兩種風格』來區隔。
- 結果頁重排成三層：第一層是一句判斷加一句可複製的回覆；第二層是附上她原句的理由，點開才看；第三層把投入分數、雷達、階段、對話健檢全收進『詳細』。目前 done 後首屏有 6–8 個元件在搶注意力（analysis_screen.dart:4113–4285）。
- 跟新話題、開場救星共用『先問再生成』元件：新話題已經有先問兩題的流程（new_topic_two_stage.ts）。分析遇到需要用戶事實時，也走同一個先問一題的元件；開場救星的 plan / write / pick 拆法（opener_plan.ts、opener_plan_write.ts、opener_pick.ts），可以套在『判斷→寫一張→其他語氣點了才寫』。
- 縮短前置流程：辨識確認時預設勾選『是同一位對象』，只有名字比對不一致才要求手動勾選；額度確認框在額度充足、低於 10 點時改成不打斷的一行提示；辨識完成直接開始分析。從截圖到能複製，目標是 2 個動作。
- 重新定義付費價值：用戶願意付費，是因為『她回了我知道怎麼辦』這件事每天都會發生。免費額度的設計（每月 30 個 40 字單位）在養成習慣之前就把他擋掉了。『先別回』要不要扣額度，也應該從用戶信任的角度重新評估，交給 Eric 決定。
- 拿掉把妹術語：『冷讀』、『調情』、『互動測試訊號』改成用戶聽得懂的語氣名，例如『猜猜她』『鬧她一下』；『本次投入 X/90』改成文字判斷，或乾脆不顯示數字。
- 等待期間要有事可做或能離開：先 3 秒給判斷，並說『推薦句 10 秒內出來』；退到背景時完成要推播通知，並重用 follow_up_notification 現有的本機通知元件（lib/features/follow_up_notification/data/local_notification_gateway.dart）。

**證據**

- tools/analyze-v2-blackbox/out/2026-10-02-e2e/arm-C.json（23 案真實輸出；送出案中位數：決策 3.0 秒、第一張卡 7.9 秒、五卡齊 14.7 秒、done 18.3 秒，最長 28.7 秒；不回案 done 7.5 秒）
- tools/analyze-v2-blackbox/out/2026-10-02-e2e/arm-A.json（Sonnet 5：決策 4.3 秒、第一張卡 12.5 秒、done 34.7 秒，最長 40.9 秒）
- tools/analyze-v2-blackbox/out/2026-10-02-e2e/critic-C.json（12 通過、3 需改寫：first_message_after_match、warm_question_back、she_asks_personal_question）；critic-A.json（14 通過、1 需改寫）
- tools/analyze-v2-blackbox/out/2026-10-02-e2e/summary.md（C 組 p50 16.6 秒、p95 20.9 秒；evaluate 22/23）
- lib/features/user_profile/domain/services/effective_style_prompt_builder.dart:9-25（analyze 不收『關於我』，buildForAnalysis 回傳 null）
- lib/features/analysis/presentation/screens/analysis_screen.dart:2741-2840（串流中只更新 streamContents；_replies 和 _finalRecommendation 只在 done 時設定；done 後才自動捲到回覆區）
- lib/features/analysis/presentation/screens/analysis_screen.dart:4051-4285（done 後的版面堆疊：決策卡、教練行動卡、回覆區、用量行、問教練、詳細分析、串流卡、額度卡、潤飾草稿、提醒、意見回饋）
- lib/features/analysis/presentation/sections/streaming_content_section.dart:28-190（串流卡是唯讀文字、最多 8 行）
- lib/features/analysis/presentation/helpers/analysis_stream_content_display.dart:60-150（reply_option 格子顯示句子＋思路＋對應；coach_hint 讀 event['coachActionHint']，但這個欄位在事件頂層不存在，所以格子被濾掉，見 analyze_stream_client.dart:385）
- lib/features/analysis/domain/coach/coach_action_policy.dart:310-332、446-453（App 端用投入分數門檻重算建議；suggestedLine 就是 finalRecommendation.content，造成同屏重複）
- supabase/functions/analyze-chat/reframer.ts:1243-1245、1398-1433（psychology 預設是空字串；absorbMetrics 不吸收 psychology）；arm-C 有 20/23 案 done.finalResult.psychology.subtext 是空字串
- lib/features/analysis/presentation/sections/detailed_analysis_section.dart:238-256（psychology 不是 null 就渲染『她話裡的意思』卡）
- lib/features/analysis/presentation/sections/analysis_banners_section.dart:115-300（不回／收尾卡、『我還是想回』、用新話題重新開）
- lib/features/analysis/domain/entities/analysis_models.dart:906-922（收尾句和最低壓力句的語意；非送出時隱藏回覆區）
- lib/features/analysis/presentation/sections/reply_zone_section.dart:309、617-620（免費只開兩種風格的升級文案；『推薦訊息素材…哪顆球』）
- lib/features/analysis/presentation/widgets/reply_style_card.dart:32-45（風格標籤：延展、共鳴、調情、幽默、冷讀）
- supabase/functions/analyze-chat/analyze_chat_handler.ts:191（免費版只有 extend 和 tease）
- supabase/functions/_shared/quota.ts:18-28（免費每月 30、每日 15）；supabase/functions/analyze-chat/billing.ts:9-13、29-33（1 則＝40 字，401–2000 字固定 10 則）
- lib/shared/widgets/analysis_preview_dialog.dart:49-139（『依對話複雜度 1–10 則』、『確認使用 N 則』）
- lib/features/analysis/presentation/widgets/screenshot_recognition_dialog.dart:354、1245（必須勾確認框才能繼續）
- lib/core/constants/app_constants.dart:17（investmentVisibleMax = 90）
- docs/decisions.md:1205-1208（需要補資料時每天前 3 次免扣；先別回照樣扣）
- /mnt/d/Obsidian個人大腦/Dev Brain/40_專案筆記/VibeSync.md:147（沒有 dogfood、沒有真實使用者、輸出品質 6/10、run14 延遲、只有約 10% 輸出能無感砍掉）
- supabase/functions/analyze-chat/new_topic_two_stage.ts:1-20（新話題先問兩題再生成，可共用的元件）

## 三套結構刀方案

### 讀判 → 伺服器政策 → 寫卡 → 送出即定稿（品質優先的分析結構刀）

**主張**：分析的「判斷」已經達到教練等級：5.5 端到端 23/23 決定正確，不回情境 8/8 判對（docs/decisions.md ADR #49）。失敗集中在三處：寫卡時拿不到該有的輸入（用戶本人事實、帶編號的逐字稿）；伺服器在「判斷」和「寫句子」之間沒有插手的時間點，只能事後記 log 或靠一句不實的威嚇（stream_prompt.ts:224-238）；卡片送出後，在 done 時又被改寫（reframer.ts:1473-1490、analyze_stream_handler.ts:665-699）。

結構刀的做法有四件。第一，把現在一次 48,842 字元的大呼叫切成「讀判」和「寫卡」兩段：讀判只輸出結構化標籤；伺服器用固定規則把標籤算成一份 WritePlan；寫卡只看 WritePlan 加上帶 id 的逐字稿。第二，卡片在送出前做一次確定性檢查，送出的卡就是最終的卡。第三，App 改成卡片一到就能用。第四，最後刪掉舊底座、v2 補丁、發散計畫和舊報告契約。

順序上，先補 CI、零成本重播測試和雜訊帶，再刪假擋、做「送出即定稿」和 App 逐件顯示。這幾步不動 prompt，卻能直接回應 Bruce 說的「等有點久」和「怕 regression」。兩段式先以離線臂量過，再藏在旗標後接上，量到不比現在差才翻開。共用的是開場救星已經驗證過的模式（伺服器給選單、模型選 enum、規劃與寫手分開、送出前否決、寫手不放示範句），不共用它的伺服器挑卡。

**目標架構**：一、新模組：supabase/functions/analyze-chat/analyze/（只給 Analyze 用）
- user_turn.ts：compileAnalyzeUserTurn(input) → { text, messages:[{id:"m1",side,text}], fragmentIds }。
  - 每則訊息一個穩定 id（`[m7] 她: …`）。片段只定義一次，prompt 標記、球清單、驗證共用同一個定義。內容會逸出（換行、以 ## 開頭的訊息）。缺值的情境欄位直接省略。
  - 取代 analyze_chat_handler.ts:930-993 和 1424-1480 的臨時組裝。tools/analyze-v2-blackbox/run_blackbox.ts 也改 import 這個函式，所以黑箱測到的就是生產環境的輸入。
- read_contract.ts：讀判的事件 enum 和 parser，全部從 TS 常數產生（沿用 divergence_contract.ts 加 stream_prompt_test.ts:450-630 的對拍作法）。
  - inventory{balls:[{id, disposition 接/併/略}]}
  - decision{messageDecision, action, selectedStyle, reason, stopCondition, closingMessage, nextStepTitle/Body, doThis, avoidThis, confidence, expectedReaction, herQuestionType(real_question|emotional_bid|test|asks_opinion|none), inviteReadiness(not_yet|seed|soft_invite|concrete_invite)+inviteEvidenceIds, selfFactNeeded[(work|place|recommendation|plan|experience)], riskFlag(none|coercion|harassment|minor|impaired)}
  - metrics{enthusiasm, dimensions, topicDepth, gameStage, psychology}，以及 coach_hint
- read_prompt.ts：讀判的 system prompt，分兩塊。
  - 凍結塊帶 cache_control，內容是角色、input contract、單一一套衝突順序（安全 > 證據 > 投入 > 階段 > 選球），以及由常數產生的 schema。
  - 每次請求不同的塊不帶 cache_control，放知識 atoms（knowledge_selector）和不回選單。
  - 零可抄的示範句。估計約 6–8K 字元（未核實，以 count_tokens 驗證）。
- card_policy.ts：純函式 deriveWritePlan(readEvents, serverSignals, tier) → WritePlan{anchorIds, supportIds, action, questionBudget, move(none|invite_soft|invite_concrete|stance_first), unknownSelfFacts[], styles(選中的排第一), readSummary(reason, doThis)}。
  - offeredNoSendDecisions（no_send_decision.ts:63-75）搬進同一張政策表，成為其中一欄。
  - riskFlag 不是 none 時，強制走不回決策。
  - stretchLevel 一律預設 within。
- write_prompt.ts：寫卡的 system prompt，只有一段 VOICE 加上由常數產生的卡片 schema（segments:[{sourceId, reply, reason}]，加上 slots），不放示範句（opener_flow_prompt.ts:1-3 的教訓）。user turn 是帶 id 的逐字稿加 WritePlan JSON。估計約 4–5K 字元（未核實）。
- emit_card.ts：送出前的確定性步驟。
  - 轉換：normalizeOutgoingMessageText（outgoing_message_text.ts）、外文剝除（從 done 時移到送出前）、依 sourceId 逐字填入 sourceIndex 和 sourceMessage。
  - 否決（只放能逐字判斷的）：hasAnalyzeChatPromptLeak（prompt_leak.ts）、sourceId 不在 plan 裡、questionCount 超過 questionBudget、未知的本人事實缺少填空標記。
  - 選中卡被否決時，比照開場救星，做一次只針對那張卡的定點改寫（坑 retry-same-prompt-cannot-fix-compliance：同一份 prompt 重試修不好）。時間不夠就照原樣送出並記錄，絕不讓整個分析失敗（reframer.ts:668-690 的 2026-06-13 教訓）。
- read_write_flow.ts：編排器，以 opener_plan_write.ts 為範本。
  - 讀判串流一解析到 decision 行就算出 WritePlan。
  - 不回決策：只有一次呼叫，直接結束。
  - 送出決策：立刻開始寫卡呼叫；讀判呼叫同時繼續輸出 metrics 和 coach_hint。
  - 兩條串流各自緩衝成完整的行，再合流餵給同一個 reframer。
  - analysis.done 由伺服器自己補上，忽略模型的 done。
  - 接上 ModelCallBudget，上限改成跟著備援鏈長度（model_call_budget.ts:31-73 現在寫死 3）。

二、共用層 _shared/
- 新增 _shared/text_metrics.ts：questionCount 從 opener_pick.ts 搬來（連續問號算一個），另外放 findQuote（opener_plan.ts:189）、graphemeLength（opener_stage.ts:39）、compactForMatch。opener_pick 和 emit_card 共用。
- 維持在 _shared/social 的只有 semantic_critic、knowledge_selector、knowledge_registry（Coach 也在用）。reasoning_core、conversation_policy、reply_voice 只有 Analyze 用，內容併進 read 和 write prompt 後就刪除（F42）。

三、模型呼叫
- 不回決策：一次呼叫，只做讀判，prompt 比現在小。
- 送出決策：兩次呼叫，讀判的尾段和寫卡同時進行。
- 已扣費後重試：只重跑寫卡，用扣費時存進 recommendation_json 的 WritePlan。recommendation_json 是 JSONB 物件，RPC 只檢查特定鍵（supabase/migrations/20260902120000_analysis_stream_runs_decision_kind.sql:127-148），所以預期不需要 migration（要以 postgres 測試核實）。
- 主模型和備援鏈不變（5.5 → Sonnet 5 → 4.6 → Haiku，streaming_fallback.ts）。

四、事件與 App 介面（wire 形狀維持不變）
- 事件依序：analysis.inventory → analysis.decision（扣費錨點不變，reframer.ts:868-881 validateDecisionChargeEvent）→ analysis.metrics（含 psychology）→ analysis.coach_hint → analysis.recommendation（thin 版，由讀判提供）→ analysis.reply_option（伺服器填好 sourceIndex 和 sourceMessage）→ analysis.done（伺服器從已送出的內容組成）。
- 內部標籤在轉發前剝掉。analysis.divergence_plan 消失，App 從來沒讀過它（lib/ grep 為 0）。
- reframer 仍然是唯一的事件消費者和扣費點，exactly-once 的帳本不動。

五、刪除後的樣子
- stream_prompt.ts 的 v2 補丁和不實威嚇句、DIVERGENCE_* 段落、divergence_contract.ts 的計畫解析、analyze_prompt/report_contract.ts、examples_legacy.ts、system_prompt.ts 的串流組合。
- post_process.ts:558-639 的模糊修補，以及依位置裁段的邏輯。
- reframer 的同義表和 legacy 鍵容錯。
- guardrails.ts 的 checkInput，以及串流路徑上的 BLOCKED 罐頭替換。
- stream_recommendation_guardrail.ts 的英文正規式清單。
- phase0_observability.ts 的 runtime 部分（改成離線計算）。

| 階段 | 目標 | 刪什麼 | 用戶看到 | 防退步 | 風險 | 可單獨退回 |
|---|---|---|---|---|---|---|
| P0 讓 CI 真的守住 analyze-chat | Bruce 改任何一行，PR 和部署前都會跑整個 analyze-chat 與 _shared/social 的測試。 | flutter-ci.yml 裡 analyze-chat 的逐檔清單（:64-74）。 | 用戶看不到變化。Bruce 和 Eric 得到「改壞了 CI 會紅」的保證。 | - 本機用 --deny-net 跑全套 1,249–1,274 個測試已經全綠（audit F21 的 scratchpad/alltests.log）。 - PR 上跑一次新步驟，必須是綠的。 - 在 PR 分支故意改壞一個 reframer 斷言，確認 CI 會轉紅，確認後還原。 | R2：改 workflow 屬於 R2，需要 Eric 對這個範圍明確授權，並經主審。CI 約多 75 秒（F21 估計）。部署前多一道測試，測試紅時部署會被擋，這正是目的。 | 是 |
| P1 零成本重播測試、語意錨點、雜訊帶 | 建一張判斷「行為有沒有變」的網，取代逐字鎖住 prompt 原文的測試，之後每一刀都靠它證明沒有回歸。 | index_test.ts 的 prompt 原文鏡像斷言，每一條都要先有對應的語意錨點才能刪。 | 用戶看不到變化。改 prompt 時不再「一碰就一片紅」，真正的行為退步反而會紅。 | - golden 先在沒改任何程式碼的 main 上自己比對，必須是綠的。 - 故意注入三種回歸（absorbMetrics 少吸一個欄位、扣費呼叫兩次、no-send 漏出卡片），replay 必須轉紅。 - 每條被刪的鏡像都列一張對照表，寫出由哪個錨點接手，審查者逐條核對。 | R2：錨點寫得太鬆會漏掉真的回歸（坑 regression-lock-compares-new-code-to-itself），所以 golden 一律從舊 commit 產生，不從新程式碼產生。這一步只改測試，但它替換的是安全網，所以當 R2 處理。 | 是 |
| P2 刪掉擋錯人的閘門和 App 走不到的路徑 | 移除會擋下正常對話的關鍵字閘門，以及現行 App 從來不送的請求形狀，讓串流成為 SYSTEM_PROMPT 唯一的使用者。 | guardrails.ts 的 checkInput，my_message_flow.ts（43 行），my_message_prompt.ts（67 行），model_selection.ts（45 行），stream_gate.ts 的 whitelist 部分，analysis_error_widget.dart，以及 handler 裡對應的分支（F32）。 | 像「我上週拒絕了那個 offer／但我還是想去日本玩」、「她不願意吃辣，晚餐怎麼辦」這類對話，不再被擋成「這次送出的對話內容有誤」，重試也不再永遠失敗。 | - replay golden 位元組完全相同，因為主串流路徑沒動。 - F01 的四句重現句改成 handler 行為測試，斷言不再回 400。 - request_shape 測試改成斷言 410。 - P0 的 CI 全綠。 - 這一步不動 prompt，所以不需要付費黑箱。 | R2：這是拿掉一道意圖閘門，屬於安全相關的 R2。拒絕和界線改由模型的 acknowledge_and_stop 和 do_not_send 處理（e2e 不回案 8/8 判對）；P6 之後再加上 riskFlag 結構化標籤。刪除前可以先請 Eric 授權唯讀查 ai_logs 裡 UNSAFE_INPUT 的次數，這是選做，不查也能刪。仍在送這些形狀的舊 App 會收到 410；現行 App 不送（analysis_auxiliary_client.dart:124-200）。 | 是 |
| P3 送出即定稿：串流卡就是最終卡 | 讓用戶讀到的卡片不再在 done 時被改寫或替換，也讓「她話裡的意思」和熱度只有一個來源。 | 串流路徑上的 BLOCKED_PATTERNS → SAFE_REPLIES 替換、stream_recommendation_guardrail.ts:34-137 的英文 regex、post_process.ts 依位置的 slice(0, n)、done 對已送出欄位的覆寫能力。 | 分析完成那一刻，卡片不會再被換成罐頭句或改字；「她話裡的意思」不再是空白卡（現在 20/23 案是空字串）；同一次分析只會有一個投入分數。 | - replay golden 只允許三類有說明的差異：done 和串流卡一致（以前不一致的案）、psychology 有值、你和妳的代名詞統一。審查者逐案核對 diff。 - audit 的 clobber2 和 trim 重現案改成單元測試。 - reframer_test 的 72 個、post_process_test 的 49 個都要綠。 - 不動 prompt，不需要付費黑箱。 | R2：屬於 R2，動到 Edge 輸出 schema 和安全閘門。刪掉 done 時的罐頭替換，等於少一道網，但這道網保護不了任何人，因為內容早就顯示過、也能被複製了。真正的安全判斷交給 P6 的 riskFlag。代名詞正規化寫死了「妳」（normalizePartnerPronoun），要先確認對象一定是女性，或沿用 App 已知的對象性別。 | 是 |
| P4 App 逐件到齊：卡片一到就能用 | 把串流當成結果逐件到齊，而不是預覽。不動伺服器和 prompt，就消除最大的一塊等待感。 | 沒有人讀的 recommendationPreview、4 步前奏和輪播文案的死碼（streaming_analyze_notifier.dart:213-232,595-631）、done 分支裡重複的 15 個欄位賦值（analysis_screen.dart:934-950,2812-2829）。 | 5.5 的送出案，推薦回覆在首卡約 8 秒時就能複製，今天要等 done 約 18–19 秒（c-fix 的中位數：首卡 8.5 秒、done 19.1 秒）。不回案約 3 秒就有完整的決策卡和可以複製的收尾句，今天要等 done 約 8 秒。 | - 用 P1 的共用 NDJSON fixture 跑 notifier 單元測試（send、do_not_send、acknowledge_and_stop），斷言：首卡事件之後就能複製；done 之後內容不變；續接後內容仍在；重試用完時有可以按的按鈕。 - 現有 30 個 notifier 測試和 characterization 測試要綠。 - 用 GitHub macOS runner 做 iOS build。 - Eric 真機驗收。 | R2：屬於 R2，改的是客戶端的 runtime 行為。P3 之後串流卡等於最終卡，所以提早開放複製沒有內容不一致的風險。扣費在轉發前就已完成（analyze_stream_handler.ts:591-642），所以也沒有計費風險。要等 P3 上線之後再上。 | 是 |
| P5 輸入編譯器加訊息 id：模型只引用 id | 讓模型收到一份帶編號、片段定義只有一套的逐字稿，引用改由伺服器逐字填入，同一個函式給 handler 和黑箱共用。 | post_process.ts:558-639 的模糊引用修補層；黑箱自己組 user turn 的程式碼（run_blackbox.ts:200-216 一帶）。 | 「這段在回她哪一句」不再標錯，例如爬山那段不會再被標成在回火鍋；長對話不會把中段誤標成「破冰」。 | - user_turn 的語意錨點測試：id 存在、片段標記、段落存在、「開頭 4 則加最近 30 則」的截斷，只比結構、不比措辭。 - prompt 變了，所以 replay 要從新的錄檔重新產生 golden，扣費和不回的不變式照舊。 - 付費黑箱用 ARMS C，≥3 輪，31 案。閘門：決定正確率不低於 23/23；sourceId 合法率；questionBudget 超標率不高於現在的 47/547；差距要超出雜訊帶才算數。 - 付費前先打 count_tokens 列出估價（參考：e2e 23 案每臂 US$1.680），Eric 說「跑」才跑。 | R2：屬於 R2，改的是 AI prompt 的輸入。片段定義改變可能影響球盤點，所以用黑箱球覆蓋和 sameOpeningCount 對照雜訊帶。雜湊鎖要更新：只動 user turn 的 commit 和動 system prompt 的 commit 分開。 | 是 |
| P6a 讀判／寫卡：先做離線評測臂 | 用真實模型量出「讀判 → 伺服器政策 → 寫卡」會不會比現在的單次呼叫更慢或更差，生產程式碼零改動。 | 這一步是離線的，不刪任何東西。 | 用戶看不到變化，只產出數據。 | - 生產零改動：handler 不 import 新模組，replay golden 位元組相同。 - 付費 A/B：C（現行）對 RW，各 ≥3 輪、同一組 31 案。閘門：   - 決定正確率不低於 C。   - 首卡中位數不慢於 C 的 8.5 秒。   - 球覆蓋和 sameOpeningCount 不差於 C 超過雜訊帶。   - questionBudget 超標率下降。   - Codex 跨家族盲評，加上 Eric 或 Bruce 標 20 張「會不會原封送出」，結果不輸 C。 - 先打 count_tokens 列估價，Eric 說「跑」才跑。 | R2：屬於 R2：付費評測、prompt 重寫，但不碰生產。最大的未知是 5.5 第二次呼叫的首字時間，因為有自適應思考，未核實。如果延遲閘沒過，退路是保留單次呼叫，只把去重後的 prompt 和伺服器算的 questionBudget 移植進 stream_prompt.ts，並刪掉發散計畫。這個退路本身也要過同一組閘門。 | 是 |
| P6b 讀判／寫卡接上 handler（旗標後） | 在 ANALYZE_READ_WRITE 旗標後面接上兩段式。旗標關時逐位元組不變；旗標開時，扣費、重試、不回的語意都不退步。 | 旗標開時不再送發散計畫那一步。舊程式碼保留到 P9 才刪。 | 旗標關時沒有變化。旗標開時就是 P6a 量到的結果，而且重試不會再整份重生成，選中的卡和策略會保持不變。 | - 旗標 unset、false、亂填時，replay 四面 digest 和 P5 的 golden 逐位元組相同（坑 four-facet）。 - 旗標 true 時，用 P6a 錄下的 read 和 write rawLines 重播，斷言：只扣費一次；不回時只有一次呼叫；寫卡失敗後已扣費的 run 能 retry 且不重扣；不回時零張卡；合流不會切斷半行。 - reframer_test、no_send_stream_test、analyze_stream_handler_test 全綠。 - 主審由 Codex（OpenAI 家族）擔任。 | R3：屬於 R3，因為改的是付費生產路徑的呼叫結構和重試語意。兩次呼叫代表多一個失敗點：扣費後寫卡失敗，用戶只拿到決定。用「只重跑寫卡的 retry」緩解，這比今天用同一份 prompt 整份重跑更穩。設定 secret 和翻旗標都要 Eric 對每個動作分別核准。存 WritePlan 預期不需要 migration，但要用 postgres 測試確認 charge RPC 會保留額外的鍵。 | 是 |
| P7 本人事實：填空，不編造 | 她問到他的工作、地點、推薦時，卡片給一個要他填的空格，而不是替他編一個答案。 | reasoning_core.ts:15 那條「不可替使用者捏造經驗」的散文規則已被結構取代；P6a 的 read 和 write prompt 不再帶它。 | 她問「你做什麼工作？」，卡片會寫「我做［你的工作］的，妳呢？」，他填一下就能送，不會再出現「我做業務類的」這種他從沒說過的話。 | - 單元測試：emit_card 的標記檢查，以及 card_policy 的映射表。 - replay：她問本人事實的錄檔，產出的卡片要帶標記。 - 付費黑箱 RW 臂 ≥3 輪：she_asks_personal_question 和 first_message_after_match 兩案的 unsupported_fact 要是 0；其他案不能濫用標記（標記只能出現在 selfFactNeeded 的案）；結果要超出雜訊帶才算數。 - Flutter widget 測試：填好 chip 後，複製出來的文字正確。 | R2：屬於 R2。標記如果被濫用，卡片會變成填表，所以黑箱要量標記出現率。舊 App 會直接顯示「［你的工作］」這幾個字，目前只有 Eric 和 Bruce 在用。這一步要等 Eric 拍板決定 1。 | 是 |
| P8 邀約時機與表態，變成政策而不是規則句 | 她打開窗口時，推薦卡會推進邀約；她問「你覺得呢」時，先給立場再尊重她的決定。 | report_contract.ts:22,156 會被逐字照抄的「不要連問清單題，也不要急著跳邀約」範例（P6a 的 prompt 已經不帶）。 | 她說「我這週末想去」時，推薦卡會直接約時間；她問「你覺得呢？」時，卡片先講他的看法，再把決定權交還給她。 | - card_policy 的單元表。 - 付費黑箱 ≥3 輪：邀約窗口案的選中卡要帶邀約；「你覺得呢」案的首段要有立場，用跨家族盲評加人工標註判斷；非窗口案不能被硬推邀約（量假陽性率）；差距要超出雜訊帶。 - 動手前先用現有黑箱輸出做一次人工標註，確認問題有多大，因為 F29 是 Sydney 視角提出、沒有經過對抗驗證的發現。 | R2：屬於 R2。邀約推得太猛會有反效果，所以設了假陽性閘門。「表態」本身沒辦法逐字判斷，只能靠輸入結構加上離線評審，伺服器不做語意檢查。 | 是 |
| P9 翻旗標，刪掉單體 prompt 和舊契約 | 確認兩段式已經是唯一的路徑後，刪掉舊底座、v2 補丁、發散計畫、舊報告契約和影子層，讓 Bruce 面對的是兩份小 prompt 加一張政策表。 | - stream_prompt.ts 的 v2 補丁、DIVERGENCE_PLAN_STEP、DIVERGENCE_REPLY_OPTION_RULE，以及不實的威嚇句（:238）。 - divergence_contract.ts 的計畫解析，以及 reframer 的歸因程式碼。 - analyze_prompt/report_contract.ts、examples_legacy.ts、system_prompt.ts 的串流組合。 - _shared/social/conversation_policy.ts（445 行）、reasoning_core.ts（95 行）、reply_voice.ts（154 行），內容已經併入 read 和 write prompt 以及 knowledge_registry。 - reframer 的同義表和 legacy 鍵容錯（:1543-1629、:635、:1345）。 - baseline_fixtures 的 v1 雜湊。 - phase0_observability.ts 的 runtime 部分。 | 沒有新的變化，行為在旗標開時就已經上線。維護者看到的分析 prompt 估計約 10–14K 字元，今天是 48,842 字元（估計未核實，以 count_tokens 驗證）。 | - RW 的 replay golden 全綠。 - 最後一輪付費黑箱，RW 和 P6a 的結果差距在雜訊帶內，證明「只刪不改」。 - Eric 真機 dogfood 一週，逐筆標註「會不會原封送出」。 - Codex 主審。 | R3：屬於 R3：刪除大量程式碼，舊 App 會被 410 擋下（目前只影響 2 位內測者）。critic 降級等於收回 Eric 2026-09-03「影子基線」的決定，需要他確認。刪除後要回滾，只能 git revert。 | 是 |

- **預期延遲**：以 Sonnet 5.5 現行生產路徑為基準，數據來自 tools/analyze-v2-blackbox/out/2026-10-02-c-fix 的送出案中位數，從模型呼叫開始算：決定 3.1 秒，首卡 8.5 秒，五卡 15.1 秒，done 19.1 秒，p95 23.3 秒。App 要等 done 才開放複製，所以用戶體感約 19 秒；不回案是決定 3.0 秒、done 8.1 秒。

1. P4（只改 App）之後：可以複製的時間會等於首卡時間，約 8 秒；不回案約 3 秒就能操作。這兩個數字是用現有的串流時間推算的，伺服器完全不用改，所以可信度最高。
2. P6（兩段式）之後，下面都是估計，未核實。
   - 寫卡呼叫在 decision 那一行出現時就開始，所以首卡約等於「決定時間」加「寫卡首字時間」加「一張卡的時間」。一張卡約 1.6 秒，是用 (15.1−8.5)/4 從實測中位數推算的。寫卡首字時間受 5.5 的自適應思考影響，目前未知，所以閘門訂為「首卡不慢於 8.5 秒」。
   - 今天決定到首卡之間約 5 秒，其中約 96% 的位元組是發散計畫（F08）。發散計畫被伺服器的 WritePlan 取代，這段可能縮短。
   - done 估計會提早，原因有三：計畫約佔輸出 15%、模型自己寫的 done 約 12% 都消失了；metrics 和 coach_hint 跟寫卡同時產生。估計 done 約 12–15 秒，未核實，以 ai_logs 的 firstCardAtMs 和 doneAtMs 驗證。
   - 不回案只剩一次比較小的讀判呼叫，預期會比現在的 8.1 秒更快。
3. Sonnet 5 備援受益最多：今天 done 約 33–35 秒（ab 和 e2e 的 arm A），首卡約 12.4 秒。
4. 如果 Eric 選「一張推薦卡加最多兩種語氣」，寫卡的輸出會再少約五分之二的卡片位元組。
5. 開始前的網路往返（RevenueCat 同步、auth、建立 run）這份提案不處理，數字仍然沒有量過（F38）。
- **預期品質**：一、現況（實測）
- 決定正確 23/23。
- 回覆約六成可以原封送出：e2e C 有 3/15 需要改寫，ab A 有 8/29。
- unsupported_fact 共 16 次，集中在兩個「她問他本人的事」的案例。
- 問句超過預算的比例約 9%（47/547）。
- 送出決策裡寫「先不邀約」：e2e C 6/15、c-gate C 11/26。
- 可送出句你、妳混用：7/220。
- 「她話裡的意思」是空字串：20/23。
- 引用標錯會發生，但生產環境的頻率未核實。

二、每一步的閘門目標
下面是要達到的閘門，不是承諾的結果。每一項都要 ≥3 輪，而且差距超出 A/A 雜訊帶才算數。
- 確定性、必然會改善的：P3 之後，代名詞混用變成 0（正規化）、done 時的卡片改寫變成 0、psychology 不再是空的、熱度只有一個值。P5 之後，引用改由伺服器逐字填入，所以不會再標錯。
- 結構性改善、要用黑箱證明的：
  - P6 由伺服器算 questionBudget 並在送出前檢查，問句超標應該明顯下降。
  - P7 讓兩個自述案的編造變成 0，改成可以填的空格，這兩案從「送不出去」變成「填一下就能送」。
  - P8 讓邀約窗口案的選中卡帶邀約，「你覺得呢」案先表態。
- 最終的「付費用戶會不會原封送出」，用 Eric 和 Bruce 的人工標註加 Codex 跨家族盲評來判，目標是不低於現在。

三、主要的品質風險
寫卡呼叫看不到完整推理，可能讓卡片和策略脫節。緩解方法是在 WritePlan 帶 readSummary（reason、doThis）和 anchor 球。P6a 的離線臂就是要先量出這一點。量不過就走退路：保留單次呼叫，只做 prompt 去重和伺服器算的預算。

四、可維護性
今天的分析 prompt 是 48,842 字元、約 105 個標題，加上 SHA 鎖的拼接和約 300 句原文鏡像測試。結構刀之後會變成兩份小 prompt（估計共 10–14K 字元，未核實）、一張可以單元測試的政策表、零成本重播測試，CI 也會跑完整目錄。這就是回答 Bruce「怕 regression、無從下手」的部分。
- **成本**：一、現況
每次分析約 US$0.073（2026-10-02-e2e/summary.md：23 案共 US$1.680）。輸入的大頭是約 39.7K token 的系統 prompt：快取寫入一次約 US$0.099，命中時讀取約 US$0.008，輸出約 US$0.028。critic 影子每次送出多約 US$0.005。

二、結構刀之後（方向估計，未核實）
- 系統 prompt 的總字數估計會從 48,842 降到約 10–14K，分成兩份。逐字稿兩次呼叫都要送一次，大約多出 1–3K token。
- 每次請求不同的知識 atoms 和選單移出快取區塊，命中率應該上升（F27）。
- 輸出少掉發散計畫（約 15%）、模型自己寫的 done（約 12%），以及每段重抄她原句的文字（約佔卡片位元組 13%）。
- 不回案只剩一次小呼叫。
- 定點改寫只在否決時才發生。
- 整體預期持平或下降，以黑箱 summary.md 的 costUsd 驗證，不採用估計值。
- critic 改成 trigger risk 之後，每次送出大約省 US$0.005。

三、一次性的評測花費
P5 到 P9 每一步都要付費黑箱，每次都要 Eric 說「跑」，付費前先用 count_tokens 列出估價。參考：e2e 每臂 23 案 US$1.680；每步 ≥3 輪，加上 RW 和 C 兩臂。整個計畫的總額估計約十多美元，未核實，每次都先報價。

四、內測流量下
30 天 Anthropic 費用約 US$10（vault VibeSync.md:52），所以單次成本的變化對總額影響很小。省錢不是這份提案的主要目的。
- **為什麼不選其他方案**：- 只做延遲優先（App 逐件到齊加刪 prompt）：這是最便宜、最有感的一步，所以我把它收成 P3 和 P4 優先做。但它修不了編造本人事實、不邀約、不表態、引用標錯。原因是判斷和寫句子在同一次呼叫裡，伺服器沒有可以插入政策的時間點，最後只能再加 prompt 規則。這違反團隊「不靠堆規則」的原則，而且坑 prompt-rule-pile-later-rules-ignored-move-to-server 已經證明，規則堆多了後面的會被忽略。

- 只做可維護性（拆 handler、補測試）：P0、P1、P2 已經涵蓋它真正有價值的部分。但只做這些，Bruce 會得到一個比較好改、品質卻一樣的模組。

- 照抄開場救星的「規劃 → 寫手 → 伺服器挑卡」：伺服器要等五張卡都到齊才能挑，首卡會延後到五卡齊的時間，約 15 秒（c-fix 中位數 15.1 秒）。而且 Analyze 的 selectedStyle 是「這一刻適合什麼語氣」的教練判斷，不是同一類候選的品質排名。所以只借它的「規劃與寫手分開」、「送出前否決加定點改寫」、「不放示範句」，不借伺服器挑卡。

- 每種風格各開一個並行的寫卡呼叫：並行呼叫會同時寫快取（ab 跑次 31 次快取寫入中，約 10 次來自並行，F27），輸入成本大約變成 5 倍，五張卡的球覆蓋也更難一致。

- 拆成多支 Edge Function：部署 workflow 會重部署所有通用函式，拆了也不會縮小影響範圍，反而讓閘門程式碼多出好幾份（F24）。

- 只刪發散計畫、保留單次呼叫：P6a 的 RW 臂本身就是比 plan-off 更完整的比較。如果 RW 沒過延遲閘門，這就是寫好的退路，而且同樣要過黑箱閘門。所以這份提案不賭結構一定贏，而是先量再決定。

### 回歸先行的勒殺式結構刀：先織網，再一片一片剝

**主張**：Bruce 怕的不是 prompt 太大，而是改了不知道有沒有壞。今天大多數 analyze-chat 測試不在 CI，部署前一個 Deno 測試都不跑；約 300 句逐字鏡像測試讓任何改寫都轉紅，真正的退步卻能過；實際送出的 v2 prompt 沒有鎖；付費黑箱沒有量過雜訊帶。所以第一刀不碰 prompt，先織四張網。第一張：CI 跑整個目錄，部署前也跑。第二張：prompt 改成可以讀 diff 的文字快照。第三張：零成本重播真實模型輸出，比對四個面：模型請求、App 收到的位元組、扣費與資料庫呼叫、log。第四張：雜訊帶加人工標註。四張網就位之後，改動只分兩種，各有各的網。改伺服器程式，由免費、確定性、每個 PR 都跑的重播網把關，prompt 快照必須不變。改 prompt，只能改在 v3 平行組合裡，由一個伺服器開關控制，看快照 diff 再過付費黑箱，而且差距要超過雜訊帶才算數。凍結的 v2 一直在 production，直到 Eric 翻開關，翻回來不用部署。整個過程 Edge 到 App 的 wire 契約維持凍結，舊版 App 一律相容，也完全不碰 migration。

**目標架構**：一、網（新增，零執行期改動）
- .github/workflows/flutter-ci.yml：analyze-chat 測試從逐檔點名改成整個目錄：`deno test --allow-env --allow-read --ignore='supabase/functions/analyze-chat/*_postgres_test.ts' supabase/functions/analyze-chat supabase/functions/_shared/social`，再加 `deno check supabase/functions/analyze-chat/index.ts`。.github/workflows/deploy-edge-function.yml 在 Deploy 前跑同一條，照 deploy-keyboard-assist.yml:35-40 的寫法。本次本機已用同一條指令加 --deny-net 實跑：1,309 passed／0 failed，耗時 1m41s。
- supabase/functions/analyze-chat/prompt_snapshot_test.ts 加 testdata/prompts/*.txt：把每一種實際渲染的 prompt 存成文字快照。包括 base、v1 五風格、v1 單 extend、v2 production（analyze_stream_handler.ts:573-578 的組合，三種不回選單）、免費兩風格、固定一組知識原子。用 UPDATE_PROMPT_SNAPSHOTS=1 重寫。這份快照取代 analyze_system_prompt_test.ts 和 baseline_contract_test.ts 的 renderedPrompts 雜湊鎖。
- supabase/functions/analyze-chat/replay_test.ts 加 testdata/replay/*.json：從 tools/analyze-v2-blackbox/out/2026-10-02-*/arm-C.json 挑約 24 筆已錄的 rawLines（四種決定都有），透過 handleAnalyzeStream 的 callModel 注入點（analyze_stream_handler.ts:193,569）吐回去，store 沿用 run_blackbox.ts:256-271 的 stub。比對四個面：模型請求、NDJSON 位元組、store 呼叫、log JSON。golden 用 git archive 從舊 commit 產生，做法照 practice-chat/agency_flag_off_equivalence_test.ts。testdata/replay/client/*.ndjson 由 Deno 和 Dart（test/unit/features/analysis/data/analyze_stream_fixture_test.dart）共讀，是 Edge 到 App 的第一份共用 wire fixture。
- tools/analyze-v2-blackbox/noise_band.ts 和 human_labels.json：用已存的多輪結果算同臂擺幅（免費），由 Bruce 標註選中卡，用來校正 critic。
- supabase/functions/analyze-chat/analyze_prompt/README.md：一張「概念 → 唯一負責段落」表，加兩條規則。一，一個概念只住一個段落。二，一個 PR 只能改 prompt 位元組（快照有 diff），或只能改伺服器程式（重播 golden 有 diff），不能兩者都改。

二、接縫（純搬移，逐位元組相同）
- supabase/functions/analyze-chat/analyze_user_turn.ts：compileAnalyzeUserTurn(input) 回傳 {text, fragment, ...}，從 analyze_chat_handler.ts:930-993 和 :1424-1480 搬出。handler 和 tools/analyze-v2-blackbox/run_blackbox.ts 都 import 它。這也是之後做訊息 id（F07）、刪雜訊摘要（F23）、省略佔位字（F49）的接縫。
- supabase/functions/analyze-chat/stream_contract.ts：事件名、欄位、enum 的唯一來源，延伸 divergence_contract.ts 的常數生成做法。prompt、reframer 解析、測試都從它產生。

三、prompt 版面（勒殺）
- analyze_prompt/legacy/：凍結的 v1 和 base SYSTEM_PROMPT，只給舊 client。舊 contract 流量接近零後刪除。
- 現行 v2（analyze_prompt.ts、stream_prompt.ts）：凍結，只有快照，不再改字。
- analyze_prompt/v3/compose.ts 加各段落檔，依序為 task（只寫一次衝突順序）、input_contract、decision、voice、output_contract（由 stream_contract.ts 產生）、shape_examples（只示範形狀、沒有可以抄的句子）。目標總長約 10–14K 字元，這是估計，要黑箱確認；現在 v2 是 48,842 字元。起點是 v3 和 v2 逐位元組相同，之後每片只改 v3。
- 唯一呼叫點 analyze_stream_handler.ts:573 依 env ANALYZE_PROMPT_V3 決定用哪一份，預設關，只認 'true'。翻開關、關開關都不用部署。

四、伺服器輸出（送出即定稿）
- reframer.ts 的 forwardReplyOption 在送出前跑 emitCard：套用與開場救星、新話題共用的 normalizeOutgoingMessageText（outgoing_message_text.ts）、hasAnalyzeChatPromptLeak 哨兵（prompt_leak.ts:27），並檢查段數上限。mergeFinalResult 改成白名單，done 不准覆寫卡片、推薦、gameStage；metrics 對分數有權威，並補吸收 psychology。
- 模型呼叫維持不變：一次串流呼叫，5.5 → Sonnet 5 → 4.6 → Haiku 備援鏈；critic 影子不變。
- 事件：App 端的 wire 不變。C2 之後 done 只當結束訊號，舊欄位由伺服器組出；C4 之後 divergence_plan 是否保留，看量測結果。

五、App
- streaming_analyze_notifier.dart 把每個事件填進一份部分結果，analysis_screen.dart 直接用最終元件渲染：選中卡一到就能複製，決定事件直接渲染 AnalysisDecisionCard。進度元件只留共用的 StreamProgressTicker（lib/shared/widgets/stream_progress_ticker.dart），skeleton 和新話題相同。

六、流程規則
- R2 階段依專案規則找一位不同家族的獨立主審。
- 付費黑箱每次都要 Eric 說「跑」。
- production 開關和 secret 每次都要 Eric 核准。
- 全案不寫 migration，絕不 supabase db push。

| 階段 | 目標 | 刪什麼 | 用戶看到 | 防退步 | 風險 | 可單獨退回 |
|---|---|---|---|---|---|---|
| N1 CI 網：整個目錄都跑，部署前也跑 | 讓 analyze-chat 和 _shared/social 的每個測試，在 PR 和直推 main 部署前都會執行；之後新增的測試檔也自動納入 | flutter-ci.yml 的 analyze-chat 逐檔清單 | 無 | 本次本機已用同一條指令加 --deny-net 實跑：1,309 passed／0 failed，1m41s。PR CI 綠才能合；在草稿分支故意弄壞一條 reframer_test，確認 CI 轉紅後丟棄 | R2：改 workflow 屬 R2，需要 Eric 對這兩個檔案的明確授權。每個 PR 多約 1.5–2 分鐘。測試紅時 Edge 不會部署，這正是目的，但緊急修正也得先修好測試或 revert | 是 |
| N2 prompt 文字快照取代 SHA 鎖 | 任何 prompt 改字都在 GitHub diff 上一行一行看得到；實際送出的 v2 prompt 第一次被鎖住 | analyze_system_prompt_test.ts；baseline_contract_test.ts 的 renderedPrompts 測試，以及 fixture 裡的 renderedPrompts 鍵（promptSlices 和 410 tombstone 保留） | 無。Bruce 改一句 prompt，review 時看到的是那一句，而不是一串雜湊 | 舊鎖 sha 等於新快照（同 commit 斷言）；靠 N1 進 CI | R1：repo 多約 6–8 份、各 40–50K 字元的文字檔。如果有人習慣性跑 UPDATE 讓測試變綠，等於自動核准，要靠 README 規則和 review 看快照 diff 擋 | 是 |
| N3 零成本重播網（四面等價＋App 共用 fixture） | 不花一毛錢，就能證明伺服器程式的改動沒改變用戶看到的內容、扣費和紀錄 | 無。docs/plans/2026-09-02-analyze-phase3-plan.md:59 那個從沒接上的「CI 跑存檔產出」，這次接上 | 無 | 這一階段本身就是網；golden 在舊 commit 產生，而且四個面全部釘住 | R1：rawLines 存的是解析後的物件，重新序列化後不等於原始位元組，所以模型吐出的怪格式要靠手做的 fixture 補。有意的行為變更需要重印 golden，但只是一條指令，不是手改 300 條斷言。錄音來自 10-02 的 prompt 版本，只能驗伺服器程式，不能驗 prompt | 是 |
| N4 量尺：雜訊帶、人工標註、三層語料 | 付費比較從此有尺：差距小於雜訊帶就算沒差；critic 的準度有人工基準可以對照 | README 裡落在雜訊內的跨臂比較結論，改標成「無差異」 | 無 | 只動 tools；evaluate_test.ts 照跑 | R1：Bruce 要花約 1 小時標註。24 張只夠看方向，不夠精確估 critic 的誤差 | 是 |
| N5 逐字鏡像測試換成語意錨點 | 改寫措辭只讓快照轉紅；真的刪掉某條規則或契約字串時，有測試會紅 | readAnalyzeChatScanCorpus 和大部分 source.includes／indexOf 鏡像。開場救星那段 index_test.ts:806-860 不擴大範圍，等開場救星下次改動時再處理 | 無。Bruce 改 prompt 時，修測試的時間從和改程式一樣多，降到一條 UPDATE 指令 | N2 快照接手措辭、N3 接手行為。驗收實驗三項：(a) 改一句 prompt，只有快照轉紅；(b) 把一條規則搬到別的檔，錨點仍綠、快照轉紅；(c) 刪掉一個事件名，契約斷言轉紅 | R1：刪太多會漏掉真正的刪除，所以這一階段一定排在 N2、N3 之後，review 要逐條對照接手清單 | 是 |
| N6 user turn 編譯器（純搬移）＋依請求形狀補語料 | 最重要的模型輸入變成一個可以測試的純函式；黑箱改送和生產環境完全相同的 user turn | analyze_chat_handler.ts:919-929 的死碼 contextInfo（在 :1427 會被覆蓋）；run_blackbox.ts 自己那份 buildUserPrompt | 無 | N3 第一面（模型請求）在 24 案逐位元組不變，加上新的單元測試 | R1：黑箱改送生產 turn 之後，和舊跑次的輸入不同，舊數字只能當參考，README 要標出分界 commit。只要任何一面出現變化，就升級為 R2 並停下來 | 是 |
| B1 生產遙測：看得到才敢改 | 用真實請求看到首卡時間、備援頻率、扣費後只拿到部分結果的情況，伺服器出錯時有警報 | stream_events.ts:23-25、critic_shadow.ts:7、analyze_stream_handler.ts:194 的過期註解 | 無 | N3 第四面（log）是有意變更，要重印 golden；第二面和第三面（用戶看到的內容、扣費）必須不變 | R1：讀這些數字仍然要 Eric 授權查 production；Sentry 只送錯誤碼，不送內容 | 是 |
| B2 刪掉壞掉的閘門 | 正常對話不再被關鍵字閘門擋成 400；不再有給人「有擋」錯覺的英文正規式 | checkInput、英文正規式清單、AnalysisErrorWidget 和它的測試 | 「她不願意吃辣，晚餐怎麼辦」「我拒絕了那個offer，但我還是想去日本玩」這類對話，可以正常分析 | N3 不變，語料沒有觸發這段。新測試：F01 的四句正常對話現在會進串流；no_send_decision 系列測試照樣全綠 | R2：拿掉一道名義上的安全閘門。它實際上會跨訊息誤判，中文的等價說法也擋不住；拒絕與界線由模型的不回決策處理（e2e 不回案 8/8 判對）。想先看 ai_logs 裡 UNSAFE_INPUT 的次數，需要 Eric 授權讀 production；預設不讀、直接刪，可以 revert | 是 |
| B3 送出即定稿：done 不再改寫看過的卡 | 用戶讀到的卡片就是最終卡片；可送出的句子和開場救星、新話題經過同一道守門 | 串流路徑上 done 時的罐頭替換；enthusiasm 50 種子；done 時的外文剝除；guardrails 重掃清單同步調整，不直接刪 | 卡片不會在「完成」那一刻被換成罐頭句或被縮短。「她話裡的意思」不再是空白（真機未核實）。熱度分數不再出現串流 68、完成 62 這種前後不一 | N3 的不變式「串流卡等於 done 卡」從 known-fail 改成必過。golden 的有意變更只限兩項：done.finalResult 補上 psychology、分數不再被 done 覆寫。Dart fixture 測試確認 App 讀的欄位都還在。audit 在 scratchpad 的 clobber／trim 重現案例改寫成正式測試 | R2：Step 3b 會改到 Eric 2026-08-17「各卡段數相同」的決定。emitCard 若擋下選中卡，就得換成下一張卡，而選中卡是扣費錨點；這一階段只做正規化、哨兵和段數上限，不做否決換卡 | 是 |
| B4 App：串流就是結果 | 推薦回覆一到就能複製，不回決定一到就看到完整的決定卡；等待畫面只保留一個誠實的進度 | streaming_content_section 重複的標頭和內文；4 步前奏和 1 秒輪播的死碼；analysis_screen.dart:934-950、2812-2829 的重複賦值 | 在 5.5 上，能複製推薦回覆的時間從 done（c-fix 中位 19.1 秒）提早到選中卡（中位 8.5 秒）；不回案在決定事件就看到決定卡（中位約 3 秒）。這些是黑箱數字，從模型呼叫開始算，不含開始前的步驟和網路 | N3 的 Dart fixture 測試加一條「done 之前已可複製」斷言。streaming_analyze_notifier_test.dart:681-726 原本鎖住「續接時清空」，改成鎖住「續接時保留」。補 widget 測試。wire 契約不變，所以新舊伺服器都相容。全套 flutter test 要過 | R2：用戶在 done 之前複製後串流才失敗：扣費在推薦轉發之前就已完成，所以不會白拿；但重試結果可能和已經看過的卡不同（F12 的長期問題）。走 TestFlight 交付，revert 需要重新出 build | 是 |
| B5 刪掉 App 不會送的請求形狀 | 非串流的 SYSTEM_PROMPT 只剩一個使用者，v1/v2/v3 才拆得乾淨 | 上面列出的檔案和分支，約幾百行 | 無。在 lib 裡 grep analyzeMode 是 0 筆，現行 App 從不送這兩種請求 | baseline_contract_test 的 tombstone 測試加兩筆；N3 不變；deno check index.ts 通過 | R2：Edge schema 變更屬 R2。如果有很舊的 App 同時送草稿和圖片，會收到「請更新 App」；目前只有 2 位內測者 | 是 |
| C0 v3 骨架：位元組相同＋單一開關 | 之後每一次 prompt 改動都只進 v3，production 在 Eric 翻開關前完全不受影響 | 無（暫時有兩份 prompt 原始碼，v2 在 C5 刪除） | 無 | 快照斷言 v3 等於 v2。N3 四個面在開關未設、off、亂填三種值下都逐位元組等於 golden，做法照 pit flag-off-zero-change-needs-four-facet-handler-harness。開關為 true 時第一面也一樣，因為 v3 等於 v2 | R1：repo 裡暫時有兩份 prompt，但 v2 已凍結、不需要維護 | 是 |
| C1 v3：只刪不加 | 拿掉死規則、重複的範例、會被逐字抄的範例句，以及帶 PUA 色彩的舊範例，一條新規則都不加 | 上述 prompt 段落；伺服器端消費 scenarioDetected 的程式 | 罐頭教練語變少，照抄次數基準是 ab C 3/21、e2e C 3/23、ab B 3/42；其他部分應該無感 | 快照 diff 全部都是刪除行，review 一眼就能確認。N3 不變，伺服器程式在另一個 PR。T2 付費檢查點：v2 對 v3 各跑 3 輪。過關條件：決定正確率不降（基準 e2e 23/23）；evaluate 通過數不低於雜訊帶下緣；Bruce 標註的「直接送」比例不降；範例句照抄次數下降 | R2：刪掉範例可能讓某類情境的輸出變形，由付費檢查點把關；每次付費跑都要 Eric 說「跑」 | 是 |
| C2 單一輸出契約（先擴再縮） | 同一份 prompt 只有一套輸出契約；done 只是結束訊號；欄位和 enum 只有一個來源 | v3 裡的第二套輸出契約；reframer 對舊鍵名的容錯（等 v2 刪除後再拿掉） | done 更早到。在 5.5 上 done 事件本身中位約 1.3 秒，Sonnet 5 備援約 6–7 秒，會縮短，但幅度未核實；5.5 上 done 約佔輸出字元 12% | (a) N3 舊錄音的四個面不變，再加一筆用 C1 檢查點錄到的 v3 輸出當新 fixture，用 Dart fixture 測試確認 App 欄位齊全。(b) T2 付費檢查點 | R2：done.finalResult 是 Edge 到 App 的契約，屬 R2。舊 App 依賴伺服器組出的舊欄位，Dart fixture 是唯一的保證 | 是 |
| C3 v3：每組矛盾和每個 enum 只留一個負責方 | 模型不必再在互相拉扯的規則之間找平衡 | 重複的優先順序清單；不一致的下一步字彙 | 低投入情境下多問問題的回覆變少（目標，未驗證） | 快照 diff；N3；T2：questionBudgetExceeded（基準 47/547，約 9%）要下降、而且降幅超過雜訊帶才算贏 | R2：這一階段牽涉語意，可能讓 5.5 的判斷位移，由付費檢查點把關，必要時拆成兩個 PR | 是 |
| C4 發散計畫：先量，再決定刪或留 | 用數據回答「佔首卡路徑最多位元組的那段文字有沒有用」 | 如果判定無效：整套發散計畫契約（divergence_contract.ts 的事件部分）和 attribution 欄位 | 如果刪掉，首卡會提早，上限約等於決定到首卡的中位差 4.96 秒（這段約 96% 位元組是計畫），實際秒數未核實，因為 5.5 有隱藏思考；輸出約少 15% | T2 付費檢查點；刪伺服器程式時，N3 fixture 裡的計畫行要能被安全忽略 | R2：計畫可能真的在撐住卡片之間的差異，所以先量，不預設要刪 | 是 |
| C5 翻開關、刪舊 | v3 上線，v2 退役，最後只剩一份 prompt | 現行 analyze_prompt.ts／stream_prompt.ts 的 v2 組合、v2 快照、ANALYZE_PROMPT_V3 開關；之後再刪 analyze_prompt/legacy/ | 和 C1–C4 累積的效果相同 | 翻開關前跑最後一次 T2 檢查點。翻開關後可以立刻關回去，不用部署，直到 v2 被刪掉為止。刪 v2 時，快照只剩 v3 | R2：改 production 設定屬 Operate，要 Eric 逐次授權。v2 一旦刪除，回退就要重新部署 | 是 |

- **預期延遲**：以黑箱為準：2026-10-02 c-fix arm C，Sonnet 5.5，送出案 n=39。從模型呼叫開始計，中位數為決定 3.1 秒、選中卡 8.5 秒、五卡 15.1 秒、done 19.1 秒。這批數字不含開始前的步驟和網路。
- N1–N6：零延遲改動。
- B4：用戶能複製推薦回覆的時間從約 19.1 秒提早到約 8.5 秒，不回案從約 8.1 秒的 done 提早到約 3.0 秒的決定事件。這是不碰 prompt 就能拿到的最大改善，屬於估計，要等真機和 B1 遙測確認。
- C2：在 5.5 上 done 事件本身中位約 1.3 秒，Sonnet 5 備援約 6–7 秒，會縮短，幅度未核實。
- C4：如果刪掉發散計畫，首卡最多提早約 4.96 秒（決定到首卡的中位差），實際秒數未核實，因為 5.5 有隱藏思考。
- Sonnet 5 備援路徑改善比例更大：done 約 33–35 秒，備援的 done 佔輸出 22–25%。
- 開始前的往返（RevenueCat、auth、建立 run）和冷啟動從沒量過，B1 上線後才有數字。
- **預期品質**：網本身不提升品質，它的作用是讓品質變化第一次可以量、可以退。
可預期的改善：
- B2：被 checkInput 誤擋的正常對話恢復可用（生產頻率未核實）。
- B3：卡片不再在 done 時被改寫或換成罐頭句（頻率未量，從黑箱看偏低）；「她話裡的意思」從 20/23 空白，補到大約 metrics 有帶 psychology 的 18/23；同一次分析不再出現兩個熱度分數。
- C1：照抄 prompt 範例的罐頭語減少，基準是 ab C 3/21、e2e C 3/23、ab B 3/42。
- C3：目標是讓問句超額低於基準 47/547（約 9%），而且降幅超過雜訊帶。
每一片 prompt 改動的上線標準都是：決定正確率不降（e2e 23/23），且 Bruce 標註的「直接送」比例不降。
這個方案不處理最大的品質洞，也就是她問到用戶本人的事時會編造（F02），以及邀約時機（F29）和不表態（F30）。這些是產品結構刀，要放在乾淨的 v3 上做，而且需要 Eric 另外拍板；本方案的作用是讓那幾刀做起來安全。
- **成本**：執行期：現在每次分析約 US$0.073（e2e C：23 案共 US$1.680）。
- C2 會少掉 done 報告的輸出，在 5.5 上約佔輸出字元 12%。
- C4 如果刪掉發散計畫，會少約 15% 的輸出，加上 prompt 的 4,809 字元。
- 兩項加起來，估計每次輸出可以少約四分之一，金額未核實。
- B1 只多寫幾個 log 欄位，成本可忽略。
- critic 影子不變，約每次 0.5 美分，是否關閉留待之後決定。
開發期：
- CI 每個 PR 多約 1.5–2 分鐘（本機實測 1m41s）。
- 付費檢查點是 T2 的 v2 對 v3 各 3 輪。c-fix C×3 共 63 次實測 US$2.60 加評審，兩臂估約 US$5–6 一次；C1、C2、C3、C4 加上翻開關前共約 4–5 次，估 US$20–30。每次都要 Eric 說「跑」。
- Bruce 標註一次約 1 小時。
- 全案不寫 migration，也不碰 production 資料；只有選做的 ai_logs 查詢需要 Eric 授權讀取。
- **為什麼不選其他方案**：- 一次重寫 prompt，或現在就照開場救星拆成 plan、write、pick：沒有雜訊帶也沒有重播網，就分不出是退步還是運氣，正好把 Bruce 怕的事放大。而且伺服器挑卡會把首卡延到五卡齊的時間（F10）。拆分應該在網建好、C4 量完之後再決定。
- 先做產品改版（一張卡加兩種語氣、用戶事實、邀約標籤）：價值最大，但每一項都要 Eric 拍板，也都會動 prompt，沒有網的話一樣不敢上。這個方案不是取代它們，而是讓它們做起來安全。
- 每一片都加一個旗標：旗標太多會讓「關閉等於零改動」變得驗不完（practice-chat 連漏三輪的坑）。這裡只用一個 v3 開關；伺服器程式的改動交給確定性的重播網，不需要旗標。
- 保留 SHA 鎖和逐字鏡像測試：它們鎖的是文字不是行為，就是讓人「無從下手」的來源。改成文字快照之後，Bruce 改什麼都看得到。
- 拆成多支 Edge Function：部署 workflow 會重部署全部通用函式，所以拆了也縮小不了影響範圍，還會讓閘門程式多出好幾份（F24）。
- 先抽共用框架（eval kit、exactly_once、streamOrRun）：今天只有一個使用者需要，照 YAGNI，等第二處真的要改同一段程式時再抽。
- 這個方案和其他方案最大的差別在節奏：前六週左右的改動對用戶完全無感，但每一步都可以單獨 revert，Bruce 第一個 PR 就能開工，而且不用碰那 48K 字元。

### 首卡即可用：對話分析的體感速度結構刀（延遲優先）

**主張**：「等有點久」最大的一塊不在模型，而在 App 把串流當成預覽。現行 Sonnet 5.5 下，推薦卡中位數 7.9–8.5 秒就到了，App 卻要等 done（18.3–19.1 秒）才讓人複製；「先別回」卡 3.0 秒就到，要約 8 秒才能操作。中位數我已從 tools/analyze-v2-blackbox/out/2026-10-02-c-fix/arm-C.json 和 e2e/arm-C.json 重算確認。

這一刀的核心是立一條契約：「串流事件就是逐件到齊的最終結果」。
- 伺服器在卡片送出那一刻就定稿，done 不再改寫用戶看過的卡。
- App 用最終元件逐件渲染，推薦卡一到就能複製。

這一刀不動 prompt、不動扣費、不花模型錢，可複製時間預期從約 19 秒降到約 8 秒。

之後再用付費黑箱加 A/A 雜訊帶，決定發散計畫是刪掉還是移到推薦卡之後；決定到首卡之間約 96% 的位元組是這段計畫。減少預設卡數、改成點了才生成，在首卡可複製之後是成本槓桿，不是體感槓桿，等複製遙測出來再交給 Eric 決定。

任何改動之前，先補三樣安全網：真實輸出重播測試、Deno 和 Dart 共用的事件 fixture、CI 跑整個目錄。這直接回應 Bruce「怕 regression、無從下手」。

**目標架構**：一、事件契約（v2，不改事件名，只改順序和不變式）
1. 順序：
   analysis.started
   → analysis.inventory
   → analysis.decision（扣費錨點，reframer.ts:795-882；不回時這個事件本身就是完整的 V2 卡，no_send_decision.ts:200-204）
   → analysis.recommendation（瘦卡，伺服器用選中卡回填全文，reframer.ts:708-737）
   → 選中風格的 analysis.reply_option（已定稿）
   → [analysis.divergence_plan：留不留、放哪裡由 P6 決定；伺服器已能處理計畫晚到，見 reframer.ts:612-621 backfillAttribution]
   → 其他 reply_option（已定稿）
   → analysis.metrics（enthusiasm、dimensions、topicDepth、gameStage、psychology 都以它為準）
   → analysis.coach_hint
   → analysis.done（伺服器自己組，卡片欄位只從已送出的事件複製）
2. 不變式：只要某張 reply_option 已送到 App，它的文字就等於 done.finalResult 和 analysis_stream_runs 持久化結果裡的同一張卡。

二、伺服器（supabase/functions/analyze-chat/）
- card_finalize.ts（新增，純函式）：finalizeReplyOption(option, {ballList, selectedSegmentCount, enthusiasmFallback})。
  - 由 post_process.ts 現有邏輯抽出：sanitizeReplyOption（:659）、enforceReplySegmentSourceContract（:588）、Step 3b 段數對齊（:1165-1195，保留 Eric 2026-08-17 的決定），再加上 guardrails.ts checkAiOutput（:338）的逐卡版本。
  - post_process.ts 的非串流路徑改呼叫同一個函式，所以只有一個來源，而且重跑結果不變。
  - 不新增任何規則或正規式。
- reframer.ts
  - forwardReplyOption（:633）在 absorbAndEmit 之前呼叫 finalizeReplyOption。非選中卡如果比選中卡早到，先暫存到選中卡到為止；選中卡永遠不暫存。bindPendingRecommendation 改用定稿後的段落。
  - mergeFinalResult（:1473）改成白名單：模型 done 只能寫 strategy、reminder、warnings、healthCheck、targetProfile，以及 metrics 沒給時的 psychology。不再接受 replies、replyOptions、finalRecommendation、stretchLevels，也不接受 metrics 已經給過的 enthusiasm、dimensions、topicDepth。
  - absorbMetrics（:1397）補上吸收 psychology。
- analyze_stream_handler.ts markDone（:665-800）
  - checkAiOutput 不再在 done 改寫卡片，因為送出時已經做過。
  - postProcessAnalysisResult 碰到已定稿的卡什麼都不做。
  - logAiCall（:758）和 emitPhase0Observability（:701）改用 deps.waitUntil 背景執行；store.markDone 仍然 await。
- stream_milestones.ts（新增，約 30 行）
  - 以請求開始為 0 秒，記錄 runCreated、firstDecision、firstReplyOption、allReplyOptions、done。
  - 由 stream_handler.ts 的 emit 包裝呼叫，寫進 finalPayload.telemetry 和 ai_logs.responseBody。用單一個巢狀鍵，避開 sanitizer 的 32 鍵上限。
  - 另外記 fallbackUsed（實際模型不等於要求的模型）和 retryCount（取自 run）。
  - 開場救星和新話題住在同一支 Edge Function，之後可以直接用。
- revenuecat_reconciliation.ts:180 的 fetch 加 AbortSignal.timeout。
- stream_prompt.ts 加選項 divergencePlanPlacement：'before'（預設，和現行逐字相同）、'after_selected'、'off'。
- 測試資料
  - supabase/functions/analyze-chat/testdata/replay/<case>.json：從 tools/analyze-v2-blackbox/out/2026-10-02-*/arm-C.json 複製約 20 組 rawLines。
  - replay_test.ts：注入 callModel 跑 handleAnalyzeStream。
  - golden 輸出寫成 test/fixtures/analysis_stream/<case>.ndjson，Deno 和 Dart 兩邊的測試讀同一個檔。

三、App
- lib/features/analysis/domain/entities/analysis_stream_partial.dart（新增，不可變）：
  - 不回決策：AnalysisDecisionV2.fromJson(decision 事件)。
  - 回覆決策：nextStepTitle、nextStepBody、doThis、avoidThis。
  - recommendation：FinalRecommendation。
  - replies 和 replyOptions：reason 對到 approach、segments 對到 messages，沿用 ReplyOption.fromJson。
  - coachActionHint：改讀頂層欄位（修 F03c）。
  - expectedStyles。
- streaming_analyze_notifier.dart：在 :422-461 把 update.rawEvent 折進 state.partial（notifier 有 keepAlive，用戶離開再回來也還在）。自動續接時保留 partial；只有在新的 started 事件沒有 resumed:true（伺服器失敗後整份重跑，stream_handler.ts:148-151）時才清掉。
- analysis_screen.dart
  - :878 的 hydrate 和 :2727 的 live 兩個 switch 合成 _applyStreamingState(s, live)。
  - :3731 的 ReplyZoneCards 改用 result ?? partial 建。
  - 串流中推薦卡和已經到的風格卡可以複製；精修和回報結果列等 done 才出現；還沒到的風格顯示 skeleton。
  - 不回決策直接渲染 AnalysisDecisionCard。
  - _analyzeAdviceId（:3618）的 runKey 改用串流的 runId。
- 等待區
  - StreamingContentCard（sections/streaming_content_section.dart）和置中 loader 的內容複製都刪掉。
  - 改用 lib/shared/widgets/stream_progress_ticker.dart，只顯示階段，heartbeat（phase=='heartbeat'）比照 opener_flow_controller.dart:842 過濾掉。
  - 開場救星的 _SkeletonStyleCard（opening_rescue_screen.dart:2657）搬到 lib/shared/widgets/skeleton_style_card.dart，兩個功能共用。
- 遙測：沿用 lib/core/services/funnel_tracker.dart（submit-feedback，去識別白名單），新增兩個事件：
  - analysis_reply_ready：{wait_s:int, decision:enum}
  - analysis_reply_copied：{card:enum final|extend|resonate|tease|humor|coldRead|closing, before_done:bool, wait_s:int}
  - 三處要同步改：funnel_tracker.dart、supabase/functions/submit-feedback/funnel_utils.ts、docs/integrations/funnel-events-v1.md。不需要新資料表，也不需要 migration。

四、刻意不做
- 不拆成多支 Edge Function。
- 不拆並行模型呼叫。
- 不做卡片內逐字串流。
- 不為了快取重排 prompt：未命中和命中的成對延遲差中位數只有 0.28 秒（F27），屬於成本議題。
- P0 到 P9 都不需要 migration；任何情況都不使用 supabase db push。

| 階段 | 目標 | 刪什麼 | 用戶看到 | 防退步 | 風險 | 可單獨退回 |
|---|---|---|---|---|---|---|
| P0 安全網：真實輸出重播、共用事件 fixture、CI 跑整個目錄 | 之後每一刀都有零成本、用真實模型輸出的回歸證據，而且 CI 和部署前真的會跑到。 | flutter-ci.yml 裡 analyze-chat 的逐檔白名單。 | 無。 | 1. 本機全套 1,249–1,274 個測試在 --deny-net 下全綠（F21 實測約 1.2–2 分鐘）。 2. replay golden 對現行 main 是綠的。 3. 故意改 reframer 一行，確認 golden 會轉紅一次，證明這張網真的咬得住。 | R2：每個 PR 的 CI 多約 75 秒（F21 估算）。改 workflow 屬於工具設定變更，需要 Eric 對這個確切範圍明確授權。golden 如果是用改動後的程式碼產生，就是假綠。 | 是 |
| P1 生產延遲與複製遙測 | 取得生產環境的首卡時間、首次複製時間、開始前耗時和備援率。現在這些只有離線黑箱的數字。 | logAiCall 裡永遠是預設值的 fallbackUsed:false 和 retryCount:0 寫法（analyze_stream_handler.ts:758、:811）。 | 無。 | 1. stream_milestones 的單元測試：每個時間點只記一次，以請求開始為基準。 2. logger sanitizer 測試：斷言 responseBody 沒有 `_truncated`。 3. funnel_utils_test 和 client 白名單鏡像同步更新。 4. replay golden 不變（遙測鍵放在 telemetry 子物件，不進 golden 比對）。 | R2：白名單三處可能漂移，用既有的成對測試擋住。資料只有 enum、int、bool，不含內容。submit-feedback 是通用函式，推 main 會重部署所有通用函式，這次推送需要 Eric 核准。 | 是 |
| P2 送出即定稿：done 不再改寫看過的卡（伺服器） | 讓手機上已經出現的卡就是最終卡。這是首卡可以誠實開放複製的前提。 | 1. 串流路徑在 done 時把整組卡換成罐頭句的做法，改成送出前逐卡檢查。 2. mergeFinalResult 對 replies、replyOptions、finalRecommendation、stretchLevels 的寫入。 3. done 覆蓋 metrics 分數的路徑（F06 的兩套熱度分數問題）。 | 1. 「她話裡的意思」不再是空白卡（e2e 有 18/23 案模型其實有給 psychology）。 2. 串流中和完成時的熱度分數一致。 3. 完成那一刻卡片不再改字或被換成罐頭句。 | 1. replay golden：20 組卡片文字逐字不變。預期只有兩種差異：psychology 不再是空的、熱度分數不再出現兩套。golden 的每一條 diff 都要人工審。 2. 新的不變式測試：每個 replay 案例中，送出的 reply_option 都等於 done.finalResult.replyOptions 裡的同一張卡。 3. 冪等測試：finalizeReplyOption 跑兩次的結果和跑一次相同，postProcess 碰到已定稿的卡什麼都不做。 4. 把 scratchpad 的 clobber2 案例 A 轉成正式測試：模型在 done 塞 replyOptions 時不能覆蓋已送出的卡。 5. reframer_test、post_process_test、guardrails_test 全綠；post_process_test.ts:1187-1242 那組 Eric 決定的段數對齊測試原樣保留且是綠的。 | R2：1. 安全語意改變：命中 BLOCKED_PATTERNS 時，原本是卡片先顯示、done 時五張一起換掉，改成送出前只換命中的那一張。罐頭句的等級改用預設分數，因為那時 metrics 還沒到。黑箱 220 份分析裡 0 份命中。 2. 非選中卡早到時要暫存，替代卡會稍晚出現。 3. 扣費錨點不動。 以上三點都要在主審裡檢查，Eric 審 PR 時可以否決。 | 是 |
| P3a 分析畫面兩條狀態切換合成一條（純整理） | 讓 P3b 只需要改一個地方，降低改 4,360 行畫面時的回歸風險。 | 重複的 switch，以及重複的欄位賦值。 | 無。 | 1. notifier 的 30 個單元測試、analysis_screen_hydration_test、presentation characterization test 全綠。 2. 新增一個測試：同一個 state 分別走 hydrate 和 live 兩條路，畫面欄位要完全相同，而且只有 live 會觸發持久化、用量同步和付費牆。 | R2：兩條路的副作用不同（持久化、用量同步、付費牆、捲動、觸覺回饋），合併時可能漏掉其中一個。依「不確定就當 R2」處理。 | 否 |
| P3b 首卡可複製：逐件到齊的結果畫面（App） | 推薦卡一到就能複製，「先別回」卡一到就能操作。 | 1. recommendationPreview 整條管線：AnalysisRecommendationPreview、analyze_stream_client.dart:594-623 的 _streamRecommendationPreview，以及 notifier 靠它判斷 phase 的邏輯（改成看 partial）。 2. analysis_stream_content_display.dart 裡 decision、reply_option、coach_hint 的純文字格子。 | 5.5 下推薦回覆的可複製時間，從約 18–19 秒（done）降到約 8 秒（首卡）；Sonnet 5 備援從約 33–35 秒降到約 12.5 秒；「先別回」卡從約 8 秒降到約 3 秒可操作。 | Dart 測試讀 P0 的共用 fixture： (1) 選中的 reply_option 到了之後、done 之前，推薦卡可以複製，文字等於 done 版本。 (2) do_not_send 和 acknowledge_and_stop 一收到 decision 事件就出現 AnalysisDecisionCard。 (3) done 時卡片不跳動。 (4) 片段過期的分支照樣擋下。 (5) adviceId 帶 runId。 (6) coach_hint 不再被濾掉。 另外由 Eric 用 iPhone TestFlight 實測「按下開始到可以複製」的時間。 | R2：1. 分析最後失敗時，提早複製的紀錄會留下一筆沒有結果的建議。 2. 串流中滑到還沒到的風格，看到的是 skeleton。 3. 手感由 Eric 拍板（決策 1）。 | 是 |
| P4 等待與中斷畫面只講真話 | 只留一個進度元件、顯示真的卡片、斷線不丟已經看到的內容、失敗時有出口。 | 1. sections/streaming_content_section.dart（StreamingContentCard）。 2. notifier 的 4 步前奏（:213-232、:595-631）。 3. 1 秒輪播文案（streaming_analysis_loading_widgets.dart:206-215、:269-270）。 4. streaming_analysis_loading_widgets_test.dart:76-95 鎖住死路的斷言，改成反向斷言。 | 畫面不再重複同一段話，也不再叫用戶「請保持連線」；網路斷一下卡片還在；失敗時有能按的重新分析。 | widget 和 notifier 測試： 1. heartbeat 不會改動標籤。 2. 第一個內容到達後，置中 spinner 消失。 3. skeleton 數量等於預期風格數減去已到的數量。 4. 續接之後卡片還在（補上 notifier_test:1006-1031 只斷言 done 的缺口）。 5. 失敗重跑不會出現重複的卡。 6. 重試用完時按鈕可以按。 | R2：文案需要 Bruce 審；續接去重寫錯會出現重複卡。 | 是 |
| P5 伺服器尾端和開始前的便宜修正 | done 少等一個 DB 往返就送出；RevenueCat 慢的時候不卡住開始。 | 無。 | 完成稍微早一點（未量測，估數十到數百毫秒）；RevenueCat 卡住時不再無限期等待。 | 1. analyze_stream_handler_test 用延遲的假 logger，證明 done 比 log 寫入先送出，而且 store.markDone 仍然 await。 2. reconciliation 測試用掛住的 fetch，證明 3 秒內回傳既有的失敗碼。 3. replay golden 不變。 | R2：worker 被回收時，背景的 log 可能遺失。3 秒逾時沒有經過量測，可以等 P1 的資料再調。 | 是 |
| P6a 發散計畫三臂量測（生產不變） | 用數據決定 decision 到首卡之間約 5 秒的那段計畫要不要留。 | 無。 | 無。 | 1. v1 的雜湊鎖不變。 2. 新增測試：'before' 渲染出來的字串和現行 v2 完全相同。 3. stream_prompt_test 由常數產生的期望全綠。 | R1：付費跑一定要等 Eric 明確說「跑」（估約 US$11–17）。評審和受評的是同一家族，所以要另做跨家族盲評（Codex）。 | 是 |
| P6b 套用計畫的量測結論 | 讓首卡提早出現。 | 「關掉」勝出時刪除： - stream_prompt.ts 的 DIVERGENCE_PLAN_STEP 和 DIVERGENCE_REPLY_OPTION_RULE - stream_budget.ts:21 的 DIVERGENCE_PLAN_EXTRA_TOKENS - reframer.ts 裡的計畫解析和歸因：parseDivergencePlanEvent 的呼叫、attributeVariant、backfillAttribution、repairDivergencePlanLineGlitch - phase0 的預算遙測、critic_shadow.ts:122、:145 的計畫輸入 - divergence_contract.ts 的大部分（509 行） - stream_events.ts:23-25 的過期註解 | 首卡估計提早約 3 秒。這是依位元組比例推估，5.5 有隱藏思考，未核實。 | 1. 重新產生 replay golden 並逐條審 diff，應該只少了計畫事件和歸因欄位。 2. P0 的不變式測試仍然是綠的。 3. 黑箱結果符合判準。 | R2：卡片可能更常同一個開頭，或球覆蓋退步。改 prompt 文字屬於高風險變動，需要黑箱驗證和主審。 | 是 |
| P7（有條件）付費用戶的權益預同步只在需要時才等 | 縮短付費用戶開始前的等待。 | 每次分析都要 await 的同步。 | 付費用戶開始前少等一段時間（幅度看 P1 的數據）。 | 1. subscription provider 的單元測試：方案相同時不 await，不同時照舊 await。 2. 既有的「升級後第一次分析拿到五種風格」測試保持綠。 | R2：方案剛被撤銷時，可能多拿一次五種風格；伺服器仍是最終把關（ADR #25）。 | 是 |
| P8（有條件）首塊期限 | provider 卡住時不再讓用戶盯著 2 分鐘的轉圈。 | 無。 | provider 狀況差的時候，錯誤或結果會更早出現。 | 1. streaming_fallback_test 新增「首塊逾時換下一個模型」，以及「已送出內容後絕不切換模型」兩個測試。 2. 既有測試「整條備援鏈共用一個總期限」（streaming_fallback_test.ts:437-466）保持綠。 | R2：5.5 的自適應思考會延後第一段文字，期限設太緊會誤殺正常的分析。 | 是 |
| P9（有條件）精簡 done：不再要求模型重寫重複的欄位 | 縮短卡片到齊後到 done 的時間，也減少輸出。 | stream_prompt.ts:252「要求 done 帶 legacy finalResult」的那句；_shared/social/conversation_policy.ts:304-306「finalRecommendation.content 仍要填」只從 v2 拿掉。 | 完成時間估計提早不到 1 秒（未核實）。 | 1. replay golden 和不變式測試保持綠。 2. 小規模付費黑箱（23 案跑 1–2 輪，估 US$2–4）確認 targetProfile 和 healthCheck 的出現率沒有低於基線的雜訊帶。 | R2：模型可能漏寫 targetProfile，影響對象記憶。 | 是 |
| P10（有條件，看決策 3）付費版預設卡數和點了才生成 | 減少輸出成本和完成時間；不影響首卡。 | 每次分析都生成五種風格的要求（stream_prompt.ts:209 依方案改成 3 種）。 | 完成時間估計提早約 3 秒（約 2 張卡 × 每張約 1.6 秒，1.6 秒是從 c-fix 的首卡到五卡差推算）；想看更多語氣時要多點一下。 | 1. 新請求形狀的行為測試：所有權、只生成一次、不扣費、限流。 2. 依「請求形狀」補黑箱語料（F22），量測多出來的風格和原本的卡在球覆蓋上是否一致。 | R2：要重新拍板 ADR #25，牽涉 Edge 的請求格式和額度語意。如果多出來的卡要持久化，可能需要 migration，屆時必須走 docs/shared-agent-rules.md 的定向 migration 流程，絕不使用 supabase db push。 | 是 |

- **預期延遲**：基準是現行生產路徑：Sonnet 5.5，送出案中位數，從模型呼叫開始計，已從 records.json 重算過。c-fix 的 n=39，e2e 的 n=15。
- 決定：3.0–3.1 秒
- 首卡：7.9–8.5 秒
- 五卡到齊：14.7–15.1 秒
- done：18.3–19.1 秒
- 不回案：決定 3.0–3.4 秒，done 7.5–8.1 秒
- Sonnet 5 備援：首卡約 12.4 秒，done 33.4–34.7 秒

P3b 之後，推薦回覆的可複製時間等於首卡：5.5 約 8 秒（原本 18–19 秒），備援約 12.5 秒（原本約 34 秒）；不回卡約 3 秒就能操作（原本約 8 秒）。這是把已經量到的首卡時間重新定義成「可以用的時間」，不是推估。真機上的渲染延遲未核實，要由 Eric 用 iPhone 確認。

P6b 如果關掉計畫或把計畫移到推薦卡之後：首卡估計再提早約 3 秒，變成約 5–5.5 秒。依據是決定到首卡之間 4.8–5.0 秒裡約 96% 的位元組是計畫；5.5 有隱藏思考，所以未核實。選「關掉」時，五卡到齊和 done 也會差不多一起提早；選「移後」時兩者不變。

P5：done 少等一次 DB 寫入往返（未量測）。
P9：done 估計提早不到 1 秒（未核實）。
P10：五卡到齊和 done 估計提早約 3 秒，不影響首卡。

開始前的耗時目前完全沒量過，包括付費用戶的 RevenueCat 加 sync-subscription（上限 20 秒）、auth、訂閱查詢、限流、建立 run。P1 之後才有數字，P7 才會決定做不做。免費方案（2 種風格）的延遲從沒在黑箱量過。
- **預期品質**：P0–P5 都不改模型的輸入，所以模型品質在構造上不會變。P2 的 replay golden 會證明 20 組真實輸出的卡片文字逐字相同。

會順帶變好的地方：
- 「她話裡的意思」不再空白：e2e 有 18/23 案模型其實有寫 psychology，卻在組裝時被丟掉（F06）。
- 熱度分數不再一次分析出現兩套，例如 78 和 71。
- 完成那一刻卡片不再被改字或換成罐頭句（F05）。
- 錯的事實文字不會在「完成」時突然被換掉。

P6b 可能讓卡片的分散度略有變化，會依事先登記的雜訊帶判準決定，不在雜訊帶內的退步就不採用。
P9 的風險是 targetProfile 的出現率，用黑箱驗證。

這份提案不處理本人事實編造、邀約時機、不表態、prompt 矛盾（F02、F29、F30、F16），這些屬於品質路線。P2 留下的 finalizeReplyOption 是那條路線接上送出句守門的唯一接縫。
- **成本**：P0–P5 和 P7、P8：模型成本為 0。CI 每個 PR 多約 75 秒（依 F21 的本機實測推算）。

P6a 需要一次付費黑箱，估約 US$11–17。算法是 e2e 每案 US$0.073（2026-10-02-e2e/summary.md），乘上三臂、23 案、2–3 輪，另加評審約 US$1；未核實，必須等 Eric 說「跑」。

P6b 如果選「關掉」，輸出約少 15%（c-fix 計畫佔比）。輸出約 US$0.028 一次，所以每次分析估省約 US$0.004；system prompt 也少 4,809 字元，約佔 v2 的 10%，快取寫入和讀取費用照比例下降（估計）。

P9 需要一次小規模付費跑，估約 US$2–4；之後輸出略減。
P10 估計輸出再少約 14%（五卡約佔 36%，乘以 2/5）。

依 vault VibeSync.md:52，內測流量下 30 天 Anthropic 費用約 US$10，所以總額影響很小，主要價值在體感速度。
- **為什麼不選其他方案**：(a) 比照開場救星拆成 plan 和 write 兩次呼叫：首卡反而會更晚，因為要等規劃呼叫結束。開場救星是完成才交付，本來就不在乎首卡；分析是邊生成邊顯示，首卡才是用戶感受到的那一刻。

(b) 決定一出來就並行開第二次呼叫寫替代卡：只能讓五卡早點到齊，而 P3b 之後用戶已經不必等五卡。代價是多一份約 40K token 的 prompt，還要合併兩條串流、處理扣費錨點和重試，屬於 R2 的複雜度。

(c) 卡片內逐字串流：首卡最多只早約 1.6 秒（每張卡約 1.6 秒，從 c-fix 推算），但需要解析不完整的 JSON，而且顯示的字可能和定稿不同，違反 P2 的不變式。

(d) 先減少預設卡數：P3b 之後這是成本槓桿，不是體感槓桿；而且要重新拍板 ADR #25、新增請求形狀，所以排在遙測之後。

(e) 為了快取重排 prompt：未命中和命中的成對延遲差中位數只有約 0.28 秒（F27），Eric 也曾否決過類似的提案。

(f) 先做 prompt 大重組（F15、F16、F19）：長期可能最重要，但解決不了等待問題；在 P0 的安全網還沒到位前就碰 prompt，正是 Bruce 擔心的情況。

(g) 拆成多支 Edge Function：部署 workflow 對 supabase/functions 的任何改動都會重部署所有通用函式，拆了也不會縮小影響範圍；冷啟動也從沒量過。

(h) 縮短盤點（inventory）來提早決定：決定已經在約 3 秒出現，盤點又是決策和球覆蓋遙測的鷹架，品質風險大於收益。

本提案和品質路線、維護性路線相容：P0 的安全網，以及 P2 的 finalizeReplyOption 單一接縫，正好是那兩條路線需要的前置。

## 兩位評審

### 評審 1（維護者／技術負責人角度）

| 方案 | 用戶價值 | 品質 | 延遲 | 防退步 | 工作量可行 | 可共用 | 總分 |
|---|---|---|---|---|---|---|---|
| 提案一：回歸先行的勒殺式結構刀（先織網，再一片一片剝） | 6.5 | 5.5 | 7 | 9.5 | 6.5 | 6.5 | 7 |
| 提案二：讀判 → 伺服器政策 → 寫卡 → 送出即定稿（品質優先） | 8.5 | 8 | 5.5 | 5 | 4 | 8 | 6.5 |
| 提案三：首卡即可用（延遲優先） | 7.5 | 4 | 9 | 8 | 8 | 6 | 7.1 |

**推薦計畫**：

【一句話結論】這個功能值得做。「要不要回」的判斷已經是教練等級：5.5 決定 23/23 正確，不回案 8/8 判對。要拿下繁中曖昧聊天的第一名，靠的不是五張卡也不是速度，而是三件事：判讀準；給一句敢原封送出的話，包括叫他別送、叫他現在約；記得這個人。

【Backbone】採提案一的框架：先織網，再把 prompt 改動全部放進 v3 平行組合，用一個開關切換。執行順序改用提案三：不動 prompt 的「送出即定稿加首卡可複製」最先上線。品質階段嫁接提案二的結構化標籤加伺服器政策，先在現有的單次呼叫裡做；兩段式讀判／寫卡只當離線對照臂量測，不預設上線。

【階段 0：安全網＋立即止血，第 1 週，都是 S】
0a 刪除 checkInput（F01，屬 P1 bug）：單獨開一個小 PR，補 handler 測試，確認四句正常對話不再回 400。這一步屬 R2，要經跨家族主審。
0b CI 改成跑整個目錄：analyze-chat 和 _shared/social 全部跑，排除 *_postgres_test.ts，三個 postgres 測試加進 PGlite 那一步；再加 deno check index.ts。deploy-edge-function.yml 在部署前跑同一條測試，寫法比照 deploy-keyboard-assist.yml:35-40。改 workflow 屬 R2，需要 Eric 對這個範圍明確授權。我已在本機實跑：1,309 passed、0 failed，2m28s。
0c 零成本重播測試 replay_test.ts：取 2026-10-02 arm-C 約 20 組 rawLines。rawLines 存的是解析後的物件，所以逐行 JSON.stringify，再經 callModel 注入點（analyze_stream_handler.ts:193,569）餵回去。golden 必須用 git archive 9adbf87c 從舊 commit 產生，比對四個面：模型請求、NDJSON、store 呼叫、log。同時輸出 3 份 send、do_not_send、acknowledge_and_stop 的 NDJSON，給 Dart 共用。
0d prompt 文字快照取代 SHA 鎖，第一次把 v2 production 的 prompt 鎖住。同一個 commit 裡斷言舊 sha 和新快照相等，避免新程式碼自己比自己的假綠。

【階段 1：送出即定稿＋首卡可複製，第 2–3 週，R2，不動 prompt】
1a 伺服器（以提案三 P2 為主）：
- reframer 在轉發卡片前定稿。Step 3b 的段數對齊照原本依位置裁切，搬到送出前做，維持 Eric 08-17 的決定；要不要改成依 sourceIndex，另外請 Eric 決定。
- mergeFinalResult 改成白名單，absorbMetrics 補吸收 psychology，拿掉 enthusiasm 50 的種子。
- normalizeOutgoingMessageText 和 prompt_leak 先以 shadow 模式只記錄、不改字。注意 normalizeOutgoingMessageText 一律會把「你」改成「妳」（outgoing_message_text.ts:57-66），黑箱語料裡有男性對象，所以代名詞等 Eric 決定後再開。
1b App：
- 先把兩個 switch 合成一個（純整理）。
- 部分結果逐件渲染：首卡一到就能複製；decision 事件直接渲染 AnalysisDecisionCard；coach_hint 改讀頂層欄位。
- 等待畫面改用 StreamProgressTicker，加上從開場救星搬到 lib/shared 的 skeleton；heartbeat 不給用戶看。
- 自動續接時保留已顯示的卡片；重試用完時給可以按的「重新分析」。
- recommendationPreviewError* 這組錯誤顯示（analysis_screen.dart:978,993,2858,2860）要搬到新結構，不能直接刪。
1c 遙測：伺服器記里程碑（決定、首卡、五卡、done）、fallbackUsed、stream_terminal 上報 Sentry；App 用 funnel 事件記 analysis_reply_ready 和 analysis_reply_copied（帶 before_done）。這一步也是之後決定卡數的數據來源。

【階段 2：量尺，免費、可以和階段 1 並行】
- 用已存的多輪結果算出 A/A 雜訊帶。
- Bruce 標註 24 張已存的選中卡（直接送／要改／不送），用來校正 critic。
- 逐字鏡像測試只在「這次要改到它」時才換成語意錨點，不一次重寫 300 條。

【階段 3：v3 骨架＋只刪不加，R2】
- 先刪 App 不會送的請求形狀（F32，改回 410）。
- 建 ANALYZE_PROMPT_V3 平行組合，起點和 v2 逐位元組相同；v1 凍結進 legacy。
- v3 只做刪除：userDraft 段、死規則、stretchLevel（伺服器預設 within）、scenarioDetected、會被逐字照抄的範例句（包括「先不邀約」那句）、帶 PUA 色彩的舊範例；「AI 約會教練」改成「戀愛教練」。
- 付費黑箱 v2 對 v3 各 ≥3 輪，差距超出雜訊帶才算數，每次都等 Eric 說「跑」。

【階段 4：單一輸出契約＋發散計畫去留，R2】
- stream_contract.ts 成為唯一的契約來源；done 只當結束訊號，舊欄位由伺服器組出。
- 計畫用三個臂量（現狀、關掉、移到推薦卡之後），判準事先寫好再跑。

【階段 5：品質結構刀，放在 v3 裡，取自提案二】
- decision 事件加三個標籤：selfFactNeeded、inviteReadiness 加 evidenceIds、herQuestionType。
- 新增純函式 card_policy，推出 move 和 slots。
- 送出前只做能逐字判斷的檢查：填空標記確實存在、證據 id 確實在片段裡。
- F02 卡片留填空，App 要他填好才能複製；F29 讓邀約窗口真的推進；F30 被問意見時先表態。
- compileAnalyzeUserTurn 加訊息 id（F07）。
- 每一項都要過黑箱 ≥3 輪，加上 Bruce 的標註。

【階段 6：有條件才做】
- 階段 5 的標籤在單次呼叫裡守不住，才去量讀判／寫卡的離線臂。
- 複製遙測累積兩週後，再請 Eric 重新拍板 ADR #25：五張卡改成「一張推薦卡加兩種、其他點了才生成」。

【共用元件】
- 現在就共用：StreamProgressTicker 加 skeleton；normalize 系列子函式加 prompt_leak；把不回決策的「伺服器給選單、模型選 enum」模式延伸到新標籤；借用新話題 my_story 的「缺素材」概念處理 F02；stream_milestones 之後接開場救星和新話題的 logAiCall；四面重播 harness 的寫法。
- 等第二個使用者真的要改同一段程式時再抽：exactly_once 純函式、NDJSON client helper、streamOrRun、eval_kit。
- 明確不共用：CONVERSATION_POLICY、各功能的計費生命週期、開場救星的伺服器挑卡（會把首卡延到五卡齊）。

【最先要做的 3 步】
1) 小 PR：刪除 guardrails.ts:378-403 的 checkInput 和 analyze_chat_handler.ts:893-901 的呼叫，補四句正常對話的 handler 測試，送跨家族主審，再請 Eric 核准 push。
2) 取得 Eric 對 .github/workflows/flutter-ci.yml 和 deploy-edge-function.yml 的明確授權後，改成整目錄 deno test 加 deno check，部署前跑同一條，postgres 測試補進 PGlite。
3) 新增 replay_test.ts、testdata 和 golden（從 9adbf87c 產生），以及 3 份 Deno 和 Dart 共用的 NDJSON fixture。這三步完成之前，不碰 reframer 和 prompt。

【請 Eric 決定（最多 3 項，各附預設）】
- 授權 CI 和部署 workflow 的修改範圍。預設：同意。
- 首卡一到就能複製，加上「送出即定稿」，Step 3b 暫時維持依位置裁切。預設：同意。
- 她問到用戶本人的事時怎麼處理。預設：卡片留填空標記，App 要他填好才能複製，不重開「關於我」。付費黑箱總預算預設上限 US$30。

**方案中的瑕疵**：

- 提案一：順序讓用戶等最久。B4（首卡可複製，5.5 上約從 19.1 秒降到 8.5 秒）排在 N1–N6、B1–B3 之後，方案自己承認「前六週對用戶完全無感」。但 B4 其實只依賴 B3（送出即定稿）和 N3（共用 fixture），Bruce 最在意的「等有點久」不必拖這麼久。
- 提案一：B3 的退出條件寫「golden 的 diff 只出現兩類」，和同一階段「在 emitCard 套用標點、簡轉繁、外文處理」互相矛盾，因為這些正規化會合理地改到部分卡片文字，包括 `\\n` 展開。另外 normalizeOutgoingMessageText 一律會先跑 normalizePartnerPronoun（outgoing_message_text.ts:57-66），所以「先不統一代名詞」實際上要改用各個子函式組合，不能直接重用共用入口。
- 提案一：N5 要一次把約 300 句逐字鏡像換成語意錨點，是全案最大的苦工，而且沒有用戶價值。比較省的做法是改到哪條才換哪條。另外 C0 之後 v1 legacy、凍結的 v2、v3 三份組合會並存好幾個月。
- 提案一：完全不處理 F02（本人事實被編造）、F29（不邀約）、F30（不表態），只說「讓它們之後做起來安全」，但這三項正是「市場最好」的前提。
- 提案一（小）：CI 耗時寫 1m41s。我用同一條指令加 --deny-net 在本機實跑，結果 1,309 passed、0 failed，耗時 2m28s，所以每個 PR 實際多約 2–2.5 分鐘，不是 F21 估的 75 秒。
- 提案二：P6a 宣稱「card_policy 只照搬今天的行為、只比較結構本身」，卻同時把 48,842 字元去重重寫成 read 約 6–8K 加 write 約 4–5K，又把 questionBudget 交給伺服器。結構和措辭兩個變因混在同一個 A/B 裡，結果無法歸因，等於披著結構刀外衣的一次性 prompt 重寫。
- 提案二：兩段式的首卡延遲沒有證據，而且很可能變慢。寫卡呼叫要等 decision 那一行（中位數約 3.1 秒）才能開始，還要付一次 5.5 自適應思考的首字時間，再加每張卡約 1.6 秒，要壓在 8.5 秒內很樂觀。刪掉計畫的收益，提案三用 plan-off 一個臂就能拿到，不需要第二次呼叫。
- 提案二：P6b 要把兩條並行 NDJSON 合進 reframer，但 reframer 的扣費順序假設只有單一串流，例如 preChargeEvents／flushPreChargeEvents 和 first-anchor-wins（reframer.ts:803-811）。重試又要改成「只重跑寫卡」，WritePlan 得存進 recommendation_json。RPC 只檢查 JSON 是物件，不回決策另外檢查特定鍵（migration 20260902120000:127-148），所以「不需要 migration」說得通，但 send 路徑還沒用 postgres 測試核實。整體屬 R3，複雜度高。
- 提案二：P3 說 Step 3b 改成依選中卡的 sourceIndex 集合過濾，「仍然保持各卡段數相同」，這不成立。依集合過濾後，其他卡的段數可能比選中卡少；現行做法是依段數 slice（post_process.ts:1165-1195）。這是改動 Eric 2026-08-17 的決定，需要他拍板，提案一就正確標出了這一點。
- 提案二：P7 用「本次補充背景裡有沒有這個事實」來決定要不要留填空，這是語意判斷，依團隊原則應該由模型給標籤，提案沒有說清楚誰來判斷。舊 App 會直接顯示「［你的工作］」。P9 是 R3 的大量刪除，還要收回 critic 影子基線的決定。
- 提案三：prompt 本體、SHA 鎖和約 300 句逐字鏡像測試（F19、F20）完全沒動，Bruce 的「超大 prompt、無從下手」只解了一半。之後 P6b、P9 改 prompt 時，仍然要過舊的鎖和鏡像測試。
- 提案三：P3b 說要「刪除 recommendationPreview 整條管線」，但畫面還在讀 recommendationPreviewErrorMessage／Code（analysis_screen.dart:978,993,2858,2860；streaming_analyze_notifier.dart:80-81）來顯示錯誤，這部分要搬到新結構，不能直接刪。
- 提案三：P2 其實有改行為：BLOCKED 罐頭句改成送出前逐卡替換，而且那時 metrics 還沒到，只能用預設的熱度等級（guardrails.ts:340-366 依 enthusiasm 選罐頭句）；另外新增了非選中卡的暫存路徑。這些都在扣費敏感的 reframer 裡加新分支，說成「不改行為」並不準確。
- 提案三：P6a 的「移到推薦卡之後」臂和 stream_prompt.ts:88 衝突，那一行要求每張卡都依計畫分枝寫，所以這個臂必須改 prompt 文字，選中卡會在沒有計畫的情況下寫成。P3a 標成「不可獨立回滾」也不合理，純整理一定可以回滾。品質洞 F02、F29、F30、F16 全部不處理。
- 三個方案共同的問題：首卡 8.5 秒、決定 3 秒都是黑箱從模型呼叫開始算的數字，不含 OCR、付費用戶的 RevenueCat 預同步（上限 20 秒）、auth 和建立 run，真機的體感時間未核實。另外，三個方案都沒先查非推薦風格卡實際被複製的比例，就在討論卡數；只有提案三把這件事交給遙測。

### 評審 2（產品負責人角度）

| 方案 | 用戶價值 | 品質 | 延遲 | 防退步 | 工作量可行 | 可共用 | 總分 |
|---|---|---|---|---|---|---|---|
| 回歸先行的勒殺式結構刀：先織網，再一片一片剝 | 7 | 6 | 7 | 9.5 | 6 | 6 | 7.2 |
| 讀判 → 伺服器政策 → 寫卡 → 送出即定稿（品質優先的分析結構刀） | 8.5 | 8.5 | 6.5 | 4.5 | 3 | 8 | 6.3 |
| 首卡即可用：對話分析的體感速度結構刀（延遲優先） | 8 | 4 | 9 | 8.5 | 8 | 6 | 7.5 |

**推薦計畫**：

骨幹用提案三（延遲優先）。prompt 部分整套嫁接提案一的「v3 平行組合加單一開關」，安全網也取提案一的版本；品質結構刀放在 v3 清乾淨之後，沿用提案二的結構化標籤和政策表思路；提案二的兩段式只留作離線實驗。

排序原則：
1. 先織網，再處理用戶有感的等待，再動 prompt。
2. 每個 PR 只做一件事，可以單獨 revert。
3. 伺服器程式的改動交給零成本重播網把關；prompt 的改動只進 v3，並且要過付費黑箱、差距超過雜訊帶才算數。
4. 全程不寫 migration，不使用 supabase db push。

階段 A：安全網（第 1 週，用戶無感）
- A1 CI 跑整個目錄（R2，要 Eric 對兩個 workflow 檔明確授權）。
  - flutter-ci.yml:64-76 的 analyze-chat 逐檔清單和 knowledge_selector，改成整個目錄執行：`deno test --allow-env --allow-read --ignore='supabase/functions/analyze-chat/*_postgres_test.ts' supabase/functions/analyze-chat supabase/functions/_shared/social`，再加 `deno check supabase/functions/analyze-chat/index.ts`。三個 analyze-chat postgres 測試已經在 PGlite 那一步，不用改。
  - deploy-edge-function.yml 在 Deploy 前加 Setup Deno 和同一條測試，寫法照 deploy-keyboard-assist.yml:35-40。
  - 本次本機用 --deny-net 實測：1,309 passed / 0 failed，耗時 2m27s。
- A2 四面重播網加 prompt 文字快照（R1）。
  - replay_test.ts 從 tools/analyze-v2-blackbox/out/2026-10-02-*/arm-C.json 取約 20 組 rawLines，透過 analyze_stream_handler.ts:193,569 的 callModel 注入點吐回去。比對四個面：模型請求、NDJSON 位元組、store 呼叫、log 的鍵。
  - golden 用 git archive 9adbf87c 產生，程序照 practice-chat/agency_flag_off_equivalence_test.ts。
  - 「串流卡等於 done 卡」先列進 known-fail 清單，指向階段 C。
  - rawLines 存的是解析後的物件，所以壞行和缺 done 要另外手做 fixture。
  - 同一批 3 條 clientText 輸出成 test/fixtures/analysis_stream/*.ndjson，給 Dart 測試一起讀。
  - prompt_snapshot_test.ts 存 base、v1、v2 production 三種不回選單和免費兩風格的渲染文字，並在同一個 commit 斷言舊快照的 sha 等於 analyze_system_prompt_test.ts:17 和 baseline_fixtures.json 的既有值。
- A3 量尺（R1，免費）。用已存的多輪結果算 A/A 雜訊帶寫進 README；Bruce 標約 24 張選中卡（直接送／要改／不送），拿來校正 critic。
- 鏡像測試（index_test 約 300 句）不做大批替換，改成壞了才換：每次被正當改動弄紅時，換成語意錨點，或交給快照或重播接手。必須先處理的時機只有兩個：搬動 analyze_chat_handler.ts 程式碼之前，以及刪除 my_message_flow.ts 和 my_message_prompt.ts 之前，因為這兩個檔都在 readAnalyzeChatScanCorpus 的清單裡（index_test.ts:28-46）。

階段 B：便宜修正和遙測（第 2 週）
- B1 刪掉 checkInput 和它唯一的呼叫點，另開一個 R2 小 PR（guardrails.ts:378-403、analyze_chat_handler.ts:893-901），用 F01 的四句正常對話當行為測試。
- B2 伺服器里程碑遙測，合併提案三 P1 和提案一 B1。內容：decision、firstCard、allCards、done 的時間點，fallbackUsed，retryCount，用 stream_terminal 回報 Sentry，修 sanitizer 的 32 鍵上限。App 端加 analysis_reply_ready 和 analysis_reply_copied 兩個 funnel 事件，先量現狀「要等 done 才能複製」的基線。
- B3 logAiCall 和 phase0 改走已有的 deps.waitUntil；RevenueCat fetch 加 AbortSignal.timeout。

階段 C：送出即定稿（伺服器，R2）
- 依提案三 P2 做：新增 card_finalize.ts，內容從 post_process 現有步驟抽出，非串流路徑也呼叫同一個函式。
  - Step 3b 維持位置裁段，只是提前到送出時做，所以不需要 Eric 重新決定。
  - BLOCKED 改成送出前逐張替換，不刪除。
  - mergeFinalResult 改成白名單，absorbMetrics 補吸收 psychology。
- 重播的 known-fail 改成必過，golden 的差異只能有 psychology 和熱度這兩類。
- 補一個「選中卡一直沒到，暫存卡怎麼收尾」的重播案。

階段 D：App 逐件到齊（R2，TestFlight 交付）
- 依序做提案三的 P3a（兩個 switch 合併）、P3b（首卡可以複製、decision 事件直接渲染 AnalysisDecisionCard、coach_hint 改讀頂層欄位）、P4（只留 StreamProgressTicker 加共用 skeleton、heartbeat 不顯示、續接時保留卡片、修正重試用完的死路）。
- recommendationPreview 不能直接刪，要先搬：analysisRunId 的取得（streaming_analyze_notifier.dart:446-451）、重試時的部分結果判斷（:501、:546-560、:607）、額度錯誤欄位（analysis_screen.dart:978-993、2858-2860），都要先移到 partial 上。
- 驗收：Eric 用真機確認首卡出現時就能複製；開關飛航模式後卡片不會消失。

階段 E：prompt 勒殺（v3）
- 照提案一 C0 到 C5 的順序：
  1. C0 v3 骨架，初始內容和 v2 逐位元組相同，由 ANALYZE_PROMPT_V3 開關控制，開關的三種值下四個面都要綠。
  2. C1 只刪不加（死規則、照抄範例、PUA 範例、品類詞）。
  3. C4 加 plan-off 和 plan-after-selected 兩個臂，量完再決定發散計畫的去留。
  4. C2 單一輸出契約，done 只當結束訊號。
  5. C3 每組矛盾、每個 enum 只留一個負責方。
- 每一片都要過 T2：v2 對 v3 各 ≥3 輪，差距超過雜訊帶才算數。每次付費都要 Eric 說「跑」，翻開關也要他逐次核准。
- 提案三 P9 的 done 精簡併進 C2，不再對 v2 打條件補丁。

階段 F：品質結構刀（在 v3 上做，每一項都要 Eric 先拍板）
- F02 本人事實：讀判輸出 selfFactNeeded，卡片改成填空標記，由伺服器逐字檢查標記存在。
- F29、F30：inviteReadiness 和 herQuestionType 由伺服器政策表決定，推廣 no_send_decision 的「伺服器給選單、模型選 enum」模式。
- F04：送出用戶自己最後幾則訊息。
- 提案二的讀判／寫卡兩段式只當離線 RW 臂來量，首卡不慢於 8.5 秒、品質不輸現狀才考慮接上。

階段 G：清理與共用（等第二個使用者出現才抽）
- B5 刪掉 App 不送的請求形狀（回 410）。
- 開場救星和新話題的 legacy 管線，等設好最低 App 版本再退役。
- 等第二處真的要改同一段程式時，再抽 text_metrics、exactly_once 純函式、client NDJSON helper。

最先做的三步：
1. 請 Eric 授權 A1，範圍只限 flutter-ci.yml 和 deploy-edge-function.yml 的上述改動。PR CI 綠了，並在草稿分支故意弄壞一條 reframer_test，確認 CI 會轉紅。
2. Bruce 開 A2：replay_test.ts、約 20 組 fixture、golden 從 9adbf87c 產生、prompt_snapshot_test.ts，並在同一個 commit 斷言舊雜湊相等。
3. 同一週平行做 B1（刪 checkInput 的小 PR）和 A3（雜訊帶腳本加 Bruce 標註 24 張卡），完成後直接進階段 C。

**方案中的瑕疵**：

- 提案一：N1 宣稱「1,309 passed，1m41s」。我用同一條指令加 --deny-net 重跑，1,309 passed / 0 failed 屬實，但本機耗時 2m27s；CI 每個 PR 實際增加的時間要另外估，因為目前已經有 11 個檔在跑。
- 提案一：排序拖慢了用戶價值。首卡可複製（B4）排在第 10 段，前面的 N4、N5、N6、B1、B5 都不是 B4 的前置；B4 真正依賴的只有 B3 送出即定稿和 N1、N3 的網。
- 提案一：N5 大批替換鏡像測試不在 v3 的關鍵路徑上。readAnalyzeChatScanCorpus（index_test.ts:26-53）只讀 17 個 handler 和 prompt 檔，加上底座 SYSTEM_PROMPT，不讀 stream_prompt.ts、reframer.ts、post_process.ts，所以新增的 v3 檔不會觸發它。真正會撞到的是 N6 從 analyze_chat_handler.ts 搬程式碼，以及 B5 刪除 my_message_flow.ts、my_message_prompt.ts，這兩個檔都在 corpus 清單裡，刪掉會讓 readTextFile 直接失敗。
- 提案一：B3 直接刪掉串流路徑在 done 時的 BLOCKED 罐頭替換，等於拿掉一層安全網，卻沒有列成 Eric 的決策。提案三改成送出前逐張替換，既保留安全語意，也不需要產品決定。
- 提案一：C2「App 要的舊版 finalResult 欄位全部由伺服器從事件組出」只標 M。這份資料是持久化的契約，App 詳情頁和 analysis_record_store 都在讀，改動規模被低估。
- 提案二：P0 說要把三個 analyze-chat 的 *_postgres_test 補進 PGlite 那一步，但 flutter-ci.yml 現在的 PGlite 步驟已經列了這三個（stream_runs_decision_kind、retention_cleanup、opener_two_stage）。
- 提案二：P2 把好幾件事捆在一起：刪安全閘門、Edge 請求形狀改回 410、刪 selectModel 和 whitelist、刪 widget。P3 也一樣：emit_card、merge 白名單、刪 BLOCKED、改 Step 3b、刪英文正規式。這違反 AGENTS.md「一個 PR 一個目的」，提案宣稱的「可以單獨 revert」不成立。
- 提案二：P3 寫「Step 3b 依選中卡的 sourceIndex 集合過濾，仍然保持各卡段數相同」，這句自相矛盾，因為用集合過濾無法保證段數相同；post_process.ts:1160-1195 現在只依位置裁掉較長的卡。這項改動也改了 Eric 2026-08-17 的決定，卻沒有列進 decisionsForEric。
- 提案二：P5 直接改生產 prompt（sourceIndex 改成 sourceId），沒有開關保護，還和 client 端的 F04 改動、語料擴充放在同一個階段。
- 提案二：付費成本低估。每道閘門是 ≥3 輪 × 2 臂 × 31 案，約 186 次分析，乘 US$0.073 約 US$13.6；P5、P6a、P7、P8、P9 五步合計約 US$68 以上，還沒算評審，不是提案說的「十多美元」。
- 提案二：P6a 是從零重寫 48,842 字元的 prompt。P6b 要把兩條並行串流合流進同一個 reframer，還要中途改寫選中卡，而選中卡是用戶第一張看到的卡，改寫卻沒有設期限；被標成 R3，對兩人團隊來說實際可行性很低。
- 提案三：P3b 說要刪掉 recommendationPreview 整條管線，範圍低估。notifier 用它取得 analysisRunId（streaming_analyze_notifier.dart:446-451），重試時判斷有沒有部分結果也靠它（:501、:546-560、:607），畫面的額度升級路徑還讀 recommendationPreviewErrorCode（analysis_screen.dart:978-993、2858-2860）。這些都要先搬到 partial 上，不能直接刪。
- 提案三：P2 會暫存比選中卡早到的非選中卡。選中卡如果一直沒到，暫存的卡永遠不會送出，STREAM_INCOMPLETE_REPLY_OPTIONS 的語意也跟著改變，需要補一個重播案例。
- 提案三：P9 把「finalRecommendation.content 仍要填」只從 v2 拿掉。conversation_policy 屬於底座 SYSTEM_PROMPT（有雜湊鎖，非串流路徑也在用），這樣做又是一個 v2 條件補丁，正好是 F19 批評的做法；應該放進 v3 平行組合裡改。
- 提案三：F01（checkInput 誤擋正常對話，P1）沒有放進計畫，只說要另開 PR。P3a 是純整理，卻標成不能單獨 revert。整份提案也沒有回應 Bruce 的第二個擔心，也就是超大 prompt 難改。
- 三份共通的風險：部署前加測試步驟之後，任何 analyze-chat 測試紅掉都會擋下全部 8 支通用函式的部署。這可以接受，因為測試是封閉的，我已經用 --deny-net 全部跑過，但緊急修正時也得先修好測試或 revert。
- 已核實沒有問題的部分：提案一說 rawLines 是解析後的物件，屬實（arm-C.json 的 results[].rawLines 是 dict），所以壞行的案例要另外手做，提案二和提案三都沒注意到這點。提案二說 recommendation_json 可以多放鍵，也屬實：RPC 只檢查它是物件，以及不回決策的幾個特定鍵（20260902120000:127-148）。v2 的扣費錨點是 decision 事件（reframer.ts:868-881），所以首卡提早開放複製沒有計費風險。

