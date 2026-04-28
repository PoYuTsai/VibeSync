// Hermetic widget tests for PartnerEditDialog.
//
// The dialog is pure UI: it pre-fills the current name, exposes
// 取消 / 儲存 actions, blocks save while the trimmed input is empty, and pops
// with the trimmed string on confirm. Caller decides what to do with it
// (PartnerWriteController.updateName).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/features/partner/presentation/dialogs/partner_edit_dialog.dart';

Future<String?> _openDialog(WidgetTester t, {required String initialName}) async {
  String? result;
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              result = await showDialog<String>(
                context: ctx,
                builder: (_) =>
                    PartnerEditDialog(initialName: initialName),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('pre-fills the current name', (t) async {
    await _openDialog(t, initialName: 'Alice');

    expect(find.byType(TextField), findsOneWidget);
    final field = t.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, 'Alice');
  });

  testWidgets('儲存 returns trimmed new name', (t) async {
    String? captured;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                captured = await showDialog<String>(
                  context: ctx,
                  builder: (_) =>
                      const PartnerEditDialog(initialName: 'Alice'),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextField), '  Alicia  ');
    await t.tap(find.text('儲存'));
    await t.pumpAndSettle();

    expect(captured, 'Alicia');
  });

  testWidgets('取消 returns null', (t) async {
    String? captured = 'sentinel';
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                captured = await showDialog<String>(
                  context: ctx,
                  builder: (_) =>
                      const PartnerEditDialog(initialName: 'Alice'),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextField), 'Alicia');
    await t.tap(find.text('取消'));
    await t.pumpAndSettle();

    expect(captured, isNull);
  });

  testWidgets('儲存 disabled while trimmed input is empty', (t) async {
    await _openDialog(t, initialName: 'Alice');

    // Initial state: prefilled with non-empty 'Alice' → enabled.
    final saveBtnFinder = find.widgetWithText(ElevatedButton, '儲存');
    expect(t.widget<ElevatedButton>(saveBtnFinder).onPressed, isNotNull);

    await t.enterText(find.byType(TextField), '   ');
    await t.pump();

    expect(t.widget<ElevatedButton>(saveBtnFinder).onPressed, isNull,
        reason: 'whitespace-only input must disable 儲存');

    await t.enterText(find.byType(TextField), 'Alicia');
    await t.pump();

    expect(t.widget<ElevatedButton>(saveBtnFinder).onPressed, isNotNull,
        reason: 'restoring non-empty input must re-enable 儲存');
  });

  testWidgets('儲存 returns null when name unchanged', (t) async {
    // Returning the same trimmed name as initialName is treated as a no-op
    // by the dialog (returns null). Caller skips the controller call.
    String? captured = 'sentinel';
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                captured = await showDialog<String>(
                  context: ctx,
                  builder: (_) =>
                      const PartnerEditDialog(initialName: 'Alice'),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    // Tap save without changing anything.
    await t.tap(find.text('儲存'));
    await t.pumpAndSettle();

    expect(captured, isNull,
        reason: 'unchanged name should be a no-op for the caller');
  });
}
