// 批 A Task 4 — 全域教練頁 TDD spec。
//
// GlobalCoachScreen＝AppBar「問教練」＋引導問句 chips＋CoachSurface
// （global scope）。chip 點擊只「預填」進輸入框（prefill＋focus token），
// 絕不自動送出（quota 安全）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/coach_chat/data/providers/coach_chat_providers.dart';
import 'package:vibesync/features/coach_chat/data/services/coach_chat_api_service.dart';
import 'package:vibesync/features/coach_chat/domain/entities/coach_scope.dart';
import 'package:vibesync/features/coach_chat/presentation/screens/global_coach_screen.dart';
import 'package:vibesync/features/coach_chat/presentation/widgets/coach_surface.dart';
import 'package:vibesync/features/coaching_memory/data/providers/coaching_outcome_providers.dart';

import '../../helpers/memory_coach_chat_repository.dart';
import '../../helpers/memory_coaching_outcome_repository.dart';

/// 引導問句直接引實作常數（review Grok Minor-3：防測試與文案漂移）。
const _guideQuestions = GlobalCoachScreen.guideQuestions;

CoachChatInvoker _recordingInvoker(List<Map<String, dynamic>> calls) {
  return (String _, {required Map<String, dynamic> body}) async {
    calls.add(body);
    return const CoachChatInvokeResponse(
      status: 429,
      data: <String, dynamic>{'error': 'Daily limit exceeded'},
    );
  };
}

Future<List<Map<String, dynamic>>> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(430, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final apiCalls = <Map<String, dynamic>>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coachChatRepositoryProvider
            .overrideWithValue(MemoryCoachChatRepository()),
        coachChatApiServiceProvider.overrideWithValue(
          CoachChatApiService(invoker: _recordingInvoker(apiCalls)),
        ),
        coachingOutcomeRepositoryProvider
            .overrideWithValue(MemoryCoachingOutcomeRepository()),
      ],
      child: const MaterialApp(home: GlobalCoachScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return apiCalls;
}

void main() {
  testWidgets('AppBar 標題「問教練」＋CoachSurface 掛 global scope', (tester) async {
    await _pump(tester);

    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('問教練'),
      ),
      findsOneWidget,
    );
    final surface = tester.widget<CoachSurface>(find.byType(CoachSurface));
    expect(surface.scope, const CoachScope.global());
  });

  testWidgets('空狀態顯示三句引導問句 chips', (tester) async {
    await _pump(tester);

    for (final question in _guideQuestions) {
      expect(find.text(question), findsOneWidget);
    }
  });

  testWidgets('點引導 chip 只預填輸入框，絕不自動送出', (tester) async {
    final apiCalls = await _pump(tester);

    await tester.tap(find.text(_guideQuestions[0]));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byType(CoachSurface),
        matching: find.byType(TextField),
      ),
    );
    expect(field.controller?.text, _guideQuestions[0]);
    expect(apiCalls, isEmpty);
  });
}
