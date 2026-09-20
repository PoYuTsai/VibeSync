// 兩段式資料型別：防禦式解析、回答狀態、一行摘要、明確矛盾（附件 §4.4、§10）。
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/opener/domain/opener_flow_models.dart';

Map<String, dynamic> _analysisJson({Map<String, dynamic>? question}) => {
      'stage': 'analyze',
      'sessionId': 'sess-1',
      'analysisRevision': 1,
      'expiresAt': '2026-09-18T12:00:00Z',
      'approach': {'mode': 'anchor_hooks', 'summary': '可以從她的狗開', 'avoid': ['不用回應抱怨', '二', '三']},
      'cues': [
        {'id': 'cue_1', 'label': '養狗', 'source': 'profile_text', 'evidence': {'field': 'bio', 'quote': '有養一隻狗'}},
        {'id': 'cue_2', 'label': '河堤', 'source': 'image', 'evidence': {'imageIndex': 1, 'visible': '河堤背景'}},
        {'label': '沒有 id 的壞線索'},
      ],
      'question': question ??
          {
            'id': 'question_1',
            'affects': 'sender_fact',
            'text': '你跟養狗這件事比較接近哪種？',
            'options': [
              {'id': 'option_1', 'label': '我自己有養', 'meaning': 'assert_sender_fact', 'cueId': 'cue_1', 'statement': '我有養狗'},
              {'id': 'option_2', 'label': '沒養，但有興趣', 'meaning': 'curious_without_experience', 'cueId': 'cue_1'},
              {'id': 'option_3', 'label': '其實想聊別的', 'meaning': 'change_direction'},
            ],
          },
      'usage': {'chargedNow': 0, 'firstGenerationCost': 3, 'includedGenerationCount': 3, 'generationsUsed': 0, 'quotaCharged': false},
    };

