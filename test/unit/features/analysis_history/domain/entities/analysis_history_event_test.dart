import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis_history/domain/entities/analysis_history_event.dart';

void main() {
  test('analyze factory 填 analyze 欄位、practice 欄位為 null', () {
    final event = AnalysisHistoryEvent.analyze(
      id: 'e-1',
      createdAt: DateTime.utc(2026, 7, 6),
      conversationId: ' c-1 ',
      partnerId: ' p-1 ',
      subjectName: ' 小雲 ',
      enthusiasmScore: 72,
      gameStageLabel: 'premise',
    );

    expect(event.kind, AnalysisHistoryKind.analyze);
    expect(event.conversationId, 'c-1'); // trim
    expect(event.partnerId, 'p-1');
    expect(event.subjectName, '小雲');
    expect(event.enthusiasmScore, 72);
    expect(event.gameStageLabel, 'premise');
    expect(event.profileId, isNull);
    expect(event.roundIndex, isNull);
    expect(event.temperatureScore, isNull);
  });

  test('practice factory 填 practice 欄位、analyze 欄位為 null', () {
    final event = AnalysisHistoryEvent.practice(
      id: 'e-2',
      createdAt: DateTime.utc(2026, 7, 6, 1),
      profileId: 'practice_girl_007',
      roundIndex: 2,
      temperatureScore: 38,
      familiarityScore: 12,
      relationshipStageLabel: '破冰',
    );

    expect(event.kind, AnalysisHistoryKind.practice);
    expect(event.profileId, 'practice_girl_007');
    expect(event.roundIndex, 2);
    expect(event.temperatureScore, 38);
    expect(event.familiarityScore, 12);
    expect(event.relationshipStageLabel, '破冰');
    expect(event.conversationId, isNull);
    expect(event.partnerId, isNull);
    expect(event.enthusiasmScore, isNull);
  });

  test('id 空字串 → ArgumentError', () {
    expect(
      () => AnalysisHistoryEvent.analyze(
        id: '  ',
        createdAt: DateTime.utc(2026, 7, 6),
      ),
      throwsArgumentError,
    );
  });

  test('withPartnerId 保留原事件內容並正規化 scope', () {
    final original = AnalysisHistoryEvent.analyze(
      id: 'e-copy',
      createdAt: DateTime.utc(2026, 7, 6),
      conversationId: 'c-1',
      subjectName: '小雲',
      enthusiasmScore: 72,
      gameStageLabel: 'premise',
    );

    final enriched = original.withPartnerId(' p-1 ');

    expect(enriched.id, original.id);
    expect(enriched.conversationId, original.conversationId);
    expect(enriched.enthusiasmScore, original.enthusiasmScore);
    expect(enriched.partnerId, 'p-1');
  });

  test('adapter typeId 鎖定 24/25（設計文件拍板，絕不漂移）', () {
    expect(AnalysisHistoryEventAdapter().typeId, 24);
    expect(AnalysisHistoryKindAdapter().typeId, 25);
  });

  test('practice factory 保存本輪條件（難度／模式／AI 回覆數／session id）並 trim', () {
    final event = AnalysisHistoryEvent.practice(
      id: AnalysisHistoryEvent.practiceEventId(' sess-9 '),
      createdAt: DateTime.utc(2026, 9, 19),
      profileId: 'practice_girl_007',
      roundIndex: 2,
      temperatureScore: 61,
      practiceDifficulty: ' challenge ',
      aiReplyCount: 8,
      practiceMode: 'game',
      practiceSessionId: ' sess-9 ',
    );

    expect(event.id, 'practice:sess-9');
    expect(event.practiceDifficulty, 'challenge');
    expect(event.aiReplyCount, 8);
    expect(event.practiceMode, 'game');
    expect(event.practiceSessionId, 'sess-9');
  });

  test('practiceEventId trim 後不得為空，合法值穩定加前綴', () {
    expect(
      () => AnalysisHistoryEvent.practiceEventId(''),
      throwsArgumentError,
    );
    expect(
      () => AnalysisHistoryEvent.practiceEventId('   '),
      throwsArgumentError,
    );
    expect(
      AnalysisHistoryEvent.practiceEventId(' abc '),
      'practice:abc',
    );
  });

  test('analyze factory 不補 practice 條件欄位（全 null）', () {
    final event = AnalysisHistoryEvent.analyze(
      id: 'e-3',
      createdAt: DateTime.utc(2026, 9, 19),
      conversationId: 'c-1',
      enthusiasmScore: 50,
    );
    expect(event.practiceDifficulty, isNull);
    expect(event.aiReplyCount, isNull);
    expect(event.practiceMode, isNull);
    expect(event.practiceSessionId, isNull);
  });

  test('withPartnerId 帶過 practice 條件欄位', () {
    final original = AnalysisHistoryEvent.practice(
      id: 'practice:s1',
      createdAt: DateTime.utc(2026, 9, 19),
      temperatureScore: 40,
      practiceDifficulty: 'easy',
      aiReplyCount: 3,
      practiceMode: 'beginner',
      practiceSessionId: 's1',
    );
    final copy = original.withPartnerId('p-x');
    expect(copy.practiceDifficulty, 'easy');
    expect(copy.aiReplyCount, 3);
    expect(copy.practiceMode, 'beginner');
    expect(copy.practiceSessionId, 's1');
  });
}
