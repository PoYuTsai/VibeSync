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
  });
}
