import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/features/coach_chat/data/providers/coach_chat_providers.dart';
import 'package:vibesync/features/coach_chat/data/services/coach_chat_api_service.dart';
import 'package:vibesync/features/coach_chat/domain/entities/coach_scope.dart';
import 'package:vibesync/features/coach_chat/presentation/screens/global_coach_screen.dart';
import 'package:vibesync/features/coach_chat/presentation/widgets/coach_chat_progress_notice.dart';
import 'package:vibesync/features/coach_chat/presentation/widgets/coach_surface.dart';
import 'package:vibesync/features/coaching_memory/data/providers/coaching_outcome_providers.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/user_profile/data/providers/data_quality_flag_provider.dart';
import 'package:vibesync/shared/widgets/ai_data_sharing_consent.dart';

import '../../helpers/memory_coach_chat_repository.dart';
import '../../helpers/memory_coaching_outcome_repository.dart';

const _clarifyingQuestion = '她短回之後，有反問你或接著聊嗎？';
const _formalHeadline = '先看有沒有接話，不急著判斷降溫';
final _longAnswer = List.generate(
  12,
  (index) => '第 ${index + 1} 段：先回顧最近三則回覆，看看她是否延伸話題、反問或補充細節。'
      '短回本身不足以代表冷淡，這次先觀察雙方是否仍願意接話。'
      '你可以維持原本自然的節奏，留一點空間，再依後續互動決定。',
).join('\n\n');

class _SeededSubscriptionNotifier extends SubscriptionNotifier {
  _SeededSubscriptionNotifier() {
    state = const SubscriptionState(dailyLimit: 5, monthlyLimit: 30);
  }
}

/// 用真正的 controller 通過 loading → data，讓結果進入本次 session。
/// 只 seed repo 不會顯示舊結果，也不應為了測試取消該限制。
class _Harness {
  final repo = MemoryCoachChatRepository();
  final calls = <Map<String, dynamic>>[];
  final pending = <Completer<CoachChatInvokeResponse>>[];
  final keyboardInset = ValueNotifier<double>(0);
  int usageSyncCalls = 0;

  Future<CoachChatInvokeResponse> invoke(
    String _, {
    required Map<String, dynamic> body,
  }) {
    calls.add(body);
    final request = Completer<CoachChatInvokeResponse>();
    pending.add(request);
    return request.future;
  }

  void succeed(
    int request, {
    bool clarifying = false,
    String headline = _formalHeadline,
    String? answer,
  }) {
    pending[request].complete(
      CoachChatInvokeResponse(
        status: 200,
        data: {
          'card': {
            'responseType': clarifying ? 'clarifyingQuestion' : 'coachAnswer',
            'mode': clarifying ? 'clarifyIntent' : 'replyCraft',
            'headline': clarifying ? '先看短回後有沒有接話' : headline,
            'answer':
                clarifying ? '單次短回還不能判定她沒興趣，先補上這個線索。' : (answer ?? _longAnswer),
            'userState': '擔心自己把短回看得太重',
            'frictionType': 'unclearIntent',
            'nextStep': '回顧最近三則她的回覆，看看有沒有反問或延伸。',
            'suggestedLine': clarifying ? null : '剛看到這個，想到你上次說的那件事。',
            'boundaryReminder': '別為了確認而連續追問。',
            'needsReflection': clarifying,
            'reflectionQuestion': clarifying ? _clarifyingQuestion : null,
            'costDeducted': clarifying ? 0 : 1,
          },
          'provider': 'test',
          'model': 'test-coach',
          'generatedAt': DateTime.now()
              .toUtc()
              .add(Duration(seconds: request))
              .toIso8601String(),
          'sessionId': 'reading-layout-session',
        },
      ),
    );
  }

  void fail(int request) {
    pending[request].complete(
      const CoachChatInvokeResponse(
        status: 500,
        data: {'error': 'test generation failed'},
      ),
    );
  }
}

Finder get _input => find.descendant(
      of: find.byType(CoachSurface),
      matching: find.byType(TextField),
    );

ScrollPosition _readingPosition(WidgetTester tester) {
  final scrollable = find.descendant(
    of: find.byKey(const Key('coach-reading-scroll')),
    matching: find.byType(Scrollable),
  );
  return tester.state<ScrollableState>(scrollable.first).position;
}

