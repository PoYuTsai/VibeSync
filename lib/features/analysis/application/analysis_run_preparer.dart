/// AnalyzeChat 送出前的請求組裝：驗證、歷史摘要、脈絡（partner／風格／
/// 已知聯絡人名）、內容修訂快照。主分析與潤飾／微調共用同一套組裝，
/// 行為逐字沿用拆分前 AnalysisScreen 的實作。
library;

import 'dart:convert';

import '../../../core/services/message_calculator.dart';
import '../../conversation/domain/entities/conversation.dart';
import '../../conversation/domain/entities/message.dart';
import '../../conversation/domain/entities/session_context.dart';
import '../../conversation/domain/services/conversation_content_revision.dart';
import '../domain/entities/previous_round_context.dart';
import '../domain/services/screenshot_recognition_helper.dart';
import 'ports/conversation_memory_port.dart';

/// 主分析組裝失敗的可判別原因；錯誤文案由畫面層決定。
enum AnalysisRunPrepareFailure {
  /// 對話沒有任何訊息。
  emptyConversation,

  /// 沒有任何一則對方訊息可分析。
  noIncomingReply,
}

/// 主分析一次 run 的完整請求素材。
class AnalysisRunPreparation {
  final List<Message> requestMessages;
  final String? conversationSummary;
  final String? partnerSummary;
  final String? effectiveStyleContext;
  final String? knownContactName;
  final SessionContext? sessionContext;

  /// Conversation 在 run 起點所屬的對象。完成前若被重新分配，結果必須
  /// 視為 stale，不能把舊對象脈絡生成的結果寫到新對象。
  final String? conversationPartnerId;

  /// 這次送出的情境是否為既有伴侶。與 event 一起凍結，避免日後修改
  /// Conversation 情境時，把舊 opening 改寫成／取消「重新連線」。
  final bool isReconnectContext;

  /// 上一個 partner-scoped 有效互動階段（弱先驗，閉環規則 8）；
  /// 從未有有效階段時為 null，絕不偽造。
  final String? previousStage;

  /// 本次分析片段在 [requestMessages] 的 0-based 起點。起點前只供脈絡
  /// 消歧；投入度只評起點後「她」的可觀察投入。
  final int analysisFragmentStartIndex;

  /// 本次實際納入分析的訊息數（clamp 過 limit 的 sourceMessages 長度）。
  final int analyzedMessageCount;

  /// 送出前同步擷取的內容修訂：同數量編輯也能被 stale 守門認出。
  final String contentRevision;

  /// 上一輪脈絡（同一個對象上一次的 v3 結果，Eric 2026-10-18）；沒有就不帶。
  final PreviousRoundContext? previousRound;

  /// 只分析最後 2000 字（Onboarding 第 15 步）才有值：整段請求的計費字數，也就是整段
  /// 分析成功後會存的字數基準。有值時 [requestMessages] 只是整段的尾段：送出時不帶上次
  /// 的基準（伺服器把尾段整段當新內容算錢），成功後的字數基準存這個數字，下次續析只算
  /// 之後新增的字——跳過的那段不再算錢，尾段也不會再算一次。一般分析是 null。
  final int? fullRequestCharBaseline;

  /// 這次只送整段的尾段（見 [fullRequestCharBaseline]）。
  bool get isTailOnly => fullRequestCharBaseline != null;

  const AnalysisRunPreparation({
    required this.requestMessages,
    required this.conversationSummary,
    required this.partnerSummary,
    required this.effectiveStyleContext,
    required this.knownContactName,
    required this.sessionContext,
    required this.conversationPartnerId,
    required this.isReconnectContext,
    this.previousStage,
    required this.analysisFragmentStartIndex,
    required this.analyzedMessageCount,
    required this.contentRevision,
    this.previousRound,
    this.fullRequestCharBaseline,
  });
}

/// [AnalysisRunPreparer.gate] 的同步結果：驗證結論＋本次 run 的
/// 訊息切片與內容修訂快照。全程無 await，呼叫端可以在這之後、
/// [AnalysisRunPreparer.assemble] 之前插入自己的同步守門。
class AnalysisRunGate {
  final AnalysisRunPrepareFailure? failure;
  final List<Message>? messagesForAnalysis;
  final int? analyzedMessageCount;
  final String? contentRevision;

  const AnalysisRunGate.failure(AnalysisRunPrepareFailure this.failure)
      : messagesForAnalysis = null,
        analyzedMessageCount = null,
        contentRevision = null;

