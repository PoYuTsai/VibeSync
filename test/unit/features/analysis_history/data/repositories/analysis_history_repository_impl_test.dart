import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/analysis_history/data/repositories/analysis_history_repository_impl.dart';
import 'package:vibesync/features/analysis_history/domain/entities/analysis_history_event.dart';

const _testHivePath = './.dart_tool/test_hive_analysis_history_repo';
const _testBoxName = 'test_analysis_history_events';

AnalysisHistoryEvent _analyzeEvent(
  String id, {
  String? conversationId = 'c-1',
  int? score = 60,
  DateTime? createdAt,
}) =>
    AnalysisHistoryEvent.analyze(
      id: id,
      createdAt: createdAt ?? DateTime.utc(2026, 7, 6),
      conversationId: conversationId,
      subjectName: '小雲',
      enthusiasmScore: score,
      gameStageLabel: 'premise',
    );

AnalysisHistoryEvent _practiceEvent(
  String id, {
  int? temperature = 30,
  DateTime? createdAt,
}) =>
    AnalysisHistoryEvent.practice(
      id: id,
      createdAt: createdAt ?? DateTime.utc(2026, 7, 6),
      profileId: 'practice_girl_001',
      roundIndex: 1,
      temperatureScore: temperature,
    );

void main() {
  setUpAll(() {
    Hive.init(_testHivePath);
    if (!Hive.isAdapterRegistered(24)) {
      Hive.registerAdapter(AnalysisHistoryEventAdapter());
    }
    if (!Hive.isAdapterRegistered(25)) {
      Hive.registerAdapter(AnalysisHistoryKindAdapter());
    }
  });

  late Box<AnalysisHistoryEvent> box;
  late AnalysisHistoryRepositoryImpl repo;

  setUp(() async {
    box = await Hive.openBox<AnalysisHistoryEvent>(_testBoxName);
    repo = AnalysisHistoryRepositoryImpl(box);
  });

  tearDown(() async {
    await box.deleteFromDisk();
  });

  tearDownAll(() async {
    await Hive.close();
    final dir = Directory(_testHivePath);
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('append + listRecent 回 newest-first', () async {
    await repo.append(_analyzeEvent('old', createdAt: DateTime.utc(2026, 1)));
    await repo.append(_analyzeEvent('new', createdAt: DateTime.utc(2026, 5)));

    expect(repo.listRecent().map((e) => e.id), ['new', 'old']);
  });

  test('listByKind 只回該 kind', () async {
    await repo.append(_analyzeEvent('a-1'));
    await repo.append(_practiceEvent('p-1'));

    expect(
      repo.listByKind(AnalysisHistoryKind.practice).map((e) => e.id),
      ['p-1'],
    );
    expect(
      repo.listByKind(AnalysisHistoryKind.analyze).map((e) => e.id),
      ['a-1'],
    );
  });

  test('listByConversation 隔離 conversation scope 並 trim 查詢', () async {
    await repo.append(_analyzeEvent('c1-a', conversationId: 'c-1'));
    await repo.append(_analyzeEvent('c1-b', conversationId: ' c-1 '));
    await repo.append(_analyzeEvent('c2', conversationId: 'c-2'));

    expect(
      repo.listByConversation(' c-1 ').map((e) => e.id).toSet(),
      {'c1-a', 'c1-b'},
    );
    expect(repo.listByConversation(' '), isEmpty);
  });

  test('append 超過 500 筆 → 刪最舊、留最新 500', () async {
    for (var i = 0; i < 502; i++) {
      await repo.append(_analyzeEvent(
        'e-$i',
        createdAt: DateTime.utc(2026, 1, 1).add(Duration(minutes: i)),
      ));
    }

    final all = repo.listRecent();
    expect(all.length, 500);
    expect(all.first.id, 'e-501'); // 最新保留
    expect(all.any((e) => e.id == 'e-0'), isFalse); // 最舊被剪
    expect(all.any((e) => e.id == 'e-1'), isFalse);
    expect(all.any((e) => e.id == 'e-2'), isTrue);
  });

  test('clearAll 清空', () async {
    await repo.append(_analyzeEvent('e-1'));
    await repo.clearAll();
    expect(repo.listRecent(), isEmpty);
  });
}
