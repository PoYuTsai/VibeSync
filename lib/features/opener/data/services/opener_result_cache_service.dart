import 'dart:convert';

import '../../../../core/services/storage_service.dart';
import 'opener_service.dart';

class OpenerResultCacheService {
  static const _latestResultKey = 'opener_latest_result_v1';

  Future<void> saveLatest(OpenerResult result) async {
    await StorageService.settingsBox.put(
      _latestResultKey,
      jsonEncode(result.toJson()),
    );
  }

  OpenerResult? loadLatest() {
    final raw = StorageService.settingsBox.get(_latestResultKey);
    if (raw is! String || raw.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return OpenerResult.fromJson(decoded);
      }
      if (decoded is Map) {
        return OpenerResult.fromJson(
          decoded.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  Future<void> clearLatest() async {
    await StorageService.settingsBox.delete(_latestResultKey);
  }
}
