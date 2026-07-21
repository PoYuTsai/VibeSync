# 教練統一 Phase E — 前端合體 實作計畫

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans（或 subagent-driven-development）逐 Task 執行本計畫。

**Goal:** 從 `CoachChatCard` 抽出 scope 參數化的共用 `CoachSurface`，對象頁改掛同一聰明教練 engine（partner scope＝串流/多輪/釐清/成效首次落地夥伴層）；三顆新情境 chip 種入 `lifecyclePhase`＋prefill；client 全路徑送 `requestId`（重送同值）啟用 Phase C exactly-once。

**Architecture:** client 新增 `CoachScope` 值物件（`conversation:<id>` / `partner:<id>` scopeKey），controller/api/history 全改 scope-keyed；conversation scope 行為與今日對等，partner scope 走新組裝（無 analysisSnapshot/recentMessages，帶 partnerHint＋followUp 風格 context＋partner 成效 digest）。`CoachFollowUpSection` 變薄 wrapper（chip row＋openCoach entry 疊 `CoachSurface(scope: partner)`）；舊 coach_follow_up engine 凍結不刪（Phase F 才退場），舊卡靠 Phase D read-bridge 出現在 partner 歷史。

**Tech Stack:** Flutter/Riverpod/Hive、`package:uuid`、`flutter test --concurrency=1`。

**設計檔真相源:** `docs/plans/2026-07-21-coach-unification-design.md` §Phase E（line 92-95）、D-3/D-4 拍板（line 105-106）、Invariants（line 45-54）。

**鐵律（動碼前重申）:**
- 預填絕不 auto-send（chip 點擊只 prefill＋focus，送出永遠是用戶按的）。
- 釐清輪任何 scope 永不扣費（Invariant #3）；付費徽章/quota 語意不動（#5/#6）。
- 同一邏輯請求 requestId 重送保持同值、成功才 retire；(question, forceAnswer, lifecyclePhase, sessionId) 任一變＝新 intent＝新 requestId——否則撞 Phase C `input_hash` REPLAY_MISMATCH。
- telemetry/持久化只存卡片欄位形狀，不新增來源訊息欄位（Invariant #8）。
- 絕不 `git add pubspec.lock`。一 commit 一 concern、繁中 message、完成即 push。
- Phase E 屬高風險（requestId 重送穩定性、consent gate、deep-link 回歸）→ Codex adversarial APPROVED 才可稱 dogfood safe。
- 開發在分支 `claude/coach-unification-phase-e`，Codex APPROVED 後 fast-forward 併回 main。

**既有程式碼地標（2026-07-22 盤點）:**
- `CoachChatCard`（1408 行，硬綁 conversationId）：`lib/features/coach_chat/presentation/widgets/coach_chat_card.dart:22-41`（建構參數）、`:150-165`（providers）、`:441/:476`（consent gate）、`:475-484`（forceAnswer）、`:986-992`（outcome capture）、`:221/:830/:980/:1086/:1299`（扣費文案群）
- controller：`coachChatControllerProvider`＝`AsyncNotifierProvider.autoDispose.family<_, CoachChatResult?, String(conversationId)>`：`lib/features/coach_chat/data/providers/coach_chat_providers.dart:82-85`；`ask({question, analysisSnapshot, forceAnswer})` `:119-123`；session 管理 `:89-111`
- api：`lib/features/coach_chat/data/services/coach_chat_api_service.dart:218-249`（request body，**無 requestId/scope/lifecyclePhase**）、`:311-406`（NDJSON 串流）
- Edge schema 已就緒（Phase B）：`supabase/functions/coach-chat/schemas.ts:88`（**conversationId 頂層必填但 index.ts 未解引用**）、`:104-114`（lifecyclePhase/requestId(UUID lowercase)/scope）、superRefine `:135-146`（partner scope 只驗 scope.partnerId==頂層 partnerId if 非 null）
- unified repo（Phase D）：`lib/features/coach_chat/domain/repositories/coach_chat_repository.dart:19-25`（`listByScope/latestForScope/putUnified/deleteScope`，scope＝裸 String×2）；impl `lib/features/coach_chat/data/repositories/coach_chat_repository_impl.dart`（partner read-bridge `:50-56`）
- `UnifiedCoachResult`（typeId 26）：`lib/features/coach_chat/domain/entities/unified_coach_result.dart`（`CoachScopeType` 常數 `:12`、conversation 映射 `:177`、partner 映射 `:209`）
- 對象頁現況：`lib/features/coach_follow_up/presentation/widgets/coach_follow_up_section.dart`（648 行；chip row `:381`、openCoach entry `:389/:602`、input sheet `:95-112`、regenerate 文案 `:490`）；掛載 `partner_detail_screen.dart:260/:553`
- deep-link：`partner_detail_screen.dart:70-77`（focus 常數）、`:884-1033`（`_CoachFocusOrchestrator`，`_open()` 直開 input sheet＋自帶 consent `:1007`）；mind-map `partner_mind_map_screen.dart:92-101`；routes `lib/app/routes.dart:76-78/:118-119/:130-138`
- requestId 範式（照抄生命週期）：`lib/features/opener/data/services/opener_request_session.dart:30`（同 intent 重試沿用、成功 retire）；`practice_chat_api_service.dart:407-422`（`requestIdFactory` 注入）
- 既有測試：`test/unit/features/coach_chat/`（api wire／providers／repository）、`test/widget/features/coach_chat/`、`test/widget/features/coach_follow_up/coach_follow_up_section_test.dart`、`test/widget/features/partner/partner_detail_coach_focus_test.dart`

