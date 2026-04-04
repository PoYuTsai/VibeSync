import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthDiagnosticsService {
  static PackageInfo? _cachedPackageInfo;
  static final Map<String, DateTime> _recentEventCache = <String, DateTime>{};
  static const Duration _dedupeWindow = Duration(seconds: 10);
  static const int _maxMetadataEntries = 12;
  static const int _maxMetadataBytes = 1200;
  static const int _maxEventLength = 64;
  static const int _maxMessageLength = 300;
  static const int _maxErrorCodeLength = 80;
  static const Set<String> _allowedStatuses = {
    'info',
    'success',
    'warning',
    'error',
  };

  static Future<void> log({
    required String event,
    String? email,
    String status = 'info',
    String? message,
    String? errorCode,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final normalizedEvent = _normalizeEvent(event);
      if (normalizedEvent == null) {
        return;
      }

      final redactedEmail = (email != null && email.trim().isNotEmpty)
          ? _redactEmail(email)
          : null;

      if (_shouldSkipRecentDuplicate(
        event: normalizedEvent,
        emailRedacted: redactedEmail,
      )) {
        return;
      }

      final packageInfo = await _getPackageInfo();
      final payload = <String, dynamic>{
        'event': normalizedEvent,
        'status': _normalizeStatus(status),
        if (redactedEmail != null) 'email_redacted': redactedEmail,
        'platform': _platformLabel,
        if (packageInfo != null) 'app_version': packageInfo.version,
        if (packageInfo != null) 'build_number': packageInfo.buildNumber,
        if (message != null && message.trim().isNotEmpty)
          'message': _truncate(message, _maxMessageLength),
        if (errorCode != null && errorCode.trim().isNotEmpty)
          'error_code': _truncate(errorCode, _maxErrorCodeLength),
        if (metadata != null && metadata.isNotEmpty)
          'metadata': _sanitizeMetadata(metadata),
      };

      final response = await Supabase.instance.client.functions
          .invoke(
            'auth-diagnostics',
            body: payload,
          )
          .timeout(const Duration(seconds: 8));

      if (response.status < 200 || response.status >= 300) {
        debugPrint(
          'Auth diagnostics skipped: status=${response.status} data=${response.data}',
        );
      }
    } catch (error) {
      debugPrint('Auth diagnostics skipped: $error');
    }
  }

  static Future<PackageInfo?> _getPackageInfo() async {
    if (_cachedPackageInfo != null) {
      return _cachedPackageInfo;
    }

    try {
      _cachedPackageInfo = await PackageInfo.fromPlatform();
    } catch (_) {
      _cachedPackageInfo = null;
    }

    return _cachedPackageInfo;
  }

  static String get _platformLabel {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  static String _redactEmail(String email) {
    final trimmed = email.trim();
    final parts = trimmed.split('@');
    if (parts.length != 2) {
      return _truncate(trimmed, 40);
    }

    final local = parts[0];
    final domain = parts[1];
    final localPrefix = local.isEmpty
        ? 'u'
        : local.length <= 2
            ? local[0]
            : local.substring(0, 2);
    final localSuffix =
        local.length <= 2 ? '' : local.substring(local.length - 2);

    return '$localPrefix***$localSuffix@$domain';
  }

  static String? _normalizeEvent(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^a-z0-9_.:-]'), '_');

    if (normalized.isEmpty) {
      return null;
    }

    return _truncate(normalized, _maxEventLength);
  }

  static String _normalizeStatus(String value) {
    final normalized = value.trim().toLowerCase();
    if (_allowedStatuses.contains(normalized)) {
      return normalized;
    }
    return 'info';
  }

  static bool _shouldSkipRecentDuplicate({
    required String event,
    required String? emailRedacted,
  }) {
    final now = DateTime.now();
    _recentEventCache.removeWhere(
      (_, timestamp) => now.difference(timestamp) > _dedupeWindow,
    );

    final cacheKey = '$event|${emailRedacted ?? 'no-email'}';
    final lastSeenAt = _recentEventCache[cacheKey];
    if (lastSeenAt != null && now.difference(lastSeenAt) <= _dedupeWindow) {
      return true;
    }

    _recentEventCache[cacheKey] = now;
    return false;
  }

  static String _truncate(String value, int maxLength) {
    final trimmed = value.trim();
    if (trimmed.length <= maxLength) {
      return trimmed;
    }
    return '${trimmed.substring(0, maxLength - 3)}...';
  }

  static Map<String, dynamic> _sanitizeMetadata(Map<String, dynamic> input) {
    final sanitized = <String, dynamic>{};
    var truncated = false;

    for (final entry in input.entries.take(_maxMetadataEntries)) {
      final key = _truncate(
        entry.key.trim().replaceAll(RegExp(r'\s+'), '_'),
        40,
      );
      final value = entry.value;
      if (value == null) {
        continue;
      }

      if (value is num || value is bool) {
        sanitized[key] = value;
        continue;
      }

      if (value is String) {
        sanitized[key] = _truncate(value, 160);
        continue;
      }

      try {
        sanitized[key] = jsonDecode(jsonEncode(value));
      } catch (_) {
        sanitized[key] = _truncate(value.toString(), 160);
      }
    }

    while (_encodedSize(sanitized) > _maxMetadataBytes && sanitized.isNotEmpty) {
      sanitized.remove(sanitized.keys.last);
      truncated = true;
    }

    if (input.length > _maxMetadataEntries) {
      truncated = true;
    }

    if (truncated) {
      sanitized['_truncated'] = true;
    }

    return sanitized;
  }

  static int _encodedSize(Map<String, dynamic> value) {
    return utf8.encode(jsonEncode(value)).length;
  }
}
