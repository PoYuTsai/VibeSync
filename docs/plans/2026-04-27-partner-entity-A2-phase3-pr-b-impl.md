# A2 Phase 3 PR-B — Merge Picker + Reassign ⋮ Menu Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task.

**Goal:** 把 Phase 2 留下的 PartnerDetail ⋮ menu (merge / edit / delete) 從 visible-only 接通成功能性的 **merge UI**（Task 12），並把 conversation 列從 chevron 改成可發現的 ⋮ menu，接通 **reassign 流**（Task 13）。

**Architecture:** 新增單一 `PartnerWriteController` 作為 partner write + 跨 partner Riverpod invalidation 的單一所有權點（鏡像 Phase 1 `ConversationWriteController` 的「Single invalidation owner」契約）。抽出共用 `PartnerPickerSheet` 給 merge / reassign 兩條路徑復用。Reassign 直接走既有 `ConversationWriteController.save(c, previousPartnerId:)` 雙端 invalidate（Phase 1 已測），不需新 write infra。Hermetic widget test pattern 沿用 Phase 2 `partner_detail_screen_test.dart`：subclass notifier + Riverpod override + temp Hive box（如需）。

**Tech Stack:** Flutter, Riverpod NotifierProvider, `flutter_test`, GoRouter, Hive (PartnerRepository A1 surface).

---

## ⚠️ Reality Check — Design Doc §5 Deviation

讀 code 後發現 design doc §5「Confirm 後行為 → 3. Riverpod aggregate invalidation 由 repo 觸發（A1 已 tested）」**是錯的**：

| Design doc 假設 | 現行 code 真相 | PR-B 處理 |
|---|---|---|
| `PartnerRepository.merge` 觸發 Riverpod invalidation | repo 沒有 `Ref`，純 Hive box ops；merge 結束後 `partnerByIdProvider(fromId)` / `partnerListProvider` 會 stale 直到下次 widget rebuild + repo re-read | **新增 `PartnerWriteController`** 作為 Phase 1 ConversationWriteController 的 partner-side 對應物，承擔 merge 後的 Riverpod 失效 |
| 「A1 已 tested」 | A1 只測了 `merge()` 的 Hive 行為（conversations 重指 / customNote 拼接 / source 刪除），沒測 invalidation | unit test 直接斷言 invalidation set，與 controller 一起 ship |
| `showCreateNewAction: true` for reassign picker | 實作此 action 需 navigate-then-reattach（push AddPartnerScreen → 用 returned id 接 reassign），複雜度顯著高 | **Deviation：PR-B ship 不含「+ 新建對象」inline action**，picker 只列其他 Partners。empty state 顯示 hint「尚無其他對象，先回首頁建立」+ 關閉按鈕。若 Codex 要堅持 design doc，標 r2 patch 加回 |

**這個 deviation 不擋 PR-B merge 的 Hive 行為**（merge 本身正確），但若不加 controller，picker confirm 後 UI 會 stale，TF QA 會抓到。**Codex spec review 必須 explicit acknowledge `PartnerWriteController` 的引入**。

---

## ⚠️ Reality Check — `PartnerRepository.merge` Bypasses `ConversationWriteController`

`PartnerRepository.merge` 內部對 conversations 做 `c.partnerId = toId; await c.save();`（直接 Hive write），**繞過** Phase 1 為 conversation writes 設的「all writes go through ConversationWriteController」契約。

**為何不在 PR-B 修：**
1. merge 是 partner-層級 transaction（partner delete + conversations 重指 + customNote 拼接 atomic-ish），夾 controller 進去會破壞 transaction 邊界
2. controller 只是 invalidation 殼，不影響資料層正確性
3. PartnerWriteController 在 merge 後接管雙端 `conversationsByPartnerProvider` invalidation，效果等價

**plan 將此標為已知契約弱化**，Codex review 必須 acknowledge。Phase 4 cleanup PR（reportDataProvider 遷出 global feed 那波）一起重審。

---

## ⚠️ Reality Check — `PartnerConversationTile` Refactor Boundary

Phase 2 留下的 `PartnerConversationTile` 是 `StatelessWidget(conversation, onTap)`。Task 13 要把 trailing 從 `Icon(chevron_right)` 改 `PopupMenuButton`，意味 tile 需要新 callback。為保持 tile pure（不 own routing/picker），**新增 `onReassign: VoidCallback?` prop**，由呼叫端（PartnerDetailScreen）負責 picker + 串 ConversationWriteController。

`onTap` 維持不變（卡片整體仍 tappable→detail）。`PopupMenuButton` 只攔截 trailing 區。Phase 2 widget test (`renders one tile per conversation when list non-empty`) 不該破，因為新 prop 是 optional。

---

## Pre-flight（Task 0）

執行：

```bash
git status
git log -1 --format=oneline
ls test/widget/features/partner/
ls lib/features/partner/presentation/
```

預期：
- `On branch feature/partner-entity-A2-flows-pickers`，working tree clean
- HEAD = `f2e791d` `[ci] 加 flutter-ci.yml — PR gate (analyze + test) (#6)` 或更新（PR #4 / PR-A 若先 merge 也 OK）
- partner test dir 含 5 個既有檔（`add_partner_screen_test.dart`, `partner_detail_screen_test.dart`, `partner_list_screen_test.dart`, `partner_radar_summary_card_test.dart` + 跑得到的 baseline）
- partner presentation dir 含 `screens/`、`widgets/`、`providers/`

跑 baseline test 確保 Phase 2 沒被打壞（用 cmd.exe 因 WSL flutter binary 壞）：

```bash
cmd.exe /c "flutter.bat test test\widget\features\partner --reporter expanded"
```

預期：21 pass / 1 skip（與 main HEAD baseline 一致）。若有 fail → STOP，先 root-cause。

---

## Task 1 — PartnerWriteController 基礎設施

**Files:**
- Create: `lib/features/partner/data/providers/partner_write_controller.dart`
- Create: `test/unit/features/partner/partner_write_controller_test.dart`

**Step 1：寫 failing unit test**

斷言：merge 後 `partnerByIdProvider(fromId)` / `partnerListProvider` / `conversationsByPartnerProvider(fromId)` / `conversationsByPartnerProvider(toId)` / `partnerAggregateProvider(fromId)` / `partnerAggregateProvider(toId)` / `conversationsProvider`（legacy global）全部被 invalidate；same-id merge no-op；missing-side throws。

