// 截圖辨識確認後一鍵「加入並開始分析」（Eric 2026-10-18）：先照今天匯入，再走分析鈕
// 同一個入口——開始鎖、最後一則提示、額度不足、超過 2000 字確認都照舊；
// 「先存起來，晚點再分析」維持今天的匯入、不送分析。確認框上那一行跟分析鈕同一套算法。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/core/constants/app_constants.dart';
import 'package:vibesync/core/services/message_calculator.dart';
import 'package:vibesync/core/services/usage_service.dart';
import 'package:vibesync/features/analysis/application/analysis_run_preparer.dart';
import 'package:vibesync/features/analysis/data/notifiers/streaming_analyze_notifier.dart';
import 'package:vibesync/features/analysis/data/providers/analysis_providers.dart';
import 'package:vibesync/features/analysis/data/services/analyze_stream_client.dart';
import 'package:vibesync/features/analysis/data/services/conversation_memory_adapter.dart';
import 'package:vibesync/features/analysis/data/services/ocr_recognition_cache_service.dart';
import 'package:vibesync/features/analysis/data/services/partner_context_resolver.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';
import 'package:vibesync/features/analysis/domain/entities/game_stage.dart';
import 'package:vibesync/features/analysis/presentation/helpers/analysis_stream_content_display.dart';
import 'package:vibesync/features/analysis/presentation/screens/analysis_screen.dart';
import 'package:vibesync/features/analysis/presentation/widgets/analysis_action_widgets.dart';
import 'package:vibesync/features/analysis/presentation/widgets/screenshot_recognition_dialog.dart';
import 'package:vibesync/features/analysis_history/data/providers/analysis_history_providers.dart';
import 'package:vibesync/features/coach_chat/data/providers/coach_chat_providers.dart';
import 'package:vibesync/features/coach_chat/domain/entities/coach_chat_result.dart';
import 'package:vibesync/features/coach_chat/domain/entities/coach_scope.dart';
import 'package:vibesync/features/coach_chat/domain/entities/unified_coach_result.dart';
import 'package:vibesync/features/coach_chat/domain/repositories/coach_chat_repository.dart';
import 'package:vibesync/features/coaching_memory/data/providers/coaching_outcome_providers.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_archive_providers.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_archive_store.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_repository.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/services/partner_summary_builder.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';
import 'package:vibesync/features/user_profile/data/repositories/partner_data_quality_repo_view.dart';
import 'package:vibesync/shared/widgets/ai_data_sharing_consent.dart';
import 'package:vibesync/shared/widgets/analysis_preview_dialog.dart';
import 'package:vibesync/shared/widgets/image_picker_widget.dart';

import '../../../helpers/memory_analysis_history_repository.dart';
import '../../../helpers/memory_coaching_outcome_repository.dart';

const _conversationId = 'ocr-one-tap-test';
const _analyzeLabel = '加入並開始分析';
const _importOnlyLabel = '先存起來，晚點再分析';

/// 「長按可編輯」提示（EditMessageCoachMark）的關閉鈕。
const _editHintDismissLabel = '知道了';

/// 縮圖會真的渲染，bytes 要是合法圖檔：1x1 透明 PNG。
final _imageBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

class _RecordingAnalyzeStreamClient extends AnalyzeStreamClient {
  _RecordingAnalyzeStreamClient()
      : super(displayMapper: const AnalysisStreamContentDisplayMapper());

  int streamCalls = 0;
  List<Message>? streamMessages;

  @override
  Stream<AnalysisStreamUpdate> stream(AnalyzeStreamRequest request) async* {
    streamCalls++;
    streamMessages = List<Message>.from(request.messages);
    yield AnalysisStreamUpdate.done(
      result: _analysisResult(),
      runId: request.analysisRunId ?? 'stream-ocr-one-tap',
    );
  }
}

AnalysisResult _analysisResult() {
  return const AnalysisResult(
    enthusiasmScore: 72,
    strategy: '保持沉穩',
    gameStage: GameStageInfo(
      current: GameStage.premise,
      status: GameStageStatus.normal,
      nextStep: '繼續',
    ),
    psychology: PsychologyAnalysis(subtext: '有興趣'),
    topicDepth: TopicDepth(
      current: TopicDepthLevel.personal,
      suggestion: '可深入',
    ),
    replies: {
      'extend': 'a',
      'resonate': 'b',
      'tease': 'c',
      'humor': 'd',
      'coldRead': 'e',
    },
    replyOptions: {},
    recommendation: FinalRecommendation(
      pick: 'tease',
      content: 'c',
      reason: 'r',
      psychology: 'p',
    ),
    reminder: '記得用你的方式說',
  );
}

