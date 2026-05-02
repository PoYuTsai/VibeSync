// Spec 5 C17 — coach-follow-up partnerHint builder.
//
// Owns the privacy/business rule for "what context is allowed to enter the
// Edge function partnerHint payload." Pure function, no DI, no Riverpod.
//
// The Edge schema (supabase/functions/coach-follow-up/schemas.ts:24-29)
// already accepts {name, heatScore?, gameStage?, lastConversationSummary?};
// this helper is the SOLE Flutter-side packager for that payload — keeping
// the privacy surface narrow at the type boundary.
//
// Static guard (asserted by coach_follow_up_partner_hint_builder_test.dart):
// this file MUST NOT import or reference PartnerContextResolver,
// partnerSummary, partnerTraits, raw `Message` entity, UserProfile / About
// Me, PartnerStyleOverride, or any cross-conversation aggregate. Caller
// passes the safe scalars (heatScore, gameStage) in directly; the helper
// just packages and applies the Spec 3 flagged guard.

import '../../../analysis/domain/entities/game_stage.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../../../partner/domain/entities/partner.dart';
import '../../../user_profile/data/providers/data_quality_flag_provider.dart';

/// Hard cap mirroring the Edge schema (`z.string().max(200)`). Truncating
/// here keeps the wire small AND makes the cap visible at the construction
/// site — the Edge would 400 a longer string anyway.
const int kCoachFollowUpSummaryMaxChars = 200;

/// Wire-shape value object handed to the API service (C18). Field names
/// mirror the Edge schema exactly so JSON serialization is trivial.
class CoachFollowUpPartnerHint {
  final String name;
  final int? heatScore;
  final String? gameStage;
  final String? lastConversationSummary;

  const CoachFollowUpPartnerHint({
    required this.name,
    this.heatScore,
    this.gameStage,
    this.lastConversationSummary,
  });
}

/// Builds the partnerHint payload from caller-provided context.
///
/// [partner] — required; caller must not invoke when there is no Partner.
/// [currentConversation] — nullable; if absent, no summary is attached.
/// [dataQualityFlag] — Spec 3 signal. When `isFlagged == true`, the summary
///   is forced to null (the conversation may mix two people's content);
///   name / heatScore / gameStage still flow because they describe the
///   partner identity, not conversation content.
/// [heatScore] — caller resolves from analysis state; passed through verbatim.
/// [gameStage] — caller resolves from analysis state; serialized as
///   `.name` (stable English wire key), never `.label` (繁中 display copy).
CoachFollowUpPartnerHint buildCoachFollowUpPartnerHint({
  required Partner partner,
  Conversation? currentConversation,
  DataQualityFlag? dataQualityFlag,
  int? heatScore,
  GameStage? gameStage,
}) {
  final name = partner.name.trim();

  String? lastSummary;
  final isFlagged = dataQualityFlag?.isFlagged ?? false;
  if (currentConversation != null && !isFlagged) {
    final summaries = currentConversation.summaries;
    if (summaries != null && summaries.isNotEmpty) {
      final latest = summaries.last.content;
      lastSummary = latest.length > kCoachFollowUpSummaryMaxChars
          ? latest.substring(0, kCoachFollowUpSummaryMaxChars)
          : latest;
    }
  }

  return CoachFollowUpPartnerHint(
    name: name,
    heatScore: heatScore,
    gameStage: gameStage?.name,
    lastConversationSummary: lastSummary,
  );
}
