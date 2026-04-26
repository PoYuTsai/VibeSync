# Partner Entity Refactor A2 — Phase 2 (UI / IA shift) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task.
>
> **For Codex (spec review):** see `## Codex Review Hot Spots` near the end. Plan-default decisions D1-D4 are inherited from the parent A2 plan and **not** reopened here.

**Goal:** Ship the Partner-first user-facing IA on top of the A2 Phase 1 data layer (`f053a9c`): home tab becomes a Partner list, FAB opens an Add Partner form, and `/partner/:partnerId` routes to a new Partner detail screen with traits / radar summary cards. Domain layer (`Conversation` entity, repositories) stays untouched (D2 plan-default A).

**Architecture:**
- New screens live under `lib/features/partner/presentation/screens/` and `widgets/`. Existing `conversation/presentation/screens/` is **only** reroute-target via `/conversation/:id`; `home_screen.dart`'s `HomeContent` is dropped from `MainShell`'s IndexedStack[0] in favor of `PartnerListScreen`.
- Routing adds `/partner/:partnerId` and `/partner/new`; `/conversation/:id` is preserved verbatim for back-compat (deep links, share survival).
- All Riverpod reads use the **narrow-invalidation** providers shipped in Phase 1 (`partnerListProvider`, `partnerByIdProvider`, `conversationsByPartnerProvider`, `partnerAggregateProvider`). **Hard rule (Codex C1)**: no Phase 2 widget may watch `conversationsProvider` (the legacy global). Violation = revert.
- Add-partner write path uses `PartnerRepository.upsertIfAbsent` (the only public write in A2). New partners get a fresh UUID + `ownerUserId` from `authConversationScopeProvider`.

**Tech Stack:** Flutter 3.x · Riverpod · go_router · Hive (read-only — A2 Phase 2 does **not** add HiveFields) · `uuid` (already a transitive dep — confirm in pre-flight) · `fl_chart` (existing radar widget reused as mini variant).

**Locked decisions (from parent A2 plan, do not reopen):**
- D1 plan-default A: screenshot flow auto-attaches Partner via "+ 新增對話" entry from Partner detail. **Phase 3** wires the screenshot path; Phase 2 only puts the entry point in place via the existing `_NewConversationSheet`.
- D2 plan-default A: domain layer keeps `Conversation` name; UI uses「對象 / 對話」. Phase 2 adds NEW UI strings; **Task 15 (Phase 4) handles the global copy sweep** including the existing `_NewConversationSheet` "新增對話" title.
- D3 plan-default A: Partner detail conversation cell tap → `/conversation/:id` → existing `AnalysisScreen`.
- D4 plan-default A: same-name banner is **deferred to Phase 3 Task 14**, NOT Phase 2.

---

## Pre-flight (must run before Task 6)

```bash
git status                                          # working tree clean
git rev-parse --abbrev-ref HEAD                     # MUST print: feature/partner-entity-A2-ui
git log --oneline -3                                # HEAD = main HEAD = 6e08fa3 (or later soak hotfix)

# Confirm dependencies + provider contracts haven't drifted since Phase 1 ship
grep -n "uuid:" pubspec.yaml || echo 'NEED uuid in pubspec'
grep -n "go_router:" pubspec.yaml
grep -n "partnerListProvider\|partnerByIdProvider\|conversationsByPartnerProvider\|partnerAggregateProvider\|partnerRepositoryProvider" \
  lib/features/partner/presentation/providers/partner_providers.dart

# Existing test baseline — none of these should be RED before we start
flutter test test/widget/ 2>&1 | tail -5 || echo 'baseline noted'
```

