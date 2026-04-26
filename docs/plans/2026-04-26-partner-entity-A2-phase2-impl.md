# Partner Entity Refactor A2 — Phase 2 (UI / IA shift) Implementation Plan

> **Revision history**
> - r1 (2026-04-26 e25cfce): initial draft
> - r2 (2026-04-26 ca2581d): patched after Codex `REVISE_BEFORE_IMPLEMENTATION` verdict
>   in [`docs/reviews/2026-04-26_partner-entity-A2-phase2-plan_codex-review.md`](../reviews/2026-04-26_partner-entity-A2-phase2-plan_codex-review.md).
>   Five fixes: (P1) package name `vibesync`, (P1) `context.replace` for submit
>   + back-stack test, (P1) hermetic widget tests, (P1) auth-null guard,
>   (P2) explicit `AnalysisResult.fromJson` reuse target. Plus ⋮ menu
>   conditional from Hot-spot judgment.
> - r3 (2026-04-26): patched after Codex r2 scoped re-review (`6842bab`). Two
>   test-harness fixes:
>   - **(P1)** `add_partner_navigation_test.dart` was const-empty-overriding
>     `partnerListProvider` while asserting `Alice` appears after back — false
>     red guaranteed. Switched to `_HomeSentinel` (this test verifies routing,
>     not list rendering); kept temp Hive box so submit still persists; data-
>     side claim already covered by `add_partner_screen_test.dart`.
>   - **(P1)** `add_partner_screen_test.dart` was missing `import 'dart:async'`
>     (used by `StreamController` in the auth-loading test) and carried
>     unused `hive_ce_flutter` + `path_provider_platform_interface` imports.
>     Imports trimmed.
>
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

**Step 1: Write failing widget tests (hermetic — sentinel widgets only)**

```dart
// test/widget/router_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// SENTINEL widgets — we only verify the route TABLE shape (literal vs
// parametric resolution + back-compat path), NOT the real screens. Mounting
// the live PartnerDetailScreen / AddPartnerScreen / AnalysisScreen here would
// pull in Hive boxes / authConversationScopeProvider / conversationProvider,
// turning a route-shape test into an integration test that fails for
// infrastructure reasons (Codex P1.3a).
class _PartnerDetailSentinel extends StatelessWidget {
  final String partnerId;
  const _PartnerDetailSentinel(this.partnerId);
  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Text('partner-detail:$partnerId'));
}

class _AddPartnerSentinel extends StatelessWidget {
  const _AddPartnerSentinel();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Text('add-partner'));
}

class _AnalysisSentinel extends StatelessWidget {
  final String conversationId;
  const _AnalysisSentinel(this.conversationId);
  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Text('analysis:$conversationId'));
}

GoRouter _testRouter(String initialLocation) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(
      path: '/partner/new',
      builder: (c, s) => const _AddPartnerSentinel(),
    ),
    GoRoute(
      path: '/partner/:partnerId',
      builder: (c, s) => _PartnerDetailSentinel(s.pathParameters['partnerId']!),
    ),
    GoRoute(
      path: '/conversation/:id',
      builder: (c, s) => _AnalysisSentinel(s.pathParameters['id']!),
    ),
  ],
);

void main() {
  testWidgets('/partner/:partnerId routes to partner detail (sentinel)',
      (t) async {
    await t.pumpWidget(ProviderScope(
      child: MaterialApp.router(routerConfig: _testRouter('/partner/abc-123')),
    ));
    await t.pumpAndSettle();
    expect(find.text('partner-detail:abc-123'), findsOneWidget);
  });

  testWidgets('/partner/new routes to add-partner (literal beats parametric)',
      (t) async {
    await t.pumpWidget(ProviderScope(
      child: MaterialApp.router(routerConfig: _testRouter('/partner/new')),
    ));
    await t.pumpAndSettle();
    expect(find.text('add-partner'), findsOneWidget);
    // Critical guard: parametric must NOT match.
    expect(find.text('partner-detail:new'), findsNothing);
  });

  testWidgets('/conversation/:id keeps back-compat (sentinel)', (t) async {
    await t.pumpWidget(ProviderScope(
      child: MaterialApp.router(routerConfig: _testRouter('/conversation/conv-1')),
    ));
    await t.pumpAndSettle();
    expect(find.text('analysis:conv-1'), findsOneWidget);
  });
}
```

