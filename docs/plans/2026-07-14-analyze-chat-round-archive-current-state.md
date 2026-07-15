# analyze-chat 分輪封存重設計 — 實作前現況核對

> **SUPERSEDED — 2026-07-15。** 本文只保留實作前的程式地圖；其中的產品假設與建議資料結構已被 `2026-07-15-analyze-chat-independent-records-implementation.md` 取代，不可再當成現行規格。

- 日期：2026-07-14
- 調查對象：docs/plans/2026-07-14-analyze-chat-round-archive-design.md 六項待驗證
- 方法：Grep 定位 + 段落 Read（大檔不整檔讀）

---

## Q1. 「補聊天紀錄」怎麼吃新片段 / 累積內容存在哪 / 資料形狀

**結論**：新片段是 **append 到既有 `Conversation.messages`（Hive 本地）**，不是離散存。重新分析時，預設把**整條累積逐字稿**送給模型（只有超過 15 輪、產生 summary 後才裁成 recent rounds）。與 `analysis_stream_runs`（那是 server 端 stream 續傳暫存）無關。

**證據**：
- UI 進入點「補聊天紀錄」按鈕：`lib/features/analysis/presentation/screens/analysis_screen.dart:7560`；輸入框 hint `lib/.../analysis_screen.dart:7696`（「貼上或輸入新的一則訊息…」）。
- 手打新訊息 → `_addMessage`：`lib/.../analysis_screen.dart:2557`，實際 append 在 `conversation.messages.add(newMessage)` `:2580`。
- 截圖辨識匯入 → `conv.messages.addAll(importedMessages)` `lib/.../analysis_screen.dart:2477`。
- 儲存層＝Hive 本地，`Conversation.messages : List<Message>`：`lib/features/conversation/domain/entities/conversation.dart:20-21`（`@HiveType(typeId: 0)`）。`Message`＝`@HiveType(typeId:1)`，欄位 `content/isFromMe/timestamp/enthusiasmScore/quotedReplyPreview`：`lib/features/conversation/domain/entities/message.dart:6-37`。
- 重新分析 `_runAnalysis`：`lib/.../analysis_screen.dart:3771`；`sourceMessages = conversation.messages`（全量，除非傳 `analysisMessageLimit`）`:3814-3818`。
- 是否裁切：`_buildSummaryAwareAnalysisContext` `:3081`；**沒有 summary 就原封送全量** `:3090-3095`；有 summary 才 `clipToRecentRounds(baseMessages, MemoryService.maxRecentRounds)` `:3097-3100`（`clipToRecentRounds` 定義 `lib/features/conversation/data/services/memory_service.dart:133`）。
- 相關持久欄位（都在 `conversation.dart`）：`lastAnalysisSnapshotJson`（序列化最新分析，供 UI 還原）`:54-55`；`lastAnalyzedMessageCount` `:58-59`；`lastAnalyzedCharCount`（計費 baseline）`:76-77`。

**對設計的意義**：新片段目前不是「離散一輪」，而是持續灌進同一個 `messages` 陣列，且**模型會吃到歷史逐字稿**——正是設計要根除的。要做離散分輪，須新增「每輪片段」的儲存結構，並在 `_runAnalysis` 送模型的 `sourceMessages` 只取「當輪未分析片段」。

---

## Q2. AI prompt 是否已注入對象耐久資料（特質／熱度／作戰板）

**結論**：**已注入**（`partnerSummary` → server 端 `## Partner Context`）。內含對象特質、熱度、興趣、備註。作戰板 mindmap 本身沒有另外序列化進 prompt，但它與注入內容同源（同一 partner aggregate）。設計要的「注入耐久資料」大體已存在，本次重點是**在裁掉逐字稿後確保它仍照送**。

**證據**：
- Server 組 prompt：`supabase/functions/analyze-chat/index.ts:6072-6074`
  `const partnerContextInfo = partnerSummary ? ["## Partner Context", partnerSummary].join("\n") : "";`，並拼進 `userPrompt`（`:6086`、`:6095`）與影像分析 prompt（`:6115`）。
- Client 產生 summary：`PartnerSummaryBuilder.build`：`lib/features/partner/domain/services/partner_summary_builder.dart:19-72`。序列化形狀（純文字、非 JSON）：
  - `[對象背景：<name>]` `:42`
  - `- 累計對話：N 段，M 則訊息，最後互動 <date>` `:44-47`
  - `- 最近熱度：<latestHeat>` `:49-51`
  - `- 興趣：…` `:52-54`／`- 性格：…` `:55-57`（＝traits/特質）
  - `- 你的備註 / 過往備註：…` `:59-67`
  - 上限 1500 grapheme／2000 code units（`kHardCharCap`/`kServerCodeUnitCap`）`:14-15`。
