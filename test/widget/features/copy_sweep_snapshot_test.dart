// test/widget/features/copy_sweep_snapshot_test.dart
//
// Anti-rot snapshot tests for ADR-15 vocabulary alignment ("對象 / 對話" two-tier).
//
// Any future PR that drifts these strings will fail these tests — fix the
// strings, don't relax the tests, unless ADR-15 itself is being amended.
//
// Vocabulary contract (Phase 4 Task 5 / ADR-15):
//   - Home tab affordances + global nav  → 「對象」(Partner-level)
//   - Partner detail interior + OCR flow → 「對話」(Conversation-level, kept)
//
// These tests assert RENDERED text via finders — they do not inspect string
// constants. Each test pumps the actual widget under test inside a minimal
// ProviderScope with the same overrides patterns used by the partner / detail
// suites (see partner_list_screen_test.dart and partner_detail_screen_test.dart).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:vibesync/app/main_shell.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/partner/presentation/screens/partner_detail_screen.dart';
import 'package:vibesync/features/partner/presentation/screens/partner_list_screen.dart';

Partner _p(String id, String name) => Partner(
      id: id,
      name: name,
      createdAt: DateTime(2026, 4, 20),
      updatedAt: DateTime(2026, 4, 20),
      ownerUserId: 'u1',
    );

void main() {
  testWidgets(
    'home FAB carries 「新增對象」 tooltip (Partner-level vocabulary)',
    (t) async {
      // We pump `HomeFab` standalone instead of the full `MainShell` because
      // the latter eagerly mounts the Learning + Report tabs via IndexedStack,
      // which require Hive — too brittle for a vocabulary snapshot test.
      // GoRouter is wired so the FAB's `context.push('/partner/new')` resolves
      // (Tooltip rendering itself doesn't require a tap, but keeping the
      // router stub around guards future refactors that re-add it).
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const Scaffold(
              floatingActionButton: HomeFab(),
              body: SizedBox.shrink(),
            ),
          ),
          GoRoute(
            path: '/partner/new',
            builder: (_, __) => const Scaffold(body: Text('partner-new-stub')),
          ),
        ],
      );

      await t.pumpWidget(ProviderScope(
        child: MaterialApp.router(routerConfig: router),
      ));
      await t.pumpAndSettle();

      // FAB is rendered.
      expect(find.byType(FloatingActionButton), findsOneWidget);
      // Tooltip surfaces 對象 vocabulary to screen readers + long-press users.
      expect(
        find.byTooltip('新增對象'),
        findsOneWidget,
        reason: 'Home FAB must advertise 「新增對象」 (Partner-level, ADR-15). '
            'If you changed this string, amend ADR-15 first.',
      );
    },
  );

  testWidgets(
    'partner list empty state uses 「對象」 vocabulary',
    (t) async {
      await t.pumpWidget(ProviderScope(
        overrides: [
          partnerListProvider.overrideWith((_) => const <Partner>[]),
        ],
        child: const MaterialApp(home: Scaffold(body: PartnerListScreen())),
      ));
      await t.pumpAndSettle();

      // Exact string checks — drift detector. Empty state now carries the
      // "memory coach" positioning while preserving Partner-level vocabulary.
      expect(find.text('先建立第一張對象卡'), findsOneWidget);
      expect(
        find.text('VibeSync 會記得你和每個對象，幫你看懂互動，陪你練下一步'),
        findsOneWidget,
        reason:
            'Partner list empty state must explain the memory-coach positioning.',
      );
      expect(
        find.text('一個人一張卡，不同日期、IG、Line 或交友軟體的聊天，都整理在同一張卡裡'),
        findsOneWidget,
        reason: 'Partner list empty state must use 「對象」 vocabulary (ADR-15).',
      );
      // Negative assertion: no leftover 「對話」 wording in the empty state.
      expect(
        find.textContaining('還沒有對話'),
        findsNothing,
        reason: 'Empty state must NOT mention 對話 — that is Conversation-level.',
      );
    },
  );

  testWidgets(
    'partner detail "+ 新增對話" FAB stays Conversation-level (kept)',
    (t) async {
      await t.pumpWidget(ProviderScope(
        overrides: [
          partnerByIdProvider('p1').overrideWith((_) => _p('p1', 'Alice')),
          partnerAggregateProvider('p1')
              .overrideWith((_) => PartnerAggregateView.empty()),
          conversationsByPartnerProvider('p1')
              .overrideWith((_) => const <Conversation>[]),
          partnerListProvider.overrideWith((_) => [_p('p1', 'Alice')]),
        ],
        child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
      ));
      await t.pumpAndSettle();

      // FAB label MUST stay 「新增對話」 — this is Conversation creation under
      // an existing Partner, the ADR-15 contract explicitly keeps this.
      expect(
        find.text('+ 新增對話'),
        findsOneWidget,
        reason: 'Partner detail FAB creates a Conversation under the current '
            'Partner — string must stay 「新增對話」 per ADR-15.',
      );
      // Empty conversation hint stays Conversation-level, but uses plainer
      // "互動紀錄" wording so first-time users understand the folder model.
      expect(
        find.textContaining('還沒有互動紀錄'),
        findsOneWidget,
        reason: 'Partner detail empty conversation hint must stay '
            '「對話」 (Conversation-level).',
      );
    },
  );
}
