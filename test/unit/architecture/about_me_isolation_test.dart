import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// 「關於我」只給 Coach 1:1（2026-08-04）的原始碼守門：開場救星與新話題的程式不得
// import 關於我或對象風格設定（user_profile 底下除了資料品質標記以外的檔案），
// 也不得直接引用讀關於我的 provider。2026-10-20 拆掉這兩邊的空管線時加上；
// 對話分析（lib/features/analysis）還在用 buildForAnalysis 的空管線，那側拆掉
// 之後再把它加進 scannedDirs。
const scannedDirs = ['lib/features/opener', 'lib/features/new_topic'];

/// user_profile 底下准許 import 的：資料品質標記（對象卡被標記時擋住生成），
/// 不是關於我。
bool isAllowedUserProfileImport(String path) {
  final file = path.split('/').last;
  return file == 'data_quality_flag_provider.dart' ||
      file.startsWith('partner_data_quality_');
}

const forbiddenIdentifiers = [
  'userProfileControllerProvider',
  'userProfileRepositoryProvider',
  'partnerStyleOverrideProvider',
  'partnerStyleRepositoryProvider',
  'effectiveStyleProvider',
  'effectiveStylePromptBuilderProvider',
  'EffectiveStylePromptBuilder',
];

final _directive = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
    multiLine: true);

Iterable<File> _dartFiles(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'));

void main() {
  test('開場救星與新話題不 import 關於我或對象風格設定', () {
    final violations = <String>[];
    var scanned = 0;
    for (final dir in scannedDirs) {
      for (final file in _dartFiles(dir)) {
        scanned++;
        for (final match in _directive.allMatches(file.readAsStringSync())) {
          final target = match.group(1)!;
          if (!target.contains('user_profile/')) continue;
          if (isAllowedUserProfileImport(target)) continue;
          violations.add('${file.path} → $target');
        }
      }
    }
    expect(scanned, greaterThan(10), reason: '掃描範圍不能意外變空');
    expect(violations, isEmpty);
  });

  test('開場救星與新話題不直接引用讀關於我的 provider 或 builder', () {
    final violations = <String>[];
    for (final dir in scannedDirs) {
      for (final file in _dartFiles(dir)) {
        final source = file.readAsStringSync();
        for (final identifier in forbiddenIdentifiers) {
          if (RegExp('\\b$identifier\\b').hasMatch(source)) {
            violations.add('${file.path} → $identifier');
          }
        }
      }
    }
    expect(violations, isEmpty);
  });

  test('守門規則本身：資料品質標記准許，其他 user_profile 檔案不准', () {
    expect(
        isAllowedUserProfileImport(
            '../../../user_profile/data/providers/data_quality_flag_provider.dart'),
        isTrue);
    expect(
        isAllowedUserProfileImport(
            'package:vibesync/features/user_profile/data/repositories/partner_data_quality_repository.dart'),
        isTrue);
    for (final path in [
      '../../../user_profile/data/providers/user_profile_providers.dart',
      '../../../user_profile/data/providers/partner_style_providers.dart',
      'package:vibesync/features/user_profile/domain/services/effective_style_prompt_builder.dart',
      '../../../user_profile/domain/entities/user_profile.dart',
    ]) {
      expect(isAllowedUserProfileImport(path), isFalse, reason: path);
    }
  });
}
