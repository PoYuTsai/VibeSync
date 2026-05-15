import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/coaching_memory/data/repositories/coaching_outcome_repository_impl.dart';
import 'package:vibesync/features/coaching_memory/domain/entities/coaching_outcome_event.dart';

const _testHivePath = './.dart_tool/test_hive_coaching_outcome_repo';
const _testBoxName = 'test_coaching_outcome_events';

CoachingOutcomeEvent _event(
  String id, {
  String? partnerId,
  String? conversationId,
  CoachingOutcomeSource source = CoachingOutcomeSource.coach,
  CoachingUserAction userAction = CoachingUserAction.unknown,
  CoachingOutcomeSignal outcome = CoachingOutcomeSignal.unknown,
  DateTime? createdAt,
  String summary = '低壓接球',
}) =>
    CoachingOutcomeEvent.create(
      id: id,
      partnerId: partnerId,
      conversationId: conversationId,
      source: source,
      suggestedMoveSummary: summary,
      userAction: userAction,
      outcome: outcome,
      createdAt: createdAt ?? DateTime.utc(2026, 5, 15),
    );

void main() {
  setUpAll(() {
    Hive.init(_testHivePath);
    if (!Hive.isAdapterRegistered(18)) {
      Hive.registerAdapter(CoachingOutcomeEventAdapter());
    }
    if (!Hive.isAdapterRegistered(19)) {
      Hive.registerAdapter(CoachingOutcomeSourceAdapter());
    }
    if (!Hive.isAdapterRegistered(20)) {
      Hive.registerAdapter(CoachingUserActionAdapter());
    }
    if (!Hive.isAdapterRegistered(21)) {
      Hive.registerAdapter(CoachingOutcomeSignalAdapter());
    }
  });

  late Box<CoachingOutcomeEvent> box;
  late CoachingOutcomeRepositoryImpl repo;

  setUp(() async {
    box = await Hive.openBox<CoachingOutcomeEvent>(_testBoxName);
    repo = CoachingOutcomeRepositoryImpl(box);
  });

  tearDown(() async {
    await box.deleteFromDisk();
  });

  tearDownAll(() async {
    await Hive.close();
    final dir = Directory(_testHivePath);
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('put + get returns the stored event', () async {
    await repo.put(_event('e-1', partnerId: 'p-1'));

    final loaded = repo.get('e-1');
    expect(loaded, isNotNull);
    expect(loaded!.id, 'e-1');
    expect(loaded.partnerId, 'p-1');
  });

  test('listByPartner isolates partner scopes and trims query', () async {
    await repo
        .put(_event('p1-old', partnerId: 'p-1', createdAt: DateTime(2026)));
    await repo.put(
      _event('p1-new', partnerId: 'p-1', createdAt: DateTime(2026, 5)),
    );
    await repo.put(_event('p2', partnerId: 'p-2'));
    await repo.put(_event('unbound', partnerId: null));

    final p1 = repo.listByPartner(' p-1 ');

    expect(p1.map((event) => event.id), ['p1-new', 'p1-old']);
    expect(repo.listByPartner(' '), isEmpty);
  });

  test('listUnbound only returns events without a partner scope', () async {
    await repo.put(_event('bound', partnerId: 'p-1'));
    await repo.put(_event('blank', partnerId: ' '));
    await repo.put(_event('null', partnerId: null));

    final unbound = repo.listUnbound();

    expect(unbound.map((event) => event.id).toSet(), {'blank', 'null'});
  });

  test('listByConversation isolates conversation scope', () async {
    await repo.put(_event('c1-a', conversationId: 'c-1'));
    await repo.put(_event('c1-b', conversationId: ' c-1 '));
    await repo.put(_event('c2', conversationId: 'c-2'));

    expect(
      repo.listByConversation('c-1').map((event) => event.id).toSet(),
      {'c1-a', 'c1-b'},
    );
    expect(repo.listByConversation(' '), isEmpty);
  });

  test('limit applies after newest-first sorting', () async {
    await repo.put(_event('old', createdAt: DateTime.utc(2026, 1)));
    await repo.put(_event('mid', createdAt: DateTime.utc(2026, 3)));
    await repo.put(_event('new', createdAt: DateTime.utc(2026, 5)));

    expect(repo.listRecent(limit: 2).map((event) => event.id), ['new', 'mid']);
    expect(repo.listRecent(limit: 0), isEmpty);
  });

  test('deleteByPartner removes only that partner scope', () async {
    await repo.put(_event('p1-a', partnerId: 'p-1'));
    await repo.put(_event('p1-b', partnerId: 'p-1'));
    await repo.put(_event('p2', partnerId: 'p-2'));
    await repo.put(_event('global'));

    final deleted = await repo.deleteByPartner(' p-1 ');

    expect(deleted, 2);
    expect(repo.listByPartner('p-1'), isEmpty);
    expect(repo.get('p2'), isNotNull);
    expect(repo.get('global'), isNotNull);
  });

  test('reassignPartner moves events from source to target', () async {
    await repo.put(_event('move-a', partnerId: 'from'));
    await repo.put(_event('move-b', partnerId: ' from '));
    await repo.put(_event('stay', partnerId: 'other'));

    final moved = await repo.reassignPartner(
      fromPartnerId: 'from',
      toPartnerId: 'to',
    );

    expect(moved, 2);
    expect(repo.listByPartner('from'), isEmpty);
    expect(repo.listByPartner('to').map((event) => event.id).toSet(), {
      'move-a',
      'move-b',
    });
    expect(repo.listByPartner('other').single.id, 'stay');
  });

  test('clearAll wipes every event', () async {
    await repo.put(_event('e-1'));
    await repo.put(_event('e-2', partnerId: 'p-1'));

    await repo.clearAll();

    expect(repo.listRecent(), isEmpty);
  });
}
