// UX review still-frames for the analysis page: input → streaming → result.
//
// Pumps the REAL AnalysisScreen with the REAL StreamingAnalyzeNotifier and the
// REAL AnalyzeStreamClient. Only the HTTP transport is faked: it replays the
// exact NDJSON wire lines recorded by the 2026-10-02 Sonnet 5.5 blackbox run
// (tools/analyze-v2-blackbox/out/2026-10-02-e2e/records.json, arm C), one
// milestone at a time, so every frame is what the App would show at that
// point of a real stream. No network, no paid call.
// The recording is a paid (essential, five-style) run, so the screen is
// seeded as an essential subscriber too; a free screen would mismatch it.
//
//   flutter test test/visual_proof/analysis_stream_ux_capture_test.dart
// Out: build/visual_proof/ux_*.png
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_ce/hive.dart';
import 'package:vibesync/core/constants/app_constants.dart';
import 'package:vibesync/core/services/usage_service.dart';
import 'package:vibesync/core/theme/app_theme.dart';
import 'package:vibesync/core/theme/app_typography.dart';
import 'package:vibesync/features/analysis/application/analysis_run_preparer.dart';
import 'package:vibesync/features/analysis/data/providers/analysis_providers.dart';
import 'package:vibesync/features/analysis/data/providers/analysis_record_providers.dart';
import 'package:vibesync/features/analysis/data/services/conversation_memory_adapter.dart';
import 'package:vibesync/features/analysis/data/services/analyze_stream_client.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';
import 'package:vibesync/features/analysis/presentation/helpers/analysis_stream_content_display.dart';
import 'package:vibesync/features/analysis/presentation/screens/analysis_screen.dart';
import 'package:vibesync/features/analysis/presentation/widgets/analysis_action_widgets.dart';
import 'package:vibesync/features/analysis/presentation/widgets/screenshot_recognition_dialog.dart';
import 'package:vibesync/features/analysis_history/data/providers/analysis_history_providers.dart';
import 'package:vibesync/features/coach_chat/data/providers/coach_chat_providers.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';
import 'package:vibesync/features/coach_chat/domain/entities/unified_coach_result.dart';
import 'package:vibesync/features/coach_chat/domain/entities/coach_scope.dart';
import 'package:vibesync/features/coaching_memory/data/providers/coaching_outcome_providers.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_archive_providers.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_archive_store.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_repository.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/conversation/domain/entities/session_context.dart';
import 'package:vibesync/shared/widgets/ai_data_sharing_consent.dart';

import '../helpers/memory_analysis_history_repository.dart';
import '../helpers/memory_coach_chat_repository.dart';
import '../helpers/memory_coaching_outcome_repository.dart';
import 'proof_support.dart';

// Fresh id per test: the shared Hive settings box keeps analysis records.
var _id = 'ux-capture-0';
var _idSeq = 0;
const _tall = Size(390, 2400);

// ---------------------------------------------------------------------------
// Recorded wire replay
// ---------------------------------------------------------------------------

List<String> _wireLines(String caseId) {
  final file = File(
    'tools/analyze-v2-blackbox/out/2026-10-02-e2e/records.json',
  );
  final records =
      (jsonDecode(file.readAsStringSync()) as Map<String, dynamic>)['records']
          as List<dynamic>;
  final record = records.cast<Map<String, dynamic>>().firstWhere(
    (r) => r['arm'] == 'C' && r['caseId'] == caseId,
  );
  final text = (record['result'] as Map<String, dynamic>)['clientText'];
  return (text as String)
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .toList();
}

/// Each send() hands out the next scripted body; the test pushes wire lines.
class _ScriptedHttp extends http.BaseClient {
  final bodies = <StreamController<List<int>>>[];

  /// When > 0, the next N sends fail at connect (simulates network down).
  int failNextSends = 0;

  StreamController<List<int>> get current => bodies.last;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (failNextSends > 0) {
      failNextSends--;
      throw TimeoutException('scripted connect timeout');
    }
    final body = StreamController<List<int>>();
    bodies.add(body);
    return http.StreamedResponse(
      body.stream,
      200,
      headers: {'content-type': 'application/x-ndjson'},
    );
  }
}

