// 截圖辨識確認後一鍵「加入並開始分析」（Eric 2026-10-18）：先照今天匯入，再走分析鈕
// 同一個入口——開始鎖、最後一則提示、額度不足、超過 2000 字確認都照舊。確認框只剩
// 「取消」和它（Eric 2026-10-19 照 Bruce 拿掉「先存起來」）：一般情況按一下就匯入並
// 開始分析；「取消」把辨識結果留在這頁（續看卡）；只有後面真的跳出關卡而在那裡取消，
// 或額度不夠，匯入的內容才留著、不送（她的訊息有自傷字眼例外：照常送出，伺服器只回
// 關心訊息與專線、不扣，Eric 2026-10-18）。確認框上那一行跟分析鈕同一套算法。
import 'dart:async';
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
import 'package:vibesync/features/analysis/domain/errors/analysis_exceptions.dart';
import 'package:vibesync/features/analysis/presentation/helpers/analysis_stream_content_display.dart';
import 'package:vibesync/features/analysis/presentation/screens/analysis_screen.dart';
import 'package:vibesync/features/analysis/presentation/sections/analysis_error_card.dart';
import 'package:vibesync/features/analysis/presentation/sections/screenshot_intake_section.dart';
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

/// 取消確認框時保留這次辨識結果的那一句。
const _draftKeptMessage = '已保留這次辨識結果，你可以稍後再繼續確認。';

/// 「長按可編輯」提示（EditMessageCoachMark）的關閉鈕。
const _editHintDismissLabel = '知道了';

/// 縮圖會真的渲染，bytes 要是合法圖檔：1x1 透明 PNG。
final _imageBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// 同一頁換一批時選的第二張圖：另一個合法 1x1 PNG，快取照 bytes 分開記。
final _laterImageBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGO46Z8HAAObAZd+AmgeAAAAAElFTkSuQmCC',
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

  /// 開了就當存檔寫不進去：匯入那次存檔丟 [saveError]。
  bool failUpdates = false;
  Object saveError = const FileSystemException('save failed');

  /// 有給就先等它：存檔卡在半路，測「還沒回來就離開這頁」。
  Future<void>? pendingSave;

  @override
  Conversation? getConversation(String id) =>
      id == _conversation.id ? _conversation : null;

  @override
  Future<void> updateConversation(Conversation c) async {
    final pending = pendingSave;
    if (pending != null) await pending;
    if (failUpdates) {
      throw saveError;
    }
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
    required this.repository,
  });

  final _RecordingAnalyzeStreamClient recorder;

  /// 畫面讀的同一個物件：匯入是就地整批取代，看它就知道匯入了沒。
  final Conversation conversation;

  final _StubConversationRepository repository;
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
  // 同一頁換一批（[_repickAndRecognize]）時，第二張圖辨識出來的內容。
  List<RecognizedMessage>? laterRecognizedMessages,
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
    if (laterRecognizedMessages != null) {
      await OcrRecognitionCacheService.write(
        images: [_laterImageBytes],
        conversationId: _conversationId,
        recognizedConversation: _recognized(laterRecognizedMessages),
      );
    }
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
  final repository = _StubConversationRepository(conversation);
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
        conversationRepositoryProvider.overrideWithValue(repository),
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
  return _Harness(
    recorder: recorder,
    conversation: conversation,
    repository: repository,
  );
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

/// 同一頁換一批再辨識：「重新選圖」挑好圖之後走的就是這個入口（相簿是平台外掛，
/// 測試不開）。已經有匯入的內容，按鈕寫「辨識並取代本次內容」。
Future<void> _repickAndRecognize(WidgetTester tester) async {
  final intake =
      tester.state(find.byType(AnalysisScreen)) as ScreenshotIntakeActions;
  intake.selectedImagesChanged([_laterImageBytes]);
  await tester.pump();
  final recognizeButton = find.text('辨識並取代本次內容（1 張）');
  await tester.ensureVisible(recognizeButton);
  await tester.tap(recognizeButton);
  await _pumpFrames(tester);
  // 辨識計時器每秒才醒一次、辨識完下一次醒來才停：推過一秒，測試結束時不留計時器。
  await tester.pump(const Duration(seconds: 1));
  expect(find.byType(ScreenshotRecognitionDialog), findsOneWidget);
}

