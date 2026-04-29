import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/features/partner/presentation/dialogs/partner_merge_confirm_dialog.dart';

Widget _harness(Future<bool?> Function(BuildContext) onPressed) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (ctx) => Center(
          child: ElevatedButton(
            onPressed: () => onPressed(ctx),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

Future<bool?> _show(BuildContext ctx,
        {String fromName = 'Alice',
        String toName = 'Bob',
        int conversationCount = 3,
        int traitCount = 7}) =>
    showDialog<bool>(
      context: ctx,
      builder: (_) => PartnerMergeConfirmDialog(
        fromName: fromName,
        toName: toName,
        conversationCount: conversationCount,
        traitCount: traitCount,
      ),
    );

void main() {
  testWidgets('dialog shows N convos + M traits + red 不可逆 warning', (t) async {
    await t.pumpWidget(_harness((ctx) => _show(ctx)));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    expect(find.textContaining('Alice'), findsWidgets);
    expect(find.textContaining('Bob'), findsWidgets);
    expect(find.textContaining('3'), findsWidgets); // N 對話
    expect(find.textContaining('7'), findsWidgets); // M traits
    expect(find.text('保留：Bob'), findsOneWidget);
    expect(find.text('移除：Alice'), findsOneWidget);
    expect(find.textContaining('Alice 底下的互動紀錄與特質會搬到 Bob'), findsOneWidget);
    expect(find.textContaining('整合整個對象卡'), findsOneWidget,
        reason: 'merge dialog must frame itself as a partner-dedupe tool '
            '(integrates the whole partner card), not a conversation-continuation action.');
    expect(find.textContaining('不是只接續目前這段對話'), findsOneWidget,
        reason:
            'dialog must explicitly contrast against conversation continuation '
            'so users do not confuse 合併 with 接續.');
    expect(find.textContaining('不可復原'), findsOneWidget);
    expect(find.text('確認合併'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
  });

  testWidgets('confirm tap returns true', (t) async {
    bool? result;
    await t.pumpWidget(_harness((ctx) async {
      result = await _show(ctx);
      return result;
    }));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    await t.tap(find.text('確認合併'));
    await t.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('cancel tap returns false', (t) async {
    bool? result;
    await t.pumpWidget(_harness((ctx) async {
      result = await _show(ctx);
      return result;
    }));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    await t.tap(find.text('取消'));
    await t.pumpAndSettle();

    expect(result, isFalse);
  });

  testWidgets('barrier dismiss returns null (no commit)', (t) async {
    bool? result;
    bool returned = false;
    await t.pumpWidget(_harness((ctx) async {
      result = await _show(ctx);
      returned = true;
      return result;
    }));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    // Tap outside the dialog → barrier dismiss
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();

    expect(returned, isTrue);
    expect(result, isNull,
        reason: 'barrier dismiss must not implicitly confirm');
  });
}
