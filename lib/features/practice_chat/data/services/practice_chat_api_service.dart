import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_catalog.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_hint.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_learning_mode.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_temperature.dart';

/// 一則送進 practice-chat 的對話 turn。
class PracticeTurnDto {
  final String role; // 'user' | 'ai'
  final String text;
  const PracticeTurnDto({required this.role, required this.text});

  Map<String, dynamic> toJson() => {'role': role, 'text': text};
}

/// 本場「對象＋難度」的請求 metadata。client 只送 allowlisted id（絕不送 prompt
/// 文字）；server 帶 profileId 時會綁定該位的 persona，並要求 nameId/professionId/
/// photoId 與該位相符。身份欄位可空：舊路徑（無 catalog）只送 personaId+difficulty。
class PracticeProfileDto {
  final String personaId;
  final String difficulty;
  final String? profileId;
  final String? nameId;
  final String? professionId;
  final String? photoId;

  const PracticeProfileDto({
    required this.personaId,
    required this.difficulty,
    this.profileId,
    this.nameId,
    this.professionId,
    this.photoId,
  });

  Map<String, dynamic> toJson() => {
        'personaId': personaId,
        'difficulty': difficulty,
        if (profileId != null) 'profileId': profileId,
        if (nameId != null) 'nameId': nameId,
        if (professionId != null) 'professionId': professionId,
        if (photoId != null) 'photoId': photoId,
      };
}

/// chat 模式成功回應。
class PracticeChatReply {
  final String reply;
  final int aiTurnCount;
  final bool sessionComplete;
  final int costDeducted;
  final int? monthlyRemaining;
  final int? dailyRemaining;
  final PracticeTemperature? temperature;
  final int? hintUsedCount;

  const PracticeChatReply({
    required this.reply,
    required this.aiTurnCount,
    required this.sessionComplete,
    required this.costDeducted,
    this.monthlyRemaining,
    this.dailyRemaining,
    this.temperature,
    this.hintUsedCount,
  });
}

/// debrief 模式成功回應（教練拆解卡）。
class PracticeDebrief {
  final String summary;
  final List<String> strengths;
  final List<String> watchouts;
  final String suggestedLine;
  final String vibe;
  final int? monthlyRemaining;
  final int? dailyRemaining;

  const PracticeDebrief({
    required this.summary,
    required this.strengths,
    required this.watchouts,
    required this.suggestedLine,
    required this.vibe,
    this.monthlyRemaining,
    this.dailyRemaining,
  });
}

/// 翻牌成功回應：server 選定的對象身份（display-only id）。
class PracticeDrawnProfile {
  final String profileId;
  final String nameId;
  final String professionId;
  final String photoId;
  final String personaId;

  const PracticeDrawnProfile({
    required this.profileId,
    required this.nameId,
    required this.professionId,
    required this.photoId,
    required this.personaId,
  });
}

/// 翻牌收據：本次扣費與免費額度狀態（server 為單一真實來源）。
class PracticeDrawReceipt {
  final int costMessages;
  final int freeAllowance;
  final int freeUsed;
  final int freeRemaining;
  final int extraCostMessages;
  final String nextResetAt;

  const PracticeDrawReceipt({
    required this.costMessages,
    required this.freeAllowance,
    required this.freeUsed,
    required this.freeRemaining,
    required this.extraCostMessages,
    required this.nextResetAt,
  });
}

/// 翻牌後的 quota 用量快照（付費額外翻牌會扣一般 quota，用來同步訂閱計數）。
class PracticeDrawUsage {
  final int monthlyUsed;
  final int monthlyLimit;
  final int dailyUsed;
  final int dailyLimit;

  const PracticeDrawUsage({
    required this.monthlyUsed,
    required this.monthlyLimit,
    required this.dailyUsed,
    required this.dailyLimit,
  });

  int get monthlyRemaining =>
      (monthlyLimit - monthlyUsed).clamp(0, monthlyLimit);
  int get dailyRemaining => (dailyLimit - dailyUsed).clamp(0, dailyLimit);
}

/// `mode: draw_profile` 成功回應（200）。
class PracticeDrawResult {
  final PracticeDrawnProfile profile;
  final PracticeDrawReceipt draw;
  final PracticeDrawUsage usage;

  const PracticeDrawResult({
    required this.profile,
    required this.draw,
    required this.usage,
  });
}

typedef PracticeChatInvoker = Future<PracticeInvokeResponse> Function(
  String functionName, {
  required Map<String, dynamic> body,
});

class PracticeInvokeResponse {
  final int status;
  final dynamic data;
  const PracticeInvokeResponse({required this.status, this.data});
}