/// 先取消確認框，再從卡片「繼續確認本次內容」打開同一個確認框。
Future<void> _cancelThenResume(WidgetTester tester) async {
  await _tapInDialog(tester, '取消');
  final resume = find.text('繼續確認本次內容');
  await tester.ensureVisible(resume);
  await tester.tap(resume);
  await tester.pumpAndSettle();
  expect(find.byType(ScreenshotRecognitionDialog), findsOneWidget);
}

/// 匯入存檔失敗、不是分析錯誤時，錯誤卡上的訊息。
const _recognitionFailedMessage = '截圖辨識暫時失敗，請稍後再試。';

/// 截圖辨識那一種錯誤卡（初次辨識與續看用同一個檢查）：訊息、主按鈕照傳進來的；
/// 來源是辨識才有「強制重新辨識」那顆（這幾條路都有上一批圖可以重跑）。
void _expectRecognitionErrorCard(
  WidgetTester tester, {
  required String message,
  required String primaryActionLabel,
}) {
  expect(find.byType(AnalysisErrorCard), findsOneWidget);
  final card = tester.widget<AnalysisErrorCard>(find.byType(AnalysisErrorCard));
  expect(card.message, message);
  expect(card.primaryActionLabel, primaryActionLabel);
  expect(card.showForceReRecognize, isTrue, reason: '錯誤來源是截圖辨識');
}

