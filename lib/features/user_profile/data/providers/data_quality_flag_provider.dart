import 'package:flutter_riverpod/flutter_riverpod.dart';

// Cross-feature import: `partnerDataQualityRepoProvider` lives under
// `analysis/data/providers/` because the resolver (its primary consumer)
// also lives in `analysis`. A future refactor could move the repo provider
// here so this dependency goes away — see Spec 3 plan note on Task 16.
import '../../../analysis/data/providers/analysis_providers.dart';
import '../../../partner/presentation/providers/partner_providers.dart';
import '../../domain/entities/partner_data_quality_state.dart';
import '../../domain/services/name_candidate_extractor.dart';

/// Result of comparing all name candidates extracted from a Partner's
/// conversations against the user-confirmed "same person" pairs.
///
/// Two outcomes only:
///  - [DataQualityFlag.unflagged]: 0 or 1 candidate, OR every distinct pair
///    of candidates is already confirmed as the same person.
///  - [DataQualityFlag.flagged]: at least one pair of distinct candidates is
///    NOT in the confirmed list. [conflictingPair] is the first such pair
///    encountered in lexicographic order (deterministic for UI binding).
class DataQualityFlag {
  final bool isFlagged;
  final NamePair? conflictingPair;

  const DataQualityFlag.unflagged()
      : isFlagged = false,
        conflictingPair = null;

  const DataQualityFlag.flagged(this.conflictingPair) : isFlagged = true;
}

/// Provider that aggregates name candidates across a partner's conversations
/// and compares them against the persisted confirmed-same-person pairs to
/// determine whether to surface a data-quality warning.
///
/// Spec 3 Task 16. Replaces the placeholder `isFlaggedUnresolved` always-false
/// behaviour in `PartnerDataQualityRepository` with real detection — wired
/// into `PartnerContextResolver` via `partnerDataQualityRepoViewProvider`.
final dataQualityFlagProvider =
    Provider.family<DataQualityFlag, String>((ref, partnerId) {
  final conversations = ref.watch(conversationsByPartnerProvider(partnerId));
  final qualityState = ref.watch(partnerDataQualityRepoProvider).load(partnerId);
  final extractor = NameCandidateExtractor();

  final candidates = <String>{};
  for (final c in conversations) {
    final name = extractor.fromConversationName(c.name) ??
        extractor.fromMessages(c.messages);
    if (name != null) candidates.add(name);
  }

  if (candidates.length < 2) return const DataQualityFlag.unflagged();

  final list = candidates.toList()..sort();
  for (var i = 0; i < list.length; i++) {
    for (var j = i + 1; j < list.length; j++) {
      final pair = NamePair.canonical(list[i], list[j]);
      if (!qualityState.confirmsSamePerson(pair)) {
        return DataQualityFlag.flagged(pair);
      }
    }
  }
  return const DataQualityFlag.unflagged();
});