> **Why sentinels, not the real screens:** the router test's purpose is to lock the **route table shape** — literal-vs-parametric resolution and the `/conversation/:id` back-compat path. Mounting real screens drags in their provider graph (Hive `Box<Conversation>`, auth scope, etc.) and turns red bars into infrastructure noise. The real screens get their own widget tests in Tasks 7-9 (with proper provider overrides).
>
> **Note on order:** `/partner/new` is declared **before** `/partner/:partnerId` so the literal path wins over the parametric one. go_router resolves first match — invert and `new` becomes a partner id "new". This MUST be in the live `routes.dart` too.

**Step 2: Run, expect 3 PASS immediately**

```bash
flutter test test/widget/router_test.dart
```

Sentinel widgets are self-contained (no Hive / no providers needed beyond an empty `ProviderScope`), so this is the rare TDD case where the test passes on first run because it's a *contract* test against the GoRouter table shape. The "fail first" comes from Step 3 below: pointing the LIVE router at not-yet-existing screens.

**Step 3: Create live screen stubs so `lib/app/routes.dart` can import them**

These are NOT test fixtures — they exist so the live `routes.dart` (Step 4) compiles. Tasks 7-9 replace these stubs with the real implementations.

```dart
// lib/features/partner/presentation/screens/partner_detail_screen.dart  (STUB — Task 9 replaces)
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
// lib/features/partner/presentation/screens/add_partner_screen.dart  (STUB — Task 8 replaces)
import 'package:flutter/material.dart';
class AddPartnerScreen extends StatelessWidget {
  const AddPartnerScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('add partner')));
}
```

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

**Step 1: Write failing widget tests (hermetic — pass aggregate down, no per-partner overrides)**

`PartnerListCard` accepts an already-computed `PartnerAggregateView` instead of watching `partnerAggregateProvider(id)` itself. This (a) keeps the card a pure render and (b) means tests only need to override `partnerListProvider` plus a single mapping from partner id → aggregate, not one Riverpod override per partner row (Codex P1.3b).

