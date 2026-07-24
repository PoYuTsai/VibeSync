/// 公式回覆 client 端守門（2026-07-24 公式回覆計畫 §9）。
///
/// Server canonical（supabase/functions/analyze-chat/formula_reply.ts）是
/// 主防線；這裡是 cache／transport defense-in-depth，同一組規則的 Dart 鏡像：
/// - 兩欄皆為非空 string；cap 以 Unicode code points（`runes.length`）計，
///   對齊 TS `[...text].length` 與 PostgreSQL `char_length()`。
/// - code fence／raw JSON／schema key 洩漏丟整則。
/// - 明顯內部作戰板標籤丟整則（只擋明確標籤，不做廣泛禁詞掃描）。
/// - 最多收兩則；壞項只丟該則，絕不影響原 opener/topic 結果。
library;

const kFormulaOpeningLineMaxRunes = 180;
const kFormulaWhyItWorksMaxRunes = 300;
const kFormulaReplyMaxCount = 2;

const kFormulaInternalLabels = [
  '對象作戰板',
  '對方作戰板',
  '最近熱度',
  '累計對話',
  '你的備註',
  '過往備註',
  '性格分析',
  '資料顯示',
  '系統判斷',
];

/// 單欄守門：合法回 trim 後字串，壞回 null（呼叫端丟整則）。
String? sanitizeFormulaReplyField(dynamic value, int maxRunes) {
  if (value is! String) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.runes.length > maxRunes) return null;
  if (trimmed.contains('```')) return null;
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) return null;
  final lower = trimmed.toLowerCase();
  if (lower.contains('"formulaopeners"') ||
      lower.contains('"formulatopics"') ||
      lower.contains('"openingline"') ||
      lower.contains('"whyitworks"') ||
      lower.contains('"openers"') ||
      lower.contains('"topics"')) {
    return null;
  }
  for (final label in kFormulaInternalLabels) {
    if (trimmed.contains(label)) return null;
  }
  return trimmed;
}

/// 單則守門：兩欄俱全才回 record；否則 null。
({String openingLine, String whyItWorks})? parseFormulaReplyItem(
  dynamic value,
) {
  if (value is! Map) return null;
  final openingLine = sanitizeFormulaReplyField(
    value['openingLine'],
    kFormulaOpeningLineMaxRunes,
  );
  final whyItWorks = sanitizeFormulaReplyField(
    value['whyItWorks'],
    kFormulaWhyItWorksMaxRunes,
  );
  if (openingLine == null || whyItWorks == null) return null;
  return (openingLine: openingLine, whyItWorks: whyItWorks);
}

/// Best-effort 清單守門：非 List 回空；依原始順序收滿兩則合法即停。
List<({String openingLine, String whyItWorks})> parseFormulaReplyList(
  dynamic value,
) {
  if (value is! List) return const [];
  final replies = <({String openingLine, String whyItWorks})>[];
  for (final item in value) {
    if (replies.length >= kFormulaReplyMaxCount) break;
    final parsed = parseFormulaReplyItem(item);
    if (parsed != null) replies.add(parsed);
  }
  return replies;
}
