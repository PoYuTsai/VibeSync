import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../user_profile/data/providers/data_quality_flag_provider.dart';
import '../../../user_profile/data/providers/partner_style_providers.dart';
import '../../../user_profile/data/providers/user_profile_providers.dart';

/// F3-1: Spec 2.5 style context for the opener prompt. Mirrors
/// `coachFollowUpStyleContextProvider`, with two opener twists: the partnerId
/// is optional (opener often runs before a partner exists), and the builder
/// slice carries the no-fabricated-common-ground guard.
final openerStyleContextProvider =
    Provider.family<String?, String?>((ref, partnerId) {
  final global = ref.watch(userProfileControllerProvider).valueOrNull;
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
  final includePartnerOverride = !ref.watch(dataQualityFlagProvider(id)).isFlagged;
  final partner = includePartnerOverride
      ? ref.watch(partnerStyleOverrideProvider(id)).valueOrNull
      : null;

  return builder.buildForOpener(
    global: global,
    partner: partner,
    includePartnerOverride: includePartnerOverride,
  );
});
