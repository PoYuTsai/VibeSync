import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/coach_chat/domain/entities/coach_scope.dart';
import 'package:vibesync/features/coach_chat/domain/entities/unified_coach_result.dart';

void main() {
  group('CoachScope', () {
    test('conversation scope 的 type/id/isConversation', () {
      const scope = CoachScope.conversation('c1');
      expect(scope.type, CoachScopeType.conversation);
      expect(scope.id, 'c1');
      expect(scope.isConversation, isTrue);
    });

    test('partner scope 的 type/id/isConversation', () {
      const scope = CoachScope.partner('p1');
      expect(scope.type, CoachScopeType.partner);
      expect(scope.id, 'p1');
      expect(scope.isConversation, isFalse);
    });

    group('key', () {
      test('conversation → conversation:c1', () {
        expect(const CoachScope.conversation('c1').key, 'conversation:c1');
      });

      test('partner → partner:p1', () {
        expect(const CoachScope.partner('p1').key, 'partner:p1');
      });
    });

    group('wireConversationId', () {
      test('conversation → 原 id', () {
        expect(const CoachScope.conversation('c1').wireConversationId, 'c1');
      });

      test('partner → partner: 前綴合成 id', () {
        expect(const CoachScope.partner('p1').wireConversationId, 'partner:p1');
      });
    });

    group('toWireJson', () {
      test('conversation → {type, conversationId}', () {
        expect(const CoachScope.conversation('c1').toWireJson(), {
          'type': 'conversation',
          'conversationId': 'c1',
        });
      });

      test('partner → {type, partnerId}', () {
        expect(const CoachScope.partner('p1').toWireJson(), {
          'type': 'partner',
          'partnerId': 'p1',
        });
      });
    });

    group('值相等性（可當 Riverpod family key）', () {
      test('同 type 同 id 相等且 hashCode 相同', () {
        expect(
          const CoachScope.conversation('c1'),
          equals(const CoachScope.conversation('c1')),
        );
        expect(
          const CoachScope.conversation('c1').hashCode,
          const CoachScope.conversation('c1').hashCode,
        );
        expect(
          const CoachScope.partner('p1'),
          equals(const CoachScope.partner('p1')),
        );
      });

      test('不同 id 不相等', () {
        expect(
          const CoachScope.conversation('c1'),
          isNot(equals(const CoachScope.conversation('c2'))),
        );
      });

      test('同 id 不同 type 不相等', () {
        expect(
          const CoachScope.conversation('x1'),
          isNot(equals(const CoachScope.partner('x1'))),
        );
      });
    });

    test('toString 含 type 與 id 供除錯', () {
      final text = const CoachScope.conversation('c1').toString();
      expect(text, contains('conversation'));
      expect(text, contains('c1'));
    });
  });
}