```dart
// test/widget/features/partner/partner_list_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/partner/presentation/screens/partner_list_screen.dart';

Partner _p(String id, String name) => Partner(
  id: id,
  name: name,
  createdAt: DateTime(2026, 4, 20),
  updatedAt: DateTime(2026, 4, 20),
  ownerUserId: 'u1',
);

PartnerAggregateView _agg({int rounds = 0, int? heat}) => PartnerAggregateView(
  unionInterests: const [],
  unionTraits: const [],
  unionNotes: null,
  latestHeat: heat,
  totalRounds: rounds,
  totalMessages: 0,
  lastInteraction: null,
);

void main() {
  testWidgets('empty state: shows "還沒有對象，加一個開始"', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerListProvider.overrideWith((_) => const <Partner>[]),
      ],
      child: const MaterialApp(home: PartnerListScreen()),
    ));
    await t.pumpAndSettle();
    expect(find.textContaining('還沒有對象'), findsOneWidget);
  });

  testWidgets('renders one PartnerListCard per partner with aggregate', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerListProvider
            .overrideWith((_) => [_p('a', 'Alice'), _p('b', 'Bob')]),
        partnerAggregateProvider('a').overrideWith((_) => _agg(rounds: 3, heat: 70)),
        partnerAggregateProvider('b').overrideWith((_) => _agg(rounds: 1)),
      ],
      child: const MaterialApp(home: PartnerListScreen()),
    ));
    await t.pumpAndSettle();
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.textContaining('3 段對話'), findsOneWidget);
    expect(find.textContaining('1 段對話'), findsOneWidget);
  });

  testWidgets('list preserves order from partnerListProvider', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerListProvider
            .overrideWith((_) => [_p('z', 'Zoe'), _p('a', 'Alice')]),
        partnerAggregateProvider('z').overrideWith((_) => _agg()),
        partnerAggregateProvider('a').overrideWith((_) => _agg()),
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

> **Why aggregate is passed down, not watched in-card:** `partnerAggregateProvider` is `Provider.family<…, String>` — overriding for 50 partners would mean 50 override entries in every list test. Lifting the watch to `PartnerListScreen` (one override per id) keeps the card a pure render and aligns with Codex P1.3b. The narrow-invalidation contract still holds because `PartnerListScreen` itself watches `partnerAggregateProvider(p.id)` per row, which only re-evaluates that row when its partner's conversations change.
>
> **Why no test for tap → `/partner/:id`** here: that requires a router-aware harness. The router test (Task 6) and the detail-screen entry path (Task 9) already cover navigation.

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
        // Watch aggregate AT THE LIST LEVEL so each row re-evaluates only when
        // its own partner's conversations change (narrow-invalidation
        // contract). Card receives data, doesn't watch.
        final agg = ref.watch(partnerAggregateProvider(p.id));
        return PartnerListCard(
          partner: p,
          aggregate: agg,
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

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/partner.dart';
import '../../domain/extensions/partner_aggregates.dart';

/// Pure render — receives aggregate, does NOT subscribe to providers.
/// This keeps tests hermetic (no per-row provider overrides needed) and
/// makes the card trivially reusable in non-list contexts.
class PartnerListCard extends StatelessWidget {
  final Partner partner;
  final PartnerAggregateView aggregate;
  final VoidCallback onTap;
  const PartnerListCard({
    super.key,
    required this.partner,
    required this.aggregate,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      title: Text(partner.name, style: AppTypography.titleSmall),
      subtitle: Text(
        '${aggregate.totalRounds} 段對話'
        '${aggregate.latestHeat != null ? ' · 熱度 ${aggregate.latestHeat}' : ''}',
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

**Step 1: Write failing tests (hermetic — opened temp Hive box, real auth override pattern)**

`PartnerRepository`'s constructor accepts `Box<Partner>? box` (`lib/features/partner/data/repositories/partner_repository.dart:21`). Tests open a temp box and pass it through, so we never touch `StorageService.partnersBox` (Codex P1.3c). Auth override uses the live pattern from `test/unit/services/conversation_write_controller_test.dart:79` (Codex P1.3d).

```dart
// test/widget/features/partner/add_partner_screen_test.dart
import 'dart:async';   // StreamController for the auth-loading test
import 'dart:io';      // Directory.systemTemp.createTemp
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/partner/data/repositories/partner_repository.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/partner/presentation/screens/add_partner_screen.dart';

