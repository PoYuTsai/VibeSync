import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart' show Box;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/core/services/app_haptics.dart';
import 'package:vibesync/core/theme/app_colors.dart';
import 'package:vibesync/core/theme/app_icons.dart';
import 'package:vibesync/features/practice_chat/data/providers/practice_chat_providers.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_session_repository.dart';
import 'package:vibesync/features/practice_chat/data/services/practice_chat_api_service.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_catalog.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_message.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_session.dart';
import 'package:vibesync/features/practice_chat/presentation/screens/practice_chat_screen.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';
import 'package:vibesync/shared/widgets/brand/brand_kit.dart';

class _UnusedPracticeSessionBox extends Fake implements Box<PracticeSession> {}

class _MemoryPracticeSessionRepository extends PracticeSessionRepository {
  _MemoryPracticeSessionRepository() : super(_UnusedPracticeSessionBox());

  final Map<String, PracticeSession> _sessions = {};

  @override
  Future<void> save(PracticeSession session) async {
    _sessions[session.id] = session;
  }

  @override
  List<PracticeSession> recentSessions() => const [];

  @override
  PracticeSession? getById(String id) => _sessions[id];

  @override
  Future<void> delete(String id) async {
    _sessions.remove(id);
  }

  @override
  Future<void> deleteVisibleThread(String threadKey) async {}
}

class _NoopPracticeChatApi extends PracticeChatApiService {}

class _SeededSubscriptionNotifier extends SubscriptionNotifier {
  _SeededSubscriptionNotifier(SubscriptionState seed) {
    state = seed;
  }
}

class _SeededPracticeChatController extends PracticeChatController {
  _SeededPracticeChatController({
    required PracticeChatState seed,
    required super.repository,
  }) : super(
          api: _NoopPracticeChatApi(),
          sessionId: seed.sessionId,
          createdAt: seed.createdAt,
        ) {
    state = seed;
  }
}

const startCtaKey = ValueKey('practice-start-chat-cta');

