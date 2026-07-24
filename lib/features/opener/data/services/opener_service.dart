import 'dart:convert';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../../../core/services/supabase_service.dart';
import '../../../../core/utils/formula_reply_guard.dart';
import '../../domain/opener_access.dart';

/// Must stay above the Edge opener pipeline deadline so a server-side timeout
/// reaches the app before Dart abandons the response.
const kOpenerRequestTimeout = Duration(seconds: 70);

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

/// 一則公式開場（2026-07-24 公式回覆計畫 §9.1）：固定結構、內容動態生成，
/// 全 tier 可見、不參與五風格 counts／推薦／outcome bar。
class OpenerFormulaReply {
  const OpenerFormulaReply({
    required this.openingLine,
    required this.whyItWorks,
  });

  final String openingLine;
  final String whyItWorks;

  Map<String, dynamic> toJson() => {
        'openingLine': openingLine,
        'whyItWorks': whyItWorks,
      };
}

class OpenerResult {
  static const _preferredTypes = OpenerAccessContract.canonicalPaidOrder;

  final Map<String, dynamic>? profileAnalysis;
  final Map<String, String> openers;
  final Map<String, String>? pioneerPlan;
  final String? recommendedPick;
  final String? recommendedReason;
  final int costUsed;

  /// 批2：outcome 回報的 adviceId 基底（`opener:<requestId>:<type>`）。
  /// 生成時由 screen 掛上扣費 idempotency 的同一個 requestId；
  /// 舊快取缺席時 fromJson 自產（冪等斷裂為已拍板接受的邊際成本）。
  final String? requestId;

  /// Server 權威 access metadata（contract v2）。舊快取／舊 Edge 為 null；
  /// null 時讀取端只能以 paid-only keys 做 legacy fallback 判斷。
  final OpenerAccess? access;

  /// 公式開場（0–2 則 canonical）。舊 cache／舊 Edge 缺欄＝空清單；
  /// 全 tier 同一份，不做 Free projection、不算進「N 種風格」。
  final List<OpenerFormulaReply> formulaOpeners;

