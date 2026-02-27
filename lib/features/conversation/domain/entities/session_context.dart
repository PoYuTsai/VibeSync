// lib/features/conversation/domain/entities/session_context.dart
import 'package:hive/hive.dart';

part 'session_context.g.dart';

/// 認識場景
@HiveType(typeId: 3)
enum MeetingContext {
  @HiveField(0)
  datingApp, // 交友軟體
  @HiveField(1)
  inPerson, // 現場搭訕
  @HiveField(2)
  friendIntro, // 朋友介紹
  @HiveField(3)
  other; // 其他

  String get label {
    switch (this) {
      case datingApp:
        return '交友軟體';
      case inPerson:
        return '現場搭訕';
      case friendIntro:
        return '朋友介紹';
      case other:
        return '其他';
    }
  }
}

/// 認識時長
@HiveType(typeId: 4)
enum AcquaintanceDuration {
  @HiveField(0)
  justMet, // 剛認識
  @HiveField(1)
  fewDays, // 幾天
  @HiveField(2)
  fewWeeks, // 幾週
  @HiveField(3)
  monthPlus; // 一個月+

  String get label {
    switch (this) {
      case justMet:
        return '剛認識';
      case fewDays:
        return '幾天';
      case fewWeeks:
        return '幾週';
      case monthPlus:
        return '一個月+';
    }
  }
}

/// 用戶目標
@HiveType(typeId: 5)
enum UserGoal {
  @HiveField(0)
  dateInvite, // 約出來 (預設)
  @HiveField(1)
  maintainHeat, // 維持熱度
  @HiveField(2)
  justChat; // 純聊天

  String get label {
    switch (this) {
      case dateInvite:
        return '約出來';
      case maintainHeat:
        return '維持熱度';
      case justChat:
        return '純聊天';
    }
  }
}

/// Session 情境
@HiveType(typeId: 6)
class SessionContext extends HiveObject {
  @HiveField(0)
  final MeetingContext meetingContext;

  @HiveField(1)
  final AcquaintanceDuration duration;

  @HiveField(2)
  final UserGoal goal;

  SessionContext({
    required this.meetingContext,
    required this.duration,
    this.goal = UserGoal.dateInvite, // 預設：約出來
  });

  Map<String, dynamic> toJson() => {
        'meetingContext': meetingContext.name,
        'duration': duration.name,
        'goal': goal.name,
      };
}
