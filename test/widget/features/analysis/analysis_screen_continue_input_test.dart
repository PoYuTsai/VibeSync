import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/coaching_memory/data/providers/coaching_outcome_providers.dart';
import '../../../helpers/memory_coaching_outcome_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/core/theme/app_colors.dart';
import 'package:vibesync/features/analysis/presentation/screens/analysis_screen.dart';
import 'package:vibesync/features/coach_chat/data/providers/coach_chat_providers.dart';
import 'package:vibesync/features/coach_chat/domain/entities/coach_chat_result.dart';
import 'package:vibesync/features/coach_chat/domain/repositories/coach_chat_repository.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_write_controller.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_repository.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/conversation/presentation/widgets/message_bubble.dart';
import 'package:vibesync/shared/widgets/image_picker_widget.dart';

import '../conversation/_fakes/recording_conversation_write_controller.dart';

Future<void> _pumpAnalysisScreen(
  WidgetTester tester, {
  Conversation? conversation,
  List<Message>? messages,
  ConversationWriteController? writeController,
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
  final repository = _StubConversationRepository(testConversation);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coachingOutcomeRepositoryProvider
            .overrideWithValue(MemoryCoachingOutcomeRepository()),
        conversationRepositoryProvider.overrideWithValue(repository),
        conversationProvider('continue-input-test')
            .overrideWithValue(testConversation),
        coachChatRepositoryProvider
            .overrideWithValue(_StubCoachChatRepository()),
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

  @override
  Conversation? getConversation(String id) {
    return id == _conversation.id ? _conversation : null;
  }

  @override
  Future<void> updateConversation(Conversation conversation) async {
    _conversation = conversation;
  }
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
    testWidgets('explains that text must be entered before choosing speaker',
        (tester) async {
      await _pumpAnalysisScreen(tester);

      expect(find.text('貼上或輸入新的一則訊息…'), findsOneWidget);
      expect(find.text('建立本次片段'), findsOneWidget);
      expect(find.text('輸入完先收起鍵盤，再選這句是她說，還是我說。'), findsOneWidget);
      expect(find.text('這句是她說'), findsOneWidget);
      expect(find.text('這句是我說'), findsOneWidget);
    });

    testWidgets('manual input can dismiss keyboard before choosing speaker',
        (tester) async {
      await _pumpAnalysisScreen(tester);

      final textFieldFinder = find.byType(TextField).last;
      final textField = tester.widget<TextField>(textFieldFinder);
      expect(textField.textInputAction, TextInputAction.done);
      expect(find.byTooltip('收起鍵盤'), findsOneWidget);

      await tester.tap(textFieldFinder);
      await tester.enterText(textFieldFinder, '要幫你帶什麼嗎？');
      expect(tester.testTextInput.isVisible, isTrue);

      await tester.tap(find.byTooltip('收起鍵盤'));
      await tester.pump();

      expect(tester.testTextInput.isVisible, isFalse);
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
        'shows a reminder when tapping her-message button with empty input',
        (tester) async {
      await _pumpAnalysisScreen(tester);

      final herButton = find.text('這句是她說');
      await tester.ensureVisible(herButton);
      await tester.tap(herButton);
      await tester.pump();

      expect(
        find.text('先貼上或輸入對方的新回覆，再點「這句是她說」。'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
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
      expect(find.text('先上傳聊天截圖，確認文字後再加入本次片段。'), findsOneWidget);
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

    testWidgets('pending fragment hides messages from the completed analysis',
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

      expect(find.text('待分析的新片段'), findsOneWidget);
      expect(find.text('片段 1'), findsNothing);
      expect(find.text('片段 2'), findsNothing);
      expect(find.text('片段 3'), findsOneWidget);
      expect(find.text('片段 4'), findsOneWidget);
    });
  });
}