Expected:
- `pubspec.yaml` has `uuid:` (any 4.x version is fine — used to mint Partner ids in Task 8). If absent, Task 8 Step 0 adds it.
- All five Phase 1 providers present at the line numbers in `partner_providers.dart`.
- Widget test baseline noted; any pre-existing failures must be flagged in the queue item before Phase 2 starts (Codex needs to know what's pre-existing vs Phase 2 regression).

---

## Branch / Commit Strategy

- **Branch (already cut):** `feature/partner-entity-A2-ui`
- One commit per Task; commit body must include `Reviewer-Hint:` and `Next-Step:` trailers per `docs/shared-agent-rules.md`.
- **Push immediately** after each commit (global CLAUDE.md rule).
- All four tasks complete + `flutter test` + `flutter analyze` green → open PR → queue item flips Codex code review.

---

## Task 6 — Routing: `/partner/:partnerId` + `/partner/new`

**Files:**
- Modify: `lib/app/routes.dart` (102 lines, current router lives here)
- Test: `test/widget/router_test.dart` (NEW — no existing widget router tests)

**Step 1: Write failing widget tests**

```dart
// test/widget/router_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:vibe_sync/features/partner/presentation/screens/partner_detail_screen.dart';
import 'package:vibe_sync/features/partner/presentation/screens/add_partner_screen.dart';
import 'package:vibe_sync/features/analysis/presentation/screens/analysis_screen.dart';

// Build a minimal harness router with the same routes shape — we test the
// route TABLE shape, not the auth redirect (auth tested elsewhere via
// SupabaseService stubbing).
GoRouter _testRouter(String initialLocation) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(
      path: '/partner/new',
      builder: (c, s) => const AddPartnerScreen(),
    ),
    GoRoute(
      path: '/partner/:partnerId',
      builder: (c, s) =>
          PartnerDetailScreen(partnerId: s.pathParameters['partnerId']!),
    ),
    GoRoute(
      path: '/conversation/:id',
      builder: (c, s) => AnalysisScreen(conversationId: s.pathParameters['id']!),
    ),
  ],
);

void main() {
  testWidgets('/partner/:partnerId routes to PartnerDetailScreen', (t) async {
    await t.pumpWidget(ProviderScope(
      child: MaterialApp.router(routerConfig: _testRouter('/partner/abc-123')),
    ));
    await t.pumpAndSettle();
    expect(find.byType(PartnerDetailScreen), findsOneWidget);
  });

  testWidgets('/partner/new routes to AddPartnerScreen', (t) async {
    await t.pumpWidget(ProviderScope(
      child: MaterialApp.router(routerConfig: _testRouter('/partner/new')),
    ));
    await t.pumpAndSettle();
    expect(find.byType(AddPartnerScreen), findsOneWidget);
    expect(find.byType(PartnerDetailScreen), findsNothing);
  });

  testWidgets('/conversation/:id keeps back-compat (still routes AnalysisScreen)',
      (t) async {
    await t.pumpWidget(ProviderScope(
      child: MaterialApp.router(routerConfig: _testRouter('/conversation/conv-1')),
    ));
    await t.pumpAndSettle();
    expect(find.byType(AnalysisScreen), findsOneWidget);
  });
}
```

> **Note on order:** `/partner/new` is declared **before** `/partner/:partnerId` so the literal path wins over the parametric one. go_router resolves first match — invert and `new` becomes a partner id "new". This MUST be in the live `routes.dart` too.

**Step 2: Run, expect FAIL** (PartnerDetailScreen / AddPartnerScreen don't exist yet)

```bash
flutter test test/widget/router_test.dart
```
Expected: compile error `Undefined name 'PartnerDetailScreen' / 'AddPartnerScreen'`.

**Step 3: Create stubs so the test compiles + still fails on the route assertions**

```dart
// lib/features/partner/presentation/screens/partner_detail_screen.dart  (STUB ONLY for Task 6)
import 'package:flutter/material.dart';
class PartnerDetailScreen extends StatelessWidget {
  final String partnerId;
  const PartnerDetailScreen({super.key, required this.partnerId});
  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text('partner $partnerId')));
}
```

```dart
// lib/features/partner/presentation/screens/add_partner_screen.dart  (STUB ONLY for Task 6)
import 'package:flutter/material.dart';
class AddPartnerScreen extends StatelessWidget {
  const AddPartnerScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('add partner')));
}
```

Re-run test — expect 3 PASS on the harness router (stubs are enough to satisfy the harness).

**Step 4: Wire the live router (`lib/app/routes.dart`)**

Insert two new `GoRoute` entries inside the existing `routes: [ ... ]` list. **Insert `/partner/new` BEFORE `/partner/:partnerId`** (literal-before-parametric). Place them right after the existing `/conversation/:id` block:

```dart
// inside lib/app/routes.dart, append imports:
import '../features/partner/presentation/screens/partner_detail_screen.dart';
import '../features/partner/presentation/screens/add_partner_screen.dart';

// inside the routes: [...] list, after the /conversation/:id GoRoute:
GoRoute(
  path: '/partner/new',
  builder: (context, state) => const AddPartnerScreen(),
),
GoRoute(
  path: '/partner/:partnerId',
  builder: (context, state) => PartnerDetailScreen(
    partnerId: state.pathParameters['partnerId']!,
  ),
),
```

Do **not** modify the redirect logic, the existing routes, or `_GoRouterRefreshStream`.

**Step 5: Run full test suite to confirm nothing else broke**

```bash
flutter test test/widget/router_test.dart
flutter test --reporter expanded test/ 2>&1 | tail -20
```
Expected: all 3 router tests PASS; pre-existing test count unchanged (or only delta = the 3 new router tests).

**Step 6: Commit**

```bash
git add lib/app/routes.dart \
        lib/features/partner/presentation/screens/partner_detail_screen.dart \
        lib/features/partner/presentation/screens/add_partner_screen.dart \
        test/widget/router_test.dart
git commit -m "$(cat <<'EOF'
[feat] router 新增 /partner/:partnerId + /partner/new，保留 /conversation/:id

- /partner/new 排在 /partner/:partnerId 之前避免 'new' 被當 partnerId
- PartnerDetailScreen / AddPartnerScreen 為 Task 6 stub，Task 7-9 補實作
- /conversation/:id 行為完全未動，deep link / share link 維持向後相容

Reviewer-Hint: literal-before-parametric ordering 是 go_router 行為的硬性依賴
Next-Step: Task 7 把 MainShell IndexedStack[0] 從 HomeContent 換成 PartnerListScreen
EOF
)"
git push -u origin feature/partner-entity-A2-ui
```

---

## Task 7 — Partner list home screen + MainShell wiring

**Files:**
- Create: `lib/features/partner/presentation/screens/partner_list_screen.dart`
- Create: `lib/features/partner/presentation/widgets/partner_list_card.dart`
- Modify: `lib/app/main_shell.dart:9-10` (drop `HomeContent` import, add `PartnerListScreen` import) and `lib/app/main_shell.dart:40-50` (swap IndexedStack[0])
- Modify: `lib/app/main_shell.dart:163-172` (FAB onPressed → `context.push('/partner/new')` instead of bottom sheet)
- Test: `test/widget/features/partner/partner_list_screen_test.dart`

**Step 1: Write failing widget tests**

```dart
// test/widget/features/partner/partner_list_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vibe_sync/features/partner/domain/entities/partner.dart';
import 'package:vibe_sync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibe_sync/features/partner/presentation/screens/partner_list_screen.dart';

Partner _p(String id, String name) => Partner(
  id: id,
  name: name,
  createdAt: DateTime(2026, 4, 20),
  updatedAt: DateTime(2026, 4, 20),
  ownerUserId: 'u1',
);

void main() {
  testWidgets('empty state: shows "還沒有對象，加一個開始" + 入口 hint',
      (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerListProvider.overrideWith((_) => const <Partner>[]),
      ],
      child: const MaterialApp(home: PartnerListScreen()),
    ));
    await t.pumpAndSettle();
    expect(find.textContaining('還沒有對象'), findsOneWidget);
  });

  testWidgets('renders one PartnerListCard per partner', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerListProvider.overrideWith((_) => [_p('a', 'Alice'), _p('b', 'Bob')]),
      ],
      child: const MaterialApp(home: PartnerListScreen()),
    ));
    await t.pumpAndSettle();
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
  });

  testWidgets('list preserves the order returned by partnerListProvider',
      (t) async {
    // partnerListProvider is the source of truth for sort order (Phase 1).
    // PartnerListScreen MUST NOT re-sort.
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerListProvider.overrideWith((_) => [_p('z', 'Zoe'), _p('a', 'Alice')]),
      ],
      child: const MaterialApp(home: PartnerListScreen()),
    ));
    await t.pumpAndSettle();
    final zoe = t.getTopLeft(find.text('Zoe'));
    final alice = t.getTopLeft(find.text('Alice'));
    expect(zoe.dy < alice.dy, isTrue, reason: 'Zoe must render above Alice');
  });
}
```

> **Why no test for tap → `/partner/:id`** here: that requires a router-aware harness. We cover the navigation behavior in Task 9's detail-screen test (entry path) and the router test (Task 6). Keep this widget test focused on rendering contract.

**Step 2: Run, expect FAIL** — `PartnerListScreen` undefined.

**Step 3: Implement**

```dart
// lib/features/partner/presentation/screens/partner_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../providers/partner_providers.dart';
import '../widgets/partner_list_card.dart';

class PartnerListScreen extends ConsumerWidget {
  const PartnerListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partners = ref.watch(partnerListProvider);
    if (partners.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            '還沒有對象，從右下加一個開始',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: partners.length,
      itemBuilder: (context, i) {
        final p = partners[i];
        return PartnerListCard(
          partner: p,
          onTap: () => context.push('/partner/${p.id}'),
        );
      },
    );
  }
}
```

```dart
// lib/features/partner/presentation/widgets/partner_list_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/partner.dart';
import '../providers/partner_providers.dart';

class PartnerListCard extends ConsumerWidget {
  final Partner partner;
  final VoidCallback onTap;
  const PartnerListCard({super.key, required this.partner, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agg = ref.watch(partnerAggregateProvider(partner.id));
    return ListTile(
      onTap: onTap,
      title: Text(partner.name, style: AppTypography.titleSmall),
      subtitle: Text(
        '${agg.totalRounds} 段對話'
        '${agg.latestHeat != null ? ' · 熱度 ${agg.latestHeat}' : ''}',
        style: AppTypography.bodySmall.copyWith(
          color: AppColors.onBackgroundSecondary,
        ),
      ),
    );
  }
}
```

**Step 4: Wire `MainShell`**

In `lib/app/main_shell.dart`:

- Drop import: `import '../features/conversation/presentation/screens/home_screen.dart';`
- Add import: `import '../features/partner/presentation/screens/partner_list_screen.dart';`
- Replace IndexedStack child at index 0:

```dart
// before:
HomeContent(
  onNewConversation: () => _showNewConversationOptions(shellContext),
),
// after:
const PartnerListScreen(),
```

- Update `_HomeFab.onPressed` to push `/partner/new` instead of opening the sheet:

```dart
// inside _HomeFab.build:
onPressed: () => context.push('/partner/new'),
```

- Delete the now-unused `_showNewConversationOptions` helper from `_MainShellState`. The `_NewConversationSheet` widget itself **stays** — Task 9 reuses it from PartnerDetailScreen's "+ 新增對話" button.

> **HomeContent cleanup**: do NOT delete `home_screen.dart`. Phase 4 Task 15/16 will retire it as part of copy sweep + cleanup. Leaving it in place preserves any direct test imports until then. Mark it `@Deprecated('Replaced by PartnerListScreen in Phase 2; remove in Phase 4 cleanup')` at the class level so Codex / `flutter analyze` see the intent.

**Step 5: Run tests**

```bash
flutter test test/widget/features/partner/partner_list_screen_test.dart
flutter test test/widget/router_test.dart            # regression check
flutter analyze lib/app/main_shell.dart lib/features/partner/
```
Expected: new tests PASS; router tests still PASS; analyze clean.

**Step 6: Commit**

```bash
git add lib/features/partner/presentation/screens/partner_list_screen.dart \
        lib/features/partner/presentation/widgets/partner_list_card.dart \
        lib/app/main_shell.dart \
        lib/features/conversation/presentation/screens/home_screen.dart \
        test/widget/features/partner/partner_list_screen_test.dart
git commit -m "$(cat <<'EOF'
[feat] Home tab 改 PartnerListScreen + FAB 改開 /partner/new

- MainShell IndexedStack[0]: HomeContent → PartnerListScreen
- _HomeFab.onPressed: 開 _NewConversationSheet → context.push('/partner/new')
- HomeContent 標 @Deprecated（Phase 4 cleanup 才砍）
- _NewConversationSheet 保留供 Task 9 PartnerDetail 「+ 新增對話」重用
- PartnerListCard 用 partnerAggregateProvider，符合 narrow-invalidation contract
  （絕不 watch conversationsProvider 全域）

Reviewer-Hint: 為什麼留 HomeContent dead code？避免本 phase blast radius，Task 15 一起掃
Next-Step: Task 8 AddPartnerScreen 表單填好寫 PartnerRepository.upsertIfAbsent
EOF
)"
git push
```

---

## Task 8 — Add Partner form (`/partner/new`)

**Files:**
- Modify: `lib/features/partner/presentation/screens/add_partner_screen.dart` (replace Task 6 stub with real form)
- Test: `test/widget/features/partner/add_partner_screen_test.dart`
- Modify (only if pre-flight flagged missing): `pubspec.yaml` — add `uuid: ^4.5.1`

**Step 0 (conditional): Add `uuid` dep**

If pre-flight `grep "uuid:" pubspec.yaml` was empty:

```bash
flutter pub add uuid
```

**Step 1: Write failing tests**

```dart
// test/widget/features/partner/add_partner_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vibe_sync/features/partner/data/repositories/partner_repository.dart';
import 'package:vibe_sync/features/partner/domain/entities/partner.dart';
import 'package:vibe_sync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibe_sync/features/partner/presentation/screens/add_partner_screen.dart';

class _FakeRepo extends PartnerRepository {
  final inserted = <Partner>[];
  @override
  Future<bool> upsertIfAbsent(Partner partner) async {
    inserted.add(partner);
    return true;
  }
}

void main() {
  testWidgets('submit disabled while name empty', (t) async {
    await t.pumpWidget(const ProviderScope(
      child: MaterialApp(home: AddPartnerScreen()),
    ));
    await t.pumpAndSettle();
    final btn = find.widgetWithText(FilledButton, '建立');
    expect(tester.widget<FilledButton>(btn).onPressed, isNull);
  }, skip: 'placeholder — replace `tester` ref before run');

  testWidgets('submit enabled once name has non-whitespace', (t) async {
    await t.pumpWidget(const ProviderScope(
      child: MaterialApp(home: AddPartnerScreen()),
    ));
    await t.enterText(find.byType(TextFormField), 'Alice');
    await t.pumpAndSettle();
    final btn = t.widget<FilledButton>(find.widgetWithText(FilledButton, '建立'));
    expect(btn.onPressed, isNotNull);
  });

  testWidgets('successful submit writes Partner via repo + has ownerUserId',
      (t) async {
    final repo = _FakeRepo();
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerRepositoryProvider.overrideWithValue(repo),
        // authConversationScopeProvider is owned by conversation/data, override
        // it to a known user id for this widget test.
        // (executor: import the provider from its real path)
      ],
      child: const MaterialApp(home: AddPartnerScreen()),
    ));
    await t.enterText(find.byType(TextFormField), 'Alice');
    await t.tap(find.widgetWithText(FilledButton, '建立'));
    await t.pumpAndSettle();
    expect(repo.inserted.length, 1);
    expect(repo.inserted.single.name, 'Alice');
    expect(repo.inserted.single.ownerUserId, isNotNull,
        reason: 'must inherit from authConversationScopeProvider');
  });
}
```

> **Executor TODO before Step 2:** the first test references `tester` instead of `t` — fix typo. The third test requires overriding `authConversationScopeProvider` — find its exact import path in `lib/features/conversation/data/providers/conversation_providers.dart` and override with `AsyncData('u-test')` (or its real type).

**Step 2: Run, expect FAIL** — current `AddPartnerScreen` is the Task 6 stub with no form.

**Step 3: Implement**

```dart
// lib/features/partner/presentation/screens/add_partner_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../conversation/data/providers/conversation_providers.dart';
import '../../domain/entities/partner.dart';
import '../providers/partner_providers.dart';

class AddPartnerScreen extends ConsumerStatefulWidget {
  const AddPartnerScreen({super.key});
  @override
  ConsumerState<AddPartnerScreen> createState() => _AddPartnerScreenState();
}

class _AddPartnerScreenState extends ConsumerState<AddPartnerScreen> {
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty || _busy) return;
    setState(() => _busy = true);
    final ownerId = ref.read(authConversationScopeProvider).valueOrNull;
    final now = DateTime.now();
    final partner = Partner(
      id: const Uuid().v4(),
      name: name,
      createdAt: now,
      updatedAt: now,
      ownerUserId: ownerId,
    );
    final repo = ref.read(partnerRepositoryProvider);
    await repo.upsertIfAbsent(partner);
    ref.invalidate(partnerListProvider);
    if (!mounted) return;
    context.go('/partner/${partner.id}');
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _name.text.trim().isNotEmpty && !_busy;
    return Scaffold(
      appBar: AppBar(title: const Text('新增對象')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '對象名稱',
                hintText: '例：Alice / 阿志 / 小張',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: canSubmit ? _submit : null,
              child: const Text('建立'),
            ),
          ],
        ),
      ),
    );
  }
}
```

> **Avatar deferred**: A2 plan Task 8 says "avatar 可選 — submit 時不選也能建". Phase 2 ships **without** an avatar picker in this PR — `Partner.avatarPath` stays nullable and the field is not exposed in the form. Added in Phase 3/4 if Bruce flags it. Document this in the commit `Reviewer-Hint`.

**Step 4: Run tests**

```bash
flutter test test/widget/features/partner/add_partner_screen_test.dart
flutter analyze lib/features/partner/presentation/screens/add_partner_screen.dart
```
Expected: 3 new tests PASS; analyze clean.

**Step 5: Commit**

```bash
git add lib/features/partner/presentation/screens/add_partner_screen.dart \
        test/widget/features/partner/add_partner_screen_test.dart \
        pubspec.yaml pubspec.lock          # only if Step 0 ran
git commit -m "$(cat <<'EOF'
[feat] AddPartnerScreen — name + 即時 enable + UUID + ownerUserId 寫 Hive

- 用 PartnerRepository.upsertIfAbsent (A2 Phase 1 surface)，避免引入新 write API
- ownerUserId 從 authConversationScopeProvider 抓，匿名/未登入 → null（與 partnerListProvider auth-gate 一致）
- 提交後 ref.invalidate(partnerListProvider) → MainShell 立即看到
- 用 context.go 而非 push：/partner/new 在 stack 上不該被 back 回到
- avatar picker 故意延後到 Phase 3（A2 plan Task 8 註明可選）

Reviewer-Hint: avatar 延後是刻意決策，pre-flight 確認 uuid dep 已存在
Next-Step: Task 9 PartnerDetailScreen 用 partnerAggregateProvider 把 traits / radar 攤開
EOF
)"
git push
```

---

## Task 9 — Partner detail screen (`/partner/:partnerId`)

**Files:**
- Modify: `lib/features/partner/presentation/screens/partner_detail_screen.dart` (replace Task 6 stub)
- Create: `lib/features/partner/presentation/widgets/partner_traits_card.dart`
- Create: `lib/features/partner/presentation/widgets/partner_radar_summary_card.dart`
- Create: `lib/features/partner/presentation/widgets/partner_conversation_tile.dart`
- Test: `test/widget/features/partner/partner_detail_screen_test.dart`
- (Reuse) `lib/app/main_shell.dart` — extract `_NewConversationSheet` to a public widget so PartnerDetail can call `showModalBottomSheet`. **Or** copy its content; choose extraction for DRY (see Step 3 below).

**Step 1: Write failing tests**

```dart
// test/widget/features/partner/partner_detail_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vibe_sync/features/partner/domain/entities/partner.dart';
import 'package:vibe_sync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibe_sync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibe_sync/features/partner/presentation/screens/partner_detail_screen.dart';
import 'package:vibe_sync/features/partner/presentation/widgets/partner_traits_card.dart';
import 'package:vibe_sync/features/partner/presentation/widgets/partner_radar_summary_card.dart';
import 'package:vibe_sync/features/conversation/domain/entities/conversation.dart';

Partner _p() => Partner(
  id: 'p1', name: 'Alice',
  createdAt: DateTime(2026, 4, 20),
  updatedAt: DateTime(2026, 4, 20),
  ownerUserId: 'u1',
);

void main() {
  testWidgets('header shows partner name + ⋮ menu', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => const <Conversation>[]),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();
    expect(find.text('Alice'), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
  });

  testWidgets('shows traits card + radar summary card + new-conversation button',
      (t) async {
    // ... same overrides as above
    await t.pumpAndSettle();
    expect(find.byType(PartnerTraitsCard), findsOneWidget);
    expect(find.byType(PartnerRadarSummaryCard), findsOneWidget);
    expect(find.text('+ 新增對話'), findsOneWidget);
  });

  testWidgets('empty conversation list shows hint text', (t) async {
    // empty conversations override
    await t.pumpAndSettle();
    expect(find.textContaining('尚未有對話'), findsOneWidget);
  });

  testWidgets('partner missing (deleted/merged) shows fallback', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerByIdProvider('ghost').overrideWith((_) => null),
        partnerAggregateProvider('ghost')
            .overrideWith((_) => PartnerAggregateView.empty()),
        conversationsByPartnerProvider('ghost')
            .overrideWith((_) => const <Conversation>[]),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'ghost')),
    ));
    await t.pumpAndSettle();
    expect(find.textContaining('找不到對象'), findsOneWidget);
  });
}
```

> **Tests on radar parsing** (`lastAnalysisSnapshotJson` → 5-dim) belong with `PartnerRadarSummaryCard` unit tests if logic is non-trivial. Pure widget rendering test above just asserts the card is present.

**Step 2: Run, expect FAIL** — widgets / proper detail screen don't exist.

**Step 3: Extract `_NewConversationSheet` for reuse**

Move `_NewConversationSheet` from `lib/app/main_shell.dart` into a new file:

```dart
// lib/features/conversation/presentation/widgets/new_conversation_sheet.dart
// (verbatim move of the existing _NewConversationSheet body, renamed to NewConversationSheet)
```

Update `main_shell.dart` to import + use the public name. Update Task 7's FAB-removed sheet site if any leftover. **Title string「新增對話」stays unchanged** — Task 15 (Phase 4) handles the global copy sweep including this title.

> **Why extract instead of copy:** Codex C1 / DRY. Two copies will drift; Bruce's "新增對話" complaint becomes two places to fix in Task 15.

**Step 4: Implement detail screen + cards**

```dart
// lib/features/partner/presentation/screens/partner_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../conversation/presentation/widgets/new_conversation_sheet.dart';
import '../providers/partner_providers.dart';
import '../widgets/partner_conversation_tile.dart';
import '../widgets/partner_radar_summary_card.dart';
import '../widgets/partner_traits_card.dart';

class PartnerDetailScreen extends ConsumerWidget {
  final String partnerId;
  const PartnerDetailScreen({super.key, required this.partnerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partner = ref.watch(partnerByIdProvider(partnerId));
    final agg = ref.watch(partnerAggregateProvider(partnerId));
    final conversations = ref.watch(conversationsByPartnerProvider(partnerId));

    if (partner == null) {
      return const Scaffold(
        body: Center(child: Text('找不到對象（可能已被合併或刪除）')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(partner.name),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'merge', child: Text('合併到其他對象')),
              PopupMenuItem(value: 'edit', child: Text('編輯對象')),
              PopupMenuItem(value: 'delete', child: Text('刪除對象')),
            ],
            onSelected: (_) {
              // Phase 4 Task 12-13 wires actual handlers. Phase 2 = visible-only.
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PartnerTraitsCard(view: agg),
          const SizedBox(height: 12),
          PartnerRadarSummaryCard(latestConversation:
              conversations.isEmpty ? null : conversations.first),
          const SizedBox(height: 16),
          if (conversations.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('尚未有對話，從下方「+ 新增對話」開始',
                  textAlign: TextAlign.center),
            )
          else
            ...conversations.map(
              (c) => PartnerConversationTile(
                conversation: c,
                onTap: () => context.push('/conversation/${c.id}'),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          // Phase 3 Task 10 wires partnerId pass-through; Phase 2 still
          // creates conversations without partnerId (legacy path).
          builder: (_) => const NewConversationSheet(),
        ),
        label: const Text('+ 新增對話'),
      ),
    );
  }
}
```

`PartnerTraitsCard` — pure render of `PartnerAggregateView` fields (`unionInterests`, `unionTraits`, `unionNotes`, `latestHeat`, `totalRounds`, `totalMessages`, `lastInteraction`). Simple chip rows + count footer.

`PartnerRadarSummaryCard` — accepts a nullable `Conversation`. If `null` or `latestConversation.lastAnalysisSnapshotJson == null` → "最新對話尚未分析". Otherwise parse the JSON and render a small (~120-160 dp) `fl_chart` `RadarChart` with the existing 5-dim shape used in `analysis_screen.dart`. **Look up the existing parser** at `lib/features/analysis/...` rather than reinventing — extract to a shared helper if it isn't already public.

`PartnerConversationTile` — name + last message timestamp + heat badge if `lastAnalysisSnapshotJson` parseable.

> **Sticky vs FAB「+ 新增對話」**: A2 parent plan Task 9 says "sticky `+ 新增對話` button". `FloatingActionButton.extended` is the closest material equivalent and avoids stack-overlap with the conversation list. If Codex prefers a literal sticky bottom bar, swap to `bottomSheet:` slot.

**Step 5: Run tests + analyze**

```bash
flutter test test/widget/features/partner/
flutter test test/widget/router_test.dart
flutter analyze lib/features/partner/ lib/app/main_shell.dart
```

**Step 6: Commit**

```bash
git add lib/features/partner/presentation/screens/partner_detail_screen.dart \
        lib/features/partner/presentation/widgets/partner_traits_card.dart \
        lib/features/partner/presentation/widgets/partner_radar_summary_card.dart \
        lib/features/partner/presentation/widgets/partner_conversation_tile.dart \
        lib/features/conversation/presentation/widgets/new_conversation_sheet.dart \
        lib/app/main_shell.dart \
        test/widget/features/partner/partner_detail_screen_test.dart
git commit -m "$(cat <<'EOF'
[feat] PartnerDetailScreen — header / traits / radar 小卡 / 對話列 / + 新增對話

- 三個 narrow providers: partnerByIdProvider / partnerAggregateProvider / conversationsByPartnerProvider
- partner 不存在（被合併/刪除）→ fallback 文案
- PartnerRadarSummaryCard 重用 analysis_screen 既有 lastAnalysisSnapshotJson parser
- ⋮ menu 三選項可見但未綁 handler（Phase 4 Task 12-13 才接）
- _NewConversationSheet 改 public NewConversationSheet 提到 conversation/widgets，PartnerDetail / MainShell 共用
- 對話 cell tap → /conversation/:id（D3 plan-default A）
- + 新增對話 FAB 仍用既有 sheet，partnerId 注入留給 Phase 3 Task 10

Reviewer-Hint: ⋮ menu 故意 visible-only，避免本 phase blast radius
Next-Step: Phase 3 接 D1 + D4，從新對話 partnerId 注入開始
EOF
)"
git push
```

---

## Codex Review Hot Spots

Tell Codex to focus on:

1. **Narrow-invalidation invariant (C1)**: grep all Phase 2 files for `conversationsProvider`. Expected count = 0. Any Phase 2 widget touching the legacy global is a contract break.
2. **go_router order**: `/partner/new` must render before `/partner/:partnerId` in the routes list. Test must lock the literal-vs-parametric resolution.
3. **Auth scope leakage**: `AddPartnerScreen` reads `authConversationScopeProvider.valueOrNull` and passes it through. Confirm the override pattern in tests matches the real provider's type.
4. **HomeContent dead-code**: marked `@Deprecated`, not deleted. Confirm Codex agrees with deferring removal to Phase 4 (vs deleting now and forcing Phase 3 to import-fix any test referring to it).
5. **NewConversationSheet extraction**: from `main_shell.dart` to `conversation/presentation/widgets/`. Verify no behavior delta — diff should be a pure move + visibility flip from `_` to public. Title string "新增對話" must NOT be touched here (Task 15 owns it).
6. **PartnerRadarSummaryCard parser reuse**: confirm the radar parser used in `analysis_screen.dart` is reused (not duplicated). If it isn't already public, the extraction must be its own commit.

---

## Daisy-Decision-Needed (Phase 2 specific)

None at plan-write time. Inheriting D1-D4 plan-defaults from parent A2 plan. If Codex flags new ambiguity → write `Verdict: Daisy-Decision-Needed` per `docs/shared-agent-rules.md`.

---

## Sanity gate before opening PR

```bash
flutter test                         # full suite — must be all green
flutter analyze                      # zero NEW warnings vs main baseline
git log --oneline main..HEAD         # MUST show 4 commits (one per Task)
git diff --stat main..HEAD           # blast radius sanity
```

Then open PR `feature/partner-entity-A2-ui` → `main`, queue item flips to Codex code review. After Codex green → merge → soak observation → Phase 3 session.
