import 'dart:convert';
import 'dart:typed_data';

import '../../../../core/services/supabase_service.dart';

typedef OpenerInvoker = Future<OpenerInvokeResponse> Function(
  String functionName, {
  required Map<String, dynamic> body,
});

class OpenerInvokeResponse {
  final int status;
  final dynamic data;

  const OpenerInvokeResponse({
    required this.status,
    this.data,
  });
}

class OpenerGenerationInput {
  final List<Uint8List>? images;
  final String? name;
  final String? bio;
  final String? interests;
  final String? meetingContext;

  const OpenerGenerationInput({
    this.images,
    this.name,
    this.bio,
    this.interests,
    this.meetingContext,
  });

  factory OpenerGenerationInput.fromActiveTab({
    required bool useScreenshotTab,
    required List<Uint8List> images,
    String? name,
    String? bio,
    String? interests,
    String? meetingContext,
  }) {
    if (useScreenshotTab) {
      return OpenerGenerationInput(
        images: images.isEmpty ? null : List<Uint8List>.unmodifiable(images),
      );
    }

    return OpenerGenerationInput(
      name: _blankToNull(name),
      bio: _blankToNull(bio),
      interests: _blankToNull(interests),
      meetingContext: _blankToNull(meetingContext),
    );
  }

  bool get hasContent =>
      (images?.isNotEmpty ?? false) ||
      _hasText(name) ||
      _hasText(bio) ||
      _hasText(interests);

  static bool _hasText(String? value) {
    final trimmed = value?.trim();
    return trimmed != null && trimmed.isNotEmpty;
  }

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

class OpenerResult {
  static const _preferredTypes = [
    'extend',
    'resonate',
    'tease',
    'humor',
    'coldRead',
  ];

  final Map<String, dynamic>? profileAnalysis;
  final Map<String, String> openers;
  final Map<String, String>? pioneerPlan;
  final String? recommendedPick;
  final String? recommendedReason;
  final int costUsed;

  const OpenerResult({
    this.profileAnalysis,
    required this.openers,
    this.pioneerPlan,
    this.recommendedPick,
    this.recommendedReason,
    this.costUsed = 3,
  });

  String? get bestOpenerType {
    final pick = recommendedPick;
    if (pick != null && (openers[pick]?.trim().isNotEmpty ?? false)) {
      return pick;
    }

    for (final type in _preferredTypes) {
      if (openers[type]?.trim().isNotEmpty ?? false) {
        return type;
      }
    }

    for (final entry in openers.entries) {
      if (entry.value.trim().isNotEmpty) {
        return entry.key;
      }
    }
    return null;
  }

  String? bestOpenerTypeForAccess({required bool isFreeUser}) {
    if (!isFreeUser) return bestOpenerType;
    return openers['extend']?.trim().isNotEmpty == true ? 'extend' : null;
  }

