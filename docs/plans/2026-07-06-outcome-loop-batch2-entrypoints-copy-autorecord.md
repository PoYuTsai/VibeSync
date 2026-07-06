# 案 1 批 2：opener/analyze 回報入口＋adviceId 自產＋複製自動記 pending 實作計畫

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
> 上游設計：`docs/plans/2026-07-06-outcome-loop-server-design.md`（APPROVED）。批 1 已 SHIPPED（cf4e9434..5d8f8de5）。本批＝表格「批 2」，純 client，低風險，單審。

**Goal:** 修正 recorder 同值重按會洗掉第二段答案的 bug；opener/analyze 補上 outcome 回報入口——複製當下自動記一筆 `sentAsIs/pending`、卡片區浮出收合的「後來呢？」晶片條（內嵌批 1 的 `CoachingOutcomeCaptureCard`）；並補 coach 卡 handler wiring widget test（批 1 備忘③）。

**Architecture:** `CoachingOutcomeRecorder` 泛化出三個共用方法（copy-pending upsert／第一段 userAction／第二段 reaction），coach 現有公開方法改為薄包裝；opener 的 adviceId＝`opener:<requestId>:<typeKey>`（requestId 復用扣費 idempotency 的 `OpenerRequestIdSession`，新增 `OpenerResult.requestId` 欄位進 JSON 快取序列化）；analyze 無現成穩定 id，adviceId＝`analyze:<conversationId>:<runKey>:<cardKey>`，runKey 在 `_applyAnalysisResult` 自產 UUID（潤飾稿另有獨立 `_polishRunKey`）。opener/analyze 的 event id 直接等於 adviceId，查詢復用現成 `coachingOutcomeEventProvider(id)` family（coach 卡批 1 就是這樣拿 event 的）。新共用收合條 `CoachingOutcomeFollowUpBar` 放 `lib/shared/widgets/`。

**Tech Stack:** Flutter 3.x / Riverpod / Hive（**不動 schema**）、uuid、flutter_test。

---

## 拍板與偵察既定事實（執行者不需重查）

### 拍板（Eric 已定，照做不重議）

- 同值短路：第一段重按同一顆 userAction 晶片→no-op（修現況「重建 event、洗回 pending、清 preview/note、刷 createdAt」的 bug）；第二段重按同值→no-op（修刷 createdAt）。
- 第一段改選不同值：保留既有 `outcomeTextPreview`/`userNote`，只換 userAction，outcome 依規則重算（sentAsIs/editedAndSent→pending、didNotSend/askedCoach→unknown）。**第二段答案被洗回 pending 是刻意行為**（改了第一段就重問反應），不要「保留舊 outcome」。
- 複製自動記冪等：該 adviceId **已有 event（不管什麼狀態）→ no-op**，絕不覆蓋使用者已作答內容。
- analyze 粒度＝卡片級：五型卡（cardKey＝extend/resonate/tease/humor/coldRead）、最終推薦整組（cardKey＝`final`）、潤飾稿（cardKey＝`polish`）各一個 adviceId；複製單句歸屬所屬卡片。
- toast 順帶提示回報（方向「已複製，發出後記得回來回報結果」），不彈窗。
- `lib/shared/widgets/reply_card.dart` 是死碼（零 production import）：不接線、不刪。
- **接受的邊際成本（記錄在案，不用修）**：
  - opener 舊快取（無 requestId）在 `fromJson` 時自產 UUID——每次解析都是新 id，舊草稿複製回報的冪等會斷（同一舊草稿重開畫面再複製會另開一筆 pending）。新生成的結果 requestId 進 JSON 持久化，穩定。
  - analyze 無穩定 id（已核實，見下）→ runKey 自產存 screen state；**重開畫面 snapshot restore 會重生 runKey，複製會另開一筆 pending**。接受。

### 偵察結果（含與原始描述不符處，已依實況修正）

- **「卡片下方浮出晶片條」在兩處無法照字面做**：opener 五卡在 `SizedBox(height: 220)` 橫向 ListView（`opening_rescue_screen.dart:1091-1107`）、analyze 五型卡在 `SizedBox(height: 360)` 橫向 ListView（`analysis_screen.dart:6236-6276`），固定高度卡內插晶片條必 overflow。→ 改為**橫向卡列正下方**放收合條（每個已複製的 cardKey 一條、帶型別 label）。最終推薦與潤飾稿是縱向區塊，照字面接在卡內下方。
- `_copyRecommendationText(text, label)`（`analysis_screen.dart:4383-4388`）是推薦區**所有**複製的單一漏斗——:4420（整組）、:4466（舊版 ①② 段）、:4590（結構化第 N 句）、:4612（整組訊息）全走它。hook 一處即可。
- 潤飾稿複製（:6666-6677）是 inline `Clipboard.setData`，**不走** helper，要另外接。
- 潤飾（`_optimizeMessage` :3861-3917）**不走** `_applyAnalysisResult` 漏斗，是獨立 API 呼叫、只設 `_optimizedMessage`——所以潤飾要自己的 `_polishRunKey`，不能共用 analysis runKey。
- analyze 穩定 id 查證：`AnalysisResult`（`lib/features/analysis/domain/entities/analysis_models.dart:840-889`）**無任何 id 欄位**；snapshot 持久化只存 `rawResponse` JSON（`_persistLatestAnalysisSnapshot` :1276-1301）；restore（:1207-1235）也走 `_applyAnalysisResult`。→ 確定自產 UUID。三個結果填入點（:780、:1228、:3773）全都經過 `_applyAnalysisResult`（:1251-1274），在那裡重生 runKey 一處搞定。
- `coachingOutcomeEventProvider(id)` family 已存在（`coaching_outcome_providers.dart:19-23`），coach 卡 :756-762 就用它。opener/analyze 令 eventId == adviceId 即可直接復用，**不需要新 provider**。
- `OpeningRescueScreen.copiedOpenerMessage(label)`（:68-70）其實忽略 label 參數、回傳固定長文案，且有測試鎖四個子字串（`opening_rescue_handoff_location_test.dart:81-88`）：改文案必須保留「已複製這則開場白／貼到交友軟體送出／她回覆後／點下方「她回覆了，開始分析對話」」四段語意。
- opener requestId 生命週期：`_requestSession.beginAttempt`（screen :503-511）→ `generateOpeners(requestId: attempt.requestId)`（:515-525）→ `markSuccess()`（:528）→ `saveDraft`（:530）→ setState `_result = result`（:544）。**requestId 必須在 saveDraft 之前掛上**（草稿序列化要帶到），不是字面上的 :544 賦值處。另 `visibleForAccess`（`opener_service.dart:139-157`）會重建 `OpenerResult`，requestId 必須在那裡傳遞，否則 free-tier 檢視／`saveLatest` 路徑掉 id。
- 既有測試「recording the same coach result overwrites the previous signal」（`coaching_outcome_providers_test.dart:203-225`）用**不同** userAction（unknown→didNotSend），同值短路不影響它，不用改。
- coach 卡 result view 是私有 `_CoachChatResultView`（`coach_chat_card.dart:738`），wiring widget test 需改成 `@visibleForTesting` 公開類名。
- 環境注意（同批 1）：`.g.dart` 缺就先 `dart run build_runner build --delete-conflicting-outputs`；WSL 下 `dart format` 壞，不要跑；**絕不 git add pubspec.lock**；每 task commit 後立即 push。

### 現況座標速查

| 東西 | 位置 |
|---|---|
| Recorder + providers | `lib/features/coaching_memory/data/providers/coaching_outcome_providers.dart`（recordCoachResultOutcome :68-98、recordCoachResultReaction :104-143） |
| Event entity | `lib/features/coaching_memory/domain/entities/coaching_outcome_event.dart:53-209`（permissive const 建構子 :97、`create` :112、summary 上限 160） |
| 共用晶片卡＋label helpers | `lib/shared/widgets/coaching_outcome_capture_card.dart`（`coachingUserActionLabel` :8、`coachingOutcomeSignalLabel` :16） |
| coach 卡接線 | `coach_chat_card.dart`：outcomeEvent watch :756-762、CoachingOutcomeCaptureCard :920-927、`_recordUserAction` :934、`_recordReaction` :972 |
| OpenerResult | `lib/features/opener/data/services/opener_service.dart:75-201`（建構子 :91、visibleForAccess :139、toJson :159、fromJson :170、server parse 建構 :401） |
| opener 快取 | `lib/features/opener/data/services/opener_result_cache_service.dart`（OpenerDraft.toJson 走 result.toJson :73、fromJson :83） |
| opener screen | `opening_rescue_screen.dart`：`_requestSession` :172、生成流程 :503-548、`_buildResults` :1029、橫卡列 :1091-1107、`_buildOpenerCard` :1442、複製按鈕 :1524-1536、`_showOpenerSnackBar` :603、`visibleOpenerCards`（回 `OpenerCardSpec`，欄位 type/content/isRecommended/isLocked）:87 |
| analysis screen | `analysis_screen.dart`（7591 行，**絕不整檔讀**）：`_applyAnalysisResult` :1251、`_copyRecommendationText` :4383、推薦區 Column :5860-5900、五型卡列 :6220-6276、潤飾稿複製 :6664-6679、`_buildHorizontalReplyCard` :7058-7077、`_optimizeMessage` :3861 |
| 五型卡 | `lib/features/analysis/presentation/widgets/reply_style_card.dart`（onCopy 簽名 `(String text, String snackBarMessage)` :14、整組複製 :199、單句 :266、私有 `_labels` :25） |