/// 按錯誤卡的主按鈕「重新辨識」（不是旁邊的「強制重新辨識」）。
Future<void> _tapRetryRecognition(WidgetTester tester) async {
  final retry = find.widgetWithText(ElevatedButton, '重新辨識');
  await tester.ensureVisible(retry);
  await tester.tap(retry);
  await _pumpFrames(tester);
  // 辨識計時器每秒才醒一次、辨識完下一次醒來才停：推過一秒，測試結束時不留計時器。
  await tester.pump(const Duration(seconds: 1));
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

/// 三則合計剛好比一般長度多 1 字（照常數切）。
List<RecognizedMessage> _justOverSoftCap() {
  const total = MessageCalculator.softCapBandMaxChars + 1;
  final first = total ~/ 3;
  return [
    _her('好' * first),
    _her('嗯' * first),
    _her('喔' * (total - first * 2)),
  ];
}

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

    testWidgets('確認框只剩「取消」和「加入並開始分析」：唯一的送出就是先匯入、再開始分析', (tester) async {
      final messages = [_her(_chars('好')), _her(_chars('嗯'))];
      final harness =
          await _pumpOcrScreen(tester, recognizedMessages: messages);
      await _recognize(tester);

      Finder inDialog(String label) => find.descendant(
            of: find.byType(ScreenshotRecognitionDialog),
            matching: find.text(label),
          );
      expect(inDialog('先存起來，晚點再分析'), findsNothing);
      expect(inDialog('取消'), findsOneWidget);
      expect(inDialog(_analyzeLabel), findsOneWidget);

      await _tapInDialog(tester, _analyzeLabel);

      expect(_contents(harness.conversation.messages),
          _recognizedContents(messages));
      expect(harness.recorder.streamCalls, 1);
    });

    testWidgets('按「取消」：照今天保留這次辨識結果，什麼都沒匯入、一次都不送；從續看卡再開、再取消也一樣', (tester) async {
      final messages = [_her(_chars('好')), _her(_chars('嗯'))];
      final harness =
          await _pumpOcrScreen(tester, recognizedMessages: messages);
      await _recognize(tester);

      await _tapInDialog(tester, '取消');

      expect(find.byType(ScreenshotRecognitionDialog), findsNothing);
      expect(find.text(_draftKeptMessage), findsOneWidget);
      expect(harness.conversation.messages, isEmpty);
      expect(harness.recorder.streamCalls, 0);
      final resume = find.text('繼續確認本次內容');
      expect(resume, findsOneWidget);

      await tester.ensureVisible(resume);
      await tester.tap(resume);
      await tester.pumpAndSettle();
      expect(find.byType(ScreenshotRecognitionDialog), findsOneWidget);
      await _tapInDialog(tester, '取消');

      expect(find.byType(ScreenshotRecognitionDialog), findsNothing);
      expect(find.text(_draftKeptMessage), findsOneWidget);
      expect(harness.conversation.messages, isEmpty);
      expect(harness.recorder.streamCalls, 0);
      expect(find.text('繼續確認本次內容'), findsOneWidget, reason: '續看卡還在');
    });

    testWidgets('超過 2000 字：匯入後跳「內容較長」確認框，確認前不送出', (tester) async {
      final messages = _justOverSoftCap();
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

    testWidgets('額度不夠：匯入後跳額度確認框、不能開始；按取消後匯入的內容留著、停在尚未開始分析，一次都不送',
        (tester) async {
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

      // 額度不夠才會停在這一關；取消後匯入的內容留著、不送。一般情況不會跳這一關
      //（Eric 2026-10-19 照 Bruce 拿掉「先存起來」）。
      await tester.tap(find.descendant(
        of: find.byType(AnalysisPreviewDialog),
        matching: find.text('取消'),
      ));
      await _pumpFrames(tester);

      expect(find.text('開始分析前'), findsNothing);
      expect(harness.recorder.streamCalls, 0);
      expect(_contents(harness.conversation.messages),
          _recognizedContents(messages),
          reason: '匯入照樣留著');
      expect(find.text('已讀取 ${messages.length} 則聊天內容，尚未開始分析'), findsOneWidget);
      expect(find.text('繼續確認本次內容'), findsNothing, reason: '不是暫存草稿，已經匯入');
    });

    testWidgets('最後一則是他傳的：跳「最後一則是你傳的」，先不要就不送，匯入的內容留著；分析鈕下那一行跟確認框上看到的一樣',
        (tester) async {
      final messages = [_her(_chars('好')), _me('那我先去忙')];
      final harness =
          await _pumpOcrScreen(tester, recognizedMessages: messages);
      await _recognize(tester);
      final line = _expectedFreeLine(messages);
      expect(
        find.descendant(
          of: find.byType(ScreenshotRecognitionDialog),
          matching: find.text(line.text),
        ),
        findsOneWidget,
      );

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
      // 匯入前在確認框上算的，跟匯入後分析鈕用預備器算的是同一行。
      final caption = find.byKey(FloatingAnalysisActionButton.captionKey);
      expect(
        find.descendant(of: caption, matching: find.text(line.text)),
        findsOneWidget,
      );
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

      final markAll = find.text('全是她說');
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

  // 主審 P3 補測（Eric 2026-10-18「不接受，先處理」）：按了「加入並開始分析」、分析卻沒
  // 開始的幾條路。扣額只在送出的那一次請求，所以「沒送」就是「沒扣」。
  group('加入並開始分析：分析沒開始的路', () {
    testWidgets('先不要之後，同一頁換一批比較少則的、再按「加入並開始分析」：整批取代、照樣不排提示，這次照常送出一次',
        (tester) async {
      // 第一批 8 則、最後一則他的（會先問）；第二批 2 則，比第一批少。
      final first = [
        for (var i = 1; i <= 7; i++) _her('第$i則'),
        _me('那我先去忙'),
      ];
      final later = [_her('剛到家'), _her('你呢')];
      final harness = await _pumpOcrScreen(
        tester,
        recognizedMessages: first,
        laterRecognizedMessages: later,
      );
      await _recognize(tester);
      await _tapInDialog(tester, _analyzeLabel);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const ValueKey('his-last-message-cancel')));
      await _pumpFrames(tester);

      expect(harness.recorder.streamCalls, 0);
      expect(
          _contents(harness.conversation.messages), _recognizedContents(first));
      expect(find.text(_editHintDismissLabel), findsNothing,
          reason: '按「加入並開始分析」的那一批照原本的決定不排提示');

      await _repickAndRecognize(tester);
      await _tapInDialog(tester, _analyzeLabel);

      expect(later.length, lessThan(first.length));
      expect(
          _contents(harness.conversation.messages), _recognizedContents(later),
          reason: '第二批整批取代第一批');
      expect(find.text('開始分析前'), findsNothing);
      expect(harness.recorder.streamCalls, 1, reason: '上一批「先不要」之後開始鎖有放掉');
      expect(_contents(harness.recorder.streamMessages!),
          _recognizedContents(later));
      expect(find.text(_editHintDismissLabel), findsNothing,
          reason: '這一批也是按「加入並開始分析」，比上一批少則也不排提示');
    });

    testWidgets('匯入存檔失敗（按「$_analyzeLabel」）：照今天的匯入失敗顯示，一次都不送', (tester) async {
      final messages = [_her(_chars('好')), _her(_chars('嗯'))];
      final harness =
          await _pumpOcrScreen(tester, recognizedMessages: messages);
      await _recognize(tester);
      harness.repository.failUpdates = true;

      await _tapInDialog(tester, _analyzeLabel);

      expect(find.byType(ScreenshotRecognitionDialog), findsNothing);
      _expectRecognitionErrorCard(
        tester,
        message: _recognitionFailedMessage,
        primaryActionLabel: '重新辨識',
      );
      expect(find.text('最後一則是你傳的'), findsNothing);
      expect(find.text('開始分析前'), findsNothing);
      expect(harness.recorder.streamCalls, 0);
      expect(_contents(harness.conversation.messages),
          _recognizedContents(messages),
          reason: '照今天：畫面上那份已整批換過，只是存檔失敗');
    });

    // 續看卡那條路（主審 P3；Eric 2026-10-18「不接受，先處理」）：存檔失敗以前例外直接漏掉、
    // 畫面什麼都沒說；要跟初次辨識同一張錯誤卡。畫面那份訊息與續看卡照今天不動。
    // 例外沒接住的話，測試框架會判這條失敗。
    testWidgets('從「繼續確認本次內容」匯入、存檔失敗（按「$_analyzeLabel」）：跟初次辨識同一張錯誤卡，一次都不送',
        (tester) async {
      final messages = [_her(_chars('好')), _her(_chars('嗯'))];
      final harness =
          await _pumpOcrScreen(tester, recognizedMessages: messages);
      await _recognize(tester);
      await _cancelThenResume(tester);
      harness.repository.failUpdates = true;

      await _tapInDialog(tester, _analyzeLabel);

      expect(find.byType(ScreenshotRecognitionDialog), findsNothing);
      _expectRecognitionErrorCard(
        tester,
        message: _recognitionFailedMessage,
        primaryActionLabel: '重新辨識',
      );
      expect(find.text('最後一則是你傳的'), findsNothing);
      expect(find.text('開始分析前'), findsNothing);
      expect(harness.recorder.streamCalls, 0);
      expect(_contents(harness.conversation.messages),
          _recognizedContents(messages),
          reason: '照今天：畫面上那份已整批換過，只是存檔失敗');
      expect(find.text('繼續確認本次內容'), findsOneWidget, reason: '照今天：續看卡還在');
    });

    testWidgets('從「繼續確認本次內容」按「加入並開始分析」、存檔丟出分析錯誤：錯誤卡照那個錯誤的訊息和動作，一次都不送',
        (tester) async {
      final messages = [_her(_chars('好')), _her(_chars('嗯'))];
      final harness =
          await _pumpOcrScreen(tester, recognizedMessages: messages);
      await _recognize(tester);
      await _cancelThenResume(tester);
      // 動作挑一個不是重試的，才看得出是照錯誤帶的、不是寫死。
      harness.repository
        ..failUpdates = true
        ..saveError = AnalysisException(
          '測試用：存檔被擋下',
          suggestedAction: AnalysisErrorAction.shortenInput,
        );

      await _tapInDialog(tester, _analyzeLabel);

      _expectRecognitionErrorCard(
        tester,
        message: '測試用：存檔被擋下',
        primaryActionLabel: '調整內容',
      );
      expect(find.text(_recognitionFailedMessage), findsNothing);
      expect(find.text('開始分析前'), findsNothing);
      expect(harness.recorder.streamCalls, 0);
    });

    testWidgets('從「繼續確認本次內容」匯入、存檔還沒回來就離開這頁：之後存檔失敗也不碰已關掉的畫面，一次都不送',
        (tester) async {
      final messages = [_her(_chars('好')), _her(_chars('嗯'))];
      final harness =
          await _pumpOcrScreen(tester, recognizedMessages: messages);
      await _recognize(tester);
      await _cancelThenResume(tester);
      final save = Completer<void>();
      harness.repository
        ..failUpdates = true
        ..pendingSave = save.future;

      await _tapInDialog(tester, _analyzeLabel);
      await tester.pumpWidget(const SizedBox());
      save.complete();
      await tester.pump();

      // 關掉的畫面再 setState 會丟錯，測試框架會判這條失敗。
      expect(find.byType(AnalysisScreen), findsNothing);
      expect(harness.recorder.streamCalls, 0);
    });

    testWidgets('按下去時換了帳號、新帳號還沒同意：暫不同意就不送，匯入的內容留著', (tester) async {
      final messages = [_her(_chars('好')), _her(_chars('嗯'))];
      final harness =
          await _pumpOcrScreen(tester, recognizedMessages: messages);
      await _recognize(tester);
      // 辨識前已同意；同意是帳號級，確認框開著時換了帳號，開始分析前要重新問。
      AiDataSharingConsent.debugUserIdOverride = () => 'another-account';
      addTearDown(() => AiDataSharingConsent.debugUserIdOverride = null);

      await _tapInDialog(tester, _analyzeLabel);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('資料使用說明'), findsOneWidget);

      await tester.tap(find.text('暫不同意'));
      await _pumpFrames(tester);

      expect(find.text('資料使用說明'), findsNothing);
      expect(harness.recorder.streamCalls, 0);
      expect(_contents(harness.conversation.messages),
          _recognizedContents(messages),
          reason: '匯入照樣留著');
    });

    testWidgets('超過 2000 字：確認框按「取消」就不送，匯入的內容留著', (tester) async {
      final messages = _justOverSoftCap();
      final harness = await _pumpOcrScreen(
        tester,
        recognizedMessages: messages,
        subscription: _essentialPlan(),
      );
      await _recognize(tester);

      await _tapInDialog(tester, _analyzeLabel);
      expect(find.text('內容較長，確認後才會扣'), findsOneWidget);

      await tester.tap(find.descendant(
        of: find.byType(AnalysisPreviewDialog),
        matching: find.text('取消'),
      ));
      await _pumpFrames(tester);

      expect(find.text('內容較長，確認後才會扣'), findsNothing);
      expect(harness.recorder.streamCalls, 0);
      expect(_contents(harness.conversation.messages),
          _recognizedContents(messages),
          reason: '匯入照樣留著');
    });
  });

  // 辨識錯誤卡的「重新辨識」（Eric 2026-10-18；主審 P3 延伸）：以前清錯誤狀態時連來源一起
  // 清掉，按下去走的是分析（跳「開始分析前」），不是重跑辨識。辨識走快取、不打網路，
  // 「辨識又跑了一次」看的是確認框再出現一次。重新分析那條見 hydration 測試
  // 「開始失敗之後鎖會放掉：按重試照樣能再開始」。
  group('辨識錯誤卡：「重新辨識」重跑辨識、不走分析', () {
    testWidgets('初次辨識後存檔失敗：按「重新辨識」再辨識一次、確認框再出現，不跳「開始分析前」、一次都不送',
        (tester) async {
      final messages = [_her(_chars('好')), _her(_chars('嗯'))];
      final harness =
          await _pumpOcrScreen(tester, recognizedMessages: messages);
      await _recognize(tester);
      harness.repository.failUpdates = true;
      await _tapInDialog(tester, _analyzeLabel);
      _expectRecognitionErrorCard(
        tester,
        message: _recognitionFailedMessage,
        primaryActionLabel: '重新辨識',
      );

      await _tapRetryRecognition(tester);

      expect(find.byType(ScreenshotRecognitionDialog), findsOneWidget,
          reason: '辨識又跑了一次，確認框再出現');
      expect(find.byType(AnalysisErrorCard), findsNothing);
      expect(find.text('開始分析前'), findsNothing);
      expect(harness.recorder.streamCalls, 0);
    });

    testWidgets('從「繼續確認本次內容」匯入、存檔失敗：按「重新辨識」照上一批圖再辨識、確認框再出現，不跳「開始分析前」、一次都不送',
        (tester) async {
      final messages = [_her(_chars('好')), _her(_chars('嗯'))];
      final harness =
          await _pumpOcrScreen(tester, recognizedMessages: messages);
      await _recognize(tester);
      await _cancelThenResume(tester);
      harness.repository.failUpdates = true;
      await _tapInDialog(tester, _analyzeLabel);
      _expectRecognitionErrorCard(
        tester,
        message: _recognitionFailedMessage,
        primaryActionLabel: '重新辨識',
      );

      await _tapRetryRecognition(tester);

      expect(find.byType(ScreenshotRecognitionDialog), findsOneWidget,
          reason: '續看那條的圖已經收起來，照上一批圖再辨識，確認框再出現');
      expect(find.byType(AnalysisErrorCard), findsNothing);
      expect(find.text('開始分析前'), findsNothing);
      expect(harness.recorder.streamCalls, 0);
    });
  });
}