class PracticeApiException implements Exception {
  final String message;
  final int? status;
  PracticeApiException(this.message, {this.status});
  @override
  String toString() => 'PracticeApiException($status): $message';
}

class PracticeQuotaExceededException implements Exception {
  final String message;
  final int? used;
  final int? limit;
  final int? monthlyRemaining;
  final int? dailyRemaining;
  PracticeQuotaExceededException(
    this.message, {
    this.used,
    this.limit,
    this.monthlyRemaining,
    this.dailyRemaining,
  });
  @override
  String toString() => 'PracticeQuotaExceededException: $message';
}

class PracticeGenerationFailedException implements Exception {
  final String message;
  PracticeGenerationFailedException(this.message);
  @override
  String toString() => 'PracticeGenerationFailedException: $message';
}

class PracticeHintLimitException implements Exception {
  PracticeHintLimitException();
  @override
  String toString() => 'PracticeHintLimitException';
}

/// 練習已滿 20 則 AI 回覆（伺服器回 409）。前端應引導去拆解卡。
class PracticeSessionCompleteException implements Exception {
  PracticeSessionCompleteException();
  @override
  String toString() => 'PracticeSessionCompleteException';
}

/// 同一輪已用另一種模式進行中（伺服器回 409 `practice_mode_locked`）。前端應
/// 提示切回原本的模式，**絕不**當成場次已滿——誤標 sessionComplete 會引導
/// 「續聊同一位」開新 billing session 多扣費。
class PracticeModeLockedException implements Exception {
  PracticeModeLockedException();
  @override
  String toString() => 'PracticeModeLockedException';
}

/// Free 帳號續「同一位」需升級（伺服器回 402 `upgrade_required`）。
/// 前端必須明確導向付費牆／升級 CTA，不可落入 generic 失敗訊息。
class PracticeUpgradeRequiredException implements Exception {
  PracticeUpgradeRequiredException();
  @override
  String toString() => 'PracticeUpgradeRequiredException';
}

/// Free 帳號每日免費翻牌用完、且該層級不開放付費額外翻牌（伺服器回 402
/// `practice_draw_upgrade_required`）。前端必須導向付費牆，並可用 [extraCostMessages]
/// / [nextResetAt] 組出文案。與續同一位的 [PracticeUpgradeRequiredException] 分開。
class PracticeDrawUpgradeRequiredException implements Exception {
  final String message;
  final int? freeAllowance;
  final int? extraCostMessages;
  final String? nextResetAt;
  PracticeDrawUpgradeRequiredException({
    this.message = '',
    this.freeAllowance,
    this.extraCostMessages,
    this.nextResetAt,
  });
  @override
  String toString() => 'PracticeDrawUpgradeRequiredException: $message';
}

class PracticeChatApiService {
  PracticeChatApiService({PracticeChatInvoker? invoker})
      : _invoke = _mapFunctionExceptions(invoker ?? _defaultInvoker);

  final PracticeChatInvoker _invoke;

  /// functions_client 2.5.0 的 `invoke` 對非 2xx **一律 throw [FunctionException]**
  /// （status＋details＝decode 後的 body），不會把狀態碼帶回 [FunctionResponse]。
  /// 不接住的話，下面所有 402/429/409 的 status→typed exception 映射全是死碼，
  /// 錯誤一路落到 controller 的 catch-all 變通用「失敗了再試一次」。這裡把它
  /// 轉回 [PracticeInvokeResponse] 餵進既有映射（只包 practice-chat 這個 service）。
  static PracticeChatInvoker _mapFunctionExceptions(
    PracticeChatInvoker inner,
  ) {
    return (String fn, {required Map<String, dynamic> body}) async {
      try {
        return await inner(fn, body: body);
      } on FunctionException catch (e) {
        return PracticeInvokeResponse(status: e.status, data: e.details);
      }
    };
  }

  static const _functionName = 'practice-chat';