void main() {
  late Directory tmp;
  late Box<Partner> partnerBox;
  late PartnerRepository repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('add_partner_test');
    Hive.init(tmp.path);
    if (!Hive.isAdapterRegistered(PartnerAdapter().typeId)) {
      Hive.registerAdapter(PartnerAdapter());
    }
    partnerBox = await Hive.openBox<Partner>('partners_${tmp.path.hashCode}');
    repo = PartnerRepository(box: partnerBox);
  });

  tearDown(() async {
    await partnerBox.close();
    await tmp.delete(recursive: true);
  });

  Widget _harness({Stream<String?>? authStream}) => ProviderScope(
        overrides: [
          partnerRepositoryProvider.overrideWithValue(repo),
          authConversationScopeProvider.overrideWith(
              (ref) => authStream ?? Stream.value('u-test')),
        ],
        child: const MaterialApp(home: AddPartnerScreen()),
      );

  testWidgets('submit disabled while name empty', (t) async {
    await t.pumpWidget(_harness());
    await t.pumpAndSettle();
    final btn = t.widget<FilledButton>(find.widgetWithText(FilledButton, '建立'));
    expect(btn.onPressed, isNull);
  });

  testWidgets('submit enabled once name has non-whitespace', (t) async {
    await t.pumpWidget(_harness());
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField), 'Alice');
    await t.pump();
    final btn = t.widget<FilledButton>(find.widgetWithText(FilledButton, '建立'));
    expect(btn.onPressed, isNotNull);
  });

  testWidgets('successful submit writes Partner with ownerUserId from auth',
      (t) async {
    await t.pumpWidget(_harness());
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField), 'Alice');
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, '建立'));
    await t.pumpAndSettle();
    expect(partnerBox.values.length, 1);
    final p = partnerBox.values.single;
    expect(p.name, 'Alice');
    expect(p.ownerUserId, 'u-test');
  });

  testWidgets('submit BLOCKED when authConversationScopeProvider is null',
      (t) async {
    // Auth still resolving / signed out — Partner without ownerUserId would
    // never appear in partnerListProvider (auth-gated). Codex P2/P1.4.
    await t.pumpWidget(_harness(authStream: Stream.value(null)));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField), 'Alice');
    await t.pump();
    final btn = t.widget<FilledButton>(find.widgetWithText(FilledButton, '建立'));
    expect(btn.onPressed, isNull,
        reason: 'must NOT create ownerless Partner that would be invisible');
    expect(partnerBox.values, isEmpty);
  });

  testWidgets('submit BLOCKED while auth still loading (no value emitted yet)',
      (t) async {
    // StreamController never emits → AsyncLoading state. Submit must wait.
    final controller = StreamController<String?>();
    addTearDown(controller.close);
    await t.pumpWidget(_harness(authStream: controller.stream));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField), 'Alice');
    await t.pump();
    final btn = t.widget<FilledButton>(find.widgetWithText(FilledButton, '建立'));
    expect(btn.onPressed, isNull, reason: 'must wait for auth resolution');
  });
}
```

> **Hermetic checklist this satisfies:**
> - Codex P1.3c: real `PartnerRepository(box: openedTestBox)` — no `StorageService` dependency.
> - Codex P1.3d: `authConversationScopeProvider.overrideWith((ref) => Stream.value(...))` matches the real `StreamProvider<String?>` API.
> - Codex P2/P1.4: explicit "auth null → submit blocked" + "auth loading → submit blocked" tests.
> - `_FakeRepo` deleted entirely — calling the real constructor with `box: partnerBox` is enough.

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

  Future<void> _submit(String ownerId) async {
    final name = _name.text.trim();
    if (name.isEmpty || _busy) return;
    setState(() => _busy = true);
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
    // context.replace (NOT .go): pop /partner/new off the stack and put
    // /partner/:id in its place, so back from detail returns to the Home
    // (Partner list) underneath. context.go would rebuild the entire stack
    // and lose the Home root (Codex P1.2).
    context.replace('/partner/${partner.id}');
  }

  @override
  Widget build(BuildContext context) {
    // Auth-scope gate (Codex P2/P1.4): if auth is loading or null, submit is
    // disabled — never create an ownerless Partner that partnerListProvider
    // would filter out.
    final authAsync = ref.watch(authConversationScopeProvider);
    final ownerId = authAsync.valueOrNull;
    final authReady = !authAsync.isLoading && ownerId != null;
    final canSubmit = authReady && _name.text.trim().isNotEmpty && !_busy;

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
              onPressed: canSubmit ? () => _submit(ownerId!) : null,
              child: const Text('建立'),
            ),
            if (!authReady)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('請先登入再建立對象',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
          ],
        ),
      ),
    );
  }
}
```

> **Why `context.replace` not `context.go`** (Codex P1.2): `context.go('/x')` rebuilds the route stack from scratch, losing the Home root underneath `/partner/new`. `context.replace('/x')` swaps the top stack entry — Home stays available so back from detail returns to the Partner list. Validated by the Home → /partner/new → submit → detail → back test in Step 4 below.
>
> **Why null auth disables submit** (Codex P2/P1.4): `partnerListProvider` returns `[]` when auth scope is null, AND filters by `ownerUserId == userId`. A Partner created with `ownerUserId == null` would never render in the list — silent data loss. The form blocks submit instead.
>
> **Avatar deferred**: A2 plan Task 8 says "avatar 可選 — submit 時不選也能建". Phase 2 ships **without** an avatar picker in this PR — `Partner.avatarPath` stays nullable and the field is not exposed in the form. Added in Phase 3/4 if Bruce flags it. Document this in the commit `Reviewer-Hint`.

**Step 3b: Add Home → new → detail → back navigation test** (Codex P1.2)

Add a separate test file to lock the back-stack contract after `context.replace`. **Home is a sentinel**, not the real `PartnerListScreen` — this test's job is to verify *routing* behavior (Home root persists; back from detail does not return to `/partner/new`). The data-side claim (Partner actually written to Hive) is already covered by `add_partner_screen_test.dart`'s "successful submit writes Partner with ownerUserId from auth" test, so we don't re-assert it here.