```dart
// test/unit/features/partner/partner_write_controller_test.dart
//
// Asserts that PartnerWriteController.merge invalidates the full set of
// partner-scoped + conversation-scoped Riverpod providers around both
// sides of a merge. PartnerRepository (no Ref) cannot do this itself;
// the controller is the single invalidation owner for partner writes.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import 'package:vibesync/core/services/storage_service.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/partner/data/providers/partner_write_controller.dart';
import 'package:vibesync/features/partner/data/repositories/partner_repository.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';

// see Phase 1 / Phase 2 unit tests for Hive-init harness; reuse pattern.
// (StorageService.initialize variant + temp dir per test)

void main() {
  group('PartnerWriteController.merge invalidations', () {
    setUp(() async { /* ... temp Hive boxes setUp ... */ });
    tearDown(() async { /* ... close + delete ... */ });

    test('merge invalidates both partner sides + their conversation scopes',
        () async {
      final container = ProviderContainer(
        overrides: [
          authConversationScopeProvider
              .overrideWith(() => _StubAuthScope('u1')),
        ],
      );
      addTearDown(container.dispose);

      // Seed: from-Partner with 2 conversations, to-Partner with 0
      final partnerRepo = container.read(partnerRepositoryProvider);
      await partnerRepo.upsertIfAbsent(_partner('A', 'u1'));
      await partnerRepo.upsertIfAbsent(_partner('B', 'u1'));
      // ...seed 2 conversations with partnerId='A' via ConversationRepository...

      // Prime providers (force them to subscribe so we can detect invalidation)
      final aBefore = container.read(partnerByIdProvider('A'));
      final listBefore = container.read(partnerListProvider);
      final aConvBefore = container.read(conversationsByPartnerProvider('A'));
      final bConvBefore = container.read(conversationsByPartnerProvider('B'));
      final aAggBefore = container.read(partnerAggregateProvider('A'));
      final bAggBefore = container.read(partnerAggregateProvider('B'));
      final globalBefore = container.read(conversationsProvider);

      expect(aBefore, isNotNull);
      expect(listBefore.length, 2);
      expect(aConvBefore.length, 2);
      expect(bConvBefore, isEmpty);

      // Action
      final controller =
          container.read(partnerWriteControllerProvider.notifier);
      await controller.merge(fromId: 'A', toId: 'B');

      // Assertions: read AGAIN — values should reflect post-merge state
      expect(container.read(partnerByIdProvider('A')), isNull,
          reason: 'A is deleted; partnerByIdProvider(A) must not stale-cache');
      expect(container.read(partnerListProvider).length, 1);
      expect(container.read(conversationsByPartnerProvider('A')), isEmpty);
      expect(container.read(conversationsByPartnerProvider('B')).length, 2);
      expect(container.read(partnerAggregateProvider('B')).count,
          greaterThanOrEqualTo(2));
      // legacy global invalidated as well (Phase 1 transition contract)
    });

    test('same-id merge is a no-op (no invalidation, no throw)', () async {
      // ...seed one Partner...
      final controller = /* ... */;
      await controller.merge(fromId: 'A', toId: 'A');
      // assert nothing changed in providers
    });

    test('missing source/target throws ArgumentError', () async {
      final controller = /* ... */;
      expect(
        () => controller.merge(fromId: 'ghost', toId: 'A'),
        throwsArgumentError,
      );
    });
  });
}

Partner _partner(String id, String owner) => Partner(
      id: id,
      name: id,
      ownerUserId: owner,
      createdAt: DateTime(2026, 4, 27),
      updatedAt: DateTime(2026, 4, 27),
    );
```

**Codex-Review-Hot-Spot**：上面的 setUp/tearDown 用「temp Hive box per test」pattern。執行時 reuse `test/unit/features/partner/partner_repository_merge_test.dart` 已 ship 的 helper（A1 留下的）。若該 helper 不 export，就同檔複製成 `_setUpTempBoxes()` private fn —— 不要為了 DRY 改既有 A1 test 檔（PR-B 邊界外）。

**Step 2：跑 test 確認 FAIL**

```bash
cmd.exe /c "flutter.bat test test\unit\features\partner\partner_write_controller_test.dart --reporter expanded"
```

預期：FAIL — `partner_write_controller.dart` 不存在。

**Step 3：寫 controller**

```dart
// lib/features/partner/data/providers/partner_write_controller.dart
//
// Single invalidation owner for partner writes (mirrors Phase 1
// ConversationWriteController for the conversation domain).
//
// Why this exists despite design doc §5 saying "repo triggers invalidation":
// PartnerRepository has no Riverpod Ref. After a merge, Hive state is
// correct but provider cache is stale until something re-reads the box.
// This controller is the boundary between repo-level mutation and
// Riverpod-level invalidation for partner writes.
//
// Phase 4 will extend this with `delete()` and possibly `update()`. Same
// invalidation surface, different repo call.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../conversation/data/providers/conversation_providers.dart';
import '../../presentation/providers/partner_providers.dart';

class PartnerWriteController extends Notifier<void> {
  @override
  void build() {
    // Stateless write coordinator.
  }

  Future<void> merge({
    required String fromId,
    required String toId,
  }) async {
    if (fromId == toId) return;
    final repo = ref.read(partnerRepositoryProvider);
    await repo.merge(fromId: fromId, toId: toId);
    _invalidatePartner(fromId);
    _invalidatePartner(toId);
    _invalidatePartnerScopedConversations(fromId);
    _invalidatePartnerScopedConversations(toId);
    ref.invalidate(partnerListProvider);
    // Legacy global feed — Phase 1 transition contract; remove after
    // reportDataProvider migrates off `conversationsProvider`.
    ref.invalidate(conversationsProvider);
  }

  void _invalidatePartner(String id) {
    ref.invalidate(partnerByIdProvider(id));
    ref.invalidate(partnerAggregateProvider(id));
  }

  void _invalidatePartnerScopedConversations(String id) {
    ref.invalidate(conversationsByPartnerProvider(id));
  }
}

final partnerWriteControllerProvider =
    NotifierProvider<PartnerWriteController, void>(
  PartnerWriteController.new,
);
```

**Step 4：跑 test 確認 PASS**

```bash
cmd.exe /c "flutter.bat test test\unit\features\partner\partner_write_controller_test.dart --reporter expanded"
```

