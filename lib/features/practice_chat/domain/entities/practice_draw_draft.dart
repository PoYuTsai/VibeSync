import 'practice_profile.dart';

/// 「翻牌成功但尚未送出第一則」的本地草稿。離開練習室再回來時，用它把同一位對象
/// 還原成 revealed（不重抽、不再扣翻牌次數）。
///
/// 刻意**不**寫進 `PracticeSession` 最近列表：草稿不是一段已開始的對話，否則會在歷史
/// 造出 0 回覆的幽靈場次。送出第一則成功後即清掉草稿，由正式 session 接手持久化。
///
/// [nextResetAt] 是該次翻牌所屬視窗的下一次重置點（Asia/Taipei 中午）；過了它代表草稿
/// 屬於上一個視窗 → 消費端視為過期忽略（今天可重新免費翻一張）。
class PracticeDrawDraft {
  final String sessionId;
  final String visiblePracticeThreadId;
  final int roundIndex;

  final String profileId;
  final String personaId;
  final String difficulty;
  final PracticeDifficultyPreference difficultyPreference;

  final int freeAllowance;
  final int freeUsed;
  final int freeRemaining;
  final int extraCostMessages;

  final DateTime nextResetAt;
  final DateTime createdAt;

  const PracticeDrawDraft({
    required this.sessionId,
    required this.visiblePracticeThreadId,
    required this.roundIndex,
    required this.profileId,
    required this.personaId,
    required this.difficulty,
    required this.difficultyPreference,
    required this.freeAllowance,
    required this.freeUsed,
    required this.freeRemaining,
    required this.extraCostMessages,
    required this.nextResetAt,
    required this.createdAt,
  });

  PracticeDrawDraft copyWith({
    String? difficulty,
    PracticeDifficultyPreference? difficultyPreference,
  }) {
    return PracticeDrawDraft(
      sessionId: sessionId,
      visiblePracticeThreadId: visiblePracticeThreadId,
      roundIndex: roundIndex,
      profileId: profileId,
      personaId: personaId,
      difficulty: difficulty ?? this.difficulty,
      difficultyPreference: difficultyPreference ?? this.difficultyPreference,
      freeAllowance: freeAllowance,
      freeUsed: freeUsed,
      freeRemaining: freeRemaining,
      extraCostMessages: extraCostMessages,
      nextResetAt: nextResetAt,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'visiblePracticeThreadId': visiblePracticeThreadId,
        'roundIndex': roundIndex,
        'profileId': profileId,
        'personaId': personaId,
        'difficulty': difficulty,
        'difficultyPreference': difficultyPreference.name,
        'freeAllowance': freeAllowance,
        'freeUsed': freeUsed,
        'freeRemaining': freeRemaining,
        'extraCostMessages': extraCostMessages,
        'nextResetAt': nextResetAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory PracticeDrawDraft.fromJson(Map<String, dynamic> json) {
    return PracticeDrawDraft(
      sessionId: json['sessionId'] as String,
      visiblePracticeThreadId: json['visiblePracticeThreadId'] as String,
      roundIndex: (json['roundIndex'] as num?)?.toInt() ?? 1,
      profileId: json['profileId'] as String,
      personaId: json['personaId'] as String,
      difficulty: json['difficulty'] as String,
      difficultyPreference:
          _preferenceFromName(json['difficultyPreference'] as String?),
      freeAllowance: (json['freeAllowance'] as num?)?.toInt() ?? 0,
      freeUsed: (json['freeUsed'] as num?)?.toInt() ?? 0,
      freeRemaining: (json['freeRemaining'] as num?)?.toInt() ?? 0,
      extraCostMessages: (json['extraCostMessages'] as num?)?.toInt() ?? 0,
      nextResetAt: DateTime.parse(json['nextResetAt'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  static PracticeDifficultyPreference _preferenceFromName(String? name) {
    for (final p in PracticeDifficultyPreference.values) {
      if (p.name == name) return p;
    }
    return PracticeDifficultyPreference.normal;
  }
}
