/// optimize-message exactly-once 計費的 durable 身分值物件（domain）。
///
/// 歷史 import 路徑（optimize_message_request_session）以 re-export 相容。
library;

/// Durable identity for one user-visible optimize-message action.
///
/// Only an input digest and UUID are stored. Conversation text and the draft
/// never enter this record. The production store lives in the existing
/// AES-256 encrypted settings box.
class OptimizeMessagePendingRequest {
  const OptimizeMessagePendingRequest({
    required this.ownerUserId,
    required this.fingerprintDigest,
    required this.requestId,
    required this.createdAt,
  });

  final String ownerUserId;
  final String fingerprintDigest;
  final String requestId;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'ownerUserId': ownerUserId,
        'fingerprintDigest': fingerprintDigest,
        'requestId': requestId,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  static OptimizeMessagePendingRequest? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final ownerUserId = json['ownerUserId'];
    final fingerprintDigest = json['fingerprintDigest'];
    final requestId = json['requestId'];
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    if (ownerUserId is! String ||
        ownerUserId.trim().isEmpty ||
        fingerprintDigest is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(fingerprintDigest) ||
        requestId is! String ||
        !RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
          caseSensitive: false,
        ).hasMatch(requestId) ||
        createdAt == null) {
      return null;
    }
    return OptimizeMessagePendingRequest(
      ownerUserId: ownerUserId.trim(),
      fingerprintDigest: fingerprintDigest,
      requestId: requestId,
      createdAt: createdAt.toUtc(),
    );
  }
}
