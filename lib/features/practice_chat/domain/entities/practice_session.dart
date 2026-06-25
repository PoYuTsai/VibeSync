import 'package:hive_ce/hive_ce.dart';

import 'practice_message.dart';

part 'practice_session.g.dart';

/// 一場 AI 實戰練習。最近 5 場 local-only 加密保存。
@HiveType(typeId: 23)
class PracticeSession {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final DateTime createdAt;

  @HiveField(2)
  final List<PracticeMessage> messages;

  /// 本場已收到的 AI 回覆數（上限 20）。
  @HiveField(3)
  final int aiReplyCount;

  // ── 教練拆解卡（練完才有；同場不另扣額度）──
  @HiveField(4)
  final String? debriefSummary;

  @HiveField(5)
  final List<String> debriefStrengths;

  @HiveField(6)
  final List<String> debriefWatchouts;

  @HiveField(7)
  final String? debriefSuggestedLine;

  @HiveField(8)
  final String? debriefVibe;

  // ── 本場角色＋難度（Batch 2 起新增；舊場為 null → 兜底 slow_worker + normal）──
  @HiveField(9)
  final String? personaId;

  @HiveField(10)
  final String? personaLabel;

  @HiveField(11)
  final String? difficulty;

  @HiveField(12)
  final String? difficultyLabel;

  // ── 續玩同一位（Batch 4 起新增）──
  /// 跨輪穩定的「同一位對象」識別。舊場為 null → 消費端兜底用 [id] 當 thread。
  @HiveField(13)
  final String? visiblePracticeThreadId;

  /// 同一位的第幾輪（1 起算，上限 3）。舊場為 null → 消費端兜底 1。
  /// 必須可空：舊 adapter 無 field 14，反序列化得 null，`as int` 會 crash。
  @HiveField(14)
  final int? roundIndex;

  /// 本場對象在 60 位 catalog 的 profileId（practice_girl_NNN）。display/persona
  /// 等其餘欄位由 client catalog 依此 id 解析，故只持久化這一個 id。舊場為 null
  /// → 消費端兜底成預設對象。
  @HiveField(15)
  final String? profileId;

  const PracticeSession({
    required this.id,
    required this.createdAt,
    this.messages = const [],
    this.aiReplyCount = 0,
    this.debriefSummary,
    this.debriefStrengths = const [],
    this.debriefWatchouts = const [],
    this.debriefSuggestedLine,
    this.debriefVibe,
    this.personaId,
    this.personaLabel,
    this.difficulty,
    this.difficultyLabel,
    this.visiblePracticeThreadId,
    this.roundIndex,
    this.profileId,
  });

  bool get hasDebrief => debriefSummary != null;

  PracticeSession copyWith({
    List<PracticeMessage>? messages,
    int? aiReplyCount,
    String? debriefSummary,
    List<String>? debriefStrengths,
    List<String>? debriefWatchouts,
    String? debriefSuggestedLine,
    String? debriefVibe,
    String? personaId,
    String? personaLabel,
    String? difficulty,
    String? difficultyLabel,
    String? visiblePracticeThreadId,
    int? roundIndex,
    String? profileId,
  }) {
    return PracticeSession(
      id: id,
      createdAt: createdAt,
      messages: messages ?? this.messages,
      aiReplyCount: aiReplyCount ?? this.aiReplyCount,
      debriefSummary: debriefSummary ?? this.debriefSummary,
      debriefStrengths: debriefStrengths ?? this.debriefStrengths,
      debriefWatchouts: debriefWatchouts ?? this.debriefWatchouts,
      debriefSuggestedLine: debriefSuggestedLine ?? this.debriefSuggestedLine,
      debriefVibe: debriefVibe ?? this.debriefVibe,
      personaId: personaId ?? this.personaId,
      personaLabel: personaLabel ?? this.personaLabel,
      difficulty: difficulty ?? this.difficulty,
      difficultyLabel: difficultyLabel ?? this.difficultyLabel,
      visiblePracticeThreadId:
          visiblePracticeThreadId ?? this.visiblePracticeThreadId,
      roundIndex: roundIndex ?? this.roundIndex,
      profileId: profileId ?? this.profileId,
    );
  }
}
