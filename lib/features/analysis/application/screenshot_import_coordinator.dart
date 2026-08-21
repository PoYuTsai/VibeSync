/// 截圖匯入工作流協調器：OCR 辨識（快取失效／命中／回寫、免費
/// recognizeOnly 傳輸、135s 畫面圍籬）與匯入落地（另開新片段或整批
/// 取代本次片段）。畫面保留對話框、辨識進度／草稿等 view 狀態與
/// callback 接線；快取、計費隔離與 repo 寫入語意逐字沿用拆分前實作。
library;

import 'dart:async';
import 'dart:typed_data';

import '../../conversation/data/providers/conversation_providers.dart';
import '../../conversation/data/providers/conversation_write_controller.dart';
import '../../conversation/domain/entities/conversation.dart';
import '../../conversation/domain/entities/message.dart';
import '../../conversation/domain/entities/session_context.dart';
import '../../partner/presentation/providers/partner_providers.dart';
import '../data/services/analysis_auxiliary_client.dart';
import '../data/services/analysis_service.dart';
import '../data/services/ocr_recognition_cache_service.dart';
import '../domain/entities/analysis_models.dart';
import '../domain/services/analysis_fragment_policy.dart';
import '../domain/services/screenshot_recognition_helper.dart';
import 'analysis_persistence_coordinator.dart' show ProviderReader;

/// [ScreenshotImportCoordinator.commitImport] 的落地結果。
enum ScreenshotImportCommitKind {
  /// 來源片段已完成分析：已另開新片段，畫面應導向 [createdConversationId]。
  createdNewFragment,

  /// 已整批取代本次片段的草稿內容。
  replacedBatch,

  /// 目前對話已不存在，畫面應顯示錯誤。
  conversationMissing,
}

class ScreenshotImportCommit {
  final ScreenshotImportCommitKind kind;
  final String? createdConversationId;

  /// 依對話框編輯結果更新後的辨識資料（畫面渲染辨識預覽卡用）。
  final RecognizedConversation? updatedRecognized;

  const ScreenshotImportCommit._(
    this.kind, {
    this.createdConversationId,
    this.updatedRecognized,
  });
}

class ScreenshotImportCoordinator {
  ScreenshotImportCoordinator({
    required this.conversationId,
    required ProviderReader read,
    required void Function() invalidateConversationProvider,
  })  : _read = read,
        _invalidateConversationProvider = invalidateConversationProvider;

  final String conversationId;
  final ProviderReader _read;

  /// repo 寫入後讓畫面的 conversationProvider 失效重讀。
  final void Function() _invalidateConversationProvider;

  /// 綁定 partner 時的預期對方名（辨識警告與匯入命名共用）。
  String? expectedPartnerName(Conversation conversation) {
    final partnerId = conversation.partnerId?.trim();
    if (partnerId == null || partnerId.isEmpty) {
      return null;
    }
    final name =
        _read(partnerRepositoryProvider).getById(partnerId)?.name.trim();
    return name == null || name.isEmpty ? null : name;
  }