預期：3/3 PASS。

**Step 5：Commit**

```bash
git add lib/features/partner/data/providers/partner_write_controller.dart \
        test/unit/features/partner/partner_write_controller_test.dart
git commit -m "[feat] PartnerWriteController — partner write 的 Riverpod 失效擁有者 (Task 1)

design doc §5 假設「repo 觸發 invalidation」是錯的（repo 沒 Ref）。
本 controller 鏡像 Phase 1 ConversationWriteController 契約：
單一 owner 把 merge 後的 partner / conversation / aggregate / list
失效全部 invalidate。Phase 4 delete 將 reuse 同一 surface。"
```

---

## Task 2 — PartnerPickerSheet 共用 widget

**Files:**
- Create: `lib/features/partner/presentation/widgets/partner_picker_sheet.dart`
- Create: `test/widget/features/partner/partner_picker_sheet_test.dart`

**Step 1：寫 failing widget tests**

```dart
// test/widget/features/partner/partner_picker_sheet_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_picker_sheet.dart';

Partner _p(String id, String name) => Partner(
      id: id,
      name: name,
      ownerUserId: 'u1',
      createdAt: DateTime(2026, 4, 27),
      updatedAt: DateTime(2026, 4, 27),
    );

void main() {
  testWidgets('lists all partners except excludeId', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerListProvider.overrideWith(
          (_) => [_p('A', 'Alice'), _p('B', 'Bob'), _p('C', 'Cara')],
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(body: PartnerPickerSheet(excludeId: 'A')),
      ),
    ));
    await t.pumpAndSettle();

    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Cara'), findsOneWidget);
    expect(find.text('Alice'), findsNothing);
  });

  testWidgets('filter TextField narrows by name (case-insensitive)', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerListProvider.overrideWith(
          (_) => [_p('A', 'Alice'), _p('B', 'Bob'), _p('C', 'Cara')],
        ),
      ],
      child: MaterialApp(home: Scaffold(body: PartnerPickerSheet())),
    ));
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextField), 'bo');
    await t.pumpAndSettle();
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Alice'), findsNothing);
    expect(find.text('Cara'), findsNothing);
  });

  testWidgets('tap on row invokes onSelected with that Partner', (t) async {
    Partner? captured;
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerListProvider.overrideWith((_) => [_p('A', 'Alice')]),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: PartnerPickerSheet(
            onSelected: (p) => captured = p,
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();

    await t.tap(find.text('Alice'));
    await t.pumpAndSettle();
    expect(captured?.id, 'A');
  });

  testWidgets('empty after exclude shows hint message', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerListProvider.overrideWith((_) => [_p('A', 'Alice')]),
      ],
      child: const MaterialApp(
        home: Scaffold(body: PartnerPickerSheet(excludeId: 'A')),
      ),
    ));
    await t.pumpAndSettle();

    expect(find.textContaining('尚無其他對象'), findsOneWidget);
  });
}
```

**Step 2：跑 test 確認 FAIL**

```bash
cmd.exe /c "flutter.bat test test\widget\features\partner\partner_picker_sheet_test.dart --reporter expanded"
```

預期：FAIL — sheet 不存在。

**Step 3：實作 sheet**

```dart
// lib/features/partner/presentation/widgets/partner_picker_sheet.dart
//
// Reusable partner picker. Used by:
//   - Task 12 merge picker (excludeId = self)
//   - Task 13 conversation reassign (excludeId = current partnerId)
//
// Design doc §5 originally proposed `showCreateNewAction` to inline-add
// a Partner from the picker. PR-B ships **without** that action — see
// "Reality Check — Design Doc §5 Deviation". The empty state instead
// shows a hint pointing the user to the home Partner list.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/partner.dart';
import '../providers/partner_providers.dart';

class PartnerPickerSheet extends ConsumerStatefulWidget {
  final String? excludeId;
  final void Function(Partner)? onSelected;

  const PartnerPickerSheet({
    super.key,
    this.excludeId,
    this.onSelected,
  });

  @override
  ConsumerState<PartnerPickerSheet> createState() =>
      _PartnerPickerSheetState();
}

class _PartnerPickerSheetState extends ConsumerState<PartnerPickerSheet> {
  final _filterCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(partnerListProvider);
    final candidates = all
        .where((p) => p.id != widget.excludeId)
        .where((p) =>
            _query.isEmpty ||
            p.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _filterCtrl,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '搜尋對象名稱',
            ),
            onChanged: (s) => setState(() => _query = s),
          ),
        ),
        if (candidates.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              '尚無其他對象，先回首頁建立後再操作',
              textAlign: TextAlign.center,
            ),
          )
        else
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final p in candidates)
                  ListTile(
                    title: Text(p.name),
                    onTap: () => widget.onSelected?.call(p),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
```

**Step 4：跑 test 確認 PASS**

預期：4/4 PASS。

**Step 5：Commit**

```bash
git add lib/features/partner/presentation/widgets/partner_picker_sheet.dart \
        test/widget/features/partner/partner_picker_sheet_test.dart
git commit -m "[feat] PartnerPickerSheet — merge / reassign 共用對象選擇器 (Task 2)

filter + ListTile + onSelected callback。design doc §5 提的
showCreateNewAction 暫不 ship（理由見 PR-B plan §Reality Check），
empty state 顯示 hint 指向首頁建立 Partner。"
```

---

## Task 3 — PartnerMergeConfirmDialog（D 版內容）

**Files:**
- Create: `lib/features/partner/presentation/dialogs/partner_merge_confirm_dialog.dart`
- Create: `test/widget/features/partner/partner_merge_confirm_dialog_test.dart`

**Step 1：寫 failing widget tests**

斷言：dialog 顯示 `N 對話` + `M traits` + 紅字「⚠️ 此操作無法復原」+ 取消/確認兩按鈕；確認 → onConfirm callback；取消 → onCancel callback；no merge call here（dialog 純 UI，merge 由 caller 串）。

