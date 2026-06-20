/// 把同一份分析資料衍生成不同用途的短/長文案，讓各 widget 共用同一套派生規則，
/// 不再各自 substring 同一段 nextStep（資訊架構去重）。純資料、零 AI 邊際成本。
///
/// - [tacticalHook]：短抓手（主特質 ＋ 主興趣），給總覽卡與作戰板入口卡 preview。
/// - [topicsLine]：可接話題（興趣前幾項），給入口卡 preview 與作戰板詳情。
/// - [fullNextStep]：完整下一步整句，只給作戰板詳情 panel。
class PartnerInsightPresentation {
  final String? tacticalHook;
  final String? topicsLine;
  final String? fullNextStep;

  const PartnerInsightPresentation({
    this.tacticalHook,
    this.topicsLine,
    this.fullNextStep,
  });

  /// 興趣串成 topicsLine 時取的上限（避免 preview 一行爆版）。
  static const _kMaxTopics = 2;

  factory PartnerInsightPresentation.derive({
    List<String> interests = const [],
    List<String> traits = const [],
    String? nextStep,
  }) {
    final cleanInterests = _clean(interests);
    final cleanTraits = _clean(traits);

    // 抓手 = 主特質 ＋ 主興趣（各取首項、去重）。只有一邊有就用一邊。
    final hookParts = <String>[];
    if (cleanTraits.isNotEmpty) hookParts.add(cleanTraits.first);
    if (cleanInterests.isNotEmpty &&
        !hookParts.contains(cleanInterests.first)) {
      hookParts.add(cleanInterests.first);
    }

    final trimmedNextStep = nextStep?.trim();

    return PartnerInsightPresentation(
      tacticalHook: hookParts.isEmpty ? null : hookParts.join(' + '),
      topicsLine: cleanInterests.isEmpty
          ? null
          : cleanInterests.take(_kMaxTopics).join(' / '),
      fullNextStep: (trimmedNextStep == null || trimmedNextStep.isEmpty)
          ? null
          : trimmedNextStep,
    );
  }

  static List<String> _clean(List<String> values) =>
      values.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
}