  String? get bestOpenerText {
    final type = bestOpenerType;
    if (type == null) return null;
    final text = openers[type]?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  String? bestOpenerTextForAccess({required bool isFreeUser}) {
    final type = bestOpenerTypeForAccess(isFreeUser: isFreeUser);
    if (type == null) return null;
    final text = openers[type]?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  OpenerResult visibleForAccess({required bool isFreeUser}) {
    if (!isFreeUser) return this;

    final extend = openers['extend']?.trim();
    final visibleOpeners = extend == null || extend.isEmpty
        ? <String, String>{}
        : <String, String>{'extend': extend};
    final visibleReason =
        recommendedPick == 'extend' ? _blankToNull(recommendedReason) : null;

    return OpenerResult(
      profileAnalysis: profileAnalysis,
      openers: visibleOpeners,
      pioneerPlan: pioneerPlan,
      recommendedPick: visibleOpeners.isEmpty ? null : 'extend',
      recommendedReason: visibleReason,
      costUsed: costUsed,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (profileAnalysis != null) 'profileAnalysis': profileAnalysis,
      'openers': openers,
      if (pioneerPlan != null) 'pioneerPlan': pioneerPlan,
      if (recommendedPick != null) 'recommendedPick': recommendedPick,
      if (recommendedReason != null) 'recommendedReason': recommendedReason,
      'costUsed': costUsed,
    };
  }

  factory OpenerResult.fromJson(Map<String, dynamic> json) {
    return OpenerResult(
      profileAnalysis: _dynamicMapOrNull(json['profileAnalysis']),
      openers: _openerStringMap(json['openers']),
      pioneerPlan:
          json['pioneerPlan'] == null ? null : _stringMap(json['pioneerPlan']),
      recommendedPick: json['recommendedPick'] as String?,
      recommendedReason: json['recommendedReason'] as String?,
      costUsed: (json['costUsed'] as num?)?.round() ?? 3,
    );
  }

  static Map<String, String> _stringMap(dynamic value) {
    if (value is! Map) {
      return const {};
    }
    return value.map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    );
  }

  static Map<String, String> _openerStringMap(dynamic value) {
    if (value is! Map) {
      return const {};
    }

    final result = <String, String>{};
    for (final entry in value.entries) {
      final text = _sanitizeOpenerText(entry.value);
      if (text != null) {
        result[entry.key.toString()] = text;
      }
    }
    return result;
  }

  static String? _sanitizeOpenerText(dynamic value) {
    String? text;
    if (value is String) {
      text = value;
    } else if (value is Map) {
      for (final key in const [
        'text',
        'message',
        'opener',
        'content',
        'line'
      ]) {
        final nested = value[key];
        if (nested is String) {
          text = nested;
          break;
        }
      }
    }

    final trimmed = text?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }

    final lower = trimmed.toLowerCase();
    if (trimmed.startsWith('```') ||
        trimmed.startsWith('{') ||
        trimmed.startsWith('[') ||
        lower.contains('"profileanalysis"') ||
        lower.contains('"openers"') ||
        lower.contains('```json')) {
      return null;
    }

    if (trimmed.length > 180) {
      return null;
    }

    return trimmed;
  }

