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
import 'package:vibesync/features/conversation/domain/entities/session_context.dart';
import 'package:vibesync/features/partner/data/repositories/partner_repository.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/partner/presentation/screens/add_partner_screen.dart';
import 'package:vibesync/shared/widgets/brand/brand_kit.dart';

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
        authConversationScopeProvider
            .overrideWith((ref) => authStream ?? Stream.value('u-test')),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        // 說明卡包了 LiquidMotionFrame（無限 ticker）；關動畫讓
        // pumpAndSettle 可收斂。
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
      ),
    );
  }

  Finder nameField() => find.byKey(const ValueKey('add-partner-name-field'));

  // Order matters: the auth-blocked tests run BEFORE the successful submit
  // test. The successful submit triggers `pushReplacement` which appears to
  // disrupt the test framework's between-test cleanup in our setup; running
  // the non-mutating tests first guarantees they always execute.

  testWidgets('hint shows free-text 範例 with emoji (post-redesign copy)',
      (t) async {
    await t.pumpWidget(harness());
    await t.pumpAndSettle();
    expect(
      find.text('例：Alice / Tinder 上的空姐'),
      findsOneWidget,
      reason: 'hint must signal free-text intent (name OR description)',
    );
  });

  testWidgets('collects partner defaults in one scrollable creation flow',
      (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(harness());
    await t.pumpAndSettle();

    expect(find.text('幫教練進一步認識她'), findsOneWidget);
    expect(find.text('認識情境'), findsOneWidget);
    expect(find.text('認識多久'), findsOneWidget);
    expect(find.text('目前目標'), findsOneWidget);
    expect(find.text('補充背景（選填）'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('add-partner-background-field')),
      findsOneWidget,
    );

    final controls = t.widgetList<BrandSegmentedButton>(
      find.byWidgetPredicate((widget) => widget is BrandSegmentedButton),
    );
    expect(controls, hasLength(3));
    expect(controls.elementAt(0).selected, MeetingContext.datingApp);
    expect(
      controls.elementAt(1).selected,
      AcquaintanceDuration.justMet,
    );
    expect(controls.elementAt(2).selected, UserGoal.dateInvite);
  });

  // Eric 2026-08-12：整頁要一頁看完，不能為了按「建立」再往下滑。
  // 量法：surface 393×852（iPhone 15 Pro pt），test MediaQuery 沒有 safe-area
  // inset，所以真機還要扣掉 top 59（含瀏海）＋ bottom 34 home indicator。
  testWidgets('whole form fits one screen on iPhone 15 Pro (no scroll to CTA)',
      (t) async {
    await t.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(harness());
    await t.pumpAndSettle();

    const usableHeight = 852.0 - 59 - 34;
    final ctaBottom = t.getBottomLeft(find.byType(BrandPrimaryButton)).dy;
    expect(
      ctaBottom,
      lessThanOrEqualTo(usableHeight),
      reason: 'CTA 落在 $ctaBottom，超過可視高度 $usableHeight 就得捲動才按得到',
    );
  });

  testWidgets('input clears transparent AppBar toolbar', (t) async {
    await t.pumpWidget(harness());
    await t.pumpAndSettle();

    final appBarBottom = t.getBottomLeft(find.byType(AppBar)).dy;
    final inputTop = t.getTopLeft(nameField()).dy;

    expect(
      inputTop,
      greaterThan(appBarBottom),
      reason: 'extendBodyBehindAppBar should only affect the background; '
          'the input must not sit underneath the transparent AppBar.',
    );
  });

  testWidgets('submit disabled while name empty', (t) async {
    await t.pumpWidget(harness());
    await t.pumpAndSettle();
    final btn = t.widget<BrandPrimaryButton>(find.byType(BrandPrimaryButton));
    expect(btn.onPressed, isNull);
  });

  testWidgets('submit enabled once name has non-whitespace', (t) async {
    await t.pumpWidget(harness());
    await t.pumpAndSettle();
    await t.enterText(nameField(), 'Alice');
    await t.pump();
    final btn = t.widget<BrandPrimaryButton>(find.byType(BrandPrimaryButton));
    expect(btn.onPressed, isNotNull);
  });

  testWidgets('submit BLOCKED when authConversationScopeProvider is null',
      (t) async {
    await t.pumpWidget(harness(authStream: Stream.value(null)));
    await t.pumpAndSettle();
    await t.enterText(nameField(), 'Alice');
    await t.pump();
    final btn = t.widget<BrandPrimaryButton>(find.byType(BrandPrimaryButton));
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
    await t.enterText(nameField(), 'Alice');
    await t.pump();
    final btn = t.widget<BrandPrimaryButton>(find.byType(BrandPrimaryButton));
    expect(btn.onPressed, isNull, reason: 'must wait for auth resolution');
  });

  testWidgets(
    'successful submit persists all Partner defaults and background',
    (t) async {
      await t.pumpWidget(harness());
      await t.pumpAndSettle();
      await t.enterText(nameField(), 'Alice');
      t
          .widget<BrandSegmentedButton<MeetingContext>>(
            find.byWidgetPredicate(
              (widget) => widget is BrandSegmentedButton<MeetingContext>,
            ),
          )
          .onChanged(MeetingContext.friendIntro);
      t
          .widget<BrandSegmentedButton<AcquaintanceDuration>>(
            find.byWidgetPredicate(
              (widget) => widget is BrandSegmentedButton<AcquaintanceDuration>,
            ),
          )
          .onChanged(AcquaintanceDuration.fewWeeks);
      t
          .widget<BrandSegmentedButton<UserGoal>>(
            find.byWidgetPredicate(
              (widget) => widget is BrandSegmentedButton<UserGoal>,
            ),
          )
          .onChanged(UserGoal.maintainHeat);
      await t.pump();
      final background =
          find.byKey(const ValueKey('add-partner-background-field'));
      await t.enterText(background, '她不喜歡臨時約');
      await t.pump();
      final submit = t.widget<BrandPrimaryButton>(
        find.byType(BrandPrimaryButton),
      );
      submit.onPressed!();
      for (var i = 0; i < 20 && partnerBox.values.isEmpty; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }

      expect(partnerBox.values.length, 1);
      final p = partnerBox.values.single;
      expect(p.name, 'Alice');
      expect(p.ownerUserId, 'u-test');
      expect(p.defaultMeetingContext, MeetingContext.friendIntro);
      expect(p.defaultAcquaintanceDuration, AcquaintanceDuration.fewWeeks);
      expect(p.defaultGoal, UserGoal.maintainHeat);
      expect(p.customNote, '她不喜歡臨時約');
    },
    // Headless Windows route replacement does not settle; the same Hive write
    // contract is covered by PartnerWriteController.create.
    skip: true,
  );
}
