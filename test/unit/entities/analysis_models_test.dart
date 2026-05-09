import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';
import 'package:vibesync/features/analysis/domain/entities/game_stage.dart';

void main() {
  group('TopicDepthLevel', () {
    test('label returns correct Chinese label for each level', () {
      expect(TopicDepthLevel.event.label, '事件層');
      expect(TopicDepthLevel.personal.label, '個人層');
      expect(TopicDepthLevel.intimate.label, '曖昧層');
    });

    test('emoji returns correct emoji for each level', () {
      expect(TopicDepthLevel.event.emoji, '📰');
      expect(TopicDepthLevel.personal.emoji, '👤');
      expect(TopicDepthLevel.intimate.emoji, '💕');
    });
  });

  group('TopicDepth', () {
    test('creates instance with required fields', () {
      const topicDepth = TopicDepth(
        current: TopicDepthLevel.personal,
        suggestion: '可以往曖昧導向推進',
      );

      expect(topicDepth.current, TopicDepthLevel.personal);
      expect(topicDepth.suggestion, '可以往曖昧導向推進');
    });
  });

  group('HealthCheck', () {
    test('creates instance with required fields', () {
      const healthCheck = HealthCheck(
        issues: ['連續提問超過3次'],
        suggestions: ['嘗試分享自己的經歷'],
      );

      expect(healthCheck.issues.length, 1);
      expect(healthCheck.suggestions.length, 1);
      expect(healthCheck.hasNeedySignals, false);
    });

    test('supports optional flags', () {
      const healthCheck = HealthCheck(
        issues: [],
        suggestions: [],
        hasNeedySignals: true,
        hasInterviewStyle: true,
        speakingRatio: 0.7,
      );

      expect(healthCheck.hasNeedySignals, true);
      expect(healthCheck.hasInterviewStyle, true);
      expect(healthCheck.speakingRatio, 0.7);
    });
  });

  group('GameStageInfo', () {
    test('creates instance with required fields', () {
      const stageInfo = GameStageInfo(
        current: GameStage.premise,
        nextStep: '可以開始評估階段',
      );

      expect(stageInfo.current, GameStage.premise);
      expect(stageInfo.status, GameStageStatus.normal);
      expect(stageInfo.nextStep, '可以開始評估階段');
    });

    test('supports custom status', () {
      const stageInfo = GameStageInfo(
        current: GameStage.qualification,
        status: GameStageStatus.canAdvance,
        nextStep: '可以推進到敘事階段',
      );

      expect(stageInfo.status, GameStageStatus.canAdvance);
    });
  });

  group('PsychologyAnalysis', () {
    test('creates instance with required fields', () {
      const analysis = PsychologyAnalysis(
        subtext: '她想讓你更了解她',
      );

      expect(analysis.subtext, '她想讓你更了解她');
      expect(analysis.shitTest, null);
      expect(analysis.qualificationSignal, false);
    });

    test('supports optional fields', () {
      const analysis = PsychologyAnalysis(
        subtext: '她在測試你的反應',
        shitTest: '你是不是對每個女生都這樣',
        qualificationSignal: true,
      );

      expect(analysis.shitTest, '你是不是對每個女生都這樣');
      expect(analysis.qualificationSignal, true);
    });
  });

  group('FinalRecommendation', () {
    test('creates instance with all required fields', () {
      const recommendation = FinalRecommendation(
        pick: 'tease',
        content: '聽起來妳很會挑地方嘛，改天帶路？',
        reason: '用調情回覆推進曖昧',
        psychology: '模糊邀約讓她有想像空間',
      );

      expect(recommendation.pick, 'tease');
      expect(recommendation.content, '聽起來妳很會挑地方嘛，改天帶路？');
      expect(recommendation.reason, '用調情回覆推進曖昧');
      expect(recommendation.psychology, '模糊邀約讓她有想像空間');
    });

    test('parses optional reply segments for split copy UI', () {
      final recommendation = FinalRecommendation.fromJson({
        'pick': 'extend',
        'content': '紅牛跟賓士沒打起來，但妳這行程已經先熱血起來了XD\n樂華夜市我只問一件事：妳等等會不會被罪惡美食收買？',
        'reason': '分開接 F1 興奮和夜市行程',
        'psychology': '兩顆球分開回會更像真人聊天',
        'replySegments': [
          {
            'sourceIndex': 2,
            'label': '接她的 F1 興奮',
            'sourceMessage': '紅牛跟賓士差點打起來XD',
            'reply': '紅牛跟賓士沒打起來，但妳這行程已經先熱血起來了XD',
            'reason': '這句有情緒和畫面，適合單獨接住',
          },
          {
            'sourceIndex': 4,
            'sourceMessage': '等等要去樂華夜市',
            'reply': '樂華夜市我只問一件事：妳等等會不會被罪惡美食收買？',
            'reason': '這句能自然延伸下一輪',
          },
        ],
      });

      expect(recommendation.replySegments, hasLength(2));
      expect(recommendation.replySegments.first.sourceIndex, 2);
      expect(recommendation.replySegments.first.displayLabel, '接她的 F1 興奮');
      expect(recommendation.replySegments.last.displayLabel, '回第 4 句');
      expect(
        recommendation.replySegments.last.reply,
        '樂華夜市我只問一件事：妳等等會不會被罪惡美食收買？',
      );
    });
  });
}
