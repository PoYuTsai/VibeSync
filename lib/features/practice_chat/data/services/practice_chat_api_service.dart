import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_pending_debrief_store.dart';
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

class PracticeAppliedHintTurnDto {
  final int turnIndex;
  final PracticeHintReplyType type;
  final String originalHintText;
  final String sentText;
  final bool exact;

  const PracticeAppliedHintTurnDto({
    required this.turnIndex,
    required this.type,
    required this.originalHintText,
    required this.sentText,
    required this.exact,
  });

  Map<String, dynamic> toJson() => {
        'turnIndex': turnIndex,
        'type': switch (type) {
          PracticeHintReplyType.warmUp => 'warm_up',
          PracticeHintReplyType.steady => 'steady',
        },
        'originalHintText': originalHintText,
        'sentText': sentText,
        'exact': exact,
      };
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
class PracticePartnerState {
  final String mood;
  final String innerThought;

  const PracticePartnerState({
    required this.mood,
    required this.innerThought,
  });

  Map<String, dynamic> toJson() => {
        'mood': mood,
        'innerThought': innerThought,
      };
}

class PracticeChatReply {
  final String reply;
  final int aiTurnCount;
  final bool sessionComplete;
  final int costDeducted;
  final int? monthlyRemaining;
  final int? dailyRemaining;
  final PracticeTemperature? temperature;
  final PracticePartnerState? partnerState;
  final int? hintUsedCount;

  const PracticeChatReply({
    required this.reply,
    required this.aiTurnCount,
    required this.sessionComplete,
    required this.costDeducted,
    this.monthlyRemaining,
    this.dailyRemaining,
    this.temperature,
    this.partnerState,
    this.hintUsedCount,
  });
}

/// debrief 模式成功回應（教練拆解卡）。
class PracticeGameBreakdown {
  final String? phaseReached;
  final String? missedVariable;
  final String? failureState;
  final String? nextFirstLine;
  final String? inviteDirection;

  const PracticeGameBreakdown({
    this.phaseReached,
    this.missedVariable,
    this.failureState,
    this.nextFirstLine,
    this.inviteDirection,
  });

  bool get isEmpty =>
      (phaseReached?.trim().isEmpty ?? true) &&
      (missedVariable?.trim().isEmpty ?? true) &&
      (failureState?.trim().isEmpty ?? true) &&
      (nextFirstLine?.trim().isEmpty ?? true) &&
      (inviteDirection?.trim().isEmpty ?? true);
}

class PracticeDebrief {
  final String summary;
  final List<String> strengths;
  final List<String> watchouts;
  final String suggestedLine;
  final String vibe;
  final String? dateChance;
  final String? dateChanceReason;
  final String? nextInviteMove;
  final PracticeGameBreakdown? gameBreakdown;
  final int? monthlyRemaining;
  final int? dailyRemaining;

  /// Transport idempotency key. The controller clears it only after the card
  /// is durably persisted; keeping it out of the UI/domain serialization
  /// avoids stranding a server-completed card during an app-kill window.
  final String? idempotencyRequestId;