**兩個先行拍板（依設計檔推導，執行時不再問）:**
1. partner scope 頂層 `conversationId` 送 sentinel `partner:<partnerId>`（server 未解引用、schema 只驗長度 ≤100；partnerId 為 UUID 36 字元安全）。**絕不**為此改 Edge schema——Phase E 改檔清單無 Edge 檔。
2. CoachSurface 統一渲染 `UnifiedCoachResult`（controller state 從 `CoachChatResult?` 泛化為 `UnifiedCoachResult?`；conversation 結果經 `:177` 既有映射）。歷史雙 scope 一律走 `listByScope`。

---

### Task 1: `CoachScope` 值物件

**Files:**
- Create: `lib/features/coach_chat/domain/entities/coach_scope.dart`
- Test: `test/unit/features/coach_chat/domain/entities/coach_scope_test.dart`

**Step 1: 寫失敗測試**：conversation/partner 兩型的 `key`（`conversation:c1`／`partner:p1`）、`wireConversationId`（conversation→原 id；partner→`partner:p1`）、`toWireJson()`（`{type:"conversation",conversationId:...}`／`{type:"partner",partnerId:...}`，鍵名對齊 `schemas.ts:20-28`）、值相等性（可當 Riverpod family key）。

**Step 2: 實作**

```dart
@immutable
class CoachScope {
  final String type; // CoachScopeType.conversation / .partner（重用 unified_coach_result.dart:12 常數）
  final String id;
  const CoachScope.conversation(this.id) : type = CoachScopeType.conversation;
  const CoachScope.partner(this.id) : type = CoachScopeType.partner;
  bool get isConversation => type == CoachScopeType.conversation;
  String get key => '$type:$id';
  String get wireConversationId => isConversation ? id : 'partner:$id';
  Map<String, dynamic> toWireJson() => isConversation
      ? {'type': 'conversation', 'conversationId': id}
      : {'type': 'partner', 'partnerId': id};
  // operator== / hashCode / toString ==> (type, id)
}
```

**Step 3: 跑測**：`flutter test test/unit/features/coach_chat/domain/entities/coach_scope_test.dart` → PASS

**Step 4: Commit** `教練統一 Phase E Task1：CoachScope 值物件（scopeKey/wire 映射）`＋push。

---

### Task 2: `CoachRequestIdSession`（exactly-once client 側）

**Files:**
- Create: `lib/features/coach_chat/data/services/coach_request_id_session.dart`
- Test: `test/unit/features/coach_chat/data/services/coach_request_id_session_test.dart`

**Step 1: 先讀範式** `opener_request_session.dart`（整檔 <100 行），照其生命週期不自創。

**Step 2: 寫失敗測試**：
- `begin(signature)` 首呼回新 UUID v4（lowercase）；同 signature 再呼（重試）回**同一** id；不同 signature（question/forceAnswer/lifecyclePhase/sessionId 任一變）回新 id。
- `retire()` 後同 signature 也回新 id（成功卡落地即 retire）。
- signature 由呼叫端組：`'$question|$forceAnswer|${lifecyclePhase ?? ''}|${sessionId ?? ''}'`。
- 建構子收 `String Function()? requestIdFactory`（測試注入定值，照 `practice_chat_api_service.dart:407-422` 範式）。

