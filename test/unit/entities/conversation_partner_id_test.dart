import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';

void main() {
  group('Conversation.partnerId', () {
    test('defaults to null and is mutable', () {
      final now = DateTime(2026, 4, 25);
      final c = Conversation(
        id: 'c-1',
        name: 'test',
        messages: const [],
        createdAt: now,
        updatedAt: now,
      );
      expect(c.partnerId, isNull);

      c.partnerId = 'p-abc';
      expect(c.partnerId, 'p-abc');
    });
  });
}