---

### Task 1: Recorder 同值短路＋改選保留 preview/note＋泛化（TDD）

**Files:**
- Modify: `lib/features/coaching_memory/data/providers/coaching_outcome_providers.dart`
- Create: `test/helpers/memory_coaching_outcome_repository.dart`（把既有測試的 `_MemoryOutcomeRepo` 抽成共用 fake，後面 Task 3/7 的 widget test 也要用）
- Modify: `test/unit/features/coaching_memory/data/providers/coaching_outcome_providers_test.dart`

**Step 1: 抽共用 fake**

把 `coaching_outcome_providers_test.dart:35-149` 的 `_MemoryOutcomeRepo` 整段搬到新檔並改名 `MemoryCoachingOutcomeRepository`（實作內容逐 byte 不變，只改類名＋加 import），原測試檔改 import 新 helper、刪本地類。

**連帶改動（漏了會編譯失敗，必做）**：刪本地類後，同測試檔還有兩處引用舊類名，一併改成 `MemoryCoachingOutcomeRepository`——
- `_container` 的參數型別 `required _MemoryOutcomeRepo repo`（test:152，共 1 處）→ `required MemoryCoachingOutcomeRepository repo`；
- 既有測試 body 內 6 處 `_MemoryOutcomeRepo()` 實例化 → `MemoryCoachingOutcomeRepository()`。

改完 `grep -n "_MemoryOutcomeRepo" test/unit/features/coaching_memory/data/providers/coaching_outcome_providers_test.dart` 必須零結果。跑下列指令確認搬遷零回歸——它會編譯整個 test 檔，任何漏改的舊類名引用都會在此被抓為編譯錯：

```bash
flutter test test/unit/features/coaching_memory/data/providers/coaching_outcome_providers_test.dart
```

**Step 2: 寫失敗的 unit tests**（加在同測試檔；需要可變 now 的測試自建 container）

```dart
// 檔頭 fixture 區新增：
CoachingAdviceContext _openerAdvice({String type = 'extend'}) {
  return CoachingAdviceContext(
    eventId: 'opener:req-1:$type',
    partnerId: 'partner-1',
    source: CoachingOutcomeSource.opener,
    adviceId: 'opener:req-1:$type',
    adviceType: type,
    suggestedMoveSummary: '妳週末也會去爬山嗎？',
  );
}

ProviderContainer _mutableNowContainer({
  required MemoryCoachingOutcomeRepository repo,
  required DateTime Function() now,
}) {
  return ProviderContainer(overrides: [
    coachingOutcomeRepositoryProvider.overrideWithValue(repo),
    coachingOutcomeNowProvider.overrideWithValue(now),
  ]);
}
```

```dart
group('批2 recorder 泛化', () {
  test('coachingOutcomeForUserAction：send 類→pending、未送類→unknown', () {
    expect(coachingOutcomeForUserAction(CoachingUserAction.sentAsIs),
        CoachingOutcomeSignal.pending);
    expect(coachingOutcomeForUserAction(CoachingUserAction.editedAndSent),
        CoachingOutcomeSignal.pending);
    expect(coachingOutcomeForUserAction(CoachingUserAction.didNotSend),
        CoachingOutcomeSignal.unknown);
    expect(coachingOutcomeForUserAction(CoachingUserAction.askedCoach),
        CoachingOutcomeSignal.unknown);
  });

  test('recordAdviceCopied 建立 sentAsIs/pending 事件', () async {
    final repo = MemoryCoachingOutcomeRepository();
    final c = _container(repo: repo, now: DateTime.utc(2026, 7, 6, 10));
    addTearDown(c.dispose);

    final event = await c
        .read(coachingOutcomeRecorderProvider)
        .recordAdviceCopied(_openerAdvice());

    expect(event, isNotNull);
    expect(event!.id, 'opener:req-1:extend');
    expect(event.source, CoachingOutcomeSource.opener);
    expect(event.adviceId, 'opener:req-1:extend');
    expect(event.adviceType, 'extend');
    expect(event.userAction, CoachingUserAction.sentAsIs);
    expect(event.outcome, CoachingOutcomeSignal.pending);
    expect(event.partnerId, 'partner-1');
    expect(c.read(coachingOutcomeDigestProvider('partner-1')).totalEvents, 1);
  });

  test('recordAdviceCopied 已有事件時 no-op，不覆蓋已作答內容', () async {
    final repo = MemoryCoachingOutcomeRepository();
    var current = DateTime.utc(2026, 7, 6, 10);
    final c = _mutableNowContainer(repo: repo, now: () => current);
    addTearDown(c.dispose);
    final recorder = c.read(coachingOutcomeRecorderProvider);

    await recorder.recordAdviceUserAction(
      advice: _openerAdvice(),
      userAction: CoachingUserAction.didNotSend,
      outcome: CoachingOutcomeSignal.unknown,
    );
    current = DateTime.utc(2026, 7, 6, 11);
    final copied = await recorder.recordAdviceCopied(_openerAdvice());

    expect(copied, isNull);
    final stored = repo.get('opener:req-1:extend')!;
    expect(stored.userAction, CoachingUserAction.didNotSend);
    expect(stored.createdAt, DateTime.utc(2026, 7, 6, 10));
  });

  test('第一段同值重按 no-op：不洗第二段、不刷 createdAt', () async {
    final repo = MemoryCoachingOutcomeRepository();
    var current = DateTime.utc(2026, 7, 6, 10);
    final c = _mutableNowContainer(repo: repo, now: () => current);
    addTearDown(c.dispose);
    final recorder = c.read(coachingOutcomeRecorderProvider);

    await recorder.recordAdviceCopied(_openerAdvice()); // sentAsIs/pending @10
    current = DateTime.utc(2026, 7, 6, 11);
    await recorder.recordAdviceReaction(
      eventId: 'opener:req-1:extend',
      outcome: CoachingOutcomeSignal.engaged,
    ); // engaged @11
    current = DateTime.utc(2026, 7, 6, 12);
    await recorder.recordAdviceUserAction(
      advice: _openerAdvice(),
      userAction: CoachingUserAction.sentAsIs, // 同值重按
      outcome: CoachingOutcomeSignal.pending,
    );

    final stored = repo.get('opener:req-1:extend')!;
    expect(stored.userAction, CoachingUserAction.sentAsIs);
    expect(stored.outcome, CoachingOutcomeSignal.engaged); // 第二段答案保住
    expect(stored.createdAt, DateTime.utc(2026, 7, 6, 11)); // 沒刷
  });

  test('第一段改選保留 preview/note、第二段刻意洗回 pending', () async {
    final repo = MemoryCoachingOutcomeRepository();
    final c = _container(repo: repo, now: DateTime.utc(2026, 7, 6, 12));
    addTearDown(c.dispose);
    await repo.put(CoachingOutcomeEvent(
      id: 'opener:req-1:extend',
      partnerId: 'partner-1',
      source: CoachingOutcomeSource.opener,
      adviceId: 'opener:req-1:extend',
      adviceType: 'extend',
      suggestedMoveSummary: '妳週末也會去爬山嗎？',
      userAction: CoachingUserAction.sentAsIs,
      outcome: CoachingOutcomeSignal.engaged,
      outcomeTextPreview: '她回：真的假的你也爬山',
      userNote: '這招對戶外掛有效',
      createdAt: DateTime.utc(2026, 7, 6, 10),
    ));

    final updated = await c
        .read(coachingOutcomeRecorderProvider)
        .recordAdviceUserAction(
          advice: _openerAdvice(),
          userAction: CoachingUserAction.editedAndSent,
          outcome: coachingOutcomeForUserAction(
            CoachingUserAction.editedAndSent,
          ),
        );

    expect(updated.userAction, CoachingUserAction.editedAndSent);
    expect(updated.outcome, CoachingOutcomeSignal.pending); // 重問反應
    expect(updated.outcomeTextPreview, '她回：真的假的你也爬山'); // 保留
    expect(updated.userNote, '這招對戶外掛有效'); // 保留
    expect(updated.createdAt, DateTime.utc(2026, 7, 6, 12)); // 改選有寫入，刷新
  });

  test('第一段改選到未送類 outcome=unknown', () async {
    final repo = MemoryCoachingOutcomeRepository();
    final c = _container(repo: repo);
    addTearDown(c.dispose);
    final recorder = c.read(coachingOutcomeRecorderProvider);

    await recorder.recordAdviceCopied(_openerAdvice());
    final updated = await recorder.recordAdviceUserAction(
      advice: _openerAdvice(),
      userAction: CoachingUserAction.didNotSend,
      outcome: coachingOutcomeForUserAction(CoachingUserAction.didNotSend),
    );

    expect(updated.outcome, CoachingOutcomeSignal.unknown);
  });

  test('第二段同值重按 no-op：不刷 createdAt', () async {
    final repo = MemoryCoachingOutcomeRepository();
    var current = DateTime.utc(2026, 7, 6, 10);
    final c = _mutableNowContainer(repo: repo, now: () => current);
    addTearDown(c.dispose);
    final recorder = c.read(coachingOutcomeRecorderProvider);

    await recorder.recordAdviceCopied(_openerAdvice());
    current = DateTime.utc(2026, 7, 6, 11);
    await recorder.recordAdviceReaction(
      eventId: 'opener:req-1:extend',
      outcome: CoachingOutcomeSignal.cold,
    );
    current = DateTime.utc(2026, 7, 6, 12);
    final again = await recorder.recordAdviceReaction(
      eventId: 'opener:req-1:extend',
      outcome: CoachingOutcomeSignal.cold, // 同值
    );

    expect(again, isNotNull);
    expect(repo.get('opener:req-1:extend')!.createdAt,
        DateTime.utc(2026, 7, 6, 11));
  });

  test('coach 薄包裝：重按同一顆第一段晶片不再洗掉第二段（批2核心 bug 修）',
      () async {
    final repo = MemoryCoachingOutcomeRepository();
    final c = _container(repo: repo);
    addTearDown(c.dispose);
    final recorder = c.read(coachingOutcomeRecorderProvider);

    await recorder.recordCoachResultOutcome(
      result: _coachResult(),
      userAction: CoachingUserAction.editedAndSent,
      outcome: CoachingOutcomeSignal.pending,
    );
    await recorder.recordCoachResultReaction(
      result: _coachResult(),
      outcome: CoachingOutcomeSignal.cold,
    );
    await recorder.recordCoachResultOutcome(
      result: _coachResult(), // 重按同一顆
      userAction: CoachingUserAction.editedAndSent,
      outcome: CoachingOutcomeSignal.pending,
    );

    final stored = repo.get('coach:result-1')!;
    expect(stored.outcome, CoachingOutcomeSignal.cold); // 修前會被洗回 pending
  });
});
```

