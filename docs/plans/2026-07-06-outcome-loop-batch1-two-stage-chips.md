# 案 1 批 1：Outcome 晶片兩段式改版 實作計畫

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
> 上游設計：`docs/plans/2026-07-06-outcome-loop-server-design.md`（APPROVED）。本批＝表格「批 1」，純 client UI，低風險，單審。

**Goal:** 把 coach 卡的 outcome 回報從 5 顆混軸晶片改成兩段式（先問 userAction、再問她的反應），並抽成共用元件供批 2 的 opener/analyze 復用。

**Architecture:** 新共用 StatelessWidget `CoachingOutcomeCaptureCard`（`lib/shared/widgets/`），選取狀態全由傳入的 `CoachingOutcomeEvent?` 反推（沿用現行無 state 設計）；`CoachingOutcomeRecorder` 新增 `recordCoachResultReaction`（只更新 outcome、保留第一段 userAction，避開整筆 put 覆蓋把 userAction 蓋回 unknown 的坑）；`coach_chat_card.dart` 換接新元件並刪舊卡。

**Tech Stack:** Flutter 3.x / Riverpod / Hive（不動 schema）、flutter_test widget tests。

---

## 拍板與既定事實（執行者不需重查）

- 兩段式規格（設計檔第一節）：
  - 第一段「這則建議你怎麼處理？」→ 照著發了(`sentAsIs`)／改一改才發(`editedAndSent`)／沒有發(`didNotSend`)／回頭問了教練(`askedCoach`)
  - 第二段只在 `sentAsIs`/`editedAndSent` 才出：「她的反應？」→ 有接話(`engaged`)／冷回(`cold`)／已讀沒回(`noReply`)／反應不好(`negative`)
  - `didNotSend`/`askedCoach` 直接結束；後選覆蓋前選。
- **第一段的 outcome 值拍板**：`sentAsIs`/`editedAndSent` → `pending`（等第二段）；`didNotSend`/`askedCoach` → `unknown`（終態，永遠不會有反應）。注意這改變了舊卡「我沒送出→pending」的映射——pending 從此語意固定為「已發出、等回報」，與批 2 複製自動記 pending 一致。
- 現況座標：
  - 舊卡 `_CoachOutcomeCaptureCard`：`lib/features/coach_chat/presentation/widgets/coach_chat_card.dart:1070-1174`；選項表 `_coachOutcomeOptions` `:1037-1068`；`_CoachOutcomeOption` `:1018-1035`；`_recordOutcome` `:929-956`；建構點 `:919-922`（在 `_CoachChatResultView.build`，`!isClarifying` 才渲染）；`outcomeEvent` 來源 `:756-762`。
  - Enums：`lib/features/coaching_memory/domain/entities/coaching_outcome_event.dart`（`CoachingUserAction` :16-28、`CoachingOutcomeSignal` :30-44）。**沒有** label helper，文案目前硬寫在舊選項表。
  - Recorder：`lib/features/coaching_memory/data/providers/coaching_outcome_providers.dart:63-113`，`recordCoachResultOutcome` 用 `.create` 組整筆事件、`repo.put`（同 id 整筆覆蓋）、之後 invalidate event+digest providers。id 組法 `coachingOutcomeIdForCoachResult` `:60-61`。
  - 覆蓋語意有既有測試：`test/unit/features/coaching_memory/data/providers/coaching_outcome_providers_test.dart`「recording the same coach result overwrites the previous signal」。
  - 晶片慣例範本：`lib/features/coach_follow_up/presentation/widgets/coach_follow_up_chip_row.dart:52-64` —— `Wrap(spacing:8, runSpacing:8)` + `ChoiceChip` + **`showCheckmark: false`**（深底 ghost-checkmark 已知坑，必加）。
  - 舊卡容器/晶片樣式（白底 alpha 0.50、圓角 14、`selectedColor: AppColors.primary`、`visualDensity: compact`、avatar icon）搬進新元件時整段沿用，僅補 `showCheckmark: false`。
  - 底部 caption「回報不扣額度…只是先把結果存在本機。」**本批照抄不改**——「只存本地」文案改版是批 3 的事，不要在這批動。
