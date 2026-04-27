import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/partner_banner_service.dart';

/// Whether the same-name dedupe banner has been dismissed for the given uid.
///
/// `FutureProvider.family<bool, String>` is the Codex spec patch P2 contract —
/// avoids build-time `await` in widgets and the SharedPreferences flicker
/// that would otherwise show the banner momentarily before hiding it.
final partnerDedupeBannerDismissedProvider =
    FutureProvider.family<bool, String>((ref, uid) {
  return PartnerBannerService.isDismissed(uid);
});
