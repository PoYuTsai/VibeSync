# Partner Entity Refactor — A2 Phase 4 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ship A2 Phase 4 (Tasks 14-18 + hidden Partner delete API) — visual restoration / dedupe banner / copy sweep / @Deprecated cleanup / docs closeout.

**Architecture:** TDD per task；Task 18 (data + UI) → 14 (data + UI) → 15 → 16 → 17。Codex spec review (verdict REVISED_AND_APPROVED `1c74722`) 已 patch design doc，本 plan 嚴格對齊 patched contract。

**Tech Stack:** Flutter 3.x · Riverpod (FutureProvider.family for async banner state) · Hive CE · GoRouter · SharedPreferences

**Predecessors:** main `1c74722` → A1 → Phase 1-3 全 ship → Phase 4 design doc patched
**Branch:** `feature/partner-entity-A2-polish`
**Design doc:** `docs/plans/2026-04-28-partner-entity-A2-phase4-design.md`
**Codex spec review:** `docs/reviews/2026-04-28_partner-entity-A2-phase4-spec_codex-review.md`

---

## Pre-flight

Branch already cut from main `1c74722` at session start.

Run baseline:

```bash
~/flutter/bin/flutter test test/widget/features/partner/ test/widget/features/conversation/ test/unit/features/partner/ 2>&1 | tail -10
~/flutter/bin/flutter analyze --no-fatal-infos lib test 2>&1 | tail -5
```

Expected (from PR-B merge state):
- 52 pass / 1 skip / 0 fail (partner widget + conversation widget + partner unit subset)
- 1 pre-existing info on `partner_write_controller_test.dart:45` (library_private_types_in_public_api)

If baseline diverges → STOP and investigate before any task.

---

## Task 1 — Partner delete API（data layer, design doc §6.1 / Task 18a）

**Files:**
- Modify: `lib/features/partner/data/repositories/partner_repository.dart` (+ `delete()` + `PartnerHasConversationsException` class export)
- Modify: `lib/features/partner/data/providers/partner_write_controller.dart` (+ `delete()` + `_invalidateDeleteScopes`)
- Create: `test/unit/features/partner/partner_repository_delete_test.dart`
- Modify: `test/unit/features/partner/partner_write_controller_test.dart` (+ delete test cases)

### Step 1.1 — Write failing repo tests

Create `test/unit/features/partner/partner_repository_delete_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/partner/data/repositories/partner_repository.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';

void main() {
  late Box<Partner> partnerBox;
  late Box<Conversation> conversationBox;
  late PartnerRepository repo;

  setUp(() async {
    final tmp = await Directory.systemTemp.createTemp('phase4_delete_');
    Hive.init(tmp.path);
    if (!Hive.isAdapterRegistered(0)) {
      // Register adapters as the existing repo tests do.
      // (Use the same registration block as merge tests.)
    }
    partnerBox = await Hive.openBox<Partner>('partners_${DateTime.now().microsecondsSinceEpoch}');
    conversationBox = await Hive.openBox<Conversation>('conversations_${DateTime.now().microsecondsSinceEpoch}');
    repo = PartnerRepository(box: partnerBox, conversationBox: conversationBox);
  });

  tearDown(() async {
    await partnerBox.close();
    await conversationBox.close();
  });

  test('delete removes partner from box when no conversations linked', () async {
    final p = Partner(id: 'p1', name: 'A', ownerUserId: 'u1', createdAt: DateTime.now(), updatedAt: DateTime.now());
    await partnerBox.put(p.id, p);

    await repo.delete('p1');

    expect(partnerBox.containsKey('p1'), isFalse);
  });

  test('delete throws PartnerHasConversationsException when conversations exist', () async {
    final p = Partner(id: 'p1', name: 'A', ownerUserId: 'u1', createdAt: DateTime.now(), updatedAt: DateTime.now());
    await partnerBox.put(p.id, p);
    final c = Conversation(id: 'c1', name: '對話 1', updatedAt: DateTime.now(), partnerId: 'p1');
    await conversationBox.put(c.id, c);

    expect(
      () => repo.delete('p1'),
      throwsA(isA<PartnerHasConversationsException>()
          .having((e) => e.conversationCount, 'count', 1)),
    );
    expect(partnerBox.containsKey('p1'), isTrue);
  });

  test('delete blocks even when conversation has currentRound == 0', () async {
    final p = Partner(id: 'p1', name: 'A', ownerUserId: 'u1', createdAt: DateTime.now(), updatedAt: DateTime.now());
    await partnerBox.put(p.id, p);
    final c = Conversation(id: 'c0', name: '對話 0', updatedAt: DateTime.now(), partnerId: 'p1', currentRound: 0);
    await conversationBox.put(c.id, c);

    expect(
      () => repo.delete('p1'),
      throwsA(isA<PartnerHasConversationsException>()),
    );
  });
}
```