- 環境注意：`.g.dart` 是 build_runner 產物不在 git；跑測試前若缺，先 `dart run build_runner build --delete-conflicting-outputs`。WSL 下 `dart format` 壞，不要跑 format。import 風格照鄰檔（開檔看同目錄現有 import 再仿寫）。

---

### Task 1: 共用元件 `CoachingOutcomeCaptureCard`（TDD）

**Files:**
- Create: `lib/shared/widgets/coaching_outcome_capture_card.dart`
- Test: `test/widget/shared/widgets/coaching_outcome_capture_card_test.dart`（目錄不存在就建）

**Step 1: 寫失敗的 widget tests**

測試要點（`event` 用 `CoachingOutcomeEvent` 的 permissive const 建構子直接組，不走 `.create`；必填欄位 id/source/suggestedMoveSummary/userAction/outcome/createdAt 給假值即可，不需要 Hive）：

```dart
// test/widget/shared/widgets/coaching_outcome_capture_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// import coaching_outcome_event.dart 與 coaching_outcome_capture_card.dart（路徑照專案 import 慣例）

CoachingOutcomeEvent _event({
  CoachingUserAction userAction = CoachingUserAction.unknown,
  CoachingOutcomeSignal outcome = CoachingOutcomeSignal.unknown,
}) {
  return CoachingOutcomeEvent(
    id: 'coach:r1',
    source: CoachingOutcomeSource.coach,
    suggestedMoveSummary: '先聊她剛說的展覽',
    userAction: userAction,
    outcome: outcome,
    createdAt: DateTime(2026, 7, 6),
  );
}

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  testWidgets('未回報時只顯示第一段四顆晶片，不顯示第二段', (tester) async {
    await tester.pumpWidget(_wrap(CoachingOutcomeCaptureCard(
      event: null,
      onUserActionSelected: (_) {},
      onOutcomeSelected: (_) {},
    )));
    expect(find.text('照著發了'), findsOneWidget);
    expect(find.text('改一改才發'), findsOneWidget);
    expect(find.text('沒有發'), findsOneWidget);
    expect(find.text('回頭問了教練'), findsOneWidget);
    expect(find.text('有接話'), findsNothing);
    expect(find.text('反應不好'), findsNothing);
  });

  testWidgets('userAction=sentAsIs 時第一段選中且顯示第二段四顆', (tester) async {
    await tester.pumpWidget(_wrap(CoachingOutcomeCaptureCard(
      event: _event(
        userAction: CoachingUserAction.sentAsIs,
        outcome: CoachingOutcomeSignal.pending,
      ),
      onUserActionSelected: (_) {},
      onOutcomeSelected: (_) {},
    )));
    final chip = tester.widget<ChoiceChip>(find.ancestor(
      of: find.text('照著發了'), matching: find.byType(ChoiceChip)));
    expect(chip.selected, isTrue);
    expect(find.text('有接話'), findsOneWidget);
    expect(find.text('冷回'), findsOneWidget);
    expect(find.text('已讀沒回'), findsOneWidget);
    expect(find.text('反應不好'), findsOneWidget);
  });

  testWidgets('userAction=didNotSend 時不顯示第二段', (tester) async {
    await tester.pumpWidget(_wrap(CoachingOutcomeCaptureCard(
      event: _event(userAction: CoachingUserAction.didNotSend),
      onUserActionSelected: (_) {},
      onOutcomeSelected: (_) {},
    )));
    expect(find.text('有接話'), findsNothing);
  });

  testWidgets('點第一段晶片回呼 onUserActionSelected', (tester) async {
    CoachingUserAction? got;
    await tester.pumpWidget(_wrap(CoachingOutcomeCaptureCard(
      event: null,
      onUserActionSelected: (a) => got = a,
      onOutcomeSelected: (_) {},
    )));
    await tester.tap(find.text('改一改才發'));
    expect(got, CoachingUserAction.editedAndSent);
  });

  testWidgets('點第二段晶片回呼 onOutcomeSelected', (tester) async {
    CoachingOutcomeSignal? got;
    await tester.pumpWidget(_wrap(CoachingOutcomeCaptureCard(
      event: _event(
        userAction: CoachingUserAction.editedAndSent,
        outcome: CoachingOutcomeSignal.pending,
      ),
      onUserActionSelected: (_) {},
      onOutcomeSelected: (s) => got = s,
    )));
    await tester.tap(find.text('已讀沒回'));
    expect(got, CoachingOutcomeSignal.noReply);
  });

  testWidgets('outcome=engaged 時第二段晶片呈選中', (tester) async {
    await tester.pumpWidget(_wrap(CoachingOutcomeCaptureCard(
      event: _event(
        userAction: CoachingUserAction.sentAsIs,
        outcome: CoachingOutcomeSignal.engaged,
      ),
      onUserActionSelected: (_) {},
      onOutcomeSelected: (_) {},
    )));
    final chip = tester.widget<ChoiceChip>(find.ancestor(
      of: find.text('有接話'), matching: find.byType(ChoiceChip)));
    expect(chip.selected, isTrue);
  });
}
```