  static Map<String, dynamic>? _dynamicMapOrNull(dynamic value) {
    if (value is! Map) {
      return null;
    }
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

class OpenerQuotaExceededException implements Exception {
  final String message;
  final int? monthlyRemaining;
  final int? dailyRemaining;
  final int? quotaNeeded;

  const OpenerQuotaExceededException({
    required this.message,
    this.monthlyRemaining,
    this.dailyRemaining,
    this.quotaNeeded,
  });

  @override
  String toString() => message;
}

class OpenerService {
  OpenerService({OpenerInvoker? invoker})
      : _invoke = invoker ?? _defaultInvoker;

  final OpenerInvoker _invoke;

  Future<OpenerResult> generateOpeners({
    List<Uint8List>? images,
    String? name,
    String? bio,
    String? interests,
    String? meetingContext,
    String? expectedTier,
    String? revenueCatAppUserId,
    String? requestId,
  }) async {
    // Build image list as ImageData objects (matching existing format)
    List<Map<String, dynamic>>? imageDataList;
    if (images != null && images.isNotEmpty) {
      imageDataList = images.asMap().entries.map((entry) {
        return {
          'data': base64Encode(entry.value),
          'mediaType': 'image/jpeg',
          'order': entry.key + 1,
        };
      }).toList();
    }

    // Build profile info
    Map<String, String>? profileInfo;
    if ((name != null && name.trim().isNotEmpty) ||
        (bio != null && bio.trim().isNotEmpty) ||
        (interests != null && interests.trim().isNotEmpty) ||
        (meetingContext != null && meetingContext.trim().isNotEmpty)) {
      profileInfo = {};
      if (name != null && name.trim().isNotEmpty) {
        profileInfo['name'] = name.trim();
      }
      if (bio != null && bio.trim().isNotEmpty) {
        profileInfo['bio'] = bio.trim();
      }
      if (interests != null && interests.trim().isNotEmpty) {
        profileInfo['interests'] = interests.trim();
      }
      if (meetingContext != null && meetingContext.trim().isNotEmpty) {
        profileInfo['meetingContext'] = meetingContext.trim();
      }
    }

    final body = {
      'mode': 'opener',
      if (imageDataList != null) 'images': imageDataList,
      if (profileInfo != null) 'profileInfo': profileInfo,
      if (expectedTier != null && expectedTier.trim().isNotEmpty)
        'expectedTier': expectedTier.trim(),
      if (revenueCatAppUserId != null && revenueCatAppUserId.trim().isNotEmpty)
        'revenueCatAppUserId': revenueCatAppUserId.trim(),
      // 扣費 idempotency：server 靠 (user, requestId) 去重傳輸層重試雙扣。
      if (requestId != null && requestId.trim().isNotEmpty)
        'requestId': requestId.trim(),
    };

    final response = await _invoke('analyze-chat', body: body);

    if (response.status != 200) {
      final errorData = response.data;
      if (response.status == 429 && errorData is Map) {
        final rawError = errorData['error']?.toString().toLowerCase() ?? '';
        final fallbackMessage = rawError.contains('monthly')
            ? '本月額度不足，升級方案可取得更多開場與分析額度。'
            : rawError.contains('daily')
                ? '今日額度不足，每天早上 8 點恢復；也可以升級取得更多額度。'
                : '額度不足，請先升級方案。';
        throw OpenerQuotaExceededException(
          message: errorData['message'] as String? ?? fallbackMessage,
          monthlyRemaining: (errorData['monthlyRemaining'] as num?)?.round(),
          dailyRemaining: (errorData['dailyRemaining'] as num?)?.round(),
          quotaNeeded: (errorData['quotaNeeded'] as num?)?.round(),
        );
      }

      final errorMsg = errorData is Map
          ? _nonQuotaErrorMessage(response.status, errorData)
          : '開場產生失敗，請稍後再試。';
      throw Exception(errorMsg);
    }

    final data = response.data as Map<String, dynamic>;

    // Parse openers defensively. Raw JSON/code fences are not sendable openers.
    final openers = OpenerResult._openerStringMap(data['openers']);
    if (openers.isEmpty) {
      throw Exception('開場產生格式異常，請重新生成一次。');
    }

    // Parse recommendation
    final recommendation = data['recommendation'] as Map<String, dynamic>?;

    // Parse first-message follow-up plan
    final pioneerPlanRaw = data['pioneerPlan'] as Map<String, dynamic>?;
    final pioneerPlan =
        pioneerPlanRaw?.map((k, v) => MapEntry(k, v.toString()));

    // Parse profile analysis
    final profileAnalysis = data['profileAnalysis'] as Map<String, dynamic>?;

    // Parse cost
    final usage = data['usage'] as Map<String, dynamic>?;
    final cost = usage?['cost'] as int? ?? 3;

    return OpenerResult(
      profileAnalysis: profileAnalysis,
      openers: openers,
      pioneerPlan: pioneerPlan,
      recommendedPick: recommendation?['pick'] as String?,
      recommendedReason: recommendation?['reason'] as String?,
      costUsed: cost,
    );
  }

  String _nonQuotaErrorMessage(int status, Map errorData) {
    final message = errorData['message']?.toString().trim();
    if (message != null && message.isNotEmpty) {
      return message;
    }

    if (status >= 500) {
      return 'AI 暫時生成失敗，請稍後再試；本次不會扣額度。';
    }

    final error = errorData['error']?.toString().trim();
    return error == null || error.isEmpty ? '開場產生失敗，請稍後再試。' : error;
  }
}

Future<OpenerInvokeResponse> _defaultInvoker(
  String fn, {
  required Map<String, dynamic> body,
}) async {
  final res = await SupabaseService.invokeFunction(fn, body: body);
  return OpenerInvokeResponse(status: res.status, data: res.data);
}
