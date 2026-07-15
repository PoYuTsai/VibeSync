import '../../../conversation/domain/entities/conversation.dart';

/// Lifecycle boundary for user-selected analysis fragments.
///
/// A [Conversation] is appendable only while it is still the draft for one
/// analysis request. Once any durable evidence says that request completed,
/// later screenshots or manual messages belong to a new conversation id. This
/// prevents unrelated user-selected snippets from becoming a fake transcript.
class AnalysisFragmentPolicy {
  const AnalysisFragmentPolicy._();

  static bool hasCompletedAnalysis(Conversation conversation) {
    final snapshot = conversation.lastAnalysisSnapshotJson?.trim();
    return (snapshot != null && snapshot.isNotEmpty) ||
        conversation.lastAnalyzedMessageCount != null ||
        conversation.lastEnthusiasmScore != null;
  }

  static bool canAppendInput(Conversation conversation) =>
      !hasCompletedAnalysis(conversation);
}
