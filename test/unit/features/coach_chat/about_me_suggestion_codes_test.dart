import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';
import 'package:vibesync/features/user_profile/domain/services/effective_style_prompt_builder.dart';

// 規格 PR-9：教練「加到關於我」的代碼與標籤，App 與伺服器各鎖一份同樣的清單。
// 伺服器那份在 supabase/functions/coach-chat/about_me_suggestion.ts，它的測試在
// 同目錄的 prompts_test.ts；改 enum 或教練標籤要兩邊一起改。
const _serverFile = 'supabase/functions/coach-chat/about_me_suggestion.ts';

Map<String, String> _serverOptions(String source, String field) {
  final block = RegExp('$field: \\{([^}]*)\\}').firstMatch(source);
  expect(block, isNotNull, reason: '$_serverFile 找不到 $field 清單');
  return {
    for (final entry
        in RegExp(r'(\w+): "([^"]*)"').allMatches(block!.group(1)!))
      entry.group(1)!: entry.group(2)!,
  };
}

void main() {
  test('卡點與練習重點的代碼鎖定（伺服器用同樣的名字）', () {
    expect(StuckPoint.values.map((value) => value.name), [
      'fadesOut',
      'dontKnowHowToAsk',
      'anxiousWontSend',
      'overExplains',
      'leftOnRead',
    ]);
    expect(PracticeGoal.values.map((value) => value.name), [
      'softInvite',
      'comfortableChat',
      'humorousReply',
      'buildCloseness',
      'findCompatiblePartner',
    ]);
  });

  test('伺服器的代碼與標籤跟 App 的 enum 與教練讀到的標籤一致', () {
    final source = File(_serverFile).readAsStringSync();
    expect(_serverOptions(source, 'stuckPoint'), {
      for (final value in StuckPoint.values)
        value.name: EffectiveStylePromptBuilder.coachStuckPointLabel(value),
    });
    expect(_serverOptions(source, 'practiceGoal'), {
      for (final value in PracticeGoal.values)
        value.name: EffectiveStylePromptBuilder.coachGoalLabel(value),
    });
  });
}
