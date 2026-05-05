import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/effective_style.dart';
import '../../domain/entities/partner_style_override.dart';
import '../../domain/services/effective_style_prompt_builder.dart';
import '../../domain/services/resolve_effective_style.dart';
import '../repositories/partner_style_repository.dart';
import 'user_profile_providers.dart';

final effectiveStylePromptBuilderProvider =
    Provider<EffectiveStylePromptBuilder>(
  (ref) => const EffectiveStylePromptBuilder(),
);

final partnerStyleRepositoryProvider = Provider<PartnerStyleRepository>(
  (ref) => PartnerStyleRepository(),
);

final partnerStyleOverrideProvider = AsyncNotifierProvider.family<
    PartnerStyleOverrideController, PartnerStyleOverride?, String>(
  PartnerStyleOverrideController.new,
);

class PartnerStyleOverrideController
    extends FamilyAsyncNotifier<PartnerStyleOverride?, String> {
  @override
  Future<PartnerStyleOverride?> build(String partnerId) async {
    final repo = ref.read(partnerStyleRepositoryProvider);
    return repo.load(partnerId);
  }

  /// Persists [override] (or deletes the row if it's [PartnerStyleOverride.isEmpty])
  /// and reflects the resulting state.
  Future<void> save(PartnerStyleOverride override) async {
    final repo = ref.read(partnerStyleRepositoryProvider);
    await repo.save(override);
    state = AsyncValue.data(override.isEmpty ? null : override);
  }

  /// Hard delete + drop state to null. Used by per-field reset paths and the
  /// "重設整個對象風格" action on the edit screen.
  Future<void> clear() async {
    final partnerId = arg;
    final repo = ref.read(partnerStyleRepositoryProvider);
    await repo.delete(partnerId);
    state = const AsyncValue.data(null);
  }
}

/// Per-field merge of the global About Me with the per-partner override.
/// UI uses this for placeholder hints ("沿用全域：穩重"). Spec 2.5 prompt code
/// reads the same merge shape through [EffectiveStylePromptBuilder].
final effectiveStyleProvider =
    Provider.family<EffectiveStyle, String>((ref, partnerId) {
  final globalAsync = ref.watch(userProfileControllerProvider);
  final partnerAsync = ref.watch(partnerStyleOverrideProvider(partnerId));
  return resolveEffectiveStyle(
    global: globalAsync.valueOrNull,
    partner: partnerAsync.valueOrNull,
  );
});