  const OpenerResult({
    this.profileAnalysis,
    required this.openers,
    this.pioneerPlan,
    this.recommendedPick,
    this.recommendedReason,
    this.costUsed = 3,
    this.requestId,
    this.access,
    this.formulaOpeners = const [],
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

  /// Free 依 contract v2 三型可見；recommendation 不可用時依 access 展示序
  /// fallback，絕不選 resonate/coldRead 給 Free。
  String? bestOpenerTypeForAccess({required bool isFreeUser}) {
    if (!isFreeUser) return bestOpenerType;

    final pick = recommendedPick;
    if (pick != null &&
        OpenerAccessContract.freeUnlockedTypes.contains(pick) &&
        (openers[pick]?.trim().isNotEmpty ?? false)) {
      return pick;
    }

    for (final type in OpenerAccessContract.freeUnlockedOrder) {
      if (openers[type]?.trim().isNotEmpty ?? false) {
        return type;
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

  String? bestOpenerTextForAccess({required bool isFreeUser}) {
    final type = bestOpenerTypeForAccess(isFreeUser: isFreeUser);
    if (type == null) return null;
    final text = openers[type]?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  /// 讀取時依目前權益重新投影（無 Hive migration）：Free 目前可見集合是
  /// contract v2 的 extend/humor/tease；舊 paid 五卡 JSON 降級 Free 後只留
  /// 三種、絕不洩漏 resonate/coldRead；舊 Free 單卡 JSON 照讀不補句。
  /// pick 被鎖時依 Free 展示序 fallback，且不硬套原鎖定內容的 reason。
  OpenerResult visibleForAccess({required bool isFreeUser}) {
    if (!isFreeUser) return this;

    final visibleOpeners = <String, String>{};
    for (final type in OpenerAccessContract.freeUnlockedOrder) {
      final text = openers[type]?.trim();
      if (text != null && text.isNotEmpty) {
        visibleOpeners[type] = text;
      }
    }

    final pickVisible =
        recommendedPick != null && visibleOpeners.containsKey(recommendedPick);
    final visiblePick = pickVisible
        ? recommendedPick
        : OpenerAccessContract.freeUnlockedOrder
            .where(visibleOpeners.containsKey)
            .firstOrNull;
    final visibleReason = pickVisible ? _blankToNull(recommendedReason) : null;

    return OpenerResult(
      profileAnalysis: profileAnalysis,
      openers: visibleOpeners,
      pioneerPlan: pioneerPlan,
      recommendedPick: visiblePick,
      recommendedReason: visibleReason,
      costUsed: costUsed,
      requestId: requestId,
      access: access,
      // 公式全 tier 可見：Free 投影只動五風格，公式原封傳遞（§9.1）。
      formulaOpeners: formulaOpeners,
    );
  }

  OpenerResult withRequestId(String? requestId) {
    return OpenerResult(
      profileAnalysis: profileAnalysis,
      openers: openers,
      pioneerPlan: pioneerPlan,
      recommendedPick: recommendedPick,
      recommendedReason: recommendedReason,
      costUsed: costUsed,
      requestId: requestId ?? this.requestId,
      access: access,
      formulaOpeners: formulaOpeners,
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
      if (requestId != null) 'requestId': requestId,
      if (access != null) 'access': access!.toJson(),
      'formulaOpeners':
          formulaOpeners.map((reply) => reply.toJson()).toList(),
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
      requestId: switch (json['requestId']) {
        final String value when value.trim().isNotEmpty => value.trim(),
        _ => const Uuid().v4(),
      },
      access: OpenerAccess.tryParse(json['access']),
      // best-effort：舊 cache 缺欄或形狀壞掉一律空清單，不拖垮原 openers。
      formulaOpeners: parseFormulaOpeners(json['formulaOpeners']),
    );
  }

  /// Cache／transport 雙用途 defense-in-depth 解析（server canonical 是
  /// 主防線）：壞項只丟該則、最多兩則。
  static List<OpenerFormulaReply> parseFormulaOpeners(dynamic value) {
    return List.unmodifiable(
      parseFormulaReplyList(value).map(
        (item) => OpenerFormulaReply(
          openingLine: item.openingLine,
          whyItWorks: item.whyItWorks,
        ),
      ),
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
    String? effectiveStyleContext,
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
      // Contract v2（Free 3 卡）：新 App 一律聲明版本；缺席時 server 以
      // legacy v1（Free 單卡）投影，避免 Edge 先上線讓舊 App 誤判。
      'openerContractVersion': OpenerAccessContract.contractVersion,
      if (imageDataList != null) 'images': imageDataList,
      if (profileInfo != null) 'profileInfo': profileInfo,
      if (expectedTier != null && expectedTier.trim().isNotEmpty)
        'expectedTier': expectedTier.trim(),
      if (revenueCatAppUserId != null && revenueCatAppUserId.trim().isNotEmpty)
        'revenueCatAppUserId': revenueCatAppUserId.trim(),
      // 扣費 idempotency：server 靠 (user, requestId) 去重傳輸層重試雙扣。
      if (requestId != null && requestId.trim().isNotEmpty)
        'requestId': requestId.trim(),
      // F3-1：用戶（發訊者）的風格設定，opener prompt 只拿來調語氣。
      if (effectiveStyleContext != null &&
          effectiveStyleContext.trim().isNotEmpty)
        'effectiveStyleContext': effectiveStyleContext.trim(),
    };

    final response = await _invoke('analyze-chat', body: body);

    if (response.status != 200) {
      final errorData = response.data;
      if (response.status == 429 && errorData is Map) {
        // server 端 per-user 模型呼叫限流（MODEL_RATE_LIMITED）不是訂閱額度：
        // 絕不 throw OpenerQuotaExceededException（那會誤開 paywall），
        // 走一般 Exception 讓 UI 顯示「稍等再試」文案。
        if (errorData['code'] == 'MODEL_RATE_LIMITED') {
          throw Exception(
            errorData['message'] as String? ?? '請求太頻繁，請稍後再試。',
          );
        }
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
      // Server 權威 tier 判定；形狀壞掉→null，讀取端走 legacy fallback。
      access: OpenerAccess.tryParse(data['access']),
      // 公式 best-effort：壞公式只得空清單，絕不影響原 openers 成功。
      formulaOpeners: OpenerResult.parseFormulaOpeners(data['formulaOpeners']),
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
  final res = await SupabaseService.invokeFunction(
    fn,
    body: body,
    timeout: kOpenerRequestTimeout,
  );
  return OpenerInvokeResponse(status: res.status, data: res.data);
}