  const AnalysisRunGate.passed({
    required List<Message> this.messagesForAnalysis,
    required int this.analyzedMessageCount,
    required String this.contentRevision,
  }) : failure = null;
}

/// 潤飾／微調共用的請求脈絡（全量訊息、無 reply 驗證、無修訂快照）。
class AuxiliaryAnalysisContext {
  final List<Message> requestMessages;
  final String? conversationSummary;
  final String? partnerSummary;
  final String? effectiveStyleContext;
  final String? knownContactName;

  const AuxiliaryAnalysisContext({
    required this.requestMessages,
    required this.conversationSummary,
    required this.partnerSummary,
    required this.effectiveStyleContext,
    required this.knownContactName,
  });
}

class AnalysisRunPreparer {
  static const _snapshotClientMetaKey = '__vibesync_snapshot_meta_v1';
  static const _snapshotSessionContextKey = 'sessionContext';

  AnalysisRunPreparer({
    required ConversationMemoryPort memory,
    required String? Function(Conversation conversation) resolvePartnerSummary,
    required String? Function(Conversation conversation)
        resolveEffectiveStyleContext,
    String? Function(Conversation conversation)? resolvePreviousStage,
    SessionContext? Function(Conversation conversation)? resolveSessionContext,
    PreviousRoundContext? Function(Conversation conversation)?
        resolvePreviousRound,
  })  : _memory = memory,
        _resolvePartnerSummary = resolvePartnerSummary,
        _resolveEffectiveStyleContext = resolveEffectiveStyleContext,
        _resolvePreviousStage = resolvePreviousStage,
        _resolveSessionContext = resolveSessionContext,
        _resolvePreviousRound = resolvePreviousRound;

  final ConversationMemoryPort _memory;
  final String? Function(Conversation conversation) _resolvePartnerSummary;
  final String? Function(Conversation conversation)
      _resolveEffectiveStyleContext;

  /// 上一個 partner-scoped 有效 stage（弱先驗）；composition root 注入，
  /// null＝呼叫端不提供連續性（輔助流程用不到）。
  final String? Function(Conversation conversation)? _resolvePreviousStage;
  final SessionContext? Function(Conversation conversation)?
      _resolveSessionContext;

  /// 上一輪脈絡（composition root 注入）；null＝不帶（輔助流程用不到）。
  final PreviousRoundContext? Function(Conversation conversation)?
      _resolvePreviousRound;

  /// 主分析同步守門：驗證（空對話、無對方訊息）、切出本次要分析的訊息、
  /// 同步擷取內容修訂——修訂必須在任何 await 之前取，old run 才不可能
  /// 蓋掉同數量的新編輯。
  AnalysisRunGate gate({
    required Conversation conversation,
    int? analysisMessageLimit,
  }) {
    if (conversation.messages.isEmpty) {
      return const AnalysisRunGate.failure(
        AnalysisRunPrepareFailure.emptyConversation,
      );
    }

    final clampedAnalysisMessageLimit =
        analysisMessageLimit?.clamp(0, conversation.messages.length).toInt();
    final sourceMessages = clampedAnalysisMessageLimit == null
        ? conversation.messages
        : conversation.messages
            .take(clampedAnalysisMessageLimit)
            .toList(growable: false);

    final messagesForAnalysis = _buildMessagesForReplyAnalysis(sourceMessages);
    if (messagesForAnalysis == null) {
      return const AnalysisRunGate.failure(
        AnalysisRunPrepareFailure.noIncomingReply,
      );
    }

    return AnalysisRunGate.passed(
      messagesForAnalysis: messagesForAnalysis,
      analyzedMessageCount: sourceMessages.length,
      contentRevision: conversationContentRevision(conversation),
    );
  }

  /// 分析鈕旁那一行的同步預覽（主審 r1 P2）：跟 [assemble] 同一套訊息切片（有歷史
  /// 摘要時只送最近幾輪），但不產生摘要文字。用它算的計費則數就是實際送出的則數。
  List<Message> previewRequestMessages({
    required Conversation conversation,
    required AnalysisRunGate gate,
  }) {
    final baseMessages = gate.messagesForAnalysis!;
    return _expectsHistoricalSummary(conversation)
        ? _clipToRecentRounds(baseMessages)
        : baseMessages;
  }

