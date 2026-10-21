import 'package:flutter/foundation.dart';

import '../../../user_profile/domain/entities/user_profile.dart';

/// 規格 PR-9：教練建議把使用者自己說出的處境或目標加進「關於我」。只從固定
/// 選項挑、只能「加入」，本人按【加入】才寫進手機。不進 Hive，只跟著當次那張
/// 正式建議顯示。
///
/// 伺服器的代碼清單在 `supabase/functions/coach-chat/about_me_suggestion.ts`，
/// 代碼就是這裡 enum 的名字；對照測試在
/// `test/unit/features/coach_chat/about_me_suggestion_codes_test.dart`。
@immutable
class AboutMeSuggestion {
  const AboutMeSuggestion.stuckPoint(StuckPoint this.stuckPoint)
      : practiceGoal = null;

  const AboutMeSuggestion.practiceGoal(PracticeGoal this.practiceGoal)
      : stuckPoint = null;

  final StuckPoint? stuckPoint;
  final PracticeGoal? practiceGoal;

  /// 回應頂層的 `aboutMeSuggestion`（`{field, key}`）。欄位或代碼不認得就當
  /// 沒有：伺服器以後加選項時，舊版 App 不會顯示錯的選項。
  static AboutMeSuggestion? fromWire(Object? raw) {
    if (raw is! Map) return null;
    final key = raw['key'];
    if (key is! String) return null;
    switch (raw['field']) {
      case 'stuckPoint':
        for (final value in StuckPoint.values) {
          if (value.name == key) return AboutMeSuggestion.stuckPoint(value);
        }
      case 'practiceGoal':
        for (final value in PracticeGoal.values) {
          if (value.name == key) return AboutMeSuggestion.practiceGoal(value);
        }
    }
    return null;
  }

  /// 關於我裡已經有這個選項。
  bool isIn(UserProfile? profile) {
    if (profile == null) return false;
    final stuck = stuckPoint;
    return stuck != null
        ? profile.stuckPoints.contains(stuck)
        : profile.practiceGoals.contains(practiceGoal);
  }

  /// 這一類已經選滿（卡點 2 個、練習重點 3 個），要先到關於我拿掉一個。
  bool categoryFullIn(UserProfile? profile) {
    if (profile == null) return false;
    return stuckPoint != null
        ? profile.stuckPoints.length >= UserProfile.maxStuckPoints
        : profile.practiceGoals.length >= UserProfile.maxPracticeGoals;
  }

  /// 把這個選項加進 [profile]（還沒有關於我就新建一份）；其他欄位照舊，
  /// [now] 當更新時間。這一類已經滿了會丟 [ArgumentError]（呼叫端先看
  /// [categoryFullIn]）。
  UserProfile addTo(UserProfile? profile, {required DateTime now}) {
    final stuck = stuckPoint;
    final goal = practiceGoal;
    final stuckPoints = profile?.stuckPoints ?? const <StuckPoint>[];
    final goals = profile?.practiceGoals ?? const <PracticeGoal>[];
    return UserProfile.create(
      interactionStyle: profile?.interactionStyle,
      secondaryStyle: profile?.secondaryStyle,
      practiceGoals: [
        ...goals,
        if (goal != null && !goals.contains(goal)) goal,
      ],
      topicSeeds: profile?.topicSeeds ?? const <TopicSeed>[],
      stuckPoints: [
        ...stuckPoints,
        if (stuck != null && !stuckPoints.contains(stuck)) stuck,
      ],
      customTopics: profile?.customTopics,
      notes: profile?.notes,
      updatedAt: now,
      recentNote: profile?.recentNote,
      recentNoteUpdatedAt: profile?.recentNoteUpdatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AboutMeSuggestion &&
      other.stuckPoint == stuckPoint &&
      other.practiceGoal == practiceGoal;

  @override
  int get hashCode => Object.hash(stuckPoint, practiceGoal);

  @override
  String toString() =>
      'AboutMeSuggestion(${stuckPoint?.name ?? practiceGoal?.name})';
}

/// 教練剛給的那張正式建議（[resultId]）附帶的「要不要加到關於我」。
@immutable
class CoachAboutMeSuggestionOffer {
  const CoachAboutMeSuggestionOffer({
    required this.resultId,
    required this.suggestion,
  });

  final String resultId;
  final AboutMeSuggestion suggestion;
}