**Step 3: 實作**（單 scope 單 session：每個 controller instance 持有一個；欄位＝`_signature`/`_requestId`）。

**Step 4: 跑測 PASS → Commit** `教練統一 Phase E Task2：CoachRequestIdSession（同 intent 重送同值、成功 retire）`＋push。

---

### Task 3: API service 加 requestId/scope/lifecyclePhase（wire 相容鐵證）

**Files:**
- Modify: `lib/features/coach_chat/data/services/coach_chat_api_service.dart`
- Test: `test/unit/features/coach_chat/data/services/coach_chat_api_service_test.dart`

**Step 1: 寫失敗測試**（既有 wire body contract 測試檔內加）：
- 舊呼叫（不帶新參數）→ body **不含** `requestId`/`scope`/`lifecyclePhase` 鍵（缺席，非 null）——Phase B `.strict()` 下多送 null 也合法，但缺席才是 byte-identical。
- 帶 `scope: CoachScope.partner('p1')` → body `conversationId == 'partner:p1'`、`scope == {type:'partner',partnerId:'p1'}`、`partnerId == 'p1'`（superRefine `:138-140` 要求一致）。
- 帶 `scope: CoachScope.conversation('c1')` → `conversationId=='c1'`、`scope=={type:'conversation',conversationId:'c1'}`。
- 帶 `requestId`/`lifecyclePhase` → 原樣入 body；lifecyclePhase 只收 `chatStalled|prepareInvite|postDate`。

**Step 2: 實作**：`ask()` 加選填參數 `{String? requestId, CoachScope? scope, String? lifecyclePhase}`；scope 非 null 時 `conversationId` 用 `scope.wireConversationId` 蓋過。串流與 buffered 兩路徑（`:218-249` body 組裝單點）都吃到。

**Step 3: 跑測**：`flutter test test/unit/features/coach_chat/data/services/coach_chat_api_service_test.dart` → PASS

**Step 4: Commit** `教練統一 Phase E Task3：coach-chat API 送 requestId/scope/lifecyclePhase（舊 body 缺席鍵不變）`＋push。

---

### Task 4: controller/providers 泛化為 scope-keyed

**Files:**
- Modify: `lib/features/coach_chat/data/providers/coach_chat_providers.dart`
- Test: `test/unit/features/coach_chat/data/providers/coach_chat_providers_test.dart`

**Step 1: 先讀** `coach_chat_providers.dart` 整檔（341 行）與 repository impl 的 `put` vs `putUnified` trim/rollup 關係——若 facade `put` 只是 conversation-scope putUnified 包裝，controller 直接統一走 scope 寫入；若 trim 只在 facade，泛化時把 trim 移到 scope 核心（保 keep=10 對等，含 partner scope）。

**Step 2: 寫失敗測試**（既有 providers 測試檔改造＋新增）：
- family key 換 `CoachScope`：`coachChatControllerProvider(CoachScope.conversation('c1'))` 既有行為全綠（ask 持久化、釐清不刷 usage、session resume、forceAnswer flag——只改 key 形狀，語意零變）。
- partner scope：`ask(question:..., lifecyclePhase:'prepareInvite')` 不帶 analysisSnapshot 可送；持久化落 `putUnified`（`scopeType=='partner'`、`scopeId=='p1'`、`lifecyclePhase` 存卡）；歷史 `listByScope('partner','p1')` 讀回。
- requestId：mock api 捕獲 body——首送有 UUID；api 拋暫態錯後重試**同值**；成功後下一問**新值**；lifecyclePhase 變更→新值（防 REPLAY_MISMATCH）。
- 釐清輪 replay：釐清回應成功也 retire（下一輪追問是新 intent）。

