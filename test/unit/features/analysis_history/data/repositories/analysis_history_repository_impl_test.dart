import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/analysis_history/data/repositories/analysis_history_repository_impl.dart';
import 'package:vibesync/features/analysis_history/domain/entities/analysis_history_event.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';

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

Conversation _conversation(String id, String partnerId) => Conversation(
      id: id,
      name: '小雲',
      messages: const [],
      createdAt: DateTime.utc(2026, 1),
      updatedAt: DateTime.utc(2026, 1),
      partnerId: partnerId,
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

  test('watchChanges 在 append 後通知報告刷新', () async {
    final changed = repo.watchChanges().first;
    await repo.append(_analyzeEvent('watched'));

    await expectLater(changed, completes);
  });

  test('backfillPartnerIds 將 legacy conversation scope 持久化成 partner scope',
      () async {
    await repo.append(_analyzeEvent('legacy', conversationId: 'c-1'));

    expect(
      await repo.backfillPartnerIds([_conversation('c-1', 'p-1')]),
      1,
    );
    expect(repo.listRecent().single.partnerId, 'p-1');
    expect(
      await repo.backfillPartnerIds([_conversation('c-1', 'p-new')]),
      1,
    );
    expect(repo.listRecent().single.partnerId, 'p-new');
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

  test('同 id（practice:<sessionId>）重寫 → 只有一筆、欄位以最後一次為準', () async {
    final id = AnalysisHistoryEvent.practiceEventId('sess-dup');
    await repo.append(AnalysisHistoryEvent.practice(
      id: id,
      createdAt: DateTime.utc(2026, 9, 19, 10),
      temperatureScore: 40,
      practiceSessionId: 'sess-dup',
    ));
    await repo.append(AnalysisHistoryEvent.practice(
      id: id,
      createdAt: DateTime.utc(2026, 9, 19, 10),
      temperatureScore: 42,
      practiceSessionId: 'sess-dup',
    ));

    final practice = repo.listByKind(AnalysisHistoryKind.practice);
    expect(practice.length, 1);
    expect(practice.single.temperatureScore, 42);
  });

  test('新欄位關箱重開 round-trip（不能只測記憶體物件）', () async {
    await repo.append(AnalysisHistoryEvent.practice(
      id: 'practice:sess-rt',
      createdAt: DateTime.utc(2026, 9, 19, 11),
      profileId: 'practice_girl_003',
      roundIndex: 2,
      temperatureScore: 55,
      practiceDifficulty: 'challenge',
      aiReplyCount: 9,
      practiceMode: 'game',
      practiceSessionId: 'sess-rt',
    ));
    final name = box.name;
    await box.close();

    box = await Hive.openBox<AnalysisHistoryEvent>(name);
    repo = AnalysisHistoryRepositoryImpl(box);
    final restored = repo.listByKind(AnalysisHistoryKind.practice).single;
    expect(restored.practiceDifficulty, 'challenge');
    expect(restored.aiReplyCount, 9);
    expect(restored.practiceMode, 'game');
    expect(restored.practiceSessionId, 'sess-rt');
    expect(restored.roundIndex, 2);
    expect(restored.temperatureScore, 55);
  });

  test('舊 adapter（14 欄）寫出的真實資料 → 新 adapter 讀：舊欄位保留、新欄位 null', () async {
    Hive.registerAdapter(_LegacyFourteenFieldAdapter(), override: true);
    final legacyBox = await Hive.openBox<AnalysisHistoryEvent>(
      'legacy_history_${DateTime.now().microsecondsSinceEpoch}',
    );
    await legacyBox.put(
      'old-uuid',
      AnalysisHistoryEvent.practice(
        id: 'old-uuid',
        createdAt: DateTime.utc(2026, 6, 1, 9),
        profileId: 'practice_girl_001',
        roundIndex: 1,
        temperatureScore: 33,
        familiarityScore: 5,
        relationshipStageLabel: '破冰',
      ),
    );
    final legacyName = legacyBox.name;
    await legacyBox.close();

    Hive.registerAdapter(AnalysisHistoryEventAdapter(), override: true);
    final reopened = await Hive.openBox<AnalysisHistoryEvent>(legacyName);
    addTearDown(() => reopened.deleteFromDisk());
    final restored = reopened.get('old-uuid')!;

    expect(restored.kind, AnalysisHistoryKind.practice);
    expect(restored.temperatureScore, 33);
    expect(restored.familiarityScore, 5);
    expect(restored.relationshipStageLabel, '破冰');
    expect(restored.roundIndex, 1);
    expect(restored.practiceDifficulty, isNull);
    expect(restored.aiReplyCount, isNull);
    expect(restored.practiceMode, isNull);
    expect(restored.practiceSessionId, isNull);
  });
}

/// 新增 HiveField 14–17 之前，generator 產出的 `write` 形狀（0..13 共 14 欄），
/// 用來製造真實的舊版資料列。
class _LegacyFourteenFieldAdapter extends TypeAdapter<AnalysisHistoryEvent> {
  @override
  final typeId = 24;

  @override
  AnalysisHistoryEvent read(BinaryReader reader) =>
      throw UnsupportedError('write-only legacy adapter');

  @override
  void write(BinaryWriter writer, AnalysisHistoryEvent obj) {
    writer
      ..writeByte(14)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.kind)
      ..writeByte(2)
      ..write(obj.createdAt)
      ..writeByte(3)
      ..write(obj.conversationId)
      ..writeByte(4)
      ..write(obj.subjectName)
      ..writeByte(5)
      ..write(obj.enthusiasmScore)
      ..writeByte(6)
      ..write(obj.gameStageLabel)
      ..writeByte(7)
      ..write(obj.profileId)
      ..writeByte(8)
      ..write(obj.roundIndex)
      ..writeByte(9)
      ..write(obj.temperatureScore)
      ..writeByte(10)
      ..write(obj.familiarityScore)
      ..writeByte(11)
      ..write(obj.relationshipStageLabel)
      ..writeByte(12)
      ..write(obj.partnerId)
      ..writeByte(13)
      ..write(obj.isReconnect);
  }
}