**Step 3: 跑測試確認失敗**

Run: `flutter test test/unit/features/coaching_memory/data/providers/coaching_outcome_providers_test.dart`
Expected: 編譯失敗（`CoachingAdviceContext`、`recordAdviceCopied` 等不存在）。

**Step 4: 實作**（providers 檔重構；`recordCoachResultOutcome`/`recordCoachResultReaction` 簽名與回傳型別**不變**）

```dart
// coachingOutcomeIdForCoachResult 之後、CoachingOutcomeRecorder 之前加：

/// 兩段式規則單點：send 類→pending（等第二段）、未送類→unknown（終態）。
CoachingOutcomeSignal coachingOutcomeForUserAction(CoachingUserAction action) {
  return action == CoachingUserAction.sentAsIs ||
          action == CoachingUserAction.editedAndSent
      ? CoachingOutcomeSignal.pending
      : CoachingOutcomeSignal.unknown;
}

/// 一則建議在 outcome 帳本裡的身分。opener/analyze 的 [eventId] 直接用
/// adviceId（一 advice 一 event）；coach 沿用 `coach:<resultId>`。
class CoachingAdviceContext {
  const CoachingAdviceContext({
    required this.eventId,
    this.partnerId,
    this.conversationId,
    required this.source,
    this.adviceId,
    this.adviceType,
    required this.suggestedMoveSummary,
  });

  final String eventId;
  final String? partnerId;
  final String? conversationId;
  final CoachingOutcomeSource source;
  final String? adviceId;
  final String? adviceType;
  final String suggestedMoveSummary;
}
```

Recorder 內部（coach 兩個舊方法的本體改為委派；invalidate 段抽 `_invalidateFor`，兩舊方法與新方法共用）：

```dart
class CoachingOutcomeRecorder {
  CoachingOutcomeRecorder(this._ref);

  final Ref _ref;

  /// 複製即自動記 pending。冪等：該 eventId 已有事件（不管狀態）→ no-op
  /// 回 null，絕不覆蓋使用者已作答內容。
  Future<CoachingOutcomeEvent?> recordAdviceCopied(
    CoachingAdviceContext advice,
  ) async {
    final repo = _ref.read(coachingOutcomeRepositoryProvider);
    if (repo.get(advice.eventId) != null) return null;
    final now = _ref.read(coachingOutcomeNowProvider);
    final event = CoachingOutcomeEvent.create(
      id: advice.eventId,
      partnerId: advice.partnerId,
      conversationId: advice.conversationId,
      source: advice.source,
      adviceId: advice.adviceId,
      adviceType: advice.adviceType,
      suggestedMoveSummary: clampSuggestedMoveSummary(
        advice.suggestedMoveSummary,
      ),
      userAction: CoachingUserAction.sentAsIs,
      outcome: CoachingOutcomeSignal.pending,
      createdAt: now(),
    );
    await repo.put(event);
    _invalidateFor(event);
    return event;
  }

  /// 第一段回報。同值重按→no-op 回既有事件（不洗第二段、不刷 createdAt）；
  /// 改選不同值→保留 preview/note、換 userAction、outcome 用呼叫端依
  /// [coachingOutcomeForUserAction] 算好的值（第二段答案刻意洗回）。
  Future<CoachingOutcomeEvent> recordAdviceUserAction({
    required CoachingAdviceContext advice,
    required CoachingUserAction userAction,
    required CoachingOutcomeSignal outcome,
  }) async {
    final repo = _ref.read(coachingOutcomeRepositoryProvider);
    final now = _ref.read(coachingOutcomeNowProvider);
    final existing = repo.get(advice.eventId);
    if (existing != null && existing.userAction == userAction) {
      return existing;
    }
    final event = existing == null
        ? CoachingOutcomeEvent.create(
            id: advice.eventId,
            partnerId: advice.partnerId,
            conversationId: advice.conversationId,
            source: advice.source,
            adviceId: advice.adviceId,
            adviceType: advice.adviceType,
            suggestedMoveSummary: clampSuggestedMoveSummary(
              advice.suggestedMoveSummary,
            ),
            userAction: userAction,
            outcome: outcome,
            createdAt: now(),
          )
        : CoachingOutcomeEvent(
            id: existing.id,
            partnerId: existing.partnerId,
            conversationId: existing.conversationId,
            source: existing.source,
            adviceId: existing.adviceId,
            adviceType: existing.adviceType,
            suggestedMoveSummary: existing.suggestedMoveSummary,
            userAction: userAction,
            outcome: outcome,
            outcomeTextPreview: existing.outcomeTextPreview,
            userNote: existing.userNote,
            createdAt: now(),
          );
    await repo.put(event);
    _invalidateFor(event);
    return event;
  }

  /// 第二段回報：只更新 outcome。沒有第一段紀錄、或第一段是未送類→回 null
  /// 不寫入；同值重按→no-op 回既有事件（不刷 createdAt）。
  Future<CoachingOutcomeEvent?> recordAdviceReaction({
    required String eventId,
    required CoachingOutcomeSignal outcome,
  }) async {
    final repo = _ref.read(coachingOutcomeRepositoryProvider);
    final now = _ref.read(coachingOutcomeNowProvider);
    final existing = repo.get(eventId);
    final action = existing?.userAction;
    if (existing == null ||
        (action != CoachingUserAction.sentAsIs &&
            action != CoachingUserAction.editedAndSent)) {
      return null;
    }
    if (existing.outcome == outcome) return existing;
    final updated = CoachingOutcomeEvent(
      id: existing.id,
      partnerId: existing.partnerId,
      conversationId: existing.conversationId,
      source: existing.source,
      adviceId: existing.adviceId,
      adviceType: existing.adviceType,
      suggestedMoveSummary: existing.suggestedMoveSummary,
      userAction: existing.userAction,
      outcome: outcome,
      outcomeTextPreview: existing.outcomeTextPreview,
      userNote: existing.userNote,
      createdAt: now(),
    );
    await repo.put(updated);
    _invalidateFor(updated);
    return updated;
  }

  Future<CoachingOutcomeEvent> recordCoachResultOutcome({
    required CoachChatResult result,
    required CoachingUserAction userAction,
    required CoachingOutcomeSignal outcome,
  }) {
    return recordAdviceUserAction(
      advice: _coachAdviceContext(result),
      userAction: userAction,
      outcome: outcome,
    );
  }

  Future<CoachingOutcomeEvent?> recordCoachResultReaction({
    required CoachChatResult result,
    required CoachingOutcomeSignal outcome,
  }) {
    return recordAdviceReaction(
      eventId: coachingOutcomeIdForCoachResult(result.id),
      outcome: outcome,
    );
  }

  CoachingAdviceContext _coachAdviceContext(CoachChatResult result) {
    return CoachingAdviceContext(
      eventId: coachingOutcomeIdForCoachResult(result.id),
      partnerId: result.partnerId,
      conversationId: result.conversationId,
      source: CoachingOutcomeSource.coach,
      adviceId: result.id,
      adviceType: result.mode,
      suggestedMoveSummary: _coachMoveSummary(result),
    );
  }

  void _invalidateFor(CoachingOutcomeEvent event) {
    _ref.invalidate(coachingOutcomeEventProvider(event.id));
    final partnerId = CoachingOutcomeEvent.normalizeScope(event.partnerId);
    if (partnerId != null) {
      _ref.invalidate(coachingOutcomesByPartnerProvider(partnerId));
      _ref.invalidate(coachingOutcomeDigestProvider(partnerId));
    } else {
      _ref.invalidate(coachingUnboundOutcomesProvider);
      _ref.invalidate(coachingUnboundOutcomeDigestProvider);
    }
  }

  /// 複製文/卡片內容進 summary 前先裁 160（entity create 超長會 throw）。
  static String clampSuggestedMoveSummary(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '建議內容';
    if (trimmed.length <= CoachingOutcomeEvent.maxSuggestedMoveSummaryLength) {
      return trimmed;
    }
    return trimmed
        .substring(0, CoachingOutcomeEvent.maxSuggestedMoveSummaryLength)
        .trimRight();
  }

  String _coachMoveSummary(CoachChatResult result) {
    // 原樣保留（:145-157），零改動
  }
}
```

