import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:uuid/uuid.dart';

import '../../../conversation/domain/entities/message.dart';
import '../../../conversation/domain/entities/session_context.dart';

const _optimizeMessageReplayWindow = Duration(days: 7);

bool canSendOptimizeMessageRequest({
  required bool isEssential,
  required OptimizeMessagePendingRequest? pending,
}) =>
    isEssential || pending != null;

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

abstract class OptimizeMessagePendingRequestStore {
  Future<OptimizeMessagePendingRequest?> loadFor({
    required String ownerUserId,
    required String fingerprintDigest,
  });

  /// Must complete before the billable HTTP request starts. Save failures are
  /// intentionally observable so the caller can fail closed.
  Future<void> save(OptimizeMessagePendingRequest pending);

  /// Identity-scoped cleanup prevents a late old screen from deleting a newer
  /// attempt for the same payload.
  Future<void> clearFor(OptimizeMessagePendingRequest pending);
}

class InMemoryOptimizeMessagePendingRequestStore
    implements OptimizeMessagePendingRequestStore {
  final Map<String, OptimizeMessagePendingRequest> _pending = {};

  static String _key(String ownerUserId, String fingerprintDigest) =>
      '${ownerUserId.trim()}::$fingerprintDigest';

  @override
  Future<OptimizeMessagePendingRequest?> loadFor({
    required String ownerUserId,
    required String fingerprintDigest,
  }) async =>
      _pending[_key(ownerUserId, fingerprintDigest)];

  @override
  Future<void> save(OptimizeMessagePendingRequest pending) async {
    _pending[_key(pending.ownerUserId, pending.fingerprintDigest)] = pending;
  }

  @override
  Future<void> clearFor(OptimizeMessagePendingRequest pending) async {
    final key = _key(pending.ownerUserId, pending.fingerprintDigest);
    final current = _pending[key];
    if (current?.requestId == pending.requestId) {
      _pending.remove(key);
    }
  }
}

