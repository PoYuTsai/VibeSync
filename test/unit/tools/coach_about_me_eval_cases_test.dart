import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';
import 'package:vibesync/features/user_profile/domain/services/effective_style_prompt_builder.dart';

// 教練「關於我」成對評測（tools/coach-about-me-eval，規格 PR-6）的題目要用 App 真正
// 送出的文字：每一題的 aboutMe 必須等於 buildForCoachFollowUp 用同一份 profile 組出
// 來的結果。App 組字改了而題目沒重產，這裡會失敗。
//
// 規格 PR-7 起 App 不再送互動風格，PR-7 之前的舊版 App 還會送。題庫裡帶風格的題目
// （U4、S1–S4，只填了風格）保留舊版格式：拿掉四行風格之後只剩使用範圍那行，而現在
// 的 App 對同一份 profile 什麼都不送。
const _legacyStylePrefixes = [
  '- 主要互動風格：',
  '- 次要互動風格：',
  '- 建議句長度：',
  '- 問句密度：',
];

void main() {
  test('coach-about-me-eval cases carry the exact App About Me text', () {
    final catalog = jsonDecode(
      File('tools/coach-about-me-eval/cases.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final cases = (catalog['cases'] as List).cast<Map<String, dynamic>>();
    expect(cases, hasLength(36));
    const builder = EffectiveStylePromptBuilder();
    for (final c in cases) {
      final profile = c['profile'] as Map<String, dynamic>?;
      final expected = profile == null
          ? null
          : builder.buildForCoachFollowUp(
              global: UserProfile.create(
                interactionStyle: profile['style'] == null
                    ? null
                    : InteractionStyle.values.byName(profile['style'] as String),
                secondaryStyle: profile['secondaryStyle'] == null
                    ? null
                    : InteractionStyle.values
                        .byName(profile['secondaryStyle'] as String),
                practiceGoals: [
                  for (final g in (profile['goals'] as List? ?? const []))
                    PracticeGoal.values.byName(g as String),
                ],
                stuckPoints: [
                  for (final s in (profile['stuckPoints'] as List? ?? const []))
                    StuckPoint.values.byName(s as String),
                ],
                notes: profile['notes'] as String?,
                updatedAt: DateTime.utc(2026, 10, 21),
              ),
            );
      final request = c['request'] as Map<String, dynamic>;
      if (profile?['style'] != null) {
        final remaining = (c['aboutMe'] as String)
            .split('\n')
            .where((line) => !_legacyStylePrefixes.any(line.startsWith))
            .toList();
        expect(remaining, [EffectiveStylePromptBuilder.coachFollowUpScopeLine],
            reason: '${c['id']} 是舊版 App 格式：只有風格行加使用範圍');
        expect(expected, isNull, reason: '${c['id']} 現在的 App 不送舊風格');
        expect(request['effectiveStyleContext'], c['aboutMe'],
            reason: '${c['id']} 送出的 effectiveStyleContext');
        continue;
      }
      expect(c['aboutMe'], expected, reason: c['id'] as String);
      expect(request['effectiveStyleContext'], expected,
          reason: '${c['id']} 送出的 effectiveStyleContext');
    }
  });
}
