import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';

part 'user_profile.g.dart';

/// 互動風格 — single select. Independent from legacy
/// `SessionContext.UserStyle` (typeId=7) on purpose: §13 forbids silent
/// migration from per-conversation data, and labels here drop the `型` suffix.
@HiveType(typeId: 10)
enum InteractionStyle {
  @HiveField(0) steady,
  @HiveField(1) direct,
  @HiveField(2) humorous,
  @HiveField(3) gentle,
  @HiveField(4) playful,
}

/// 練習目標 — multi select, max 3.
@HiveType(typeId: 11)
enum PracticeGoal {
  @HiveField(0) softInvite,
  @HiveField(1) comfortableChat,
  @HiveField(2) humorousReply,
  @HiveField(3) buildCloseness,
  @HiveField(4) findCompatiblePartner,
}

/// 常聊話題 — multi select, max 5.
@HiveType(typeId: 12)
enum TopicSeed {
  @HiveField(0) fitness,
  @HiveField(1) travel,
  @HiveField(2) coffee,
  @HiveField(3) music,
  @HiveField(4) movies,
  @HiveField(5) photography,
  @HiveField(6) food,
  @HiveField(7) pets,
  @HiveField(8) reading,
  @HiveField(9) workLife,
}

/// 我現在卡在哪 — multi select, max 2（2026-08 關於我重新定位案 批2 新增）。
/// anxiousWontSend／overExplains 承接舊 PracticeGoal.reduceAnxiety／
/// explainLess 的語意（那兩個 PracticeGoal 成員已重新定義成別的概念，
/// 見批3 前置的 PracticeGoal 改造）。
@HiveType(typeId: 27)
enum StuckPoint {
  @HiveField(0) fadesOut, // 聊一聊就冷掉，不知道怎麼接下去
  @HiveField(1) dontKnowHowToAsk, // 不知道怎麼開口約
  @HiveField(2) anxiousWontSend, // 會緊張、怕講錯話不敢傳
  @HiveField(3) overExplains, // 話太多、一直在解釋自己
  @HiveField(4) leftOnRead, // 一直被已讀不回
}

@immutable
@HiveType(typeId: 9)
class UserProfile {
  static const int maxPracticeGoals = 3;
  static const int maxTopicSeeds = 5;
  static const int maxCustomTopicsLength = 60;
  static const int maxNotesLength = 100;
  static const int maxStuckPoints = 2;

  /// 規格 PR-8「最近的狀況」：一兩句就好。
  static const int maxRecentNoteLength = 60;

  /// 寫下超過這麼多天就不再提供給教練（D5 照預設 14 天）。
  static const int recentNoteFreshDays = 14;

  @HiveField(0)
  final InteractionStyle? interactionStyle;
  @HiveField(1)
  final List<PracticeGoal> practiceGoals;
  @HiveField(2)
  final List<TopicSeed> topicSeeds;
  @HiveField(3)
  final String? customTopics;
  @HiveField(4)
  final String? notes;
  @HiveField(5)
  final DateTime updatedAt;

  /// 副風格（style pair 2026-06-10）。[interactionStyle] 原地不動＝主風格。
  /// Old rows read back as null — zero migration.
  @HiveField(6)
  final InteractionStyle? secondaryStyle;

  @HiveField(7)
  final List<StuckPoint> stuckPoints;

  /// 規格 PR-8「最近的狀況」原文。舊資料讀回來是 null，不做 migration；舊版
  /// App 讀到這兩格會略過（adapter 先把欄位讀進 map 再按編號取值）。
  @HiveField(8)
  final String? recentNote;

  /// [recentNote] 最後一次寫下或確認「還是這樣」的時間。
  @HiveField(9)
  final DateTime? recentNoteUpdatedAt;