**Step 5: 跑測試確認通過**

Run: `flutter test test/unit/features/coaching_memory/data/providers/coaching_outcome_providers_test.dart`
Expected: 既有 6 測項＋新 8 測項全 PASS。既有「overwrites the previous signal」測試（unknown→didNotSend，不同值）**不得改**、必須綠。

**Step 6: Commit**

```bash
git add lib/features/coaching_memory/data/providers/coaching_outcome_providers.dart \
  test/helpers/memory_coaching_outcome_repository.dart \
  test/unit/features/coaching_memory/data/providers/coaching_outcome_providers_test.dart
git commit -m "案1批2：recorder 同值短路＋改選保留 preview/note＋泛化 opener/analyze 記錄方法"
git push
```

---

### Task 2: `OpenerResult.requestId` 序列化與生成時掛載（TDD）

**Files:**
- Modify: `lib/features/opener/data/services/opener_service.dart`（OpenerResult :75-201）
- Modify: `lib/features/opener/presentation/screens/opening_rescue_screen.dart`（:515-528）
- Test: `test/unit/features/opener/data/services/opener_service_test.dart`（加 group）

這是 **JSON 快取序列化非 Hive adapter**，加欄位安全（`opener_result_cache_service.dart` 的 OpenerDraft.toJson/fromJson 直接走 `result.toJson()`/`OpenerResult.fromJson`，欄位自動跟上）。

**Step 1: 寫失敗的 tests**

```dart
group('OpenerResult.requestId（批2 outcome adviceId 基底）', () {
  test('toJson/fromJson round-trip 保留 requestId', () {
    const result = OpenerResult(
      openers: {'extend': '妳週末也會去爬山嗎？'},
      requestId: 'req-1',
    );
    final restored = OpenerResult.fromJson(result.toJson());
    expect(restored.requestId, 'req-1');
  });

  test('fromJson 缺 requestId（舊快取）自產非空 id，且每次解析各自成一 id', () {
    final json = const OpenerResult(openers: {'extend': 'hi'}).toJson()
      ..remove('requestId');
    final a = OpenerResult.fromJson(json);
    final b = OpenerResult.fromJson(json);
    expect(a.requestId, isNotNull);
    expect(a.requestId, isNotEmpty);
    expect(a.requestId, isNot(b.requestId)); // 接受的邊際成本，鎖住行為
  });

  test('visibleForAccess 對 free user 保留 requestId', () {
    const result = OpenerResult(
      openers: {'extend': 'hi', 'tease': 'yo'},
      recommendedPick: 'tease',
      requestId: 'req-1',
    );
    expect(
      result.visibleForAccess(isFreeUser: true).requestId,
      'req-1',
    );
  });

  test('withRequestId 只掛 id 不動其他欄位', () {
    const result = OpenerResult(
      openers: {'extend': 'hi'},
      recommendedPick: 'extend',
      costUsed: 5,
    );
    final tagged = result.withRequestId('req-9');
    expect(tagged.requestId, 'req-9');
    expect(tagged.openers, result.openers);
    expect(tagged.recommendedPick, 'extend');
    expect(tagged.costUsed, 5);
  });
});
```

**Step 2:** Run: `flutter test test/unit/features/opener/data/services/opener_service_test.dart` → Expected: 編譯失敗（requestId 具名參數不存在）。

**Step 3: 實作**

`opener_service.dart`：

1. 檔頭加 `import 'package:uuid/uuid.dart';`（pubspec 已有 uuid，**不動 pubspec**）。
2. `OpenerResult` 加欄位＋建構子參數（:85-98 區）：

```dart
  /// 批2：outcome 回報的 adviceId 基底（`opener:<requestId>:<type>`）。
  /// 生成時由 screen 掛上扣費 idempotency 的同一個 requestId；
  /// 舊快取缺席時 fromJson 自產（冪等斷裂為已拍板接受的邊際成本）。
  final String? requestId;

  const OpenerResult({
    this.profileAnalysis,
    required this.openers,
    this.pioneerPlan,
    this.recommendedPick,
    this.recommendedReason,
    this.costUsed = 3,
    this.requestId,
  });
```

3. `visibleForAccess`（:149-157 的 return）補 `requestId: requestId,`。
4. `toJson`（:159）加 `if (requestId != null) 'requestId': requestId,`。
5. `fromJson`（:170）加：

```dart
      requestId: switch (json['requestId']) {
        final String value when value.trim().isNotEmpty => value.trim(),
        _ => const Uuid().v4(),
      },
```

6. 加 `withRequestId`（放 `visibleForAccess` 之後）：

```dart
  OpenerResult withRequestId(String? requestId) {
    return OpenerResult(
      profileAnalysis: profileAnalysis,
      openers: openers,
      pioneerPlan: pioneerPlan,
      recommendedPick: recommendedPick,
      recommendedReason: recommendedReason,
      costUsed: costUsed,
      requestId: requestId ?? this.requestId,
    );
  }
```

注意 `generateOpeners` 的 server parse（:401 的 `return OpenerResult(...)`）**不掛** requestId——由 screen 掛（單一掛載點，避免 service 與 screen 各掛一次的歧義）。

`opening_rescue_screen.dart` :515-528：`generateOpeners` 回來後、`saveDraft` **之前**掛上：

```dart
      final service = OpenerService();
      final rawResult = await service.generateOpeners(
        // ...參數原樣不動...
        requestId: attempt.requestId,
      );
      // 結果已到手＝這次計費完結；之後任何失敗（存草稿等）都不該讓
      // 下一次生成沿用同 id 而被 server 當重試去重。
      _requestSession.markSuccess();
      // 批2：outcome adviceId 與扣費共用同一 requestId；必須在 saveDraft
      // 前掛上，草稿序列化才帶得到。
      final result = rawResult.withRequestId(attempt.requestId);
```

（其後 `saveDraft(result: result, ...)`、`_result = result` 原樣不動。）

**Step 4:** Run:

```bash
flutter test test/unit/features/opener/data/services/opener_service_test.dart \
  test/unit/features/opener/data/services/opener_result_cache_service_test.dart
```
Expected: 全 PASS（cache round-trip 測試不得壞）。

**Step 5: Commit**

```bash
git add lib/features/opener/data/services/opener_service.dart \
  lib/features/opener/presentation/screens/opening_rescue_screen.dart \
  test/unit/features/opener/data/services/opener_service_test.dart
git commit -m "案1批2：OpenerResult 增 requestId 序列化並在生成時掛載"
git push
```

---

### Task 3: 共用收合條 `CoachingOutcomeFollowUpBar`（TDD）

**Files:**
- Create: `lib/shared/widgets/coaching_outcome_follow_up_bar.dart`
- Test: `test/widget/shared/widgets/coaching_outcome_follow_up_bar_test.dart`

**Step 1: 寫失敗的 widget tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/coaching_memory/domain/entities/coaching_outcome_event.dart';
import 'package:vibesync/shared/widgets/coaching_outcome_capture_card.dart';
import 'package:vibesync/shared/widgets/coaching_outcome_follow_up_bar.dart';

