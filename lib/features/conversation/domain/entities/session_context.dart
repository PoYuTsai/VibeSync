// lib/features/conversation/domain/entities/session_context.dart
import 'package:hive_ce/hive_ce.dart';

part 'session_context.g.dart';

/// 用戶說話風格
@HiveType(typeId: 7)
enum UserStyle {
  @HiveField(0)
  humorous, // 幽默型
  @HiveField(1)
  steady, // 穩重型
  @HiveField(2)
  direct, // 直球型
  @HiveField(3)
  gentle, // 溫柔型
  @HiveField(4)
  playful; // 調皮型

  String get label {
    switch (this) {
      case humorous:
        return '幽默型';
      case steady:
        return '穩重型';
      case direct:
        return '直球型';
      case gentle:
        return '溫柔型';
      case playful:
        return '調皮型';
    }
  }
}

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

  @HiveField(3)
  final UserStyle? userStyle;

  @HiveField(4)
  final String? userInterests;

  @HiveField(5)
  final String? targetDescription;

  SessionContext({
    required this.meetingContext,
    required this.duration,
    this.goal = UserGoal.dateInvite, // 預設：約出來
    this.userStyle,
    this.userInterests,
    this.targetDescription,
  });

  Map<String, dynamic> toJson() => {
        'meetingContext': meetingContext.label,
        'duration': duration.label,
        'goal': goal.label,
        'userStyle': userStyle?.label,
        'userInterests': userInterests,
        'targetDescription': targetDescription,
      };
}