**Note**: 抄既有 `partner_repository_merge_test.dart` 的 Hive setup pattern；adapter 註冊段 import 同檔的 helper。

### Step 1.2 — Run tests, expect FAIL

```bash
~/flutter/bin/flutter test test/unit/features/partner/partner_repository_delete_test.dart
```

Expected: 3 fail（`delete` undefined / `PartnerHasConversationsException` undefined）

### Step 1.3 — Implement repo `delete()` + exception

Modify `lib/features/partner/data/repositories/partner_repository.dart`，在檔尾 `merge()` 之後加：

```dart
  Future<void> delete(String partnerId) async {
    final hasConv = _conversationBox.values
        .where((c) => c.partnerId == partnerId)
        .length;
    if (hasConv > 0) {
      throw PartnerHasConversationsException(hasConv);
    }
    await _box.delete(partnerId);
  }
}

/// Thrown by [PartnerRepository.delete] when the partner still has
/// conversations linked. Caller must surface this as informational UI and
/// guide the user toward merge / reassign instead of cascade-deleting.
class PartnerHasConversationsException implements Exception {
  PartnerHasConversationsException(this.conversationCount);
  final int conversationCount;

  @override
  String toString() =>
      'PartnerHasConversationsException(count=$conversationCount)';
}
```

Update class doc top comment：A2 surface `+ delete()`。

### Step 1.4 — Run repo tests, expect PASS

```bash
~/flutter/bin/flutter test test/unit/features/partner/partner_repository_delete_test.dart
```

Expected: 3 pass

### Step 1.5 — Write failing controller tests

Modify `test/unit/features/partner/partner_write_controller_test.dart`，加 delete group：

```dart
group('delete', () {
  test('controller delete invalidates partnerListProvider + partnerByIdProvider + partnerAggregateProvider + conversationsByPartnerProvider after success', () async {
    // Setup: empty conversations for partner 'p1', partner exists in box.
    // ... (fakes for partnerRepositoryProvider)

    final container = ProviderContainer(overrides: [
      partnerRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);

    // Prime watchers so invalidation has observable effect.
    container.read(partnerListProvider);
    container.read(partnerByIdProvider('p1'));
    container.read(partnerAggregateProvider('p1'));
    container.read(conversationsByPartnerProvider('p1'));

    await container
        .read(partnerWriteControllerProvider.notifier)
        .delete(testPartner);

    // Verify each provider was invalidated (assert read returns fresh value).
  });

  test('controller delete still invalidates scopes when repo throws', () async {
    // Use a repo override that throws PartnerHasConversationsException.
    // After expectLater(controller.delete(...), throwsException),
    // verify all 4 providers were invalidated regardless.
  });
});
```

**Note**: 抄既有 `merge` group 的 ProviderContainer + recording fake pattern（同檔 line ~80 已有先例）。

### Step 1.6 — Run controller tests, expect FAIL

```bash
~/flutter/bin/flutter test test/unit/features/partner/partner_write_controller_test.dart
```

Expected: 2 new fail（`delete` undefined on controller）

### Step 1.7 — Implement controller `delete()`

Modify `lib/features/partner/data/providers/partner_write_controller.dart`，在 `merge()` 後加：

```dart
  Future<void> delete(Partner partner) async {
    final repo = ref.read(partnerRepositoryProvider);
    try {
      await repo.delete(partner.id);
    } finally {
      _invalidateDeleteScopes(partner.id);
    }
  }

  void _invalidateDeleteScopes(String id) {
    _invalidatePartner(id);
    _invalidatePartnerScopedConversations(id);
    ref.invalidate(partnerListProvider);
    // A2 transition contract — same surface as merge for global feed.
    ref.invalidate(conversationsProvider);
  }
```

### Step 1.8 — Run all controller + repo tests, expect PASS

```bash
~/flutter/bin/flutter test test/unit/features/partner/
```

Expected: all pass (existing merge tests + new 5 delete tests = 8+ total in this dir).

### Step 1.9 — Lint + commit

