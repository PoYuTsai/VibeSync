import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart' show Box;
import 'package:vibesync/core/theme/app_colors.dart';
import 'package:vibesync/features/practice_chat/data/providers/practice_chat_providers.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_session_repository.dart';
import 'package:vibesync/features/practice_chat/data/services/practice_chat_api_service.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_message.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_session.dart';
import 'package:vibesync/features/practice_chat/presentation/screens/practice_chat_screen.dart';

class _UnusedPracticeSessionBox extends Fake implements Box<PracticeSession> {}

class _MemoryPracticeSessionRepository extends PracticeSessionRepository {
  _MemoryPracticeSessionRepository([Iterable<PracticeSession> seed = const []])
      : super(_UnusedPracticeSessionBox()) {
    for (final session in seed) {
      _sessions[session.id] = session;
    }
  }

  final Map<String, PracticeSession> _sessions = {};

  @override
  Future<void> save(PracticeSession session) async {
    _sessions[session.id] = session;
  }

  @override
  List<PracticeSession> recentSessions() {
    final all = _sessions.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return all.take(PracticeSessionRepository.maxSessions).toList();
  }

  @override
  PracticeSession? getById(String id) => _sessions[id];

  @override
  Future<void> delete(String id) async {
    _sessions.remove(id);
  }
}

class _NoopPracticeChatApi extends PracticeChatApiService {
  @override
  Future<PracticeChatReply> sendMessage({
    required String sessionId,
    required PracticeProfileDto profile,
    required List<PracticeTurnDto> turns,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<PracticeDebrief> requestDebrief({
    required String sessionId,
    required PracticeProfileDto profile,
    required List<PracticeTurnDto> turns,
  }) {
    throw UnimplementedError();
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
    repo = _MemoryPracticeSessionRepository();
  });

  testWidgets('renders practice bubbles on the light conversation workspace',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final seed = PracticeChatState(
      sessionId: 'practice-style-test',
      createdAt: DateTime(2026, 6, 24, 15, 30),
      aiReplyCount: 1,
      personaId: 'slow_worker',
      personaLabel: '慢熱上班族',
      difficulty: 'normal',
      difficultyLabel: '一般',
      messages: const [
        PracticeMessage(role: 'user', text: '今天好無聊'),
        PracticeMessage(role: 'ai', text: '認真的嗎？我今天事情多到爆炸，超想喊假的。'),
      ],
    );
    final controller = _SeededPracticeChatController(
      seed: seed,
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

    final workspace = tester.widget<Container>(
      find.byKey(const ValueKey('practice-chat-workspace')),
    );
    final decoration = workspace.decoration! as BoxDecoration;

    expect(decoration.color, Colors.white.withValues(alpha: 0.96));
    expect(find.text('我說'), findsOneWidget);
    expect(find.text('她說'), findsOneWidget);
    expect(find.text('今天好無聊'), findsOneWidget);
    expect(find.textContaining('認真的嗎'), findsOneWidget);

    final userText = tester.widget<Text>(find.text('今天好無聊'));
    expect(userText.style?.color, AppColors.glassTextPrimary);
  });

  testWidgets('empty room explains when quota is charged', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceSessionRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    expect(
      find.textContaining('首次 AI 回覆成功才扣 1 則'),
      findsAtLeastNWidgets(1),
    );
    expect(find.textContaining('進來或送出失敗不扣'), findsOneWidget);
  });

  testWidgets('opens unfinished local session for continuation',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await repo.save(PracticeSession(
      id: 'resume-widget',
      createdAt: DateTime(2026, 6, 24, 15, 58),
      aiReplyCount: 1,
      messages: const [
        PracticeMessage(role: 'user', text: '嗨'),
        PracticeMessage(role: 'ai', text: '嗨～你今天怎麼樣？'),
      ],
    ));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceSessionRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    expect(find.text('嗨'), findsOneWidget);
    expect(find.text('嗨～你今天怎麼樣？'), findsOneWidget);
    expect(find.textContaining('本場已扣 1 則'), findsOneWidget);
  });

  testWidgets('recent sessions can be deleted from the history sheet',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await repo.save(PracticeSession(
      id: 'delete-me',
      createdAt: DateTime(2026, 6, 24, 15, 58),
      aiReplyCount: 1,
      messages: const [PracticeMessage(role: 'user', text: '嗨')],
      debriefSummary: '已拆解',
    ));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceSessionRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-practice-delete-me')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('刪除'));
    await tester.pumpAndSettle();

    expect(repo.getById('delete-me'), isNull);
    expect(find.text('還沒有練習紀錄'), findsOneWidget);
  });

  testWidgets(
      'new room shows persona and difficulty controls before first message',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceSessionRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    expect(find.textContaining('本場對象：'), findsOneWidget);
    expect(find.text('換一位'), findsOneWidget);
    expect(find.text('輕鬆'), findsOneWidget);
    expect(find.text('一般'), findsOneWidget);
    expect(find.text('挑戰'), findsOneWidget);
    expect(find.text('隨機'), findsOneWidget);
  });

  testWidgets('started room hides persona changer and keeps profile visible',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await repo.save(PracticeSession(
      id: 'started',
      createdAt: DateTime(2026, 6, 24, 18),
      aiReplyCount: 1,
      personaId: 'cool_rational',
      personaLabel: '高冷理性型',
      difficulty: 'challenge',
      difficultyLabel: '挑戰',
      messages: const [
        PracticeMessage(role: 'user', text: '嗨'),
        PracticeMessage(role: 'ai', text: '嗯？'),
      ],
    ));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceSessionRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    expect(find.textContaining('高冷理性型 · 挑戰'), findsOneWidget);
    expect(find.text('換一位'), findsNothing);
    expect(find.text('輕鬆'), findsNothing);
  });
}
