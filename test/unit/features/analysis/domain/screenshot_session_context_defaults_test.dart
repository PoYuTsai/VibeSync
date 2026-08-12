import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/services/screenshot_session_context_defaults.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/session_context.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';

void main() {
  final now = DateTime(2026, 8, 12);

  Partner partner({
    MeetingContext? meetingContext = MeetingContext.friendIntro,
    AcquaintanceDuration? duration = AcquaintanceDuration.fewWeeks,
    UserGoal? goal = UserGoal.maintainHeat,
    String? note = '  她不喜歡臨時約  ',
  }) {
    return Partner(
      id: 'p1',
      name: 'Alice',
      createdAt: now,
      updatedAt: now,
      defaultMeetingContext: meetingContext,
      defaultAcquaintanceDuration: duration,
      defaultGoal: goal,
      customNote: note,
    );
  }

  Conversation conversation({SessionContext? sessionContext}) {
    return Conversation(
      id: 'c1',
      name: 'Alice',
      messages: const [],
      createdAt: now,
      updatedAt: now,
      partnerId: 'p1',
      sessionContext: sessionContext,
    );
  }

  test('uses partner-card defaults when the conversation has no context', () {
    final resolved = ScreenshotSessionContextDefaults.resolve(
      conversation: conversation(),
      partner: partner(),
    );

    expect(resolved.meetingContext, MeetingContext.friendIntro);
    expect(resolved.duration, AcquaintanceDuration.fewWeeks);
    expect(resolved.goal, UserGoal.maintainHeat);
    expect(resolved.analysisContextNote, '她不喜歡臨時約');
  });

  test('conversation context wins over partner-card defaults', () {
    final resolved = ScreenshotSessionContextDefaults.resolve(
      conversation: conversation(
        sessionContext: SessionContext(
          meetingContext: MeetingContext.committedPartner,
          duration: AcquaintanceDuration.monthPlus,
          goal: UserGoal.justChat,
          analysisContextNote: '  已交往  ',
        ),
      ),
      partner: partner(),
    );

    expect(resolved.meetingContext, MeetingContext.committedPartner);
    expect(resolved.duration, AcquaintanceDuration.monthPlus);
    expect(resolved.goal, UserGoal.justChat);
    expect(resolved.analysisContextNote, '已交往');
  });

  test('legacy partner falls back to current product defaults', () {
    final resolved = ScreenshotSessionContextDefaults.resolve(
      conversation: conversation(),
      partner: partner(
        meetingContext: null,
        duration: null,
        goal: null,
        note: '   ',
      ),
    );

    expect(resolved.meetingContext, MeetingContext.datingApp);
    expect(resolved.duration, AcquaintanceDuration.justMet);
    expect(resolved.goal, UserGoal.dateInvite);
    expect(resolved.analysisContextNote, isNull);
  });
}
