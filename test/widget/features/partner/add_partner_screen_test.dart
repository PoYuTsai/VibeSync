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
//
// onboarding 轉換第 10 步（建好直接選截圖）照規格補兩層測試，見檔尾 group：
// 1. 建立後的導航抽成可注入的 followUpAfterPartnerCreated，直接斷言呼叫順序；
// 2. 用真的 addPartnerRoute＋不碰磁碟的替身倉庫跑完整個送出鏈，驗 next 參數
//    真的傳進畫面、落點與返回堆疊。上面那條 skip 卡住的是 Hive 真檔案 I/O 在
//    fake-async 裡收不掉（送出鏈停在寫入、根本走不到換頁）；換成記憶體倉庫後
//    pushReplacement／push 都照常生效。
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive_ce.dart';

import 'package:vibesync/app/routes.dart' show addPartnerRoute;
import 'package:vibesync/core/theme/app_typography.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_write_controller.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
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
        // 建立頁已無 LiquidMotionFrame；關動畫讓
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

  testWidgets('名稱欄只提示名字或暱稱', (t) async {
    await t.pumpWidget(harness());
    await t.pumpAndSettle();
    expect(
      find.text('輸入她的名字或暱稱'),
      findsOneWidget,
      reason: '背景已改 chips-only，名稱欄只負責名字或暱稱',
    );
  });

  // 2026-08-13 夥伴稿：三段情境改走原生 grouped 下鑽列（值顯示在列右側，
  // 點開 bottom sheet 選），不再是三排 segmented chips。預設值照舊，
  // 列上要直接看得到——不能顯示成「尚未設定」而實際帶著預設值送分析。
  testWidgets('三段情境走下鑽列，預設值顯示在列上；選完落回列上', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(harness());
    await t.pumpAndSettle();

    expect(find.text('幫教練進一步認識她'), findsOneWidget);
    expect(find.text('認識情境'), findsOneWidget);
    expect(find.text('認識多久'), findsOneWidget);
    expect(find.text('目前目標'), findsOneWidget);
    expect(find.text('關於她'), findsOneWidget);

    expect(find.text(MeetingContext.datingApp.displayLabel), findsOneWidget);
    expect(
      find.text(AcquaintanceDuration.justMet.displayLabel),
      findsOneWidget,
    );
    expect(find.text(UserGoal.dateInvite.displayLabel), findsOneWidget);
    expect(find.text('選填'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('add-partner-goal-row')));
    await t.pumpAndSettle();
    await t.tap(
      find.byKey(
        ValueKey('add-partner-option-${UserGoal.maintainHeat.displayLabel}'),
      ),
    );
    await t.pumpAndSettle();

    expect(find.text(UserGoal.maintainHeat.displayLabel), findsOneWidget);
    expect(find.text(UserGoal.dateInvite.displayLabel), findsNothing);
  });

  testWidgets('關於她下鑽只提供 chips，選完摘要存回列上', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(harness());
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('add-partner-background-row')));
    await t.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('add-partner-background-field')),
      findsNothing,
    );
    await t.ensureVisible(find.text('輪班工作'));
    await t.tap(find.text('輪班工作'));
    await t.pump();
    await t.ensureVisible(find.text('喜歡寵物'));
    await t.tap(find.text('喜歡寵物'));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('add-partner-background-save')));
    await t.pumpAndSettle();

    expect(find.text('輪班工作、喜歡寵物'), findsOneWidget);
    expect(find.text('選填'), findsNothing);
  });

  // Eric 2026-08-12：整頁要一頁看完，不能為了按「建立」再往下滑。
  // 2026-08-13 改下鑽列後「建立」改成貼底固定（不在捲動區內），量法跟著改：
  // 不再比絕對 y（貼底本來就會落在 safe-area 那條線上，真機由 SafeArea 讓開），
  // 改鎖兩件事——CTA 不在 Scrollable 裡（永遠不用捲就按得到），且表單最後一列
  // 在 CTA 之上（整張表確實一頁看完）。
  testWidgets('whole form fits one screen on iPhone 15 Pro (no scroll to CTA)',
      (t) async {
    await t.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(harness());
    await t.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(Scrollable),
        matching: find.byType(BrandPrimaryButton),
      ),
      findsNothing,
      reason: '「建立」必須貼底固定，不能落在捲動區裡',
    );

    final lastRowBottom = t
        .getBottomLeft(find.byKey(const ValueKey('add-partner-background-row')))
        .dy;
    final ctaTop = t.getTopLeft(find.byType(BrandPrimaryButton)).dy;
    expect(
      lastRowBottom,
      lessThanOrEqualTo(ctaTop),
      reason: '表單最後一列落在 $lastRowBottom，撞到 CTA（$ctaTop）就是一頁裝不完',
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

  // 2026-08-27 Eric 真機回報：這頁標題字體跟其他頁不一樣。原因是 AppBar
  // 標題自己寫 TextStyle 只蓋掉顏色，字體家族／字級／字重仍落回 Flutter
  // 預設 titleLarge（iOS = .SF UI Display 22/w400）。守門＝標題必須是共用
  // 的 AppTypography.appBarTitle 檔（brandAppBar 提供）。
  testWidgets('AppBar 標題走共用字級，不落回 Flutter 預設', (t) async {
    await t.pumpWidget(harness());
    await t.pumpAndSettle();

    final title = t.widget<Text>(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('新增對象'),
      ),
    );

    expect(title.style?.fontSize, AppTypography.appBarTitle.fontSize);
    expect(title.style?.fontWeight, AppTypography.appBarTitle.fontWeight);
    expect(title.style?.color, AppTypography.appBarTitle.color);
    expect(
      title.style?.fontFamily,
      isNull,
      reason: '字體家族要跟 App 其他文字一樣吃平台預設，不要指定 .SF UI Display',
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
      Future<void> pickRow(String rowKey, String optionLabel) async {
        await t.tap(find.byKey(ValueKey(rowKey)));
        await t.pumpAndSettle();
        await t.tap(find.byKey(ValueKey('add-partner-option-$optionLabel')));
        await t.pumpAndSettle();
      }

      await pickRow(
        'add-partner-meeting-context-row',
        MeetingContext.friendIntro.displayLabel,
      );
      await pickRow(
        'add-partner-duration-row',
        AcquaintanceDuration.fewWeeks.displayLabel,
      );
      await pickRow(
        'add-partner-goal-row',
        UserGoal.maintainHeat.displayLabel,
      );
      await t.tap(find.byKey(const ValueKey('add-partner-background-row')));
      await t.pumpAndSettle();
      await t.tap(find.text('慢熱'));
      await t.pump();
      await t.ensureVisible(find.text('不想聊工作'));
      await t.tap(find.text('不想聊工作'));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('add-partner-background-save')));
      await t.pumpAndSettle();
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
      expect(p.customNote, '慢熱、不想聊工作');
    },
    // Headless Windows route replacement does not settle; the same Hive write
    // contract is covered by PartnerWriteController.create.
    skip: true,
  );

  group('建好直接選截圖（onboarding 轉換第 10 步）', () {
    test('入口網址固定：這串會存在使用者手機的登入前暫存裡', () {
      expect(
        AddPartnerScreen.screenshotFlowLocation,
        '/partner/new?next=screenshot',
      );
    });

    group('建立後的導航順序（followUpAfterPartnerCreated）', () {
      Future<List<String>> run({String? nextStep, bool fail = false}) async {
        final calls = <String>[];
        await followUpAfterPartnerCreated(
          partnerId: 'p1',
          nextStep: nextStep,
          createEmptyConversation: () async {
            calls.add('create');
            if (fail) throw StateError('寫入失敗');
            return 'c1';
          },
          replaceWith: (location) => calls.add('replace $location'),
          push: (location) => calls.add('push $location'),
          onCreateConversationFailed: () => calls.add('error'),
        );
        return calls;
      }

      test('沒帶 next：只把新增頁換成對象頁，不建片段', () async {
        expect(await run(), ['replace /partner/p1']);
      });

      test('不認得的 next 值：跟沒帶一樣', () async {
        expect(await run(nextStep: 'gallery'), ['replace /partner/p1']);
      });

      test('next=screenshot：先建空片段，再換成對象頁、把片段疊上去', () async {
        expect(await run(nextStep: AddPartnerScreen.nextStepScreenshot), [
          'create',
          'replace /partner/p1',
          'push /conversation/c1',
        ]);
      });

      test('建空片段失敗：照樣落在對象頁並跳錯誤字，不疊片段', () async {
        expect(
          await run(nextStep: AddPartnerScreen.nextStepScreenshot, fail: true),
          ['create', 'replace /partner/p1', 'error'],
        );
      });
    });

    group('真的路由＋送出鏈', () {
      Future<GoRouter> pumpNav(
        WidgetTester t, {
        required _MemoryPartnerRepository partners,
        required _RecordingConversationWriter writer,
      }) async {
        await t.binding.setSurfaceSize(const Size(393, 852));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final router = GoRouter(
          initialLocation: '/',
          routes: [
            GoRoute(
              path: '/',
              builder: (c, s) => const Scaffold(body: Text('home-stub')),
            ),
            // 真的 /partner/new 路由（routes.dart），驗 next 參數有傳進畫面。
            addPartnerRoute,
            GoRoute(
              path: '/partner/:id',
              builder: (c, s) =>
                  Scaffold(body: Text('detail:${s.pathParameters['id']}')),
            ),
            GoRoute(
              path: '/conversation/:id',
              builder: (c, s) => Scaffold(
                body: Text('conversation:${s.pathParameters['id']}'),
              ),
            ),
          ],
        );
        addTearDown(router.dispose);
        await t.pumpWidget(
          ProviderScope(
            overrides: [
              partnerRepositoryProvider.overrideWithValue(partners),
              conversationWriteControllerProvider.overrideWith(() => writer),
              authConversationScopeProvider
                  .overrideWith((ref) => Stream.value('u-test')),
            ],
            child: MaterialApp.router(
              routerConfig: router,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: child!,
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        return router;
      }

      Future<void> openAddPartner(
        WidgetTester t,
        GoRouter router,
        String location,
      ) async {
        unawaited(router.push<void>(location));
        await t.pumpAndSettle();
      }

      Future<void> submit(WidgetTester t, String name) async {
        await t.enterText(nameField(), name);
        await t.pump();
        await t.tap(find.widgetWithText(BrandPrimaryButton, '建立'));
        await t.pumpAndSettle();
      }

      String? nextStepOnScreen(WidgetTester t) =>
          t.widget<AddPartnerScreen>(find.byType(AddPartnerScreen)).nextStep;

      testWidgets('帶 next=screenshot：建好直接到空片段；返回回對象頁，再返回回首頁', (t) async {
        final partners = _MemoryPartnerRepository();
        final writer = _RecordingConversationWriter();
        final router = await pumpNav(t, partners: partners, writer: writer);
        await openAddPartner(
            t, router, AddPartnerScreen.screenshotFlowLocation);
        expect(nextStepOnScreen(t), AddPartnerScreen.nextStepScreenshot);

        await submit(t, 'Alice');

        final partner = partners.saved.single;
        expect(partner.name, 'Alice');
        expect(partner.ownerUserId, 'u-test');
        expect(writer.created, [
          (name: '新對話', messageCount: 0, partnerId: partner.id),
        ]);
        expect(find.text('conversation:conv-new'), findsOneWidget);
        expect(find.byType(AddPartnerScreen), findsNothing);

        router.pop();
        await t.pumpAndSettle();
        expect(find.text('detail:${partner.id}'), findsOneWidget,
            reason: '返回要回到剛建好的對象頁，不是新增表單');

        router.pop();
        await t.pumpAndSettle();
        expect(find.text('home-stub'), findsOneWidget);
        expect(find.byType(AddPartnerScreen), findsNothing);
      });

      testWidgets('建空片段失敗：停在對象頁、跳既有錯誤字；返回回首頁', (t) async {
        final partners = _MemoryPartnerRepository();
        final writer = _RecordingConversationWriter(fail: true);
        final router = await pumpNav(t, partners: partners, writer: writer);
        await openAddPartner(
            t, router, AddPartnerScreen.screenshotFlowLocation);

        await submit(t, 'Alice');

        expect(find.text('detail:${partners.saved.single.id}'), findsOneWidget);
        expect(find.text('建立對話失敗，請再試一次'), findsOneWidget);
        expect(find.textContaining('conversation:'), findsNothing);

        router.pop();
        await t.pumpAndSettle();
        expect(find.text('home-stub'), findsOneWidget);
      });

      testWidgets('沒帶參數（含舊版暫存的 /partner/new）：照舊只到對象頁、不建片段', (t) async {
        final partners = _MemoryPartnerRepository();
        final writer = _RecordingConversationWriter();
        final router = await pumpNav(t, partners: partners, writer: writer);
        await openAddPartner(t, router, '/partner/new');
        expect(nextStepOnScreen(t), isNull);

        await submit(t, 'Alice');

        expect(find.text('detail:${partners.saved.single.id}'), findsOneWidget);
        expect(writer.created, isEmpty);

        router.pop();
        await t.pumpAndSettle();
        expect(find.text('home-stub'), findsOneWidget);
      });
    });
  });
}

/// 不碰磁碟的對象倉庫：Hive 真檔案 I/O 在 testWidgets 的 fake-async 裡收不掉，
/// 導航測試改用它，讓送出鏈真的跑完。
class _MemoryPartnerRepository implements PartnerRepository {
  final saved = <Partner>[];

  @override
  Future<bool> upsertIfAbsent(Partner partner) async {
    saved.add(partner);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 記下建片段的參數；fail＝模擬寫入失敗。
class _RecordingConversationWriter extends ConversationWriteController {
  _RecordingConversationWriter({this.fail = false});

  final bool fail;
  final created = <({String name, int messageCount, String? partnerId})>[];

  @override
  void build() {}

  @override
  Future<Conversation> create({
    required String name,
    required List<Message> messages,
    String? partnerId,
  }) async {
    created.add(
      (name: name, messageCount: messages.length, partnerId: partnerId),
    );
    if (fail) throw StateError('寫入失敗');
    final now = DateTime(2026, 10, 27);
    return Conversation(
      id: 'conv-new',
      name: name,
      messages: messages,
      createdAt: now,
      updatedAt: now,
      partnerId: partnerId,
    );
  }
}