void main() {
  late PracticeSessionRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppHaptics.enabled = true;
    repo = _MemoryPracticeSessionRepository();
  });

  PracticeChatState preChatSeed() {
    final girl = practiceGirlProfiles.first;
    return PracticeChatState(
      sessionId: 'composer-pre-chat',
      createdAt: DateTime(2026, 7, 6, 10),
      girl: girl,
      personaId: girl.personaId,
      personaLabel: '慢熱上班族',
      difficulty: 'normal',
      difficultyLabel: '一般',
      messages: const [],
    );
  }

  PracticeChatState inChatSeed() {
    return preChatSeed().copyWith(
      aiReplyCount: 1,
      messages: const [
        PracticeMessage(role: 'user', text: '嗨'),
        PracticeMessage(role: 'ai', text: '嗨，怎麼了？'),
      ],
    );
  }

  Future<void> pumpScreen(WidgetTester tester, PracticeChatState seed) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _SeededPracticeChatController(
      seed: seed,
      repository: repo,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
          subscriptionProvider.overrideWith(
            (ref) => _SeededSubscriptionNotifier(
              const SubscriptionState(
                tier: SubscriptionTierHelper.starter,
                monthlyLimit: 100,
                dailyLimit: 30,
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );
  }

  /// 首屏只有 CTA；要碰輸入框的測試都得先按下它進對話框。
  Future<void> startChat(WidgetTester tester) async {
    await tester.tap(find.byKey(startCtaKey));
    // 一幀掛上輸入框（focus node reparent 時補領焦點），再推過 AppHaptics.strong()
    // 第二下重震的計時器，否則測試結束時會留 pending Timer。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
  }

  testWidgets('首屏沒有輸入框，只有「開始和她聊」CTA', (tester) async {
    await pumpScreen(tester, preChatSeed());

    expect(find.byKey(startCtaKey), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(const ValueKey('practice-profile-hero')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('practice-chat-origin-intro')),
      findsNothing,
    );
  });

  testWidgets('CTA 沿用生成開場白的橘底黑字造型，句尾走 Tabler icon 不用 emoji',
      (tester) async {
    await pumpScreen(tester, preChatSeed());

    final cta = tester.widget<BrandPrimaryButton>(find.byKey(startCtaKey));
    expect(cta.label, '開始和她聊');
    // 🤓 換成 Tabler icon（2026-08-17 Eric 拍板），而且留在文案「後面」。
    expect(cta.trailingIcon, TablerIcons.mood_nerd);
    expect(cta.icon, isNull);

    // 橘底：跟「生成開場白」同一顆 BrandPrimaryButton 的 ctaStart→ctaEnd 漸層。
    final decoration = tester
        .widget<AnimatedContainer>(
          find.descendant(
            of: find.byKey(startCtaKey),
            matching: find.byType(AnimatedContainer),
          ),
        )
        .decoration! as BoxDecoration;
    expect(decoration.gradient, isA<LinearGradient>());
    expect(
      (decoration.gradient! as LinearGradient).colors,
      [AppColors.ctaStart, AppColors.ctaEnd],
    );
    // 黑字（品牌墨色）。
    final style = tester
        .widget<ElevatedButton>(
          find.descendant(
            of: find.byKey(startCtaKey),
            matching: find.byType(ElevatedButton),
          ),
        )
        .style!;
    expect(
      style.foregroundColor!.resolve(const <WidgetState>{}),
      AppColors.onCta,
    );
  });

  testWidgets('點 CTA 直接進對話框：資料卡收起、掛上認識場合、輸入框自動聚焦',
      (tester) async {
    await pumpScreen(tester, preChatSeed());
    await startChat(tester);

    expect(find.byKey(startCtaKey), findsNothing);
    expect(find.byKey(const ValueKey('practice-profile-hero')), findsNothing);
    expect(
      find.byKey(const ValueKey('practice-chat-origin-intro')),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
      true,
    );
  });

  testWidgets('點 CTA 給強烈觸覺回饋（heavyImpact）', (tester) async {
    final vibrates = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        // Material 的 Feedback.forTap 也會打這條（arguments 是 null），
        // 直接 cast 會炸；只收得出強度的那幾發。
        final type = call.arguments as String?;
        if (type != null) vibrates.add(type);
      }
      return null;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await pumpScreen(tester, preChatSeed());
    await startChat(tester);

    // 按下瞬間的 mediumImpact 之外，必須再吃到 AppHaptics.strong() 的重震×2。
    expect(
      vibrates.where((v) => v == 'HapticFeedbackType.heavyImpact').length,
      2,
    );
  });

  testWidgets('送出第一則之後，認識場合說明就從對話框消失', (tester) async {
    await pumpScreen(tester, inChatSeed());

    expect(
      find.byKey(const ValueKey('practice-chat-origin-intro')),
      findsNothing,
    );
  });

  testWidgets('進對話框後聚焦輸入框 → 出現收起鍵盤，點它即退出輸入狀態',
      (tester) async {
    await pumpScreen(tester, preChatSeed());
    await startChat(tester);

    expect(
      find.byKey(const ValueKey('practice-dismiss-keyboard')),
      findsOneWidget,
    );
    // 資料入口一律在 header 的 compact identity 列，輸入列不重複。
    expect(
      find.byKey(const ValueKey('practice-view-profile-action')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('practice-dismiss-keyboard')));
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
      false,
    );
    expect(
      find.byKey(const ValueKey('practice-dismiss-keyboard')),
      findsNothing,
    );
  });

  testWidgets('開聊後聚焦只顯示收起鍵盤（資料入口已在 header）', (tester) async {
    await pumpScreen(tester, inChatSeed());

    await tester.tap(find.byType(TextField));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('practice-dismiss-keyboard')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('practice-view-profile-action')),
      findsNothing,
    );
  });

  testWidgets('送出鈕：空字串灰階不可送，打字後亮橘', (tester) async {
    await pumpScreen(tester, preChatSeed());
    await startChat(tester);

    Container sendContainer() => tester.widget<Container>(
          find.descendant(
            of: find.byKey(const ValueKey('practice-send-button')),
            matching: find.byType(Container),
          ),
        );

    expect((sendContainer().decoration! as BoxDecoration).gradient, isNull);

    await tester.enterText(find.byType(TextField), '嗨嗨');
    await tester.pump();

    expect((sendContainer().decoration! as BoxDecoration).gradient, isNotNull);
  });

  testWidgets('hint 文案：開場前是開場白引導', (tester) async {
    await pumpScreen(tester, preChatSeed());
    await startChat(tester);
    expect(
      tester.widget<TextField>(find.byType(TextField)).decoration?.hintText,
      '傳出你的第一句開場白…',
    );
  });

  testWidgets('hint 文案：開聊後恢復輸入訊息', (tester) async {
    await pumpScreen(tester, inChatSeed());
    expect(
      tester.widget<TextField>(find.byType(TextField)).decoration?.hintText,
      '輸入訊息…',
    );
  });

  testWidgets('Return 鍵是換行不是送出——自己打字也能連發短訊（Eric 2026-08-12）',
      (tester) async {
    await pumpScreen(tester, inChatSeed());

    final field = tester.widget<TextField>(find.byType(TextField));
    // 綁成 send 的話 return 鍵會直接送出，使用者永遠打不出換行，
    // 而 _send 的分則鐵律預期輸入框裡就是可以有換行的。
    expect(field.textInputAction, TextInputAction.newline);
    expect(field.onSubmitted, isNull);
    // 換行要留得住才拆得出多顆泡：maxLines 必須 > 1。
    expect(field.maxLines, greaterThan(1));

    // 打得進多行，而且不會在輸入階段就被吃掉。
    await tester.enterText(find.byType(TextField), '剛下班\n腦袋還沒關機');
    await tester.pump();
    expect(find.text('剛下班\n腦袋還沒關機'), findsOneWidget);
  });

  testWidgets('聚焦態輸入框描邊上品牌橘', (tester) async {
    await pumpScreen(tester, preChatSeed());
    await startChat(tester);

    final decoration =
        tester.widget<TextField>(find.byType(TextField)).decoration!;
    final focused = decoration.focusedBorder! as OutlineInputBorder;
    expect(focused.borderSide.color, AppColors.ctaStart);
  });
}
