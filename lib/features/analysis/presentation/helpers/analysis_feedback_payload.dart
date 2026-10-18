/// 對話分析 v3 的回饋內容（Eric 2026-10-18）：v3 自己的負評分類，以及送給
/// submit-feedback 的 v3 欄位（帶伺服器 runId，負評才對得回是哪一次、哪一組卡）。
library;

import '../../domain/entities/guide_v3_result.dart';

/// v3 的負評分類。前四類沿用資料庫已有的分類值（跟 Coach 1:1 同一套）；「像在
/// 考她」資料庫還沒有對應值，送出時存成 other，確切分類另外帶在
/// guideV3.feedbackCategory（見 [guideV3FeedbackStoredCategory]）。
const kGuideV3FeedbackCategories = <(String, String)>[
  ('wrong_judgment', '判斷不準'),
  ('testing_her', '像在考她'),
  ('invented_detail', '編了我的事'),
  ('too_beta', '太軟有客服感'),
  ('other', '其他'),
];

/// 送進 feedback.category 欄的值：資料庫有固定清單（migration
/// 20260901120000），還沒有對應值的 v3 分類先存成 other。
String? guideV3FeedbackStoredCategory(String? category) =>
    category == 'testing_her' ? 'other' : category;

/// aiResponse.guideV3：判讀、燈號、任務、伺服器 runId（跟卡片的成效紀錄同一個），
/// 負評時再帶他選的 v3 分類。
Map<String, dynamic> guideV3FeedbackContext(
  GuideV3Result result, {
  String? runId,
  String? category,
}) =>
    {
      'guideVersion': result.read.guideVersion,
      'decision': result.read.decision.wire,
      if (result.read.light != null) 'light': result.read.light!.wire,
      'cardTasks': [for (final card in result.cards) card.task.wire],
      if (runId != null && runId.isNotEmpty) 'runId': runId,
      if (category != null) 'feedbackCategory': category,
    };