// ---------------------------------------------------------------------------
// Repository stubs (same shape as analysis_screen characterization tests)
// ---------------------------------------------------------------------------

class _StubConversationRepository extends ConversationRepository {
  _StubConversationRepository(this._conversation);
  Conversation _conversation;

  @override
  Conversation? getConversation(String id) =>
      id == _conversation.id ? _conversation : null;

  @override
  Future<void> updateConversation(Conversation c) async {
    _conversation = c;
  }
}

class _MemoryArchiveStore implements ConversationArchiveStore {
  @override
  ConversationArchiveEntry? entryFor(Conversation conversation) => null;
  @override
  Future<void> markActive(
    Conversation conversation, {
    DateTime? changedAt,
    String? analyzedContentRevision,
  }) async {}
  @override
  Future<void> markArchived(
    Conversation conversation, {
    required DateTime archivedAt,
  }) async {}
  @override
  Future<void> remove(Conversation conversation) async {}
}

Conversation _conversation(List<(bool, String)> lines) {
  final base = DateTime(2026, 10, 2, 21, 0);
  return Conversation(
    id: _id,
    name: 'Ivy',
    ownerUserId: 'proof-user',
    messages: [
      for (var i = 0; i < lines.length; i++)
        Message(
          id: 'm$i',
          content: lines[i].$2,
          isFromMe: lines[i].$1,
          timestamp: base.add(Duration(minutes: i)),
        ),
    ],
    createdAt: base,
    updatedAt: base,
  );
}

// corpus.ts hobby_common_ground / cold_one_word_replies / soft_reject_after_invite
const _hobby = [
  (false, '你也有在玩攝影喔 我看你照片'),
  (true, '對啊 但都是隨手拍'),
  (false, '我最近在學底片 沖出來都糊掉哈哈'),
  (false, '你有推薦的入門機嗎'),
];
const _cold = [
  (true, '今天天氣超好 有出門嗎'),
  (false, '沒'),
  (true, '那在家做什麼'),
  (false, '躺著'),
  (true, '哈哈 週末就是要耍廢 你平常有什麼興趣嗎'),
  (false, '還好'),
];
const _softReject = [
  (false, '你週末都在幹嘛啊'),
  (true, '通常會去爬山或找朋友吃飯，你呢'),
  (false, '我都在家耍廢哈哈'),
  (true, '那這週六要不要一起去吃那家新開的義大利麵'),
  (false, '這週有點忙耶'),
  (false, '下次再看看'),
];

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

final _rootKey = GlobalKey();

final _essentialLimits = SubscriptionTierHelper.limitsFor(
  SubscriptionTierHelper.essential,
);

/// Keeps the seeded paid state; every sync just restores it.
class _PaidSubscriptionNotifier extends SubscriptionNotifier {
  _PaidSubscriptionNotifier(this._seed) {
    state = _seed;
  }

  final SubscriptionState _seed;

  @override
  Future<void> refresh() async => state = _seed;

  @override
  Future<void> syncWithRevenueCat() async => state = _seed;

  @override
  Future<void> ensureServerEntitlementSyncedForAnalysis() async =>
      state = _seed;

  @override
  void syncUsageFromServer({
    required int monthlyRemaining,
    required int dailyRemaining,
    bool isTestAccount = false,
  }) {}
}

