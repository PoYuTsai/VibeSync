import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';
import 'package:vibesync/features/user_profile/domain/services/effective_style_prompt_builder.dart';

// 教練「關於我」成對評測（tools/coach-about-me-eval，規格 PR-6）的題目要用 App 真正
// 送出的文字：每一題的 aboutMe 必須等於 buildForCoachFollowUp 用同一份 profile 組出
// 來的結果。App 組字改了而題目沒重產，這裡會失敗。
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
              partner: null,
              includePartnerOverride: false,
            );
      expect(c['aboutMe'], expected, reason: c['id'] as String);
      final request = c['request'] as Map<String, dynamic>;
      expect(request['effectiveStyleContext'], expected,
          reason: '${c['id']} 送出的 effectiveStyleContext');
    }
  });
}