```dart
// test/widget/features/partner/add_partner_navigation_test.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';

import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/partner/data/repositories/partner_repository.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/partner/presentation/screens/add_partner_screen.dart';

// Sentinel Home — we verify the BACK-STACK contract, not what Home renders.
// Using the real PartnerListScreen here would require also overriding
// partnerAggregateProvider per partner (Task 7's lifted-aggregate design),
// turning a router test into an integration test that fails for unrelated
// reasons. The data-side assertion ("Partner actually persisted") lives in
// add_partner_screen_test.dart.
class _HomeSentinel extends StatelessWidget {
  const _HomeSentinel();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Text('home-sentinel'));
}

void main() {
  late Directory tmp;
  late Box<Partner> partnerBox;
  late PartnerRepository repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('add_partner_nav');
    Hive.init(tmp.path);
    if (!Hive.isAdapterRegistered(PartnerAdapter().typeId)) {
      Hive.registerAdapter(PartnerAdapter());
    }
    partnerBox = await Hive.openBox<Partner>('partners_${tmp.path.hashCode}');
    repo = PartnerRepository(box: partnerBox);
  });
  tearDown(() async {
    await partnerBox.close();
    await tmp.delete(recursive: true);
  });

  testWidgets('Home → /partner/new → submit → /partner/:id → back → Home',
      (t) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (c, s) => const _HomeSentinel()),
        GoRoute(path: '/partner/new', builder: (c, s) => const AddPartnerScreen()),
        GoRoute(
          path: '/partner/:id',
          builder: (c, s) =>
              Scaffold(body: Text('detail:${s.pathParameters['id']!}')),
        ),
      ],
    );

    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerRepositoryProvider.overrideWithValue(repo),
        authConversationScopeProvider
            .overrideWith((ref) => Stream.value('u-test')),
        // NB: do NOT override partnerListProvider — _HomeSentinel doesn't
        // read it. Overriding it const-empty here was the r2 false-red
        // (Alice could never appear in a const [] list, so the back→Home
        // assertion was guaranteed to fail).
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await t.pumpAndSettle();

    // Home sentinel visible
    expect(find.text('home-sentinel'), findsOneWidget);

    // Push to /partner/new
    router.push('/partner/new');
    await t.pumpAndSettle();
    expect(find.text('新增對象'), findsOneWidget);

    // Submit creates partner + replaces /partner/new with /partner/:id
    await t.enterText(find.byType(TextFormField), 'Alice');
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, '建立'));
    await t.pumpAndSettle();

    // We're on detail (sentinel detail, just enough to read partnerId)
    expect(find.textContaining('detail:'), findsOneWidget);

    // Sanity: Partner actually persisted (cheap check; full coverage in
    // add_partner_screen_test.dart's repo write test).
    expect(partnerBox.values.length, 1);
    expect(partnerBox.values.single.name, 'Alice');

    // Critical: pop returns to Home, NOT back to /partner/new (which would
    // happen if we used context.go and then push instead of replace).
    expect(router.canPop(), isTrue, reason: 'Home stack root must persist');
    router.pop();
    await t.pumpAndSettle();
    expect(find.text('home-sentinel'), findsOneWidget,
        reason: 'Back from detail must land on Home, not /partner/new');
    expect(find.text('新增對象'), findsNothing,
        reason: '/partner/new must NOT be reachable via back');
  });
}
```

> **Direct-entry no-history fallback** (Codex P1.2 third bullet): if a user lands on `/partner/:id` cold (deep link / app reopened on detail page) and presses back, `Navigator.canPop` is false. Phase 2 deliberately defers this fallback because Phase 3 wires the Partner-list home as the only normal entry point — direct deep links to `/partner/:id` aren't shipped yet. Documented here as known limitation; Phase 4 polish can add an explicit "回首頁" affordance if Bruce/TF surfaces a real case.

**Step 4: Run tests**

```bash
flutter test test/widget/features/partner/add_partner_screen_test.dart
flutter test test/widget/features/partner/add_partner_navigation_test.dart
flutter analyze lib/features/partner/presentation/screens/add_partner_screen.dart
```
Expected: 5 new tests PASS (4 from Step 1 + 1 from Step 3b); analyze clean.

