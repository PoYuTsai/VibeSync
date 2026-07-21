// 作戰板 nextStep 節點 → Coach 1:1 預填（決策 1/2/3，2026-06-10 拍板）。
// 覆蓋 AnalysisScreen.coachPrefillQuestion 參數 → 捲動到 CoachSurface →
// 輸入框預填的整條鏈，以及「絕不 auto-send」quota 安全硬規則。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/coaching_memory/data/providers/coaching_outcome_providers.dart';
import '../../../helpers/memory_coaching_outcome_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/features/analysis/data/notifiers/streaming_analyze_notifier.dart';
import 'package:vibesync/features/analysis/presentation/screens/analysis_screen.dart';
import 'package:vibesync/features/coach_chat/data/providers/coach_chat_providers.dart';
import 'package:vibesync/features/coach_chat/domain/entities/coach_chat_result.dart';
import 'package:vibesync/features/coach_chat/domain/entities/unified_coach_result.dart';
import 'package:vibesync/features/coach_chat/domain/repositories/coach_chat_repository.dart';
import 'package:vibesync/features/coach_chat/presentation/widgets/coach_surface.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_repository.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

const _conversationId = 'prefill-test';
const _prefillQuestion = '如何約她週末喝咖啡';

/// idle 起步的 notifier：本測試只走 `_restorePersistedAnalysis()` 還原路徑，
/// 不需要任何 streaming 階段。
class _IdleStreamingAnalyzeNotifier extends StreamingAnalyzeNotifier {
  @override
  StreamingAnalysisState build(String conversationId) =>
      const StreamingAnalysisState(phase: StreamingAnalyzePhase.idle);
}

/// 取代 Hive box 版 repository；另記錄 put 次數佐證「絕不 auto-send」
/// （auto-send 成功與否都會經過 controller → put / api，put 必須為 0）。
class _StubCoachChatRepository implements CoachChatRepository {
  int putCalls = 0;

  @override
  List<CoachChatResult> listByConversation(String conversationId) => const [];

  @override
  CoachChatResult? latestForConversation(String conversationId) => null;

  @override
  Future<void> put(CoachChatResult result) async {
    putCalls++;
  }

  @override
  Future<ConversationDeleteOutcome> deleteConversation(
    String conversationId,
  ) async =>
      const ConversationDeleteOutcome(
        deleted: true,
        deletedOwnerUserId: 'stub-owner',
      );

  @override
  Future<void> clearAll() async {}

  @override
  List<UnifiedCoachResult> listByScope(String scopeType, String scopeId) =>
      const [];

  @override
  UnifiedCoachResult? latestForScope(String scopeType, String scopeId) => null;

  @override
  Future<void> putUnified(UnifiedCoachResult result) async {}

  @override
  Future<void> deleteScope(String scopeType, String scopeId) async {}
}

class _StubConversationRepository extends ConversationRepository {
  _StubConversationRepository(this._conversation);

  final Conversation _conversation;

  @override
  Conversation? getConversation(String id) =>
      id == _conversation.id ? _conversation : null;

  @override
  Future<void> updateConversation(Conversation c) async {}
}

/// 含 recommendation 的完整快照——CoachSurface 渲染條件
/// （enthusiasm + gameStage + recommendation 齊備）。
String _analyzedSnapshotJson() => jsonEncode({
      'enthusiasm': {'score': 66},
      'strategy': '穩住節奏',
      'gameStage': {
        'current': 'premise',
        'status': 'normal',
        'nextStep': '約她週末喝咖啡',
      },
      'topicDepth': {'current': 'personal', 'suggestion': ''},
      'replies': {
        'extend': 'a',
        'resonate': 'b',
        'tease': 'c',
        'humor': 'd',
        'coldRead': 'e',
      },
      'recommendation': {
        'pick': 'resonate',
        'content': 'b',
        'reason': 'r',
        'psychology': 'p',
      },
    });

Conversation _conversation({String? snapshotJson}) => Conversation(
      id: _conversationId,
      name: '小雲',
      messages: [
        Message(
          id: 'm1',
          content: '今天加班好累喔',
          isFromMe: false,
          timestamp: DateTime(2026, 6, 1, 12),
        ),
      ],
      createdAt: DateTime(2026, 6, 1, 12),
      updatedAt: DateTime(2026, 6, 1, 12),
      lastAnalysisSnapshotJson: snapshotJson,
      lastAnalyzedMessageCount: snapshotJson == null ? null : 1,
    );

Future<_StubCoachChatRepository> _pumpScreen(
  WidgetTester tester, {
  required Conversation conversation,
  String? coachPrefillQuestion,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final coachRepo = _StubCoachChatRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coachingOutcomeRepositoryProvider
            .overrideWithValue(MemoryCoachingOutcomeRepository()),
        conversationRepositoryProvider
            .overrideWithValue(_StubConversationRepository(conversation)),
        conversationProvider(_conversationId).overrideWithValue(conversation),
        coachChatRepositoryProvider.overrideWithValue(coachRepo),
        streamingAnalyzeProvider
            .overrideWith(_IdleStreamingAnalyzeNotifier.new),
      ],
      child: MaterialApp(
        home: AnalysisScreen(
          conversationId: _conversationId,
          coachPrefillQuestion: coachPrefillQuestion,
        ),
      ),
    ),
  );
  // 背景 bokeh 是無限循環動畫，pumpAndSettle 會超時——改用有界 pump：
  // 首幀 → post-frame 預填觸發 → ensureVisible 280ms 捲動 → 收尾幀。
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
  return coachRepo;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AnalysisScreen coachPrefillQuestion（作戰板 → Coach 1:1 預填）', () {
    testWidgets('預填問題出現在 Coach 輸入框，且絕不 auto-send', (tester) async {
      final coachRepo = await _pumpScreen(
        tester,
        conversation: _conversation(snapshotJson: _analyzedSnapshotJson()),
        coachPrefillQuestion: _prefillQuestion,
      );

      // 輸入框已預填（auto-send 會 clear controller，文字留著即未送出）。
      expect(
        find.descendant(
          of: find.byType(CoachSurface),
          matching: find.widgetWithText(TextField, _prefillQuestion),
        ),
        findsOneWidget,
      );
      // 沒有任何送出痕跡：無 thinking notice、repository 零寫入。
      expect(find.textContaining('你剛剛問'), findsNothing);
      expect(coachRepo.putCalls, 0);
    });

    testWidgets('未帶 coachPrefillQuestion → 輸入框維持空白（既有行為不變）', (tester) async {
      await _pumpScreen(
        tester,
        conversation: _conversation(snapshotJson: _analyzedSnapshotJson()),
      );

      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byType(CoachSurface),
          matching: find.byType(TextField),
        ),
      );
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('帶了 prefill 但對話沒有分析快照（卡片不渲染）→ 安靜 no-op 不 crash',
        (tester) async {
      await _pumpScreen(
        tester,
        conversation: _conversation(snapshotJson: null),
        coachPrefillQuestion: _prefillQuestion,
      );

      expect(find.byType(CoachSurface), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