  /// 免費 OCR 辨識一批截圖。forceRefresh 先失效快取；快取命中不打網路、
  /// 以合成 telemetry 通知呼叫端；網路結果成功才回寫快取。快取、額度
  /// 隔離（recognizeOnly 不扣訂閱額度、不自動重送）與 135 秒畫面圍籬
  /// （含本地 payload 準備，須大於 HTTP 130s 圍籬）行為不變。
  Future<({AnalysisResult result, bool fromCache})> recognize({
    required List<Uint8List> images,
    required Conversation conversation,
    required SessionContext sessionContext,
    required bool forceRefresh,
    required int totalCompressedImageBytes,
    AnalysisProgressCallback? onProgress,
    AnalysisTelemetryCallback? onTelemetry,
  }) async {
    if (forceRefresh) {
      await OcrRecognitionCacheService.invalidate(images, conversationId);
    }
    final cachedRecognition = forceRefresh
        ? null
        : await OcrRecognitionCacheService.read(images, conversationId);
    if (cachedRecognition != null) {
      onTelemetry?.call(
        AnalysisTelemetry(
          requestType: 'recognize_only',
          imageCount: images.length,
          requestBodyBytes: 0,
          payloadPreparationDuration: Duration.zero,
          roundTripDuration: Duration.zero,
          edgeAiDuration: Duration.zero,
          totalCompressedImageBytes: totalCompressedImageBytes,
          cacheHit: true,
          recognizedClassification:
              cachedRecognition.recognizedConversation.classification,
          recognizedConfidence:
              cachedRecognition.recognizedConversation.confidence,
          recognizedSideConfidence:
              cachedRecognition.recognizedConversation.sideConfidence,
          recognizedMessageCount:
              cachedRecognition.recognizedConversation.messageCount,
          uncertainSideCount:
              cachedRecognition.recognizedConversation.uncertainSideCount,
        ),
      );
      return (
        result: AnalysisResult.fromJson(
          {
            'recognizedConversation':
                cachedRecognition.recognizedConversation.toJson(),
          },
        ),
        fromCache: true,
      );
    }

    // 使用 Future.any 來實現強制 timeout。
    final result = await Future.any([
      // 純識別模式：只識別截圖，不扣額度
      AnalysisAuxiliaryClient().recognizeScreenshots(
        images: images,
        sessionContext: sessionContext,
        knownContactName: ScreenshotRecognitionHelper.resolveKnownContactName(
          currentConversation: conversation,
          expectedPartnerName: expectedPartnerName(conversation),
        ),
        onProgress: onProgress,
        onTelemetry: onTelemetry,
      ),
      // Screen fence also includes local payload preparation, so it must
      // stay outside AnalysisAuxiliaryClient's 130-second HTTP fence.
      Future.delayed(kAnalyzeOcrScreenTimeout, () {
        throw TimeoutException('辨識超時 (135秒)');
      }),
    ]);

    if (result.recognizedConversation != null) {
      await OcrRecognitionCacheService.write(
        images: images,
        recognizedConversation: result.recognizedConversation!,
        conversationId: conversationId,
      );
    }
    return (result: result, fromCache: false);
  }

