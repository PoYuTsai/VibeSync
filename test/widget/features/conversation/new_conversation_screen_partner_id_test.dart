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

// Production reality (`new_conversation_screen.dart`)：
//   - 加號按鈕 = `_buildAddButton(_addHerMessage)` (line 435)，內含 `Icons.add`。
//     第二顆相同 icon 是 _addMyMessage。
//   - 必須真的 _messages.add 一則，否則 _createConversation()
//     snackbar early return，controller.create 永遠不會被叫。
//   - 一條 her message 入列 → _hasIncomingMessage=true → CTA 文字固定「建立對話」。
//
// TextField 順序在 partnerId == null 與 != null 兩種狀態下不同：
//   - partnerId == null：[0]=對話對象 name, [1]=她的訊息, [2]=我的訊息
//   - partnerId != null：[0]=她的訊息, [1]=我的訊息  (對話對象欄位被隱藏，
//     因為 Partner 已帶 identity，避免雙重輸入；Bruce TF feedback 2026-04-28)
Future<void> _fillNameAndOneMessage(WidgetTester t) async {
  await t.enterText(find.byType(TextField).at(0), 'Alice');
  await _settle(t);
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

/// partnerId-set helper：「對話對象」 field is hidden, so we only feed one
/// her message. Conversation name defaults to '新對話' inside production
/// `_createConversation` (Bruce TF feedback 2026-04-28).
Future<void> _fillOnlyOneMessage(WidgetTester t) async {
  // After hiding 對話對象, [0] is 她的訊息.
  final herField = find.byType(TextField).at(0);
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
  testWidgets('partnerId arg "p-test" propagates to controller.create',
      (t) async {
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

    // partnerId-set 時 對話對象 name field 被隱藏（Bruce TF feedback 2026-04-28），
    // 只需要灌一則 her message；name 由 _createConversation default 為 '新對話'。
    await _fillOnlyOneMessage(t);

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
    expect(fake.capturedName, '新對話',
        reason:
            'partnerId set → name field hidden → default to 新對話 placeholder. '
            'Partner already owns the identity; re-typing it is redundant double-input.');
    expect(fake.capturedMessageCount, greaterThanOrEqualTo(1));
  });

  testWidgets('partnerId arg null (legacy entry) propagates as null',
      (t) async {
    await t.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));

    final fake = RecordingConversationWriteController();

    await t.pumpWidget(ProviderScope(
      overrides: [
        conversationWriteControllerProvider.overrideWith(() => fake),
      ],
      child: MaterialApp.router(routerConfig: _routerWith(null)),
    ));
    await _settle(t);

    await _fillNameAndOneMessage(t);

    // 同 Task 2：GradientButton + 文字「建立對話」（一條 her message 已入列）。
    final cta = find.byType(GradientButton);
    await t.ensureVisible(cta);
    await _settle(t);
    await t.tap(cta);
    await _settle(t);

    expect(fake.createCalled, isTrue);
    expect(fake.capturedPartnerId, isNull,
        reason:
            'Legacy entry without partnerId arg should pass null to controller.create. '
            'Auto-derive on create is NOT implemented in current architecture; '
            'A1 migration backfills Partners on app start. Phase 4+ may revisit.');
  });

  testWidgets('partnerId set hides 對話對象 input (avoid double-identity)',
      (t) async {
    await t.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));

    await t.pumpWidget(ProviderScope(
      child: MaterialApp.router(routerConfig: _routerWith('p-test')),
    ));
    await _settle(t);

    expect(find.text('對話對象'), findsNothing,
        reason: 'partnerId != null → 對話對象 label is hidden because Partner '
            'already owns the relationship identity. Bruce TF feedback 2026-04-28.');
    expect(find.text('例如：小安'), findsNothing,
        reason: 'partnerId != null → name placeholder hidden too.');
  });

  testWidgets('partnerId set hides per-conversation personalization block',
      (t) async {
    await t.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));

    await t.pumpWidget(ProviderScope(
      child: MaterialApp.router(routerConfig: _routerWith('p-test')),
    ));
    await _settle(t);

    expect(find.text('個人化資訊（選填）'), findsNothing,
        reason: 'Partner-level 對方資訊 should be set once from PartnerDetail, '
            'not repeated every time a new conversation is manually entered.');
    expect(find.text('對方特質'), findsNothing);
    expect(find.text('例如：活潑、慢熱、喜歡戶外活動'), findsNothing);
  });

  testWidgets(
      'partnerId set shows conversation input first and collapses analysis settings',
      (t) async {
    await t.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));

    await t.pumpWidget(ProviderScope(
      child: MaterialApp.router(routerConfig: _routerWith('p-test')),
    ));
    await _settle(t);

    expect(find.text('對話內容'), findsOneWidget);
    expect(find.text('這次分析設定（可不改）'), findsOneWidget);
    expect(find.text('只影響這次分析，不會改對象資料。'), findsOneWidget);
    expect(find.text('認識情境'), findsNothing,
        reason: 'Partner-scoped manual input should not lead with settings; '
            'the optional per-analysis controls stay collapsed by default.');
    expect(
      t.getTopLeft(find.text('對話內容')).dy,
      lessThan(t.getTopLeft(find.text('這次分析設定（可不改）')).dy),
      reason: 'The first thing users should see is where to type the chat.',
    );

    await t.tap(find.text('這次分析設定（可不改）'));
    await _settle(t);

    expect(find.text('認識情境'), findsOneWidget);
    expect(find.text('認識多久'), findsOneWidget);
    expect(find.text('目前目標'), findsOneWidget);
  });

  testWidgets('partnerId null still shows 對話對象 input (legacy entry)',
      (t) async {
    await t.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));

    await t.pumpWidget(ProviderScope(
      child: MaterialApp.router(routerConfig: _routerWith(null)),
    ));
    await _settle(t);

    expect(find.text('對話對象'), findsOneWidget,
        reason: 'Legacy entry without partnerId still needs the name input.');
  });

  testWidgets('partnerId null keeps personalization block for legacy entry',
      (t) async {
    await t.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));

    await t.pumpWidget(ProviderScope(
      child: MaterialApp.router(routerConfig: _routerWith(null)),
    ));
    await _settle(t);

    expect(find.text('個人化資訊（選填）'), findsOneWidget,
        reason: 'Orphan / legacy manual input still has no Partner card, so '
            'the old per-conversation note escape hatch stays available.');
  });
}