```bash
~/flutter/bin/flutter analyze --no-fatal-infos lib/features/partner/data/ test/unit/features/partner/
git add lib/features/partner/data/repositories/partner_repository.dart \
        lib/features/partner/data/providers/partner_write_controller.dart \
        test/unit/features/partner/partner_repository_delete_test.dart \
        test/unit/features/partner/partner_write_controller_test.dart
git commit -m "[feat] PartnerRepository.delete() + cascade guard + controller invalidation

- delete() throws PartnerHasConversationsException when ≥1 conversation
  references partnerId（依 conversation count，不依 aggregate.totalRounds）
- PartnerWriteController.delete() try/finally invalidate
  partnerListProvider + partnerByIdProvider + partnerAggregateProvider
  + conversationsByPartnerProvider + conversationsProvider
- Codex spec review patched: 對齊 PartnerRepository._conversationBox 既有
  surface（無 listByPartner）、partnerListProvider 非 family

Reviewer-Hint: delete repo guard 用 _conversationBox.values，與 merge 同
               來源；try/finally invalidate 對齊 PR-B 0187685 紀律
Next-Step: Task 2 — PartnerListCard 視覺還原 + delete dialog two-mode"
git push -u origin feature/partner-entity-A2-polish
```

---

## Task 2 — PartnerListCard 視覺還原 + delete dialog two-mode（UI, design doc §6.2 / Task 18b）

**Files:**
- Modify: `lib/features/partner/presentation/widgets/partner_list_card.dart`
- Modify: `lib/features/partner/presentation/screens/partner_list_screen.dart` (row builder watch conversationsByPartnerProvider, capture conversationCount → onDelete)
- Create: `test/widget/features/partner/partner_list_card_test.dart`
- Modify: `test/widget/features/partner/partner_list_screen_test.dart` (+ delete dialog two-mode coverage)

### Step 2.1 — Write failing card widget tests

Create `test/widget/features/partner/partner_list_card_test.dart`：

```dart
testWidgets('renders 5 visual pieces given Partner + non-empty aggregate', ...);
testWidgets('falls back to "🌡️ 待分析" when latestHeat is null', ...);
testWidgets('shows interleaved interests+traits joined by " · " as preview, capped at 3', ...);
testWidgets('keeps at least one trait when both interests and traits exist', ...);
testWidgets('tap delete fires onDelete callback', ...);
```

Helpers：以 lifted-aggregate API mock partner + aggregate（不 ref.watch）。

### Step 2.2 — Run, expect FAIL

```bash
~/flutter/bin/flutter test test/widget/features/partner/partner_list_card_test.dart
```

Expected: 5 fail（widget visual not yet restored）

### Step 2.3 — Restore PartnerListCard 5 件套

Replace `lib/features/partner/presentation/widgets/partner_list_card.dart` body：

```dart
class PartnerListCard extends StatelessWidget {
  final Partner partner;
  final PartnerAggregateView aggregate;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const PartnerListCard({
    super.key,
    required this.partner,
    required this.aggregate,
    required this.onTap,
    this.onDelete,
  });

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return DateFormat('HH:mm').format(date);
    if (diff.inDays == 1) return '昨天';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return DateFormat('MM/dd').format(date);
  }

  /// interleave interests / traits 後 cap 3，避免 traits 被 interests 餓死。
  /// (Codex spec review HS-P4-5)
  List<String> _previewTags(List<String> interests, List<String> traits) {
    final out = <String>[];
    final maxLen = interests.length > traits.length ? interests.length : traits.length;
    for (var i = 0; i < maxLen && out.length < 3; i++) {
      if (i < interests.length) {
        out.add(interests[i]);
        if (out.length >= 3) break;
      }
      if (i < traits.length) {
        out.add(traits[i]);
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final tags = _previewTags(aggregate.unionInterests, aggregate.unionTraits);
    final heat = aggregate.latestHeat;
    final level = heat != null ? EnthusiasmLevel.fromScore(heat) : null;

    return GlassmorphicContainer(
      padding: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.avatarHerStart, AppColors.avatarHerEnd],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              partner.name.isNotEmpty ? partner.name[0] : '?',
              style: AppTypography.titleLarge.copyWith(color: Colors.black87),
            ),
          ),
        ),
        title: Row(children: [
          Expanded(child: Text(partner.name,
              style: AppTypography.titleLarge.copyWith(color: AppColors.glassTextPrimary),
              overflow: TextOverflow.ellipsis)),
          Text(_formatDate(aggregate.lastInteraction),
              style: AppTypography.caption.copyWith(color: AppColors.glassTextHint)),
        ]),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            if (level != null)
              Row(children: [
                Text(level.emoji),
                const SizedBox(width: 4),
                Text('$heat',
                    style: AppTypography.caption.copyWith(color: level.color)),
              ])
            else
              Row(children: [
                const Text('🌡️'),
                const SizedBox(width: 4),
                Text('待分析',
                    style: AppTypography.caption.copyWith(color: AppColors.glassTextHint)),
              ]),
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(tags.join(' · '),
                  style: AppTypography.caption.copyWith(color: AppColors.glassTextHint),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ],
        ),
        trailing: onDelete != null
            ? IconButton(
                icon: Icon(Icons.delete_outline, color: AppColors.glassTextHint),
                onPressed: onDelete,
                tooltip: '刪除對象',
              )
            : null,
      ),
    );
  }
}
```