  /// 確認對話框拍板後的匯入落地。來源片段已完成分析時另開新片段（繼承
  /// partnerId，否則新對話會從 partner 詳頁消失）；否則整批取代本次片段
  /// 草稿。名稱／session context 合併規則不變。
  Future<ScreenshotImportCommit> commitImport({
    required List<RecognizedMessage> editedRecognizedMessages,
    required String newName,
    required MeetingContext? meeting,
    required AcquaintanceDuration? duration,
    required UserGoal? goal,
    required String? analysisContextNote,
    required RecognizedConversation recognized,
    required bool hasLoadedAnalysisResult,
  }) async {
    final repository = _read(conversationRepositoryProvider);
    final importedMessages = _buildImportedMessages(editedRecognizedMessages);
    final sourceConversation = repository.getConversation(conversationId);
    final mustStartNewFragment = sourceConversation != null &&
        AnalysisFragmentPolicy.mustCreateNewFragmentForImport(
          conversation: sourceConversation,
          hasLoadedAnalysisResult: hasLoadedAnalysisResult,
        );
    final sourcePartnerId = sourceConversation?.partnerId?.trim();
    final isPartnerBound =
        sourcePartnerId != null && sourcePartnerId.isNotEmpty;
    final boundExpectedPartnerName = sourceConversation == null
        ? null
        : expectedPartnerName(sourceConversation);
    final updatedRecognized = recognized.copyWith(
      contactName: isPartnerBound
          ? recognized.contactName
          : newName.isNotEmpty
              ? newName
              : recognized.contactName,
      messageCount: editedRecognizedMessages.length,
      messages: editedRecognizedMessages,
    );

    if (mustStartNewFragment) {
      final controller = _read(conversationWriteControllerProvider.notifier);
      // Inherit partnerId from the source conversation so the new "互動紀錄"
      // shows up under the same Partner detail page. Pre-A2 this path
      // created orphan conversations (partnerId=null) which silently
      // disappeared from `conversationsByPartnerProvider(partnerId)`.
      // (Bruce TF feedback 2026-04-28.)
      final createdConversation = await controller.create(
        name: isPartnerBound
            ? ScreenshotRecognitionHelper.resolvePartnerBoundNewFragmentName(
                currentConversation: sourceConversation,
                expectedPartnerName: boundExpectedPartnerName,
              )
            : ScreenshotRecognitionHelper.resolveImportedConversationName(
                enteredName: newName,
                recognizedName: recognized.contactName,
              ),
        messages: importedMessages,
        partnerId: sourceConversation.partnerId,
      );

      if (meeting != null && duration != null) {
        createdConversation.sessionContext = SessionContext(
          meetingContext: meeting,
          duration: duration,
          goal: goal ?? UserGoal.dateInvite,
          analysisContextNote: analysisContextNote,
        );
      }
      await controller.save(createdConversation);
      _invalidateConversationProvider();

      return ScreenshotImportCommit._(
        ScreenshotImportCommitKind.createdNewFragment,
        createdConversationId: createdConversation.id,
        updatedRecognized: updatedRecognized,
      );
    }

    final conv = repository.getConversation(conversationId);
    if (conv == null) {
      return const ScreenshotImportCommit._(
        ScreenshotImportCommitKind.conversationMissing,
      );
    }

    final partnerId = conv.partnerId?.trim();
    if (partnerId != null && partnerId.isNotEmpty) {
      conv.name =
          ScreenshotRecognitionHelper.resolvePartnerBoundConversationName(
        currentConversation: conv,
        expectedPartnerName: expectedPartnerName(conv),
      );
    } else if (newName.isNotEmpty &&
        ScreenshotRecognitionHelper.isPlaceholderConversationName(conv.name)) {
      conv.name = newName;
    }

    if (conv.sessionContext == null && meeting != null && duration != null) {
      conv.sessionContext = SessionContext(
        meetingContext: meeting,
        duration: duration,
        goal: goal ?? UserGoal.dateInvite,
        analysisContextNote: analysisContextNote,
      );
    } else if (conv.sessionContext != null &&
        analysisContextNote != null &&
        analysisContextNote.trim().isNotEmpty) {
      final existing = conv.sessionContext!;
      conv.sessionContext = SessionContext(
        meetingContext: existing.meetingContext,
        duration: existing.duration,
        goal: existing.goal,
        userStyle: existing.userStyle,
        userInterests: existing.userInterests,
        targetDescription: existing.targetDescription,
        analysisContextNote: analysisContextNote.trim(),
      );
    }

    // 一次 OCR 選取（1–3 張）就是完整的一個待分析片段。重新選圖時
    // 整批取代，不把不連貫的新內容接成越來越長的逐字稿。
    AnalysisFragmentPolicy.replaceDraftBatch(
      conversation: conv,
      messages: importedMessages,
    );
    await _read(conversationWriteControllerProvider.notifier).save(conv);
    _invalidateConversationProvider();

    return ScreenshotImportCommit._(
      ScreenshotImportCommitKind.replacedBatch,
      updatedRecognized: updatedRecognized,
    );
  }

  List<Message> _buildImportedMessages(List<RecognizedMessage> recognized) {
    final baseTimestamp = DateTime.now();
    return List.generate(recognized.length, (index) {
      final message = recognized[index];
      return Message(
        id: '${baseTimestamp.microsecondsSinceEpoch}_$index',
        content: message.content,
        isFromMe: message.isFromMe,
        timestamp: baseTimestamp.add(Duration(milliseconds: index)),
        quotedReplyPreview: message.quotedReplyPreview,
        quotedReplyPreviewIsFromMe: message.quotedReplyPreviewIsFromMe,
      );
    });
  }
}