void main() {
  group('OpenerAnalysis.tryParse', () {
    test('解析分析、線索證據、題目；壞線索丟掉、avoid 最多兩點', () {
      final analysis = OpenerAnalysis.tryParse(_analysisJson())!;
      expect(analysis.sessionId, 'sess-1');
      expect(analysis.cues.map((c) => c.id), ['cue_1', 'cue_2']);
      expect(analysis.cues[0].evidence!.describe(), '自我介紹：「有養一隻狗」');
      expect(analysis.cues[1].evidence!.describe(), '第 1 張截圖：河堤背景');
      expect(analysis.approach.avoid, ['不用回應抱怨', '二']);
      expect(analysis.question!.options.length, 3);
      expect(analysis.firstGenerationCost, 3);
      expect(analysis.generationsRemaining, 3);
      expect(analysis.isExpiredAt(DateTime.utc(2026, 9, 18, 11)), isFalse);
      expect(analysis.isExpiredAt(DateTime.utc(2026, 9, 18, 12)), isTrue);
    });

    test('題目少於兩個合法選項→null（零題）；缺 sessionId／expiresAt→整份 null', () {
      final noQuestion = OpenerAnalysis.tryParse(_analysisJson(question: {
        'id': 'q', 'text': 'x', 'options': [{'id': 'o1', 'label': 'a', 'meaning': 'pick_cue'}],
      }))!;
      expect(noQuestion.question, isNull);
      expect(OpenerAnalysis.tryParse({..._analysisJson(), 'sessionId': null}), isNull);
      expect(OpenerAnalysis.tryParse({..._analysisJson(), 'expiresAt': 'not-a-date'}), isNull);
    });

    test('JSON 往返後內容一致（草稿保存用）', () {
      final analysis = OpenerAnalysis.tryParse(_analysisJson())!;
      final restored = OpenerAnalysis.tryParse(analysis.toJson())!;
      expect(restored.toJson(), analysis.toJson());
    });
  });

  group('OpenerContributionDraft.toContribution', () {
    final question = OpenerAnalysis.tryParse(_analysisJson())!.question;

    test('有選項或文字＝answered；只有題目未回答＝no_answer；按略過＝skipped', () {
      expect(const OpenerContributionDraft(selectedOptionId: 'option_2').toContribution(question).toJson(), {
        'state': 'answered', 'questionId': 'question_1', 'selectedOptionId': 'option_2',
      });
      expect(const OpenerContributionDraft(freeText: ' 我妹也是美容師 ').toContribution(question).toJson(), {
        'state': 'answered', 'freeText': '我妹也是美容師',
      });
      expect(const OpenerContributionDraft().toContribution(question).toJson(), {'state': 'no_answer'});
      expect(const OpenerContributionDraft(skipped: true).toContribution(question).toJson(), {'state': 'skipped'});
    });

    test('選了不存在於本題的選項＝視同沒選（不把假選項送上伺服器）', () {
      final contribution = const OpenerContributionDraft(selectedOptionId: 'option_9', freeText: '狗').toContribution(question);
      expect(contribution.selectedOptionId, isNull);
      expect(contribution.questionId, isNull);
      expect(contribution.freeText, '狗');
    });

    test('題目為 null 時不帶 questionId／selectedOptionId', () {
      final contribution = const OpenerContributionDraft(selectedOptionId: 'option_1', freeText: '想聊咖啡').toContribution(null);
      expect(contribution.toJson(), {'state': 'answered', 'freeText': '想聊咖啡'});
    });
  });

  group('OpenerContributionSummary', () {
    final analysis = OpenerAnalysis.tryParse(_analysisJson())!;

    test('只組合已選選項與用戶原文，不打模型；略過有專屬文案；空＝null', () {
      expect(
        OpenerContributionSummary.compose(question: analysis.question, draft: const OpenerContributionDraft(selectedOptionId: 'option_2', freeText: '只想知道牠散步會不會自己選路'), cues: analysis.cues),
        '從「養狗」聊起；你只是好奇，不寫成你也有；你補充：「只想知道牠散步會不會自己選路」',
      );
      expect(
        OpenerContributionSummary.compose(question: analysis.question, draft: const OpenerContributionDraft(selectedOptionId: 'option_1'), cues: analysis.cues),
        '你自己「我有養狗」，可以當共同點',
      );
      expect(
        OpenerContributionSummary.compose(question: analysis.question, draft: const OpenerContributionDraft(selectedOptionId: 'option_3'), cues: analysis.cues),
        '這些線索都先不接，另開話題',
      );
      expect(OpenerContributionSummary.compose(question: analysis.question, draft: const OpenerContributionDraft(skipped: true), cues: analysis.cues), '略過補充，用她的資料直接生成');
      expect(OpenerContributionSummary.compose(question: analysis.question, draft: const OpenerContributionDraft(), cues: analysis.cues), isNull);
    });
  });

  group('OpenerContributionConflict', () {
    final analysis = OpenerAnalysis.tryParse(_analysisJson())!;

    test('選「狗」又寫「不要聊狗」→ 明確矛盾；寫「不想聊工作」不算', () {
      final option = analysis.question!.optionById('option_2');
      expect(OpenerContributionConflict.optionNegatedByText(option: option, cues: analysis.cues, freeText: '不要聊養狗了，想問她照片那間咖啡店'), isTrue);
      expect(OpenerContributionConflict.optionNegatedByText(option: option, cues: analysis.cues, freeText: '不想聊她的工作'), isFalse);
      expect(OpenerContributionConflict.optionNegatedByText(option: option, cues: analysis.cues, freeText: '改聊咖啡'), isTrue, reason: '明確的「改聊…」覆蓋先前選擇');
      expect(OpenerContributionConflict.optionNegatedByText(option: analysis.question!.optionById('option_3'), cues: analysis.cues, freeText: '不要聊養狗'), isFalse);
      expect(OpenerContributionConflict.optionNegatedByText(option: null, cues: analysis.cues, freeText: '不要聊養狗'), isFalse);
    });
  });

  group('OpenerGeneration.fromServerBody', () {
    test('攤平的伺服器 body → 結果、來源核對、用量；requestId＝generationId', () {
      final generation = OpenerGeneration.fromServerBody({
        'stage': 'generate',
        'sessionId': 'sess-1',
        'generationId': 'gen-1',
        'expiresAt': '2026-09-18T12:00:00Z',
        'openers': {'extend': '牠散步會自己選路嗎', 'humor': '導航派還是隨機派', 'tease': '妳家狗比妳會排行程'},
        'recommendation': {'pick': 'extend', 'reason': '直接問你想知道的事'},
        'cardReasons': {'extend': '直接問你想知道的事', 'humor': '可愛的問題'},
        'materialUse': {'inputState': 'answered', 'references': [{'style': 'extend', 'materialId': 'material_1', 'outputSpan': '散步會自己選路'}], 'traceStatus': 'matched', 'displayNote': '這句接的是你想知道的散步習慣'},
        'access': {'contractVersion': 2, 'servedTier': 'free', 'visibleTypes': ['extend', 'humor', 'tease'], 'lockedTypes': ['resonate', 'coldRead']},
        'usage': {'chargedNow': 3, 'sessionChargedTotal': 3, 'generationsUsed': 1, 'generationsRemaining': 2, 'replayed': false, 'cost': 3},
      }, contribution: const OpenerContribution(state: OpenerContributionState.answered, freeText: '沒養過'))!;
      expect(generation.result.requestId, 'gen-1');
      expect(generation.result.recommendedPick, 'extend');
      expect(generation.result.costUsed, 3);
      expect(generation.result.access!.servedTier, 'free');
      expect(generation.materialUse.matched, isTrue);
      expect(generation.materialUse.displayNote, '這句接的是你想知道的散步習慣');
      expect(generation.materialUse.styleReferenced('extend'), isTrue);
      expect(generation.usage.generationsRemaining, 2);
      final restored = OpenerGeneration.tryParse(generation.toJson())!;
      expect(restored.toJson(), generation.toJson());
    });

    test('沒有任何開場白→null（不交付空結果）', () {
      expect(OpenerGeneration.fromServerBody({'sessionId': 's', 'generationId': 'g', 'expiresAt': '2026-09-18T12:00:00Z', 'openers': {}}, contribution: const OpenerContribution(state: OpenerContributionState.skipped)), isNull);
    });
  });
}
