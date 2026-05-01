import 'package:hive_ce/hive_ce.dart';

part 'partner_data_quality_state.g.dart';

/// Canonical, order-independent pair of partner display names used by the
/// data-quality guard to flag "same person" duplicates.
///
/// Both names are trimmed and lower-cased, then sorted lexicographically
/// so that `NamePair.canonical('May', 'Anna')` and
/// `NamePair.canonical('Anna', 'May')` are equal.
@HiveType(typeId: 15)
class NamePair {
  @HiveField(0)
  final String first;
  @HiveField(1)
  final String second;

  /// Permissive raw constructor — used by the Hive adapter to rebuild stored
  /// rows. Trusted call sites should prefer [NamePair.canonical], which
  /// enforces the canonical invariants (non-empty, lower-case, sorted).
  const NamePair({required this.first, required this.second});

  factory NamePair.canonical(String a, String b) {
    final na = a.trim().toLowerCase();
    final nb = b.trim().toLowerCase();
    if (na.isEmpty || nb.isEmpty) {
      throw ArgumentError('NamePair: names must be non-empty');
    }
    final sorted = [na, nb]..sort();
    return NamePair(first: sorted[0], second: sorted[1]);
  }

  @override
  bool operator ==(Object other) =>
      other is NamePair && other.first == first && other.second == second;

  @override
  int get hashCode => Object.hash(first, second);
}

/// Per-partner data-quality state persisted alongside the partner record.
///
/// Stores user-confirmed "same person" name pairs so that the resolver can
/// suppress repeat warnings for pairs the user has already acknowledged.
@HiveType(typeId: 14)
class PartnerDataQualityState {
  @HiveField(0)
  final String partnerId;
  @HiveField(1)
  final List<NamePair> confirmedSamePersonPairs;
  @HiveField(2)
  final DateTime updatedAt;

  const PartnerDataQualityState({
    required this.partnerId,
    required this.confirmedSamePersonPairs,
    required this.updatedAt,
  });

  factory PartnerDataQualityState.empty(
    String partnerId, {
    required DateTime updatedAt,
  }) =>
      PartnerDataQualityState(
        partnerId: partnerId,
        confirmedSamePersonPairs: const [],
        updatedAt: updatedAt,
      );

  bool confirmsSamePerson(NamePair pair) =>
      confirmedSamePersonPairs.contains(pair);

  PartnerDataQualityState withConfirmed(NamePair pair, {required DateTime at}) {
    if (confirmsSamePerson(pair)) return this;
    return PartnerDataQualityState(
      partnerId: partnerId,
      confirmedSamePersonPairs: [...confirmedSamePersonPairs, pair],
      updatedAt: at,
    );
  }
}
