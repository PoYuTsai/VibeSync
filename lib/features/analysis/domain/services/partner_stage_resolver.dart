import 'dart:convert';

import '../../../analysis_history/domain/entities/analysis_history_event.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../../../conversation/domain/entities/session_context.dart';
import '../entities/game_stage.dart';

class PartnerStageResolution {
  const PartnerStageResolution({
    required this.stage,
    required this.isReconnect,
    this.conversationId,
  });

  final GameStage stage;

  /// `opening` 在分析當下屬於既有伴侶的重新連線，而不是陌生人破冰。
  ///
  /// 這個值只可取自該次分析所屬 Conversation 的持久化 context；不得用
  /// Partner 今天的預設值回寫舊歷史。
  final bool isReconnect;
  final String? conversationId;
}

/// Resolves the latest valid interaction stage for one partner without
/// depending on report/UI code.
///
/// AnalyzeChat uses this as a weak prior for the next fragment, while the
/// report board uses the same result as its current-stage source of truth.
class PartnerStageResolver {
  const PartnerStageResolver();

  GameStage? latestStageFor(
    String partnerId,
    List<AnalysisHistoryEvent> events,
    List<Conversation> conversations,
  ) =>
      latestResolutionFor(partnerId, events, conversations)?.stage;

  PartnerStageResolution? latestResolutionFor(
    String partnerId,
    List<AnalysisHistoryEvent> events,
    List<Conversation> conversations,
  ) {
    final id = AnalysisHistoryEvent.normalizeScope(partnerId);
    if (id == null) return null;
    final conversationsById = {
      for (final conversation in conversations)
        conversation.id.trim(): conversation,
    };

    AnalysisHistoryEvent? latestValid;
    for (final event in events) {
      if (event.kind != AnalysisHistoryKind.analyze) continue;
      if (_subjectIdFor(event, conversationsById) != id) continue;
      if (GameStage.tryFromString(event.gameStageLabel) == null) continue;
      if (latestValid == null ||
          event.createdAt.isAfter(latestValid.createdAt)) {
        latestValid = event;
      }
    }
    if (latestValid != null) {
      final stage = GameStage.tryFromString(latestValid.gameStageLabel)!;
      final conversationId = AnalysisHistoryEvent.normalizeScope(
        latestValid.conversationId,
      );
      final sourceConversation =
          conversationId == null ? null : conversationsById[conversationId];
      return PartnerStageResolution(
        stage: stage,
        isReconnect: _isReconnect(stage, sourceConversation),
        conversationId: conversationId,
      );
    }

    // Old installs can have a valid Conversation snapshot but no history
    // event yet. Invalid or missing values never become opening implicitly.
    final partnerConversations = conversations
        .where(
          (conversation) =>
              AnalysisHistoryEvent.normalizeScope(conversation.partnerId) == id,
        )
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    for (final conversation in partnerConversations) {
      final stage = stageForConversation(conversation);
      if (stage != null) {
        return PartnerStageResolution(
          stage: stage,
          isReconnect: _isReconnect(stage, conversation),
          conversationId: conversation.id,
        );
      }
    }
    return null;
  }

  bool _isReconnect(GameStage stage, Conversation? conversation) {
    return stage == GameStage.opening &&
        conversation?.sessionContext?.meetingContext ==
            MeetingContext.committedPartner;
  }

  /// Strictly parses the durable stage on one legacy conversation.
  GameStage? stageForConversation(Conversation conversation) {
    final directStage = GameStage.tryFromString(
      conversation.currentGameStage,
    );
    if (directStage != null) return directStage;

    final snapshotJson = conversation.lastAnalysisSnapshotJson;
    if (snapshotJson == null || snapshotJson.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(snapshotJson);
      if (decoded is! Map) return null;
      final gameStage = decoded['gameStage'];
      if (gameStage is! Map) return null;
      return GameStage.tryFromString(gameStage['current'] as String?);
    } catch (_) {
      return null;
    }
  }

  String? _subjectIdFor(
    AnalysisHistoryEvent event,
    Map<String, Conversation> conversationsById,
  ) {
    final conversationId =
        AnalysisHistoryEvent.normalizeScope(event.conversationId);
    if (conversationId != null) {
      final currentPartner = AnalysisHistoryEvent.normalizeScope(
        conversationsById[conversationId]?.partnerId,
      );
      if (currentPartner != null) return currentPartner;
    }

    final persistedPartner =
        AnalysisHistoryEvent.normalizeScope(event.partnerId);
    return persistedPartner ?? conversationId;
  }
}