Future<_ScriptedHttp> _pumpScreen(
  WidgetTester tester,
  Conversation conversation,
) async {
  await tester.binding.setSurfaceSize(kPhone);
  final transport = _ScriptedHttp();
  final client = AnalyzeStreamClient(
    displayMapper: const AnalysisStreamContentDisplayMapper(),
    clientFactory: () => transport,
    accessTokenProvider: () => 'proof-token',
    expectedTierProvider: () => SubscriptionTierHelper.essential,
    revenueCatAppUserIdProvider: () async => null,
  );
  final theme = AppTheme.darkTheme;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coachingOutcomeRepositoryProvider.overrideWithValue(
          MemoryCoachingOutcomeRepository(),
        ),
        analysisHistoryRepositoryProvider.overrideWithValue(
          MemoryAnalysisHistoryRepository(),
        ),
        conversationArchiveStoreProvider.overrideWithValue(
          _MemoryArchiveStore(),
        ),
        conversationRepositoryProvider.overrideWithValue(
          _StubConversationRepository(conversation),
        ),
        conversationProvider(_id).overrideWithValue(conversation),
        analyzeStreamClientProvider.overrideWithValue(client),
        // Signed-in owner so the analysis record persists like production.
        analysisRecordOwnerProvider.overrideWith((ref) => 'proof-user'),
        // Essential subscriber, matching the paid five-style recording.
        subscriptionProvider.overrideWith(
          (ref) => _PaidSubscriptionNotifier(
            SubscriptionState(
              tier: SubscriptionTierHelper.essential,
              monthlyLimit: _essentialLimits.monthly,
              dailyLimit: _essentialLimits.daily,
            ),
          ),
        ),
        // Hive usage box stand-in: essential limits, a few used.
        usageDataProvider.overrideWithValue(
          UsageData(
            monthlyUsed: 12,
            monthlyLimit: _essentialLimits.monthly,
            dailyUsed: 3,
            dailyLimit: _essentialLimits.daily,
            dailyResetAt: DateTime(2026, 10, 3),
          ),
        ),
        // Real preparer; only Hive-backed partner/profile lookups stubbed
        // (this proof conversation has no partner card).
        analysisRunPreparerProvider.overrideWithValue(
          AnalysisRunPreparer(
            memory: ConversationMemoryAdapter(),
            resolvePartnerSummary: (_) => null,
            resolveEffectiveStyleContext: (_) => null,
            resolveSessionContext: (c) => c.sessionContext,
          ),
        ),
        coachChatRepositoryProvider.overrideWithValue(
          MemoryCoachChatRepository(),
        ),
        coachChatHistoryProvider(CoachScope.conversation(_id))
            .overrideWithValue(const <UnifiedCoachResult>[]),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'AppTC'),
          primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'AppTC'),
          appBarTheme: theme.appBarTheme.copyWith(
            titleTextStyle: AppTypography.appBarTitle.copyWith(
              fontFamily: 'AppTC',
            ),
          ),
        ),
        // Boundary wraps the Navigator so dialogs/snackbars are in frame.
        builder: (context, child) => RepaintBoundary(
          key: _rootKey,
          child: DefaultTextStyle.merge(
            style: const TextStyle(fontFamily: 'AppTC'),
            child: child!,
          ),
        ),
        home: AnalysisScreen(conversationId: _id),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  tester.takeException();
  return transport;
}

Future<void> _shot(WidgetTester tester, String name, {Size? size}) async {
  if (size != null) {
    await tester.binding.setSurfaceSize(size);
    await tester.pump(const Duration(milliseconds: 50));
  }
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_rootKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    (File(outPath('ux_$name.png'))..createSync(recursive: true))
        .writeAsBytesSync(data!.buffer.asUint8List());
  });
  // Verbatim on-stage copy (tree order) next to the PNG, icon glyphs dropped.
  final texts = tester
      .widgetList<RichText>(find.byType(RichText))
      .map(
        (w) => w.text
            .toPlainText()
            .replaceAll(RegExp('[\uE000-\uF8FF]'), '')
            .trim(),
      )
      .where((t) => t.isNotEmpty)
      .toList();
  File(outPath('ux_$name.txt')).writeAsStringSync('${texts.join('\n')}\n');
  if (size != null) {
    await tester.binding.setSurfaceSize(kPhone);
    await tester.pump(const Duration(milliseconds: 50));
  }
  tester.takeException();
}