- 傳遞路徑：`_resolvePartnerSummary` → `partnerContextResolverProvider.resolve(conversation)`：`lib/.../analysis_screen.dart:3051-3053`；於 `analyzeConversation(... partnerSummary: _resolvePartnerSummary(conversation))` 送出：`:3920`、`:4182`。
- 資料來源＝從各對話快照聚合：`PartnerAggregateView aggregateOver`：`lib/features/partner/domain/extensions/partner_aggregates.dart:40-70`，逐一 `_parseSnapshot(c.lastAnalysisSnapshotJson)` `:48`，`latestHeat = descByDate.first.lastEnthusiasmScore` `:70`。
- 作戰板（mindmap）是**同源的 UI 衍生**（`lib/features/partner/domain/mindmap/mind_map_builder.dart`），未單獨進 prompt。

**對設計的意義**：耐久資料管線已在，且它**不依賴當輪逐字稿**（讀的是各對話的 `lastAnalysisSnapshotJson` 聚合）。改成「只送當輪片段」時 partnerSummary 可原樣保留，是設計「關係連續性靠耐久資料」的現成載體。注意：熱度來自「對話級」的 `lastEnthusiasmScore`，若分輪後每輪不再回寫 conversation 級快照，aggregate 會斷更——需在計畫中確認每輪分析仍更新聚合來源。

---

## Q3. 「展開全部 X 則訊息」控制項位置與資料來源

**結論**：在 `analysis_screen.dart:5590-5618`，資料源＝`conversation.messages`（Hive 全量訊息），僅在訊息數 > 5 時出現。

**證據**：
- 條件與 widget：`lib/.../analysis_screen.dart:5590`（`if (conversation.messages.length > 5)`）～`:5618`。
- toggle 狀態 `_showAllMessages`：`:5592-5593`。
- 文案：`:5611` `'展開全部 ${conversation.messages.length} 則訊息'`（資料源即 `conversation.messages.length`）。
- 逐字稿逐則渲染在其上方 `:5560-5589`（`_MessageBubble` 類），同樣吃 `conversation.messages`。

**對設計的意義**：這正是「舊輪次被埋、要展開才看到」的來源。新設計主畫面只顯示當前輪 → 這段整塊訊息列表需改為「只渲染當輪片段」，展開控制項可移除或改義為「進封存盒子」。

---

## Q4. partner ↔ conversation 資料層關係（盒子綁對象可行性）

**結論**：**可行**。Partner 與 Conversation 都在 Hive 本地、各自獨立 box；Conversation 以 `partnerId`（穩定字串 id）外鍵指向 Partner。一個 partner 對多個 conversation 已有現成查詢。可用 `partnerId` 當封存 key。唯一注意：舊資料可能 `partnerId == null`（A1 migration 遺留）需 fallback。

**證據**：
- `Conversation.partnerId : String?`：`lib/features/conversation/domain/entities/conversation.dart:69-70`（含註解說明 A1 migration 回填）。
- `Partner`＝`@HiveType(typeId:8)`，`id` 穩定字串：`lib/features/partner/domain/entities/partner.dart:12-16`。
- 一對多查詢：`ConversationRepository.listByPartner(partnerId)`：`lib/features/conversation/data/repositories/conversation_repository.dart:99-101`（`where c.partnerId == partnerId`）；provider family：`lib/features/partner/presentation/providers/partner_providers.dart:54`；計數：`lib/features/partner/data/repositories/partner_repository.dart:173`。
- 兩者各自 openBox：`lib/core/services/storage_service.dart:64`（Conversation box）、`:69`（Partner box），皆 AES 加密。
- 既有「對話級」封存先例（active/archived marker，非分輪）：`lib/features/conversation/data/repositories/conversation_archive_store.dart:64-153`，key 含 owner scope＋conversationId `:148-152`，存在 `StorageService.settingsBox`（`lib/features/conversation/data/providers/conversation_archive_providers.dart:9`）。

**對設計的意義**：「盒子綁對象、開新對話不清空」與現有模型完全相容——以 `partnerId` 為 key。但 legacy `partnerId==null` 對話要有降級 key（例：fallback 到 conversationId），否則這些對話的封存會全部撞在同一個 null 桶。

---

## Q5. 建議卡：累積疊加 vs 單一最新

**結論**：建議**狀態本身已是「單一最新、原地取代」**——`_finalRecommendation`、`_replyOptions` 都是單值欄位，每次分析直接覆寫、開跑前清空。真正「越疊越長」的是**逐字稿訊息列表**（Q3），不是建議卡。所以「建議改成原地更新最新一版」在狀態層幾乎零改動，改動面集中在把逐字稿限縮為當輪。

**證據**：
- 單值狀態欄位：`_replyOptions`（`Map<String, ReplyOption>?`）`lib/.../analysis_screen.dart:115`；`_finalRecommendation` `:129`。
- 每次分析覆寫：`_finalRecommendation = result.recommendation` `:814`、`:1422`、`:4063`；`_replyOptions = result.replyOptions` `:809`、`:1417`、`:4058`。
- 開跑前清空：`_replyOptions = null` `:937`。
- 渲染：`_buildRecommendationContent(FinalRecommendation)` `:4789`（吃單一 `_finalRecommendation`）。

