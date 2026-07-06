import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis_history/domain/entities/analysis_history_event.dart';

void main() {
  test('analyze factory 填 analyze 欄位、practice 欄位為 null', () {
    final event = AnalysisHistoryEvent.analyze(
      id: 'e-1',
      createdAt: DateTime.utc(2026, 7, 6),
      conversationId: ' c-1 ',
      subjectName: ' 小雲 ',
      enthusiasmScore: 72,
      gameStageLabel: 'premise',
    );

    expect(event.kind, AnalysisHistoryKind.analyze);
    expect(event.conversationId, 'c-1'); // trim
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

  test('adapter typeId 鎖定 24/25（設計文件拍板，絕不漂移）', () {
    expect(AnalysisHistoryEventAdapter().typeId, 24);
    expect(AnalysisHistoryKindAdapter().typeId, 25);
  });
}