### Step 2.4 — Run card tests, expect PASS

```bash
~/flutter/bin/flutter test test/widget/features/partner/partner_list_card_test.dart
```

Expected: 5 pass

### Step 2.5 — Write failing screen delete dialog tests

Modify `test/widget/features/partner/partner_list_screen_test.dart`，加：

```dart
testWidgets('tapping delete with conversationCount==0 shows confirm dialog', ...);
testWidgets('tapping delete with conversationCount>0 shows informational dialog (no destructive action) even if aggregate.totalRounds==0', ...);
testWidgets('confirm dialog → controller.delete called → SnackBar success', ...);
testWidgets('confirm dialog → controller.delete throws → defensive catch shows retry SnackBar', ...);
```

### Step 2.6 — Run, expect FAIL

### Step 2.7 — Wire `PartnerListScreen` row builder

Modify `partner_list_screen.dart`：每筆 row 同時 watch `partnerAggregateProvider(p.id)` + `conversationsByPartnerProvider(p.id).length`，capture 進 `onDelete` handler。

```dart
itemBuilder: (context, i) {
  final p = partners[i];
  final agg = ref.watch(partnerAggregateProvider(p.id));
  final convCount = ref.watch(conversationsByPartnerProvider(p.id)).length;
  return PartnerListCard(
    partner: p,
    aggregate: agg,
    onTap: () => context.push('/partner/${p.id}'),
    onDelete: () => _onDelete(context, ref, p, convCount),
  );
}
```

`_onDelete` 內按 §6.2 規格 two-mode dialog（confirm / informational），含防衛性 try/catch on `PartnerHasConversationsException` race。

### Step 2.8 — Run all tests, lint, commit

```bash
~/flutter/bin/flutter test test/widget/features/partner/
~/flutter/bin/flutter analyze --no-fatal-infos lib/features/partner/presentation/ test/widget/features/partner/
git add lib/features/partner/presentation/widgets/partner_list_card.dart \
        lib/features/partner/presentation/screens/partner_list_screen.dart \
        test/widget/features/partner/partner_list_card_test.dart \
        test/widget/features/partner/partner_list_screen_test.dart
git commit -m "[feat] PartnerListCard 視覺還原 5 件套 + delete dialog two-mode

- avatar / name+date header / heat-or-待分析 / interleave tags / delete icon
- _previewTags interleave 興趣/特質再 cap 3（Codex HS-P4-5）
- Delete dialog: conversationCount==0 → confirm; >0 → informational
- Screen row builder watch conversationsByPartnerProvider 取真實數，不依
  aggregate.totalRounds（Codex P1.2 false-safe fix）

Reviewer-Hint: card 仍 pure render（不 ref.watch），lifted-aggregate 不破
Next-Step: Task 3 — PartnerBannerService + FutureProvider"
git push
```

---

## Task 3 — PartnerBannerService + FutureProvider（data, design doc §7.1-7.2 / Task 14a）

**Files:**
- Create: `lib/features/partner/data/services/partner_banner_service.dart`
- Create: `lib/features/partner/data/providers/partner_banner_providers.dart`
- Create: `test/unit/features/partner/partner_banner_service_test.dart`

### Step 3.1 — Write failing service tests

```dart
test('isDismissed returns false when key absent for uid', ...);
test('markDismissed then isDismissed returns true for same uid', ...);
test('markDismissed for uid A does not affect uid B (per-account isolation)', ...);
```

Use `SharedPreferences.setMockInitialValues({})` per Flutter test idiom.

### Step 3.2 — Run, expect FAIL

### Step 3.3 — Implement service

```dart
// lib/features/partner/data/services/partner_banner_service.dart
import 'package:shared_preferences/shared_preferences.dart';

class PartnerBannerService {
  static String _key(String uid) => 'partner_dedupe_banner_dismissed_$uid';

  static Future<bool> isDismissed(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(uid)) ?? false;
  }

  static Future<void> markDismissed(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(uid), true);
  }
}
```

### Step 3.4 — Add provider

