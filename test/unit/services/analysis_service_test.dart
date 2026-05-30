import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';
import 'package:vibesync/features/analysis/domain/entities/game_stage.dart';

void main() {
  group('AnalysisResult.fromJson', () {
    test('parses valid response correctly', () {
      final json = {
        'enthusiasm': {'score': 75, 'level': 'hot'},
        'gameStage': {
          'current': 'premise',
          'status': 'normal',
          'nextStep': '可以開始評估階段',
        },
        'psychology': {
          'subtext': '對你有興趣',
          'shitTest': {'detected': false},
          'qualificationSignal': true,
        },
        'topicDepth': {'current': 'personal', 'suggestion': '可以往曖昧導向推進'},
        'replies': {
          'extend': '延展回覆',
          'resonate': '共鳴回覆',
          'tease': '調情回覆',
          'humor': '幽默回覆',
          'coldRead': '冷讀回覆',
        },
        'replyOptions': {
          'tease': {
            'approach': '先接她的行程，再用輕推拉延伸',
            'messages': [
              {
                'sourceMessage': '等等要去樂華夜市',
                'reply': '樂華夜市我只問一件事：妳等等會不會被罪惡美食收買？',
                'reason': '接住她主動分享的下一站',
              },
            ],
          },
        },
        'finalRecommendation': {
          'pick': 'tease',
          'content': '推薦的回覆',
          'reason': '推薦理由',
          'psychology': '心理學依據',
        },
        'coachActionHint': {
          'catchablePoint': '在家追劇 / 絕命毒師',
          'read': '她有補生活細節，可以接這顆球。',
          'microMove': '接劇名，再補一個你的看劇感受。',
          'avoid': '不要連問清單題。',
          'actionType': 'extendTopicStoryFrame',
          'confidence': 'high',
        },
        'warnings': [],
        'strategy': '保持沉穩',
        'reminder': '記得用你的方式說',
      };

      final result = AnalysisResult.fromJson(json);

      expect(result.enthusiasmScore, 75);
      expect(result.strategy, '保持沉穩');
      expect(result.gameStage.current, GameStage.premise);
      expect(result.gameStage.status, GameStageStatus.normal);
      expect(result.gameStage.nextStep, '可以開始評估階段');
      expect(result.psychology.subtext, '對你有興趣');
      expect(result.psychology.qualificationSignal, true);
      expect(result.topicDepth.current, TopicDepthLevel.personal);
      expect(result.replies['extend'], '延展回覆');
      expect(result.replies['humor'], '幽默回覆');
      expect(result.replies['coldRead'], '冷讀回覆');
      expect(result.recommendation.pick, 'tease');
      expect(result.recommendation.content, '調情回覆');
      expect(result.replyOptions['tease']?.approach, contains('輕推拉'));
      expect(result.replyOptions['tease']?.messages.single.reply,
          contains('樂華夜市'));
      expect(result.coachActionHint?.catchablePoint, '在家追劇 / 絕命毒師');
      expect(result.coachActionHint?.microMove, contains('接劇名'));
      expect(result.coachActionHint?.isUsable, true);
      expect(result.reminder, '記得用你的方式說');
      expect(result.shouldGiveUp, false);
    });

    test('parses response with healthCheck (Essential tier)', () {
      final json = {
        'enthusiasm': {'score': 60, 'level': 'warm'},
        'gameStage': {'current': 'opening', 'nextStep': ''},
        'psychology': {'subtext': ''},
        'topicDepth': {'current': 'facts'},
        'replies': {'extend': '回覆'},
        'finalRecommendation': {'pick': 'extend', 'content': ''},
        'healthCheck': {
          'issues': ['面試式提問'],
          'suggestions': ['用假設代替問句'],
          'hasNeedySignals': true,
        },
        'warnings': [],
        'strategy': '策略',
      };

      final result = AnalysisResult.fromJson(json);

      expect(result.healthCheck, isNotNull);
      expect(result.healthCheck!.issues, ['面試式提問']);
      expect(result.healthCheck!.suggestions, ['用假設代替問句']);
      expect(result.healthCheck!.hasNeedySignals, true);
    });

    test('handles missing optional fields', () {
      final json = {
        'enthusiasm': {'score': 50, 'level': 'warm'},
        'replies': {'extend': '延展回覆'},
      };

      final result = AnalysisResult.fromJson(json);

      expect(result.enthusiasmScore, 50);
      expect(result.strategy, '');
      expect(result.healthCheck, isNull);
      expect(result.reminder, isNull);
      expect(result.replyOptions['extend']?.copyText, '延展回覆');
      expect(result.shouldGiveUp, false);
    });

    test('sets shouldGiveUp when cold and has give up warning', () {
      final json = {
        'enthusiasm': {'score': 20, 'level': 'cold'},
        'replies': {'extend': '...'},
        'warnings': ['建議放棄'],
        'strategy': '建議開新對話',
      };

      final result = AnalysisResult.fromJson(json);

      expect(result.shouldGiveUp, true);
    });

    test('parses shitTest detection correctly', () {
      final json = {
        'enthusiasm': {'score': 65, 'level': 'hot'},
        'psychology': {
          'subtext': '在測試你',
          'shitTest': {
            'detected': true,
            'type': '一致性測試',
            'suggestion': '用幽默曲解回應',
          },
          'qualificationSignal': false,
        },
        'replies': {'extend': '...'},
      };

      final result = AnalysisResult.fromJson(json);

      expect(result.psychology.shitTest, '用幽默曲解回應');
    });

    test('parses dogfood raw and official full recommendation comparison', () {
      final json = {
        'enthusiasm': {'score': 45, 'level': 'warm'},
        'replies': {'extend': '正式延展回覆'},
        'finalRecommendation': {
          'pick': 'extend',
          'content': '正式延展回覆',
          'reason': '正式顯示理由',
          'psychology': '正式顯示心理',
        },
        'dogfoodComparison': {
          'rawFullRecommendation': {
            'pick': 'resonate',
            'content': '我懂你的感覺，我們慢慢來。',
            'reason': '完整 prompt 原始理由',
            'psychology': '完整 prompt 原始判斷',
          },
          'officialFullRecommendation': {
            'pick': 'extend',
            'content': '正式延展回覆',
            'reason': '正式顯示理由',
            'psychology': '正式顯示心理',
          },
          'entitlementAdjusted': true,
          'tierUsed': 'free',
        },
      };

      final result = AnalysisResult.fromJson(json);

      expect(result.recommendation.pick, 'extend');
      expect(result.dogfoodRawFullRecommendation?.pick, 'resonate');
      expect(result.dogfoodRawFullRecommendation?.content, contains('慢慢來'));
      expect(result.dogfoodOfficialFullRecommendation?.pick, 'extend');
      expect(result.dogfoodOfficialFullRecommendation?.content, '正式延展回覆');
      expect(result.dogfoodEntitlementAdjusted, true);
      expect(result.dogfoodTierUsed, 'free');
    });
  });

  group('TopicDepthLevelX.fromString', () {
    test('parses facts as event', () {
      expect(TopicDepthLevelX.fromString('facts'), TopicDepthLevel.event);
    });

    test('parses personal correctly', () {
      expect(TopicDepthLevelX.fromString('personal'), TopicDepthLevel.personal);
    });

    test('parses intimate correctly', () {
      expect(TopicDepthLevelX.fromString('intimate'), TopicDepthLevel.intimate);
    });

    test('defaults to event for unknown value', () {
      expect(TopicDepthLevelX.fromString('unknown'), TopicDepthLevel.event);
    });
  });

  group('GameStage.fromString', () {
    test('parses all stages correctly', () {
      expect(GameStage.fromString('opening'), GameStage.opening);
      expect(GameStage.fromString('premise'), GameStage.premise);
      expect(GameStage.fromString('qualification'), GameStage.qualification);
      expect(GameStage.fromString('narrative'), GameStage.narrative);
      expect(GameStage.fromString('close'), GameStage.close);
    });

    test('defaults to opening for unknown value', () {
      expect(GameStage.fromString('unknown'), GameStage.opening);
    });
  });

  group('GameStageStatus.fromString', () {
    test('parses all statuses correctly', () {
      expect(GameStageStatus.fromString('normal'), GameStageStatus.normal);
      expect(GameStageStatus.fromString('stuckFriend'),
          GameStageStatus.stuckFriend);
      expect(
          GameStageStatus.fromString('canAdvance'), GameStageStatus.canAdvance);
      expect(GameStageStatus.fromString('shouldRetreat'),
          GameStageStatus.shouldRetreat);
    });

    test('defaults to normal for unknown value', () {
      expect(GameStageStatus.fromString('unknown'), GameStageStatus.normal);
    });
  });
}