**Step 3: 實作**：
- `coachChatControllerProvider/coachChatProgressProvider/coachChatHistoryProvider` family key `String conversationId` → `CoachScope`；`analysisSnapshot` 參數改選填（conversation 呼叫端照舊傳）。
- controller 持 `CoachRequestIdSession`；`ask()` 組 signature→`begin()`→傳 api；成功持久化後 `retire()`；catch 不 retire。
- controller state 型別泛化為 `UnifiedCoachResult?`：conversation 成功結果經 `unified_coach_result.dart:177` 映射；partner 直接建 unified（含 lifecyclePhase）。
- `coachChatHistoryProvider` 改 `repository.listByScope(scope.type, scope.id)`。
- partner scope 組裝：跳過 conversation-only providers（conversationProvider/dataQualityFlag/recentMessages/conversationSummary/analysisSnapshot 全缺席）；`partnerHint` 取自 partner 資料、`effectiveStyleContext` 用 `effective_style_prompt_builder.dart:121 buildForCoachFollowUp`、`outcomeInsightLines` 走 `coachingOutcomeDigestProvider(partnerId)`（已 partner-aware，`coach_chat_providers.dart:161`）。

**Step 4: 跑測**：`flutter test test/unit/features/coach_chat/ --concurrency=1` → 全綠

**Step 5: Commit** `教練統一 Phase E Task4：coach controller/providers 泛化 CoachScope＋requestId 生命週期` ＋push。

---

### Task 5: 抽出 `CoachSurface`（conversation 行為對等）

**Files:**
- Create: `lib/features/coach_chat/presentation/widgets/coach_surface.dart`（內容＝`coach_chat_card.dart` 搬移＋泛化）
- Delete: `lib/features/coach_chat/presentation/widgets/coach_chat_card.dart`（呼叫端一併改，不留 alias）
- Modify: 分析頁掛載點（grep `CoachChatCard(` 全 lib/ 找齊，預期在 analysis screen）
- Test: `test/widget/features/coach_chat/`（既有三檔改 import/建構）＋`coach_chat_card_error_copy_test.dart`

**Step 1: 搬檔泛化**，建構參數：

```dart
CoachSurface({
  required CoachScope scope,
  CoachChatAnalysisSnapshot? analysisSnapshot, // conversation scope 由分析頁照舊傳
  VoidCallback? onQuotaExceeded,
  VoidCallback? onReturnToAnalysis,            // partner scope 不傳＝不渲染返回鈕
  int focusRequestToken = 0,
  String? prefillText,
  String? lifecyclePhase,                      // 下一次 ask 隨送；chip 種入
})
```

- 內部 `conversationId` 引用全換 `scope`；conversation-only 區塊（dataQualityFlag、conversationProvider、返回分析鈕）以 `scope.isConversation` gate。
- 渲染型別換 `UnifiedCoachResult`（Task 4 已定）；釐清/forceAnswer/outcome capture UI 原樣保留、雙 scope 共用。
- consent gate（原 `:441/:476`）保留在 `_ask`/`_forceAnswer`，featureLabel 統一 `'Coach 1:1'`。

**Step 2: 分析頁呼叫端改 `CoachSurface(scope: CoachScope.conversation(conversationId), ...)`**，其餘參數照舊。

**Step 3: 跑測**：`flutter test test/widget/features/coach_chat/ test/unit/features/coach_chat/ --concurrency=1` → 全綠；`flutter analyze` 0 issue（抓漏改的呼叫端）。

**Step 4: Commit** `教練統一 Phase E Task5：CoachChatCard 抽出 scope 參數化 CoachSurface（conversation 對等）`＋push。

---

### Task 6: 對象頁薄 wrapper（三新 chip＋文案）

**Files:**
- Rewrite: `lib/features/coach_follow_up/presentation/widgets/coach_follow_up_section.dart`
- Test: `test/widget/features/coach_follow_up/coach_follow_up_section_test.dart`（重寫）

**Step 1: 寫失敗 widget 測試**：
- 渲染三 chip：「聊天卡住了」「想約她出來」「約完會之後」＋openCoach entry（「或直接問教練一個問題」保留）。
- caption＝「釐清免費，正式建議才扣 1 則」（取代舊 `:374/:490` 文案；全 widget 無「生成會扣 1 則」字樣）。
- 點 chip →（a）CoachSurface 收到對應 `lifecyclePhase`＋prefill 開場問題＋focus token 遞增；（b）**絕無** auto-send（mock controller 零 ask 呼叫）。
- 點 openCoach entry → focus token 遞增、無 lifecyclePhase、無 prefill。
- 舊 input sheet／`coachFollowUpControllerProvider.generate` 不再被本 widget 引用。

**Step 2: 實作**：section 變薄＝標題＋chip row＋caption＋`CoachSurface(scope: CoachScope.partner(partnerId))`。chip 定義：