class HiveOptimizeMessagePendingRequestStore
    implements OptimizeMessagePendingRequestStore {
  HiveOptimizeMessagePendingRequestStore(this._openBox);

  final Box Function() _openBox;

  static const storageKeyPrefix = 'optimize_message_pending:v1:';

  static String _storageKey(String ownerUserId, String fingerprintDigest) {
    final encodedOwner =
        base64Url.encode(utf8.encode(ownerUserId.trim())).replaceAll('=', '');
    return '$storageKeyPrefix$encodedOwner:$fingerprintDigest';
  }

  @override
  Future<OptimizeMessagePendingRequest?> loadFor({
    required String ownerUserId,
    required String fingerprintDigest,
  }) async {
    final box = _openBox();
    final key = _storageKey(ownerUserId, fingerprintDigest);
    final hasStoredValue = box.containsKey(key);
    if (!hasStoredValue) return null;
    final pending = _decode(box.get(key));
    if (pending == null ||
        pending.ownerUserId != ownerUserId.trim() ||
        pending.fingerprintDigest != fingerprintDigest) {
      // An unreadable row may represent a server-settled request whose
      // response was lost. Deleting it and minting a new UUID could charge the
      // same user action twice, so fail closed and preserve forensic evidence.
      throw StateError('optimize-message pending identity is unreadable');
    }
    if (DateTime.now().toUtc().difference(pending.createdAt) >=
        _optimizeMessageReplayWindow) {
      await box.delete(key);
      return null;
    }
    return pending;
  }

  @override
  Future<void> save(OptimizeMessagePendingRequest pending) async {
    await _openBox().put(
      _storageKey(pending.ownerUserId, pending.fingerprintDigest),
      jsonEncode(pending.toJson()),
    );
  }

  @override
  Future<void> clearFor(OptimizeMessagePendingRequest pending) async {
    final box = _openBox();
    final key = _storageKey(pending.ownerUserId, pending.fingerprintDigest);
    final current = _decode(box.get(key));
    if (current?.ownerUserId == pending.ownerUserId &&
        current?.requestId == pending.requestId) {
      await box.delete(key);
    }
  }

  static OptimizeMessagePendingRequest? _decode(dynamic raw) {
    if (raw is! String) return null;
    try {
      return OptimizeMessagePendingRequest.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }
}

/// Keeps one optimize-message idempotency key alive across retries, route
/// changes, and app restarts. A changed wire payload gets a different digest
/// and therefore a new key.
class OptimizeMessageRequestIdSession {
  OptimizeMessageRequestIdSession({
    OptimizeMessagePendingRequestStore? store,
    DateTime Function()? now,
  })  : _store = store ?? InMemoryOptimizeMessagePendingRequestStore(),
        _now = now ?? DateTime.now;

  final OptimizeMessagePendingRequestStore _store;
  final DateTime Function() _now;
  final Map<String, OptimizeMessagePendingRequest> _pendingByIntent = {};
  final Set<String> _completedRequestIds = {};

  /// Reads an existing retry identity without minting one. This lets a user
  /// who has since downgraded recover an already-paid result, while a fresh
  /// non-Essential action still opens the paywall without touching the server.
  Future<OptimizeMessagePendingRequest?> findPending({
    required String ownerUserId,
    required String fingerprint,
  }) async {
    final normalizedOwner = ownerUserId.trim();
    if (normalizedOwner.isEmpty) {
      throw StateError('optimize-message owner is required');
    }
    final fingerprintDigest = digestFingerprint(fingerprint);
    final intentKey = '$normalizedOwner::$fingerprintDigest';
    final memoryPending = _pendingByIntent[intentKey];
    if (memoryPending != null &&
        !_isExpired(memoryPending) &&
        !_completedRequestIds.contains(memoryPending.requestId)) {
      return memoryPending;
    }

    final stored = await _store.loadFor(
      ownerUserId: normalizedOwner,
      fingerprintDigest: fingerprintDigest,
    );
    if (stored != null &&
        !_isExpired(stored) &&
        !_completedRequestIds.contains(stored.requestId)) {
      _pendingByIntent[intentKey] = stored;
      return stored;
    }

    return null;
  }

  Future<OptimizeMessagePendingRequest> beginAttempt({
    required String ownerUserId,
    required String fingerprint,
  }) async {
    final restored = await findPending(
      ownerUserId: ownerUserId,
      fingerprint: fingerprint,
    );
    if (restored != null) return restored;

    final normalizedOwner = ownerUserId.trim();
    final fingerprintDigest = digestFingerprint(fingerprint);
    final intentKey = '$normalizedOwner::$fingerprintDigest';

    final pending = OptimizeMessagePendingRequest(
      ownerUserId: normalizedOwner,
      fingerprintDigest: fingerprintDigest,
      requestId: const Uuid().v4(),
      createdAt: _now().toUtc(),
    );
    // Persist before any billable request. If this throws, the caller must not
    // send HTTP because a lost response could no longer be replayed safely.
    await _store.save(pending);
    _pendingByIntent[intentKey] = pending;
    return pending;
  }

  /// A parsed result closes the logical request only after the current screen
  /// can actually present it. Cleanup is identity-scoped for late responses.
  Future<void> markSuccess(OptimizeMessagePendingRequest pending) async {
    _completedRequestIds.add(pending.requestId);
    final intentKey = '${pending.ownerUserId}::${pending.fingerprintDigest}';
    if (_pendingByIntent[intentKey]?.requestId == pending.requestId) {
      _pendingByIntent.remove(intentKey);
    }
    try {
      await _store.clearFor(pending);
    } catch (_) {
      // Never hide a result that the server may already have charged for.
      // This session ignores the stale row; a later replay is user-safe and
      // cannot double-charge because the server ledger owns settlement.
    }
  }

  Future<void> reset(OptimizeMessagePendingRequest pending) async {
    final intentKey = '${pending.ownerUserId}::${pending.fingerprintDigest}';
    if (_pendingByIntent[intentKey]?.requestId == pending.requestId) {
      _pendingByIntent.remove(intentKey);
    }
    await _store.clearFor(pending);
  }

  bool _isExpired(OptimizeMessagePendingRequest pending) =>
      _now().toUtc().difference(pending.createdAt) >=
      _optimizeMessageReplayWindow;

  static String digestFingerprint(String fingerprint) =>
      sha256.convert(utf8.encode(fingerprint)).toString();

  /// Exact wire-affecting inputs, with field boundaries preserved by JSON.
  /// This fingerprint is never persisted; only its SHA-256 digest is stored.
  /// The server independently computes the authoritative input hash.
  static String fingerprintFor({
    required List<Message> messages,
    required String userDraft,
    SessionContext? sessionContext,
    String? conversationSummary,
    String? partnerSummary,
    String? effectiveStyleContext,
    String? knownContactName,
  }) {
    String? normalizedOptional(String? value) {
      final trimmed = value?.trim();
      return trimmed == null || trimmed.isEmpty ? null : trimmed;
    }

    return jsonEncode([
      messages.map((message) {
        final quotedPreview = normalizedOptional(
          message.quotedReplyPreview,
        );
        return {
          'isFromMe': message.isFromMe,
          'content': message.content,
          if (quotedPreview != null) 'quotedReplyPreview': quotedPreview,
          if (quotedPreview != null &&
              message.quotedReplyPreviewIsFromMe != null)
            'quotedReplyPreviewIsFromMe': message.quotedReplyPreviewIsFromMe,
        };
      }).toList(),
      userDraft.trim(),
      if (sessionContext == null)
        null
      else
        {
          'meetingContext': sessionContext.meetingContext.label,
          'duration': sessionContext.duration.label,
          'goal': sessionContext.goal.label,
          if (normalizedOptional(sessionContext.analysisContextNote) != null)
            'analysisContextNote':
                normalizedOptional(sessionContext.analysisContextNote),
        },
      normalizedOptional(conversationSummary),
      normalizedOptional(partnerSummary),
      normalizedOptional(effectiveStyleContext),
      normalizedOptional(knownContactName),
    ]);
  }
}