```dart
testWidgets('dialog shows N convos + M traits + red 不可逆 warning', (t) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () => showDialog(
            context: ctx,
            builder: (_) => PartnerMergeConfirmDialog(
              fromName: 'Alice',
              toName: 'Bob',
              conversationCount: 3,
              traitCount: 7,
              onConfirm: () {},
              onCancel: () {},
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();

  expect(find.textContaining('Alice'), findsWidgets);
  expect(find.textContaining('Bob'), findsWidgets);
  expect(find.textContaining('3'), findsWidgets); // N 對話
  expect(find.textContaining('7'), findsWidgets); // M traits
  expect(find.textContaining('不可復原'), findsOneWidget);
  expect(find.text('確認合併'), findsOneWidget);
  expect(find.text('取消'), findsOneWidget);
});

testWidgets('confirm tap fires onConfirm exactly once', (t) async {
  var confirmCount = 0;
  /* ...show dialog with onConfirm: () => confirmCount++... */
  await t.tap(find.text('確認合併'));
  await t.pumpAndSettle();
  expect(confirmCount, 1);
});

testWidgets('cancel tap fires onCancel and dismisses', (t) async {
  var cancelled = false;
  /* ...show dialog... */
  await t.tap(find.text('取消'));
  await t.pumpAndSettle();
  expect(cancelled, isTrue);
});
```

**Step 2：跑 test 確認 FAIL**

**Step 3：實作 dialog**

```dart
// lib/features/partner/presentation/dialogs/partner_merge_confirm_dialog.dart
//
// D-variant confirm UI per Phase 3 design doc §3:
//   - N 對話搬遷 + M traits 聯集（具象 metric）
//   - 紅字「⚠️ 此操作無法復原」（destructive 心理安全感）
//   - 「保留 B avatar」隱含於選 B，dialog 不再贅述
import 'package:flutter/material.dart';

class PartnerMergeConfirmDialog extends StatelessWidget {
  final String fromName;
  final String toName;
  final int conversationCount;
  final int traitCount;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const PartnerMergeConfirmDialog({
    super.key,
    required this.fromName,
    required this.toName,
    required this.conversationCount,
    required this.traitCount,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('將 $fromName 合併到 $toName？'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$conversationCount 對話將搬遷'),
          Text('$traitCount 個特質聯集保留'),
          const SizedBox(height: 12),
          Text(
            '⚠️ 此操作不可復原',
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            onCancel();
            Navigator.of(context).pop();
          },
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () {
            onConfirm();
            Navigator.of(context).pop();
          },
          child: const Text('確認合併'),
        ),
      ],
    );
  }
}
```

**Step 4：跑 test PASS**

**Step 5：Commit**

```bash
git add lib/features/partner/presentation/dialogs/partner_merge_confirm_dialog.dart \
        test/widget/features/partner/partner_merge_confirm_dialog_test.dart
git commit -m "[feat] PartnerMergeConfirmDialog — D 版（具象 metric + 紅字不可逆）(Task 3)

純 UI；onConfirm/onCancel callback 由 caller (merge picker screen) 串
PartnerWriteController.merge + GoRouter 跳轉。dialog 自身只負責顯示
與 dismiss。"
```

---

## Task 4 — Wire ⋮ menu + PartnerMergePickerScreen + 路由

**Files:**
- Create: `lib/features/partner/presentation/screens/partner_merge_picker_screen.dart`
- Modify: `lib/features/partner/presentation/screens/partner_detail_screen.dart`（merge item enable + nav）
- Modify: GoRouter 設定（locate via `grep -rn "GoRoute" lib/core/`）— 加 `/partner/:id/merge` route
- Modify/Add: `test/widget/features/partner/partner_detail_screen_test.dart`（更新「⋮ 三 disabled」test → 變「merge enabled / edit+delete still disabled」）+ 新檔 `partner_merge_picker_screen_test.dart`

**Step 1：寫 failing widget tests**

PartnerDetail 既有 test 改 + 新 test：

```dart
// test/widget/features/partner/partner_detail_screen_test.dart 現有 test 改：
testWidgets('⋮ menu: merge ENABLED, edit+delete still 即將推出', (t) async {
  await t.pumpWidget(ProviderScope(
    overrides: [
      partnerByIdProvider('p1').overrideWith((_) => _p()),
      partnerAggregateProvider('p1')
          .overrideWith((_) => PartnerAggregateView.empty()),
      conversationsByPartnerProvider('p1')
          .overrideWith((_) => const <Conversation>[]),
      partnerListProvider.overrideWith(
        (_) => [_p(), _otherPartner('q1', 'Bob')],
      ),
    ],
    child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
  ));
  await t.pumpAndSettle();
  await t.tap(find.byIcon(Icons.more_vert));
  await t.pumpAndSettle();

  expect(find.text('合併到其他對象'), findsOneWidget); // no 即將推出
  expect(find.text('編輯對象（即將推出）'), findsOneWidget);
  expect(find.text('刪除對象（即將推出）'), findsOneWidget);
});

testWidgets('⋮ menu: merge DISABLED when only one partner exists',
    (t) async {
  await t.pumpWidget(ProviderScope(
    overrides: [
      partnerByIdProvider('p1').overrideWith((_) => _p()),
      // ...
      partnerListProvider.overrideWith((_) => [_p()]), // only self
    ],
    child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
  ));
  await t.pumpAndSettle();
  await t.tap(find.byIcon(Icons.more_vert));
  await t.pumpAndSettle();

  expect(find.text('合併到其他對象（需至少 2 個對象）'), findsOneWidget);
});

testWidgets('⋮ merge tap navigates to /partner/p1/merge', (t) async {
  // use a GoRouter with /partner/:id/merge stub route
  // tap merge → expect to land on stub
});
```

新 test for picker screen：

```dart
// test/widget/features/partner/partner_merge_picker_screen_test.dart
testWidgets('picker selection → confirm dialog with correct counts',
    (t) async {
  // override partnerListProvider with 3 partners (self + 2 others)
  // override partnerAggregateProvider for 'A' to view with 3 convs / 7 traits
  // navigate to picker for 'A'
  // tap 'B' → confirm dialog appears
  // assert 3 + 7 + 紅字
});

testWidgets('confirm tap calls PartnerWriteController.merge + go(/partner/B)',
    (t) async {
  final fake = _RecordingPartnerWriteController();
  await t.pumpWidget(ProviderScope(
    overrides: [
      partnerWriteControllerProvider.overrideWith(() => fake),
      // ...
    ],
    child: /* MaterialApp.router with picker on 'A' */,
  ));
  // ... interact ...
  expect(fake.mergeCalled, isTrue);
  expect(fake.fromId, 'A');
  expect(fake.toId, 'B');
  // assert nav to /partner/B
});

testWidgets('cancel does not call merge', (t) async {
  // ...similar, tap 取消, assert fake.mergeCalled isFalse...
});
```

