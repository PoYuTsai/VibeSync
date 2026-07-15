import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/coach_chat/data/services/coach_chat_api_service.dart';
import 'package:vibesync/features/coach_chat/presentation/widgets/coach_chat_progress_notice.dart';

void main() {
  Future<void> pumpNotice(
    WidgetTester tester,
    CoachChatProgressUpdate? update,
  ) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CoachChatProgressNotice(
            update: update,
            question: '我現在該怎麼做？',
          ),
        ),
      ),
    );
  }

  testWidgets('shows truthful system progress stages without draft answer',
      (tester) async {
    const cases = <CoachChatProgressStage, String>{
      CoachChatProgressStage.request: '教練已收到問題',
      CoachChatProgressStage.generating: '教練正在整理建議',
      CoachChatProgressStage.validating: '正在檢查答案是否完整',
      CoachChatProgressStage.retrying: '答案還不夠完整，正在重新整理',
      CoachChatProgressStage.finalizing: '檢查完成，正在準備正式建議',
    };

    for (final entry in cases.entries) {
      await pumpNotice(
        tester,
        CoachChatProgressUpdate(stage: entry.key),
      );
      expect(find.byKey(const ValueKey('coach-chat-progress-title')),
          findsOneWidget);
      expect(find.text(entry.value), findsOneWidget);
      expect(find.textContaining('我現在該怎麼做？'), findsOneWidget);
      expect(find.textContaining('正式回答'), findsNothing);
    }
  });

  testWidgets('shows a local connecting label before first server stage',
      (tester) async {
    await pumpNotice(tester, null);
    expect(find.text('正在送出問題'), findsOneWidget);
  });

  testWidgets('keeps retry copy visible while the next generation is running',
      (tester) async {
    await pumpNotice(
      tester,
      const CoachChatProgressUpdate(
        stage: CoachChatProgressStage.generating,
        attempt: 2,
        maxAttempts: 3,
      ),
    );
    expect(find.text('答案還不夠完整，正在重新整理'), findsOneWidget);
  });
}
