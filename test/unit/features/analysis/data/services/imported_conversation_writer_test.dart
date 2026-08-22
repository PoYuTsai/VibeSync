// 深 write operation 行為回歸：save 成功後 refresh 恰好一次；save 失敗
// 絕不 refresh（截圖匯入的 provider 失效 side effect 不得漏、不得多）。
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/data/services/imported_conversation_writer.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';

Conversation _conversation() => Conversation(
      id: 'writer-conv',
      name: '小雲',
      messages: const [],
      createdAt: DateTime(2026, 5, 28),
      updatedAt: DateTime(2026, 5, 28),
    );

void main() {
  test('save 成功：先 save、後 refresh，恰好一次', () async {
    final order = <String>[];
    final writer = ImportedConversationWriter(
      save: (_) async => order.add('save'),
      refreshConversationViews: () => order.add('refresh'),
    );

    await writer.persist(_conversation());
    expect(order, ['save', 'refresh']);
  });

  test('save 失敗：錯誤上拋且絕不 refresh', () async {
    var refreshes = 0;
    final writer = ImportedConversationWriter(
      save: (_) async => throw StateError('save failed'),
      refreshConversationViews: () => refreshes++,
    );

    await expectLater(
      () => writer.persist(_conversation()),
      throwsA(isA<StateError>()),
    );
    expect(refreshes, 0);
  });
}