**Step 5: Commit**

```bash
git add lib/features/partner/presentation/screens/add_partner_screen.dart \
        test/widget/features/partner/add_partner_screen_test.dart \
        test/widget/features/partner/add_partner_navigation_test.dart \
        pubspec.yaml pubspec.lock          # only if Step 0 ran
git commit -m "$(cat <<'EOF'
[feat] AddPartnerScreen — name + auth-ready gate + UUID + context.replace

- 用 PartnerRepository.upsertIfAbsent (A2 Phase 1 surface)，避免引入新 write API
- ownerUserId 從 authConversationScopeProvider 抓，null/loading 時 submit 禁用
  （絕不建 ownerless Partner — partnerListProvider 會把它過濾掉）
- 提交後 ref.invalidate(partnerListProvider) → MainShell 立即看到
- 用 context.replace 而非 context.go：/partner/new 換成 /partner/:id 同時保留
  Home root，從 detail 按 back 會回到 Partner list（不是回到 /partner/new）
- 加 add_partner_navigation_test.dart 鎖 Home → new → detail → back 行為
- avatar picker 故意延後到 Phase 3（A2 plan Task 8 註明可選）

Reviewer-Hint: r2 修正項 P1.2/P1.3c/P1.3d/P1.4，avatar 延後不變
Next-Step: Task 9 PartnerDetailScreen 用 AnalysisResult.fromJson 跑 radar 小卡
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

import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/partner/presentation/screens/partner_detail_screen.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_traits_card.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_radar_summary_card.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';

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

**Step 1b: Add PartnerRadarSummaryCard parser test** (Codex P2.2)

```dart
// test/widget/features/partner/partner_radar_summary_card_test.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_radar_summary_card.dart';

Conversation _conv({String? snapshot}) => Conversation(
  id: 'c1',
  partnerId: 'p1',
  name: '測試',
  messages: const [],
  createdAt: DateTime(2026, 4, 20),
  updatedAt: DateTime(2026, 4, 20),
  lastAnalysisSnapshotJson: snapshot,
);

void main() {
  testWidgets('null conversation → fallback text', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(body: PartnerRadarSummaryCard(latestConversation: null)),
    ));
    expect(find.text('最新對話尚未分析'), findsOneWidget);
  });

  testWidgets('snapshot with dimensions renders RadarChart', (t) async {
    final snapshot = jsonEncode({
      'enthusiasm': {'score': 70, 'level': 'warm'},
      'dimensions': {
        'heat': 70,
        'engagement': 65,
        'topicDepth': 55,
        'replyWillingness': 80,
        'emotionalConnection': 60,
      },
      // Other AnalysisResult.fromJson required-ish fields can be omitted —
      // factory tolerates nullables and defaults dimensions per-key.
    });
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PartnerRadarSummaryCard(latestConversation: _conv(snapshot: snapshot)),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('最新對話尚未分析'), findsNothing);
    // RadarChart from fl_chart — verify the widget mounted (chart pixel
    // assertions are brittle; presence check is the contract).
    expect(find.byType(PartnerRadarSummaryCard), findsOneWidget);
  });

  testWidgets('snapshot without dimensions key → factory still returns null map → fallback',
      (t) async {
    final snapshot = jsonEncode({
      'enthusiasm': {'score': 50, 'level': 'cool'},
      // no 'dimensions' key — _parseDimensions returns null
    });
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PartnerRadarSummaryCard(latestConversation: _conv(snapshot: snapshot)),
      ),
    ));
    expect(find.text('最新對話尚未分析'), findsOneWidget);
  });

  testWidgets('malformed snapshot → fallback (no throw)', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PartnerRadarSummaryCard(
          latestConversation: _conv(snapshot: 'not-json{{{'),
        ),
      ),
    ));
    expect(find.text('最新對話尚未分析'), findsOneWidget);
  });
}
```

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
            // Phase 2 ships items DISABLED, not no-op (Codex Hot-spot judgment):
            // visible-but-no-op confuses users if Phase 2 ships independently.
            // Items become enabled in Phase 4 Tasks 12-13 with real handlers.
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'merge', enabled: false,
                child: Text('合併到其他對象（即將推出）'),
              ),
              PopupMenuItem(
                value: 'edit', enabled: false,
                child: Text('編輯對象（即將推出）'),
              ),
              PopupMenuItem(
                value: 'delete', enabled: false,
                child: Text('刪除對象（即將推出）'),
              ),
            ],
            onSelected: (_) {/* unreachable — all items disabled */},
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

`PartnerRadarSummaryCard` — accepts a nullable `Conversation`. If `null` or `latestConversation.lastAnalysisSnapshotJson == null` → "最新對話尚未分析". Otherwise:

```dart
// lib/features/partner/presentation/widgets/partner_radar_summary_card.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../../analysis/domain/entities/analysis_models.dart' show AnalysisResult;
import '../../../conversation/domain/entities/conversation.dart';

