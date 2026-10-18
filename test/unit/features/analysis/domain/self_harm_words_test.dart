import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/services/self_harm_words.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

// 額度不夠時的自傷關心（Eric 2026-10-18）：App 用這份字眼決定要不要跳過額度不足的框，
// 伺服器用 guide_v3/safety.ts 那一份決定要不要直接回關心訊息，兩份不能各改各的。
void main() {
  var id = 0;
  Message her(String content, {String? quoted}) => Message(
        id: 'her-${id++}',
        content: content,
        isFromMe: false,
        timestamp: DateTime(2026, 10, 18, 10),
        quotedReplyPreview: quoted,
      );
  Message me(String content) => Message(
        id: 'me-${id++}',
        content: content,
        isFromMe: true,
        timestamp: DateTime(2026, 10, 18, 9),
      );

  test('伺服器 safety.ts 的自傷字眼跟 App 的繁體清單一樣（只改一邊就會失敗）', () {
    final source = File('supabase/functions/analyze-chat/guide_v3/safety.ts')
        .readAsStringSync();
    final match =
        RegExp(r'const SELF_HARM_WORDS = /([^/]+)/u;').firstMatch(source);
    expect(match, isNotNull, reason: '找不到伺服器的 SELF_HARM_WORDS');
    expect(
      match!.group(1)!.split('|').toSet(),
      SelfHarmWords.traditional.toSet(),
    );
    expect(SelfHarmWords.traditional, hasLength(5));
  });

  test('她的訊息有任何一個字就算，含簡體寫法', () {
    for (final word in [
      ...SelfHarmWords.traditional,
      ...SelfHarmWords.simplified,
    ]) {
      expect(
        SelfHarmWords.inHerMessages([me('最近還好嗎'), her('其實我有$word的念頭')]),
        isTrue,
        reason: word,
      );
    }
  });

  test('只看她自己的訊息：他說的、她引用的內容都不算', () {
    expect(
      SelfHarmWords.inHerMessages([me('我真的不想活了'), her('怎麼了？')]),
      isFalse,
    );
    expect(
      SelfHarmWords.inHerMessages([her('先好好休息吧', quoted: '我真的不想活了')]),
      isFalse,
    );
  });

  test('沒有那五個字就不算：想死、熱死了、未成年都不算', () {
    for (final content in ['我好想死', '今天熱死了', '我今年高二', '殺價殺很大']) {
      expect(
        SelfHarmWords.inHerMessages([her(content)]),
        isFalse,
        reason: content,
      );
    }
  });
}
