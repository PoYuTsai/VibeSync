// test/widget/features/conversation/new_conversation_sheet_screenshot_test.dart
//
// Hermetic widget tests for NewConversationSheet's screenshot ListTile.
// Verifies that the partnerId passed to the sheet is propagated to
// controller.create(partnerId:) when the user taps「截圖開始」. Pairs
// with new_conversation_screen_partner_id_test.dart to cover both
// manual + screenshot conversation creation paths.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:vibesync/features/conversation/data/providers/conversation_write_controller.dart';
import 'package:vibesync/features/conversation/presentation/widgets/new_conversation_sheet.dart';

import '_fakes/recording_conversation_write_controller.dart';

// Sheet 不包 GradientBackground，原則上可以 pumpAndSettle，但保險起見
// 與 manual-path test 同一風格用 _settle()。
Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

GoRouter _sheetTestRouter(String? partnerId) {
  return GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, __) => Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet(
                  context: ctx,
                  builder: (_) => NewConversationSheet(partnerId: partnerId),
                ),
                child: const Text('open sheet'),
              ),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/conversation/:id',
        builder: (_, __) => const Scaffold(body: Text('post-create stub')),
      ),
      GoRoute(
        path: '/new',
        builder: (_, __) => const Scaffold(body: Text('manual entry stub')),
      ),
      GoRoute(
        path: '/opener',
        builder: (_, __) => const Scaffold(body: Text('opener stub')),
      ),
    ],
  );
}

void main() {
  testWidgets('sheet partnerId="p-test" + 截圖開始 → controller.create(partnerId: "p-test")',
      (t) async {
    // Phase 2 已驗 sheet bottom sheet 在 800x600 default 有 1.5px overflow。
    // 用 partner_detail_screen_test.dart 的 setSurfaceSize pattern 避開。
    await t.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));

    final fake = RecordingConversationWriteController();

    await t.pumpWidget(ProviderScope(
      overrides: [
        conversationWriteControllerProvider.overrideWith(() => fake),
      ],
      child: MaterialApp.router(routerConfig: _sheetTestRouter('p-test')),
    ));
    await _settle(t);

    await t.tap(find.text('open sheet'));
    await _settle(t);

    expect(find.text('截圖開始'), findsOneWidget);
    await t.tap(find.text('截圖開始'));
    await _settle(t);

    expect(fake.createCalled, isTrue);
    expect(fake.capturedPartnerId, 'p-test');
    expect(fake.capturedName, '新對話',
        reason: '截圖 path hardcodes 名稱「新對話」(NewConversationSheet line 96)');
    expect(fake.capturedMessageCount, 0,
        reason: '截圖 path 在 sheet 階段不傳 messages — OCR 完才補');
  });
}
