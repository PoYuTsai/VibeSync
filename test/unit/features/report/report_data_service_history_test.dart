import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/game_stage.dart';
import 'package:vibesync/features/analysis_history/domain/entities/analysis_history_event.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/session_context.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/report/data/services/report_data_service.dart';

AnalysisHistoryEvent _analyze(
  String id,
  String conversationId,
  String name,
  int score,
  DateTime createdAt,
) =>
    AnalysisHistoryEvent.analyze(
      id: id,
      createdAt: createdAt,
      conversationId: conversationId,
      subjectName: name,
      enthusiasmScore: score,
      gameStageLabel: 'premise',
    );

AnalysisHistoryEvent _practice(
        String id, int? temperature, DateTime createdAt) =>
    AnalysisHistoryEvent.practice(
      id: id,
      createdAt: createdAt,
      profileId: 'practice_girl_001',
      roundIndex: 1,
      temperatureScore: temperature,
    );

Conversation _conversation(
  String id,
  String partnerId,
  String name, {
  MeetingContext? meetingContext,
}) =>
    Conversation(
      id: id,
      name: name,
      messages: const [],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      partnerId: partnerId,
      sessionContext: meetingContext == null
          ? null
          : SessionContext(
              meetingContext: meetingContext,
              duration: AcquaintanceDuration.fewWeeks,
            ),
    );

Partner _partner(String id, String name) => Partner(
      id: id,
      name: name,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      ownerUserId: 'u-1',
    );

