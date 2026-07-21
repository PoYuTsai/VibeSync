import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/core/constants/app_constants.dart';
import 'package:vibesync/features/coaching_memory/data/providers/coaching_outcome_providers.dart';
import '../../../helpers/memory_coaching_outcome_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/core/theme/app_colors.dart';
import 'package:vibesync/features/analysis/data/services/ocr_recognition_cache_service.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';
import 'package:vibesync/features/analysis/presentation/screens/analysis_screen.dart';
import 'package:vibesync/features/analysis/presentation/widgets/screenshot_recognition_dialog.dart';
import 'package:vibesync/features/coach_chat/data/providers/coach_chat_providers.dart';
import 'package:vibesync/features/coach_chat/domain/entities/coach_chat_result.dart';
import 'package:vibesync/features/coach_chat/domain/entities/unified_coach_result.dart';
import 'package:vibesync/features/coach_chat/domain/repositories/coach_chat_repository.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_write_controller.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_repository.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/conversation/presentation/widgets/message_bubble.dart';
import 'package:vibesync/features/partner/data/repositories/partner_repository.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/shared/widgets/ai_data_sharing_consent.dart';
import 'package:vibesync/shared/widgets/image_picker_widget.dart';

import '../conversation/_fakes/recording_conversation_write_controller.dart';

Future<void> _pumpAnalysisScreen(
  WidgetTester tester, {
  Conversation? conversation,
  List<Message>? messages,
  ConversationWriteController? writeController,
  _StubConversationRepository? repository,
  PartnerRepository? partnerRepository,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final testConversation = conversation ??
      Conversation(
        id: 'continue-input-test',
        name: '小雲',
        messages: messages ??
            [
              Message(
                id: 'm1',
                content: '昨天那家甜點不錯耶',
                isFromMe: false,
                timestamp: DateTime(2026, 5, 4),
              ),
            ],
        createdAt: DateTime(2026, 5, 4),
        updatedAt: DateTime(2026, 5, 4),
      );
  final resolvedRepository =
      repository ?? _StubConversationRepository(testConversation);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coachingOutcomeRepositoryProvider
            .overrideWithValue(MemoryCoachingOutcomeRepository()),
        conversationRepositoryProvider.overrideWithValue(resolvedRepository),
        conversationProvider('continue-input-test')
            .overrideWithValue(testConversation),
        coachChatRepositoryProvider
            .overrideWithValue(_StubCoachChatRepository()),
        if (partnerRepository != null)
          partnerRepositoryProvider.overrideWithValue(partnerRepository),
        if (writeController != null)
          conversationWriteControllerProvider
              .overrideWith(() => writeController),
      ],
      child: const MaterialApp(
        home: AnalysisScreen(conversationId: 'continue-input-test'),
      ),
    ),
  );
  await tester.pump();
  await _dismissEditHintIfVisible(tester);
}

class _StubConversationRepository extends ConversationRepository {
  _StubConversationRepository(this._conversation);

  Conversation _conversation;

  void replace(Conversation conversation) {
    _conversation = conversation;
  }

  @override
  Conversation? getConversation(String id) {
    return id == _conversation.id ? _conversation : null;
  }

  @override
  Future<void> updateConversation(Conversation conversation) async {
    _conversation = conversation;
  }
}

class _StubPartnerRepository implements PartnerRepository {
  _StubPartnerRepository(this.partner);

  final Partner partner;

