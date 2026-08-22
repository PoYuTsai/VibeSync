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
    String? note = '  工作忙碌、異地  ',
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
    expect(resolved.analysisContextNote, '工作忙碌、住不同縣市');
  });

  test('對象卡最新設定蓋過舊 conversation context（meetingContext／duration／goal）', () {
    // 閉環規則：修改對象卡認識情境後，新分析片段必須取得最新對象設定；
    // 既有非空 SessionContext 不得靜默擋住這三個欄位。
    final resolved = ScreenshotSessionContextDefaults.resolve(
      conversation: conversation(
        sessionContext: SessionContext(
          meetingContext: MeetingContext.datingApp,
          duration: AcquaintanceDuration.justMet,
          goal: UserGoal.dateInvite,
          userStyle: UserStyle.steady,
          analysisContextNote: '  已交往  ',
        ),
      ),
      partner: partner(
        meetingContext: MeetingContext.committedPartner,
        duration: AcquaintanceDuration.monthPlus,
        goal: UserGoal.justChat,
      ),
    );

    expect(resolved.meetingContext, MeetingContext.committedPartner);
    expect(resolved.duration, AcquaintanceDuration.monthPlus);
    expect(resolved.goal, UserGoal.justChat);
    // conversation 專屬欄位仍沿用既有 context。
    expect(resolved.userStyle, UserStyle.steady);
    expect(resolved.analysisContextNote, '已交往');
  });

  test('legacy partner（未設預設）時既有 conversation context 照舊生效', () {
    final resolved = ScreenshotSessionContextDefaults.resolve(
      conversation: conversation(
        sessionContext: SessionContext(
          meetingContext: MeetingContext.friendIntro,
          duration: AcquaintanceDuration.fewDays,
          goal: UserGoal.maintainHeat,
        ),
      ),
      partner: partner(meetingContext: null, duration: null, goal: null),
    );

    expect(resolved.meetingContext, MeetingContext.friendIntro);
    expect(resolved.duration, AcquaintanceDuration.fewDays);
    expect(resolved.goal, UserGoal.maintainHeat);
  });

  test('孤兒對話（無 partner）沿用既有 conversation context', () {
    final resolved = ScreenshotSessionContextDefaults.resolve(
      conversation: conversation(
        sessionContext: SessionContext(
          meetingContext: MeetingContext.inPerson,
          duration: AcquaintanceDuration.fewWeeks,
          goal: UserGoal.justChat,
        ),
      ),
      partner: null,
    );

    expect(resolved.meetingContext, MeetingContext.inPerson);
    expect(resolved.duration, AcquaintanceDuration.fewWeeks);
    expect(resolved.goal, UserGoal.justChat);
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

  test('legacy free text and relationship-state chips do not enter analysis',
      () {
    final resolved = ScreenshotSessionContextDefaults.resolve(
      conversation: conversation(),
      partner: partner(note: '想約出來見面、剛認識'),
    );

    expect(resolved.analysisContextNote, isNull);
  });
}
