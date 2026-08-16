// 乾淨版（2026-08-16 Bruce 回饋三輪）：問教練畫面進場不顯示歷史卡，
// 只顯示本次 session 問出去的結果；教練記憶（repo）完全不動。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/features/coach_chat/data/providers/coach_chat_providers.dart';
import 'package:vibesync/features/coach_chat/domain/entities/coach_scope.dart';
import 'package:vibesync/features/coach_chat/domain/entities/unified_coach_result.dart';
import 'package:vibesync/features/coach_chat/presentation/widgets/coach_surface.dart';
import 'package:vibesync/features/coaching_memory/data/providers/coaching_outcome_providers.dart';

import '../../../helpers/memory_coach_chat_repository.dart';
import '../../../helpers/memory_coaching_outcome_repository.dart';

UnifiedCoachResult _storedFormal() => UnifiedCoachResult(
      id: 'stored-1',
      conversationId: null,
      partnerId: null,
      question: '上次的問題',
      mode: 'replyCraft',
      headline: '上次的建議標題',
      answer: '上次的完整回答',
      userState: '上次的狀態',
      nextStep: '上次的下一步',
      suggestedLine: '上次的建議句',
      boundaryReminder: '上次的邊界提醒',
      needsReflection: false,
      generatedAt: DateTime.utc(2026, 8, 16, 6),
      provider: 'claude',
      modelUsed: 'claude-sonnet-5',
      scopeType: 'global',
      scopeId: 'me',
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('進場不顯示歷史結果；記憶仍留在 repo 供下一問續接', (tester) async {
    final repo = MemoryCoachChatRepository()..seedUnified(_storedFormal());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coachChatRepositoryProvider.overrideWithValue(repo),
          coachingOutcomeRepositoryProvider
              .overrideWithValue(MemoryCoachingOutcomeRepository()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: CoachSurface(scope: CoachScope.global()),
          ),
        ),
      ),
    );
    await tester.pump();

    // 歷史卡與「前面 N 輪」摺疊區都不出現，畫面只剩輸入引導。
    expect(find.text('上次的建議標題'), findsNothing);
    expect(find.text('上次的建議句'), findsNothing);
    expect(find.textContaining('前面'), findsNothing);
    expect(find.text('例如：她這句話是真的有興趣嗎？'), findsOneWidget);

    // 教練記憶照舊：controller 下一問仍會從 repo 續接這筆。
    expect(repo.latestForScope('global', 'me')?.id, 'stored-1');
  });
}