```dart
const _chips = [
  (phase: 'chatStalled',  label: '聊天卡住了',   prefill: '我們聊天卡住了，接下來該怎麼辦？'),
  (phase: 'prepareInvite', label: '想約她出來',  prefill: '我想約她出來，該怎麼開口比較自然？'),
  (phase: 'postDate',     label: '約完會之後',   prefill: '剛約完會，接下來要怎麼經營比較好？'),
];
```

State＝`_pendingPhase`/`_prefill`/`_focusToken`，chip 點擊 setState 三者。quota 例外沿用 `CoachSurface.onQuotaExceeded` 開 paywall（對齊舊 `:1030-1031` 行為）。舊 coach_follow_up widgets/controller/api **不刪**（凍結，Phase F 退場）；其單元測試續留綠。

**Step 3: 跑測**：`flutter test test/widget/features/coach_follow_up/ --concurrency=1` → 全綠

**Step 4: Commit** `教練統一 Phase E Task6：對象頁改掛 CoachSurface＋三情境 chip（chatStalled/prepareInvite/postDate）`＋push。

---

### Task 7: deep-link 回歸（orchestrator 改 focus CoachSurface）

**Files:**
- Modify: `lib/features/partner/presentation/screens/partner_detail_screen.dart`（`_CoachFocusOrchestrator._open()` `:1000-1033`）
- Verify only: `partner_mind_map_screen.dart`、`lib/app/routes.dart`（參數鏈不變即零改）
- Test: `test/widget/features/partner/partner_detail_coach_focus_test.dart`

**Step 1: 寫失敗測試**：deep-link `focus=coachFollowUp&focusAction=openCoachInput` → 捲到教練區＋CoachSurface 輸入框獲 focus（token 遞增）；**不再**彈舊 input sheet；orchestrator 路徑不再自呼 consent（consent 只在 ask 時由 CoachSurface gate——修掉舊 `:1007` 的提前彈窗）。

**Step 2: 實作**：`_open()` 改為透過 section 的 focus 機制（傳遞 openCoachInput 意圖 → section bump `_focusToken`）；刪 orchestrator 內 `showCoachFollowUpInputSheet`/consent/telemetry generate 呼叫，telemetry 改記「開啟輸入」事件即可。mind-map/routes 只跑既有測試確認零回歸。

**Step 3: 跑測**：`flutter test test/widget/features/partner/ test/widget/features/analysis/analysis_screen_coach_prefill_test.dart --concurrency=1` → 全綠

**Step 4: Commit** `教練統一 Phase E Task7：coach deep-link 改 focus CoachSurface 輸入（不再開舊表單）`＋push。

---

### Task 8: 全套驗收＋Codex 審查包＋live e2e

**Step 1: 全套**：`flutter test --concurrency=1` 全綠、`flutter analyze` 0 issue。任何既有測試紅＝先修再往下。

**Step 2: live e2e（測試帳號 vibesync.test@gmail.com）**：
- 分析頁 conversation scope：問答＋釐清＋forceAnswer 全通、串流正常。
- 對象頁 partner scope：chip 種入→prefill→送出→釐清追問→正式建議扣 1；歷史含舊 follow-up 卡（read-bridge）。
- PAT 查 `coach_requests` 帳本：兩 scope 各留 settled row、`request_id` 與 client 送出一致、釐清 `charged=false`。

**Step 3: Codex adversarial 審查包**（直呼 codex:rescue，拿 verdict 才稱 safe）：
- base ref＝Task 1 起點 commit；檔案清單＝本計畫全部 Create/Modify/Delete。
- 高風險焦點（設計檔 §7）：requestId 重送穩定性（intent signature 完整性 vs `input_hash` 欄位、retire 時機、釐清輪）、consent gate（partner 路徑不漏 gate、不雙彈）、deep-link 回歸（focus/prefill/mind-map redirect）、conversation scope 行為對等（wire body 缺席鍵）。
- 佐證：flutter test/analyze 輸出＋live smoke 證據。

**Step 4: APPROVED 後** fast-forward 併回 main → push（自動出 build）→ 交 Eric 真機 dogfood 雙介面。

**Commit** `教練統一 Phase E 收尾：全套驗收＋Codex 審查證據落檔`（審查紀錄存 `docs/reviews/`）。