```dart
// lib/features/partner/data/providers/partner_banner_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/partner_banner_service.dart';

final partnerDedupeBannerDismissedProvider =
    FutureProvider.family<bool, String>((ref, uid) {
  return PartnerBannerService.isDismissed(uid);
});
```

### Step 3.5 — Run service tests, expect PASS

### Step 3.6 — Lint + commit

```bash
~/flutter/bin/flutter analyze --no-fatal-infos lib/features/partner/data/ test/unit/features/partner/
git add lib/features/partner/data/services/partner_banner_service.dart \
        lib/features/partner/data/providers/partner_banner_providers.dart \
        test/unit/features/partner/partner_banner_service_test.dart
git commit -m "[feat] PartnerBannerService + FutureProvider (per-uid SharedPreferences)

- key = 'partner_dedupe_banner_dismissed_\$uid'（D-P4-5 per-account scope）
- partnerDedupeBannerDismissedProvider = FutureProvider.family<bool, String>
  (Codex P2 async state contract — 避免 build 內 await / banner flicker)

Reviewer-Hint: 抄 OnboardingService pattern 加 uid 參數
Next-Step: Task 4 — banner widget + merge picker preselect"
git push
```

---

## Task 4 — SameNameDedupeBanner widget + merge picker preselect（UI, design doc §7.3-7.6 / Task 14b）

**Files:**
- Create: `lib/features/partner/presentation/widgets/same_name_dedupe_banner.dart`
- Modify: `lib/features/partner/presentation/screens/partner_list_screen.dart` (banner 頂部 conditionally render)
- Modify: `lib/features/partner/presentation/screens/partner_merge_picker_screen.dart` (+ `initialTargetId` field, preselect contract)
- Modify: `lib/features/partner/presentation/widgets/partner_picker_sheet.dart` (+ preselect highlight + bottom CTA when preselect set)
- Modify: `lib/app/routes.dart` (merge picker route 接 `?target=` query param)
- Create: `test/widget/features/partner/same_name_banner_test.dart`
- Modify: `test/widget/features/partner/partner_merge_picker_screen_test.dart` (+ preselect contract tests)

### Step 4.1 — Write failing banner widget tests

```dart
testWidgets('shows when ≥2 partners share same name and dismissed=false', ...);
testWidgets('does not show when all partners unique', ...);
testWidgets('does not show when partnerDedupeBannerDismissedProvider returns true', ...);
testWidgets('does not show when partnerDedupeBannerDismissedProvider is loading', ...);
testWidgets('tap "以後再說" calls service.markDismissed(uid) + invalidates provider + hides banner', ...);
testWidgets('tap "立即合併" pushes /partner/{newer.id}/merge?target={older.id}', ...);
```

### Step 4.2 — Run, expect FAIL

### Step 4.3 — Implement banner widget + screen wiring

`same_name_dedupe_banner.dart`：純 stateless widget 收 `(partnerName, onMergeTap, onDismissTap)`。

`partner_list_screen.dart`：
1. 加 private helper `_findFirstDupPair(List<Partner>)` 回傳 `({Partner older, Partner newer})?`
2. 從 `authConversationScopeProvider.valueOrNull` 取 uid（null 時不顯示 banner）
3. `ref.watch(partnerDedupeBannerDismissedProvider(uid))` — `data.value == true` 或 loading/error 時不顯示
4. dup pair 為 null 也不顯示
5. dup pair + 未 dismissed + uid 有 → 顯示 banner 在 list 頂部（非 sticky）
6. `onDismissTap` 內 `await PartnerBannerService.markDismissed(uid)` 後 `ref.invalidate(partnerDedupeBannerDismissedProvider(uid))`
7. `onMergeTap` 內 `context.push('/partner/${newer.id}/merge?target=${older.id}')`

### Step 4.4 — Run banner tests, expect PASS

### Step 4.5 — Write failing merge picker preselect tests

```dart
testWidgets('no target query → preserves PR-B row-tap → confirm dialog flow', ...);
testWidgets('valid target → preselect target row, shows bottom "確認合併" CTA, no auto-open destructive', ...);
testWidgets('valid target preselect → tap different row → switches preselect, still no auto-open', ...);
testWidgets('preselect CTA tap → opens confirm dialog (manual continuation of PR-B flow)', ...);
testWidgets('target = self id → query ignored, falls back to PR-B row-tap flow', ...);
testWidgets('target = unknown id → query ignored, falls back to PR-B row-tap flow', ...);
```

### Step 4.6 — Run, expect FAIL

### Step 4.7 — Implement preselect on PartnerMergePickerScreen + PartnerPickerSheet