  Future<PracticeChatReply> sendMessage({
    required String sessionId,
    required PracticeProfileDto profile,
    required List<PracticeTurnDto> turns,
    int roundIndex = 1,
    String? visiblePracticeThreadId,
    PracticeLearningMode practiceMode = PracticeLearningMode.standard,
    int? temperatureScore,
    int? familiarityScore,
    PracticeHintReplyType? appliedHintType,
    String? appliedHintText,
  }) async {
    final normalizedAppliedHintText = appliedHintText?.trim();
    final response = await _invoke(
      _functionName,
      body: {
        'mode': 'chat',
        'sessionId': sessionId,
        'practiceMode': practiceMode.wireName,
        ...profile.toJson(),
        'turns': turns.map((t) => t.toJson()).toList(),
        'roundIndex': roundIndex,
        if (temperatureScore != null) 'temperatureScore': temperatureScore,
        if (familiarityScore != null) 'familiarityScore': familiarityScore,
        if (practiceMode == PracticeLearningMode.beginner &&
            appliedHintType != null)
          'appliedHintType': _hintReplyTypeWireName(appliedHintType),
        if (practiceMode == PracticeLearningMode.beginner &&
            appliedHintType != null &&
            normalizedAppliedHintText != null &&
            normalizedAppliedHintText.isNotEmpty)
          'appliedHintText': normalizedAppliedHintText,
        if (visiblePracticeThreadId != null)
          'visiblePracticeThreadId': visiblePracticeThreadId,
      },
    );
    final data = _guardStatus(response);
    // 防半渲染：reply 必須是非空字串，否則會 append 一顆空白 AI 泡並持久化。
    final rawReply = data['reply'];
    if (rawReply is! String || rawReply.trim().isEmpty) {
      throw PracticeGenerationFailedException('empty_reply');
    }
    return PracticeChatReply(
      reply: rawReply.trim(),
      aiTurnCount: _asInt(data['aiTurnCount']) ?? 0,
      sessionComplete: data['sessionComplete'] == true,
      costDeducted: _asInt(data['costDeducted']) ?? 0,
      monthlyRemaining: _asInt(data['monthlyRemaining']),
      dailyRemaining: _asInt(data['dailyRemaining']),
      temperature: _parseTemperature(data['temperature']),
      hintUsedCount: _asInt(data['hintUsedCount']),
    );
  }

  /// [requestId] 是 client 產的扣費 idempotency key（比照 opener）：同一次意圖
  /// 失敗重試沿用同 id，server 靠 (user, requestId) 去重傳輸層重試雙扣。
  Future<PracticeHintResult> requestHint({
    required String sessionId,
    required PracticeProfileDto profile,
    required List<PracticeTurnDto> turns,
    int roundIndex = 1,
    String? visiblePracticeThreadId,
    String? requestId,
  }) async {
    final response = await _invoke(
      _functionName,
      body: {
        'mode': 'hint',
        'sessionId': sessionId,
        if (requestId != null && requestId.trim().isNotEmpty)
          'requestId': requestId.trim(),
        'practiceMode': PracticeLearningMode.beginner.wireName,
        ...profile.toJson(),
        'turns': turns.map((t) => t.toJson()).toList(),
        'roundIndex': roundIndex,
        if (visiblePracticeThreadId != null)
          'visiblePracticeThreadId': visiblePracticeThreadId,
      },
    );
    final data = _guardHintStatus(response);
    return _parseHintResult(data);
  }

  Future<PracticeDebrief> requestDebrief({
    required String sessionId,
    required PracticeProfileDto profile,
    required List<PracticeTurnDto> turns,
    int roundIndex = 1,
    String? visiblePracticeThreadId,
  }) async {
    final response = await _invoke(
      _functionName,
      body: {
        'mode': 'debrief',
        'sessionId': sessionId,
        ...profile.toJson(),
        'turns': turns.map((t) => t.toJson()).toList(),
        'roundIndex': roundIndex,
        if (visiblePracticeThreadId != null)
          'visiblePracticeThreadId': visiblePracticeThreadId,
      },
    );
    final data = _guardStatus(response);
    final card = data['card'];
    if (card is! Map) {
      throw PracticeGenerationFailedException('malformed_debrief');
    }
    return PracticeDebrief(
      summary: _asString(card['summary']),
      strengths: _asStringList(card['strengths']),
      watchouts: _asStringList(card['watchouts']),
      suggestedLine: _asString(card['suggestedLine']),
      vibe: _asString(card['vibe']).isEmpty ? '中性' : _asString(card['vibe']),
      monthlyRemaining: _asInt(data['monthlyRemaining']),
      dailyRemaining: _asInt(data['dailyRemaining']),
    );
  }