**Step 2: 跑測試確認失敗**

Run: `flutter test test/widget/shared/widgets/coaching_outcome_capture_card_test.dart`
Expected: 編譯失敗（`CoachingOutcomeCaptureCard` 不存在）。

**Step 3: 最小實作**

```dart
// lib/shared/widgets/coaching_outcome_capture_card.dart
import 'package:flutter/material.dart';
// import AppColors 與 coaching_outcome_event.dart（照鄰檔慣例）

/// 兩段式 outcome 回報卡。選取狀態全由 [event] 反推，無內部 state。
/// coach / opener / analyze 三處共用（批 2 接後兩處）。
class CoachingOutcomeCaptureCard extends StatelessWidget {
  const CoachingOutcomeCaptureCard({
    super.key,
    required this.event,
    required this.onUserActionSelected,
    required this.onOutcomeSelected,
  });

  final CoachingOutcomeEvent? event;
  final ValueChanged<CoachingUserAction> onUserActionSelected;
  final ValueChanged<CoachingOutcomeSignal> onOutcomeSelected;

  bool get _showsReactionStage =>
      event?.userAction == CoachingUserAction.sentAsIs ||
      event?.userAction == CoachingUserAction.editedAndSent;

  @override
  Widget build(BuildContext context) {
    // 容器樣式整段照搬舊 _CoachOutcomeCaptureCard（coach_chat_card.dart:1070-1174）：
    // 白底 alpha 0.50、圓角 14、標題/副標/底部 caption 結構不變。
    // 內容改為：
    //   標題「這則建議你怎麼處理？」＋第一段 Wrap 四顆 ChoiceChip
    //   （_showsReactionStage 時）分隔 + 「她的反應？」＋第二段 Wrap 四顆 ChoiceChip
    //   caption 照抄舊卡「回報不扣額度…只是先把結果存在本機。」（批 3 才改文案）
    // ChoiceChip 樣式沿用舊卡（selectedColor: AppColors.primary、visualDensity compact），
    // 一律加 showCheckmark: false（ghost-checkmark 坑）。
    // selected 判定：第一段 = event?.userAction == option 值；
    //               第二段 = event?.outcome == option 值且 outcome != pending/unknown。
  }
}

/// 晶片/SnackBar 共用文案（enum 沒有 label helper，統一放這裡）。
String coachingUserActionLabel(CoachingUserAction action) => switch (action) {
      CoachingUserAction.sentAsIs => '照著發了',
      CoachingUserAction.editedAndSent => '改一改才發',
      CoachingUserAction.didNotSend => '沒有發',
      CoachingUserAction.askedCoach => '回頭問了教練',
      CoachingUserAction.unknown => '尚未回報',
    };

String coachingOutcomeSignalLabel(CoachingOutcomeSignal signal) =>
    switch (signal) {
      CoachingOutcomeSignal.engaged => '有接話',
      CoachingOutcomeSignal.cold => '冷回',
      CoachingOutcomeSignal.noReply => '已讀沒回',
      CoachingOutcomeSignal.negative => '反應不好',
      CoachingOutcomeSignal.pending => '等你回報',
      CoachingOutcomeSignal.unknown => '未知',
    };
```

（build 內容照註解落實；副標邏輯：未回報→「點一下，教練下次就記得這招有沒有用」；第一段答完 didNotSend/askedCoach→「已記下，謝謝回報」；第二段答完→「已記下「{label}」」。文案可微調但不得出現「只存本地」承諾的新增變體。）