Modify `partner_merge_picker_screen.dart` — 加 `final String? initialTargetId`。

Logic（Codex spec patch §7.5 contract）：
```dart
final preselectId = (() {
  if (initialTargetId == null) return null;
  if (initialTargetId == fromPartnerId) return null;
  // candidate must exist in partner list (excluded source)
  final candidate = ref.read(partnerByIdProvider(initialTargetId!));
  if (candidate == null) return null;
  return initialTargetId;
})();
```

If `preselectId != null`：
- `PartnerPickerSheet` 收 `selectedId: preselectId` 顯示 highlight
- 顯示底部 CTA「確認合併到 ${preselectName}」按鈕
- CTA tap → 跑既有 `_confirm(context, ref, target)` 進 confirm dialog
- 仍允許 tap 其他 row 切換 preselect（無 auto-open）

If `preselectId == null`：
- Picker 行為 100% 維持 PR-B 既有 — `onSelected` row tap → confirm dialog

`partner_picker_sheet.dart` 加 optional `selectedId` + `onSelectedChanged` callback for preselect-mode tap-to-switch（不 auto-open）。

### Step 4.8 — Update route

`lib/app/routes.dart`：

```dart
GoRoute(
  path: '/partner/:partnerId/merge',
  builder: (context, state) => PartnerMergePickerScreen(
    fromPartnerId: state.pathParameters['partnerId']!,
    initialTargetId: state.uri.queryParameters['target'],
  ),
),
```

### Step 4.9 — Run all tests, lint, commit

```bash
~/flutter/bin/flutter test test/widget/features/partner/ test/unit/features/partner/
~/flutter/bin/flutter analyze --no-fatal-infos lib test
git add lib/features/partner/presentation/ \
        lib/app/routes.dart \
        test/widget/features/partner/same_name_banner_test.dart \
        test/widget/features/partner/partner_merge_picker_screen_test.dart
git commit -m "[feat] SameNameDedupeBanner + merge picker preselect contract

- banner detect via _findFirstDupPair (presentation helper)
- async-safe via partnerDedupeBannerDismissedProvider FutureProvider.family
- CTA → /partner/\${newer.id}/merge?target=\${older.id}（D-P4-2: older=target）
- merge picker initialTargetId contract（Codex P2）：
  · null → PR-B row-tap flow 保留
  · valid → preselect + 底部 CTA，不 auto-open destructive dialog
  · self/unknown → 忽略 query，回 row-tap flow

Reviewer-Hint: route query param 是 optional，向後相容；preselect mode
               不破壞 PR-B 既有 onSelected pattern
Next-Step: Task 5 — copy sweep"
git push
```

---

## Task 5 — Copy sweep（design doc §8 / Task 15）

**Files:**
- Modify: `lib/app/main_shell.dart` (Bruce 紅框 popup 標題)
- Modify: `lib/features/partner/presentation/screens/partner_list_screen.dart` (空狀態文案)
- Modify: 其他 grep 命中位逐筆判斷
- Create: `test/widget/features/copy_sweep_snapshot_test.dart` (snapshot 防漂移)

### Step 5.1 — Pre-flight grep

```bash
grep -rn "新增對話\|新對話\|建立對話\|對話列表\|你的對話\|還沒有對話\|加一個開始" lib/ \
  | grep -v "_test.dart\|.g.dart\|migration_service\|_repository.dart\|_controller.dart\|@Deprecated"
```

逐筆筆記是否改：用 `[改]` / `[保留]` 標。

### Step 5.2 — Write failing snapshot tests

```dart
testWidgets('home FAB label = "+ 新增對象"', ...);
testWidgets('partner detail "+ 新增對話" label remains', ...);
testWidgets('partner list empty state copy = "還沒有對象，加一個開始"', ...);
```

### Step 5.3 — Run, expect FAIL

至少 1 條 fail（現在文案是「對話」而非「對象」）。

### Step 5.4 — Edit copy

逐筆改 grep 命中位（不動 `MainShell` PopupMenuItem 的 `key`）。

### Step 5.5 — Run snapshot tests + analyze, expect PASS

```bash
~/flutter/bin/flutter test test/widget/features/copy_sweep_snapshot_test.dart
~/flutter/bin/flutter test test/widget/features/   # 確認沒打到既有 fixture
~/flutter/bin/flutter analyze --no-fatal-infos lib
```

### Step 5.6 — Commit

```bash
git add lib/ test/widget/features/copy_sweep_snapshot_test.dart
git commit -m "[refactor] copy sweep — UI 「對象 / 對話」雙層詞彙對齊 ADR-15

- home FAB / 全域導覽 → 「對象」
- Partner detail 內 / 截圖 OCR / domain Conversation → 保留「對話」
- snapshot tests 防漂移（home FAB / partner detail / empty state）"
git push
```

