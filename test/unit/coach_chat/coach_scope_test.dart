import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/coach_chat/domain/entities/coach_scope.dart';
import 'package:vibesync/features/coach_chat/domain/entities/unified_coach_result.dart';

void main() {
  group('CoachScope', () {
    test('global scope 的 key/wire 形狀', () {
      const scope = CoachScope.global();
      expect(scope.type, CoachScopeType.global);
      expect(scope.id, 'me');
      expect(scope.key, 'global:me');
      expect(scope.wireConversationId, 'global:me');
      expect(scope.toWireJson(), {'type': 'global'});
      expect(scope.isConversation, isFalse);
      expect(scope.isGlobal, isTrue);
    });

    test('conversation scope 形狀不回歸', () {
      const scope = CoachScope.conversation('c1');
      expect(scope.key, 'conversation:c1');
      expect(scope.wireConversationId, 'c1');
      expect(scope.toWireJson(), {'type': 'conversation', 'conversationId': 'c1'});
      expect(scope.isConversation, isTrue);
      expect(scope.isGlobal, isFalse);
    });

    test('partner scope 形狀不回歸', () {
      const scope = CoachScope.partner('p1');
      expect(scope.key, 'partner:p1');
      expect(scope.wireConversationId, 'partner:p1');
      expect(scope.toWireJson(), {'type': 'partner', 'partnerId': 'p1'});
      expect(scope.isConversation, isFalse);
      expect(scope.isGlobal, isFalse);
    });

    test('global scope 值相等性', () {
      expect(const CoachScope.global(), const CoachScope.global());
      expect(const CoachScope.global(), isNot(const CoachScope.partner('me')));
    });
  });
}
