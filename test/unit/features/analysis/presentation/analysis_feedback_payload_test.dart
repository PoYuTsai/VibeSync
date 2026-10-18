import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/guide_v3_result.dart';
import 'package:vibesync/features/analysis/presentation/helpers/analysis_feedback_payload.dart';

GuideV3Result _result() => GuideV3Result.fromJson({
      'guideVersion': 'v3.5',
      'read': {
        'guideVersion': 'v3.5',
        'decision': 'send',
        'light': 'green',
        'judgment': '她有在接你的話。',
        'plannedCards': [
          {'slot': 1, 'task': 'accept', 'locked': false},
          {'slot': 2, 'task': 'push', 'locked': false},
        ],
      },
      'cards': [
        {
          'slot': 1,
          'task': 'accept',
          'method': 'reaction',
          'voice': 'default',
          'messages': ['那家我也想吃吃看'],
          'hasInventedDetail': false,
          'hasBlank': false,
        },
        {
          'slot': 2,
          'task': 'push',
          'method': 'reaction',
          'voice': 'default',
          'messages': ['週六下午一起去？'],
          'hasInventedDetail': false,
          'hasBlank': false,
        },
      ],
      'partial': false,
      'usage': {'messagesUsed': 1},
    })!;

void main() {
  test('v3 的負評分類（Eric 2026-10-18）：判斷不準、像在考她、編了我的事、太軟有客服感、其他', () {
    expect(
      [for (final (_, label) in kGuideV3FeedbackCategories) label],
      ['判斷不準', '像在考她', '編了我的事', '太軟有客服感', '其他'],
    );
  });

  test('存進分類欄的值只用資料庫已有的：像在考她先存成 other', () {
    expect(
      [
        for (final (id, _) in kGuideV3FeedbackCategories)
          guideV3FeedbackStoredCategory(id),
      ],
      ['wrong_judgment', 'other', 'invented_detail', 'too_beta', 'other'],
    );
    expect(guideV3FeedbackStoredCategory(null), isNull);
  });

  test('回饋帶伺服器 runId；負評再帶他選的 v3 分類', () {
    expect(
      guideV3FeedbackContext(
        _result(),
        runId: 'run-123',
        category: 'testing_her',
      ),
      {
        'guideVersion': 'v3.5',
        'decision': 'send',
        'light': 'green',
        'cardTasks': ['accept', 'push'],
        'runId': 'run-123',
        'feedbackCategory': 'testing_her',
      },
    );
    final positive = guideV3FeedbackContext(_result(), runId: null);
    expect(positive.containsKey('runId'), isFalse);
    expect(positive.containsKey('feedbackCategory'), isFalse);
  });
}
