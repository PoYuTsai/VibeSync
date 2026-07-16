import '../../../conversation/domain/entities/conversation.dart';
import '../../../conversation/domain/entities/message.dart';

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

  /// Re-evaluated when an OCR confirmation dialog returns. The fragment may
  /// have completed while the dialog was open, so the caller must not trust
  /// the state captured before awaiting user input.
  static bool mustCreateNewFragmentForImport({
    required Conversation conversation,
    required bool hasLoadedAnalysisResult,
  }) =>
      !canAppendInput(conversation) || hasLoadedAnalysisResult;

  /// Replaces the whole pending input batch instead of appending snippets.
  /// A completed fragment is immutable and must be handled by creating a new
  /// [Conversation] before calling this method. Any summary derived from the
  /// discarded batch must go with it, or the next analysis would still receive
  /// stale context even though the visible messages were replaced.
  static void replaceDraftBatch({
    required Conversation conversation,
    required List<Message> messages,
  }) {
    if (!canAppendInput(conversation)) {
      throw StateError('Completed analysis fragments cannot be replaced.');
    }
    conversation.messages
      ..clear()
      ..addAll(messages);
    conversation.summaries = null;
  }
}