class _SeededStreamingAnalyzeNotifier extends StreamingAnalyzeNotifier {
  _SeededStreamingAnalyzeNotifier(this.seed);
  final StreamingAnalysisState seed;

  @override
  StreamingAnalysisState build(String conversationId) => seed;
}

class _SeededSubscriptionNotifier extends SubscriptionNotifier {
  _SeededSubscriptionNotifier(this._seed) {
    state = _seed;
  }

  final SubscriptionState _seed;

  void restoreSeed() {
    state = _seed;
  }

  @override
  Future<void> refresh() async => restoreSeed();

  @override
  Future<void> syncWithRevenueCat() async => restoreSeed();

  @override
  Future<void> ensureServerEntitlementSyncedForAnalysis() async =>
      restoreSeed();

  @override
  void syncUsageFromServer({
    required int monthlyRemaining,
    required int dailyRemaining,
    bool isTestAccount = false,
  }) {}
}

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

class _MemoryConversationArchiveStore implements ConversationArchiveStore {
  final Map<String, ConversationArchiveEntry> entries = {};

  @override
  ConversationArchiveEntry? entryFor(Conversation conversation) =>
      entries[conversation.id];

  @override
  Future<void> markActive(
    Conversation conversation, {
    DateTime? changedAt,
    String? analyzedContentRevision,
  }) async {
    entries[conversation.id] = ConversationArchiveEntry.active(
      changedAt: changedAt ?? DateTime.now(),
      contentRevision:
          analyzedContentRevision ?? entries[conversation.id]?.contentRevision,
    );
  }

  @override
  Future<void> markArchived(
    Conversation conversation, {
    required DateTime archivedAt,
  }) async {
    entries[conversation.id] = ConversationArchiveEntry.archived(
      archivedAt: archivedAt,
      contentRevision: conversationContentRevision(conversation),
    );
  }

  @override
  Future<void> remove(Conversation conversation) async {
    entries.remove(conversation.id);
  }
}

class _EmptyCoachChatRepository extends CoachChatRepository {
  @override
  List<CoachChatResult> listByConversation(String conversationId) => const [];

  @override
  CoachChatResult? latestForConversation(String conversationId) => null;

  @override
  Future<void> put(CoachChatResult result) async {}

  @override
  Future<ConversationDeleteOutcome> deleteConversation(
    String conversationId,
  ) async =>
      const ConversationDeleteOutcome(
        deleted: true,
        deletedOwnerUserId: 'stub-owner',
      );

  @override
  Future<void> clearAll() async {}

  @override
  List<UnifiedCoachResult> listByScope(String scopeType, String scopeId) =>
      const [];

  @override
  UnifiedCoachResult? latestForScope(String scopeType, String scopeId) => null;

  @override
  Future<void> putUnified(UnifiedCoachResult result) async {}

  @override
  Future<void> deleteScope(String scopeType, String scopeId) async {}

  @override
  Future<bool> deleteUnified(String id) async => false;
}

class _NoPartnerRepo implements PartnerRepoView {
  @override
  Partner? getById(String id) => null;
}

class _NoPartnerConversationList implements ConversationListByPartnerView {
  @override
  List<Conversation> listByPartner(String partnerId) => const [];
}

class _NoPartnerDataQualityRepo implements PartnerDataQualityRepoView {
  @override
  bool isFlaggedUnresolved(String partnerId) => false;
}

class _Harness {
  _Harness({
    required this.recorder,
    required this.conversation,
  });

  final _RecordingAnalyzeStreamClient recorder;

  /// 畫面讀的同一個物件：匯入是就地整批取代，看它就知道匯入了沒。
  final Conversation conversation;
}

RecognizedConversation _recognized(List<RecognizedMessage> messages) =>
    RecognizedConversation(
      contactName: '小雲',
      messageCount: messages.length,
      summary: '測試批次',
      classification: 'valid_chat',
      importPolicy: 'allow',
      confidence: 'high',
      sideConfidence: 'high',
      messages: messages,
    );