/// Phone-height pages of a long screen, top to bottom (readable crops).
Future<void> _pages(WidgetTester tester, String name) async {
  final state = tester.state<ScrollableState>(find.byType(Scrollable).first);
  state.position.jumpTo(0);
  await tester.pump(const Duration(milliseconds: 100));
  var page = 1;
  while (true) {
    await _shot(tester, '${name}_p$page');
    final pos = state.position;
    if (pos.pixels >= pos.maxScrollExtent - 1 || page >= 8) break;
    pos.jumpTo((pos.pixels + 600).clamp(0, pos.maxScrollExtent));
    await tester.pump(const Duration(milliseconds: 100));
    page++;
  }
  state.position.jumpTo(0);
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _dismissCoachMark(WidgetTester tester) async {
  final ok = find.text('知道了');
  if (ok.evaluate().isNotEmpty) {
    await tester.tap(ok.first);
    await tester.pump(const Duration(milliseconds: 400));
  }
}

/// Taps the real analyze CTA, walks the preview + consent dialogs (optionally
/// photographing them), and returns once the stream request is open.
Future<void> _startAnalysis(
  WidgetTester tester, {
  String? previewShot,
  String? consentShot,
}) async {
  await tester.tap(find.byKey(FloatingAnalysisActionButton.buttonKey));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  if (previewShot != null) await _shot(tester, previewShot);
  await tester.tap(find.text('開始分析').last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  if (consentShot != null) await _shot(tester, consentShot);
  final accept = find.text('同意並繼續');
  if (accept.evaluate().isNotEmpty) {
    await tester.tap(find.byType(Checkbox).last);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(accept.last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
}

Future<void> _push(
  WidgetTester tester,
  _ScriptedHttp transport,
  List<String> lines, {
  Duration settle = const Duration(milliseconds: 700),
}) async {
  for (final line in lines) {
    transport.current.add(utf8.encode('$line\n'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(settle);
  tester.takeException();
}

Future<void> _scrollToBottom(WidgetTester tester) async {
  final scrollable = find.byType(Scrollable).first;
  final state = tester.state<ScrollableState>(scrollable);
  state.position.jumpTo(state.position.maxScrollExtent);
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _scrollToTop(WidgetTester tester) async {
  final scrollable = find.byType(Scrollable).first;
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _drain(WidgetTester tester) async {
  // Let snackbars/timers (incl. the 120s stream idle fence) expire.
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(seconds: 5));
  }
  tester.takeException();
}

void main() {
  setUpAll(() async {
    await loadProofFonts();
    // Plain (unencrypted) stand-ins for the usage/settings boxes the
    // done-transition usage sync writes to.
    Hive.init(Directory.systemTemp.createTempSync('ux_capture_hive').path);
    await Hive.openBox(AppConstants.usageBox);
    await Hive.openBox(AppConstants.settingsBox);
    // Tabler icon font (package font) so production icons are not tofu.
    final pkgs =
        (jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
                as Map<String, dynamic>)['packages']
            as List;
    final root =
        (pkgs.cast<Map<String, dynamic>>().firstWhere(
              (p) => p['name'] == 'flutter_tabler_icons',
            )['rootUri']
            as String);
    final ttf = File.fromUri(
      Uri.parse(root.endsWith('/') ? root : '$root/')
          .resolve('assets/fonts/tabler-icons.ttf'),
    );
    await (FontLoader('packages/flutter_tabler_icons/tabler-icons')..addFont(
          Future.value(
            ByteData.view(Uint8List.fromList(ttf.readAsBytesSync()).buffer),
          ),
        ))
        .load();
  });
  setUp(() {
    _id = 'ux-capture-${++_idSeq}';
    SharedPreferences.setMockInitialValues({});
    AiDataSharingConsent.debugUserIdOverride = () => 'proof-user';
  });
  tearDown(() => AiDataSharingConsent.debugUserIdOverride = null);

  testWidgets('01 input: empty fragment intake', (tester) async {
    await _pumpScreen(tester, _conversation(const []));
    await _shot(tester, '01_input_empty_intake');
    await _shot(tester, '01_input_empty_intake_tall', size: _tall);
    await _drain(tester);
  });

  testWidgets('01 input: recognition confirm dialog', (tester) async {
    final now = DateTime(2026, 10, 2);
    Widget dialog() => ColoredBox(
      // App background behind the sheet (the dialog is pumped alone).
      color: const Color(0xFF140C24),
      child: TickerMode(
        enabled: false,
        child: ScreenshotRecognitionDialog(
          recognized: RecognizedConversation(
            contactName: 'Ivy',
            messageCount: _hobby.length,
            summary: '識別到 ${_hobby.length} 則訊息',
            messages: [
              for (final (mine, text) in _hobby)
                RecognizedMessage(
                  side: mine ? 'right' : 'left',
                  isFromMe: mine,
                  content: text,
                ),
            ],
          ),
          warningMessage: null,
          initialName: 'Ivy',
          initialMeetingContext: MeetingContext.datingApp,
          initialDuration: AcquaintanceDuration.justMet,
          initialGoal: UserGoal.dateInvite,
          initialAnalysisContextNote: '',
          expectedPartnerName: 'Ivy',
          currentConversation: Conversation(
            id: 'ux-dialog',
            name: 'Ivy',
            messages: const [],
            createdAt: now,
            updatedAt: now,
          ),
        ),
      ),
    );
    // Page through the sheet's own scroll body.
    for (var page = 1; page <= 4; page++) {
      final name = 'ux_01_input_recognition_dialog_p$page';
      await pumpAndCapture(
        tester,
        child: dialog(),
        outPath: outPath('$name.png'),
        beforeCapture: (t) async {
          final scrollables = find.byType(Scrollable);
          if (scrollables.evaluate().isNotEmpty) {
            final pos = t.state<ScrollableState>(scrollables.first).position;
            pos.jumpTo(((page - 1) * 420.0).clamp(0, pos.maxScrollExtent));
            await t.pump();
          }
          final texts = t
              .widgetList<RichText>(find.byType(RichText))
              .map((w) => w.text.toPlainText().trim())
              .where((x) => x.isNotEmpty);
          File(outPath('$name.txt')).writeAsStringSync(texts.join('\n'));
        },
      );
    }
  });

  testWidgets('02/03 send case: full stream to result', (tester) async {
    final lines = _wireLines('hobby_common_ground');
    expect(lines.length, 15);
    final transport = await _pumpScreen(tester, _conversation(_hobby));
    await _shot(tester, '01_input_fragment_coachmark');
    await _dismissCoachMark(tester);
    await _shot(tester, '01_input_fragment_ready');

    await _startAnalysis(
      tester,
      previewShot: '01_input_preview_dialog',
      consentShot: '01_input_consent_dialog',
    );
    expect(transport.bodies, isNotEmpty, reason: 'stream request opened');
    await tester.pump(const Duration(milliseconds: 300));
    await _shot(tester, '02_stream_00_t0_connecting');

    // t≈0s: started + two server progress lines.
    await _push(tester, transport, lines.sublist(0, 3));
    await _shot(tester, '02_stream_01_t0_progress');
    // t≈2.9s: inventory + decision.
    await _push(tester, transport, lines.sublist(3, 5));
    await _shot(tester, '02_stream_02_t3_decision');
    await _shot(tester, '02_stream_02_t3_decision_tall', size: _tall);
    // t≈8.5s: recommendation + first card (extend).
    await _push(tester, transport, lines.sublist(5, 7));
    await _shot(tester, '02_stream_03_t8_first_card');
    await _shot(tester, '02_stream_03_t8_first_card_tall', size: _tall);
    // t≈13s: three cards.
    await _push(tester, transport, lines.sublist(7, 9));
    await _shot(tester, '02_stream_04_t13_three_cards_tall', size: _tall);
    // t≈15s: server heartbeat.
    await _push(tester, transport, lines.sublist(9, 10));
    await _shot(tester, '02_stream_05_t15_heartbeat');
    await _shot(tester, '02_stream_05_t15_heartbeat_tall', size: _tall);
    // t≈17s: all five cards, not done.
    await _push(tester, transport, lines.sublist(10, 12));
    await _shot(tester, '02_stream_06_t17_five_cards_tall', size: _tall);
    await _scrollToBottom(tester);
    await _shot(tester, '02_stream_06_t17_five_cards_bottom');
    await _scrollToTop(tester);
    // t≈19s: metrics + coach hint.
    await _push(tester, transport, lines.sublist(12, 14));
    await _shot(tester, '02_stream_07_t19_metrics_coach_tall', size: _tall);
    await _pages(tester, '02_stream_07_t19_metrics_coach');
    // t≈20.4s: done.
    await _push(tester, transport, lines.sublist(14));
    await tester.pump(const Duration(milliseconds: 900));
    await _shot(tester, '03_result_t20_done_viewport');
    await _scrollToTop(tester);
    await _shot(tester, '03_result_t20_done_top');
    await _shot(tester, '03_result_done_full', size: const Size(390, 3200));

    // Reply carousel: swipe through the five style cards.
    final zone = find.byKey(const ValueKey('analysis-reply-zone'));
    if (zone.evaluate().isNotEmpty) {
      await tester.ensureVisible(zone);
      await tester.pump(const Duration(milliseconds: 200));
      final pager = find
          .descendant(of: zone, matching: find.byType(Scrollable))
          .first;
      for (var i = 2; i <= 5; i++) {
        await tester.drag(pager, const Offset(-340, 0));
        await tester.pump(const Duration(milliseconds: 600));
        await _shot(tester, '03_result_carousel_card$i');
      }
      await _scrollToTop(tester);
    }

    final toggle = find.text('詳細分析');
    if (toggle.evaluate().isNotEmpty) {
      await tester.ensureVisible(toggle.first);
      await tester.tap(toggle.first);
      await tester.pump(const Duration(milliseconds: 600));
      tester.takeException();
      await _scrollToTop(tester);
      await _shot(
        tester,
        '03_result_done_detail_expanded_full',
        size: const Size(390, 4400),
      );
      await _pages(tester, '03_result_detail_expanded');
    }
    await _drain(tester);
  });

  for (final (caseId, convo, tag) in [
    ('cold_one_word_replies', _cold, 'do_not_send'),
    ('soft_reject_after_invite', _softReject, 'ack_stop'),
  ]) {
    testWidgets('04 no-send: $caseId', (tester) async {
      final lines = _wireLines(caseId);
      final transport = await _pumpScreen(tester, _conversation(convo));
      await _dismissCoachMark(tester);
      await _startAnalysis(tester);
      final decisionIndex = lines.indexWhere(
        (l) => l.contains('"analysis.decision"'),
      );
      await _push(tester, transport, lines.sublist(0, decisionIndex + 1));
      await _shot(tester, '04_nosend_${tag}_stream_decision_tall', size: _tall);
      await _push(tester, transport, lines.sublist(decisionIndex + 1));
      await tester.pump(const Duration(milliseconds: 900));
      await _shot(tester, '04_nosend_${tag}_done_viewport');
      await _scrollToTop(tester);
      await _shot(
        tester,
        '04_nosend_${tag}_done_full',
        size: const Size(390, 2600),
      );
      await _pages(tester, '04_nosend_${tag}_done');
      await _drain(tester);
    });
  }

  testWidgets('05 error: timeout after cards (auto-recover then retry card)', (
    tester,
  ) async {
    final lines = _wireLines('hobby_common_ground');
    final transport = await _pumpScreen(tester, _conversation(_hobby));
    await _dismissCoachMark(tester);
    await _startAnalysis(tester);
    await _push(tester, transport, lines.sublist(0, 9)); // 3 cards
    await _shot(tester, '05_error_00_before_drop_three_cards');
    // Mid-stream drop: idle timeout surfaces as TIMEOUT → auto-recover
    // (same runId, recovery request opens a second body).
    transport.current.addError(TimeoutException('idle'));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(transport.bodies.length, 2, reason: 'recovery request opened');
    await _shot(tester, '05_error_01_reconnecting');
    await _shot(tester, '05_error_01_reconnecting_tall', size: _tall);
    // Recovery body also drops; the 2nd automatic attempt fails at connect.
    transport.failNextSends = 1;
    transport.current.addError(TimeoutException('idle'));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    tester.takeException();
    await _shot(tester, '05_error_02_after_cards_retry_card');
    await _shot(tester, '05_error_02_after_cards_retry_card_tall', size: _tall);
    await _drain(tester);
  });

  testWidgets('05 error: fails before any event (connect timeout)', (
    tester,
  ) async {
    final transport = await _pumpScreen(tester, _conversation(_hobby));
    transport.failNextSends = 1;
    await _dismissCoachMark(tester);
    await _startAnalysis(tester);
    await tester.pump(const Duration(milliseconds: 600));
    tester.takeException();
    await _shot(tester, '05_error_03_before_events');
    await _shot(tester, '05_error_03_before_events_tall', size: _tall);
    await _drain(tester);
  });
}
