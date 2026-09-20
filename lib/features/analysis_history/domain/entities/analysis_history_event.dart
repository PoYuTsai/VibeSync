import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';

part 'analysis_history_event.g.dart';

/// 案2：本機分析事件歷史（analyze 熱度 / practice 溫度共用一張表）。
/// 本機 only，絕不上傳。新 id 形成新事件；同一內容修訂重跑會以相同 id
/// 原地更新，避免趨勢重複。legacy scope metadata 可回填；repository 寫入
/// 時超過 500 筆刪最舊。
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

  /// Canonical person scope for report aggregation. Legacy events can leave
  /// this null and are resolved through [conversationId] at read time.
  @HiveField(12)
  final String? partnerId;

  /// `opening` 是否代表分析當下的既有伴侶重新連線。
  /// null 只供舊資料相容；新 analyze event 一律寫入明確布林值，避免日後
  /// 修改 Conversation 情境時回寫舊歷史語意。
  @HiveField(13)
  final bool? isReconnect;

  /// practice 用：本輪已解析的難度 `easy / normal / challenge`（不是使用者選的
  /// random 偏好）。舊事件為 null；報告頁不猜值。
  @HiveField(14)
  final String? practiceDifficulty;

  /// practice 用：本輪成功接受的 AI 回覆次數（不是 messages 長度，也不是跨輪
  /// 逐字稿長度）。舊事件為 null。
  @HiveField(15)
  final int? aiReplyCount;

  /// practice 用：`beginner / game`。舊事件為 null。
  @HiveField(16)
  final String? practiceMode;

  /// practice 用：當次完成的 session id。新格式事件的 id 亦為
  /// `practice:<sessionId>`（同場冪等覆寫）；舊事件 id 是隨機 UUID，此欄位
  /// 讓讀取端不必解析 id 字串。
  @HiveField(17)
  final String? practiceSessionId;

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
    this.partnerId,
    this.isReconnect,
    this.practiceDifficulty,
    this.aiReplyCount,
    this.practiceMode,
    this.practiceSessionId,
  });

  factory AnalysisHistoryEvent.analyze({
    required String id,
    required DateTime createdAt,
    String? conversationId,
    String? partnerId,
    String? subjectName,
    int? enthusiasmScore,
    String? gameStageLabel,
    bool? isReconnect,
  }) {
    return AnalysisHistoryEvent(
      id: _requireId(id),
      kind: AnalysisHistoryKind.analyze,
      createdAt: createdAt,
      conversationId: _optionalTrim(conversationId),
      partnerId: _optionalTrim(partnerId),
      subjectName: _optionalTrim(subjectName),
      enthusiasmScore: enthusiasmScore,
      gameStageLabel: _optionalTrim(gameStageLabel),
      isReconnect: isReconnect,
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
    String? practiceDifficulty,
    int? aiReplyCount,
    String? practiceMode,
    String? practiceSessionId,
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
      practiceDifficulty: _optionalTrim(practiceDifficulty),
      aiReplyCount: aiReplyCount,
      practiceMode: _optionalTrim(practiceMode),
      practiceSessionId: _optionalTrim(practiceSessionId),
    );
  }

  /// 新格式練習事件的穩定 id：同一場 debrief 再寫一次也只覆寫同一筆。
  static String practiceEventId(String sessionId) {
    final normalized = sessionId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(
        sessionId,
        'sessionId',
        'must not be empty',
      );
    }
    return 'practice:$normalized';
  }

  static String? normalizeScope(String? value) => _optionalTrim(value);

  AnalysisHistoryEvent withPartnerId(String partnerId) {
    return AnalysisHistoryEvent(
      id: id,
      kind: kind,
      createdAt: createdAt,
      conversationId: conversationId,
      subjectName: subjectName,
      enthusiasmScore: enthusiasmScore,
      gameStageLabel: gameStageLabel,
      profileId: profileId,
      roundIndex: roundIndex,
      temperatureScore: temperatureScore,
      familiarityScore: familiarityScore,
      relationshipStageLabel: relationshipStageLabel,
      partnerId: _optionalTrim(partnerId),
      isReconnect: isReconnect,
      practiceDifficulty: practiceDifficulty,
      aiReplyCount: aiReplyCount,
      practiceMode: practiceMode,
      practiceSessionId: practiceSessionId,
    );
  }

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