---

## Task 6 — 砍 @Deprecated HomeContent（design doc §9.1 / Task 16a）

**Files:**
- Delete: `lib/features/conversation/presentation/screens/home_screen.dart`
- Modify: 任何殘留 import / route reference（grep 後逐筆）

### Step 6.1 — Pre-flight grep

```bash
grep -rn "HomeContent\|home_screen" lib/ test/ --include="*.dart"
```

紀錄所有命中位。

### Step 6.2 — Delete file + clean references

```bash
rm lib/features/conversation/presentation/screens/home_screen.dart
```

逐筆清 import / route fallback / test reference。

### Step 6.3 — Verification gate

```bash
grep -rn "HomeContent\|home_screen" lib/ test/   # expect 0 hit
~/flutter/bin/flutter analyze --no-fatal-infos lib test 2>&1 | tail -10  # expect 0 issues
~/flutter/bin/flutter test 2>&1 | tail -5  # expect all pass
```

若任一 gate fail → 回 step 6.1 重新 grep。

### Step 6.4 — Commit

```bash
git add lib/ test/
git commit -m "[refactor] 砍 @Deprecated HomeContent — Phase 4 cleanup

Phase 2 將 home tab 切到 PartnerListScreen 後，HomeContent 標 @Deprecated
保留作為 visual donor。Task 18 (PartnerListCard 視覺還原) 完成後可砍。

Reviewer-Hint: 0 reference 殘留；flutter test + analyze 雙 gate
Next-Step: Task 7 — TF regression / ADR-15 v2 / snapshot / pitfall"
git push
```

---

## Task 7 — Doc closeout（design doc §9.2-9.5 / Task 16b）

**Files:**
- Modify: `docs/testflight-regression-checklist.md` (+ A2 ship 段落 13 項)
- Modify: `docs/decisions.md` (+ ADR-15 v2 ship section)
- Modify: `docs/snapshot.md` (+ A2 ship 階段)
- Modify: `CLAUDE.md` (+ 1 條 Common Pitfall)

### Step 7.1 — TF regression checklist

Append A2 ship 段落（13 項，見 design doc §11）。

### Step 7.2 — ADR-15 v2 ship section

Append 至 `docs/decisions.md`：D1-D4 主決策 + D-P4-1 ~ D-P4-5 Phase 4 新增決策（見 design doc §9.3）。

Date 寫實際 ship date（commit 時填）。

### Step 7.3 — Snapshot 刷新

更新 `docs/snapshot.md`「當前階段」一句話 + A2 ship date。

### Step 7.4 — Common Pitfall

`CLAUDE.md` Common Pitfalls 段加：

> Partner delete 必須先驗 conversation count，非空 throw `PartnerHasConversationsException`；UI 需切 informational vs confirm dialog（不可省略 guard）

`AGENTS.md` 同步（pre-commit hook 會驗）。

### Step 7.5 — Commit

```bash
git add docs/testflight-regression-checklist.md docs/decisions.md docs/snapshot.md CLAUDE.md AGENTS.md
git commit -m "[docs] A2 ship — TF regression + ADR-15 v2 + snapshot + 1 pitfall

- TF regression checklist 補 A2 ship 段落 13 項（含 Phase 4 5 件套 + delete
  two-mode dialog + per-account banner 隔離）
- ADR-15 v2 ship 段落：D1-D4 主決策 + D-P4-1~D-P4-5 Phase 4 新增決策
- snapshot.md 月度刷新 — 當前階段 = A2 ship + TF soak
- CLAUDE.md / AGENTS.md Common Pitfall 加 1 條：partner delete cascade guard"
git push
```

---

## Task 8 — Pre-PR sanity + ship gate（design doc §10 / Task 17）

### Step 8.1 — 全測試 + lint

```bash
~/flutter/bin/flutter test 2>&1 | tee /tmp/phase4_test_output.log
~/flutter/bin/flutter analyze 2>&1 | tee /tmp/phase4_analyze_output.log
```

**Acceptance gates:**
- 0 failing tests
- 0 lint warnings on new files (`partner_list_card.dart` / `same_name_dedupe_banner.dart` / `partner_banner_service.dart` / `partner_banner_providers.dart`)
- 既有 main test count ≤ Phase 4 branch test count
- Skip count 維持 1（Phase 2 那個 add_partner_screen skip）

### Step 8.2 — Manual smoke（5 critical paths，見 design doc §10.2）

