import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/coaching_memory/domain/entities/coaching_outcome_event.dart';

const _testHivePath = './.dart_tool/test_hive_coaching_outcome_entity';

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

  tearDownAll(() async {
    await Hive.close();
    final dir = Directory(_testHivePath);
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('create trims optional scopes and blank strings become null', () {
    final event = CoachingOutcomeEvent.create(
      id: ' e-1 ',
      partnerId: ' p-1 ',
      conversationId: '   ',
      source: CoachingOutcomeSource.coach,
      adviceId: ' a-1 ',
      adviceType: ' nextStep ',
      suggestedMoveSummary: ' 先低壓接球 ',
      userAction: CoachingUserAction.editedAndSent,
      outcome: CoachingOutcomeSignal.engaged,
      outcomeTextPreview: ' 她有回 ',
      userNote: ' 有接住 ',
      createdAt: DateTime.utc(2026, 5, 15),
    );

    expect(event.id, 'e-1');
    expect(event.partnerId, 'p-1');
    expect(event.conversationId, isNull);
    expect(event.adviceId, 'a-1');
    expect(event.adviceType, 'nextStep');
    expect(event.suggestedMoveSummary, '先低壓接球');
    expect(event.outcomeTextPreview, '她有回');
    expect(event.userNote, '有接住');
  });

  test('create rejects empty id and summary', () {
    expect(
      () => CoachingOutcomeEvent.create(
        id: ' ',
        source: CoachingOutcomeSource.coach,
        suggestedMoveSummary: 'ok',
        createdAt: DateTime.utc(2026),
      ),
      throwsArgumentError,
    );

    expect(
      () => CoachingOutcomeEvent.create(
        id: 'e-1',
        source: CoachingOutcomeSource.coach,
        suggestedMoveSummary: ' ',
        createdAt: DateTime.utc(2026),
      ),
      throwsArgumentError,
    );
  });

  test('Hive round trip preserves enums and optional fields', () async {
    final box = await Hive.openBox<CoachingOutcomeEvent>('event_rt');
    addTearDown(box.deleteFromDisk);

    final original = CoachingOutcomeEvent.create(
      id: 'e-rt',
      partnerId: 'p-rt',
      conversationId: 'c-rt',
      source: CoachingOutcomeSource.analyze,
      adviceId: 'reply-1',
      adviceType: 'recommendedReply',
      suggestedMoveSummary: '用一句短回覆把球丟回去',
      userAction: CoachingUserAction.sentAsIs,
      outcome: CoachingOutcomeSignal.cold,
      outcomeTextPreview: '嗯嗯',
      userNote: '太直接',
      createdAt: DateTime.utc(2026, 5, 15, 8),
    );

    await box.put(original.id, original);
    final restored = box.get(original.id);

    expect(restored, isNotNull);
    expect(restored!.source, CoachingOutcomeSource.analyze);
    expect(restored.userAction, CoachingUserAction.sentAsIs);
    expect(restored.outcome, CoachingOutcomeSignal.cold);
    expect(restored.partnerId, 'p-rt');
    expect(restored.suggestedMoveSummary, '用一句短回覆把球丟回去');
  });
}
