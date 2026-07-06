import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';

part 'analysis_history_event.g.dart';

/// 案2：本機分析事件歷史（analyze 熱度 / practice 溫度共用一張表）。
/// 本機 only，絕不上傳。append-only，repository 寫入時超過 500 筆刪最舊。
@HiveType(typeId: 25)
enum AnalysisHistoryKind {
  @HiveField(0)
  analyze,
  @HiveField(1)
  practice,
}

@immutable
@HiveType(typeId: 24)
class AnalysisHistoryEvent {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final AnalysisHistoryKind kind;

  /// 事件時間（報告頁 x 軸真日期來源）。
  @HiveField(2)
  final DateTime createdAt;

  /// analyze 用（hook 現場只有 conversationId，沒有 partnerId）。
  @HiveField(3)
  final String? conversationId;

  /// 對象名快照（選擇器顯示用，防改名/刪除後查不到）。
  @HiveField(4)
  final String? subjectName;

  @HiveField(5)
  final int? enthusiasmScore;

  @HiveField(6)
  final String? gameStageLabel;

  /// practice 用（practice_girl_NNN）。
  @HiveField(7)
  final String? profileId;

  /// practice 輪次 1–3。
  @HiveField(8)
  final int? roundIndex;

  @HiveField(9)
  final int? temperatureScore;

  @HiveField(10)
  final int? familiarityScore;

  @HiveField(11)
  final String? relationshipStageLabel;

  /// Hive rebuild 用寬鬆建構子；寫入路徑一律走 [analyze] / [practice] factory。
  const AnalysisHistoryEvent({
    required this.id,
    required this.kind,
    required this.createdAt,
    this.conversationId,
    this.subjectName,
    this.enthusiasmScore,
    this.gameStageLabel,
    this.profileId,
    this.roundIndex,
    this.temperatureScore,
    this.familiarityScore,
    this.relationshipStageLabel,
  });

  factory AnalysisHistoryEvent.analyze({
    required String id,
    required DateTime createdAt,
    String? conversationId,
    String? subjectName,
    int? enthusiasmScore,
    String? gameStageLabel,
  }) {
    return AnalysisHistoryEvent(
      id: _requireId(id),
      kind: AnalysisHistoryKind.analyze,
      createdAt: createdAt,
      conversationId: _optionalTrim(conversationId),
      subjectName: _optionalTrim(subjectName),
      enthusiasmScore: enthusiasmScore,
      gameStageLabel: _optionalTrim(gameStageLabel),
    );
  }

  factory AnalysisHistoryEvent.practice({
    required String id,
    required DateTime createdAt,
    String? profileId,
    int? roundIndex,
    int? temperatureScore,
    int? familiarityScore,
    String? relationshipStageLabel,
  }) {
    return AnalysisHistoryEvent(
      id: _requireId(id),
      kind: AnalysisHistoryKind.practice,
      createdAt: createdAt,
      profileId: _optionalTrim(profileId),
      roundIndex: roundIndex,
      temperatureScore: temperatureScore,
      familiarityScore: familiarityScore,
      relationshipStageLabel: _optionalTrim(relationshipStageLabel),
    );
  }

  static String? normalizeScope(String? value) => _optionalTrim(value);

  static String _requireId(String id) {
    final normalized = id.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('AnalysisHistoryEvent.id must be non-empty');
    }
    return normalized;
  }

  static String? _optionalTrim(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