  /// Public raw constructor — used by Hive codegen and trusted call sites.
  /// Callers from UI / controller MUST use [UserProfile.create] instead so
  /// trimming + bounds are enforced. Permissive on purpose so generated
  /// adapters can rebuild rows without re-running validation that might
  /// reject data which legitimately existed before a future bound was
  /// tightened.
  const UserProfile({
    this.interactionStyle,
    this.secondaryStyle,
    this.practiceGoals = const [],
    this.topicSeeds = const [],
    this.stuckPoints = const [],
    this.customTopics,
    this.notes,
    required this.updatedAt,
    this.recentNote,
    this.recentNoteUpdatedAt,
  });

  /// Validates + normalizes inputs. Always use this from controllers,
  /// repository write-path, or any UI surface that builds a profile from
  /// user input. Throws [ArgumentError] on bound violation.
  factory UserProfile.create({
    InteractionStyle? interactionStyle,
    InteractionStyle? secondaryStyle,
    List<PracticeGoal> practiceGoals = const [],
    List<TopicSeed> topicSeeds = const [],
    List<StuckPoint> stuckPoints = const [],
    String? customTopics,
    String? notes,
    required DateTime updatedAt,
    String? recentNote,
    DateTime? recentNoteUpdatedAt,
  }) {
    if (secondaryStyle != null && interactionStyle == null) {
      throw ArgumentError('secondaryStyle requires interactionStyle (主)');
    }
    if (secondaryStyle != null && secondaryStyle == interactionStyle) {
      throw ArgumentError('secondaryStyle must differ from interactionStyle');
    }
    if (practiceGoals.length > maxPracticeGoals) {
      throw ArgumentError('practiceGoals exceeds max $maxPracticeGoals');
    }
    if (topicSeeds.length > maxTopicSeeds) {
      throw ArgumentError('topicSeeds exceeds max $maxTopicSeeds');
    }
    if (stuckPoints.length > maxStuckPoints) {
      throw ArgumentError('stuckPoints exceeds max $maxStuckPoints');
    }
    final ct = customTopics?.trim();
    if (ct != null && ct.length > maxCustomTopicsLength) {
      throw ArgumentError('customTopics exceeds $maxCustomTopicsLength chars');
    }
    final n = notes?.trim();
    if (n != null && n.length > maxNotesLength) {
      throw ArgumentError('notes exceeds $maxNotesLength chars');
    }
    final rn = recentNote?.trim();
    final hasRecentNote = rn != null && rn.isNotEmpty;
    if (hasRecentNote && rn.length > maxRecentNoteLength) {
      throw ArgumentError('recentNote exceeds $maxRecentNoteLength chars');
    }
    if (hasRecentNote && recentNoteUpdatedAt == null) {
      throw ArgumentError('recentNote requires recentNoteUpdatedAt');
    }
    return UserProfile(
      interactionStyle: interactionStyle,
      secondaryStyle: secondaryStyle,
      practiceGoals: List.unmodifiable(practiceGoals),
      topicSeeds: List.unmodifiable(topicSeeds),
      stuckPoints: List.unmodifiable(stuckPoints),
      customTopics: (ct == null || ct.isEmpty) ? null : ct,
      notes: (n == null || n.isEmpty) ? null : n,
      updatedAt: updatedAt,
      recentNote: hasRecentNote ? rn : null,
      recentNoteUpdatedAt: hasRecentNote ? recentNoteUpdatedAt : null,
    );
  }

  bool get isEmpty =>
      interactionStyle == null &&
      secondaryStyle == null &&
      practiceGoals.isEmpty &&
      topicSeeds.isEmpty &&
      stuckPoints.isEmpty &&
      customTopics == null &&
      notes == null &&
      recentNote == null;

  /// [recentNote] 寫下（或確認）到 [now] 經過幾個整天；沒有近況回 null。
  int? recentNoteAgeDays(DateTime now) {
    final at = recentNoteUpdatedAt;
    if (recentNote == null || at == null) return null;
    return now.difference(at).inDays;
  }

  /// 近況還在 [recentNoteFreshDays] 天內，才提供給教練。
  bool recentNoteIsFresh(DateTime now) {
    final age = recentNoteAgeDays(now);
    return age != null && age <= recentNoteFreshDays;
  }
}
