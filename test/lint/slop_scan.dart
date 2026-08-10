// 去 slop 防回歸掃描（DESIGN.md 階段 D，2026-08-10 Eric 拍板）。
//
// 四種機械可判定的 slop，逐檔計數，與 slop_baseline.json 棘輪比對：
// 新增（任一檔計數超過基準）＝測試紅；還債（低於基準）＝提示重產基準。
// 視覺判斷型 slop（卡片堆疊、間距節奏…）不在此列，靠 review＋DESIGN.md。
import 'dart:convert';
import 'dart:io';

/// 憲法圓角尺度（DESIGN.md §4）＋pill 慣用值。
const kAllowedRadii = {18, 22, 23, 24, 99, 999};

/// 彩色陰影白名單：DESIGN.md §7 刻意保留登記表的檔案。
const kColoredShadowAllowedFiles = {
  'lib/features/practice_chat/presentation/widgets/practice_room_entry_card.dart',
  'lib/features/practice_chat/presentation/screens/practice_collection_screen.dart',
  'lib/features/practice_chat/presentation/widgets/practice_draw_ceremony.dart',
  'lib/features/analysis/presentation/widgets/screenshot_recognition_dialog.dart',
  // 輸入框聚焦瞬態光（DESIGN.md §7）
  'lib/features/practice_chat/presentation/screens/practice_chat_screen.dart',
};

/// 硬寫 Color(0x…) 的豁免目錄／檔案：色票本體與正在服役的主題檔。
const kRawColorAllowedPrefixes = [
  'lib/core/theme/',
];

const kBrandShadowColorPattern =
    r'AppColors\.(ctaStart|ctaEnd|primary|primaryLight|primaryDark|'
    r'brandFlame|brandFlameDark|brandBlush|coachAccent|coachAccentBright|'
    r'bokeh\w*)';

final _fontSize = RegExp(r'fontSize:\s*(\d+(?:\.\d+)?)');
final _radius = RegExp(r'(?:BorderRadius|Radius)\.circular\(\s*(\d+)\s*\)');
final _rawColor = RegExp(r'\bColor\(0x');
final _boxShadow = RegExp(r'BoxShadow\(');
final _brandShadowColor = RegExp(
  r'BoxShadow\((?:[^)]|\n)*?color:\s*' + kBrandShadowColorPattern,
  multiLine: true,
);

bool _isComment(String line) => line.trimLeft().startsWith('//');

/// 單檔掃描 → {check: count}。
Map<String, int> scanSource(String path, String source) {
  final lines = source.split('\n');
  var tinyFont = 0;
  var offScaleRadius = 0;
  var rawColor = 0;

  final allowRaw =
      kRawColorAllowedPrefixes.any((prefix) => path.startsWith(prefix));
  for (final line in lines) {
    if (_isComment(line)) continue;
    for (final m in _fontSize.allMatches(line)) {
      if (double.parse(m.group(1)!) < 12) tinyFont++;
    }
    for (final m in _radius.allMatches(line)) {
      if (!kAllowedRadii.contains(int.parse(m.group(1)!))) offScaleRadius++;
    }
    if (!allowRaw) rawColor += _rawColor.allMatches(line).length;
  }

  var coloredShadow = 0;
  if (!kColoredShadowAllowedFiles.contains(path) &&
      _boxShadow.hasMatch(source)) {
    coloredShadow = _brandShadowColor.allMatches(source).length;
  }

  return {
    if (tinyFont > 0) 'tiny_font': tinyFont,
    if (offScaleRadius > 0) 'off_scale_radius': offScaleRadius,
    if (rawColor > 0) 'raw_color': rawColor,
    if (coloredShadow > 0) 'colored_shadow': coloredShadow,
  };
}

/// 掃整個 lib/ → {check: {file: count}}（穩定排序，供 JSON 基準）。
Map<String, Map<String, int>> scanLib(Directory root) {
  final result = <String, Map<String, int>>{};
  final files = root
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final path = file.path.replaceAll('\\', '/');
    final counts = scanSource(path, file.readAsStringSync());
    counts.forEach((check, count) {
      (result[check] ??= {})[path] = count;
    });
  }
  return result;
}

String encodeBaseline(Map<String, Map<String, int>> scan) =>
    const JsonEncoder.withIndent('  ').convert(scan);

Map<String, Map<String, int>> decodeBaseline(String json) {
  final raw = jsonDecode(json) as Map<String, dynamic>;
  return raw.map((check, files) => MapEntry(
        check,
        (files as Map<String, dynamic>).map(
          (path, count) => MapEntry(path, count as int),
        ),
      ));
}
