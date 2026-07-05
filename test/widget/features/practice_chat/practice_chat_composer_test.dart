import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart' show Box;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/core/theme/app_colors.dart';
import 'package:vibesync/features/practice_chat/data/providers/practice_chat_providers.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_session_repository.dart';
import 'package:vibesync/features/practice_chat/data/services/practice_chat_api_service.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_catalog.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_message.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_session.dart';
import 'package:vibesync/features/practice_chat/presentation/screens/practice_chat_screen.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';

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

void main() {
  late PracticeSessionRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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

  testWidgets('開場前聚焦輸入框 → 出現收起鍵盤與看她的資料，點收起鍵盤即退出輸入狀態',
      (tester) async {
    await pumpScreen(tester, preChatSeed());

    // 未聚焦：不顯示鍵盤操作列。
    expect(
      find.byKey(const ValueKey('practice-dismiss-keyboard')),
      findsNothing,
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('practice-dismiss-keyboard')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('practice-view-profile-action')),
      findsOneWidget,
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

  testWidgets('拖動開場資訊卡會收鍵盤', (tester) async {
    await pumpScreen(tester, preChatSeed());

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('practice-dismiss-keyboard')),
      findsOneWidget,
    );

    await tester.drag(
      find.byKey(const ValueKey('practice-profile-hero')),
      const Offset(0, -60),
    );
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
      false,
    );
  });

  testWidgets('送出鈕：空字串灰階不可送，打字後亮橘', (tester) async {
    await pumpScreen(tester, preChatSeed());

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

  testWidgets('聚焦態輸入框描邊上品牌橘', (tester) async {
    await pumpScreen(tester, preChatSeed());

    final decoration =
        tester.widget<TextField>(find.byType(TextField)).decoration!;
    final focused = decoration.focusedBorder! as OutlineInputBorder;
    expect(focused.borderSide.color, AppColors.ctaStart);
  });
}
