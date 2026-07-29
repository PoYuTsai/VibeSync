// test/unit/features/learning/dating_knowledge_links_test.dart
//
// Dating Knowledge Library 深連對照表的漂移守門。
//
// 為什麼要這一支：2026-07-28 AI 鍵盤事故的根因就是「模型端 taxonomy 改了、
// 另一端的白名單沒跟著改」——Deno 測試全綠，功能卻從來沒成功過。深連是
// 同一類東西，有三邊要對齊：
//   1. 對照表裡的 bookId / chapterId
//   2. assets/learning/ebooks/*.json 裡真實存在的章節
//   3. 各 widget 自己的 chip 清單（phase 字串 / 問句文案）
// 任何一邊單獨改動都會讓入口靜默連錯或消失，使用者不會看到錯誤訊息。
//
// 這裡刻意斷言「語意」而不只是「存在」：不是檢查表非空，而是逐筆比對到
// 真實章節，並反向檢查每個 chip 都有對應。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/coach/coach_action_type.dart';
import 'package:vibesync/features/analysis/domain/coach/learning_link_resolver.dart';
import 'package:vibesync/features/learning/domain/dating_knowledge_links.dart';
import 'package:vibesync/features/learning/domain/models/learning_link_target.dart';

/// 從 JSON 資產讀出所有真實存在的 (bookId, chapterId)。
Set<String> _realChapterKeys() {
  final dir = Directory('assets/learning/ebooks');
  final keys = <String>{};
  for (final file in dir.listSync().whereType<File>()) {
    if (!file.path.endsWith('.json')) continue;
    final decoded =
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final bookId = decoded['id'] as String;
    for (final chapter in (decoded['chapters'] as List)) {
      final chapterId = (chapter as Map<String, dynamic>)['id'] as String;
      keys.add('$bookId::$chapterId');
    }
  }
  return keys;
}

String _key(LearningLinkTarget t) => '${t.bookId}::${t.chapterId}';

void main() {
  late Set<String> realChapters;

  setUpAll(() {
    realChapters = _realChapterKeys();
  });

  test('資產真的被讀到了（守門本身沒有空跑）', () {
    // 4 冊 × 5 章。這條在於：如果路徑寫錯導致讀到空集合，
    // 下面所有「存在性」斷言都會變成假通過。
    expect(realChapters.length, 20);
  });

  group('教練動作卡（本回合怎麼接）', () {
    test('每個 CoachActionType 都有深連目標', () {
      for (final type in CoachActionType.values) {
        expect(
          LearningLinkResolver.resolve(type),
          isNotNull,
          reason: 'CoachActionType.$type 沒有對應章節，卡片會隱藏教學入口',
        );
      }
    });

    test('每個目標都指向真實存在的章節', () {
      for (final type in CoachActionType.values) {
        final target = LearningLinkResolver.resolve(type);
        if (target == null) continue;
        expect(
          realChapters.contains(_key(target)),
          isTrue,
          reason: 'CoachActionType.$type 指向不存在的章節 ${_key(target)}',
        );
      }
    });

    test('目標一律是電子書章節，不再是舊的 numeric article id', () {
      for (final type in CoachActionType.values) {
        final target = LearningLinkResolver.resolve(type);
        if (target == null) continue;
        expect(target.bookId.startsWith('ebook-'), isTrue);
        expect(target.chapterId.startsWith('ebook-'), isTrue);
      }
    });
  });

  group('Coach 1:1 對照表', () {
    test('教練跟進三情境的目標都存在', () {
      for (final entry in DatingKnowledgeLinks.followUpPhaseTable.entries) {
        expect(
          realChapters.contains(_key(entry.value)),
          isTrue,
          reason: 'phase "${entry.key}" 指向不存在的章節 ${_key(entry.value)}',
        );
      }
    });

    test('問教練一句五個快捷問句的目標都存在', () {
      for (final entry in DatingKnowledgeLinks.coachQuestionTable.entries) {
        expect(
          realChapters.contains(_key(entry.value)),
          isTrue,
          reason: '問句 "${entry.key}" 指向不存在的章節 ${_key(entry.value)}',
        );
      }
    });

    test('查不到的 key 回 null，不 fallback 到任何一章', () {
      expect(DatingKnowledgeLinks.forFollowUpPhase(null), isNull);
      expect(DatingKnowledgeLinks.forFollowUpPhase('nonexistentPhase'), isNull);
      expect(DatingKnowledgeLinks.forCoachQuestion(null), isNull);
      expect(DatingKnowledgeLinks.forCoachQuestion('隨便打的問句'), isNull);
      // prefill 是完整句子而不是 chip 文案，查表本來就該落空。
      expect(
        DatingKnowledgeLinks.forCoachQuestion('我們聊天卡住了，接下來該怎麼辦？'),
        isNull,
      );
    });
  });

  group('widget chip 清單與對照表沒有漂移', () {
    // 兩份 chip 清單是 widget 內的 private const，測試讀原始碼比對。
    // 這比「兩邊各自維護」多一道保險：改了文案忘了改表，這裡就會紅。

    test('教練跟進的每個 phase 都在對照表裡', () {
      final source = File(
        'lib/features/coach_follow_up/presentation/widgets/'
        'coach_follow_up_section.dart',
      ).readAsStringSync();
      final phases = RegExp(r"\(phase: '([^']+)'")
          .allMatches(source)
          .map((m) => m.group(1)!)
          .toSet();

      expect(phases, isNotEmpty, reason: 'chip 清單解析失敗，守門會變成空跑');
      for (final phase in phases) {
        expect(
          DatingKnowledgeLinks.followUpPhaseTable.containsKey(phase),
          isTrue,
          reason: 'chip phase "$phase" 沒有對應章節；'
              '改了 chip 就要同步 dating_knowledge_links.dart',
        );
      }
    });

    test('對照表沒有多出 widget 已經不存在的 phase', () {
      final source = File(
        'lib/features/coach_follow_up/presentation/widgets/'
        'coach_follow_up_section.dart',
      ).readAsStringSync();
      for (final phase in DatingKnowledgeLinks.followUpPhaseTable.keys) {
        expect(
          source.contains("(phase: '$phase'"),
          isTrue,
          reason: '對照表有 "$phase" 但 widget 已經沒有這個 chip 了',
        );
      }
    });

    test('問教練一句的每個 chip 文案都在對照表裡', () {
      final source = File(
        'lib/features/coach_chat/presentation/widgets/coach_surface.dart',
      ).readAsStringSync();
      final block = RegExp(
        r'static const _chips = <String>\[(.*?)\];',
        dotAll: true,
      ).firstMatch(source);
      expect(block, isNotNull, reason: 'chip 清單解析失敗，守門會變成空跑');

      final chips = RegExp("'([^']+)'")
          .allMatches(block!.group(1)!)
          .map((m) => m.group(1)!)
          .toSet();
      expect(chips.length, 5);

      for (final chip in chips) {
        expect(
          DatingKnowledgeLinks.coachQuestionTable.containsKey(chip),
          isTrue,
          reason: '快捷問句 "$chip" 沒有對應章節；'
              '改了文案就要同步 dating_knowledge_links.dart',
        );
      }
    });

    test('對照表沒有多出 widget 已經不存在的問句', () {
      final source = File(
        'lib/features/coach_chat/presentation/widgets/coach_surface.dart',
      ).readAsStringSync();
      for (final chip in DatingKnowledgeLinks.coachQuestionTable.keys) {
        expect(
          source.contains("'$chip'"),
          isTrue,
          reason: '對照表有 "$chip" 但 widget 已經沒有這個 chip 了',
        );
      }
    });
  });
}