**Codex-Review-Hot-Spot**：fake 與 PR-A `RecordingConversationWriteController` 同 pattern，subclass `PartnerWriteController` 覆寫 `merge` capture args，避免實接 Hive。放在 `test/widget/features/partner/_fakes/recording_partner_write_controller.dart`。

**Step 2：跑 tests 確認 FAIL**

**Step 3：實作**

3a. 改 `partner_detail_screen.dart`：

```dart
// 抓 partnerListProvider，計算 enableMerge
final partners = ref.watch(partnerListProvider);
final hasOtherPartner = partners.any((p) => p.id != partnerId);

PopupMenuButton<String>(
  icon: const Icon(Icons.more_vert),
  itemBuilder: (_) => [
    PopupMenuItem(
      value: 'merge',
      enabled: hasOtherPartner,
      child: Text(hasOtherPartner
          ? '合併到其他對象'
          : '合併到其他對象（需至少 2 個對象）'),
    ),
    const PopupMenuItem(
      value: 'edit',
      enabled: false,
      child: Text('編輯對象（即將推出）'),
    ),
    const PopupMenuItem(
      value: 'delete',
      enabled: false,
      child: Text('刪除對象（即將推出）'),
    ),
  ],
  onSelected: (v) {
    if (v == 'merge') context.push('/partner/$partnerId/merge');
  },
),
```

同時更新 line 10-12 stale comment（`Phase 4 Tasks 12-13` → `Phase 3 Task 12 wires merge; Phase 4 wires edit/delete`）。

3b. 寫 `partner_merge_picker_screen.dart`：

```dart
class PartnerMergePickerScreen extends ConsumerWidget {
  final String fromPartnerId;
  const PartnerMergePickerScreen({super.key, required this.fromPartnerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('選擇要合併到的對象')),
      body: PartnerPickerSheet(
        excludeId: fromPartnerId,
        onSelected: (target) => _confirm(context, ref, target),
      ),
    );
  }

  void _confirm(BuildContext context, WidgetRef ref, Partner target) {
    final fromAgg = ref.read(partnerAggregateProvider(fromPartnerId));
    final convCount = ref
        .read(conversationsByPartnerProvider(fromPartnerId))
        .length;
    final fromPartner = ref.read(partnerByIdProvider(fromPartnerId));
    if (fromPartner == null) return;
    final traitCount = fromAgg.traits.length;
    showDialog(
      context: context,
      builder: (_) => PartnerMergeConfirmDialog(
        fromName: fromPartner.name,
        toName: target.name,
        conversationCount: convCount,
        traitCount: traitCount,
        onConfirm: () async {
          await ref
              .read(partnerWriteControllerProvider.notifier)
              .merge(fromId: fromPartnerId, toId: target.id);
          if (context.mounted) context.go('/partner/${target.id}');
        },
        onCancel: () {},
      ),
    );
  }
}
```

**Codex-Review-Hot-Spot**：`fromAgg.traits.length` 假設 `PartnerAggregateView` 有 `traits` field。執行時先 `grep "traits" lib/features/partner/domain/extensions/partner_aggregates.dart` 確認 field 名（可能是 `traits` 或 `traitTags` 或 union 結構）。若名字不同，調整代入；若沒有同等 field，**unwind 為「對話數搬遷 + 自定義備註合併」單行**（接受 design doc D 版的精神，捨棄精確 trait count）。此 unwind 不影響 plan core，標 test reason 即可。

3c. 加路由（在 `lib/core/router/...` 或主 GoRouter config 處）：

```dart
GoRoute(
  path: '/partner/:id/merge',
  builder: (ctx, state) => PartnerMergePickerScreen(
    fromPartnerId: state.pathParameters['id']!,
  ),
),
```

執行時先 `grep -rn "GoRoute" lib/` 找 router 主檔，加在 `/partner/:id` 同層。

**Step 4：跑 tests 確認 PASS**

```bash
cmd.exe /c "flutter.bat test test\widget\features\partner --reporter expanded"
```

預期：partner widget tests 全綠（既有 21 + Task 1-2-3 新增 + Task 4 新增）。

**Step 5：Commit**

```bash
git add lib/features/partner/presentation/screens/partner_detail_screen.dart \
        lib/features/partner/presentation/screens/partner_merge_picker_screen.dart \
        lib/core/router/...  \
        test/widget/features/partner/partner_detail_screen_test.dart \
        test/widget/features/partner/partner_merge_picker_screen_test.dart \
        test/widget/features/partner/_fakes/recording_partner_write_controller.dart
git commit -m "[feat] Partner ⋮ merge enable + merge picker screen + 路由 (Task 4)

PartnerDetail ⋮ menu 第 1 項從 disabled 改 enabled（且 list-empty 時動態
disable + tooltip 提示）。新 picker screen route /partner/:id/merge 用
PartnerPickerSheet + PartnerMergeConfirmDialog 串到 PartnerWriteController.
nav 完成後 context.go('/partner/<targetId>')。"
```

---

## Task 5 — PartnerConversationTile：trailing 改 PopupMenuButton

**Files:**
- Modify: `lib/features/partner/presentation/widgets/partner_conversation_tile.dart`
- Modify: `test/widget/features/partner/partner_conversation_tile_test.dart`（新檔；目前無此 test）

**Reality Check sub-note**：Phase 2 widget test `renders one tile per conversation when list non-empty`（`partner_detail_screen_test.dart` line 121-136）只 `find.text('第 a 段')`，不依賴 trailing 形狀。trailing 從 `Icon(chevron_right)` 改 `PopupMenuButton` **不會**破這個 test。但 build a smoke test 確認 ⋮ 出現 + items 對。

**Step 1：寫 failing widget tests**

