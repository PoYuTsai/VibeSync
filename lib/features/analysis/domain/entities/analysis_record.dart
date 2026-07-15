import 'dart:convert';

import '../../../conversation/domain/entities/message.dart';

/// A durable, independent analyze-chat case.
///
/// [segmentStart] is inclusive and [segmentEnd] is exclusive. Adjacent
/// records must never be stitched together for display or sent back to AI.
class AnalysisRecord {
  const AnalysisRecord({
    required this.id,
    required this.ownerUserId,
    required this.conversationId,
    required this.partnerId,
    required this.subjectName,
    required this.segmentStart,
    required this.segmentEnd,
    required this.createdAt,
    required this.messages,
    required this.analysisSnapshotJson,
    required this.analyzedContentRevision,
    required this.completionKey,
    required this.sourcePlatform,
    required this.enthusiasmScore,
    required this.gameStageLabel,
  });

  final String id;
  final String ownerUserId;
  final String conversationId;
  final String? partnerId;
  final String subjectName;
  final int segmentStart;
  final int segmentEnd;
  final DateTime createdAt;
  final List<AnalysisRecordMessage> messages;
  final String analysisSnapshotJson;
  final String analyzedContentRevision;

  /// Idempotency key of the successful analyzer completion that last wrote
  /// this record. A refresh of the same fragment replaces the current record
  /// instead of creating a new archived case.
  final String completionKey;

  /// User-selected conversation source at save time (for example `Omi` or
  /// `LINE`). Null means the source has not been labelled yet; OCR never
  /// guesses it.
  final String? sourcePlatform;
  final int enthusiasmScore;
  final String gameStageLabel;