  /// 主分析請求組裝（通過 [gate] 之後）：摘要感知訊息切片＋脈絡解析。
  Future<AnalysisRunPreparation> assemble({
    required Conversation conversation,
    required AnalysisRunGate gate,
  }) async {
    final context = await _buildSummaryAwareContext(
      conversation: conversation,
      baseMessages: gate.messagesForAnalysis!,
    );
    final isNewFragment =
        conversation.lastAnalyzedMessageCount != gate.analyzedMessageCount;
    final analysisFragmentStartIndex = _analysisFragmentStartIndex(
      baseMessages: gate.messagesForAnalysis!,
      requestMessages: context.requestMessages,
      previousAnalyzedCount: conversation.lastAnalyzedMessageCount,
      isNewFragment: isNewFragment,
    );
    final frozenSessionContext = isNewFragment
        ? (found: false, value: null)
        : _sessionContextFromSnapshot(
            conversation.lastAnalysisSnapshotJson,
          );
    final sessionContext = isNewFragment
        ? (_resolveSessionContext?.call(conversation) ??
            conversation.sessionContext)
        : frozenSessionContext.found
            ? frozenSessionContext.value
            : conversation.sessionContext;
    final normalizedPartnerId = conversation.partnerId?.trim();

    return AnalysisRunPreparation(
      requestMessages: context.requestMessages,
      conversationSummary: context.conversationSummary,
      partnerSummary: _resolvePartnerSummary(conversation),
      // Product boundary: About Me / style chips do not enter AnalyzeChat's
      // score, stage, or five reply-style decision. Auxiliary composition
      // remains a separate path; the current profile builder also returns
      // null there under the existing Coach-1:1-only product decision.
      effectiveStyleContext: null,
      knownContactName: _knownContactName(conversation),
      // New fragments use the partner card's latest defaults. An exact
      // same-boundary rerun uses the context frozen inside its snapshot, so a
      // later card edit cannot rewrite that historical fragment. Legacy
      // snapshots without this metadata fall back to Conversation context.
      sessionContext: sessionContext,
      conversationPartnerId:
          normalizedPartnerId == null || normalizedPartnerId.isEmpty
              ? null
              : normalizedPartnerId,
      isReconnectContext:
          sessionContext?.meetingContext == MeetingContext.committedPartner,
      previousStage: _resolvePreviousStage?.call(conversation),
      analysisFragmentStartIndex: analysisFragmentStartIndex,
      analyzedMessageCount: gate.analyzedMessageCount!,
      contentRevision: gate.contentRevision!,
      previousRound: _resolvePreviousRound?.call(conversation),
    );
  }

  /// 只分析最後 2000 字（Onboarding 第 15 步）：從 [full] 的請求最後往前一則一則加，
  /// 取計費字數不超過 [maxBillableChars] 的最長尾段，回一份只送這段的請求。現有的
  /// `analysisMessageLimit` 是取前 N 則，這裡是取最後那段。
  ///
  /// 計費字數用伺服器同一套算法（MessageCalculator 跟 billing.ts 對拍：trim 後加總；
  /// F04 最後面他傳的、上限內不算）。送出時不帶上次的基準（見
  /// [AnalysisRunPreparation.fullRequestCharBaseline]），伺服器算的計費字數就是這段的
  /// 計費字數，不超過 2000 字，一定落在 10 則以內。
  ///
  /// 回 null＝沒有這個選項：整段本來就不超過（不用截）、沒有她的訊息，或從她最後一則
  /// 開始就超過（她那一則、或之後他傳的要算錢的那幾則太長）。不截斷單則：截了會改到
  /// 她說的話（Onboarding 第 15 步定案）。
  AnalysisRunPreparation? tailOnly(
    AnalysisRunPreparation full, {
    int maxBillableChars = MessageCalculator.softCapBandMaxChars,
  }) {
    if (full.isTailOnly) return null;
    final messages = full.requestMessages;
    final start = _tailStart(messages, maxBillableChars);
    if (start == null || start == 0) return null;
    final tail = List<Message>.unmodifiable(messages.sublist(start));
    return AnalysisRunPreparation(
      requestMessages: tail,
      conversationSummary: full.conversationSummary,
      partnerSummary: full.partnerSummary,
      effectiveStyleContext: full.effectiveStyleContext,
      knownContactName: full.knownContactName,
      sessionContext: full.sessionContext,
      conversationPartnerId: full.conversationPartnerId,
      isReconnectContext: full.isReconnectContext,
      previousStage: full.previousStage,
      // 片段起點換成尾段裡的位置；起點在尾段之前＝整段尾段都是這次的新內容。
      analysisFragmentStartIndex: (full.analysisFragmentStartIndex - start)
          .clamp(0, tail.length - 1)
          .toInt(),
      // 續析基準照實際送出範圍的結尾：尾段一直到整段的最後一則，訊息數基準跟整段
      // 一樣；字數基準存整段的計費字數（等於整段分析成功會存的那個）。
      analyzedMessageCount: full.analyzedMessageCount,
      contentRevision: full.contentRevision,
      previousRound: full.previousRound,
      fullRequestCharBaseline: MessageCalculator.countPayloadChars(
        MessageCalculator.billingMessagesForAnalysis(messages),
      ),
    );
  }