**Step 4: 跑測試確認通過**

Run: `flutter test test/widget/shared/widgets/coaching_outcome_capture_card_test.dart`
Expected: 6 tests PASS。

**Step 5: Commit**

```bash
git add lib/shared/widgets/coaching_outcome_capture_card.dart test/widget/shared/widgets/coaching_outcome_capture_card_test.dart
git commit -m "案1批1：新增兩段式 outcome 回報共用元件 CoachingOutcomeCaptureCard"
git push
```

---

### Task 2: Recorder 新增 `recordCoachResultReaction`（TDD）

第二段只更新 outcome。因為 repo.put 是同 id 整筆覆蓋、`.create` 會把 userAction 重設為 unknown，所以必須讀舊事件、保留全部欄位、只換 outcome（createdAt 更新為現在，digest 排序才對）。

**Files:**
- Modify: `lib/features/coaching_memory/data/providers/coaching_outcome_providers.dart`（`CoachingOutcomeRecorder` 內，`recordCoachResultOutcome` 之後）
- Test: `test/unit/features/coaching_memory/data/providers/coaching_outcome_providers_test.dart`（加測項）

**Step 1: 寫失敗的 unit tests**（照該檔既有測試的 container/box 佈置方式仿寫）

```dart
test('recordCoachResultReaction 保留第一段 userAction、只更新 outcome', () async {
  // 先 recordCoachResultOutcome(userAction: editedAndSent, outcome: pending)
  // 再 recordCoachResultReaction(outcome: cold)
  // 斷言：同一筆 event 的 userAction 仍是 editedAndSent、outcome 變 cold、
  //       id/adviceId/suggestedMoveSummary 不變。
});

test('recordCoachResultReaction 在沒有第一段紀錄時不寫入', () async {
  // 直接呼叫 recordCoachResultReaction(outcome: engaged)
  // 斷言：回傳 null 且 box 內沒有該 id 的事件。
});

test('recordCoachResultReaction 在 userAction=didNotSend 時不覆寫', () async {
  // 先 recordCoachResultOutcome(userAction: didNotSend, outcome: unknown)
  // 再 recordCoachResultReaction(outcome: engaged)
  // 斷言：回傳 null，事件 outcome 仍是 unknown。
});
```

**Step 2:** Run: `flutter test test/unit/features/coaching_memory/data/providers/coaching_outcome_providers_test.dart` → Expected: FAIL（方法不存在）。

**Step 3: 實作**（結構、錯誤處理、invalidate 清單逐行仿照 `recordCoachResultOutcome` `:68-98`，回傳型別也一致）

```dart
Future<CoachingOutcomeEvent?> recordCoachResultReaction({
  required CoachChatResult result,
  required CoachingOutcomeSignal outcome,
}) async {
  final id = coachingOutcomeIdForCoachResult(result.id);
  final existing = _repository.get(id); // 依實際欄位名取 repo，照鄰近 method
  final action = existing?.userAction;
  if (existing == null ||
      (action != CoachingUserAction.sentAsIs &&
          action != CoachingUserAction.editedAndSent)) {
    return null; // 第二段只在第一段答「有發出」後合法
  }
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
    createdAt: DateTime.now(),
  );
  await _repository.put(updated);
  // invalidate 段落照 recordCoachResultOutcome 複製（event + partner/unbound digest）
  return updated;
}
```

**Step 4:** 同 Step 2 指令 → Expected: 既有 3 測項＋新 3 測項全 PASS（既有「overwrites the previous signal」測試不得壞——`recordCoachResultOutcome` 本批**零改動**）。

**Step 5: Commit**

```bash
git add lib/features/coaching_memory/data/providers/coaching_outcome_providers.dart test/unit/features/coaching_memory/data/providers/coaching_outcome_providers_test.dart
git commit -m "案1批1：recorder 新增第二段回報 recordCoachResultReaction（保留 userAction 只更新 outcome）"
git push
```

---

### Task 3: coach 卡接上兩段式、刪舊卡

