import '../../../conversation/domain/entities/conversation.dart';
import '../../../conversation/domain/entities/session_context.dart';
import '../../../partner/domain/entities/partner.dart';

/// Resolves the starting context shown before screenshot analysis.
///
/// A context already saved on the conversation is the most specific source.
/// Partner-card values are defaults for conversations that do not have one
/// yet; legacy partners fall back to the product defaults.
class ScreenshotSessionContextDefaults {
  const ScreenshotSessionContextDefaults._();

  static SessionContext resolve({
    required Conversation? conversation,
    required Partner? partner,
  }) {
    final existing = conversation?.sessionContext;
    if (existing != null) {
      return SessionContext(
        meetingContext: existing.meetingContext,
        duration: existing.duration,
        goal: existing.goal,
        userStyle: existing.userStyle,
        userInterests: existing.userInterests,
        targetDescription: existing.targetDescription,
        analysisContextNote: _normalized(existing.analysisContextNote),
      );
    }

    return SessionContext(
      meetingContext:
          partner?.defaultMeetingContext ?? MeetingContext.datingApp,
      duration:
          partner?.defaultAcquaintanceDuration ?? AcquaintanceDuration.justMet,
      goal: partner?.defaultGoal ?? UserGoal.dateInvite,
      analysisContextNote: _normalized(partner?.customNote),
    );
  }

  static String? _normalized(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