**對設計的意義**：建議卡不需要大改就是「最新一版原地更新」。封存輪次要各自保留當時建議，則需在「歸檔那一刻」把當時的 `_finalRecommendation`/`_replyOptions`（或其序列化，如 `lastAnalysisSnapshotJson` 同格式）連同當輪片段一起寫進封存記錄。

---

## Q6. 5 輪 FIFO 封存放哪一層、是否需 migration

**結論**：**放 Hive 本地**最合適（與 partner/conversation/現有 archive 同層，符合隱私規則不上傳逐字稿）。**不需 Supabase migration**（server 端每次呼叫無狀態；`analysis_stream_runs` 只是續傳暫存）。Hive 有兩條路，建議走**既有 settingsBox 動態 Map 先例、免 build_runner**；若要型別安全則新增 adapter（下一個空 typeId＝**26**）需跑 build_runner。現有 `AnalysisHistoryEvent`（typeId 24）只存 metadata，**不能**當封存體。

**證據**：
- 現有 adapters 到 typeId 25 為止：`lib/core/services/storage_service.dart:33-58`（最後 `AnalysisHistoryKindAdapter() // typeId=25`）→ **下一個空號＝26**。
- 免 adapter 的動態 Map 先例：`HiveConversationArchiveStore` 用 `StorageService.settingsBox` 存 `Map<String,String>`，自帶 owner-scoped key、fail-open：`conversation_archive_store.dart:64-153`。分輪封存可比照，key＝`partnerId`，value＝JSON（含當輪 messages + 建議快照 + createdAt），FIFO 在程式碼裁到 5。
- 每輪封存體需要的內容（片段＋建議）已有序列化基礎：`Conversation.lastAnalysisSnapshotJson`（分析原始回應序列化）`conversation.dart:54-55` 可作建議快照格式參考。
- `AnalysisHistoryEvent` 欄位＝id/kind/createdAt/conversationId/subjectName/enthusiasmScore/gameStageLabel/profileId/roundIndex/temperatureScore/familiarityScore/relationshipStageLabel：`lib/features/analysis_history/domain/entities/analysis_history_event.dart:18-58`——**沒有逐字稿、沒有建議文本**，只能當時間軸 telemetry，無法承載「當時她說什麼＋AI 當時建議」。
- Server 無需 migration：`partnerSummary`/`compiledConversationText` 都是每次 request 現拼（Q2 證據），`analysis_stream_runs` 僅 stream 續傳（`supabase/functions/analyze-chat/stream_run_store.ts`）。

---

## 對設計的影響／風險提醒

1. **耐久資料管線已存在（Q2）是最大利多**：`partnerSummary` 已注入特質/熱度/興趣/備註，且不依賴當輪逐字稿。改「只送當輪片段」時可原樣保留——設計的「關係連續性靠耐久資料」有現成載體，工作量遠低於預期。
2. **熱度/特質聚合的更新來源要顧**：aggregate 讀的是每個 conversation 的 `lastAnalysisSnapshotJson` 與 `lastEnthusiasmScore`（partner_aggregates.dart:48/70）。若分輪後不再把當輪結果回寫 conversation 級快照，耐久資料會停止更新。計畫需定義「每輪分析完，什麼寫回 conversation 級（餵下次 partnerSummary）／什麼只進封存輪」。
3. **「當輪片段」需要新的邊界概念**：目前 `messages` 是單一長陣列，靠 `lastAnalyzedMessageCount` 切「已分析 vs 未分析」（conversation.dart:58-59）。分輪封存需要記錄「每一輪涵蓋哪些 message 區間」，否則歸檔時切不出乾淨的一輪。這是本案主要新結構。
4. **建議卡改動面小（Q5）**：狀態已是單值覆寫，主戰場是逐字稿渲染（Q3, analysis_screen.dart:5560-5618）與 CTA 版位重排，不是建議卡本身。
5. **legacy `partnerId==null` 的降級 key（Q4）**：封存以 partnerId 為 key，但舊對話可能無 partnerId，需 fallback（例：conversationId），避免全撞 null 桶。
6. **儲存實作建議走 settingsBox 動態 Map（Q6）**：比照 `HiveConversationArchiveStore`，免新增 adapter、免 build_runner、免動 typeId，且天然 owner-scoped；FIFO 5 輪在程式碼裁切。若團隊偏好型別安全再考慮 typeId 26 + build_runner。
7. **高風險區＋成本量測**：analyze-chat 屬 AI prompt/token/cost 高風險區（CLAUDE.md）。改「只送當輪片段」實際會**降低** token（不再送全逐字稿），但仍須量測 partnerSummary 佔比並跑 Codex 雙審才可宣稱 dogfood safe。
8. **`analysis_stream_runs` 不是累積存儲**：勿誤把它當歷史來源；它是 server stream 續傳暫存，與封存無關（Q1/Q6）。
