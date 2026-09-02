import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/data/services/analysis_transport_support.dart';

void main() {
  group('recognitionFailureMessage', () {
    test('模型給的英文摘要不當錯誤訊息露出', () {
      expect(
        recognitionFailureMessage(
          'The screenshot does not contain a chat conversation.',
        ),
        '無法辨識截圖中的對話',
      );
      expect(recognitionFailureMessage(null), '無法辨識截圖中的對話');
      expect(recognitionFailureMessage('   '), '無法辨識截圖中的對話');
    });

    test('繁中摘要可以直接給使用者看', () {
      expect(
        recognitionFailureMessage('這張截圖看起來是社群貼文，不是聊天對話'),
        '這張截圖看起來是社群貼文，不是聊天對話',
      );
    });
  });
}