```dart
testWidgets('trailing renders ⋮ icon (not chevron_right) + popup items',
    (t) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: PartnerConversationTile(
        conversation: _convA,
        onTap: () {},
        onReassign: () {},
      ),
    ),
  ));
  expect(find.byIcon(Icons.more_vert), findsOneWidget);
  expect(find.byIcon(Icons.chevron_right), findsNothing);

  await t.tap(find.byIcon(Icons.more_vert));
  await t.pumpAndSettle();
  expect(find.text('改派到其他對象'), findsOneWidget);
  expect(find.text('刪除對話（即將推出）'), findsOneWidget);
});

testWidgets('改派 tap fires onReassign callback', (t) async {
  var fired = false;
  /* ...pumpWidget with onReassign: () => fired = true ... */
  await t.tap(find.byIcon(Icons.more_vert));
  await t.pumpAndSettle();
  await t.tap(find.text('改派到其他對象'));
  await t.pumpAndSettle();
  expect(fired, isTrue);
});

testWidgets('cell main area tap still fires onTap', (t) async {
  // assert onTap still called on title region tap, not on ⋮
});
```

**Step 2：跑 tests 確認 FAIL**

**Step 3：改 tile**

```dart
// lib/features/partner/presentation/widgets/partner_conversation_tile.dart
class PartnerConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;
  final VoidCallback? onReassign; // new — null = no reassign action
  const PartnerConversationTile({
    super.key,
    required this.conversation,
    required this.onTap,
    this.onReassign,
  });

  @override
  Widget build(BuildContext context) {
    final heat = conversation.lastEnthusiasmScore;
    return ListTile(
      onTap: onTap,
      title: Text(conversation.name, style: AppTypography.titleSmall),
      subtitle: Text(
        '${conversation.currentRound} 輪 · ${conversation.messages.length} 則訊息'
        '${heat != null ? ' · 熱度 $heat' : ''}',
        style: AppTypography.bodySmall.copyWith(
          color: AppColors.onBackgroundSecondary,
        ),
      ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        onSelected: (v) {
          if (v == 'reassign') onReassign?.call();
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'reassign',
            enabled: onReassign != null,
            child: const Text('改派到其他對象'),
          ),
          const PopupMenuItem(
            value: 'delete',
            enabled: false,
            child: Text('刪除對話（即將推出）'),
          ),
        ],
      ),
    );
  }
}
```

**Step 4：跑 tests PASS**

**Step 5：Commit**

```bash
git add lib/features/partner/presentation/widgets/partner_conversation_tile.dart \
        test/widget/features/partner/partner_conversation_tile_test.dart
git commit -m "[refactor] PartnerConversationTile trailing: chevron → ⋮ menu (Task 5)

新 onReassign callback 由 caller (PartnerDetailScreen) 串 picker。
[改派到其他對象] enabled / [刪除對話] disabled (Phase 4)。tile 維持 pure，
不 own routing。"
```

---

## Task 6 — ConversationReassignPicker

**Files:**
- Create: `lib/features/conversation/presentation/dialogs/conversation_reassign_picker.dart`
- Create: `test/widget/features/partner/conversation_reassign_picker_test.dart`（test 放 partner 子目錄以滿足 CI gate；該 test 涵蓋 partner-side reassign 流，scope 對齊）

**Reality Check sub-note**：picker 內部 reuse `PartnerPickerSheet`，外殼是 `showModalBottomSheet`。selected target → call `ConversationWriteController.save(updatedConversation, previousPartnerId: oldId)` —— 此 controller signature 已確認（`lib/features/conversation/data/providers/conversation_write_controller.dart:48-56`），不需新增 surface。

**Step 1：寫 failing widget tests**

```dart
testWidgets('reassign sheet opens with picker excluding current partner',
    (t) async {
  await t.binding.setSurfaceSize(const Size(400, 1200));
  addTearDown(() => t.binding.setSurfaceSize(null));

  await t.pumpWidget(ProviderScope(
    overrides: [
      partnerListProvider.overrideWith(
        (_) => [_p('A', 'Alice'), _p('B', 'Bob'), _p('C', 'Cara')],
      ),
    ],
    child: MaterialApp(/* harness shows picker for conv whose partnerId='A' */),
  ));
  // open picker
  await t.tap(find.text('open picker'));
  await t.pumpAndSettle();

  expect(find.text('Bob'), findsOneWidget);
  expect(find.text('Cara'), findsOneWidget);
  expect(find.text('Alice'), findsNothing);
});

testWidgets('selecting target calls ConversationWriteController.save with previousPartnerId',
    (t) async {
  final fake = RecordingConversationWriteController();
  // ...pump with override...
  // ...open picker, tap 'B'...
  expect(fake.savedConversation?.partnerId, 'B');
  expect(fake.savedPreviousPartnerId, 'A');
});

testWidgets('empty picker (only self exists) shows hint, no save', (t) async {
  // override partnerListProvider with [_p('A', 'Alice')] only
  // open picker → expect hint「尚無其他對象」
  // expect no save
});
```

**Codex-Review-Hot-Spot**：reuse PR-A 的 `RecordingConversationWriteController`（路徑 `test/widget/features/conversation/_fakes/recording_conversation_write_controller.dart`）—— 但 PR-B 不該動 PR-A 領地。**解法：在 `test/widget/features/partner/_fakes/` 同檔複製**（10 行 fake），標 comment「duplicated from PR-A path; merge in Phase 4 cleanup PR」。Codex review 必 acknowledge 此複製。

**Step 2：跑 tests 確認 FAIL**

**Step 3：實作 picker**

```dart
// lib/features/conversation/presentation/dialogs/conversation_reassign_picker.dart
//
// Modal sheet that lets the user move a single Conversation to another
// Partner. Reuses PartnerPickerSheet for the list UI.
//
// Save path: ConversationWriteController.save(c, previousPartnerId:)
// — Phase 1's narrow contract handles dual-side invalidation.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../partner/presentation/widgets/partner_picker_sheet.dart';
import '../../data/providers/conversation_write_controller.dart';
import '../../domain/entities/conversation.dart';

Future<void> showConversationReassignPicker(
  BuildContext context, {
  required Conversation conversation,
  required WidgetRef ref,
}) {
  return showModalBottomSheet(
    context: context,
    builder: (_) => SafeArea(
      child: PartnerPickerSheet(
        excludeId: conversation.partnerId,
        onSelected: (target) async {
          final previousPartnerId = conversation.partnerId;
          conversation.partnerId = target.id;
          await ref
              .read(conversationWriteControllerProvider.notifier)
              .save(conversation, previousPartnerId: previousPartnerId);
          if (context.mounted) Navigator.of(context).pop();
        },
      ),
    ),
  );
}
```

**Step 4：跑 tests PASS**

**Step 5：Commit**

