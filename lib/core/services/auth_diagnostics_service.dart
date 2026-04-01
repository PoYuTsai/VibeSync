import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthDiagnosticsService {
  static PackageInfo? _cachedPackageInfo;

  static Future<void> log({
    required String event,
    String? email,
    String status = 'info',
    String? message,
    String? errorCode,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final packageInfo = await _getPackageInfo();
      final payload = <String, dynamic>{
        'event': event,
        'status': status,
        if (email != null && email.trim().isNotEmpty)
          'email_redacted': _redactEmail(email),
        'platform': _platformLabel,
        if (packageInfo != null) 'app_version': packageInfo.version,
        if (packageInfo != null) 'build_number': packageInfo.buildNumber,
        if (message != null && message.trim().isNotEmpty)
          'message': _truncate(message, 300),
        if (errorCode != null && errorCode.trim().isNotEmpty)
          'error_code': _truncate(errorCode, 80),
        if (metadata != null && metadata.isNotEmpty)
          'metadata': _sanitizeMetadata(metadata),
      };

      await Supabase.instance.client.from('auth_diagnostics').insert(payload);
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

  static String _truncate(String value, int maxLength) {
    final trimmed = value.trim();
    if (trimmed.length <= maxLength) {
      return trimmed;
    }
    return '${trimmed.substring(0, maxLength - 3)}...';
  }

  static Map<String, dynamic> _sanitizeMetadata(Map<String, dynamic> input) {
    final sanitized = <String, dynamic>{};

    input.forEach((key, value) {
      if (value == null) {
        return;
      }

      if (value is num || value is bool) {
        sanitized[key] = value;
        return;
      }

      if (value is String) {
        sanitized[key] = _truncate(value, 160);
        return;
      }

      try {
        sanitized[key] = jsonDecode(jsonEncode(value));
      } catch (_) {
        sanitized[key] = _truncate(value.toString(), 160);
      }
    });

    return sanitized;
  }
}
