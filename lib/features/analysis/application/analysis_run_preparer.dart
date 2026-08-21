/// AnalyzeChat 送出前的請求組裝：驗證、歷史摘要、脈絡（partner／風格／
/// 已知聯絡人名）、內容修訂快照。主分析與潤飾／微調共用同一套組裝，
/// 行為逐字沿用拆分前 AnalysisScreen 的實作。
library;

import '../../conversation/data/repositories/conversation_archive_store.dart'
    show conversationContentRevision;
import '../../conversation/data/services/memory_service.dart';
import '../../conversation/domain/entities/conversation.dart';
import '../../conversation/domain/entities/conversation_summary.dart';
import '../../conversation/domain/entities/message.dart';
import '../domain/services/screenshot_recognition_helper.dart';

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

  /// 本次實際納入分析的訊息數（clamp 過 limit 的 sourceMessages 長度）。
  final int analyzedMessageCount;

  /// 送出前同步擷取的內容修訂：同數量編輯也能被 stale 守門認出。
  final String contentRevision;

  const AnalysisRunPreparation({
    required this.requestMessages,
    required this.conversationSummary,
    required this.partnerSummary,
    required this.effectiveStyleContext,
    required this.knownContactName,
    required this.analyzedMessageCount,
    required this.contentRevision,
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
  AnalysisRunPreparer({
    MemoryService? memoryService,
    required String? Function(Conversation conversation) resolvePartnerSummary,
    required String? Function(Conversation conversation)
        resolveEffectiveStyleContext,
  })  : _memoryService = memoryService ?? MemoryService(),
        _resolvePartnerSummary = resolvePartnerSummary,
        _resolveEffectiveStyleContext = resolveEffectiveStyleContext;

  final MemoryService _memoryService;
  final String? Function(Conversation conversation) _resolvePartnerSummary;
  final String? Function(Conversation conversation)
      _resolveEffectiveStyleContext;

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

  /// 主分析請求組裝（通過 [gate] 之後）：摘要感知訊息切片＋脈絡解析。
  Future<AnalysisRunPreparation> assemble({
    required Conversation conversation,
    required AnalysisRunGate gate,
  }) async {
    final context = await _buildSummaryAwareContext(
      conversation: conversation,
      baseMessages: gate.messagesForAnalysis!,
    );

    return AnalysisRunPreparation(
      requestMessages: context.requestMessages,
      conversationSummary: context.conversationSummary,
      partnerSummary: _resolvePartnerSummary(conversation),
      effectiveStyleContext: _resolveEffectiveStyleContext(conversation),
      knownContactName: _knownContactName(conversation),
      analyzedMessageCount: gate.analyzedMessageCount!,
      contentRevision: gate.contentRevision!,
    );
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

  List<Message>? _buildMessagesForReplyAnalysis(List<Message> messages) {
    if (messages.isEmpty) return null;

    final lastIncomingIndex =
        messages.lastIndexWhere((message) => !message.isFromMe);
    if (lastIncomingIndex == -1) {
      return null;
    }

    return messages.sublist(0, lastIncomingIndex + 1);
  }

  Future<String?> _buildHistoricalContextSummary(
    Conversation conversation,
  ) async {
    final persistedSummary =
        _memoryService.buildHistoricalSummary(conversation);
    if (persistedSummary != null && persistedSummary.isNotEmpty) {
      return persistedSummary;
    }

    final olderRounds =
        conversation.currentRound - MemoryService.maxRecentRounds;
    if (olderRounds < MemoryService.minRoundsPerSummary) {
      return null;
    }

    final ephemeralSummary = await _memoryService.generateSummary(
      conversation,
      0,
      olderRounds,
    );

    final formattedSummary = _memoryService.formatSummarySegments(
      <ConversationSummary>[ephemeralSummary],
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

    final requestMessages = _memoryService.clipToRecentRounds(
      baseMessages,
      MemoryService.maxRecentRounds,
    );

    return (
      requestMessages: requestMessages.isEmpty ? baseMessages : requestMessages,
      conversationSummary: conversationSummary,
    );
  }
}