CoachingOutcomeEvent _event({
  CoachingUserAction userAction = CoachingUserAction.sentAsIs,
  CoachingOutcomeSignal outcome = CoachingOutcomeSignal.pending,
}) {
  return CoachingOutcomeEvent(
    id: 'opener:req-1:extend',
    source: CoachingOutcomeSource.opener,
    suggestedMoveSummary: '妳週末也會去爬山嗎？',
    userAction: userAction,
    outcome: outcome,
    createdAt: DateTime(2026, 7, 6),
  );
}

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  testWidgets('event 為 null 時整條不渲染', (tester) async {
    await tester.pumpWidget(_wrap(CoachingOutcomeFollowUpBar(
      event: null,
      onUserActionSelected: (_) {},
      onOutcomeSelected: (_) {},
    )));
    expect(find.textContaining('後來呢？'), findsNothing);
  });

  testWidgets('預設收合：看得到標題、看不到晶片', (tester) async {
    await tester.pumpWidget(_wrap(CoachingOutcomeFollowUpBar(
      event: _event(),
      label: '延展',
      onUserActionSelected: (_) {},
      onOutcomeSelected: (_) {},
    )));
    expect(find.textContaining('後來呢？'), findsOneWidget);
    expect(find.textContaining('延展'), findsOneWidget);
    expect(find.byType(CoachingOutcomeCaptureCard), findsNothing);
  });

  testWidgets('複製自動記（sentAsIs/pending）收合標題顯示中性文案、不謊稱「照著發了」',
      (tester) async {
    await tester.pumpWidget(_wrap(CoachingOutcomeFollowUpBar(
      event: _event(), // sentAsIs / pending
      onUserActionSelected: (_) {},
      onOutcomeSelected: (_) {},
    )));
    expect(find.textContaining('已複製，發出後回報結果'), findsOneWidget);
    expect(find.textContaining('已記下：照著發了'), findsNothing);
  });

  testWidgets('未送類（didNotSend/unknown）收合標題報第一段動作', (tester) async {
    await tester.pumpWidget(_wrap(CoachingOutcomeFollowUpBar(
      event: _event(
        userAction: CoachingUserAction.didNotSend,
        outcome: CoachingOutcomeSignal.unknown,
      ),
      onUserActionSelected: (_) {},
      onOutcomeSelected: (_) {},
    )));
    expect(find.textContaining('已記下：沒有發'), findsOneWidget);
  });

  testWidgets('點標題展開後渲染共用晶片卡、再點收合', (tester) async {
    await tester.pumpWidget(_wrap(CoachingOutcomeFollowUpBar(
      event: _event(),
      onUserActionSelected: (_) {},
      onOutcomeSelected: (_) {},
    )));
    await tester.tap(find.textContaining('後來呢？'));
    await tester.pumpAndSettle();
    expect(find.byType(CoachingOutcomeCaptureCard), findsOneWidget);
    expect(find.text('照著發了'), findsOneWidget);
    await tester.tap(find.textContaining('後來呢？'));
    await tester.pumpAndSettle();
    expect(find.byType(CoachingOutcomeCaptureCard), findsNothing);
  });

  testWidgets('展開後晶片回呼直通', (tester) async {
    CoachingOutcomeSignal? got;
    await tester.pumpWidget(_wrap(CoachingOutcomeFollowUpBar(
      event: _event(),
      onUserActionSelected: (_) {},
      onOutcomeSelected: (s) => got = s,
    )));
    await tester.tap(find.textContaining('後來呢？'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('有接話'));
    expect(got, CoachingOutcomeSignal.engaged);
  });

  testWidgets('已有第二段答案時收合標題帶回報狀態', (tester) async {
    await tester.pumpWidget(_wrap(CoachingOutcomeFollowUpBar(
      event: _event(outcome: CoachingOutcomeSignal.engaged),
      onUserActionSelected: (_) {},
      onOutcomeSelected: (_) {},
    )));
    expect(find.textContaining('有接話'), findsOneWidget);
  });
}
```

**Step 2:** Run: `flutter test test/widget/shared/widgets/coaching_outcome_follow_up_bar_test.dart` → Expected: 編譯失敗。

**Step 3: 最小實作**

```dart
// lib/shared/widgets/coaching_outcome_follow_up_bar.dart
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../features/coaching_memory/domain/entities/coaching_outcome_event.dart';
import 'coaching_outcome_capture_card.dart';

/// 複製過建議後浮出的收合「後來呢？」條（opener / analyze 共用）。
/// [event] 為 null（尚未複製）時整條不渲染；展開後內嵌批 1 的
/// [CoachingOutcomeCaptureCard]，持久化仍由呼叫端 handler 負責。
class CoachingOutcomeFollowUpBar extends StatefulWidget {
  const CoachingOutcomeFollowUpBar({
    super.key,
    required this.event,
    this.label,
    required this.onUserActionSelected,
    required this.onOutcomeSelected,
  });

  final CoachingOutcomeEvent? event;

  /// 卡片型別短標（例：「延展」「AI 推薦回覆」），區分同一區多條。
  final String? label;
  final ValueChanged<CoachingUserAction> onUserActionSelected;
  final ValueChanged<CoachingOutcomeSignal> onOutcomeSelected;

  @override
  State<CoachingOutcomeFollowUpBar> createState() =>
      _CoachingOutcomeFollowUpBarState();
}

class _CoachingOutcomeFollowUpBarState
    extends State<CoachingOutcomeFollowUpBar> {
  bool _expanded = false;

  String _statusText(CoachingOutcomeEvent event) {
    final outcome = event.outcome;
    // 有第二段實際反應（engaged/cold/noReply/negative）→ 確定狀態。
    if (outcome != CoachingOutcomeSignal.pending &&
        outcome != CoachingOutcomeSignal.unknown) {
      return '已記下：${coachingOutcomeSignalLabel(outcome)}';
    }
    // 未送類（didNotSend/askedCoach）→ outcome==unknown，終態，報第一段動作。
    // 註：本流程 outcome==unknown 一律配非 unknown 的 userAction（copy 記
    // sentAsIs/pending、第一段未送類記 didNotSend|askedCoach/unknown），
    // 故舊版 `userAction==unknown → '回報一下結果'` 是走不到的 dead branch，
    // 本批移除。
    if (outcome == CoachingOutcomeSignal.unknown) {
      return '已記下：${coachingUserActionLabel(event.userAction)}';
    }
    // outcome==pending：可能是「複製自動記」的 sentAsIs，也可能是使用者手選
    // sentAsIs/editedAndSent 但還沒回報反應。現有欄位無法區分「自動記」與
    // 「手選」的 sentAsIs（兩者都是 sentAsIs/pending，無旗標），故統一用
    // outcome==pending 當 proxy 顯示中性文案——寧可對「已手選但沒回報反應」
    // 的使用者也顯示中性提示，也不對「只複製、沒真的確認發出」的使用者謊稱
    // 「已記下：照著發了」。使用者一旦回報第二段反應就落入上面的確定狀態分支。
    // 接受決策：手選「照著發了」但尚未答第二段時，收合標題仍顯示中性文案。
    return '已複製，發出後回報結果';
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    if (event == null) return const SizedBox.shrink();

    final title =
        widget.label == null ? '後來呢？' : '後來呢？（${widget.label}）';
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.flag_outlined,
                    size: 16,
                    color: AppColors.ctaStart,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$title・${_statusText(event)}',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.onBackgroundPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: AppColors.onBackgroundSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: CoachingOutcomeCaptureCard(
                event: event,
                onUserActionSelected: widget.onUserActionSelected,
                onOutcomeSelected: widget.onOutcomeSelected,
              ),
            ),
        ],
      ),
    );
  }
}
```

（若 `AppColors.ctaStart` 不是 const，把 `const Icon` 的 const 拿掉即可——以 analyze/opener 檔內現有用法為準。展開收合不加動畫，**零無限 repeat** 鐵則自動滿足。）

**Step 4:** Run: `flutter test test/widget/shared/widgets/coaching_outcome_follow_up_bar_test.dart` → Expected: 7 tests PASS。

**Step 5: Commit**

```bash
git add lib/shared/widgets/coaching_outcome_follow_up_bar.dart \
  test/widget/shared/widgets/coaching_outcome_follow_up_bar_test.dart
git commit -m "案1批2：新增收合式「後來呢？」回報條共用元件"
git push
```

---

### Task 4: opener 複製自動記 pending＋toast 文案＋晶片條接線

**Files:**
- Modify: `lib/features/opener/presentation/screens/opening_rescue_screen.dart`
- Modify: `test/unit/features/opener/presentation/opening_rescue_handoff_location_test.dart`（copiedOpenerMessage 斷言）
- Test（新增）: adviceId 靜態 helper 斷言加進 `opening_rescue_locked_cards_test.dart` 同層新檔或既有檔一個 group（照該目錄慣例＝純 static function unit test）

**Step 1: 寫失敗的 tests**

copiedOpenerMessage 文案測試（改 `opening_rescue_handoff_location_test.dart:81-88`，四個既有 contains 保留、加一個）：

```dart
  test('copy snackbar tells user the next opener step', () {
    final message = OpeningRescueScreen.copiedOpenerMessage('延展');

    expect(message, contains('已複製這則開場白'));
    expect(message, contains('貼到交友軟體送出'));
    expect(message, contains('回來回報結果')); // 批2新增
    expect(message, contains('她回覆後'));
    expect(message, contains('點下方「她回覆了，開始分析對話」'));
  });
