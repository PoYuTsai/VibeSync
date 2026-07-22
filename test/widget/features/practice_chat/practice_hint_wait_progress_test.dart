import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart' show Box;
import 'package:vibesync/features/practice_chat/data/providers/practice_chat_providers.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_session_repository.dart';
import 'package:vibesync/features/practice_chat/data/services/practice_chat_api_service.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_catalog.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_learning_mode.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_message.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_session.dart';
import 'package:vibesync/features/practice_chat/presentation/screens/practice_chat_screen.dart';

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

/// 本檔測試只驗載入面板文案切換，絕不會真的打 API。
class _NoopPracticeChatApi extends PracticeChatApiService {}

/// 同其他 widget test 的 seeded-notifier idiom：constructor 同步覆寫 state，
/// [emit] 讓測試模擬 controller 狀態變化（例如 hint 載入結束）。
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

  void emit(PracticeChatState next) => state = next;
}

void main() {
  late _MemoryPracticeSessionRepository repo;

  setUp(() {
    repo = _MemoryPracticeSessionRepository();
  });

  PracticeChatState hintLoadingSeed() {
    final girl = practiceGirlProfiles.first;
    return PracticeChatState(
      sessionId: 'hint-wait-progress-test',
      createdAt: DateTime(2026, 7, 22, 12),
      girl: girl,
      personaId: girl.personaId,
      personaLabel: '慢熱上班族',
      difficulty: 'normal',
      difficultyLabel: '一般',
      aiReplyCount: 1,
      learningMode: PracticeLearningMode.beginner,
      isHintLoading: true,
      messages: const [
        PracticeMessage(role: 'user', text: '嗨'),
        PracticeMessage(role: 'ai', text: '嗯？'),
      ],
    );
  }

  Future<_SeededPracticeChatController> pumpHintLoading(
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _SeededPracticeChatController(
      seed: hintLoadingSeed(),
      repository: repo,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );
    return controller;
  }

  testWidgets('提示等待依時間切換三段文案並顯示經過秒數；載入結束 timer 收斂', (tester) async {
    final controller = await pumpHintLoading(tester);
    final progressRow = find.byKey(const ValueKey('practice-hint-wait-progress'));

    // 0-8s：第一段文案＋經過秒數。
    expect(progressRow, findsOneWidget);
    expect(find.textContaining('教練正在讀你們最後幾句'), findsOneWidget);
    expect(find.textContaining('0 秒'), findsOneWidget);

    // 7s：仍是第一段。
    await tester.pump(const Duration(seconds: 7));
    expect(find.textContaining('教練正在讀你們最後幾句'), findsOneWidget);
    expect(find.textContaining('7 秒'), findsOneWidget);

    // 8s：切第二段。
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('正在想兩種回法'), findsOneWidget);
    expect(find.textContaining('教練正在讀你們最後幾句'), findsNothing);
    expect(find.textContaining('8 秒'), findsOneWidget);

    // 20s：切第三段（單發管線；reviewer 已拆，文案不得再稱雙重複核）。
    await tester.pump(const Duration(seconds: 12));
    expect(find.textContaining('快好了，正在做最後檢查'), findsOneWidget);
    expect(find.textContaining('正在想兩種回法'), findsNothing);
    expect(find.textContaining('20 秒'), findsOneWidget);

    // 載入結束：進度列消失、timer 必須取消 → pumpAndSettle 必收斂。
    controller.emit(
      controller.currentState.copyWith(isHintLoading: false),
    );
    await tester.pumpAndSettle();
    expect(progressRow, findsNothing);
    expect(find.textContaining('快好了，正在做最後檢查'), findsNothing);
  });

  testWidgets('等待中重新載入 → 秒數與文案從第一段重新起算', (tester) async {
    final controller = await pumpHintLoading(tester);

    await tester.pump(const Duration(seconds: 30));
    expect(find.textContaining('快好了，正在做最後檢查'), findsOneWidget);

    // 結束再重新載入（例如失敗後再點一次）→ 從 0 秒第一段重來。
    controller.emit(controller.currentState.copyWith(isHintLoading: false));
    await tester.pumpAndSettle();
    controller.emit(controller.currentState.copyWith(isHintLoading: true));
    await tester.pump();

    expect(find.textContaining('教練正在讀你們最後幾句'), findsOneWidget);
    expect(find.textContaining('0 秒'), findsOneWidget);

    // 收尾：結束載入，timer 不得殘留。
    controller.emit(controller.currentState.copyWith(isHintLoading: false));
    await tester.pumpAndSettle();
  });

  testWidgets('widget dispose 必須取消等待 timer（不留 pending timer）', (tester) async {
    await pumpHintLoading(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(find.textContaining('教練正在讀你們最後幾句'), findsOneWidget);

    // 載入仍進行中就整頁卸載：dispose 必須 cancel timer，
    // 否則 testWidgets 會以 pending timer 失敗。
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
  });
}