  /// 尾段起點：一定要含她最後一則（沒有她的訊息不能分析）。加進更前面的訊息，計費
  /// 字數只會變多（她最後一則之後那幾則算不算錢，對每個候選尾段都一樣），所以往前
  /// 加到下一則會超過就停。null＝從她最後一則開始就超過。
  static int? _tailStart(List<Message> messages, int maxBillableChars) {
    final lastIncoming =
        messages.lastIndexWhere((message) => !message.isFromMe);
    if (lastIncoming < 0) return null;
    int billableCharsFrom(int start) => MessageCalculator.countPayloadChars(
          MessageCalculator.billingMessagesForAnalysis(messages.sublist(start)),
        );
    if (billableCharsFrom(lastIncoming) > maxBillableChars) return null;
    var start = lastIncoming;
    while (start > 0 && billableCharsFrom(start - 1) <= maxBillableChars) {
      start--;
    }
    return start;
  }

  /// 潤飾／微調脈絡：全量訊息走同一套摘要感知組裝。
  Future<AuxiliaryAnalysisContext> prepareAuxiliary({
    required Conversation conversation,
  }) async {
    final context = await _buildSummaryAwareContext(
      conversation: conversation,
      baseMessages: conversation.messages,
    );
    return AuxiliaryAnalysisContext(
      requestMessages: context.requestMessages,
      conversationSummary: context.conversationSummary,
      partnerSummary: _resolvePartnerSummary(conversation),
      effectiveStyleContext: _resolveEffectiveStyleContext(conversation),
      knownContactName: _knownContactName(conversation),
    );
  }

  String? _knownContactName(Conversation conversation) =>
      ScreenshotRecognitionHelper.isPlaceholderConversationName(
        conversation.name,
      )
          ? null
          : conversation.name.trim();

  ({bool found, SessionContext? value}) _sessionContextFromSnapshot(
    String? snapshotJson,
  ) {
    if (snapshotJson == null || snapshotJson.trim().isEmpty) {
      return (found: false, value: null);
    }

    try {
      final decoded = jsonDecode(snapshotJson);
      if (decoded is! Map) return (found: false, value: null);
      final meta = decoded[_snapshotClientMetaKey];
      if (meta is! Map || !meta.containsKey(_snapshotSessionContextKey)) {
        return (found: false, value: null);
      }

      final rawContext = meta[_snapshotSessionContextKey];
      if (rawContext == null) return (found: true, value: null);
      if (rawContext is! Map) return (found: true, value: null);

      final meetingContext = _enumByName(
        MeetingContext.values,
        rawContext['meetingContext'],
      );
      final duration = _enumByName(
        AcquaintanceDuration.values,
        rawContext['duration'],
      );
      if (meetingContext == null || duration == null) {
        return (found: true, value: null);
      }

      final rawGoal = rawContext['goal'];
      final goal = rawGoal == null
          ? UserGoal.dateInvite
          : _enumByName(UserGoal.values, rawGoal);
      if (goal == null) return (found: true, value: null);

      final rawUserStyle = rawContext['userStyle'];
      final userStyle = rawUserStyle == null
          ? null
          : _enumByName(UserStyle.values, rawUserStyle);
      if (rawUserStyle != null && userStyle == null) {
        return (found: true, value: null);
      }

      return (
        found: true,
        value: SessionContext(
          meetingContext: meetingContext,
          duration: duration,
          goal: goal,
          userStyle: userStyle,
          userInterests: rawContext['userInterests'] is String
              ? rawContext['userInterests'] as String
              : null,
          targetDescription: rawContext['targetDescription'] is String
              ? rawContext['targetDescription'] as String
              : null,
          analysisContextNote: rawContext['analysisContextNote'] is String
              ? rawContext['analysisContextNote'] as String
              : null,
        ),
      );
    } catch (_) {
      return (found: false, value: null);
    }
  }

  T? _enumByName<T extends Enum>(List<T> values, Object? rawName) {
    if (rawName is! String) return null;
    for (final value in values) {
      if (value.name == rawName) return value;
    }
    return null;
  }

