// test/widget/features/partner/partner_note_edit_dialog_test.dart
//
// Hermetic tests for the Partner.customNote edit dialog. This dialog returns
// a value only when the user actually changes the trimmed note.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/features/partner/presentation/dialogs/partner_note_edit_dialog.dart';

const _sentinel = Object();

Future<Object?> _openAndCloseDialog(
  WidgetTester t, {
  required String initialNote,
  required Future<void> Function(WidgetTester t) act,
}) async {
  Object? result = _sentinel;

  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: ElevatedButton(
          onPressed: () async {
            result = await showDialog<String>(
              context: context,
              builder: (_) => PartnerNoteEditDialog(initialNote: initialNote),
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  ));

  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  await act(t);
  await t.pumpAndSettle();

  return result;
}

void main() {
  testWidgets('save returns trimmed note when changed', (t) async {
    final result = await _openAndCloseDialog(
      t,
      initialNote: '',
      act: (t) async {
        await t.enterText(find.byType(TextField), '  慢熱，喜歡戶外活動  ');
        await t.tap(find.text('儲存'));
      },
    );

    expect(result, '慢熱，喜歡戶外活動');
  });

  testWidgets('save returns empty string when user clears note', (t) async {
    final result = await _openAndCloseDialog(
      t,
      initialNote: '慢熱',
      act: (t) async {
        await t.enterText(find.byType(TextField), '   ');
        await t.tap(find.text('儲存'));
      },
    );

    expect(result, '');
  });

  testWidgets('unchanged save returns null', (t) async {
    final result = await _openAndCloseDialog(
      t,
      initialNote: '慢熱',
      act: (t) async {
        await t.tap(find.text('儲存'));
      },
    );

    expect(result, isNull);
  });
}