跑 TF 候選 build / 自家 build。

### Step 8.3 — 開 PR

```bash
gh pr create --title "Partner Entity Refactor A2 — Phase 4 polish + ship (Tasks 14-18)" --body "$(cat <<'EOF'
## Summary
- PartnerListCard 視覺還原（5 件套 + delete API w/ cascade guard）
- Same-name dedupe banner（per-account dismissal + pre-filled merge CTA）
- Copy sweep（首頁 / 全域「對象」、Partner detail 內保留「對話」）
- 砍 @Deprecated HomeContent + ADR-15 v2 ship section + TF regression 補項

## Test plan
- [x] flutter test — all green
- [x] flutter analyze — no warnings
- [x] Manual smoke 5 paths（upgrade / banner / delete two-mode / per-account 隔離 / 5 件套 visual）
- [ ] Codex code review pass

## Phase 4 design decisions
- D-P4-1: Partner delete cascade = block-when-non-empty
- D-P4-2: Banner pre-fill = older=target / newer=source（createdAt）
- D-P4-3: PartnerListCard preview = interleave interests/traits 前 3 tag
- D-P4-4: Heat fallback = 🌡️ 待分析 灰字
- D-P4-5: Banner dismissed = per-account uid-scoped key

## Codex spec review (REVISED_AND_APPROVED)
- docs/reviews/2026-04-28_partner-entity-A2-phase4-spec_codex-review.md
- 5 patches 已落 1c74722 / 對齊現有 codebase contract

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

### Step 8.4 — Open queue item「A2 Phase 4 Code Review」

`docs/reviews/ai-arbitration-queue.md` 頂部新 item，Status: IN_REVIEW，Owner: Codex，喊 Codex 審 diff。

```bash
git add docs/reviews/ai-arbitration-queue.md
git commit -m "[docs] queue: A2 Phase 4 code review IN_REVIEW — 喊 Codex 審 diff"
git push
```

---

## Commit Summary（預期 7 commits + 1 queue update）

| # | Task | Layer | Commit Subject |
|---|---|---|---|
| 1 | 18a | data | `[feat] PartnerRepository.delete() + cascade guard + controller invalidation` |
| 2 | 18b | UI | `[feat] PartnerListCard 視覺還原 5 件套 + delete dialog two-mode` |
| 3 | 14a | data | `[feat] PartnerBannerService + FutureProvider (per-uid SharedPreferences)` |
| 4 | 14b | UI | `[feat] SameNameDedupeBanner + merge picker preselect contract` |
| 5 | 15 | UI | `[refactor] copy sweep — UI 「對象 / 對話」雙層詞彙對齊 ADR-15` |
| 6 | 16a | refactor | `[refactor] 砍 @Deprecated HomeContent — Phase 4 cleanup` |
| 7 | 16b | docs | `[docs] A2 ship — TF regression + ADR-15 v2 + snapshot + 1 pitfall` |
| — | 17 | gate | `gh pr create` + `[docs] queue: code review IN_REVIEW` |

Codex code review 若 REVISED_AND_APPROVED，預期會多 1 patch commit（直接 push 到本 branch），總計 8-9 commits。

---

## Skip / Hang Avoidance（從 Phase 2-3 經驗繼承）

- **不在 Windows Flutter CLI 跑 widget tests** — 用 WSL `~/flutter/bin/flutter`
- **不混 OCR 改動** — Phase 4 全程不碰 `lib/features/analysis/`、`supabase/functions/`
- **不擴大 scope 改 ADR-15 D 決策** — 5 D-P4 已 locked
- **遇 hang test 直接 skip + 標 reason** — 不戰 cache / kernel 問題（PR-A 期間已驗 falsified）

---

## Codex Code Review Hot Spots（exec 完後喊）

執行完 Tasks 1-8 後喊 Codex 重點看：

1. **HS-Code-1**: PartnerListCard `_previewTags` 邏輯是否正確 interleave？邊界 (interests 5 / traits 0) 跟 (interests 0 / traits 5) 是否都正確？
2. **HS-Code-2**: Delete dialog two-mode 的 race（dialog 開啟期間用戶建對話）防衛性 catch 是否落實？
3. **HS-Code-3**: Banner FutureProvider invalidate 後 widget 是否真的 re-render（避免「以後再說」按了沒效果）？
4. **HS-Code-4**: Merge picker preselect mode 切其他 row 是否真的 not auto-open destructive？
5. **HS-Code-5**: Copy sweep 是否漏掉「+ 新增對話」popup 子項位置（Bruce 紅框）？