```bash
git add lib/features/conversation/presentation/dialogs/conversation_reassign_picker.dart \
        test/widget/features/partner/conversation_reassign_picker_test.dart \
        test/widget/features/partner/_fakes/recording_conversation_write_controller.dart
git commit -m "[feat] ConversationReassignPicker — modal sheet + 雙端 invalidate (Task 6)

reuse PartnerPickerSheet（excludeId = current partnerId）+ Phase 1
ConversationWriteController.save(previousPartnerId:) 雙端 invalidate
contract。fake 暫時複製自 PR-A path，Phase 4 cleanup 統一。"
```

---

## Task 7 — Wire reassign from PartnerDetail

**Files:**
- Modify: `lib/features/partner/presentation/screens/partner_detail_screen.dart`（pass `onReassign` to each tile）
- Modify: `test/widget/features/partner/partner_detail_screen_test.dart`

**Step 1：寫 failing test**

```dart
testWidgets('PartnerDetail tile ⋮ → 改派 → picker opens with excludeId=current',
    (t) async {
  await t.binding.setSurfaceSize(const Size(400, 1200));
  addTearDown(() => t.binding.setSurfaceSize(null));

  await t.pumpWidget(ProviderScope(
    overrides: [
      partnerByIdProvider('p1').overrideWith((_) => _p()),
      partnerAggregateProvider('p1')
          .overrideWith((_) => PartnerAggregateView.empty()),
      conversationsByPartnerProvider('p1')
          .overrideWith((_) => [_conv('a')]),
      partnerListProvider.overrideWith(
        (_) => [_p(), _otherPartner('q1', 'Bob')],
      ),
    ],
    child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
  ));
  await t.pumpAndSettle();

  await t.tap(find.byIcon(Icons.more_vert).at(1)); // tile's ⋮ (not header's)
  await t.pumpAndSettle();
  await t.tap(find.text('改派到其他對象'));
  await t.pumpAndSettle();

  // Picker opens, shows 'Bob' (excluded p1)
  expect(find.text('Bob'), findsOneWidget);
});
```

**Codex-Review-Hot-Spot**：`find.byIcon(Icons.more_vert)` 會抓到 header ⋮ + 每 tile 的 ⋮。`.at(1)` 假設 header 在 [0]。若 widget tree 變動，改 `find.descendant(of: find.byType(PartnerConversationTile), matching: find.byIcon(Icons.more_vert))` 更穩。

**Step 2：跑 test FAIL**

**Step 3：modify PartnerDetailScreen**

```dart
// inside ListView builder:
...conversations.map(
  (c) => PartnerConversationTile(
    conversation: c,
    onTap: () => context.push('/conversation/${c.id}'),
    onReassign: () => showConversationReassignPicker(
      context,
      conversation: c,
      ref: ref,
    ),
  ),
),
```

**Step 4：跑 test PASS**

**Step 5：Commit**

```bash
git add lib/features/partner/presentation/screens/partner_detail_screen.dart \
        test/widget/features/partner/partner_detail_screen_test.dart
git commit -m "[feat] PartnerDetail tile 接 onReassign — 串 ConversationReassignPicker (Task 7)

每個 PartnerConversationTile 接到 showConversationReassignPicker，
picker excludeId = 當前 partnerId，selection 後雙端 invalidate +
sheet 自動關。用戶不換頁，cell 從 list 自然消失。"
```

---

## Task 8 — Full sweep + push

**Step 1：跑全 partner widget + unit + analyze**

```bash
cmd.exe /c "flutter.bat test test\widget\features\partner --reporter expanded"
cmd.exe /c "flutter.bat test test\unit\features\partner --reporter expanded"
cmd.exe /c "flutter.bat analyze --no-fatal-infos"
```

預期：
- partner widget tests：原 21 + 新增 (PR-B 約 15-20 條)；全綠
- partner unit tests：A1 既有 + Task 1 新增 3 條；全綠
- analyze：`No issues found!`

**Step 2：跑 PR-A 領地確認沒誤動 conversation tests**

```bash
cmd.exe /c "flutter.bat test test\widget\features\conversation --reporter expanded"
```

預期：PR-A 4 條 widget test 仍綠（PR-B 不該動到此目錄）。

**Step 3：push branch**

```bash
git push -u origin feature/partner-entity-A2-flows-pickers
```

預期：branch 上 remote，~8 個 commit 全推上。

---

## Task 9 — 喊 Codex spec review + queue 開新 item

**Step 1：在 `docs/reviews/ai-arbitration-queue.md` 頂部加 PR-B live item**

```markdown
## [LIVE] A2 Phase 3 PR-B — Merge Picker + Reassign ⋮ Menu Spec Review

**Status**: AWAITING_CODEX_SPEC_REVIEW
**Branch**: `feature/partner-entity-A2-flows-pickers`
**Plan**: `docs/plans/2026-04-27-partner-entity-A2-phase3-pr-b-impl.md`
**Design**: `docs/plans/2026-04-27-partner-entity-A2-phase3-design.md`
**Master plan**: `docs/plans/2026-04-26-partner-entity-A2-impl.md` Tasks 12-13

### Round 1 — YYYY-MM-DD HH:MM

Plan scope（8 個 task，預估 ~15-20 widget tests + 3 unit tests + 5 新 prod files + 3 modify points）：
- Task 1：PartnerWriteController（**design doc §5 deviation —— repo 不能 own invalidation**）
- Task 2：PartnerPickerSheet（共用 widget）
- Task 3：PartnerMergeConfirmDialog（D 版）
- Task 4：⋮ menu enable + merge picker screen + 路由
- Task 5：PartnerConversationTile trailing → ⋮
- Task 6：ConversationReassignPicker
- Task 7：Wire reassign from PartnerDetail
- Task 8：Full sweep + push

### Reviewer-Hint

主要 trade-off：
1. **PartnerWriteController 引入** — design doc §5「repo 觸發 invalidation」是錯的；plan 修正為新增 controller 對齊 Phase 1 ConversationWriteController 契約。Codex 必須 acknowledge 此修正。
2. **「+ 新建對象」inline action 暫不 ship** — design doc §5 提到 `showCreateNewAction: true`，plan 因複雜度（push + return 重接 reassign）暫不做，empty state 顯示 hint 引導用戶回首頁建立。是否接受？
3. **`PartnerRepository.merge` 內部繞過 `ConversationWriteController`**（A1 既有實作，PR-B 不重寫 transaction 邊界）— controller post-hoc 雙端 invalidate 等價。Codex 必須 acknowledge。
4. **PartnerConversationTile trailing 從 chevron 改 ⋮** — Phase 3 design doc §3 已決議偏離 master plan B 版（trailing ⋮）；plan 完整繼承。
5. **Fake notifier 複製問題** — `RecordingConversationWriteController` 在 PR-A 已 ship 於 `test/widget/features/conversation/_fakes/`，PR-B 邊界規定不動 PR-A 領地，故複製到 partner 子目錄。Phase 4 cleanup 一起合一。

預期 Verdict：APPROVED 或 REVISE（小調整）。最大風險點是 §1 PartnerWriteController 的範圍（會否擴張到 Phase 4 delete 的設計）。
```