/// 長文是一個 Text，取第 5 段首行的真實位置，避免只驗證仍在 widget tree。
Rect _fifthParagraphRect(WidgetTester tester) {
  final richText = find.descendant(
    of: find.text(_longAnswer),
    matching: find.byType(RichText),
  );
  final paragraph = tester.renderObject<RenderParagraph>(richText);
  final start = _longAnswer.indexOf('第 5 段');
  final box = paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: start + 5),
      )
      .first
      .toRect();
  return Rect.fromPoints(
    paragraph.localToGlobal(box.topLeft),
    paragraph.localToGlobal(box.bottomRight),
  );
}

Future<void> _scrollToFifthParagraph(WidgetTester tester) async {
  final scroll = find.byKey(const Key('coach-reading-scroll'));
  final position = _readingPosition(tester);
  final target = position.pixels +
      _fifthParagraphRect(tester).top -
      tester.getTopLeft(scroll).dy -
      80;
  position.jumpTo(
    target.clamp(position.minScrollExtent, position.maxScrollExtent),
  );
  await tester.pump();
  expect(tester.getRect(scroll).contains(_fifthParagraphRect(tester).center),
      isTrue);
}

Future<_Harness> _pump(
  WidgetTester tester, {
  bool lockedPartner = false,
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final harness = _Harness();
  final partner = Partner(
    id: 'p1',
    name: '安安',
    createdAt: DateTime(2026, 9, 1),
    updatedAt: DateTime(2026, 9, 1),
    ownerUserId: 'test-owner',
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coachChatRepositoryProvider.overrideWithValue(harness.repo),
        coachChatApiServiceProvider.overrideWithValue(
          CoachChatApiService(invoker: harness.invoke),
        ),
        coachChatUsageSyncProvider.overrideWithValue(() async {
          harness.usageSyncCalls++;
        }),
        coachChatStyleContextResolverProvider.overrideWithValue(({
          required String? partnerId,
          required bool includePartnerOverride,
        }) async =>
            null),
        coachingOutcomeRepositoryProvider.overrideWithValue(
          MemoryCoachingOutcomeRepository(),
        ),
        subscriptionProvider.overrideWith((_) => _SeededSubscriptionNotifier()),
        partnerListProvider.overrideWithValue([partner]),
        partnerByIdProvider('p1').overrideWithValue(partner),
        partnerAggregateProvider('p1')
            .overrideWithValue(PartnerAggregateView.empty()),
        conversationsByPartnerProvider('p1').overrideWithValue(const []),
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
      ],
      child: MaterialApp(
        builder: (context, child) => ValueListenableBuilder<double>(
          valueListenable: harness.keyboardInset,
          builder: (context, inset, _) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(textScale),
              viewInsets: EdgeInsets.only(bottom: inset),
            ),
            child: child!,
          ),
        ),
        home: GlobalCoachScreen(lockedPartnerId: lockedPartner ? 'p1' : null),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    // 不留下 controller 的 keepAlive/in-flight request。
    for (var i = 0; i < harness.pending.length; i++) {
      if (!harness.pending[i].isCompleted) harness.fail(i);
    }
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox.shrink());
    harness.keyboardInset.dispose();
  });
  return harness;
}

Future<void> _send(
  WidgetTester tester,
  _Harness harness,
  String question,
) async {
  final before = harness.calls.length;
  await tester.enterText(_input, question);
  await tester.pump();
  await tester.tap(find.byIcon(Icons.arrow_upward));
  // pending 等待有持續進度動畫，不用 pumpAndSettle。
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
  expect(harness.calls.length, before + 1);
}

