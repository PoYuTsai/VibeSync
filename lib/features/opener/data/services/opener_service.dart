import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

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

class OpenerResult {
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

    for (final type in const [
      'extend',
      'resonate',
      'tease',
      'humor',
      'coldRead',
    ]) {
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

  String? get bestOpenerText {
    final type = bestOpenerType;
    if (type == null) return null;
    final text = openers[type]?.trim();
    return text == null || text.isEmpty ? null : text;
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
      openers: _stringMap(json['openers']),
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

  static Map<String, dynamic>? _dynamicMapOrNull(dynamic value) {
    if (value is! Map) {
      return null;
    }
    return value.map((key, value) => MapEntry(key.toString(), value));
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
    };

    final response = await _invoke('analyze-chat', body: body);

    if (response.status != 200) {
      final errorData = response.data;
      if (response.status == 429 && errorData is Map) {
        final rawError = errorData['error']?.toString().toLowerCase() ?? '';
        final fallbackMessage = rawError.contains('monthly')
            ? '本月額度不足，升級方案可取得更多開場與分析額度。'
            : rawError.contains('daily')
                ? '今日額度不足，明天會自動恢復；也可以升級取得更多額度。'
                : '額度不足，請先升級方案。';
        throw OpenerQuotaExceededException(
          message: errorData['message'] as String? ?? fallbackMessage,
          monthlyRemaining: (errorData['monthlyRemaining'] as num?)?.round(),
          dailyRemaining: (errorData['dailyRemaining'] as num?)?.round(),
          quotaNeeded: (errorData['quotaNeeded'] as num?)?.round(),
        );
      }

      final errorMsg = errorData is Map
          ? (errorData['error'] as String? ?? 'Unknown error')
          : 'Unknown error';
      throw Exception(errorMsg);
    }

    final data = response.data as Map<String, dynamic>;

    // Parse openers
    final openersRaw = data['openers'] as Map<String, dynamic>? ?? {};
    final openers = openersRaw.map((k, v) => MapEntry(k, v.toString()));

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
}

Future<OpenerInvokeResponse> _defaultInvoker(
  String fn, {
  required Map<String, dynamic> body,
}) async {
  final res = await Supabase.instance.client.functions.invoke(fn, body: body);
  return OpenerInvokeResponse(status: res.status, data: res.data);
}