RecognizedMessage _her(String content) =>
    RecognizedMessage(side: 'left', isFromMe: false, content: content);

RecognizedMessage _me(String content) =>
    RecognizedMessage(side: 'right', isFromMe: true, content: content);

/// 每則都比一則額度多 1 字，則數不會剛好落在整數邊界（照常數組，不寫死字數）。
String _chars(String glyph, {int units = 1}) =>
    glyph * (MessageCalculator.charsPerMessageUnit * units + 1);

/// 匯入後按下去會用幾則、剩幾則：跟正式算法分開算——計費字數照
/// [MessageCalculator]，剩下的額度照方案常數，不寫死數字。
AnalysisQuotaLine _expectedLine(
  List<RecognizedMessage> messages, {
  required int monthlyRemaining,
  required int dailyRemaining,
}) {
  final preview = MessageCalculator.previewAnalysisRequest([
    for (final (index, message) in messages.indexed)
      Message(
        id: 'expected-$index',
        content: message.content,
        isFromMe: message.isFromMe,
        timestamp: DateTime(2026, 10, 18, 9, index),
      ),
  ]);
  final line = AnalysisQuotaLine.of(
    preview,
    monthlyRemaining: monthlyRemaining,
    dailyRemaining: dailyRemaining,
  );
  expect(line, isNotNull, reason: '測試資料要落在不跳框的一般長度');
  return line!;
}

/// 免費方案（[SubscriptionState] 預設值）今天用了 [dailyUsed] 則時的那一行。
AnalysisQuotaLine _expectedFreeLine(
  List<RecognizedMessage> messages, {
  int dailyUsed = 0,
}) =>
    _expectedLine(
      messages,
      monthlyRemaining: AppConstants.freeMonthlyLimit,
      dailyRemaining: AppConstants.freeDailyLimit - dailyUsed,
    );

SubscriptionState _essentialPlan() {
  final limits =
      SubscriptionTierHelper.limitsFor(SubscriptionTierHelper.essential);
  return SubscriptionState(
    tier: SubscriptionTierHelper.essential,
    monthlyLimit: limits.monthly,
    dailyLimit: limits.daily,
  );
}