void main() {
  final service = ReportDataService();

  group('analysisSubjects', () {
    test('distinct conversationId、按最近事件 desc、名字取最新快照', () {
      final subjects = service.analysisSubjects([
        _analyze('a1', 'c-1', '小雲', 50, DateTime(2026, 6, 1)),
        _analyze('a2', 'c-2', '安安', 60, DateTime(2026, 6, 5)),
        _analyze('a3', 'c-1', '小雲改名', 70, DateTime(2026, 6, 9)),
        _practice('p1', 30, DateTime(2026, 6, 30)), // practice 不入對象清單
      ], const [], const []);

      expect(subjects.map((s) => s.subjectId), ['c-1', 'c-2']);
      expect(subjects.first.name, '小雲改名'); // 最新快照
    });

    test('空事件 → 空清單', () {
      expect(service.analysisSubjects(const [], const [], const []), isEmpty);
    });

    test('同一 partner 的不同 conversation 合併成一個對象', () {
      final subjects = service.analysisSubjects(
        [
          _analyze('a1', 'c-1', '小雲', 50, DateTime(2026, 6, 1)),
          _analyze('a2', 'c-2', '小雲', 70, DateTime(2026, 6, 9)),
        ],
        [
          _conversation('c-1', 'p-1', '小雲'),
          _conversation('c-2', 'p-1', '小雲'),
        ],
        [_partner('p-1', '正式名稱')],
      );

      expect(subjects, hasLength(1));
      expect(subjects.single.subjectId, 'p-1');
      expect(subjects.single.name, '正式名稱');
    });
  });

  group('subjectTrendPoints', () {
    test('單對象、createdAt 升序、跳過 null 分數', () {
      final points = service.subjectTrendPoints(
          [
            _analyze('a2', 'c-1', '小雲', 70, DateTime(2026, 6, 9)),
            _analyze('a1', 'c-1', '小雲', 50, DateTime(2026, 6, 1)),
            _analyze('b1', 'c-2', '安安', 99, DateTime(2026, 6, 2)), // 別的對象
            AnalysisHistoryEvent.analyze(
              id: 'a-null',
              createdAt: DateTime(2026, 6, 3),
              conversationId: 'c-1',
              subjectName: '小雲',
              enthusiasmScore: null, // 無分數 → 跳過
            ),
          ],
          'c-1',
          const []);

      expect(points.map((p) => p.score), [50, 70]); // 升序
      expect(points.map((p) => p.date),
          [DateTime(2026, 6, 1), DateTime(2026, 6, 9)]);
    });

    test('partner scope 會合併不同 conversation 的歷史點', () {
      final points = service.subjectTrendPoints(
        [
          _analyze('a1', 'c-1', '小雲', 50, DateTime(2026, 6, 1)),
          _analyze('a2', 'c-2', '小雲', 70, DateTime(2026, 6, 9)),
        ],
        'p-1',
        [
          _conversation('c-1', 'p-1', '小雲'),
          _conversation('c-2', 'p-1', '小雲'),
        ],
      );

      expect(points.map((point) => point.score), [50, 70]);
    });

    test('partner 合併後以 Conversation 的目前 scope 優先', () {
      final event = AnalysisHistoryEvent.analyze(
        id: 'before-merge',
        createdAt: DateTime(2026, 6, 1),
        conversationId: 'c-1',
        partnerId: 'p-old',
        subjectName: '小雲',
        enthusiasmScore: 50,
      );

      final points = service.subjectTrendPoints(
        [event],
        'p-new',
        [_conversation('c-1', 'p-new', '小雲')],
      );

      expect(points.map((point) => point.score), [50]);
    });

    test('原 Conversation 刪除後仍使用已回填的 partnerId', () {
      final event = AnalysisHistoryEvent.analyze(
        id: 'after-delete',
        createdAt: DateTime(2026, 6, 1),
        conversationId: 'c-1',
        partnerId: 'p-1',
        subjectName: '小雲',
        enthusiasmScore: 50,
      );

      final subjects = service.analysisSubjects(
        [event],
        const [],
        [_partner('p-1', '小雲')],
      );

      expect(subjects.single.subjectId, 'p-1');
    });
  });

  group('latestStageFor（作戰板真相）', () {
    AnalysisHistoryEvent stageEvent(
      String id,
      String partnerId,
      String? stageLabel,
      DateTime createdAt, {
      String? conversationId,
      bool? isReconnect,
    }) =>
        AnalysisHistoryEvent.analyze(
          id: id,
          createdAt: createdAt,
          conversationId: conversationId,
          partnerId: partnerId,
          subjectName: '小雲',
          enthusiasmScore: 60,
          gameStageLabel: stageLabel,
          isReconnect: isReconnect,
        );

    test('依分析完成時間取最新有效 stage，可前進也可後退，不保留歷史最高', () {
      final events = [
        stageEvent('e1', 'p-1', 'premise', DateTime(2026, 6, 1)),
        stageEvent('e2', 'p-1', 'qualification', DateTime(2026, 6, 5)),
        stageEvent('e3', 'p-1', 'close', DateTime(2026, 6, 9)),
      ];
      expect(
        service.latestStageFor('p-1', events, const []),
        GameStage.close,
      );

      // close 之後回到 qualification：最新成功分析才是真相。
      final retreated = [
        ...events,
        stageEvent('e4', 'p-1', 'qualification', DateTime(2026, 6, 12)),
      ];
      expect(
        service.latestStageFor('p-1', retreated, const []),
        GameStage.qualification,
      );
    });

    test('最新事件 stage 缺失或未知 → 保留較舊的有效 stage', () {
      final events = [
        stageEvent('e1', 'p-1', 'close', DateTime(2026, 6, 1)),
        stageEvent('e2', 'p-1', null, DateTime(2026, 6, 5)),
        stageEvent('e3', 'p-1', 'vibing hard', DateTime(2026, 6, 9)),
      ];
      expect(
        service.latestStageFor('p-1', events, const []),
        GameStage.close,
      );
    });

    test('全部無效且無 legacy → null（問號），不得默認 opening', () {
      final events = [
        stageEvent('e1', 'p-1', 'vibing hard', DateTime(2026, 6, 1)),
      ];
      expect(service.latestStageFor('p-1', events, const []), isNull);
      expect(service.latestStageFor('p-1', const [], const []), isNull);
    });

    test('事件透過 conversationId 對照 partner scope', () {
      final event = AnalysisHistoryEvent.analyze(
        id: 'e1',
        createdAt: DateTime(2026, 6, 1),
        conversationId: 'c-1',
        subjectName: '小雲',
        enthusiasmScore: 60,
        gameStageLabel: 'narrative',
      );
      expect(
        service.latestStageFor(
          'p-1',
          [event],
          [_conversation('c-1', 'p-1', '小雲')],
        ),
        GameStage.narrative,
      );
    });

    test('無事件時 legacy fallback 只接受五個合法值', () {
      final valid = _conversation('c-1', 'p-1', '小雲')
        ..currentGameStage = 'narrative';
      expect(
        service.latestStageFor('p-1', const [], [valid]),
        GameStage.narrative,
      );

      final garbage = _conversation('c-2', 'p-1', '小雲')
        ..currentGameStage = 'vibing hard';
      expect(service.latestStageFor('p-1', const [], [garbage]), isNull);
    });

    test('普通 Conversation 更新不得超車較新的分析事件', () {
      // conversation updatedAt 晚於事件，但事件才是分析完成時間的真相。
      final conv = _conversation('c-1', 'p-1', '小雲')
        ..currentGameStage = 'opening'
        ..updatedAt = DateTime(2026, 7, 1);
      final events = [
        stageEvent('e1', 'p-1', 'close', DateTime(2026, 6, 9)),
      ];
      expect(
        service.latestStageFor('p-1', events, [conv]),
        GameStage.close,
      );
    });

    test('重新連線只取分析來源 Conversation 的已保存 context', () {
      final committedConversation = _conversation(
        'c-1',
        'p-1',
        '小雲',
        meetingContext: MeetingContext.committedPartner,
      );
      final event = stageEvent(
        'e1',
        'p-1',
        'opening',
        DateTime(2026, 6, 9),
        conversationId: 'c-1',
      );

      final resolution = service.latestStageResolutionFor(
        'p-1',
        [event],
        [committedConversation],
      );

      expect(resolution?.stage, GameStage.opening);
      expect(resolution?.isReconnect, isTrue);
      expect(resolution?.conversationId, 'c-1');
    });

    test('舊分析當時不是伴侶，之後的對象卡設定不得把它改寫成重新連線', () {
      final datingAppConversation = _conversation(
        'c-1',
        'p-1',
        '小雲',
        meetingContext: MeetingContext.datingApp,
      );
      final event = stageEvent(
        'e1',
        'p-1',
        'opening',
        DateTime(2026, 6, 9),
        conversationId: 'c-1',
      );

      final resolution = service.latestStageResolutionFor(
        'p-1',
        [event],
        [datingAppConversation],
      );

      expect(resolution?.isReconnect, isFalse);
    });

    test('新事件凍結重新連線語意，不受 Conversation 後續設定改寫', () {
      final nowDatingApp = _conversation(
        'c-1',
        'p-1',
        '小雲',
        meetingContext: MeetingContext.datingApp,
      );
      final frozenReconnect = stageEvent(
        'e1',
        'p-1',
        'opening',
        DateTime(2026, 6, 9),
        conversationId: 'c-1',
        isReconnect: true,
      );
      expect(
        service.latestStageResolutionFor(
          'p-1',
          [frozenReconnect],
          [nowDatingApp],
        )?.isReconnect,
        isTrue,
      );

      final nowCommitted = _conversation(
        'c-2',
        'p-1',
        '小雲',
        meetingContext: MeetingContext.committedPartner,
      );
      final frozenOpening = stageEvent(
        'e2',
        'p-1',
        'opening',
        DateTime(2026, 6, 10),
        conversationId: 'c-2',
        isReconnect: false,
      );
      expect(
        service.latestStageResolutionFor(
          'p-1',
          [frozenOpening],
          [nowCommitted],
        )?.isReconnect,
        isFalse,
      );
    });

    test('Conversation 從 A 重分配到 B 後，同一事件只屬於 B', () {
      final moved = _conversation('c-1', 'partner-b', '小雲');
      final event = stageEvent(
        'e1',
        'partner-a',
        'qualification',
        DateTime(2026, 6, 9),
        conversationId: 'c-1',
      );

      expect(service.latestStageFor('partner-a', [event], [moved]), isNull);
      expect(
        service.latestStageFor('partner-b', [event], [moved]),
        GameStage.qualification,
      );
    });
  });

  group('practiceTemperaturePoints', () {
    test('全域混排、升序、跳過 null 溫度', () {
      final points = service.practiceTemperaturePoints([
        _practice('p2', 45, DateTime(2026, 6, 9)),
        _practice('p1', 30, DateTime(2026, 6, 1)),
        _practice('p-null', null, DateTime(2026, 6, 5)),
        _analyze('a1', 'c-1', '小雲', 50, DateTime(2026, 6, 2)), // analyze 不入
      ]);

      expect(points.map((p) => p.score), [30, 45]);
    });

    test('全空 → 空清單（UI 依此顯示引導文案）', () {
      expect(service.practiceTemperaturePoints(const []), isEmpty);
    });
  });
}
