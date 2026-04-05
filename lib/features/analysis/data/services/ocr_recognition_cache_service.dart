import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../../../core/services/storage_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../domain/entities/analysis_models.dart';

class OcrRecognitionCacheEntry {
  final String fingerprint;
  final DateTime cachedAt;
  final RecognizedConversation recognizedConversation;

  const OcrRecognitionCacheEntry({
    required this.fingerprint,
    required this.cachedAt,
    required this.recognizedConversation,
  });
}

class OcrRecognitionCacheService {
  static const _cachePrefix = 'ocr_recognition_cache';
  // Bump this whenever OCR structure/speaker heuristics change so the app
  // does not keep replaying stale local recognition results for the same image.
  static const _cacheVersion = 4;
  static const _maxEntriesPerUser = 20;
  static const _maxAge = Duration(hours: 24);
  static const _pruneInterval = Duration(minutes: 10);
  static DateTime? _lastPrunedAt;

  static String _currentUserKey() =>
      SupabaseService.currentUser?.id ?? 'anonymous';

  static String _normalizeScopeKey(String? conversationId) {
    final trimmed = conversationId?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return 'global';
    }

    return trimmed;
  }

  static String _cacheKey(
    String fingerprint,
    String userKey,
    String scopeKey,
  ) => '$_cachePrefix:$userKey:$scopeKey:$fingerprint';

  static String _fingerprintImages(List<Uint8List> images) {
    final combined = <int>[];
    combined.addAll(utf8.encode('v$_cacheVersion:${images.length}|'));
    for (final image in images) {
      combined.addAll(utf8.encode('${image.length}:'));
      combined.addAll(image);
      combined.add(124);
    }
    return sha256.convert(combined).toString();
  }

  static bool _isExpired(DateTime cachedAt) {
    return DateTime.now().difference(cachedAt) > _maxAge;
  }

  static bool _shouldCache(RecognizedConversation recognizedConversation) {
    final hasMessages = (recognizedConversation.messages ?? const [])
        .where((message) => message.content.trim().isNotEmpty)
        .isNotEmpty;

    if (!hasMessages) {
      return false;
    }

    return recognizedConversation.importPolicy == 'allow' &&
        recognizedConversation.confidence == 'high' &&
        recognizedConversation.sideConfidence == 'high' &&
        recognizedConversation.uncertainSideCount == 0;
  }

  static DateTime? _parseCachedAt(dynamic value) {
    if (value is! String || value.trim().isEmpty) {
      return null;
    }

    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _decodeEntry(dynamic rawValue) {
    if (rawValue is! String || rawValue.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(rawValue);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  static Future<void> _pruneEntries() async {
    final now = DateTime.now();
    if (_lastPrunedAt != null &&
        now.difference(_lastPrunedAt!) < _pruneInterval) {
      return;
    }
    _lastPrunedAt = now;

    final box = StorageService.settingsBox;
    final prefix = '$_cachePrefix:';
    final cachedEntries = <({
      dynamic key,
      DateTime cachedAt,
    })>[];
    final keysToDelete = <dynamic>[];

    for (final key in box.keys) {
      if (key is! String || !key.startsWith(prefix)) {
        continue;
      }

      final decoded = _decodeEntry(box.get(key));
      if (decoded == null || decoded['version'] != _cacheVersion) {
        keysToDelete.add(key);
        continue;
      }

      final cachedAt = _parseCachedAt(decoded['cachedAt']);
      if (cachedAt == null || _isExpired(cachedAt)) {
        keysToDelete.add(key);
        continue;
      }

      cachedEntries.add((key: key, cachedAt: cachedAt));
    }

    final userKey = _currentUserKey();
    final currentUserPrefix = '$_cachePrefix:$userKey:';
    final currentUserEntries = cachedEntries
        .where((entry) => (entry.key as String).startsWith(currentUserPrefix))
        .toList()
      ..sort((a, b) => b.cachedAt.compareTo(a.cachedAt));

    for (final staleEntry in currentUserEntries.skip(_maxEntriesPerUser)) {
      keysToDelete.add(staleEntry.key);
    }

    if (keysToDelete.isNotEmpty) {
      await box.deleteAll(keysToDelete);
    }
  }

  static Future<OcrRecognitionCacheEntry?> read(
    List<Uint8List> images,
    String? conversationId,
  ) async {
    if (images.isEmpty) {
      return null;
    }

    await _pruneEntries();

    final userKey = _currentUserKey();
    final scopeKey = _normalizeScopeKey(conversationId);
    final fingerprint = _fingerprintImages(images);
    final decoded = _decodeEntry(
      StorageService.settingsBox.get(_cacheKey(fingerprint, userKey, scopeKey)),
    );
    if (decoded == null || decoded['version'] != _cacheVersion) {
      return null;
    }

    final cachedAt = _parseCachedAt(decoded['cachedAt']);
    final recognizedJson = decoded['recognizedConversation'];
    if (cachedAt == null ||
        _isExpired(cachedAt) ||
        recognizedJson is! Map<String, dynamic>) {
      await StorageService.settingsBox.delete(
        _cacheKey(fingerprint, userKey, scopeKey),
      );
      return null;
    }

    final recognizedConversation = RecognizedConversation.fromJson(
      recognizedJson,
    );
    if (!_shouldCache(recognizedConversation)) {
      await StorageService.settingsBox.delete(
        _cacheKey(fingerprint, userKey, scopeKey),
      );
      return null;
    }

    return OcrRecognitionCacheEntry(
      fingerprint: fingerprint,
      cachedAt: cachedAt,
      recognizedConversation: recognizedConversation,
    );
  }

  static Future<void> write({
    required List<Uint8List> images,
    required RecognizedConversation recognizedConversation,
    String? conversationId,
  }) async {
    if (images.isEmpty || !_shouldCache(recognizedConversation)) {
      return;
    }

    final userKey = _currentUserKey();
    final scopeKey = _normalizeScopeKey(conversationId);
    final fingerprint = _fingerprintImages(images);
    final payload = <String, dynamic>{
      'version': _cacheVersion,
      'cachedAt': DateTime.now().toIso8601String(),
      'recognizedConversation': recognizedConversation.toJson(),
    };

    await StorageService.settingsBox.put(
      _cacheKey(fingerprint, userKey, scopeKey),
      jsonEncode(payload),
    );
    await _pruneEntries();
  }

  static Future<void> invalidate(
    List<Uint8List> images,
    String? conversationId,
  ) async {
    if (images.isEmpty) {
      return;
    }

    final userKey = _currentUserKey();
    final scopeKey = _normalizeScopeKey(conversationId);
    final fingerprint = _fingerprintImages(images);
    await StorageService.settingsBox.delete(
      _cacheKey(fingerprint, userKey, scopeKey),
    );
  }
}