```

adviceId helper 測試（加在同檔新 group）：

```dart
  group('openerAdviceIdFor', () {
    test('組合 opener:<requestId>:<type>', () {
      expect(
        OpeningRescueScreen.openerAdviceIdFor(
            requestId: 'req-1', type: 'tease'),
        'opener:req-1:tease',
      );
    });

    test('requestId 缺席回 null（不記錄、不渲染晶片條）', () {
      expect(
        OpeningRescueScreen.openerAdviceIdFor(requestId: null, type: 'extend'),
        isNull,
      );
      expect(
        OpeningRescueScreen.openerAdviceIdFor(requestId: '  ', type: 'extend'),
        isNull,
      );
    });
  });
```

**Step 2:** Run: `flutter test test/unit/features/opener/presentation/opening_rescue_handoff_location_test.dart` → Expected: FAIL（helper 不存在＋文案沒有新句）。

**Step 3: 實作**

imports（照鄰近 import 排序慣例插入；`dart:async` 若未 import 則補，`unawaited` 需要）：

```dart
import '../../../../shared/widgets/coaching_outcome_capture_card.dart';
import '../../../../shared/widgets/coaching_outcome_follow_up_bar.dart';
import '../../../coaching_memory/data/providers/coaching_outcome_providers.dart';
import '../../../coaching_memory/domain/entities/coaching_outcome_event.dart';
```

`OpeningRescueScreen`（StatefulWidget 類）statics 區（`copiedOpenerMessage` 附近）：

```dart
  static String copiedOpenerMessage(String label) {
    return '已複製這則開場白。貼到交友軟體送出，發出後記得回來回報結果；'
        '她回覆後，點下方「她回覆了，開始分析對話」。';
  }

  /// 批2：opener outcome 事件的 adviceId（＝eventId）。
  /// requestId 缺席→null＝不自動記、不渲染晶片條（防禦，正常路徑必有）。
  static String? openerAdviceIdFor({
    required String? requestId,
    required String type,
  }) {
    final normalized = requestId?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    return 'opener:$normalized:$type';
  }
```

State 內新增（放 `_buildOpenerCard` 附近）：

```dart
  String? _openerAdviceId(String type) => OpeningRescueScreen.openerAdviceIdFor(
        requestId: _result?.requestId,
        type: type,
      );

  CoachingAdviceContext? _openerAdviceContext({
    required String type,
    required String content,
  }) {
    final adviceId = _openerAdviceId(type);
    if (adviceId == null) return null;
    return CoachingAdviceContext(
      eventId: adviceId,
      partnerId: widget.partnerId,
      source: CoachingOutcomeSource.opener,
      adviceId: adviceId,
      adviceType: type,
      suggestedMoveSummary: content,
    );
  }

  Future<void> _recordOpenerCopy({
    required String type,
    required String content,
  }) async {
    final advice = _openerAdviceContext(type: type, content: content);
    if (advice == null) return;
    try {
      await ref.read(coachingOutcomeRecorderProvider).recordAdviceCopied(advice);
    } catch (_) {
      // 記錄失敗不擋複製主流程，也不打擾使用者。
    }
  }

  Future<void> _recordOpenerUserAction({
    required String type,
    required String content,
    required CoachingUserAction action,
  }) async {
    final advice = _openerAdviceContext(type: type, content: content);
    if (advice == null) return;
    try {
      await ref.read(coachingOutcomeRecorderProvider).recordAdviceUserAction(
            advice: advice,
            userAction: action,
            outcome: coachingOutcomeForUserAction(action),
          );
      _showOpenerSnackBar('已記下「${coachingUserActionLabel(action)}」，不扣額度。');
    } catch (_) {
      _showOpenerSnackBar('暫時記不起來，晚點再試一次。');
    }
  }

  Future<void> _recordOpenerReaction({
    required String type,
    required CoachingOutcomeSignal signal,
  }) async {
    final adviceId = _openerAdviceId(type);
    if (adviceId == null) return;
    try {
      final updated = await ref
          .read(coachingOutcomeRecorderProvider)
          .recordAdviceReaction(eventId: adviceId, outcome: signal);
      if (updated == null) return;
      _showOpenerSnackBar('已記下「${coachingOutcomeSignalLabel(signal)}」，不扣額度。');
    } catch (_) {
      _showOpenerSnackBar('暫時記不起來，晚點再試一次。');
    }
  }
```

複製按鈕（:1524-1536 `_buildOpenerCard` 內）：

```dart
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: content));
                    unawaited(_recordOpenerCopy(type: type, content: content));
                    _showOpenerSnackBar(
                      OpeningRescueScreen.copiedOpenerMessage(label),
                    );
                  },
```

晶片條（`_buildResults` :1091-1107 的橫卡 `SizedBox(height: 220, ...)` 之後、「Recommended reason」之前插）：

```dart
        ..._buildOpenerOutcomeBars(openerCards),
```

```dart
  List<Widget> _buildOpenerOutcomeBars(List<OpenerCardSpec> openerCards) {
    final bars = <Widget>[];
    for (final card in openerCards) {
      if (card.isLocked) continue;
      final adviceId = _openerAdviceId(card.type);
      if (adviceId == null) continue;
      final event = ref.watch(coachingOutcomeEventProvider(adviceId));
      if (event == null) continue; // 沒複製過不浮出
      bars.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: CoachingOutcomeFollowUpBar(
          event: event,
          label: OpeningRescueScreen.openerTypeLabels[card.type] ?? card.type,
          onUserActionSelected: (action) => _recordOpenerUserAction(
            type: card.type,
            content: card.content,
            action: action,
          ),
          onOutcomeSelected: (signal) => _recordOpenerReaction(
            type: card.type,
            signal: signal,
          ),
        ),
      ));
    }
    if (bars.isEmpty) return const [];
    return [const SizedBox(height: 4), ...bars];
  }
```

（`OpenerCardSpec` 的欄位名以 :87 `visibleOpenerCards` 的實際定義為準；`_buildResults` 所在 State 是 ConsumerState，`ref.watch` 在 build 呼叫鏈內合法。）

**Step 4: 驗證**

```bash
flutter analyze lib/features/opener
flutter test test/unit/features/opener/
```
Expected: analyze 零 error；opener 全測試 PASS。

**Step 5: Commit**

```bash
git add lib/features/opener/presentation/screens/opening_rescue_screen.dart \
  test/unit/features/opener/presentation/opening_rescue_handoff_location_test.dart
git commit -m "案1批2：opener 複製自動記 pending＋回報晶片條接線"
git push
```

---

### Task 5: analyze 自產 runKey＋複製自動記 pending＋toast

**Files:**
- Modify: `lib/features/analysis/presentation/screens/analysis_screen.dart`（**7591 行，先 Grep 錨點再 Read 段落，絕不整檔讀**）

**Step 1: state 與 helper**

imports 補（uuid 已有 :12、`dart:async` 已有 :4）：

```dart
import '../../../../shared/widgets/coaching_outcome_capture_card.dart';
import '../../../../shared/widgets/coaching_outcome_follow_up_bar.dart';
import '../../../coaching_memory/data/providers/coaching_outcome_providers.dart';
import '../../../coaching_memory/domain/entities/coaching_outcome_event.dart';
```

State 欄位（`_lastAiResponse` 等鄰近宣告區）：

```dart
  /// 批2：本輪分析結果的 outcome 關聯鍵。AnalysisResult 無穩定 id
  ///（已核實 analysis_models.dart:840 無 id 欄位、snapshot 只存 rawResponse），
  /// 每次 _applyAnalysisResult 自產；重開畫面 restore 會重生→複製另開一筆
  /// pending，為已拍板接受的邊際成本。
  String? _analysisRunKey;

  /// 潤飾稿獨立 runKey（_optimizeMessage 不走 _applyAnalysisResult 漏斗）。
  String? _polishRunKey;
```

`_applyAnalysisResult`（:1251）方法體開頭加一行：

```dart
    _analysisRunKey = const Uuid().v4();
