import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_hint.dart';

// ── W1（2026-08-06）：「本輪沒有可貼句」是合法結果 ──
// 她封鎖使用者時，硬擠兩句可貼回覆會被 server 守門打回並轉 503（真實事故：模型
// 自己判斷「沒有任何可貼句能送出」是對的，是系統接不住）。client 端要認得空
// replies + noPasteableReason 這個形狀，並在請求裡宣告自己認得——專案鐵則：
// 新的 server 輸出形狀必配 client 能力宣告，缺席一律 fail-closed。
void main() {
  group('W1 無可貼句', () {
    test('空 replies + noPasteableReason → 解析成功', () {
      final result = PracticeHintResult.fromJson({
        'replies': <dynamic>[],
        'noPasteableReason': '她已經明確要求停止聯絡並封鎖了你，這輪沒有任何適合送出的訊息。',
        'coaching': '她已經把界線畫死，再傳任何訊息都只會讓情況更糟。這裡要學的是收手。',
        'costDeducted': 1,
        'hintUsedCount': 3,
      });
      expect(result, isNotNull);
      expect(result!.replies, isEmpty);
      expect(result.noPasteableReason, isNotNull);
      expect(result.hasPasteableReplies, isFalse);
    });

    test('空 replies 但沒有 noPasteableReason → 判失敗（不得靜默給空畫面）', () {
      final result = PracticeHintResult.fromJson({
        'replies': <dynamic>[],
        'coaching': '教練說明',
        'costDeducted': 1,
        'hintUsedCount': 3,
      });
      expect(result, isNull);
    });

    // 2026-08-06 W3（Eric 拍板「零 503」）推翻了 W1 的「一般情形恰好兩句」：
    // salvage 對「兩句寫成同一句」去重後只剩一句，那一句仍是可用的建議，不該
    // 因為數量不是 2 就整份丟掉。零句仍然只有「本輪沒有可貼句」一種合法解釋。
    test('salvage 去重後只剩一句仍是合法結果', () {
      final result = PracticeHintResult.fromJson({
        'replies': <dynamic>[
          {'type': 'warm_up', 'label': '升溫回覆', 'text': '哈哈那我先不吵妳。'},
        ],
        'coaching': '教練說明',
        'costDeducted': 1,
        'hintUsedCount': 3,
      });
      expect(result, isNotNull);
      expect(result!.replies.length, 1);
      expect(result.noPasteableReason, isNull);
    });

    test('三句以上不是任何合法形狀', () {
      final result = PracticeHintResult.fromJson({
        'replies': <dynamic>[
          {'type': 'warm_up', 'label': '升溫回覆', 'text': '哈哈那我先不吵妳。'},
          {'type': 'steady', 'label': '穩住回覆', 'text': '那我等妳有空再說。'},
          {'type': 'steady', 'label': '穩住回覆', 'text': '多出來的第三句。'},
        ],
        'coaching': '教練說明',
        'costDeducted': 1,
        'hintUsedCount': 3,
      });
      expect(result, isNull);
    });

    test('noPasteableReason 跨 toJson/fromJson 來回不遺失', () {
      final original = PracticeHintResult.fromJson({
        'replies': <dynamic>[],
        'noPasteableReason': '她已經封鎖你了，這輪沒有可送出的訊息。',
        'coaching': '這裡要學的是收手。',
        'costDeducted': 1,
        'hintUsedCount': 3,
      })!;
      final restored = PracticeHintResult.fromJson(original.toJson());
      expect(restored, isNotNull);
      expect(restored!.noPasteableReason, original.noPasteableReason);
      expect(restored.replies, isEmpty);
    });
  });
}