  /// 每日翻牌：server 選一位新對象並原子扣費（免費額度／付費額外）。
  /// [requestId] 是 client 產的冪等 key；[currentProfileId] 帶上目前這位以便排除
  /// （換一位不換回自己）。402 → upgrade required；429 → quota exceeded。
  Future<PracticeDrawResult> drawProfile({
    required String requestId,
    String? currentProfileId,
    String? visiblePracticeThreadId,
  }) async {
    final response = await _invoke(
      _functionName,
      body: {
        'mode': 'draw_profile',
        'requestId': requestId,
        if (currentProfileId != null) 'currentProfileId': currentProfileId,
        if (visiblePracticeThreadId != null)
          'visiblePracticeThreadId': visiblePracticeThreadId,
        // 宣告本 build 的 catalog 人數：server 只從前 n 位抽，避免舊 build 抽到
        // 自己反查不到的新角色（會 fallback 渲染成第一位且額度白扣）。不硬編 100，
        // catalog 擴充/回滾時自動跟上。
        'catalogSize': practiceGirlProfiles.length,
      },
    );

    switch (response.status) {
      case 200:
        final data = response.data;
        if (data is! Map) {
          throw PracticeGenerationFailedException('malformed_response');
        }
        return _parseDrawResult(Map<String, dynamic>.from(data));
      case 402:
        final data = response.data is Map ? response.data as Map : const {};
        final draw = data['draw'] is Map ? data['draw'] as Map : const {};
        throw PracticeDrawUpgradeRequiredException(
          message: (data['message'] as String?) ?? '',
          freeAllowance: _asInt(draw['freeAllowance']),
          extraCostMessages: _asInt(draw['extraCostMessages']),
          nextResetAt: draw['nextResetAt'] as String?,
        );
      case 429:
        final data = response.data is Map ? response.data as Map : const {};
        throw PracticeQuotaExceededException(
          (data['message'] as String?) ?? '額度已用完',
          used: _asInt(data['used']),
          limit: _asInt(data['limit']),
          monthlyRemaining: _asInt(data['monthlyRemaining']),
          dailyRemaining: _asInt(data['dailyRemaining']),
        );
      default:
        if (response.status >= 500) {
          throw PracticeGenerationFailedException(
            'practice_draw_failed_${response.status}',
          );
        }
        final data = response.data is Map ? response.data as Map : const {};
        throw PracticeApiException(
          (data['error'] as String?) ?? 'practice_draw_error',
          status: response.status,
        );
    }
  }

  PracticeDrawResult _parseDrawResult(Map<String, dynamic> data) {
    final profile = data['profile'];
    final draw = data['draw'];
    final usage = data['usage'];
    if (profile is! Map || draw is! Map || usage is! Map) {
      throw PracticeGenerationFailedException('malformed_draw');
    }
    final profileId = profile['profileId'];
    if (profileId is! String || profileId.isEmpty) {
      throw PracticeGenerationFailedException('malformed_draw_profile');
    }
    return PracticeDrawResult(
      profile: PracticeDrawnProfile(
        profileId: profileId,
        nameId: _asString(profile['nameId']),
        professionId: _asString(profile['professionId']),
        photoId: _asString(profile['photoId']),
        personaId: _asString(profile['personaId']),
      ),
      draw: PracticeDrawReceipt(
        costMessages: _asInt(draw['costMessages']) ?? 0,
        freeAllowance: _asInt(draw['freeAllowance']) ?? 0,
        freeUsed: _asInt(draw['freeUsed']) ?? 0,
        freeRemaining: _asInt(draw['freeRemaining']) ?? 0,
        extraCostMessages: _asInt(draw['extraCostMessages']) ?? 0,
        nextResetAt: _asString(draw['nextResetAt']),
      ),
      usage: PracticeDrawUsage(
        monthlyUsed: _asInt(usage['monthlyUsed']) ?? 0,
        monthlyLimit: _asInt(usage['monthlyLimit']) ?? 0,
        dailyUsed: _asInt(usage['dailyUsed']) ?? 0,
        dailyLimit: _asInt(usage['dailyLimit']) ?? 0,
      ),
    );
  }

  PracticeHintResult _parseHintResult(Map<String, dynamic> data) {
    final rawReplies = data['replies'];
    final coaching = data['coaching'];
    if (rawReplies is! List ||
        rawReplies.length != 2 ||
        coaching is! String ||
        coaching.trim().isEmpty) {
      throw PracticeGenerationFailedException('malformed_hint');
    }

    final replies = rawReplies.map(_parseHintReply).toList();
    return PracticeHintResult(
      replies: replies,
      coaching: coaching.trim(),
      costDeducted: _asInt(data['costDeducted']) ?? 0,
      hintUsedCount: _asInt(data['hintUsedCount']) ?? 0,
      monthlyRemaining: _asInt(data['monthlyRemaining']),
      dailyRemaining: _asInt(data['dailyRemaining']),
    );
  }