  String get previewText {
    final incoming = messages.where((message) => !message.isFromMe);
    final source = incoming.isNotEmpty
        ? incoming.last.content
        : messages.lastOrNull?.content;
    final normalized =
        (source ?? '這次分析').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 32) return normalized;
    return '${normalized.substring(0, 32)}…';
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': 1,
        'id': id,
        'ownerUserId': ownerUserId,
        'conversationId': conversationId,
        'partnerId': partnerId,
        'subjectName': subjectName,
        'segmentStart': segmentStart,
        'segmentEnd': segmentEnd,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'messages': messages.map((message) => message.toJson()).toList(),
        'analysisSnapshotJson': analysisSnapshotJson,
        'analyzedContentRevision': analyzedContentRevision,
        'completionKey': completionKey,
        'sourcePlatform': sourcePlatform,
        'enthusiasmScore': enthusiasmScore,
        'gameStageLabel': gameStageLabel,
      };

  String encode() => jsonEncode(toJson());

  static AnalysisRecord? tryDecode(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final json = decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final schemaVersion = json['schemaVersion'];
      final id = json['id'];
      final ownerUserId = json['ownerUserId'];
      final conversationId = json['conversationId'];
      final subjectName = json['subjectName'];
      final segmentStart = json['segmentStart'];
      final segmentEnd = json['segmentEnd'];
      final createdAtRaw = json['createdAt'];
      final snapshot = json['analysisSnapshotJson'];
      final contentRevision = json['analyzedContentRevision'];
      final completionKey = json['completionKey'];
      final enthusiasmScore = json['enthusiasmScore'];
      final gameStageLabel = json['gameStageLabel'];
      final rawMessages = json['messages'];
      if (schemaVersion != 1 ||
          id is! String ||
          id.trim().isEmpty ||
          ownerUserId is! String ||
          ownerUserId.trim().isEmpty ||
          conversationId is! String ||
          conversationId.trim().isEmpty ||
          subjectName is! String ||
          segmentStart is! int ||
          segmentEnd is! int ||
          createdAtRaw is! String ||
          snapshot is! String ||
          snapshot.trim().isEmpty ||
          contentRevision is! String ||
          contentRevision.trim().isEmpty ||
          completionKey is! String ||
          completionKey.trim().isEmpty ||
          enthusiasmScore is! int ||
          gameStageLabel is! String ||
          rawMessages is! List) {
        return null;
      }
      final createdAt = DateTime.tryParse(createdAtRaw);
      if (createdAt == null || segmentStart < 0 || segmentEnd <= segmentStart) {
        return null;
      }
      final messages = <AnalysisRecordMessage>[];
      for (final rawMessage in rawMessages) {
        final message = AnalysisRecordMessage.tryFromJson(rawMessage);
        if (message == null) return null;
        messages.add(message);
      }
      if (messages.length != segmentEnd - segmentStart) return null;
      final partnerIdRaw = json['partnerId'];
      final sourcePlatformRaw = json['sourcePlatform'];
      if (sourcePlatformRaw != null && sourcePlatformRaw is! String) {
        return null;
      }
      return AnalysisRecord(
        id: id,
        ownerUserId: ownerUserId,
        conversationId: conversationId,
        partnerId: partnerIdRaw is String && partnerIdRaw.trim().isNotEmpty
            ? partnerIdRaw
            : null,
        subjectName: subjectName,
        segmentStart: segmentStart,
        segmentEnd: segmentEnd,
        createdAt: createdAt,
        messages: List.unmodifiable(messages),
        analysisSnapshotJson: snapshot,
        analyzedContentRevision: contentRevision,
        completionKey: completionKey,
        sourcePlatform:
            sourcePlatformRaw is String && sourcePlatformRaw.trim().isNotEmpty
                ? sourcePlatformRaw.trim()
                : null,
        enthusiasmScore: enthusiasmScore.clamp(0, 100),
        gameStageLabel: gameStageLabel,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Immutable deep copy of a [Message] at analysis completion time.
class AnalysisRecordMessage {
  const AnalysisRecordMessage({
    required this.id,
    required this.content,
    required this.isFromMe,
    required this.timestamp,
    this.enthusiasmScore,
    this.quotedReplyPreview,
    this.quotedReplyPreviewIsFromMe,
  });

  factory AnalysisRecordMessage.fromMessage(Message message) =>
      AnalysisRecordMessage(
        id: message.id,
        content: message.content,
        isFromMe: message.isFromMe,
        timestamp: message.timestamp,
        enthusiasmScore: message.enthusiasmScore,
        quotedReplyPreview: message.quotedReplyPreview,
        quotedReplyPreviewIsFromMe: message.quotedReplyPreviewIsFromMe,
      );

  final String id;
  final String content;
  final bool isFromMe;
  final DateTime timestamp;
  final int? enthusiasmScore;
  final String? quotedReplyPreview;
  final bool? quotedReplyPreviewIsFromMe;

  Message toMessage() => Message(
        id: id,
        content: content,
        isFromMe: isFromMe,
        timestamp: timestamp,
        enthusiasmScore: enthusiasmScore,
        quotedReplyPreview: quotedReplyPreview,
        quotedReplyPreviewIsFromMe: quotedReplyPreviewIsFromMe,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'content': content,
        'isFromMe': isFromMe,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'enthusiasmScore': enthusiasmScore,
        'quotedReplyPreview': quotedReplyPreview,
        'quotedReplyPreviewIsFromMe': quotedReplyPreviewIsFromMe,
      };

  static AnalysisRecordMessage? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = raw.map((key, value) => MapEntry(key.toString(), value));
    final id = json['id'];
    final content = json['content'];
    final isFromMe = json['isFromMe'];
    final timestampRaw = json['timestamp'];
    final enthusiasmScore = json['enthusiasmScore'];
    if (id is! String ||
        content is! String ||
        isFromMe is! bool ||
        timestampRaw is! String ||
        (enthusiasmScore != null && enthusiasmScore is! int)) {
      return null;
    }
    final timestamp = DateTime.tryParse(timestampRaw);
    if (timestamp == null) return null;
    final quote = json['quotedReplyPreview'];
    final quoteSide = json['quotedReplyPreviewIsFromMe'];
    if (quote != null && quote is! String) return null;
    if (quoteSide != null && quoteSide is! bool) return null;
    return AnalysisRecordMessage(
      id: id,
      content: content,
      isFromMe: isFromMe,
      timestamp: timestamp,
      enthusiasmScore: enthusiasmScore as int?,
      quotedReplyPreview: quote as String?,
      quotedReplyPreviewIsFromMe: quoteSide as bool?,
    );
  }
}

extension _LastOrNull<T> on Iterable<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
