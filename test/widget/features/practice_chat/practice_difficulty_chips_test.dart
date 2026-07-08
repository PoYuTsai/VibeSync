import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart' show Box;
import 'package:vibesync/features/practice_chat/data/providers/practice_chat_providers.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_session_repository.dart';
import 'package:vibesync/features/practice_chat/data/services/practice_chat_api_service.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_catalog.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_hint.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_learning_mode.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_profile.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_session.dart';
import 'package:vibesync/features/practice_chat/presentation/screens/practice_chat_screen.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';

/// 沿用 practice_chat_screen_style_test.dart 的既有 harness 慣例：
/// seeded-notifier idiom（constructor 同步初始化後直接覆寫 state）＋
/// in-memory repository（無 Supabase user 時後續 async 初始化全 no-op）。
class _SeededSubscriptionNotifier extends SubscriptionNotifier {
  _SeededSubscriptionNotifier(SubscriptionState seed) {
    state = seed;
  }
}

class _UnusedPracticeSessionBox extends Fake implements Box<PracticeSession> {}

class _MemoryPracticeSessionRepository extends PracticeSessionRepository {
  _MemoryPracticeSessionRepository() : super(_UnusedPracticeSessionBox());

  @override
  Future<void> save(PracticeSession session) async {}

  @override
  List<PracticeSession> recentSessions() => const [];
}

class _NoopPracticeChatApi extends PracticeChatApiService {
  @override
  Future<PracticeChatReply> sendMessage({
    required String sessionId,
    required PracticeProfileDto profile,
    required List<PracticeTurnDto> turns,
    int roundIndex = 1,
    String? visiblePracticeThreadId,
    PracticeLearningMode practiceMode = PracticeLearningMode.standard,
    int? temperatureScore,
    int? familiarityScore,
    String? memorySummary,
    PracticePartnerState? continuationPartnerState,
    PracticeHintReplyType? appliedHintType,
    String? appliedHintText,
  }) =>
      throw UnimplementedError();

  @override
  Future<PracticeDebrief> requestDebrief({
    required String sessionId,
    required PracticeProfileDto profile,
    required List<PracticeTurnDto> turns,
    PracticeLearningMode practiceMode = PracticeLearningMode.standard,
    int roundIndex = 1,
    String? visiblePracticeThreadId,
    String? memorySummary,
    PracticePartnerState? continuationPartnerState,
  }) =>
      throw UnimplementedError();
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
    repo = _MemoryPracticeSessionRepository();
  });

  PracticeChatState revealedPreMsgSeed() {
    final girl = practiceGirlProfiles.first;
    return PracticeChatState(
      sessionId: 'difficulty-subtitle-test',
      createdAt: DateTime(2026, 6, 26, 13),
      girl: girl,
      personaId: girl.personaId,
      personaLabel: '慢熱上班族',
      difficulty: 'normal',
      difficultyLabel: '一般',
      messages: const [],
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    PracticeChatController controller,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
    await tester.pumpAndSettle();
  }

  testWidgets('選中一般難度 chip → 顯示對應副標文案', (tester) async {
    final controller = _SeededPracticeChatController(
      seed: revealedPreMsgSeed(),
      repository: repo,
    );
    await pumpScreen(tester, controller);

    expect(find.text('真實交友軟體體感，會已讀、會變短'), findsOneWidget);
  });

  testWidgets('點選挑戰 chip → 副標切換成挑戰文案', (tester) async {
    final controller = _SeededPracticeChatController(
      seed: revealedPreMsgSeed(),
      repository: repo,
    );
    await pumpScreen(tester, controller);

    await tester.tap(find.text('挑戰'));
    await tester.pumpAndSettle();

    expect(controller.currentState.difficultyPreference,
        PracticeDifficultyPreference.challenge);
    expect(find.text('高標準對象，不救場、會句點你'), findsOneWidget);
    expect(find.text('真實交友軟體體感，會已讀、會變短'), findsNothing);
  });
}
