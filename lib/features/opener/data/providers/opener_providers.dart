import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../user_profile/data/providers/data_quality_flag_provider.dart';
import '../../../user_profile/data/providers/partner_style_providers.dart';
import '../../../user_profile/data/providers/user_profile_providers.dart';

/// F3-1: Spec 2.5 style context for the opener prompt. Mirrors
/// `coachFollowUpStyleContextProvider`, with two opener twists: the partnerId
/// is optional (opener often runs before a partner exists), and the builder
/// slice carries the no-fabricated-common-ground guard.
///
/// Future-based on purpose (Codex R1 P2): the async profile/partner deps are
/// awaited so a cold opener entry still resolves the style snapshot *before*
/// `beginAttempt` mints the requestId. A `valueOrNull` sync read would send
/// no style on first use, then flip the fingerprint once deps load — a lost
/// charged response could no longer dedup on retry (double-charge risk).
final openerStyleContextProvider =
    FutureProvider.family<String?, String?>((ref, partnerId) async {
  final global = await ref.watch(userProfileControllerProvider.future);
  final builder = ref.watch(effectiveStylePromptBuilderProvider);

  final id = partnerId?.trim();
  if (id == null || id.isEmpty) {
    return builder.buildForOpener(
      global: global,
      partner: null,
      includePartnerOverride: false,
    );
  }

  // Spec 3: a flagged partner card suspends partner-specific style memory.
  final includePartnerOverride =
      !ref.watch(dataQualityFlagProvider(id)).isFlagged;
  final partner = includePartnerOverride
      ? await ref.watch(partnerStyleOverrideProvider(id).future)
      : null;

  return builder.buildForOpener(
    global: global,
    partner: partner,
    includePartnerOverride: includePartnerOverride,
  );
});
