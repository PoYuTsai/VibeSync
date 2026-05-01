import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/user_profile/data/repositories/partner_data_quality_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_data_quality_state.dart';

void main() {
  late Directory tmp;
  late Box<PartnerDataQualityState> box;
  late PartnerDataQualityRepository repo;

  setUpAll(() {
    if (!Hive.isAdapterRegistered(PartnerDataQualityStateAdapter().typeId)) {
      Hive.registerAdapter(PartnerDataQualityStateAdapter());
    }
    if (!Hive.isAdapterRegistered(NamePairAdapter().typeId)) {
      Hive.registerAdapter(NamePairAdapter());
    }
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('partner_data_quality_repo_test');
    Hive.init(tmp.path);
    box = await Hive.openBox<PartnerDataQualityState>(
      'test_pdq_${DateTime.now().microsecondsSinceEpoch}',
    );
    repo = PartnerDataQualityRepository(injectedBox: box);
  });

  tearDown(() async {
    await box.close();
    await tmp.delete(recursive: true);
  });

  group('PartnerDataQualityRepository', () {
    test('load returns empty state when none stored', () {
      final state = repo.load('p1');
      expect(state.partnerId, 'p1');
      expect(state.confirmedSamePersonPairs, isEmpty);
    });

    test('save persists state', () async {
      final pair = NamePair.canonical('Anna', 'May');
      final state = PartnerDataQualityState(
        partnerId: 'p1',
        confirmedSamePersonPairs: [pair],
        updatedAt: DateTime.utc(2026, 5, 1),
      );
      await repo.save(state);

      final loaded = repo.load('p1');
      expect(loaded.partnerId, 'p1');
      expect(loaded.confirmedSamePersonPairs, [pair]);
      expect(loaded.updatedAt, DateTime.utc(2026, 5, 1));
    });

    test('delete removes state', () async {
      await repo.save(PartnerDataQualityState(
        partnerId: 'p2',
        confirmedSamePersonPairs: [NamePair.canonical('Anna', 'May')],
        updatedAt: DateTime.utc(2026, 5, 1),
      ));
      await repo.delete('p2');

      final loaded = repo.load('p2');
      // After delete, load() falls back to empty state.
      expect(loaded.partnerId, 'p2');
      expect(loaded.confirmedSamePersonPairs, isEmpty);
    });

    test('markSamePerson appends NamePair to confirmed list', () async {
      final pair = NamePair.canonical('Anna', 'May');
      await repo.markSamePerson('p3', pair);

      final loaded = repo.load('p3');
      expect(loaded.partnerId, 'p3');
      expect(loaded.confirmedSamePersonPairs, [pair]);

      // Idempotent — marking the same pair again does not duplicate.
      await repo.markSamePerson('p3', pair);
      final loaded2 = repo.load('p3');
      expect(loaded2.confirmedSamePersonPairs.length, 1);

      // A different pair appends.
      final other = NamePair.canonical('Bob', 'Robert');
      await repo.markSamePerson('p3', other);
      final loaded3 = repo.load('p3');
      expect(loaded3.confirmedSamePersonPairs, containsAll([pair, other]));
      expect(loaded3.confirmedSamePersonPairs.length, 2);
    });

    test(
        'isFlaggedUnresolved returns false in Phase 3 (real detection wired in Phase 4 Task 16)',
        () {
      expect(
        repo.isFlaggedUnresolved('any-id'),
        isFalse,
        reason:
            'Phase 3 placeholder — Provider-backed view in analysis_providers '
            'will adopt dataQualityFlagProvider in Phase 4 Task 16',
      );
    });
  });
}
