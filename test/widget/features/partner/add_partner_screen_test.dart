// test/widget/features/partner/add_partner_screen_test.dart
//
// Hermetic widget tests for AddPartnerScreen.
//
// - Real PartnerRepository(box: openedTestBox) — no StorageService dep.
// - authConversationScopeProvider override matches the real
//   StreamProvider<String?> shape.
// - Auth-null and auth-loading both block submit (Codex r1 P2/P1.4).
//
// KNOWN GAP — back-stack contract not unit-testable in this harness:
// The plan (Codex r3 APPROVED) called for an `add_partner_navigation_test`
// asserting Home → /partner/new → submit → /partner/:id → back → Home.
// Reproducible failure: `pushReplacement` fired from inside the screen's
// async submit chain silently no-ops in `flutter test`, while the same
// router accepts `go(...)` from outside the widget tree (verified via a
// diagnostic harness; see commit body for the trace). Both `setState`
// guard removal, `WidgetsBinding.instance.addPostFrameCallback`, microtask
// defer, `Future.delayed`, and capture-pre-await router refs were tried —
// none change the outcome. The data-side contract (Partner persisted with
// owner) IS covered by the "successful submit writes Partner" test below.
// The back-stack semantic is covered by the manual TF QA checklist.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive_ce.dart';

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
    partnerBox =
        await Hive.openBox<Partner>('partners_${tmp.path.hashCode}');
    repo = PartnerRepository(box: partnerBox);
  });

  tearDown(() async {
    await partnerBox.close();
    await tmp.delete(recursive: true);
  });

  Widget harness({Stream<String?>? authStream}) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (c, s) => const AddPartnerScreen()),
        // /partner/:id stub — submit's pushReplacement lands here. Test
        // assertions stay on the upsert side; this route just needs to
        // exist so the navigation call resolves (no router → hang).
        GoRoute(
          path: '/partner/:id',
          builder: (c, s) => const Scaffold(body: Text('detail-stub')),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        partnerRepositoryProvider.overrideWithValue(repo),
        authConversationScopeProvider.overrideWith(
            (ref) => authStream ?? Stream.value('u-test')),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  // Order matters: the auth-blocked tests run BEFORE the successful submit
  // test. The successful submit triggers `pushReplacement` which appears to
  // disrupt the test framework's between-test cleanup in our setup; running
  // the non-mutating tests first guarantees they always execute.

  testWidgets('submit disabled while name empty', (t) async {
    await t.pumpWidget(harness());
    await t.pumpAndSettle();
    final btn =
        t.widget<FilledButton>(find.widgetWithText(FilledButton, '建立'));
    expect(btn.onPressed, isNull);
  });

  testWidgets('submit enabled once name has non-whitespace', (t) async {
    await t.pumpWidget(harness());
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField), 'Alice');
    await t.pump();
    final btn =
        t.widget<FilledButton>(find.widgetWithText(FilledButton, '建立'));
    expect(btn.onPressed, isNotNull);
  });

  testWidgets('submit BLOCKED when authConversationScopeProvider is null',
      (t) async {
    await t.pumpWidget(harness(authStream: Stream.value(null)));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField), 'Alice');
    await t.pump();
    final btn =
        t.widget<FilledButton>(find.widgetWithText(FilledButton, '建立'));
    expect(btn.onPressed, isNull,
        reason: 'must NOT create ownerless Partner that would be invisible');
    expect(partnerBox.values, isEmpty);
  });

  testWidgets('submit BLOCKED while auth still loading (no value emitted yet)',
      (t) async {
    final controller = StreamController<String?>();
    addTearDown(controller.close);
    await t.pumpWidget(harness(authStream: controller.stream));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField), 'Alice');
    await t.pump();
    final btn =
        t.widget<FilledButton>(find.widgetWithText(FilledButton, '建立'));
    expect(btn.onPressed, isNull, reason: 'must wait for auth resolution');
  });

  testWidgets('successful submit writes Partner with ownerUserId from auth',
      (t) async {
    await t.pumpWidget(harness());
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
}
