// test/widget/features/conversation/new_conversation_screen_partner_id_test.dart
//
// Hermetic widget tests for NewConversationScreen partnerId chain.
// Verifies that the partnerId arg passed to the screen is propagated all
// the way to ConversationWriteController.create(partnerId:). Phase 2
// already wired this; PR-A locks it in as a contract test.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:vibesync/features/conversation/data/providers/conversation_write_controller.dart';
import 'package:vibesync/features/conversation/presentation/screens/new_conversation_screen.dart';
import 'package:vibesync/shared/widgets/warm_theme_widgets.dart'; // GradientButton

import '_fakes/recording_conversation_write_controller.dart';

GoRouter _routerWith(String? partnerId) => GoRouter(
      initialLocation: '/new',
      routes: [
        GoRoute(
          path: '/new',
          builder: (_, __) => NewConversationScreen(partnerId: partnerId),
        ),
        GoRoute(
          path: '/conversation/:id',
          builder: (_, __) => const Scaffold(body: Text('post-create stub')),
        ),
      ],
    );

// pumpAndSettle is unsafe here: NewConversationScreen wraps in
// GradientBackground which runs 3 .repeat() AnimationControllers, so
// pumpAndSettle never returns. Use bounded pump() calls instead.
Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

Future<void> _fillNameAndOneMessage(WidgetTester t) async {
  // Production reality (`new_conversation_screen.dart`)：
  //   - default state（personalization 未展開）TextField 順序：
  //     [0] 對話對象 name (_nameController, line 270)
  //     [1] 她的訊息 (_herMessageController, line 429)
  //     [2] 我的訊息 (_myMessageController, line 448)
  //   - 加號按鈕 = `_buildAddButton(_addHerMessage)` (line 435)，
  //     內含 `Icons.add` (line 189)。第二顆相同 icon 是 _addMyMessage。
  //   - 必須真的 _messages.add 一則，否則 _createConversation()
  //     line 116-121 snackbar early return，controller.create 永遠不會被叫。
  //   - 一條 her message 入列 → _hasIncomingMessage=true → CTA 文字固定「建立對話」(line 46)。
  await t.enterText(find.byType(TextField).at(0), 'Alice');
  await _settle(t);
  // SingleChildScrollView：her message TextField 在表單中段，預設 surface 可能
  // 看不到，先 ensureVisible 再輸入並 tap 加號。
  final herField = find.byType(TextField).at(1);
  await t.ensureVisible(herField);
  await _settle(t);
  await t.enterText(herField, '嗨');
  await _settle(t);
  final addBtn = find.byIcon(Icons.add).first;
  await t.ensureVisible(addBtn);
  await _settle(t);
  await t.tap(addBtn);
  await _settle(t);
}

void main() {
  testWidgets('partnerId arg "p-test" propagates to controller.create', (t) async {
    // 用較大 surface 避開 800x600 預設導致的 SingleChildScrollView 折疊；
    // 沿用 Phase 2 partner_detail_screen_test.dart 的 setSurfaceSize pattern。
    await t.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));

    final fake = RecordingConversationWriteController();

    await t.pumpWidget(ProviderScope(
      overrides: [
        conversationWriteControllerProvider.overrideWith(() => fake),
      ],
      child: MaterialApp.router(routerConfig: _routerWith('p-test')),
    ));
    await _settle(t);

    await _fillNameAndOneMessage(t);

    // CTA = GradientButton (production line 481-485, NOT ElevatedButton).
    // _hasIncomingMessage=true 後 text 固定「建立對話」(line 46)。
    final cta = find.byType(GradientButton);
    expect(cta, findsOneWidget,
        reason: 'GradientButton CTA renders after a「her message」 is added');
    expect(find.text('建立對話'), findsOneWidget,
        reason: '_hasIncomingMessage=true 應 render 文字「建立對話」(line 46)');

    await t.ensureVisible(cta);
    await _settle(t);
    await t.tap(cta);
    await _settle(t);

    expect(fake.createCalled, isTrue);
    expect(fake.capturedPartnerId, 'p-test');
    expect(fake.capturedName, 'Alice');
    expect(fake.capturedMessageCount, greaterThanOrEqualTo(1));
  });
}