  const PracticeDebrief({
    required this.summary,
    required this.strengths,
    required this.watchouts,
    required this.suggestedLine,
    required this.vibe,
    this.dateChance,
    this.dateChanceReason,
    this.nextInviteMove,
    this.gameBreakdown,
    this.monthlyRemaining,
    this.dailyRemaining,
    this.idempotencyRequestId,
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
  PracticeChatApiService({
    PracticeChatInvoker? invoker,
    Duration debriefRequestTimeout = const Duration(seconds: 35),
    String Function()? requestIdFactory,
    PracticePendingDebriefStore? pendingDebriefStore,
  })  : _invoke = _mapFunctionExceptions(invoker ?? _defaultInvoker),
        _debriefRequestTimeout = debriefRequestTimeout,
        _requestIdFactory = requestIdFactory ?? _newRequestId,
        _pendingDebriefStore =
            pendingDebriefStore ?? InMemoryPracticePendingDebriefStore();

  final PracticeChatInvoker _invoke;
  final Duration _debriefRequestTimeout;
  final String Function() _requestIdFactory;
  final PracticePendingDebriefStore _pendingDebriefStore;

  PracticePendingDebrief? _pendingDebriefRequest;

  static String _newRequestId() => const Uuid().v4();

  static String _payloadDigest(Map<String, dynamic> intentBody) =>
      sha256.convert(utf8.encode(jsonEncode(intentBody))).toString();

  Future<String> _requestIdForDebrief({
    required String sessionId,
    required String payloadDigest,
  }) async {
    bool matches(PracticePendingDebrief pending) =>
        pending.sessionId == sessionId &&
        pending.payloadDigest == payloadDigest;

    final memoryPending = _pendingDebriefRequest;
    if (memoryPending != null && matches(memoryPending)) {
      return memoryPending.requestId;
    }

    final stored = _pendingDebriefStore.load();
    final requestId = stored != null && matches(stored)
        ? stored.requestId
        : _requestIdFactory();
    final pending = PracticePendingDebrief(
      sessionId: sessionId,
      payloadDigest: payloadDigest,
      requestId: requestId,
    );
    _pendingDebriefRequest = pending;
    // 在送出 request 前持久化，縮到最小的「server 已 claim、client 尚未存 id」窗口。
    // store 自身 fail-open；box 不可用時仍會靠記憶體維持 process-lifetime 冪等。
    await _pendingDebriefStore.save(pending);
    return requestId;
  }

  Future<void> _clearPendingDebrief({
    required String sessionId,
    required String requestId,
  }) async {
    if (_pendingDebriefRequest?.sessionId == sessionId &&
        _pendingDebriefRequest?.requestId == requestId) {
      _pendingDebriefRequest = null;
    }
    // 晚到的舊 response 不得清掉較新的 pending request。
    try {
      final stored = _pendingDebriefStore.load();
      if (stored?.sessionId == sessionId && stored?.requestId == requestId) {
        await _pendingDebriefStore.clear();
      }
    } catch (_) {
      // Persistence cleanup is fail-open. A stale key can only replay the same
      // completed response and is overwritten by the next distinct intent.
    }
  }

  /// A successful HTTP response is not enough to retire the requestId: the app
  /// may be killed before the debrief card reaches Hive. The controller calls
  /// this only after its session persistence succeeds.
  Future<void> confirmDebriefPersisted({
    required String sessionId,
    required String requestId,
  }) =>
      _clearPendingDebrief(sessionId: sessionId, requestId: requestId);

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
    String? memorySummary,
    PracticePartnerState? continuationPartnerState,
    PracticeHintReplyType? appliedHintType,
    String? appliedHintText,
  }) async {
    final normalizedAppliedHintText = appliedHintText?.trim();
    final normalizedMemorySummary = memorySummary?.trim();
    final response = await _invoke(
      _functionName,
      body: {
        'mode': 'chat',
        'sessionId': sessionId,
        'practiceMode': practiceMode.wireName,
        ...profile.toJson(),
        'turns': turns.map((t) => t.toJson()).toList(),
        if (normalizedMemorySummary != null &&
            normalizedMemorySummary.isNotEmpty)
          'memorySummary': normalizedMemorySummary,
        'roundIndex': roundIndex,
        if (temperatureScore != null) 'temperatureScore': temperatureScore,
        if (familiarityScore != null) 'familiarityScore': familiarityScore,
        if (practiceMode.usesAssistedLearning && appliedHintType != null)
          'appliedHintType': _hintReplyTypeWireName(appliedHintType),
        if (practiceMode.usesAssistedLearning &&
            appliedHintType != null &&
            normalizedAppliedHintText != null &&
            normalizedAppliedHintText.isNotEmpty)
          'appliedHintText': normalizedAppliedHintText,
        if (visiblePracticeThreadId != null)
          'visiblePracticeThreadId': visiblePracticeThreadId,
        if (continuationPartnerState != null)
          'continuationPartnerState': continuationPartnerState.toJson(),
      },
    );
    final data = _guardStatus(response);
    // 防半渲染：reply 必須是非空字串，否則會 append 一顆空白 AI 泡並持久化。
    final rawReply = data['reply'];
    if (rawReply is! String || rawReply.trim().isEmpty) {
      throw PracticeGenerationFailedException('empty_reply');
    }
    final rawTemperature = data['temperature'];
    final rawPartnerState = data['partnerState'];
    final nestedPartnerState = rawPartnerState == null && rawTemperature is Map
        ? rawTemperature['partnerState']
        : null;
    return PracticeChatReply(
      reply: rawReply.trim(),
      aiTurnCount: _asInt(data['aiTurnCount']) ?? 0,
      sessionComplete: data['sessionComplete'] == true,
      costDeducted: _asInt(data['costDeducted']) ?? 0,
      monthlyRemaining: _asInt(data['monthlyRemaining']),
      dailyRemaining: _asInt(data['dailyRemaining']),
      temperature: _parseTemperature(rawTemperature),
      partnerState: _parsePartnerState(rawPartnerState ?? nestedPartnerState),
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
    String? memorySummary,
    PracticePartnerState? continuationPartnerState,
    String? requestId,
    PracticeLearningMode practiceMode = PracticeLearningMode.beginner,
  }) async {
    final normalizedMemorySummary = memorySummary?.trim();
    final response = await _invoke(
      _functionName,
      body: {
        'mode': 'hint',
        'sessionId': sessionId,
        if (requestId != null && requestId.trim().isNotEmpty)
          'requestId': requestId.trim(),
        'practiceMode': practiceMode.wireName,
        ...profile.toJson(),
        'turns': turns.map((t) => t.toJson()).toList(),
        if (normalizedMemorySummary != null &&
            normalizedMemorySummary.isNotEmpty)
          'memorySummary': normalizedMemorySummary,
        'roundIndex': roundIndex,
        if (visiblePracticeThreadId != null)
          'visiblePracticeThreadId': visiblePracticeThreadId,
        if (continuationPartnerState != null)
          'continuationPartnerState': continuationPartnerState.toJson(),
      },
    );
    final data = _guardHintStatus(response);
    return _parseHintResult(data);
  }