class PartnerRadarSummaryCard extends StatelessWidget {
  final Conversation? latestConversation;
  const PartnerRadarSummaryCard({super.key, required this.latestConversation});

  @override
  Widget build(BuildContext context) {
    final dims = _parseDimensions(latestConversation);
    if (dims == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('最新對話尚未分析'),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: 160,
          child: RadarChart(/* shape mirrors analysis_screen.dart 5-dim */),
        ),
      ),
    );
  }

  /// REUSE — call AnalysisResult.fromJson and consume dimensionScores.
  /// AnalysisResult.fromJson is at:
  ///   lib/features/analysis/domain/entities/analysis_models.dart:556
  /// dimensionScores is Map<String, int>? with exactly these keys (default 50):
  ///   heat / engagement / topicDepth / replyWillingness / emotionalConnection
  /// (parsed by the package-private _parseDimensions at analysis_models.dart:632)
  static Map<String, int>? _parseDimensions(Conversation? c) {
    final raw = c?.lastAnalysisSnapshotJson;
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return AnalysisResult.fromJson(json).dimensionScores;
    } catch (_) {
      return null;  // malformed snapshot → render "尚未分析" fallback
    }
  }
}
```

> **Why call `AnalysisResult.fromJson` instead of extracting a helper** (Codex P2.2): `_parseDimensions` is package-private inside `analysis_models.dart`, but the public surface — `AnalysisResult.fromJson` + the public `dimensionScores` field — already returns exactly what the radar card needs. Extracting a separate helper would (a) be a second commit and (b) duplicate the default-50 fallback logic. Calling the existing factory once per card render is cheap (no I/O, just `jsonDecode` + struct build) and keeps a single source of truth.

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
        test/widget/features/partner/partner_detail_screen_test.dart \
        test/widget/features/partner/partner_radar_summary_card_test.dart
git commit -m "$(cat <<'EOF'
[feat] PartnerDetailScreen — header / traits / radar 小卡 / 對話列 / + 新增對話

- 三個 narrow providers: partnerByIdProvider / partnerAggregateProvider / conversationsByPartnerProvider
- partner 不存在（被合併/刪除）→ fallback 文案
- PartnerRadarSummaryCard 重用 analysis_screen 既有 lastAnalysisSnapshotJson parser
- ⋮ menu 三選項顯示但 disabled（即將推出 hint），Phase 4 Task 12-13 才開啟 handler
- _NewConversationSheet 改 public NewConversationSheet 提到 conversation/widgets，PartnerDetail / MainShell 共用
- 對話 cell tap → /conversation/:id（D3 plan-default A）
- + 新增對話 FAB 仍用既有 sheet，partnerId 注入留給 Phase 3 Task 10

Reviewer-Hint: ⋮ menu disabled 而非 no-op（Phase 2 若獨立 ship 不致誤點），radar 用 AnalysisResult.fromJson 公開 API
Next-Step: Phase 3 接 D1 + D4，從新對話 partnerId 注入開始
EOF
)"
git push
```

---

## Codex Review Hot Spots

> **r3 scoped re-review:** focus ONLY on the two r2 remaining findings:
> (1) `add_partner_navigation_test.dart` no longer false-reds (sentinel Home,
>     no `partnerListProvider` const-empty override),
> (2) `add_partner_screen_test.dart` imports clean (`dart:async` added,
>     `hive_ce_flutter` + `path_provider_platform_interface` removed).
> All r1 findings + r2 hot-spot judgments stand. Do NOT re-litigate items
> previously marked acceptable.

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