**Step 2：Commit queue update**

```bash
git add docs/reviews/ai-arbitration-queue.md
git commit -m "[docs] queue: A2 Phase 3 PR-B spec review item OPEN"
git push
```

**Step 3：等 Codex spec review 結果**

- ✅ APPROVED → 喊 executing-plans 開工 Task 0-8
- 🔴 REVISE → 依 verdict patch plan，update queue Round 2，重審

---

## Failure Protocols

### Test 在 Task 1-7 任一 step FAIL（非 finder 問題，是真實 chain regression / API 不對）

PR-B scope expand 為 production fix。流程：
1. STOP，標出哪一條 chain / API assumption 斷了
2. 寫 1 個 commit 修 production，commit msg 開頭 `[fix]`
3. plan 末尾加 Round 2 entry 描述 fix
4. queue item Status 改 `IN_PROGRESS_PRODUCTION_FIX`
5. 重跑對應 task + 後續 task
6. Codex code review 必須看 fix（不只是看 test）

### `PartnerAggregateView.traits` field 名不對

執行 Task 4 step 3 前 grep 確認。若不對，unwind 為「dialog 顯示對話搬遷數 + 「同時保留特質聯集」抽象 wording」（不顯具象 trait count）。標 plan deviation，更新對應 test reason。

### GoRouter 主檔結構不熟

執行 Task 4 step 3c 前 `grep -rn "GoRoute" lib/core/ lib/main.dart` 找入口。若 router 是 `Provider.autoDispose` 形式，要在 `ProviderScope.overrides` 中提供 router；test harness 用內聯 stub router（同 PR-A pattern）。

### Windows flutter.bat hang

`add_partner_screen_test.dart` 「successful submit」test 已知會 hang（skip:true）。PR-B 8 個 task 的 widget test **不要碰** `pushReplacement` / Hive write future；用 fake controller no-op。若仍 hang，疑點優先級：
1. `pumpAndSettle` 在含 GradientBackground 樹下：改 `_settle(t)` helper（PR-A Task 2 commit `4dbcb07` pattern）
2. 800x600 surface 折疊：`setSurfaceSize(400, 1200)` + `ensureVisible`
3. Provider 沒 dispose：每 test `addTearDown(() => container?.dispose())`
4. 環境性 Windows kernel cache：**不再戰**，標 skip + reason，不 block PR-B

### 並行 PR-A merge 後 main 已 advance

`git fetch && git rebase origin/main`（PR-A 在 PR-B 不動的目錄，0 conflict 機率高）。若有 conflict，先讀 conflict region，決定保留哪邊；不要 `--theirs` / `--ours` 一鍵了結。

---

## Inherited Tech Traps（PR-A Lessons — 必套）

### 陷阱 1：`pumpAndSettle()` 在 GradientBackground 死鎖

PR-B 的 `PartnerMergePickerScreen` 若沒 wrap `GradientBackground`（Phase 2 PartnerDetail 也沒 wrap，pattern 沿用），可正常用 `pumpAndSettle`。**但若有人為了視覺一致性加了 GradientBackground，必改 `_settle(t)` helper：**

```dart
Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}
```

每 widget test 在含 `GradientBackground` 的 widget tree 都該用 `_settle()`，**禁** `pumpAndSettle()`。

### 陷阱 2：800×600 surface 折疊下半部

PartnerDetail 既有 surface 是 800×600 的 hard-coded test 假設了（lines 79-83 用 `setSurfaceSize(400, 900)`）。PR-B 的 picker / dialog / modal sheet 大概率有「需要捲到下方按鈕」的狀況，要套：

```dart
await t.binding.setSurfaceSize(const Size(400, 1200));
addTearDown(() => t.binding.setSurfaceSize(null));

await t.ensureVisible(find.text('確認合併'));
await t.tap(find.text('確認合併'));
```

每個 PR-B 新 widget test 開頭都該預設加上 `setSurfaceSize(400, 1200)` + `addTearDown` 兩行。

---

## DoD（Definition of Done）

PR-B 真正完成的條件：

- [ ] 8-10 commits 推到 `feature/partner-entity-A2-flows-pickers`
- [ ] CI 全綠（`flutter analyze` + `flutter test test/widget/features/partner/`，per PR #6 gate）
- [ ] partner widget tests 全綠（既有 21 + PR-B 新增 ~15-20）
- [ ] partner unit tests 全綠（A1 既有 + PartnerWriteController 新增 3）
- [ ] PR-A 領地 (`test/widget/features/conversation/`) 不變動
- [ ] Codex spec review APPROVED
- [ ] Codex code review APPROVED
- [ ] PR merge 進 main
- [ ] TF QA 4 項全綠（merge / reassign / 同名 partner merge / merged Partner detail navigation — per design doc §6 manual gate）
- [ ] queue item Status: CLOSED
- [ ] `reference_partner_refactor_in_flight.md` Phase 3 PR-B 段更新為 ✅
- [ ] memory 補一筆「Phase 4 待議：showCreateNewAction inline + delete handler + traits-vs-traitTags 命名」issue tracker entry

---

## 後續

PR-B merge → Phase 3 整體 CLOSED → 切 Phase 4：
- Task 14 same-name banner（依賴 PR-B 的 merge picker — 已 ship）
- Task 15-17 copy sweep / ship checklist / TestFlight gate
- Cleanup PR：`reportDataProvider` 遷出 global feed → `conversationsProvider` invalidate 從 `ConversationWriteController` / `PartnerWriteController` 全部 retire
- Cleanup PR：`RecordingConversationWriteController` fake 從 partner / conversation 兩處複製合一

詳細在 Phase 4 design doc（待開工）。