  PracticeHintReply _parseHintReply(dynamic raw) {
    if (raw is! Map) {
      throw PracticeGenerationFailedException('malformed_hint');
    }
    final type = _parseHintReplyType(raw['type']);
    final label = raw['label'];
    final text = raw['text'];
    if (type == null ||
        label is! String ||
        label.trim().isEmpty ||
        text is! String ||
        text.trim().isEmpty) {
      throw PracticeGenerationFailedException('malformed_hint');
    }
    return PracticeHintReply(
      type: type,
      label: label.trim(),
      text: text.trim(),
    );
  }

  PracticeHintReplyType? _parseHintReplyType(dynamic value) {
    return switch (value) {
      'warm_up' => PracticeHintReplyType.warmUp,
      'steady' => PracticeHintReplyType.steady,
      _ => null,
    };
  }

  String _hintReplyTypeWireName(PracticeHintReplyType type) {
    return switch (type) {
      PracticeHintReplyType.warmUp => 'warm_up',
      PracticeHintReplyType.steady => 'steady',
    };
  }

  PracticeTemperature? _parseTemperature(dynamic raw) {
    if (raw == null) return null;
    if (raw is! Map) {
      throw PracticeGenerationFailedException('malformed_temperature');
    }
    final score = _asInt(raw['score']);
    final delta = _asInt(raw['delta']);
    final band = raw['band'];
    final reason = raw['reason'];
    final familiarityScore = _asInt(raw['familiarityScore']);
    final familiarityDelta = _asInt(raw['familiarityDelta']);
    final stageLabel = raw['stageLabel'];
    if (score == null ||
        delta == null ||
        band is! String ||
        reason is! String) {
      throw PracticeGenerationFailedException('malformed_temperature');
    }
    return PracticeTemperature(
      score: score,
      delta: delta,
      band: band,
      reason: reason,
      familiarityScore: familiarityScore,
      familiarityDelta: familiarityDelta,
      stageLabel: stageLabel is String ? stageLabel : null,
    );
  }

  Map<String, dynamic> _guardHintStatus(PracticeInvokeResponse response) {
    if (response.status == 403) {
      final data = response.data is Map ? response.data as Map : const {};
      if (data['error'] == 'practice_hint_limit') {
        throw PracticeHintLimitException();
      }
    }
    return _guardStatus(response);
  }

  /// 把 HTTP 狀態映射成例外；200 回傳 data map。
  Map<String, dynamic> _guardStatus(PracticeInvokeResponse response) {
    switch (response.status) {
      case 200:
        final data = response.data;
        if (data is Map) return Map<String, dynamic>.from(data);
        throw PracticeGenerationFailedException('malformed_response');
      case 429:
        final data = response.data is Map ? response.data as Map : const {};
        // server per-user 模型限流不是訂閱額度：絕不 throw quota 例外
        // （那會標 quotaExceeded 誤導升級），走 ApiException 顯示稍等文案。
        if (data['code'] == 'MODEL_RATE_LIMITED') {
          throw PracticeApiException(
            (data['message'] as String?) ?? '請求太頻繁，請稍後再試。',
            status: 429,
          );
        }
        throw PracticeQuotaExceededException(
          (data['message'] as String?) ?? '額度已用完',
          used: _asInt(data['used']),
          limit: _asInt(data['limit']),
          monthlyRemaining: _asInt(data['monthlyRemaining']),
          dailyRemaining: _asInt(data['dailyRemaining']),
        );
      case 409:
        // 409 依 body error code 分流：mode locked 是「切回原模式」而非場次已滿；
        // 讀不到 body 一律回退場次已滿（既有行為）。
        final conflict = response.data is Map ? response.data as Map : const {};
        if (conflict['error'] == 'practice_mode_locked') {
          throw PracticeModeLockedException();
        }
        throw PracticeSessionCompleteException();
      case 402:
        throw PracticeUpgradeRequiredException();
      default:
        if (response.status >= 500) {
          final data = response.data is Map ? response.data as Map : const {};
          final error = data['error'];
          throw PracticeGenerationFailedException(
            error is String && error.trim().isNotEmpty
                ? error.trim()
                : 'practice_generation_failed_${response.status}',
          );
        }
        final data = response.data is Map ? response.data as Map : const {};
        throw PracticeApiException(
          (data['error'] as String?) ?? 'practice_api_error',
          status: response.status,
        );
    }
  }

  static String _asString(dynamic v) => v is String ? v : '';

  static int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return null;
  }

  static List<String> _asStringList(dynamic v) {
    if (v is List) {
      return v.whereType<String>().toList();
    }
    return const [];
  }
}

Future<PracticeInvokeResponse> _defaultInvoker(
  String fn, {
  required Map<String, dynamic> body,
}) async {
  final res = await Supabase.instance.client.functions.invoke(fn, body: body);
  return PracticeInvokeResponse(status: res.status, data: res.data);
}
