// test/widget/features/partner/conversation_reassign_picker_test.dart
//
// Hermetic widget tests for showConversationReassignPicker (PR-B Task 6).
// Test lives under partner/ to satisfy the partner-scoped CI gate; the
// flow itself spans conversation + partner domains.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/features/conversation/data/providers/conversation_write_controller.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/presentation/dialogs/conversation_reassign_picker.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';

import '_fakes/recording_conversation_write_controller.dart';

Partner _p(String id, String name) => Partner(
      id: id,
      name: name,
      ownerUserId: 'u1',
      createdAt: DateTime(2026, 4, 27),
      updatedAt: DateTime(2026, 4, 27),
    );

Conversation _conv({String partnerId = 'A'}) => Conversation(
      id: 'c1',
      name: '第 a 段',
      messages: const [],
      createdAt: DateTime(2026, 4, 20),
      updatedAt: DateTime(2026, 4, 20),
      partnerId: partnerId,
    );

class _Harness extends ConsumerWidget {
  final Conversation conversation;
  final DateTime? preservedArchivedAt;
  const _Harness({
    required this.conversation,
    this.preservedArchivedAt,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => showConversationReassignPicker(
            context,
            conversation: conversation,
            ref: ref,
            preservedArchivedAt: preservedArchivedAt,
          ),
          child: const Text('open-picker'),
        ),
      ),
    );
  }
}

// No GradientBackground in this tree; pumpAndSettle is safe and is
// required because showModalBottomSheet's slide-up animation is 250ms.
Future<void> _pumpHarness(
  WidgetTester t, {
  required Conversation conversation,
  required List<Partner> partners,
  required RecordingConversationWriteController fake,
  DateTime? preservedArchivedAt,
}) async {
  await t.binding.setSurfaceSize(const Size(400, 1200));
  addTearDown(() => t.binding.setSurfaceSize(null));

  await t.pumpWidget(ProviderScope(
    overrides: [
      partnerListProvider.overrideWith((_) => partners),
      conversationWriteControllerProvider.overrideWith(() => fake),
    ],
    child: MaterialApp(
      home: _Harness(
        conversation: conversation,
        preservedArchivedAt: preservedArchivedAt,
      ),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('sheet opens with picker excluding current partnerId', (t) async {
    final fake = RecordingConversationWriteController();
    final c = _conv(partnerId: 'A');
    await _pumpHarness(
      t,
      conversation: c,
      partners: [_p('A', 'Alice'), _p('B', 'Bob'), _p('C', 'Cara')],
      fake: fake,
    );

    await t.tap(find.text('open-picker'));
    await t.pumpAndSettle();

    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Cara'), findsOneWidget);
    expect(find.text('Alice'), findsNothing);
  });

  testWidgets(
      'selecting target calls save with new partnerId + previousPartnerId',
      (t) async {
    final fake = RecordingConversationWriteController();
    final c = _conv(partnerId: 'A');
    await _pumpHarness(
      t,
      conversation: c,
      partners: [_p('A', 'Alice'), _p('B', 'Bob')],
      fake: fake,
    );

    await t.tap(find.text('open-picker'));
    await t.pumpAndSettle();
    await t.tap(find.text('Bob'));
    await t.pumpAndSettle();
    expect(find.text('把這段移到「Bob」？'), findsOneWidget);
    expect(find.textContaining('只會移動目前這一段互動紀錄'), findsOneWidget);
    await t.tap(find.text('移過去'));
    await t.pumpAndSettle();

    expect(fake.saveCalled, isTrue);
    expect(fake.savedConversation?.id, 'c1');
    expect(fake.savedPartnerIdAtCallTime, 'B');
    expect(fake.savedPreviousPartnerId, 'A');
    expect(fake.savedIntent, ConversationSaveIntent.metadataOnly);
    expect(fake.savedPreservedArchivedAt, isNull);
    // sheet popped → trigger button visible again
    expect(find.text('open-picker'), findsOneWidget);
    expect(find.text('Bob'), findsNothing);
  });

  testWidgets('archived reassign preserves the original archive timestamp',
      (t) async {
    final fake = RecordingConversationWriteController();
    final c = _conv(partnerId: 'A');
    final archivedAt = DateTime.utc(2026, 6, 20, 8);
    await _pumpHarness(
      t,
      conversation: c,
      partners: [_p('A', 'Alice'), _p('B', 'Bob')],
      fake: fake,
      preservedArchivedAt: archivedAt,
    );

    await t.tap(find.text('open-picker'));
    await t.pumpAndSettle();
    await t.tap(find.text('Bob'));
    await t.pumpAndSettle();
    await t.tap(find.text('移過去'));
    await t.pumpAndSettle();

    expect(fake.savedIntent, ConversationSaveIntent.metadataOnly);
    expect(fake.savedPreservedArchivedAt, archivedAt);
  });

  testWidgets('save failure rolls back conversation.partnerId + shows SnackBar',
      (t) async {
    final fake = RecordingConversationWriteController()
      ..throwOnSave = StateError('boom');
    final c = _conv(partnerId: 'A');
    await _pumpHarness(
      t,
      conversation: c,
      partners: [_p('A', 'Alice'), _p('B', 'Bob')],
      fake: fake,
    );

    await t.tap(find.text('open-picker'));
    await t.pumpAndSettle();
    await t.tap(find.text('Bob'));
    await t.pumpAndSettle();
    await t.tap(find.text('移過去'));
    await t.pumpAndSettle();

    expect(fake.saveCalled, isTrue);
    expect(c.partnerId, 'A',
        reason: 'failure must roll back the in-memory mutation');
    expect(find.textContaining('移動失敗'), findsOneWidget);
  });

  testWidgets('only-self list → empty hint, no save', (t) async {
    final fake = RecordingConversationWriteController();
    final c = _conv(partnerId: 'A');
    await _pumpHarness(
      t,
      conversation: c,
      partners: [_p('A', 'Alice')],
      fake: fake,
    );

    await t.tap(find.text('open-picker'));
    await t.pumpAndSettle();

    expect(find.textContaining('尚無其他對象'), findsOneWidget);
    expect(fake.saveCalled, isFalse);
  });
}