```

`_optimizeMessage`（:3861）兩處：開頭 `setState` 裡 `_optimizedMessage = null;` 後加 `_polishRunKey = null;`；成功 `setState`（:3913-3916）裡 `_optimizedMessage = result.optimizedMessage;` 後加 `_polishRunKey = const Uuid().v4();`。

adviceId／記錄 helpers（`_copyRecommendationText` 附近加）：

```dart
  String? _analyzeAdviceId(String cardKey) {
    final runKey = cardKey == 'polish' ? _polishRunKey : _analysisRunKey;
    if (runKey == null) return null;
    return 'analyze:${widget.conversationId}:$runKey:$cardKey';
  }

  Future<void> _recordAnalysisCopy({
    required String cardKey,
    required String copiedText,
  }) async {
    final adviceId = _analyzeAdviceId(cardKey);
    if (adviceId == null) return;
    final conversation = ref.read(conversationProvider(widget.conversationId));
    try {
      await ref.read(coachingOutcomeRecorderProvider).recordAdviceCopied(
            CoachingAdviceContext(
              eventId: adviceId,
              partnerId: conversation?.partnerId,
              conversationId: widget.conversationId,
              source: CoachingOutcomeSource.analyze,
              adviceId: adviceId,
              adviceType: cardKey,
              suggestedMoveSummary: copiedText,
            ),
          );
    } catch (_) {
      // 記錄失敗不擋複製主流程。
    }
  }
```

**Step 2: 三個複製觸點接線**

1. `_copyRecommendationText`（:4383-4388，推薦區單一漏斗，:4420/:4466/:4590/:4612 全走它）：

```dart
  void _copyRecommendationText(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    unawaited(_recordAnalysisCopy(cardKey: 'final', copiedText: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label，發出後記得回來回報結果')),
    );
  }
```

2. 五型卡父層 onCopy（`_buildHorizontalReplyCard` :7058-7077）：

```dart
      onCopy: (text, message) {
        unawaited(_recordAnalysisCopy(cardKey: type, copiedText: text));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$message，發出後記得回來回報結果'),
            duration: const Duration(seconds: 2),
          ),
        );
      },
```

（原 duration 1 秒對加長文案太短，改 2 秒。`reply_style_card.dart` 本身零改動——:199/:266 都經 onCopy 回父層。）

3. 潤飾稿 inline 複製（:6664-6679）：

```dart
                                      onPressed: () {
                                        Clipboard.setData(ClipboardData(
                                            text:
                                                _optimizedMessage!.optimized));
                                        unawaited(_recordAnalysisCopy(
                                          cardKey: 'polish',
                                          copiedText:
                                              _optimizedMessage!.optimized,
                                        ));
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                              content: Text(
                                                  '已複製草稿，發出後記得回來回報結果')),
                                        );
                                      },
```

**Step 3: 驗證**

```bash
flutter analyze lib/features/analysis
flutter test test/widget/features/analysis/ test/widget/screens/analysis_screen_test.dart
```
Expected: analyze 零 error；既有 analysis widget tests 全 PASS（本 step 只加 state 與複製 hook，不加 provider watch，不應動到既有渲染）。若有測試斷言舊 toast 文案（「已複製到剪貼簿」等），把斷言更新為新文案——語意變更是本批目的，**不是**回歸。

**Step 4: Commit**

```bash
git add lib/features/analysis/presentation/screens/analysis_screen.dart
git commit -m "案1批2：analyze 自產 runKey＋複製自動記 pending＋toast 提示回報"
git push
```

（若 Step 3 改了測試檔，一併 add。）

---

### Task 6: analyze 三區接上「後來呢？」晶片條

**Files:**
- Modify: `lib/features/analysis/presentation/screens/analysis_screen.dart`
- Modify: `lib/features/analysis/presentation/widgets/reply_style_card.dart`（僅 `_labels` 改公開 `labels`）

**Step 1: 回報 handlers＋共用 bar builder**（接在 Task 5 的 helpers 後）

```dart
  Future<void> _recordAnalysisUserAction({
    required String cardKey,
    required String summary,
    required CoachingUserAction action,
  }) async {
    final adviceId = _analyzeAdviceId(cardKey);
    if (adviceId == null) return;
    final conversation = ref.read(conversationProvider(widget.conversationId));
    try {
      await ref.read(coachingOutcomeRecorderProvider).recordAdviceUserAction(
            advice: CoachingAdviceContext(
              eventId: adviceId,
              partnerId: conversation?.partnerId,
              conversationId: widget.conversationId,
              source: CoachingOutcomeSource.analyze,
              adviceId: adviceId,
              adviceType: cardKey,
              suggestedMoveSummary: summary,
            ),
            userAction: action,
            outcome: coachingOutcomeForUserAction(action),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('已記下「${coachingUserActionLabel(action)}」，不扣額度。')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暫時記不起來，晚點再試一次。')),
      );
    }
  }

  Future<void> _recordAnalysisReaction({
    required String cardKey,
    required CoachingOutcomeSignal signal,
  }) async {
    final adviceId = _analyzeAdviceId(cardKey);
    if (adviceId == null) return;
    try {
      final updated = await ref
          .read(coachingOutcomeRecorderProvider)
          .recordAdviceReaction(eventId: adviceId, outcome: signal);
      if (updated == null || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('已記下「${coachingOutcomeSignalLabel(signal)}」，不扣額度。')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暫時記不起來，晚點再試一次。')),
      );
    }
  }

  Widget _buildAnalysisOutcomeBar({required String cardKey, String? label}) {
    final adviceId = _analyzeAdviceId(cardKey);
    if (adviceId == null) return const SizedBox.shrink();
    final event = ref.watch(coachingOutcomeEventProvider(adviceId));
    if (event == null) return const SizedBox.shrink(); // 沒複製過不浮出
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: CoachingOutcomeFollowUpBar(
        event: event,
        label: label,
        onUserActionSelected: (action) => _recordAnalysisUserAction(
          cardKey: cardKey,
          summary: event.suggestedMoveSummary,
          action: action,
        ),
        onOutcomeSelected: (signal) => _recordAnalysisReaction(
          cardKey: cardKey,
          signal: signal,
        ),
      ),
    );
  }
```

**Step 2: 三個渲染位**

1. 五型卡：`reply_style_card.dart` 的 `static const _labels`（:25-31）改名公開 `labels`（檔內引用同步改，`grep -n "_labels" reply_style_card.dart` 全換）。橫卡列 `SizedBox(height: 360, child: ListView(...))`（:6236-6276）的**收尾 `),` 之後**（仍在 `if (_replies != null ...)` spread 區內）插：

```dart
                              for (final type in const [
                                'extend',
                                'resonate',
                                'tease',
                                'humor',
                                'coldRead',
                              ])
                                if (_replies!.containsKey(type))
                                  _buildAnalysisOutcomeBar(
                                    cardKey: type,
                                    label: ReplyStyleCard.labels[type] ?? type,
                                  ),
```

2. 最終推薦：推薦區 Column（:5874-5899）內、`'🧠 ${_finalRecommendation!.psychology}'` 的 `Text` 之後插：

```dart
                                _buildAnalysisOutcomeBar(
                                  cardKey: 'final',
                                  label: 'AI 推薦回覆',
                                ),
```

3. 潤飾稿：潤飾卡 Column 內、「複製草稿」按鈕的 `SizedBox`（:6663-6680）之後插：

```dart
                                  _buildAnalysisOutcomeBar(
                                    cardKey: 'polish',
                                    label: '潤飾草稿',
                                  ),
```

（縮排以實際插入點鄰行為準；行號會因 Task 5 的編輯漂移，一律先 Grep 錨字串「複製草稿」「🧠」「height: 360」再插。）

**Step 3: 驗證**

```bash
flutter analyze lib/features/analysis
flutter test test/widget/features/analysis/ test/widget/screens/analysis_screen_test.dart \
  test/unit/features/analysis/
```
Expected: 全 PASS。注意：bar 只在 `coachingOutcomeEventProvider` 查到 event 才渲染，而既有 widget tests 不會有 event（repo 空 / box 未 seed），理論上零渲染差異。**若**出現 Hive box 未開的 provider 錯誤（`coachingOutcomeRepositoryProvider` 預設走 `StorageService.coachingOutcomeEventsBox`），在受影響測試的 `ProviderScope` overrides 加 `coachingOutcomeRepositoryProvider.overrideWithValue(MemoryCoachingOutcomeRepository())`（Task 1 的共用 fake），不要去改 production 的 provider。

**Step 4: Commit**

```bash
git add lib/features/analysis/presentation/screens/analysis_screen.dart \
  lib/features/analysis/presentation/widgets/reply_style_card.dart