  /// 要有她的訊息才分析。F04（Eric 2026-10-16，協定 3）：她最後一則之後他傳的
  /// 也一起送（v3 的「他是最後一則」、已讀不回都要看到）；這幾則在上限內不算費，
  /// 扣費預覽與字數基準見 MessageCalculator.billingMessagesForAnalysis。
  List<Message>? _buildMessagesForReplyAnalysis(List<Message> messages) {
    if (messages.isEmpty) return null;
    if (!messages.any((message) => !message.isFromMe)) return null;
    return messages;
  }

  int _analysisFragmentStartIndex({
    required List<Message> baseMessages,
    required List<Message> requestMessages,
    required int? previousAnalyzedCount,
    required bool isNewFragment,
  }) {
    if (requestMessages.isEmpty || baseMessages.isEmpty) return 0;

    final firstRequest = requestMessages.first;
    var requestSliceStart = baseMessages.indexWhere(
      (message) => identical(message, firstRequest),
    );
    requestSliceStart = requestSliceStart >= 0
        ? requestSliceStart
        : baseMessages.indexWhere((message) => message.id == firstRequest.id);
    if (requestSliceStart < 0) {
      // Memory adapters are contractually suffix clippers. A custom/test
      // adapter that copied messages still gets a safe suffix fallback.
      requestSliceStart = (baseMessages.length - requestMessages.length)
          .clamp(0, baseMessages.length)
          .toInt();
    }

    var sourceStart = isNewFragment
        ? (previousAnalyzedCount ?? 0).clamp(0, baseMessages.length).toInt()
        : baseMessages.length;
    // Exact-boundary reruns (or an outgoing-only delta) have no new incoming
    // boundary. Reuse the latest contiguous incoming run instead of scoring
    // the whole history or emitting an empty fragment. F04：最後面可能是他傳的，
    // 所以錨在她最後一則（她最後一則就是最後一則時，跟原本一模一樣）。
    final lastIncomingIndex =
        baseMessages.lastIndexWhere((message) => !message.isFromMe);
    if (lastIncomingIndex >= 0 && sourceStart > lastIncomingIndex) {
      sourceStart = lastIncomingIndex;
      while (sourceStart > 0 && !baseMessages[sourceStart - 1].isFromMe) {
        sourceStart--;
      }
    }

    return (sourceStart - requestSliceStart)
        .clamp(0, requestMessages.length - 1)
        .toInt();
  }

  /// 會不會帶歷史摘要（只送最近幾輪）：已存的摘要，或更早的輪數夠做一段。後者的
  /// 摘要是本機規則產生、一定不是空的，所以同步預覽與實際組請求都看這裡就一致。
  bool _expectsHistoricalSummary(Conversation conversation) {
    final persistedSummary = _memory.persistedHistoricalSummary(conversation);
    if (persistedSummary != null && persistedSummary.isNotEmpty) return true;
    return conversation.currentRound - _memory.maxRecentRounds >=
        _memory.minRoundsPerSummary;
  }

  List<Message> _clipToRecentRounds(List<Message> baseMessages) {
    final clipped = _memory.clipToRecentRounds(
      baseMessages,
      _memory.maxRecentRounds,
    );
    return clipped.isEmpty ? baseMessages : clipped;
  }

  Future<String?> _buildHistoricalContextSummary(
    Conversation conversation,
  ) async {
    final persistedSummary = _memory.persistedHistoricalSummary(conversation);
    if (persistedSummary != null && persistedSummary.isNotEmpty) {
      return persistedSummary;
    }
    if (!_expectsHistoricalSummary(conversation)) {
      return null;
    }

    final olderRounds = conversation.currentRound - _memory.maxRecentRounds;

    final formattedSummary = await _memory.formatEphemeralSummary(
      conversation,
      olderRounds,
    );

    return formattedSummary.isEmpty ? null : formattedSummary;
  }

  Future<({List<Message> requestMessages, String? conversationSummary})>
      _buildSummaryAwareContext({
    required Conversation conversation,
    required List<Message> baseMessages,
  }) async {
    final conversationSummary = await _buildHistoricalContextSummary(
      conversation,
    );

    if (conversationSummary == null || conversationSummary.isEmpty) {
      return (
        requestMessages: baseMessages,
        conversationSummary: null,
      );
    }

    return (
      requestMessages: _clipToRecentRounds(baseMessages),
      conversationSummary: conversationSummary,
    );
  }
}
