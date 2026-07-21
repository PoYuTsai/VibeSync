import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/coach_chat/data/services/coach_request_id_session.dart';

/// 依序回傳定值序列的 factory，驗證生命週期何時鑄新 id。
String Function() _sequenceFactory(List<String> ids) {
  var index = 0;
  return () => ids[index++];
}

void main() {
  group('CoachRequestIdSession', () {
    test('首呼 begin 鑄新 id；同 signature 重呼（重試）沿用同一 id', () {
      final session = CoachRequestIdSession(
        requestIdFactory: _sequenceFactory(['id-1', 'id-2']),
      );

      expect(session.begin('sig-a'), 'id-1');
      expect(session.begin('sig-a'), 'id-1');
      expect(session.begin('sig-a'), 'id-1');
    });

    test('signature 變更（intent 變更）必鑄新 id', () {
      final session = CoachRequestIdSession(
        requestIdFactory: _sequenceFactory(['id-1', 'id-2', 'id-3']),
      );

      expect(session.begin('sig-a'), 'id-1');
      expect(session.begin('sig-b'), 'id-2');
      // 換回舊 signature 也不得撿回舊 id（pending 只有一個）。
      expect(session.begin('sig-a'), 'id-3');
    });

    test('retire 後同 signature 也鑄新 id（成功落卡＝下一次是新計費）', () {
      final session = CoachRequestIdSession(
        requestIdFactory: _sequenceFactory(['id-1', 'id-2']),
      );

      expect(session.begin('sig-a'), 'id-1');
      session.retire();
      expect(session.begin('sig-a'), 'id-2');
    });

    test('retire 在無 pending 時呼叫不炸', () {
      final session = CoachRequestIdSession(
        requestIdFactory: _sequenceFactory(['id-1']),
      );

      expect(session.retire, returnsNormally);
      expect(session.begin('sig-a'), 'id-1');
    });

    test('預設 factory 產出 lowercase UUID v4', () {
      final session = CoachRequestIdSession();
      final id = session.begin('sig-a');

      final uuidV4 = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      expect(id, matches(uuidV4));
      expect(id, id.toLowerCase());
      // 同 signature 重呼仍穩定。
      expect(session.begin('sig-a'), id);
    });
  });
}