  @override
  Partner? getById(String id) => id == partner.id ? partner : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubCoachChatRepository implements CoachChatRepository {
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
}

Map<String, dynamic> _analysisSnapshotJson({int score = 65}) {
  return <String, dynamic>{
    'enthusiasm': {'score': score},
    'strategy': '保持輕鬆節奏',
    'gameStage': {
      'current': 'opening',
      'status': 'normal',
      'nextStep': '接著回應她的甜點話題',
    },
    'psychology': {
      'subtext': '願意延續話題',
      'qualificationSignal': true,
    },
    'topicDepth': {
      'current': 'small_talk',
      'suggestion': '先接住情緒，再自然延伸',
    },
    'replies': {
      'extend': '那家真的不錯，下次可以再去試別的口味',
      'resonate': '我也覺得那個甜點有驚喜',
      'tease': '你是不是已經偷偷列甜點清單了',
      'humor': '看來甜點雷達有開到最大',
      'coldRead': '你應該是會為了甜點特地繞路的人',
    },
    'finalRecommendation': {
      'pick': 'extend',
      'content': '那家真的不錯，下次可以再去試別的口味',
      'reason': '接住她的回饋並留下延續空間',
      'psychology': '保持輕鬆投入感',
    },
    'reminder': '用自己的語氣講就好',
  };
}

Future<void> _dismissEditHintIfVisible(WidgetTester tester) async {
  await tester.pump();
  final dismissButton = find.text('知道了');
  if (dismissButton.evaluate().isEmpty) {
    return;
  }
  await tester.tap(dismissButton);
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AnalysisScreen continue input', () {
    testWidgets('pending fragment no longer exposes the manual append composer',
        (tester) async {
      await _pumpAnalysisScreen(tester);

      expect(find.text('開始分析'), findsOneWidget);
      expect(find.text('貼上或輸入新的一則訊息…'), findsNothing);
      expect(find.text('建立本次片段'), findsNothing);
      expect(find.text('這句是她說'), findsNothing);
      expect(find.text('這句是我說'), findsNothing);
    });

    testWidgets('pending fragment explains that a new OCR batch replaces it',
        (tester) async {
      await _pumpAnalysisScreen(tester);

      expect(find.byType(ImagePickerWidget), findsOneWidget);
      expect(find.textContaining('重新選擇 1–3 張截圖會整批取代'),
          findsOneWidget);
      expect(find.textContaining('不會往下追加'), findsOneWidget);
    });

    testWidgets(
        'stale OCR confirmation creates a new Partner fragment and preserves completed source',
        (tester) async {
      final imageBytes = Uint8List.fromList([1, 2, 3, 4]);
      final tempDir = (await tester.runAsync(() async {
        final directory = await Directory.systemTemp.createTemp(
          'vibesync_ocr_stale_confirm_',
        );
        Hive.init(directory.path);
        await Hive.openBox<dynamic>(AppConstants.settingsBox);
        await OcrRecognitionCacheService.write(
          images: [imageBytes],
          conversationId: 'continue-input-test',
          recognizedConversation: const RecognizedConversation(
            contactName: 'Bruce',
            messageCount: 2,
            summary: '新批次',
            classification: 'valid_chat',
            importPolicy: 'allow',
            confidence: 'high',
            sideConfidence: 'high',
            messages: [
              RecognizedMessage(
                side: 'left',
                isFromMe: false,
                content: '新一',
              ),
              RecognizedMessage(
                side: 'right',
                isFromMe: true,
                content: '新二',
              ),
            ],
          ),
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

      final draft = Conversation(
        id: 'continue-input-test',
        name: '春季活動那次',
        partnerId: 'partner-bruce',
        messages: [
          Message(
            id: 'old',
            content: '完成前的舊內容',
            isFromMe: false,
            timestamp: DateTime(2026, 7, 16),
          ),
        ],
        createdAt: DateTime(2026, 7, 16),
        updatedAt: DateTime(2026, 7, 16),
      );
      final repository = _StubConversationRepository(draft);
      final writer = RecordingConversationWriteController();
      final partnerRepository = _StubPartnerRepository(
        Partner(
          id: 'partner-bruce',
          name: 'Bruce',
          createdAt: DateTime(2026, 7, 16),
          updatedAt: DateTime(2026, 7, 16),
        ),
      );

      await _pumpAnalysisScreen(
        tester,
        conversation: draft,
        repository: repository,
        partnerRepository: partnerRepository,
        writeController: writer,
      );

      final picker = tester.widget<ImagePickerWidget>(
        find.byType(ImagePickerWidget),
      );
      picker.onImagesChanged([imageBytes]);
      await tester.pump();
      final recognizeButton = find.text('辨識並取代本次內容（1 張）');
      await tester.ensureVisible(recognizeButton);
      await tester.tap(recognizeButton);
      await tester.pumpAndSettle();
      expect(find.byType(ScreenshotRecognitionDialog), findsOneWidget);

      final completedSource = Conversation(
        id: 'continue-input-test',
        name: '春季活動那次',
        partnerId: 'partner-bruce',
        messages: [
          Message(
            id: 'old',
            content: '完成前的舊內容',
            isFromMe: false,
            timestamp: DateTime(2026, 7, 16),
          ),
        ],
        createdAt: DateTime(2026, 7, 16),
        updatedAt: DateTime(2026, 7, 16),
        lastAnalyzedMessageCount: 1,
        lastAnalysisSnapshotJson: jsonEncode(_analysisSnapshotJson()),
        lastEnthusiasmScore: 65,
      );
      repository.replace(completedSource);

      final confirmButton = find.text('確認本次內容');
      await tester.ensureVisible(confirmButton);
      await tester.tap(confirmButton);
      await tester.pumpAndSettle();

      expect(writer.createCalled, isTrue);
      expect(writer.capturedPartnerId, 'partner-bruce');
      expect(writer.capturedName, 'Bruce');
      expect(writer.capturedMessageCount, 2);
      expect(completedSource.messages, hasLength(1));
      expect(completedSource.messages.single.id, 'old');
      expect(completedSource.messages.single.content, '完成前的舊內容');
      expect(completedSource.lastAnalyzedMessageCount, 1);
      expect(completedSource.lastAnalysisSnapshotJson, isNotEmpty);
    });

    testWidgets('edit dialog keeps the text field readable on a dark surface',
        (tester) async {
      await _pumpAnalysisScreen(
        tester,
        messages: [
          Message(
            id: 'm1',
            content: 'Readable edit target',
            isFromMe: false,
            timestamp: DateTime(2026, 5, 4),
          ),
        ],
      );

      final bubble = find.text('Readable edit target').first;
      await tester.ensureVisible(bubble);
      await tester.longPress(bubble);
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('編輯文字'));
      await tester.pump(const Duration(milliseconds: 300));

      final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      expect(dialog.backgroundColor, AppColors.brandSurface2);
      expect(dialog.surfaceTintColor, Colors.transparent);

      final fieldFinder = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      final field = tester.widget<TextField>(fieldFinder);
      expect(field.cursorColor, AppColors.ctaStart);
      expect(field.style?.color, AppColors.onBackgroundPrimary);
      expect(field.decoration?.filled, isTrue);
      expect(field.decoration?.fillColor,
          AppColors.brandInk.withValues(alpha: 0.4));
    });

    testWidgets('completed analysis fragment is read-only', (tester) async {
      final conversation = Conversation(
        id: 'continue-input-test',
        name: '小雲',
        messages: [
          Message(
            id: 'm1',
            content: 'Original analyzed text',
            isFromMe: false,
            timestamp: DateTime(2026, 5, 4),
          ),
        ],
        createdAt: DateTime(2026, 5, 4),
        updatedAt: DateTime(2026, 5, 4),
        lastAnalyzedMessageCount: 1,
        lastAnalysisSnapshotJson: jsonEncode({
          'enthusiasm': {'score': 65},
        }),
      );

      await _pumpAnalysisScreen(
        tester,
        conversation: conversation,
        writeController: RecordingConversationWriteController(),
      );

      final bubble = tester.widget<MessageBubble>(
        find.byType(MessageBubble).first,
      );
      expect(bubble.onEdit, isNull);
      expect(bubble.onSwapSide, isNull);
      expect(bubble.onDelete, isNull);
      expect(find.textContaining('內容唯讀'), findsOneWidget);
    });

    testWidgets(
        'completed fragment stays closed when its old snapshot is corrupt',
        (tester) async {
      final conversation = Conversation(
        id: 'continue-input-test',
        name: '小雲',
        messages: [
          Message(
            id: 'm1',
            content: '已經分析過的內容',
            isFromMe: false,
            timestamp: DateTime(2026, 5, 4),
          ),
        ],
        createdAt: DateTime(2026, 5, 4),
        updatedAt: DateTime(2026, 5, 4),
        lastAnalyzedMessageCount: 1,
        lastAnalysisSnapshotJson: 'corrupt-snapshot',
      );

      await _pumpAnalysisScreen(tester, conversation: conversation);

      final bubble = tester.widget<MessageBubble>(
        find.byType(MessageBubble).first,
      );
      expect(bubble.onEdit, isNull);
      expect(bubble.onSwapSide, isNull);
      expect(bubble.onDelete, isNull);
      expect(find.byType(ImagePickerWidget), findsNothing);
      expect(find.text('分析新片段'), findsOneWidget);
      expect(find.textContaining('內容唯讀'), findsOneWidget);
    });

    testWidgets('editing any bubble shows an immediate reanalysis snackbar',
        (tester) async {
      await _pumpAnalysisScreen(
        tester,
        messages: [
          Message(
            id: 'm1',
            content: 'Draft text before analysis',
            isFromMe: false,
            timestamp: DateTime(2026, 5, 4),
          ),
        ],
        writeController: RecordingConversationWriteController(),
      );

      final bubble = find.text('Draft text before analysis').first;
      await tester.ensureVisible(bubble);
      await tester.longPress(bubble);
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('編輯文字'));
      await tester.pump(const Duration(milliseconds: 300));

      final fieldFinder = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fieldFinder, 'Edited draft text');
      await tester.tap(find.widgetWithText(TextButton, '儲存'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('已儲存，點重新分析更新結果。'), findsOneWidget);
      expect(find.text('重新分析'), findsWidgets);
    });

    testWidgets(
        'first analysis is not mislabeled as pending appended content',
        (tester) async {
      await _pumpAnalysisScreen(tester);

      expect(find.text('分析新增內容'), findsNothing);
      expect(find.textContaining('有 1 則新訊息'), findsNothing);
    });

    testWidgets('empty screenshot-start conversation keeps upload flow clean',
        (tester) async {
      await _pumpAnalysisScreen(tester, messages: const []);

      expect(find.text('還沒有訊息'), findsOneWidget);
      expect(find.text('新的分析片段'), findsOneWidget);
      expect(
        find.text('先加入這次想給 AI 解析的聊天；不會接回舊紀錄。'),
        findsOneWidget,
      );
      expect(find.textContaining('內容唯讀'), findsNothing);
      expect(find.text('先上傳 1–3 張聊天截圖，確認文字後作為本次片段。'), findsOneWidget);
      expect(find.byType(ImagePickerWidget), findsOneWidget);
      expect(find.text('建立本次片段'), findsNothing);
      expect(find.text('貼上或輸入新的一則訊息…'), findsNothing);
      expect(find.text('這句是她說'), findsNothing);
      expect(find.text('這句是我說'), findsNothing);
      expect(
        find.text('開始分析'),
        findsNothing,
      );
      expect(find.text('這次分析設定（可不改）'), findsOneWidget);
      expect(find.text('交友軟體・剛認識・邀約見面'), findsOneWidget);
      expect(find.text('不確定可以先跳過；AI 會用預設情境分析。'), findsOneWidget);
      expect(find.text('認識情境'), findsNothing);
      expect(find.text('補充背景（選填）'), findsNothing);

      await tester.tap(find.text('這次分析設定（可不改）'));
      await tester.pump();

      expect(find.text('已是伴侶'), findsOneWidget);
      expect(find.text('目前目標'), findsOneWidget);
      expect(find.text('補充背景（選填）'), findsOneWidget);
      expect(find.text('沒有可以留空'), findsOneWidget);
      expect(find.text('其他'), findsNothing);
      expect(find.textContaining('只影響本次片段的分析'), findsAtLeastNWidgets(1));
      final noteField = tester.widget<TextField>(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.hintText == '沒有可以留空',
        ),
      );
      expect(noteField.maxLength, 300);
      expect(noteField.textInputAction, TextInputAction.done);
    });

    testWidgets(
        'completed analysis starts a new independent fragment instead of reopening input',
        (tester) async {
      final conversation = Conversation(
        id: 'continue-input-test',
        name: '小雲',
        messages: [
          Message(
            id: 'm1',
            content: '昨天那家甜點不錯耶',
            isFromMe: false,
            timestamp: DateTime(2026, 5, 4),
          ),
        ],
        createdAt: DateTime(2026, 5, 4),
        updatedAt: DateTime(2026, 5, 4),
        lastAnalyzedMessageCount: 1,
        lastAnalysisSnapshotJson: jsonEncode(_analysisSnapshotJson()),
      );

      await _pumpAnalysisScreen(tester, conversation: conversation);

      expect(find.text('補聊天紀錄'), findsNothing);
      expect(find.byType(ImagePickerWidget), findsNothing);
      final newFragmentButton = find.text('分析新片段');
      expect(newFragmentButton, findsOneWidget);
      expect(find.textContaining('舊片段不會接進來'), findsOneWidget);

      await tester.tap(newFragmentButton);
      await tester.pumpAndSettle();

      expect(find.text('新增對話'), findsOneWidget);
      expect(find.textContaining('建立一段新的互動紀錄'), findsOneWidget);
    });

    testWidgets(
        'independent fragment is not truncated into a five-message preview',
        (tester) async {
      await _pumpAnalysisScreen(
        tester,
        messages: List.generate(
          6,
          (index) => Message(
            id: 'm$index',
            content: '訊息 ${index + 1}',
            isFromMe: index.isOdd,
            timestamp: DateTime(2026, 5, 4, 12, index),
          ),
        ),
      );

      expect(find.text('訊息 1'), findsOneWidget);
      expect(find.text('訊息 2'), findsOneWidget);
      expect(find.text('訊息 6'), findsOneWidget);
      expect(find.textContaining('展開全部'), findsNothing);
    });

    testWidgets('legacy appended tail cannot reopen a completed fragment',
        (tester) async {
      final conversation = Conversation(
        id: 'continue-input-test',
        name: '小雲',
        messages: List.generate(
          4,
          (index) => Message(
            id: 'm$index',
            content: '片段 ${index + 1}',
            isFromMe: index.isOdd,
            timestamp: DateTime(2026, 5, 4, 12, index),
          ),
        ),
        createdAt: DateTime(2026, 5, 4),
        updatedAt: DateTime(2026, 5, 4),
        lastAnalyzedMessageCount: 2,
        lastAnalysisSnapshotJson: jsonEncode(_analysisSnapshotJson()),
      );

      await _pumpAnalysisScreen(tester, conversation: conversation);

      expect(find.text('本次分析片段'), findsOneWidget);
      expect(find.text('片段 1'), findsOneWidget);
      expect(find.text('片段 2'), findsOneWidget);
      expect(find.text('片段 3'), findsNothing);
      expect(find.text('片段 4'), findsNothing);
      expect(find.text('分析新增內容'), findsNothing);
      expect(find.text('分析新片段'), findsOneWidget);
    });
  });
}