git commit -m "案1批2：analyze 三區接上「後來呢？」回報晶片條"
git push
```

（如 Step 3 動了測試 overrides，一併 add。）

---

### Task 7: coach 卡 outcome wiring widget test（批 1 備忘③）

**Files:**
- Modify: `lib/features/coach_chat/presentation/widgets/coach_chat_card.dart`（`_CoachChatResultView` → `@visibleForTesting` 公開；`_recordUserAction` 改用共用規則 helper）
- Test: `test/widget/features/coach_chat/coach_chat_result_view_outcome_wiring_test.dart`（目錄不存在就建）

**Step 1: 寫失敗的 widget tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/coach_chat/domain/entities/coach_chat_result.dart';
import 'package:vibesync/features/coach_chat/presentation/widgets/coach_chat_card.dart';
import 'package:vibesync/features/coaching_memory/data/providers/coaching_outcome_providers.dart';
import 'package:vibesync/features/coaching_memory/domain/entities/coaching_outcome_event.dart';

import '../../../helpers/memory_coaching_outcome_repository.dart';

CoachChatResult _result() {
  return CoachChatResult(
    id: 'result-1',
    conversationId: 'conversation-1',
    partnerId: 'partner-1',
    question: '我現在該怎麼回？',
    mode: 'replyCraft',
    headline: '先穩住節奏',
    answer: '先接住她的情緒，再丟一個好回的小球。',
    userState: '有點急著想推進',
    nextStep: '先用一句輕鬆的話把球丟回去',
    suggestedLine: '你這句有點突然，但我可以接。',
    boundaryReminder: '不要急著把對話推太重。',
    needsReflection: false,
    generatedAt: DateTime.utc(2026, 7, 6, 8),
    provider: 'claude',
    modelUsed: 'claude-sonnet-4-20250514',
  );
}

Widget _wrap(MemoryCoachingOutcomeRepository repo) {
  return ProviderScope(
    overrides: [
      coachingOutcomeRepositoryProvider.overrideWithValue(repo),
      coachingOutcomeNowProvider
          .overrideWithValue(() => DateTime.utc(2026, 7, 6, 9)),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CoachChatResultView(
            result: _result(),
            dailyRemaining: 3,
            onFollowUp: () {},
            onForceAnswer: () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('點第一段「照著發了」→ recorder 寫入 sentAsIs/pending 並浮出第二段',
      (tester) async {
    final repo = MemoryCoachingOutcomeRepository();
    await tester.pumpWidget(_wrap(repo));

    await tester.tap(find.text('照著發了'));
    await tester.pumpAndSettle();

    final stored = repo.get('coach:result-1')!;
    expect(stored.userAction, CoachingUserAction.sentAsIs);
    expect(stored.outcome, CoachingOutcomeSignal.pending);
    expect(find.text('有接話'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5)); // 清 SnackBar timer
  });

  testWidgets('點「沒有發」→ outcome=unknown 且不出第二段', (tester) async {
    final repo = MemoryCoachingOutcomeRepository();
    await tester.pumpWidget(_wrap(repo));

    await tester.tap(find.text('沒有發'));
    await tester.pumpAndSettle();

    final stored = repo.get('coach:result-1')!;
    expect(stored.userAction, CoachingUserAction.didNotSend);
    expect(stored.outcome, CoachingOutcomeSignal.unknown);
    expect(find.text('有接話'), findsNothing);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('第二段作答後重按同一顆第一段晶片，反應不被洗掉（批2同值短路）',
      (tester) async {
    final repo = MemoryCoachingOutcomeRepository();
    await tester.pumpWidget(_wrap(repo));

    await tester.tap(find.text('照著發了'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('有接話'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('照著發了')); // 重按同值
    await tester.pumpAndSettle();

    final stored = repo.get('coach:result-1')!;
    expect(stored.userAction, CoachingUserAction.sentAsIs);
    expect(stored.outcome, CoachingOutcomeSignal.engaged);

    await tester.pump(const Duration(seconds: 5));
  });
}
```

**Step 2:** Run: `flutter test test/widget/features/coach_chat/coach_chat_result_view_outcome_wiring_test.dart`
Expected: 編譯失敗（`CoachChatResultView` 不存在——現為私有 `_CoachChatResultView`）。

**Step 3: 實作**

`coach_chat_card.dart`：

1. `_CoachChatResultView`（:738）改名 `CoachChatResultView`，類宣告前加：

```dart
/// 公開僅為了 widget test 直接 pump；production 只在本檔內使用。
@visibleForTesting
class CoachChatResultView extends ConsumerWidget {
```

檔內所有 `_CoachChatResultView(` 引用同步改名（grep 確認零殘留）。`@visibleForTesting` 由 material.dart 轉出（foundation），不用加 import。

2. 順手把 `_recordUserAction`（:934-940）的 inline 規則換成 Task 1 的共用 helper（單點規則，避免 UI 與 recorder 各寫一份）：

```dart
    final outcome = coachingOutcomeForUserAction(action);
```

（原本三行三元運算刪除；其餘 try/catch、SnackBar 邏輯零改動。）

**Step 4:** Run:

```bash
flutter test test/widget/features/coach_chat/coach_chat_result_view_outcome_wiring_test.dart \
  test/unit/features/coach_chat/presentation/coach_chat_card_error_copy_test.dart
flutter analyze lib/features/coach_chat
```
Expected: 全 PASS、analyze 零 error。

**Step 5: Commit**

```bash
git add lib/features/coach_chat/presentation/widgets/coach_chat_card.dart \
  test/widget/features/coach_chat/coach_chat_result_view_outcome_wiring_test.dart
git commit -m "案1批2：coach 卡 outcome 晶片 wiring widget test＋規則改用共用 helper"
git push
```

---

### Task 8: 收尾驗證＋單審

**Step 1:** REQUIRED SUB-SKILL: superpowers:verification-before-completion——重跑全部 targeted 指令、貼實際輸出後才可宣稱完成：

```bash
flutter analyze lib/features/coaching_memory lib/features/opener lib/features/analysis \
  lib/features/coach_chat lib/shared/widgets/coaching_outcome_capture_card.dart \
  lib/shared/widgets/coaching_outcome_follow_up_bar.dart
flutter test test/unit/features/coaching_memory/ \
  test/widget/shared/widgets/ \
  test/unit/features/opener/ \
  test/widget/features/analysis/ test/widget/screens/analysis_screen_test.dart \
  test/widget/features/coach_chat/ \
  test/unit/features/coach_chat/presentation/coach_chat_card_error_copy_test.dart
```

**批 1 回歸紅線**：`coaching_outcome_capture_card_test.dart`（6 tests）與 coaching_memory 全部（含 digest 4 檔）必須全綠——本批動了 recorder 內部，任何 digest/批 1 測試紅燈都是回歸，停下查因，不改測試遷就。

**Step 2:** 單審（本批純 client 低風險，不派 Codex 雙審）：REQUIRED SUB-SKILL: superpowers:requesting-code-review，審查重點：
1. 同值短路是否可能吃掉合法寫入（唯一同值仍需寫入的情境不存在？——確認 outcome 由 userAction 決定性導出）
2. 複製冪等：已作答事件絕不被 copy-pending 覆蓋
3. opener requestId 是否在 saveDraft 前掛上、`visibleForAccess` 是否傳遞
4. analyze 三區 `ref.watch` 是否只在 build 內、bar 未複製時零渲染
5. 本批不得出現任何「只存本地」文案改動（那是批 3）、不得碰 quota/計費路徑

**Step 3:** 更新 memory：批 2 SHIPPED 記入 `project_post_review_optimization_roadmap_2026-07-06.md` 對應行（不新開檔）。

---

## 不做的事（本批）

- 不動 submit-feedback／任何 Edge Function／上傳封裝（批 3）。
- 不動「只存本地」/隱私文案（批 3）。
- 不動 digest 注入 coach prompt、`coach_chat_api_service` body、Edge schema（批 4）。
- 不刪、不接線 `lib/shared/widgets/reply_card.dart`（死碼，零 production import，留待日後清理案）。
- 不碰 subscription/quota/RevenueCat/計費路徑（複製記錄失敗一律吞掉，絕不擋複製）。
- 不加 Hive schema 欄位、不跑 migration（`CoachingOutcomeEvent` typeId=18 全欄位夠用；opener requestId 走 JSON 快取）。
- 不做 opener/analyze 的 `outcomeTextPreview`/`userNote` 收集 UI（現階段只有晶片，preview/note 欄位僅做保留不做新入口）。
- 不動 `OpenerRequestIdSession` 的扣費 idempotency 語意（只讀 requestId，不改生命週期）。

## 風險與回歸範圍

- **全批純 client、低風險、單審。** 不碰 server、不碰計費、Hive schema 零變動。
- **同值短路改變既有 coach 卡行為**（原本重按同晶片會整筆重建）：批 1 測試（capture card 6 tests＋providers 既有 6 tests＋digest 4 檔）必須全綠（Task 8 紅線）；另 Task 1 新測試與 Task 7 widget test 把新語意鎖死。
- **opener 扣費線旁路風險**：Task 2 動到生成流程 :515-528，但只在 `markSuccess()` 之後**加一行** `withRequestId`，不動 beginAttempt/fingerprint/payload——idempotency 測試（`opener_request_session_test.dart`）與 opener service tests 全跑。
- **analysis_screen 是 7591 行大檔**：所有插入以錨字串定位（「height: 360」「🧠」「複製草稿」「_copyRecommendationText」），行號僅供初次定位；Task 5/6 分開 commit，出問題可獨立 revert。
- **既有 analysis widget tests 對 Hive box 的隱性依賴**：Task 6 Step 3 已給 fallback（override repo provider），不改 production provider。
- 「後來呢？」條在橫向卡列下方而非卡內（overflow 硬限制）：屬 UX 折衷，dogfood 若體感不佳再開後續案調整，不在本批返工。
