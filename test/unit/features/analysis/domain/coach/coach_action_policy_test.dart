import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/coach/coach_action_card_data.dart';
import 'package:vibesync/features/analysis/domain/coach/coach_action_policy.dart';
import 'package:vibesync/features/analysis/domain/coach/coach_action_type.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';
import 'package:vibesync/features/analysis/domain/entities/game_stage.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';

void main() {
  group('CoachActionType', () {
    test('should expose 9 distinct values matching spec', () {
      expect(CoachActionType.values.length, 9);
      expect(CoachActionType.values.toSet(), {
        CoachActionType.softInvite,
        CoachActionType.lowerPressureReply,
        CoachActionType.extendTopicStoryFrame,
        CoachActionType.emotionalResonance,
        CoachActionType.rightSizeReply,
        CoachActionType.playfulReply,
        CoachActionType.pausePursuit,
        CoachActionType.preferenceSignal,
        CoachActionType.fitCheck,
      });
    });
  });

  group('CoachActionCardData', () {
    test('should be value-equal when all 6 fields match', () {
      const a = CoachActionCardData(
        actionLabel: '模糊邀約',
        whyNow: '熱度 88，可以給具體時間',
        task: '拋一個低門檻邀約',
        suggestedLine: '週六下午有空嗎？',
        avoid: '別問三題',
        learningLink: null,
      );
      const b = CoachActionCardData(
        actionLabel: '模糊邀約',
        whyNow: '熱度 88，可以給具體時間',
        task: '拋一個低門檻邀約',
        suggestedLine: '週六下午有空嗎？',
        avoid: '別問三題',
        learningLink: null,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('should not be equal when suggestedLine differs', () {
      const a = CoachActionCardData(
        actionLabel: 'x',
        whyNow: 'x',
        task: 'x',
        suggestedLine: 'a',
        avoid: 'x',
        learningLink: null,
      );
      const b = CoachActionCardData(
        actionLabel: 'x',
        whyNow: 'x',
        task: 'x',
        suggestedLine: 'b',
        avoid: 'x',
        learningLink: null,
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('CoachActionPolicy.evaluate', () {
    test('should return fitCheck card when no upstream rule matches', () {
      final card = CoachActionPolicy.evaluate(
        heatScore: 50,
        gameStage: const GameStageInfo(
          current: GameStage.opening,
          nextStep: '',
        ),
        finalRecommendation: const FinalRecommendation(
          pick: 'extend',
          content: '',
          reason: '',
          psychology: '',
        ),
        messages: const [],
        practiceGoals: const [],
        isDataQualityFlagged: false,
      );
      expect(card.actionLabel, '互動品質觀察');
      expect(card.suggestedLine, isNull);
      expect(card.learningLink, '18');
    });

    test(
        'should turn concrete entertainment topics into a topic-extension practice',
        () {
      final messages = [
        Message(
          id: 'm1',
          content: '嘿呀',
          isFromMe: false,
          timestamp: DateTime(2026, 5, 8, 21),
        ),
        Message(
          id: 'm2',
          content: '你今天過得如何',
          isFromMe: true,
          timestamp: DateTime(2026, 5, 8, 21, 1),
        ),
        Message(
          id: 'm3',
          content: '不錯呀',
          isFromMe: false,
          timestamp: DateTime(2026, 5, 8, 21, 2),
        ),
        Message(
          id: 'm4',
          content: '在家追劇 看絕命毒師',
          isFromMe: false,
          timestamp: DateTime(2026, 5, 8, 21, 3),
        ),
      ];

      final card = CoachActionPolicy.evaluate(
        heatScore: 60,
        gameStage: const GameStageInfo(
          current: GameStage.opening,
          nextStep: '',
        ),
        finalRecommendation: const FinalRecommendation(
          pick: 'extend',
          content: '絕命毒師很經典，你看到第幾季了？',
          reason: '接住她主動丟出的追劇話題',
          psychology: '',
        ),
        messages: messages,
        practiceGoals: const [],
        isDataQualityFlagged: false,
      );

      expect(card.actionLabel, '接住生活話題');
      expect(card.whyNow, contains('在家追劇 看絕命毒師'));
      expect(card.task, contains('補一個你的感受'));
      expect(card.avoidLabel, '節奏提醒');
      expect(card.avoid, contains('別只連問清單題'));
      expect(card.suggestedLine, isNull);
      expect(card.learningLink, '14');
    });

    test('should prefer usable AI coachActionHint over generic fallback', () {
      final card = CoachActionPolicy.evaluate(
        heatScore: 60,
        gameStage: const GameStageInfo(
          current: GameStage.opening,
          nextStep: '',
        ),
        finalRecommendation: const FinalRecommendation(
          pick: 'extend',
          content: '絕命毒師很經典，你看到第幾季了？',
          reason: '',
          psychology: '',
        ),
        messages: const [],
        practiceGoals: const [],
        isDataQualityFlagged: false,
        coachActionHint: const CoachActionHint(
          catchablePoint: '在家追劇 / 絕命毒師',
          read: '她有補生活細節，這顆球可以接，不是單純冷回。',
          microMove: '先接劇名，再補一個你的看劇感受或低壓小問題',
          avoid: '不要連問清單題，也不要急著跳邀約',
          actionType: 'extendTopicStoryFrame',
          confidence: 'high',
        ),
      );

      expect(card.actionLabel, '可接球點');
      expect(card.whyNow, contains('她丟出的球：在家追劇 / 絕命毒師'));
      expect(card.whyNow, contains('不是單純冷回'));
      expect(card.task, contains('接劇名'));
      expect(card.avoidLabel, '節奏提醒');
      expect(card.avoid, contains('不要連問清單題'));
      expect(card.learningLink, '14');
    });

    test('should keep hard brake label only for pressure-reduction actions',
        () {
      final card = CoachActionPolicy.evaluate(
        heatScore: 25,
        gameStage: const GameStageInfo(
          current: GameStage.opening,
          nextStep: '直接約她出來吃飯',
        ),
        finalRecommendation: const FinalRecommendation(
          pick: 'extend',
          content: '',
          reason: '',
          psychology: '',
        ),
        messages: const [],
        practiceGoals: const [],
        isDataQualityFlagged: false,
      );

      expect(card.actionLabel, '暫停追問');
      expect(card.avoidLabel, '先不要');
    });

    test('should ignore low-confidence AI coachActionHint', () {
      final card = CoachActionPolicy.evaluate(
        heatScore: 50,
        gameStage: const GameStageInfo(
          current: GameStage.opening,
          nextStep: '',
        ),
        finalRecommendation: const FinalRecommendation(
          pick: 'extend',
          content: '',
          reason: '',
          psychology: '',
        ),
        messages: const [],
        practiceGoals: const [],
        isDataQualityFlagged: false,
        coachActionHint: const CoachActionHint(
          catchablePoint: '訊號太少，沒有明確可接球點',
          read: '對方沒有提供足夠內容。',
          microMove: '保守回一個低壓小球',
          avoid: '不要硬推進',
          actionType: 'fitCheck',
          confidence: 'low',
        ),
      );

      expect(card.actionLabel, '互動品質觀察');
    });

    test('should not surface long-term-trait phrases when partner is flagged',
        () {
      final card = CoachActionPolicy.evaluate(
        heatScore: 50,
        gameStage: const GameStageInfo(
          current: GameStage.opening,
          nextStep: '',
        ),
        finalRecommendation: const FinalRecommendation(
          pick: 'extend',
          content: '',
          reason: '',
          psychology: '',
        ),
        messages: const [],
        practiceGoals: const [],
        isDataQualityFlagged: true,
      );
      // Positive assertion pins the flagged code path — without it the
      // denylist below is true-by-construction (the unflagged template
      // also happens not to contain those tokens). If a future refactor
      // routes flagged inputs through unflagged copy, this fails first.
      expect(card.whyNow, contains('資料還不完整'));
      for (final forbidden in const [
        '你們之前',
        '上次',
        '通常她',
        '她總是',
        '從歷史看',
      ]) {
        expect(
          card.whyNow.contains(forbidden),
          isFalse,
          reason: 'flagged whyNow leaked long-term-trait token "$forbidden"',
        );
      }
    });

    test(
        'should pick softInvite when heat is in veryHot range and stage is close',
        () {
      final card = CoachActionPolicy.evaluate(
        heatScore: 90,
        gameStage: const GameStageInfo(
          current: GameStage.close,
          status: GameStageStatus.canAdvance,
          nextStep: '提議週末一起去看那部電影',
        ),
        finalRecommendation: const FinalRecommendation(
          pick: 'extend',
          content: '剛好我也想去，週六下午有空嗎？',
          reason: '趁熱拋出具體時間能降低拒絕成本',
          psychology: '具體選項比開放邀請更容易成行',
        ),
        messages: const [],
        practiceGoals: const [],
        isDataQualityFlagged: false,
      );
      expect(card.actionLabel, '模糊邀約');
      expect(card.suggestedLine, '剛好我也想去，週六下午有空嗎？');
      expect(card.learningLink, '21');
    });

    test('should not pick softInvite on veryHot heat without meeting signal',
        () {
      final card = CoachActionPolicy.evaluate(
        heatScore: 90,
        gameStage: const GameStageInfo(
          current: GameStage.opening,
          status: GameStageStatus.normal,
          nextStep: '延續她剛剛提到的週末活動',
        ),
        finalRecommendation: const FinalRecommendation(
          pick: 'extend',
          content: '聽起來很放鬆，那你通常週末會怎麼安排？',
          reason: '先接住她分享的生活節奏',
          psychology: '',
        ),
        messages: const [],
        practiceGoals: const [PracticeGoal.softInvite],
        isDataQualityFlagged: false,
      );

      expect(
        card.actionLabel,
        isNot('模糊邀約'),
        reason:
            'softInvite needs both veryHot heat and a meeting/close gameplay signal',
      );
    });

    test(
        'should pick pausePursuit when heat is cold and nextStep contains meeting keyword',
        () {
      final card = CoachActionPolicy.evaluate(
        heatScore: 20,
        gameStage: const GameStageInfo(
          current: GameStage.opening,
          nextStep: '直接約她出來吃飯',
        ),
        finalRecommendation: const FinalRecommendation(
          pick: 'extend',
          content: '',
          reason: '',
          psychology: '',
        ),
        messages: const [],
        practiceGoals: const [],
        isDataQualityFlagged: false,
      );
      expect(card.actionLabel, '暫停追問');
      expect(card.suggestedLine, isNull);
    });

    test(
        'should suppress suggestedLine when heat is below 81 and content contains meeting keyword',
        () {
      final card = CoachActionPolicy.evaluate(
        heatScore: 35,
        gameStage: const GameStageInfo(
          current: GameStage.premise,
          nextStep: '提議週末一起去看電影',
        ),
        finalRecommendation: const FinalRecommendation(
          pick: 'extend',
          content: '週末要不要一起去喝咖啡？',
          reason: '趁熱邀約會讓關係升溫',
          psychology: '低門檻邀請降低壓力',
        ),
        messages: const [],
        practiceGoals: const [],
        isDataQualityFlagged: false,
      );
      expect(
        card.suggestedLine,
        isNull,
        reason: 'meeting-keyword content must not surface below heat 81',
      );
    });

    test(
        'should pick pausePursuit (not softInvite) when heat is cold and nextStep contains 見個面',
        () {
      final card = CoachActionPolicy.evaluate(
        heatScore: 25,
        gameStage: const GameStageInfo(
          current: GameStage.opening,
          nextStep: '找機會見個面',
        ),
        finalRecommendation: const FinalRecommendation(
          pick: 'extend',
          content: '想約她出來吃飯',
          reason: '',
          psychology: '',
        ),
        messages: const [],
        practiceGoals: const [],
        isDataQualityFlagged: false,
      );
      expect(card.actionLabel, '暫停追問');
    });

    test(
        'should pick extendTopicStoryFrame when heat is warm-hot and stage is mid-game without explainLess goal',
        () {
      final card = CoachActionPolicy.evaluate(
        heatScore: 50,
        gameStage: const GameStageInfo(
          current: GameStage.premise,
          nextStep: '聊聊她最近在忙什麼',
        ),
        finalRecommendation: const FinalRecommendation(
          pick: 'extend',
          content: '聽起來最近壓力大，是哪一塊？',
          reason: '',
          psychology: '',
        ),
        messages: const [],
        practiceGoals: const [],
        isDataQualityFlagged: false,
      );
      expect(card.actionLabel, '故事框架');
      expect(card.learningLink, '14');
      expect(card.suggestedLine, '聽起來最近壓力大，是哪一塊？');
    });

    test(
        'should switch to preferenceSignal when explainLess practice goal is set',
        () {
      final card = CoachActionPolicy.evaluate(
        heatScore: 50,
        gameStage: const GameStageInfo(
          current: GameStage.premise,
          nextStep: '',
        ),
        finalRecommendation: const FinalRecommendation(
          pick: 'extend',
          content: '',
          reason: '',
          psychology: '',
        ),
        messages: const [],
        practiceGoals: const [PracticeGoal.explainLess],
        isDataQualityFlagged: false,
      );
      expect(card.actionLabel, '輕量表達偏好');
      expect(card.learningLink, '2');
    });

    test('should pick challenge copy when challengeSignal is detected', () {
      final card = CoachActionPolicy.evaluate(
        heatScore: 55,
        gameStage: const GameStageInfo(
          current: GameStage.qualification,
          nextStep: '',
        ),
        finalRecommendation: const FinalRecommendation(
          pick: 'resonate',
          content: '聽起來那天真的很累，先吃個飯再聊吧。',
          reason: '',
          psychology: '',
        ),
        messages: const [],
        practiceGoals: const [],
        isDataQualityFlagged: false,
        psychology: const PsychologyAnalysis(
          subtext: '',
          shitTest: '她在試你會不會推回去',
        ),
      );
      expect(card.actionLabel, '接住試探球');
      expect(card.whyNow, contains('互動測試'));
      expect(card.task, contains('把球自然丟回去'));
      expect(card.avoid, contains('別急著自證'));
      expect(card.learningLink, '11');
    });

    test('should pick emotionalResonance when subtext has explicit emotion',
        () {
      final card = CoachActionPolicy.evaluate(
        heatScore: 55,
        gameStage:
            const GameStageInfo(current: GameStage.qualification, nextStep: ''),
        finalRecommendation: const FinalRecommendation(
          pick: 'resonate',
          content: '',
          reason: '',
          psychology: '',
        ),
        messages: const [],
        practiceGoals: const [],
        isDataQualityFlagged: false,
        psychology: const PsychologyAnalysis(subtext: '她其實有點不安，想先被理解和安撫一下'),
      );
      expect(card.actionLabel, '情緒共鳴');
      expect(card.whyNow, contains('明確情緒訊號'));
    });

    test('should not pick emotionalResonance when subtext is generic signal',
        () {
      final card = CoachActionPolicy.evaluate(
        heatScore: 55,
        gameStage:
            const GameStageInfo(current: GameStage.qualification, nextStep: ''),
        finalRecommendation: const FinalRecommendation(
          pick: 'extend',
          content: '被妳發現了，我會在飲料櫃前思考人生。妳也是亂逛派嗎？',
          reason: '',
          psychology: '',
        ),
        messages: const [],
        practiceGoals: const [],
        isDataQualityFlagged: false,
        psychology: const PsychologyAnalysis(subtext: '她想了解你是不是有趣、有生活感'),
      );

      expect(card.actionLabel, isNot('情緒共鳴'));
      expect(card.actionLabel, '故事框架');
    });

    test('should not pick emotionalResonance when subtext is short noise', () {
      final card = CoachActionPolicy.evaluate(
        heatScore: 50,
        gameStage:
            const GameStageInfo(current: GameStage.opening, nextStep: ''),
        finalRecommendation: const FinalRecommendation(
          pick: 'extend',
          content: '',
          reason: '',
          psychology: '',
        ),
        messages: const [],
        practiceGoals: const [],
        isDataQualityFlagged: false,
        psychology: const PsychologyAnalysis(subtext: '嗯'),
      );
      expect(card.actionLabel, isNot('情緒共鳴'));
    });

    test(
        'should pick rightSizeReply when user reply exceeds partner length × 1.8',
        () {
      final messages = [
        Message(
          id: 'm1',
          content: '今天累',
          isFromMe: false,
          timestamp: DateTime(2026, 5, 1, 10),
        ),
        Message(
          id: 'm2',
          content: '哎我也是欸今天從早到晚開會根本沒時間吃飯下班還被叫去處理一個爛攤子',
          isFromMe: true,
          timestamp: DateTime(2026, 5, 1, 11),
        ),
      ];
      final card = CoachActionPolicy.evaluate(
        heatScore: 55,
        gameStage:
            const GameStageInfo(current: GameStage.premise, nextStep: ''),
        finalRecommendation: const FinalRecommendation(
          pick: 'extend',
          content: '',
          reason: '',
          psychology: '',
        ),
        messages: messages,
        practiceGoals: const [],
        isDataQualityFlagged: false,
      );
      expect(card.actionLabel, '回得剛剛好');
      expect(card.learningLink, '12');
    });

    test(
        'should compare against the latest user reply after the partner message',
        () {
      final messages = [
        Message(
          id: 'm1',
          content: '今天累',
          isFromMe: false,
          timestamp: DateTime(2026, 5, 1, 10),
        ),
        Message(
          id: 'm2',
          content: '我懂',
          isFromMe: true,
          timestamp: DateTime(2026, 5, 1, 11),
        ),
        Message(
          id: 'm3',
          content: '我今天也是一路從早忙到晚，還一直想著昨天那件事到底怎麼收尾比較好',
          isFromMe: true,
          timestamp: DateTime(2026, 5, 1, 12),
        ),
      ];

      final card = CoachActionPolicy.evaluate(
        heatScore: 55,
        gameStage:
            const GameStageInfo(current: GameStage.premise, nextStep: ''),
        finalRecommendation: const FinalRecommendation(
          pick: 'extend',
          content: '',
          reason: '',
          psychology: '',
        ),
        messages: messages,
        practiceGoals: const [],
        isDataQualityFlagged: false,
      );

      expect(card.actionLabel, '回得剛剛好');
    });

    test(
        'should not call a natural greeting too long after a brief name answer',
        () {
      final messages = [
        Message(
          id: 'm1',
          content: 'hihi',
          isFromMe: false,
          timestamp: DateTime(2026, 5, 1, 10),
        ),
        Message(
          id: 'm2',
          content: '你好',
          isFromMe: true,
          timestamp: DateTime(2026, 5, 1, 10, 1),
        ),
        Message(
          id: 'm3',
          content: 'hi! 怎麼稱呼你？',
          isFromMe: true,
          timestamp: DateTime(2026, 5, 1, 10, 2),
        ),
        Message(
          id: 'm4',
          content: 'Amy',
          isFromMe: false,
          timestamp: DateTime(2026, 5, 1, 10, 3),
        ),
        Message(
          id: 'm5',
          content: 'Amy 好呀😊 最近在忙什麼？',
          isFromMe: true,
          timestamp: DateTime(2026, 5, 1, 10, 4),
        ),
      ];

      final card = CoachActionPolicy.evaluate(
        heatScore: 60,
        gameStage:
            const GameStageInfo(current: GameStage.opening, nextStep: ''),
        finalRecommendation: const FinalRecommendation(
          pick: 'extend',
          content: 'Amy 好呀😊 最近在忙什麼？',
          reason: '',
          psychology: '',
        ),
        messages: messages,
        practiceGoals: const [],
        isDataQualityFlagged: false,
      );

      expect(card.actionLabel, isNot('回得剛剛好'));
      expect(card.whyNow, isNot(contains('回得有點長')));
    });

    test('should not pick rightSizeReply when ratio is at the threshold', () {
      final messages = [
        Message(
          id: 'm1',
          content: '今天好累',
          isFromMe: false,
          timestamp: DateTime(2026, 5, 1, 10),
        ),
        Message(
          id: 'm2',
          content: '我也累',
          isFromMe: true,
          timestamp: DateTime(2026, 5, 1, 11),
        ),
      ];
      final card = CoachActionPolicy.evaluate(
        heatScore: 55,
        gameStage:
            const GameStageInfo(current: GameStage.premise, nextStep: ''),
        finalRecommendation: const FinalRecommendation(
          pick: 'extend',
          content: '',
          reason: '',
          psychology: '',
        ),
        messages: messages,
        practiceGoals: const [],
        isDataQualityFlagged: false,
      );
      expect(card.actionLabel, isNot('回得剛剛好'));
    });

    test(
        'should pick lowerPressureReply when heat is cold without meeting keyword',
        () {
      final card = CoachActionPolicy.evaluate(
        heatScore: 25,
        gameStage: const GameStageInfo(
          current: GameStage.opening,
          nextStep: '聊聊她最近怎樣',
        ),
        finalRecommendation: const FinalRecommendation(
          pick: 'extend',
          content: '',
          reason: '',
          psychology: '',
        ),
        messages: const [],
        practiceGoals: const [],
        isDataQualityFlagged: false,
      );
      expect(card.actionLabel, '降低壓力');
      expect(card.learningLink, '10');
    });

    test(
        'should pick playfulReply when humorousReply practice goal is set in warm-hot',
        () {
      final card = CoachActionPolicy.evaluate(
        heatScore: 55,
        gameStage: const GameStageInfo(
          current: GameStage.qualification,
          nextStep: '',
        ),
        finalRecommendation: const FinalRecommendation(
          pick: 'humor',
          content: '我看妳今天比咖啡因還清醒',
          reason: '',
          psychology: '',
        ),
        messages: const [],
        practiceGoals: const [PracticeGoal.humorousReply],
        isDataQualityFlagged: false,
      );
      expect(card.actionLabel, '輕鬆幽默');
      expect(card.learningLink, '3');
    });

    test('should restrict actionType to safe set when partner is flagged', () {
      final card = CoachActionPolicy.evaluate(
        heatScore: 90,
        gameStage: const GameStageInfo(
          current: GameStage.close,
          nextStep: '提議週末一起去看電影',
        ),
        finalRecommendation: const FinalRecommendation(
          pick: 'extend',
          content: '週六下午有空嗎？',
          reason: '',
          psychology: '',
        ),
        messages: const [],
        practiceGoals: const [],
        isDataQualityFlagged: true,
      );
      expect(card.actionLabel, isNot('模糊邀約'));
      const safeLabels = ['情緒共鳴', '接住試探球', '回得剛剛好', '降低壓力', '互動品質觀察'];
      expect(
        safeLabels.contains(card.actionLabel),
        isTrue,
        reason:
            'flagged path produced "${card.actionLabel}" which is outside the safe set',
      );
    });

    test('should ignore practiceGoals input entirely when flagged', () {
      CoachActionCardData runWith(List<PracticeGoal> goals) =>
          CoachActionPolicy.evaluate(
            heatScore: 55,
            gameStage: const GameStageInfo(
              current: GameStage.qualification,
              nextStep: '',
            ),
            finalRecommendation: const FinalRecommendation(
              pick: 'extend',
              content: '',
              reason: '',
              psychology: '',
            ),
            messages: const [],
            practiceGoals: goals,
            isDataQualityFlagged: true,
          );
      final cardA = runWith(const [PracticeGoal.softInvite]);
      final cardB = runWith(const [PracticeGoal.reduceAnxiety]);
      expect(
        cardA.actionLabel,
        cardB.actionLabel,
        reason:
            'flagged path must ignore practiceGoals — same flagged input should give same actionType regardless of practiceGoals',
      );
    });

    test(
        'should never produce forbidden phrases in any task or avoid field across all 9 actionTypes',
        () {
      final triggers = <Map<String, dynamic>>[
        // softInvite
        {
          'heatScore': 90,
          'gameStage':
              const GameStageInfo(current: GameStage.close, nextStep: ''),
        },
        // pausePursuit (cold + meeting keyword)
        {
          'heatScore': 20,
          'gameStage': const GameStageInfo(
              current: GameStage.opening, nextStep: '想約她出來'),
        },
        // lowerPressureReply (cold without meeting keyword)
        {
          'heatScore': 25,
          'gameStage':
              const GameStageInfo(current: GameStage.opening, nextStep: ''),
        },
        // rightSizeReply
        {
          'heatScore': 55,
          'gameStage':
              const GameStageInfo(current: GameStage.premise, nextStep: ''),
          'messages': [
            Message(
              id: 'm1',
              content: '累',
              isFromMe: false,
              timestamp: DateTime(2026, 5, 1, 10),
            ),
            Message(
              id: 'm2',
              content: '今天從早忙到晚根本沒空喝水',
              isFromMe: true,
              timestamp: DateTime(2026, 5, 1, 11),
            ),
          ],
        },
        // emotionalResonance
        {
          'heatScore': 55,
          'gameStage': const GameStageInfo(
              current: GameStage.qualification, nextStep: ''),
          'psychology': const PsychologyAnalysis(subtext: '她其實有點不安，想先被理解一下'),
        },
        // playfulReply
        {
          'heatScore': 55,
          'gameStage': const GameStageInfo(
              current: GameStage.qualification, nextStep: ''),
          'practiceGoals': const [PracticeGoal.humorousReply],
        },
        // extendTopicStoryFrame
        {
          'heatScore': 50,
          'gameStage':
              const GameStageInfo(current: GameStage.premise, nextStep: ''),
        },
        // preferenceSignal
        {
          'heatScore': 50,
          'gameStage':
              const GameStageInfo(current: GameStage.premise, nextStep: ''),
          'practiceGoals': const [PracticeGoal.explainLess],
        },
        // fitCheck (default fallback)
        {
          'heatScore': 50,
          'gameStage':
              const GameStageInfo(current: GameStage.opening, nextStep: ''),
        },
      ];

      const forbiddenInTask = ['推拉', '製造焦慮', '反差', '人格', '型', '是 ... 的人'];
      const forbiddenInAvoid = ['消失', '不回', '已讀不回'];

      for (final t in triggers) {
        final card = CoachActionPolicy.evaluate(
          heatScore: t['heatScore'] as int,
          gameStage: t['gameStage'] as GameStageInfo,
          finalRecommendation: const FinalRecommendation(
            pick: 'extend',
            content: '',
            reason: '',
            psychology: '',
          ),
          messages: (t['messages'] as List<Message>?) ?? const [],
          practiceGoals:
              (t['practiceGoals'] as List<PracticeGoal>?) ?? const [],
          isDataQualityFlagged: false,
          psychology: t['psychology'] as PsychologyAnalysis?,
        );
        for (final word in forbiddenInTask) {
          expect(
            card.task.contains(word),
            isFalse,
            reason: '${card.actionLabel} task leaked forbidden token "$word"',
          );
        }
        for (final word in forbiddenInAvoid) {
          expect(
            card.avoid.contains(word),
            isFalse,
            reason: '${card.actionLabel} avoid leaked forbidden token "$word"',
          );
        }
      }
    });
  });
}