Future<_Harness> _pumpOcrScreen(
  WidgetTester tester, {
  required List<RecognizedMessage> recognizedMessages,
  SubscriptionState subscription = const SubscriptionState(),
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  // 辨識走快取命中：不打網路，直接出確認框。
  final tempDir = (await tester.runAsync(() async {
    final directory =
        await Directory.systemTemp.createTemp('vibesync_ocr_one_tap_');
    Hive.init(directory.path);
    await Hive.openBox<dynamic>(AppConstants.settingsBox);
    await OcrRecognitionCacheService.write(
      images: [_imageBytes],
      conversationId: _conversationId,
      recognizedConversation: _recognized(recognizedMessages),
    );
    return directory;
  }))!;
  addTearDown(() async {
    if (Hive.isBoxOpen(AppConstants.settingsBox)) {
      await Hive.box<dynamic>(AppConstants.settingsBox).close();
    }
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });
  SharedPreferences.setMockInitialValues({
    AiDataSharingConsent.acceptedKeyForTesting: true,
    'analysis_ocr_swipe_tutorial_seen_v1_global': true,
  });

  final conversation = Conversation(
    id: _conversationId,
    name: '小雲',
    messages: [],
    createdAt: DateTime(2026, 10, 18),
    updatedAt: DateTime(2026, 10, 18),
  );
  final recorder = _RecordingAnalyzeStreamClient();
  late final _SeededSubscriptionNotifier subscriptionNotifier;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coachingOutcomeRepositoryProvider
            .overrideWithValue(MemoryCoachingOutcomeRepository()),
        analysisHistoryRepositoryProvider
            .overrideWithValue(MemoryAnalysisHistoryRepository()),
        conversationArchiveStoreProvider
            .overrideWithValue(_MemoryConversationArchiveStore()),
        conversationRepositoryProvider
            .overrideWithValue(_StubConversationRepository(conversation)),
        conversationProvider(_conversationId).overrideWithValue(conversation),
        analyzeStreamClientProvider.overrideWithValue(recorder),
        coachChatRepositoryProvider
            .overrideWithValue(_EmptyCoachChatRepository()),
        coachChatHistoryProvider(const CoachScope.conversation(_conversationId))
            .overrideWithValue(const []),
        streamingAnalyzeProvider.overrideWith(
          () => _SeededStreamingAnalyzeNotifier(
            const StreamingAnalysisState.idle(),
          ),
        ),
        analysisRunPreparerProvider.overrideWithValue(
          AnalysisRunPreparer(
            memory: ConversationMemoryAdapter(),
            resolvePartnerSummary: (_) => null,
            resolveEffectiveStyleContext: (_) => null,
          ),
        ),
        partnerContextResolverProvider.overrideWithValue(
          PartnerContextResolver(
            partnerRepo: _NoPartnerRepo(),
            conversationRepo: _NoPartnerConversationList(),
            summaryBuilder: PartnerSummaryBuilder(),
            dataQualityRepo: _NoPartnerDataQualityRepo(),
          ),
        ),
        subscriptionProvider.overrideWith((ref) {
          subscriptionNotifier = _SeededSubscriptionNotifier(subscription);
          return subscriptionNotifier;
        }),
        // 確認流程照舊讀本機用量（只拿重置時間；方案載好時數字以方案為準）。
        usageDataProvider.overrideWithValue(
          UsageData(
            monthlyUsed: subscription.monthlyMessagesUsed,
            monthlyLimit: subscription.monthlyLimit,
            dailyUsed: subscription.dailyMessagesUsed,
            dailyLimit: subscription.dailyLimit,
            dailyResetAt: DateTime(2026, 10, 19),
          ),
        ),
      ],
      child: const MaterialApp(
        home: AnalysisScreen(conversationId: _conversationId),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  subscriptionNotifier.restoreSeed();
  await tester.pump();
  return _Harness(recorder: recorder, conversation: conversation);
}

/// 選一張圖、按辨識：快取命中後跳出確認框。
Future<void> _recognize(WidgetTester tester) async {
  final picker = tester.widget<ImagePickerWidget>(
    find.byType(ImagePickerWidget),
  );
  picker.onImagesChanged([_imageBytes]);
  await tester.pump();
  final recognizeButton = find.text('辨識截圖文字（1 張）');
  await tester.ensureVisible(recognizeButton);
  await tester.tap(recognizeButton);
  // 開始分析前只有有限次的動畫（確認框的滑動教學播兩輪就停），可以 settle。
  await tester.pumpAndSettle();
  expect(find.byType(ScreenshotRecognitionDialog), findsOneWidget);
}

/// 分析開始之後有輪播動畫，不能 settle：固定推幾格。
Future<void> _pumpFrames(WidgetTester tester, {int count = 8}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _tapInDialog(WidgetTester tester, String label) async {
  final button = find.descendant(
    of: find.byType(ScreenshotRecognitionDialog),
    matching: find.text(label),
  );
  await tester.ensureVisible(button);
  await tester.tap(button);
  await _pumpFrames(tester);
}

List<String> _contents(List<Message> messages) =>
    [for (final message in messages) message.content];

List<String> _recognizedContents(List<RecognizedMessage> messages) =>
    [for (final message in messages) message.content];

void main() {
  group('截圖確認框：加入並開始分析（Eric 2026-10-18）', () {
    testWidgets('按之前寫出這次會用幾則（照常數算），按下去先匯入、再送出一次，不跳確認框', (tester) async {
      final messages = [_her(_chars('好')), _her(_chars('嗯'))];
      final harness =
          await _pumpOcrScreen(tester, recognizedMessages: messages);
      await _recognize(tester);

      final line = _expectedFreeLine(messages);
      expect(line.units, greaterThan(1), reason: '測試資料不要剛好是最低 1 則');
      expect(
        find.descendant(
          of: find.byType(ScreenshotRecognitionDialog),
          matching: find.text(line.text),
        ),
        findsOneWidget,
      );

      await _tapInDialog(tester, _analyzeLabel);

      expect(find.byType(ScreenshotRecognitionDialog), findsNothing);
      expect(_contents(harness.conversation.messages),
          _recognizedContents(messages),
          reason: '先照今天的匯入整批放進這次片段');
      expect(find.text('開始分析前'), findsNothing);
      expect(harness.recorder.streamCalls, 1);
      expect(_contents(harness.recorder.streamMessages!),
          _recognizedContents(messages),
          reason: '送出去的是匯入後的內容');
      expect(find.text(_editHintDismissLabel), findsNothing,
          reason: '片段馬上唯讀，「長按可編輯」提示不跳出來蓋住畫面');
    });

    testWidgets('先存起來，晚點再分析：照今天只匯入、不送分析；分析鈕下那一行跟確認框上看到的一樣', (tester) async {
      final messages = [_her(_chars('好')), _her(_chars('嗯'))];
      final harness =
          await _pumpOcrScreen(tester, recognizedMessages: messages);
      await _recognize(tester);
      final line = _expectedFreeLine(messages);

      await _tapInDialog(tester, _importOnlyLabel);

      expect(find.byType(ScreenshotRecognitionDialog), findsNothing);
      expect(_contents(harness.conversation.messages),
          _recognizedContents(messages));
      expect(harness.recorder.streamCalls, 0);
      expect(find.text('已讀取 ${messages.length} 則聊天內容，尚未開始分析'), findsOneWidget);
      // 匯入前在確認框上算的，跟匯入後分析鈕用預備器算的是同一行。
      final caption = find.byKey(FloatingAnalysisActionButton.captionKey);
      expect(
        find.descendant(of: caption, matching: find.text(line.text)),
        findsOneWidget,
      );
      // 片段還能改：「長按可編輯」提示照今天出現（測試是 debug，每次都當沒看過）。
      expect(find.text(_editHintDismissLabel), findsOneWidget);
    });

    testWidgets('超過 2000 字：匯入後跳「內容較長」確認框，確認前不送出', (tester) async {
      // 三則合計剛好比一般長度多 1 字（照常數切）。
      const total = MessageCalculator.softCapBandMaxChars + 1;
      final first = total ~/ 3;
      final messages = [
        _her('好' * first),
        _her('嗯' * first),
        _her('喔' * (total - first * 2)),
      ];
      final harness = await _pumpOcrScreen(
        tester,
        recognizedMessages: messages,
        subscription: _essentialPlan(),
      );
      await _recognize(tester);
      expect(find.textContaining('這次會用'), findsNothing,
          reason: '超過 2000 字不寫那一行，按下去照舊確認');

      await _tapInDialog(tester, _analyzeLabel);

      expect(_contents(harness.conversation.messages),
          _recognizedContents(messages));
      expect(find.text('內容較長，確認後才會扣'), findsOneWidget);
      expect(harness.recorder.streamCalls, 0);

      await tester.tap(
        find.text('確認使用 ${MessageCalculator.overchargeUnits} 則'),
      );
      await _pumpFrames(tester);
      expect(harness.recorder.streamCalls, 1);
    });

    testWidgets('額度不夠：匯入後跳額度確認框、不能開始，一次都不送', (tester) async {
      final messages = [_her(_chars('好')), _her(_chars('嗯'))];
      final harness = await _pumpOcrScreen(
        tester,
        recognizedMessages: messages,
        subscription: const SubscriptionState(
          dailyMessagesUsed: AppConstants.freeDailyLimit,
        ),
      );
      await _recognize(tester);
      expect(find.textContaining('這次會用'), findsNothing);

      await _tapInDialog(tester, _analyzeLabel);

      expect(_contents(harness.conversation.messages),
          _recognizedContents(messages),
          reason: '匯入照樣留著');
      expect(find.text('開始分析前'), findsOneWidget);
      expect(find.text('今天的分析次數不夠了，每天早上 8 點恢復，也可以升級取得更多額度。'), findsOneWidget);
      final start = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, '開始分析'),
      );
      expect(start.onPressed, isNull);
      expect(harness.recorder.streamCalls, 0);
    });

    testWidgets('最後一則是他傳的：跳「最後一則是你傳的」，先不要就不送，匯入的內容留著', (tester) async {
      final messages = [_her(_chars('好')), _me('那我先去忙')];
      final harness =
          await _pumpOcrScreen(tester, recognizedMessages: messages);
      await _recognize(tester);

      await _tapInDialog(tester, _analyzeLabel);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('最後一則是你傳的'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('his-last-message-cancel')));
      await _pumpFrames(tester);

      expect(find.text('最後一則是你傳的'), findsNothing);
      expect(find.text('開始分析前'), findsNothing);
      expect(harness.recorder.streamCalls, 0);
      expect(_contents(harness.conversation.messages),
          _recognizedContents(messages));
      expect(find.text('已讀取 ${messages.length} 則聊天內容，尚未開始分析'), findsOneWidget);
      expect(find.text('繼續確認本次內容'), findsNothing, reason: '不是暫存草稿，已經匯入');
    });

    testWidgets('最後一則是他傳的：選「還是要分析」就照確認框那一行開始，不再跳確認框', (tester) async {
      final messages = [_her(_chars('好')), _me('那我先去忙')];
      final harness =
          await _pumpOcrScreen(tester, recognizedMessages: messages);
      await _recognize(tester);
      // 他最後那一則不算費（F04），那一行照只算她的那段。
      expect(find.text(_expectedFreeLine(messages).text), findsOneWidget);

      await _tapInDialog(tester, _analyzeLabel);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const ValueKey('his-last-message-proceed')));
      await _pumpFrames(tester);

      expect(find.text('開始分析前'), findsNothing);
      expect(harness.recorder.streamCalls, 1);
      expect(harness.recorder.streamMessages!.last.isFromMe, isTrue,
          reason: '他傳的那則照樣送去分析');
    });

    testWidgets('連點兩下「加入並開始分析」：只匯入一次、只送出一次，分析頁還在', (tester) async {
      final messages = [_her(_chars('好')), _her(_chars('嗯'))];
      final harness =
          await _pumpOcrScreen(tester, recognizedMessages: messages);
      await _recognize(tester);

      final button = find.descendant(
        of: find.byType(ScreenshotRecognitionDialog),
        matching: find.text(_analyzeLabel),
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.tap(button, warnIfMissed: false);
      await _pumpFrames(tester);

      expect(find.byType(AnalysisScreen), findsOneWidget);
      expect(harness.conversation.messages, hasLength(messages.length));
      expect(harness.recorder.streamCalls, 1);
    });

    testWidgets('先取消確認框：卡片「繼續確認本次內容」再打開，一樣可以加入並開始分析', (tester) async {
      final messages = [_her(_chars('好')), _her(_chars('嗯'))];
      final harness =
          await _pumpOcrScreen(tester, recognizedMessages: messages);
      await _recognize(tester);

      await _tapInDialog(tester, '取消');
      expect(harness.conversation.messages, isEmpty);
      final resume = find.text('繼續確認本次內容');
      await tester.ensureVisible(resume);
      await tester.tap(resume);
      await tester.pumpAndSettle();
      expect(find.byType(ScreenshotRecognitionDialog), findsOneWidget);

      await _tapInDialog(tester, _analyzeLabel);

      expect(_contents(harness.conversation.messages),
          _recognizedContents(messages));
      expect(find.text('開始分析前'), findsNothing);
      expect(harness.recorder.streamCalls, 1);
    });

    testWidgets('在確認框裡改了左右，那一行跟著重算；按下去照樣不跳確認框', (tester) async {
      // 最後一則他的不算費（F04），改成她說之後就要算。
      final messages = [_her(_chars('好')), _me(_chars('嗯'))];
      final harness =
          await _pumpOcrScreen(tester, recognizedMessages: messages);
      await _recognize(tester);
      final before = _expectedFreeLine(messages);
      final edited = [_her(_chars('好')), _her(_chars('嗯'))];
      final after = _expectedFreeLine(edited);
      expect(after.units, isNot(before.units), reason: '改了左右則數要不一樣');
      expect(find.text(before.text), findsOneWidget);

      final markAll = find.text('全部都是對方說的');
      await tester.ensureVisible(markAll);
      await tester.tap(markAll);
      await tester.pump();

      expect(find.text(before.text), findsNothing);
      expect(find.text(after.text), findsOneWidget);

      await _tapInDialog(tester, _analyzeLabel);
      expect(find.text('開始分析前'), findsNothing);
      expect(harness.recorder.streamCalls, 1);
    });

    testWidgets('方案還在載入：確認框不寫那一行，按下去照舊跳額度確認框、不送出', (tester) async {
      final messages = [_her(_chars('好')), _her(_chars('嗯'))];
      final harness = await _pumpOcrScreen(
        tester,
        recognizedMessages: messages,
        subscription: const SubscriptionState(isLoading: true),
      );
      await _recognize(tester);
      expect(find.textContaining('這次會用'), findsNothing);

      await _tapInDialog(tester, _analyzeLabel);

      expect(find.text('開始分析前'), findsOneWidget);
      expect(harness.recorder.streamCalls, 0);
    });
  });
}
