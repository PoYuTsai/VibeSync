import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/theme/app_colors.dart';
import 'package:vibesync/features/conversation/presentation/dialogs/delete_conversation_confirm_dialog.dart';

void main() {
  testWidgets('conversation management dialog uses a white brand surface',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const DeleteConversationConfirmDialog(
                  dateLabel: '06/18',
                  messageCount: 14,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect(dialog.backgroundColor, AppColors.glassWhite);
    expect(dialog.surfaceTintColor, Colors.transparent);
    expect(dialog.titleTextStyle?.color, AppColors.glassTextPrimary);
    expect(dialog.contentTextStyle?.color, AppColors.glassTextPrimary);
  });
}
