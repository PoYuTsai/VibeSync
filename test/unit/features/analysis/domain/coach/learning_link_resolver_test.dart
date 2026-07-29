// test/unit/features/analysis/domain/coach/learning_link_resolver_test.dart
//
// 教練動作卡深連的逐筆鎖定。
//
// 這裡鎖「哪個動作連到哪一章」的具體對應，而不只是「有值」——因為改錯
// 一筆的症狀是連到一章不相干的內容，畫面完全正常、沒有任何錯誤訊息。
//
// 章節是否真實存在、chip 清單有沒有漂移，由
// test/unit/features/learning/dating_knowledge_links_test.dart 守。
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/coach/coach_action_type.dart';
import 'package:vibesync/features/analysis/domain/coach/learning_link_resolver.dart';

void main() {
  group('LearningLinkResolver.resolve', () {
    void expectTarget(
      CoachActionType type,
      String bookId,
      String chapterId,
    ) {
      final target = LearningLinkResolver.resolve(type);
      expect(target, isNotNull, reason: '$type 應該要有深連目標');
      expect(target!.bookId, bookId);
      expect(target.chapterId, chapterId);
    }

    test('模糊邀約 → 第 4 冊「種子：模糊的是時間，不是對象」', () {
      expectTarget(
        CoachActionType.softInvite,
        'ebook-4-meeting',
        'ebook-4-chapter-2',
      );
    });

    test('降低壓力 → 第 2 冊「對話為什麼死」（死因一：查戶口）', () {
      expectTarget(
        CoachActionType.lowerPressureReply,
        'ebook-2-conversation',
        'ebook-2-chapter-2',
      );
    });

    test('故事框架 → 第 2 冊「回應性與側面價值」', () {
      expectTarget(
        CoachActionType.extendTopicStoryFrame,
        'ebook-2-conversation',
        'ebook-2-chapter-3',
      );
    });

    test('情緒共鳴 → 第 2 冊「回應性與側面價值」', () {
      expectTarget(
        CoachActionType.emotionalResonance,
        'ebook-2-conversation',
        'ebook-2-chapter-3',
      );
    });

    test('回得剛剛好 → 第 2 冊「變數標記法」（三燈：對稱 vs 加碼）', () {
      expectTarget(
        CoachActionType.rightSizeReply,
        'ebook-2-conversation',
        'ebook-2-chapter-1',
      );
    });

    test('輕鬆幽默 → 第 2 冊「情緒、玩笑與訊號讀取」', () {
      expectTarget(
        CoachActionType.playfulReply,
        'ebook-2-conversation',
        'ebook-2-chapter-4',
      );
    });

    test('暫停追問 → 第 3 冊「診斷樹」', () {
      expectTarget(
        CoachActionType.pausePursuit,
        'ebook-3-rescue',
        'ebook-3-chapter-1',
      );
    });

    test('輕量表達偏好 → 第 2 冊「對話為什麼死」（死因三：你沒出現在對話裡）', () {
      expectTarget(
        CoachActionType.preferenceSignal,
        'ebook-2-conversation',
        'ebook-2-chapter-2',
      );
    });

    test('互動品質觀察 → 第 3 冊「診斷樹」', () {
      expectTarget(
        CoachActionType.fitCheck,
        'ebook-3-rescue',
        'ebook-3-chapter-1',
      );
    });

    test('每個動作型別都有 exact 深連，沒有 fallback 分類頁', () {
      for (final type in CoachActionType.values) {
        expect(
          LearningLinkResolver.resolve(type),
          isNotNull,
          reason: '$type 應該對到一個明確章節',
        );
      }
    });

    test('沒有任何目標帶 entryId（目前全部落在章首）', () {
      for (final type in CoachActionType.values) {
        expect(LearningLinkResolver.resolve(type)?.entryId, isNull);
      }
    });
  });
}