**Files:**
- Modify: `lib/features/coach_chat/presentation/widgets/coach_chat_card.dart`
  - 建構點 `:919-922` 換成 `CoachingOutcomeCaptureCard`
  - 刪除 `_CoachOutcomeCaptureCard`（`:1070-1174`）、`_CoachOutcomeOption`（`:1018-1035`）、`_coachOutcomeOptions`（`:1037-1068`）、舊 `_recordOutcome`（`:929-956`）

**Step 1: 改寫建構點與 handlers**

```dart
// _CoachChatResultView.build 內，取代原 _CoachOutcomeCaptureCard(...)
CoachingOutcomeCaptureCard(
  event: outcomeEvent,
  onUserActionSelected: (action) => _recordUserAction(context, ref, action),
  onOutcomeSelected: (signal) => _recordReaction(context, ref, signal),
),
```

```dart
// 兩個 handler 取代舊 _recordOutcome；SnackBar 成功/失敗文案與 try-catch 結構照舊 _recordOutcome 搬
Future<void> _recordUserAction(
  BuildContext context, WidgetRef ref, CoachingUserAction action) async {
  final outcome = (action == CoachingUserAction.sentAsIs ||
          action == CoachingUserAction.editedAndSent)
      ? CoachingOutcomeSignal.pending
      : CoachingOutcomeSignal.unknown;
  // ref.read(coachingOutcomeRecorderProvider).recordCoachResultOutcome(
  //   result: result, userAction: action, outcome: outcome);
  // 成功 SnackBar 用 coachingUserActionLabel(action)
}

Future<void> _recordReaction(
  BuildContext context, WidgetRef ref, CoachingOutcomeSignal signal) async {
  // ref.read(coachingOutcomeRecorderProvider).recordCoachResultReaction(
  //   result: result, outcome: signal);
  // 回傳 null（防禦路徑）不彈成功 SnackBar；成功用 coachingOutcomeSignalLabel(signal)
}
```

**Step 2: 刪舊碼後全域搜尋確認**

Run: `grep -rn "_CoachOutcomeCaptureCard\|_coachOutcomeOptions\|_CoachOutcomeOption" lib/ test/`
Expected: 零結果。

**Step 3: analyze + 跑相關測試**

Run:
```bash
flutter analyze lib/features/coach_chat lib/shared/widgets/coaching_outcome_capture_card.dart
flutter test test/widget/shared/widgets/coaching_outcome_capture_card_test.dart \
  test/unit/features/coaching_memory/ \
  test/unit/features/coach_chat/presentation/coach_chat_card_error_copy_test.dart
```
Expected: analyze 零 error；測試全 PASS（含 digest 4 檔——本批不動 digest，任何 digest 測試紅燈都是回歸，停下查因，不改測試遷就）。

**Step 4: Commit**

```bash
git add lib/features/coach_chat/presentation/widgets/coach_chat_card.dart
git commit -m "案1批1：coach 卡接上兩段式 outcome 晶片、移除舊 5 顆混軸卡"
git push
```

---

### Task 4: 收尾驗證

**Step 1:** REQUIRED SUB-SKILL: superpowers:verification-before-completion——重跑 Task 3 Step 3 全部指令，貼實際輸出後才可宣稱完成。

**Step 2:** 單審（本批低風險，不派 Codex）：REQUIRED SUB-SKILL: superpowers:requesting-code-review，審查重點：
1. 第二段是否可能把 userAction 蓋回 unknown（Task 2 的核心坑）
2. 「後選覆蓋前選」語意：第一段改答 didNotSend 後，outcome 是否正確回到 unknown、第二段是否消失
3. 舊卡刪乾淨、無殘留引用
4. 本批不得出現任何「只存本地」文案改動（那是批 3）

**Step 3:** 更新 memory：批 1 SHIPPED 記入 `project_post_review_optimization_roadmap_2026-07-06.md` 對應行（不新開檔）。

---

## 明確不做（本批）

- 不動 opener/analyze 入口與 adviceId 自產（批 2）。
- 不動「只存本地」/隱私文案（批 3）。
- 不動 submit-feedback、任何 Edge Function、digest 注入（批 3/4）。
- 不動 `recordCoachResultOutcome` 既有簽名與行為。
- 不加 Hive schema 欄位、不跑 migration。
