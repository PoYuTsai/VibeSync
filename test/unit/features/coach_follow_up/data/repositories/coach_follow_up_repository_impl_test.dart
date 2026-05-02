// Spec 5 — B13 repository tests.
//
// Temp Hive path pattern (Codex P2 #6) — `Hive.init(testHivePath)` instead of
// `Hive.initFlutter`. The latter would share state with other test files and
// the dev's local Hive box; the temp path keeps each test run hermetic and
// disposable. Mirrors the convention in
// test/unit/services/storage_service_partner_box_test.dart.
//
// Five behavioral cases:
//   1. put + get returns the stored card
//   2. put twice for same partner OVERWRITES (latest-only — design §3.1)
//   3. delete(partnerId) removes that partner's card only
//   4. clearAll wipes every entry
//   5. get for unknown partnerId returns null

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/coach_follow_up/data/repositories/coach_follow_up_repository_impl.dart';
import 'package:vibesync/features/coach_follow_up/domain/entities/coach_follow_up_result.dart';

const _testHivePath = './.dart_tool/test_hive_coach_follow_up_repo';
const _testBoxName = 'test_coach_follow_up_results';

CoachFollowUpResult _result(
  String partnerId, {
  String phase = 'postDateReflection',
  String headline = 'h',
  String observation = 'o',
  String task = 't',
  String? suggestedLine,
  String boundaryReminder = 'b',
  DateTime? generatedAt,
  String modelUsed = 'claude-sonnet-4-20250514',
}) =>
    CoachFollowUpResult(
      partnerId: partnerId,
      phase: phase,
      headline: headline,
      observation: observation,
      task: task,
      suggestedLine: suggestedLine,
      boundaryReminder: boundaryReminder,
      generatedAt: generatedAt ?? DateTime(2026, 5, 2, 16),
      modelUsed: modelUsed,
    );

void main() {
  setUpAll(() {
    Hive.init(_testHivePath);
    if (!Hive.isAdapterRegistered(16)) {
      Hive.registerAdapter(CoachFollowUpResultAdapter());
    }
  });

  late Box<CoachFollowUpResult> box;
  late CoachFollowUpRepositoryImpl repo;

  setUp(() async {
    box = await Hive.openBox<CoachFollowUpResult>(_testBoxName);
    repo = CoachFollowUpRepositoryImpl(box);
  });

  tearDown(() async {
    await box.deleteFromDisk();
  });

  tearDownAll(() async {
    await Hive.close();
    final dir = Directory(_testHivePath);
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('put + get returns the stored card', () async {
    final r = _result('p-1', headline: 'first card');
    await repo.put(r);

    final loaded = repo.get('p-1');
    expect(loaded, isNotNull);
    expect(loaded!.partnerId, 'p-1');
    expect(loaded.headline, 'first card');
  });

  test('put twice for same partner overwrites (latest-only)', () async {
    await repo.put(_result('p-1', headline: 'first'));
    await repo.put(_result('p-1', headline: 'second'));

    expect(repo.get('p-1')?.headline, 'second');
    // No leftover history entries: box has exactly one row keyed by partnerId
    expect(box.length, 1);
  });

  test('delete removes the partner-keyed entry only', () async {
    await repo.put(_result('p-1', headline: 'keep me out'));
    await repo.put(_result('p-2', headline: 'survivor'));

    await repo.delete('p-1');
    expect(repo.get('p-1'), isNull);
    expect(repo.get('p-2')?.headline, 'survivor');
  });

  test('clearAll wipes every entry', () async {
    await repo.put(_result('p-1'));
    await repo.put(_result('p-2'));
    await repo.put(_result('p-3'));
    expect(box.length, 3);

    await repo.clearAll();
    expect(box.length, 0);
    expect(repo.get('p-1'), isNull);
    expect(repo.get('p-2'), isNull);
    expect(repo.get('p-3'), isNull);
  });

  test('get for unknown partnerId returns null', () async {
    expect(repo.get('p-does-not-exist'), isNull);

    await repo.put(_result('p-1'));
    expect(repo.get('p-other-partner'), isNull);
  });
}
