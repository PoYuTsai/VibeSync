// test/widget/features/partner/partner_conversation_tile_test.dart
//
// Hermetic widget tests for PartnerConversationTile after PR-B Task 5.
// trailing changed from Icon(chevron_right) to PopupMenuButton(⋮) with
// 改派 (enabled when onReassign != null) + 刪除（即將推出）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_conversation_tile.dart';

Conversation _conv() => Conversation(
      id: 'c1',
      name: '第 a 段',
      messages: const [],
      createdAt: DateTime(2026, 4, 20),
      updatedAt: DateTime(2026, 4, 20),
    );

void main() {
  testWidgets('trailing renders ⋮ icon (not chevron_right)', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PartnerConversationTile(
          conversation: _conv(),
          onTap: () {},
          onReassign: () {},
        ),
      ),
    ));

    expect(find.byIcon(Icons.more_vert), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('⋮ tap shows 改派 + 刪除（即將推出）items', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PartnerConversationTile(
          conversation: _conv(),
          onTap: () {},
          onReassign: () {},
        ),
      ),
    ));
    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();

    expect(find.text('改派到其他對象'), findsOneWidget);
    expect(find.text('刪除對話（即將推出）'), findsOneWidget);
  });

  testWidgets('改派 tap fires onReassign callback', (t) async {
    var fired = false;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PartnerConversationTile(
          conversation: _conv(),
          onTap: () {},
          onReassign: () => fired = true,
        ),
      ),
    ));
    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();
    await t.tap(find.text('改派到其他對象'));
    await t.pumpAndSettle();

    expect(fired, isTrue);
  });

  testWidgets('cell title tap still fires onTap, not onReassign', (t) async {
    var tapped = false;
    var reassigned = false;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PartnerConversationTile(
          conversation: _conv(),
          onTap: () => tapped = true,
          onReassign: () => reassigned = true,
        ),
      ),
    ));
    await t.tap(find.text('04/20 互動紀錄'));
    await t.pumpAndSettle();

    expect(tapped, isTrue);
    expect(reassigned, isFalse);
  });

  testWidgets('title shows MM/dd 互動紀錄, not partner name', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PartnerConversationTile(
          conversation: _conv(),
          onTap: () {},
        ),
      ),
    ));

    expect(find.text('04/20 互動紀錄'), findsOneWidget);
    expect(find.text('第 a 段'), findsNothing,
        reason:
            'Conversation tile under Partner detail must NOT main-bill the partner name; '
            'that breaks the "人 vs 互動" mental model.');
  });

  testWidgets('onReassign=null → 改派 item disabled', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PartnerConversationTile(
          conversation: _conv(),
          onTap: () {},
        ),
      ),
    ));
    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();

    final item = t.widget<PopupMenuItem<String>>(
      find.ancestor(
        of: find.text('改派到其他對象'),
        matching: find.byType(PopupMenuItem<String>),
      ),
    );
    expect(item.enabled, isFalse);
  });
}