  Future<PracticeDebrief> requestDebrief({
    required String sessionId,
    required PracticeProfileDto profile,
    required List<PracticeTurnDto> turns,
    PracticeLearningMode practiceMode = PracticeLearningMode.standard,
    int roundIndex = 1,
    String? visiblePracticeThreadId,
    String? memorySummary,
    PracticePartnerState? continuationPartnerState,
    List<PracticeAppliedHintTurnDto> appliedHintTurns = const [],
  }) async {
    final normalizedMemorySummary = memorySummary?.trim();
    final normalizedAppliedHintTurns = appliedHintTurns
        .where((hint) =>
            hint.turnIndex >= 0 &&
            hint.originalHintText.trim().isNotEmpty &&
            hint.sentText.trim().isNotEmpty)
        .take(5)
        .toList(growable: false);
    // 冪等指紋只吃跨 controller/App 重建後仍可還原的場次事實。
    // appliedHintTurns 是 controller RAM side-channel；memory/partnerState 也屬衍生
    // context。把它們放進 digest 會讓同一場 lost-response retry 在重建後換 ID。
    final durableIntentBody = <String, dynamic>{
      'mode': 'debrief',
      'sessionId': sessionId,
      'practiceMode': practiceMode.wireName,
      ...profile.toJson(),
      'turns': turns.map((t) => t.toJson()).toList(),
      'roundIndex': roundIndex,
      if (visiblePracticeThreadId != null)
        'visiblePracticeThreadId': visiblePracticeThreadId,
    };
    final intentBody = <String, dynamic>{
      ...durableIntentBody,
      if (normalizedMemorySummary != null && normalizedMemorySummary.isNotEmpty)
        'memorySummary': normalizedMemorySummary,
      if (continuationPartnerState != null)
        'continuationPartnerState': continuationPartnerState.toJson(),
      if (practiceMode.usesAssistedLearning &&
          normalizedAppliedHintTurns.isNotEmpty)
        'appliedHintTurns':
            normalizedAppliedHintTurns.map((hint) => hint.toJson()).toList(),
    };
    final requestId = await _requestIdForDebrief(
      sessionId: sessionId,
      payloadDigest: _payloadDigest(durableIntentBody),
    );
    final response = await _invoke(
      _functionName,
      body: {
        ...intentBody,
        'requestId': requestId,
      },
    ).timeout(_debriefRequestTimeout);
    // 一般 4xx 是明確拒絕，下一次屬於新意圖；429 只代表目前限流，前一輪同 id
    // 仍可能已 claim 未完成，所以和 timeout、網路例外、5xx、malformed 200 一樣
    // 保留 id，避免下次換 id 又吃一個 debrief 次數。425 表示同 id 還在 server
    // 生成中，也必須保留，稍後才能 replay 同一份結果。
    if (response.status >= 400 &&
        response.status < 500 &&
        response.status != 429 &&
        response.status != 425) {
      await _clearPendingDebrief(
        sessionId: sessionId,
        requestId: requestId,
      );
    }
    final data = _guardStatus(response);
    final card = data['card'];
    if (card is! Map) {
      throw PracticeGenerationFailedException('malformed_debrief');
    }
    final debrief = PracticeDebrief(
      summary: _asString(card['summary']),
      strengths: _asStringList(card['strengths']),
      watchouts: _asStringList(card['watchouts']),
      suggestedLine: _asString(card['suggestedLine']),
      vibe: _asString(card['vibe']).isEmpty ? '中性' : _asString(card['vibe']),
      dateChance: _asNullableString(card['dateChance']),
      dateChanceReason: _asNullableString(card['dateChanceReason']),
      nextInviteMove: _asNullableString(card['nextInviteMove']),
      gameBreakdown: practiceMode == PracticeLearningMode.game
          ? _parseGameBreakdown(card['gameBreakdown'])
          : null,
      monthlyRemaining: _asInt(data['monthlyRemaining']),
      dailyRemaining: _asInt(data['dailyRemaining']),
      idempotencyRequestId: requestId,
    );
    return debrief;
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

  PracticePartnerState? _parsePartnerState(dynamic raw) {
    if (raw == null) return null;
    if (raw is! Map) {
      throw PracticeGenerationFailedException('malformed_partner_state');
    }
    final mood = raw['mood'];
    final innerThought = raw['innerThought'];
    if (mood is! String || !_validPartnerMoods.contains(mood)) {
      throw PracticeGenerationFailedException('malformed_partner_state');
    }
    return PracticePartnerState(
      mood: mood,
      innerThought: innerThought is String ? innerThought.trim() : '',
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

  static String? _asNullableString(dynamic v) {
    if (v is! String) return null;
    final trimmed = v.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static PracticeGameBreakdown? _parseGameBreakdown(dynamic v) {
    if (v is! Map) return null;
    final breakdown = PracticeGameBreakdown(
      phaseReached: _asNullableString(v['phaseReached']),
      missedVariable: _asNullableString(v['missedVariable']),
      failureState: _asNullableString(v['failureState']),
      nextFirstLine: _asNullableString(v['nextFirstLine']),
      inviteDirection: _asNullableString(v['inviteDirection']),
    );
    return breakdown.isEmpty ? null : breakdown;
  }

  static const Set<String> _validPartnerMoods = {
    'neutral',
    'curious',
    'amused',
    'comfortable',
    'guarded',
    'annoyed',
  };

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