Future<void> _finish(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  // 閱讀錨點在 post-frame 還原；再排版一幀才比較螢幕位置。
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      AiDataSharingConsent.acceptedKeyForTesting: true,
    });
  });

  testWidgets('免費釐清收起人物後仍可補充，追問等待不變正式建議', (tester) async {
    final harness = await _pump(tester);
    await _send(tester, harness, '對方回得很短，我該怎麼判斷？');
    harness.succeed(0, clarifying: true);
    await _finish(tester);

    expect(find.text(_clarifyingQuestion), findsOneWidget);
    expect(find.text('免費釐清 第 1 次（最多 3 次）'), findsOneWidget);
    expect(harness.usageSyncCalls, 0);
    expect(find.byKey(const Key('coach-welcome')), findsNothing);
    expect(find.byKey(const Key('coach-compact-avatar')), findsOneWidget);

    await tester.enterText(_input, '她有問我週末想去哪裡。');
    await tester.pump(const Duration(milliseconds: 350));
    expect(harness.calls, hasLength(1), reason: '聚焦與打字不能自動送出');
    expect(find.text(_clarifyingQuestion), findsOneWidget);

    await _send(tester, harness, '她有問我週末想去哪裡。');
    expect(find.byType(CoachChatProgressNotice), findsOneWidget);
    expect(find.text(_clarifyingQuestion), findsOneWidget,
        reason: '等待補充回答時不能移除還在閱讀的上一輪');
    expect(find.text('免費釐清 第 1 次（最多 3 次）'), findsOneWidget);
    expect(harness.calls.last.containsKey('forceAnswer'), isFalse);
    expect(harness.usageSyncCalls, 0);
    expect(harness.repo.putUnifiedCalls, 1);
    expect(find.textContaining('已扣 1 則'), findsNothing);

    harness.succeed(1, clarifying: true);
    await _finish(tester);
    expect(find.text('免費釐清 第 2 次（最多 3 次）'), findsOneWidget);
    expect(harness.usageSyncCalls, 0);
  });

  testWidgets('正式全文展開後，追問 pending 與 error 都保留原答案及展開狀態', (tester) async {
    final harness = await _pump(tester);
    await _send(tester, harness, '怎麼把聊天接下去？');
    harness.succeed(0);
    await _finish(tester);
    expect(harness.usageSyncCalls, 1);

    await tester.ensureVisible(find.text('看完整教練分析'));
    await tester.tap(find.text('看完整教練分析'));
    await _finish(tester);
    expect(find.text(_longAnswer), findsOneWidget);

    await _scrollToFifthParagraph(tester);

    await _send(tester, harness, '如果她沒有接話呢？');
    expect(find.byType(CoachChatProgressNotice), findsOneWidget);
    expect(find.text(_longAnswer), findsOneWidget);
    expect(find.text('收起完整分析'), findsOneWidget);
    expect(find.byKey(const Key('coach-welcome')), findsNothing);
    expect(harness.usageSyncCalls, 1);

    final beforeFailure = _fifthParagraphRect(tester);
    harness.fail(1);
    await _finish(tester);
    expect(find.byType(CoachChatProgressNotice), findsNothing);
    expect(find.text('這題教練沒接住'), findsOneWidget);
    expect(find.text(_longAnswer), findsOneWidget);
    expect(find.text('收起完整分析'), findsOneWidget);
    expect(_fifthParagraphRect(tester).top, closeTo(beforeFailure.top, 2),
        reason: '失敗通知及重填問題改變版面時，正在讀的段落仍留在原位');
    expect(
      tester
          .getRect(find.byKey(const Key('coach-reading-scroll')))
          .contains(_fifthParagraphRect(tester).center),
      isTrue,
    );
    expect(tester.widget<TextField>(_input).controller?.text, '如果她沒有接話呢？');
    expect(harness.repo.putUnifiedCalls, 1);
    expect(harness.usageSyncCalls, 1);
  });

  testWidgets('讀舊全文時新正式答案完成，保留可見段落直到主動點新答案', (tester) async {
    final harness = await _pump(tester);
    await _send(tester, harness, '先幫我分析目前聊天。');
    harness.succeed(0);
    await _finish(tester);
    await tester.ensureVisible(find.text('看完整教練分析'));
    await tester.tap(find.text('看完整教練分析'));
    await _finish(tester);

    final scroll = find.byKey(const Key('coach-reading-scroll'));
    final position = _readingPosition(tester);
    final target = position.pixels +
        _fifthParagraphRect(tester).top -
        tester.getTopLeft(scroll).dy -
        80;
    position.jumpTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
    await tester.pump();
    expect(
      tester.getRect(scroll).contains(_fifthParagraphRect(tester).center),
      isTrue,
      reason: '先確定第 5 段真的在畫面裡，才能驗證保留閱讀位置',
    );

    await _send(tester, harness, '她如果只是忙，應該怎麼接？');
    final before = _fifthParagraphRect(tester);
    expect(tester.getRect(scroll).contains(before.center), isTrue);
    final oldOffset = position.pixels;
    expect(oldOffset, greaterThan(80));

    const newHeadline = '先接住她的時間安排';
    harness.succeed(
      1,
      headline: newHeadline,
      answer: '第二輪完整分析：配合目前互動節奏，再觀察她是否主動延伸。',
    );
    await _finish(tester);

    expect(find.byType(CoachChatProgressNotice), findsNothing);
    expect(find.text(_longAnswer), findsOneWidget);
    expect(find.text('收起完整分析'), findsOneWidget);
    expect(find.text(newHeadline), findsNothing, reason: '新答案不能直接替換正在閱讀的全文');
    expect(find.byKey(const Key('coach-new-answer')).hitTestable(),
        findsOneWidget);
    final after = _fifthParagraphRect(tester);
    expect(after.top, closeTo(before.top, 2));
    expect(tester.getRect(scroll).contains(after.center), isTrue);
    expect(position.pixels, greaterThan(80), reason: '通知完成不應把閱讀區帶回開頭');
    expect(harness.repo.putUnifiedCalls, 2);
    expect(harness.usageSyncCalls, 2, reason: '新正式回答已完成，不因延後閱讀而延後或重複額度同步');

    await tester.tap(find.byKey(const Key('coach-new-answer')));
    await _finish(tester);

    expect(find.byKey(const Key('coach-new-answer')), findsNothing);
    expect(find.text(newHeadline).hitTestable(), findsOneWidget);
    expect(find.text(_longAnswer), findsNothing);
    final headlineTop = tester.getTopLeft(find.text(newHeadline)).dy;
    final viewportTop = tester.getTopLeft(scroll).dy;
    expect(headlineTop, greaterThanOrEqualTo(viewportTop));
    expect(headlineTop, lessThan(viewportTop + 140),
        reason: '主動點通知後應從新答案標題開始閱讀');
    expect(harness.usageSyncCalls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('正式 A 深挖成釐清 C 後捨棄 C，讀 A 期間新回覆完成不會變空白', (tester) async {
    final harness = await _pump(tester);
    await _send(tester, harness, '先分析目前的互動。');
    harness.succeed(0);
    await _finish(tester);
    final formalId = harness.repo.latestForScope('global', 'me')!.id;

    await tester.ensureVisible(find.text('繼續深挖'));
    await tester.tap(find.text('繼續深挖'));
    await _send(tester, harness, '可以再幫我確認自己的想法嗎？');
    harness.succeed(1, clarifying: true);
    await _finish(tester);
    if (find.byKey(const Key('coach-new-answer')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('coach-new-answer')));
      await _finish(tester);
    }
    final clarifyId = harness.repo.latestForScope('global', 'me')!.id;
    expect(clarifyId, isNot(formalId));
    expect(find.text(_clarifyingQuestion), findsOneWidget);

    await tester.ensureVisible(find.text('想問別的'));
    await tester.tap(find.text('想問別的'));
    await _finish(tester);
    expect(
        harness.repo.listByScope('global', 'me').map((r) => r.id), [formalId]);
    expect(find.text(_clarifyingQuestion), findsNothing);
    expect(find.byKey(const Key('coach-new-answer')), findsNothing);
    expect(find.text(_formalHeadline), findsOneWidget);

    await tester.ensureVisible(find.text('看完整教練分析'));
    await tester.tap(find.text('看完整教練分析'));
    await _finish(tester);
    await _scrollToFifthParagraph(tester);
    await _send(tester, harness, '另一件事，我要怎麼約下一次？');
    final before = _fifthParagraphRect(tester);
    harness.succeed(2, headline: '先提出一個具體又輕鬆的邀約');
    await _finish(tester);

    expect(find.byKey(const Key('coach-new-answer')).hitTestable(),
        findsOneWidget);
    expect(find.byKey(ValueKey('coach-answer-$formalId')), findsOneWidget,
        reason: '捨棄的 C 不能再拿來切 timeline，舊正式 A 仍應可讀');
    expect(find.byKey(ValueKey('coach-answer-$clarifyId')), findsNothing);
    expect(find.text(_longAnswer), findsOneWidget);
    expect(_fifthParagraphRect(tester).top, closeTo(before.top, 2));
    expect(harness.repo.listByScope('global', 'me'), hasLength(2));
    expect(harness.usageSyncCalls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('等待與新回覆待讀時都能寫草稿，只擋送出並持續顯示費用', (tester) async {
    final harness = await _pump(tester);
    final semantics = tester.ensureSemantics();
    try {
      await tester.tap(_input);
      harness.keyboardInset.value = 300;
      await _finish(tester);
      expect(find.text('釐清免費 · 正式建議扣 1 則').hitTestable(), findsOneWidget);

      await _send(tester, harness, '我該如何判斷她的短回？');
      expect(tester.widget<TextField>(_input).focusNode!.hasFocus, isTrue);
      const firstDraft = '先記下另一個想法，等這題回覆。';
      await tester.enterText(_input, firstDraft);
      await tester.tap(find.byIcon(Icons.arrow_upward));
      await _finish(tester);
      expect(harness.calls, hasLength(1));
      expect(tester.widget<TextField>(_input).controller!.text, firstDraft);
      expect(tester.widget<TextField>(_input).focusNode!.hasFocus, isTrue);
      expect(find.bySemanticsLabel('等待教練回覆'), findsOneWidget);
      expect(find.byKey(const Key('coach-composer-cost')).hitTestable(),
          findsOneWidget);

      harness.succeed(0);
      await _finish(tester);
      expect(tester.widget<TextField>(_input).controller!.text, firstDraft);
      expect(tester.widget<TextField>(_input).focusNode!.hasFocus, isTrue,
          reason: '非同步回覆不應替使用者收起仍在編輯的輸入列');
      await tester.ensureVisible(find.text('看完整教練分析'));
      await tester.tap(find.text('看完整教練分析'));
      await _finish(tester);
      await _scrollToFifthParagraph(tester);
      await _send(tester, harness, '但我還不確定自己想不想推進。');
      const pendingDraft = '我想慢慢來，不用現在就邀約。';
      await tester.enterText(_input, pendingDraft);
      await _finish(tester);
      harness.succeed(1, clarifying: true);
      await _finish(tester);

      expect(find.text('新回覆已完成，從開頭看'), findsOneWidget);
      expect(find.bySemanticsLabel('新回覆已完成，請先閱讀'), findsOneWidget);
      expect(find.bySemanticsLabel('等待教練回覆'), findsNothing);
      expect(tester.widget<TextField>(_input).controller!.text, pendingDraft);
      expect(tester.widget<TextField>(_input).focusNode!.hasFocus, isTrue);
      await tester.enterText(_input, '$pendingDraft 先保存這句。');
      await tester.tap(find.byIcon(Icons.arrow_upward));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _finish(tester);
      expect(tester.widget<TextField>(_input).focusNode!.hasFocus, isFalse,
          reason: '新回覆待讀時，使用者仍能按完成主動收鍵盤');
      expect(harness.calls, hasLength(2));
      expect(tester.widget<TextField>(_input).controller!.text,
          '$pendingDraft 先保存這句。');
      expect(find.byKey(const Key('coach-composer-cost')).hitTestable(),
          findsOneWidget);
      expect(tester.getBottomRight(_input).dy, lessThanOrEqualTo(544));
      expect(harness.usageSyncCalls, 1, reason: '第二輪免費釐清不能因提示或草稿操作多扣一次');
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('首次等待沒有可捲長文時，完成鍵仍能主動收鍵盤且保留草稿', (tester) async {
    final harness = await _pump(tester);
    await tester.tap(_input);
    harness.keyboardInset.value = 300;
    await _send(tester, harness, '她剛剛只回一個字。');
    await _finish(tester);
    expect(_readingPosition(tester).maxScrollExtent, 0,
        reason: '此情境不能依賴拖動長文收鍵盤');
    expect(tester.widget<TextField>(_input).focusNode!.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    const draft = '我想補充她前一則其實有問我問題。';
    await tester.enterText(_input, draft);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _finish(tester);
    expect(tester.widget<TextField>(_input).focusNode!.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(tester.widget<TextField>(_input).controller!.text, draft);
    expect(harness.calls, hasLength(1));
    expect(find.byType(CoachChatProgressNotice), findsOneWidget);

    harness.succeed(0, clarifying: true);
    await _finish(tester);
    expect(tester.widget<TextField>(_input).focusNode!.hasFocus, isFalse,
        reason: '使用者已主動收起後，回覆到達也不應重新搶焦點');
    expect(tester.widget<TextField>(_input).controller!.text, draft);
    expect(harness.usageSyncCalls, 0);
    await tester.tap(_input);
    await _finish(tester);
    expect(tester.widget<TextField>(_input).focusNode!.hasFocus, isTrue);
    expect(tester.widget<TextField>(_input).controller!.text, draft);
    expect(tester.takeException(), isNull);
  });

  testWidgets('大字體進場先縮人物，文字維持使用者倍率且輸入仍可見', (tester) async {
    await _pump(tester);
    final portrait = find.byKey(const Key('coach-welcome-portrait'));
    final normalSize = tester.getSize(portrait);
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester, textScale: 2.5);
    final largeTextPortrait = tester.getSize(portrait);

    expect(largeTextPortrait.width, lessThan(normalSize.width));
    expect(largeTextPortrait.height, lessThan(normalSize.height));
    final opening = find.text('隨時問我，聊天卡住我來接。');
    final richText =
        find.descendant(of: opening, matching: find.byType(RichText));
    expect(tester.widget<RichText>(richText).textScaler.scale(16), 40);
    expect(_input.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('390×844 大字體讀全文時，鍵盤不搶閱讀位置且輸入仍在可用區', (tester) async {
    final harness = await _pump(tester, textScale: 1.5);
    expect(tester.takeException(), isNull);
    await _send(tester, harness, '我想先看完整建議。');
    harness.succeed(0);
    await _finish(tester);
    final nextStepText = find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText() == '這次先做：回顧最近三則她的回覆，看看有沒有反問或延伸。',
    );
    expect(nextStepText, findsOneWidget);
    expect(tester.widget<RichText>(nextStepText).textScaler.scale(16), 24,
        reason: '主行動文字也必須套用 1.5 倍字體，不能只有一般 Text 放大');
    await tester.ensureVisible(find.text('看完整教練分析'));
    await tester.tap(find.text('看完整教練分析'));
    await _finish(tester);

    final position = _readingPosition(tester);
    expect(position.maxScrollExtent, greaterThan(500));
    position.jumpTo(position.maxScrollExtent * 0.4);
    await tester.pump();
    final readingOffset = position.pixels;

    await tester.tap(_input);
    harness.keyboardInset.value = 300;
    await _finish(tester);
    expect(tester.takeException(), isNull);
    expect(find.text(_longAnswer), findsOneWidget);
    expect(find.byKey(const Key('coach-welcome')), findsNothing);
    expect(position.pixels, closeTo(readingOffset, 2),
        reason: '打字只縮短可視高度，不得把全文捲回頂端或底部');
    expect(tester.getBottomRight(_input).dy, lessThanOrEqualTo(544));
    expect(tester.getTopLeft(_input).dy, greaterThan(0));
    expect(find.byIcon(Icons.arrow_upward).hitTestable(), findsOneWidget);

    harness.keyboardInset.value = 0;
    FocusManager.instance.primaryFocus?.unfocus();
    await _finish(tester);
    expect(position.pixels, closeTo(readingOffset, 2));
    await tester.ensureVisible(find.text('收起完整分析'));
    await tester.tap(find.text('收起完整分析'));
    await _finish(tester);
    expect(find.text(_longAnswer), findsNothing);
    expect(find.text('看完整教練分析').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('指定對象收起人物後仍鎖定 partner，不能從精簡列改問一般', (tester) async {
    final harness = await _pump(tester, lockedPartner: true);
    expect(find.byKey(const Key('coach_scope_general')), findsNothing);
    await tester.enterText(_input, '她說週末有空，我該怎麼接？');
    await _finish(tester);

    expect(find.byKey(const Key('coach-compact-avatar')), findsOneWidget);
    expect(find.byKey(const Key('coach-welcome')), findsNothing);
    expect(find.byKey(const Key('coach_scope_general')), findsNothing);
    expect(find.text('一般'), findsNothing);
    expect(tester.widget<CoachSurface>(find.byType(CoachSurface)).scope,
        const CoachScope.partner('p1'));
    expect(harness.calls, isEmpty);

    await _send(tester, harness, '她說週末有空，我該怎麼接？');
    expect(harness.calls.single['partnerId'], 'p1');
    expect(
        harness.calls.single['scope'], {'type': 'partner', 'partnerId': 'p1'});
    harness.succeed(0, clarifying: true);
    await _finish(tester);
    expect(find.byKey(const Key('coach_scope_general')), findsNothing);
    expect(tester.widget<CoachSurface>(find.byType(CoachSurface)).scope,
        const CoachScope.partner('p1'));
  });

  testWidgets('釐清頁取消直接建議確認，不發 request 也不更新額度', (tester) async {
    final harness = await _pump(tester);
    await _send(tester, harness, '她是不是不想聊了？');
    harness.succeed(0, clarifying: true);
    await _finish(tester);

    await tester.ensureVisible(find.text('直接看建議（扣 1 則）'));
    await tester.tap(find.text('直接看建議（扣 1 則）'));
    await _finish(tester);
    expect(find.text('直接看正式建議？'), findsOneWidget);
    expect(harness.calls, hasLength(1));

    await tester.tap(find.text('先補充想法'));
    await _finish(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text(_clarifyingQuestion), findsOneWidget);
    expect(harness.calls, hasLength(1));
    expect(harness.usageSyncCalls, 0);
  });
}
