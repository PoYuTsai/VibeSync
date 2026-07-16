import '../../../conversation/domain/entities/conversation.dart';
import '../entities/analysis_models.dart';

enum ScreenshotRecognitionGuidanceTone {
  stable,
  review,
  caution,
  reject,
}

class ScreenshotRecognitionGuidance {
  final String title;
  final String body;
  final ScreenshotRecognitionGuidanceTone tone;

  const ScreenshotRecognitionGuidance({
    required this.title,
    required this.body,
    required this.tone,
  });
}

class ScreenshotRecognitionHelper {
  static const String untitledConversationName = '新對話';

  static bool _looksLikeMixedThreadWarning(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }

    return normalized.contains('不同聯絡人') ||
        normalized.contains('不同對話') ||
        normalized.contains('不同聊天') ||
        normalized.contains('不同 chat') ||
        normalized.contains('混入') ||
        normalized.contains('混合') ||
        normalized.contains('different contact') ||
        normalized.contains('different thread') ||
        normalized.contains('multiple threads') ||
        normalized.contains('mixed thread');
  }

  static bool isPlaceholderConversationName(String name) {
    final normalized = name.trim();
    return normalized.isEmpty ||
        normalized == untitledConversationName ||
        normalized == '新的對話';
  }

  static String? resolveKnownContactName({
    required Conversation currentConversation,
    String? expectedPartnerName,
  }) {
    final normalizedExpectedPartnerName = expectedPartnerName?.trim();
    if (normalizedExpectedPartnerName != null &&
        normalizedExpectedPartnerName.isNotEmpty) {
      return normalizedExpectedPartnerName;
    }

    final partnerId = currentConversation.partnerId?.trim();
    if (partnerId != null && partnerId.isNotEmpty) {
      return null;
    }

    final currentName = currentConversation.name.trim();
    return isPlaceholderConversationName(currentName) ? null : currentName;
  }

  static bool hasContactNameMismatch({
    required RecognizedConversation recognized,
    required Conversation currentConversation,
    String? expectedPartnerName,
  }) {
    final recognizedName = recognized.contactName?.trim();
    final normalizedExpectedPartnerName = expectedPartnerName?.trim();
    final currentName = normalizedExpectedPartnerName != null &&
            normalizedExpectedPartnerName.isNotEmpty
        ? normalizedExpectedPartnerName
        : currentConversation.name.trim();
    return !isPlaceholderConversationName(currentName) &&
        recognizedName != null &&
        recognizedName.isNotEmpty &&
        recognizedName != currentName;
  }

  static bool isPartnerBoundPlaceholderConversation(
    Conversation currentConversation,
  ) {
    final partnerId = currentConversation.partnerId?.trim();
    return partnerId != null &&
        partnerId.isNotEmpty &&
        isPlaceholderConversationName(currentConversation.name);
  }

  static bool requiresSamePartnerConfirmation({
    required RecognizedConversation recognized,
    required Conversation currentConversation,
    String? expectedPartnerName,
  }) {
    final normalizedExpectedPartnerName = expectedPartnerName?.trim();
    final cannotVerifyBoundPlaceholder =
        isPartnerBoundPlaceholderConversation(currentConversation) &&
            (normalizedExpectedPartnerName == null ||
                normalizedExpectedPartnerName.isEmpty);
    return hasContactNameMismatch(
          recognized: recognized,
          currentConversation: currentConversation,
          expectedPartnerName: expectedPartnerName,
        ) ||
        cannotVerifyBoundPlaceholder ||
        _looksLikeMixedThreadWarning(recognized.warning ?? '');
  }

  static String? fallbackWarningForClassification(String classification) {
    switch (classification) {
      case 'group_chat':
        return '這張圖看起來像群組聊天，目前只支援一對一聊天截圖。';
      case 'gallery_album':
        return '這張圖看起來像相簿或選圖畫面，不是聊天視窗。';
      case 'call_log_screen':
        return '這張圖比較像通話紀錄頁，不是可直接加入的聊天畫面。';
      case 'system_ui':
        return '這張圖看起來像系統畫面或通知頁，不是聊天視窗。';
      case 'sensitive_content':
        return '這張圖包含不適合辨識的敏感內容，請改傳聊天截圖。';
      case 'social_feed':
        return '這張圖看起來比較像社群貼文或留言串，不像雙人聊天視窗。';
      case 'unsupported':
        return '這張圖目前不像可分析的聊天截圖，請改傳完整聊天視窗後再試。';
      default:
        return null;
    }
  }

  static String? buildWarning({
    required RecognizedConversation recognized,
    required Conversation currentConversation,
    String? expectedPartnerName,
  }) {
    final warnings = <String>[];
    final serverWarning = recognized.warning?.trim();
    if (serverWarning != null && serverWarning.isNotEmpty) {
      warnings.add(serverWarning);
    }

    final recognizedName = recognized.contactName?.trim();
    if (hasContactNameMismatch(
      recognized: recognized,
      currentConversation: currentConversation,
      expectedPartnerName: expectedPartnerName,
    )) {
      final expectedName = expectedPartnerName?.trim();
      warnings.add(
        '這張截圖辨識到「$recognizedName」，和目前對象${expectedName != null && expectedName.isNotEmpty ? '「$expectedName」' : ''}不同。若是另一人，請取消並回到正確對象；只有確認是目前這位對象時才能繼續。',
      );
    }

    final normalizedExpectedPartnerName = expectedPartnerName?.trim();
    if (isPartnerBoundPlaceholderConversation(currentConversation) &&
        (normalizedExpectedPartnerName == null ||
            normalizedExpectedPartnerName.isEmpty)) {
      warnings.add('這段新對話已歸在目前對象名下。請確認內容確實都是同一位對象。');
    }

    if (recognized.importPolicy == 'confirm' && warnings.isEmpty) {
      warnings.add('這張圖還不太確定，請先看一下內容有沒有抓對。');
    }

    if (serverWarning != null && _looksLikeMixedThreadWarning(serverWarning)) {
      warnings.add(
        '請確認這批截圖都是目前這位對象；若混到另一人，請取消並回到正確對象。',
      );
    }

    final sideWarning = sideConfidenceWarning(recognized);
    if (sideWarning != null) {
      warnings.add(sideWarning);
    }

    if (recognized.importPolicy == 'reject' && warnings.isEmpty) {
      final fallback =
          fallbackWarningForClassification(recognized.classification);
      if (fallback != null) {
        warnings.add(fallback);
      }
    }

    if (warnings.isEmpty) {
      return null;
    }

    return warnings.join('\n');
  }

  static String resolveImportedConversationName({
    required String? enteredName,
    required String? recognizedName,
  }) {
    final normalizedEntered = enteredName?.trim();
    if (normalizedEntered != null && normalizedEntered.isNotEmpty) {
      return normalizedEntered;
    }

    final normalizedRecognized = recognizedName?.trim();
    if (normalizedRecognized != null && normalizedRecognized.isNotEmpty) {
      return normalizedRecognized;
    }

    return untitledConversationName;
  }

  /// A fragment already bound to a Partner must never take its display name
  /// from OCR. OCR contact labels are evidence to verify, not identity data.
  static String resolvePartnerBoundConversationName({
    required Conversation currentConversation,
    String? expectedPartnerName,
  }) {
    final currentName = currentConversation.name.trim();
    if (!isPlaceholderConversationName(currentName)) {
      return currentName;
    }

    final normalizedExpectedPartnerName = expectedPartnerName?.trim();
    if (normalizedExpectedPartnerName != null &&
        normalizedExpectedPartnerName.isNotEmpty) {
      return normalizedExpectedPartnerName;
    }

    return currentName.isEmpty ? untitledConversationName : currentName;
  }

  /// A newly created fragment should start from the canonical Partner name
  /// when available, without changing the title of an older fragment.
  static String resolvePartnerBoundNewFragmentName({
    required Conversation currentConversation,
    String? expectedPartnerName,
  }) {
    final normalizedExpectedPartnerName = expectedPartnerName?.trim();
    if (normalizedExpectedPartnerName != null &&
        normalizedExpectedPartnerName.isNotEmpty) {
      return normalizedExpectedPartnerName;
    }

    final currentName = currentConversation.name.trim();
    return currentName.isEmpty ? untitledConversationName : currentName;
  }

  static String classificationLabel(String classification) {
    switch (classification) {
      case 'low_confidence':
        return '需要確認';
      case 'social_feed':
        return '社群畫面';
      case 'group_chat':
        return '群組聊天';
      case 'gallery_album':
        return '相簿畫面';
      case 'call_log_screen':
        return '通話紀錄';
      case 'system_ui':
        return '系統畫面';
      case 'sensitive_content':
        return '敏感內容';
      case 'unsupported':
        return '不適合';
      case 'valid_chat':
      default:
        return '聊天畫面';
    }
  }

  static String confidenceLabel(String confidence) {
    switch (confidence) {
      case 'low':
        return '內容需確認';
      case 'medium':
        return '內容大致可用';
      case 'high':
      default:
        return '內容清楚';
    }
  }

  static String sideConfidenceLabel(String confidence) {
    switch (confidence) {
      case 'low':
        return '左右需確認';
      case 'medium':
        return '左右大致可用';
      case 'high':
      default:
        return '左右清楚';
    }
  }

  static bool hasQuotedReplyPreview(RecognizedConversation recognized) {
    return (recognized.messages ?? const <RecognizedMessage>[]).any(
      (message) => message.quotedReplyPreview?.trim().isNotEmpty ?? false,
    );
  }

  static String? sideConfidenceWarning(RecognizedConversation recognized) {
    if (recognized.uncertainSideCount > 0) {
      return '有 ${recognized.uncertainSideCount} 則訊息的左右還不夠清楚，請再看一下「我說 / 她說」有沒有判對。';
    }

    if (hasQuotedReplyPreview(recognized)) {
      return '這批訊息含回覆引用框，暗色或長截圖時 AI 較容易把引用卡裡的人名誤當成發話方向。請特別確認「我說 / 她說」。';
    }

    if (recognized.sideConfidence == 'medium') {
      return '這批訊息的左右有部分是系統幫你補判的，建議快速看一下。';
    }

    if (recognized.sideConfidence == 'low') {
      return '這批訊息的左右還不夠穩，建議先檢查後再確認。';
    }

    return null;
  }

  static ScreenshotRecognitionGuidance guidance(
    RecognizedConversation recognized,
  ) {
    final warning = recognized.warning?.trim() ?? '';
    final looksLikeCallRecord =
        warning.contains('通話紀錄') || warning.contains('未接來電');
    final looksLikeMixedThread = _looksLikeMixedThreadWarning(warning);

    if (recognized.importPolicy == 'reject') {
      switch (recognized.classification) {
        case 'social_feed':
          return const ScreenshotRecognitionGuidance(
            title: '請改傳聊天截圖',
            body: '這看起來比較像社群貼文或留言串，建議改截雙人聊天畫面再試。',
            tone: ScreenshotRecognitionGuidanceTone.reject,
          );
        case 'group_chat':
          return const ScreenshotRecognitionGuidance(
            title: '請改傳一對一聊天',
            body: '這看起來像群組聊天，目前產品只支援一對一對話分析，建議改截和單一對象的聊天視窗。',
            tone: ScreenshotRecognitionGuidanceTone.reject,
          );
        case 'gallery_album':
          return const ScreenshotRecognitionGuidance(
            title: '請回到聊天視窗再截圖',
            body: '這看起來像相簿或選圖畫面，建議回到聊天 App 內重新截圖。',
            tone: ScreenshotRecognitionGuidanceTone.reject,
          );
        case 'call_log_screen':
          return const ScreenshotRecognitionGuidance(
            title: '請回到聊天畫面再截',
            body: '這看起來像手機的通話紀錄頁。若你想加入聊天對話裡的來電事件，請保留聊天標題列與上下文後再重截。',
            tone: ScreenshotRecognitionGuidanceTone.reject,
          );
        case 'system_ui':
          return const ScreenshotRecognitionGuidance(
            title: '請改傳聊天視窗',
            body: '這看起來像系統畫面或通知頁，不是可分析的聊天截圖。請改傳聊天視窗。',
            tone: ScreenshotRecognitionGuidanceTone.reject,
          );
        case 'sensitive_content':
          return const ScreenshotRecognitionGuidance(
            title: '請改傳純聊天截圖',
            body: '這張圖包含不適合辨識的敏感內容，請改傳純聊天截圖。',
            tone: ScreenshotRecognitionGuidanceTone.reject,
          );
      }
      return const ScreenshotRecognitionGuidance(
        title: '建議換一張更清楚的圖',
        body: '這張圖目前不適合分析，建議重截更清楚的聊天畫面，保留完整對話泡泡與標題列。',
        tone: ScreenshotRecognitionGuidanceTone.reject,
      );
    }

    if (looksLikeCallRecord) {
      return const ScreenshotRecognitionGuidance(
        title: '先確認本次內容',
        body: '這張圖像是聊天視窗裡的未接來電或通話紀錄。若確認是同一段對話，先檢查方向與順序。',
        tone: ScreenshotRecognitionGuidanceTone.review,
      );
    }

    if (looksLikeMixedThread) {
      return const ScreenshotRecognitionGuidance(
        title: '先確認是不是同一人',
        body: '這批截圖可能混到不同人的內容。若不是目前這位對象，請取消並回到正確對象再匯入。',
        tone: ScreenshotRecognitionGuidanceTone.caution,
      );
    }

    if (recognized.sideConfidence == 'low') {
      return const ScreenshotRecognitionGuidance(
        title: '先確認我說 / 她說',
        body: '這批訊息的左右還不夠穩，建議先檢查每則是「我說」還是「她說」，再確認本次內容。',
        tone: ScreenshotRecognitionGuidanceTone.review,
      );
    }

    if (recognized.uncertainSideCount > 0) {
      return const ScreenshotRecognitionGuidance(
        title: '先修正幾則再確認',
        body: '大部分內容可用，但有少數訊息的左右還不夠清楚。建議先修正「我說 / 她說」後再確認。',
        tone: ScreenshotRecognitionGuidanceTone.review,
      );
    }

    if (hasQuotedReplyPreview(recognized)) {
      return const ScreenshotRecognitionGuidance(
        title: '先確認我說 / 她說',
        body: '這批訊息含回覆引用框。暗色、長截圖或引用卡裡的人名可能讓 AI 誤判左右，請特別確認每則是「我說」還是「她說」。',
        tone: ScreenshotRecognitionGuidanceTone.review,
      );
    }

    if (recognized.importPolicy == 'confirm' ||
        recognized.confidence != 'high') {
      return const ScreenshotRecognitionGuidance(
        title: '先確認本次內容',
        body: '若有模糊、截到一半，或是 LINE 的回覆引用框，建議保留完整泡泡後重截一次。',
        tone: ScreenshotRecognitionGuidanceTone.review,
      );
    }

    return const ScreenshotRecognitionGuidance(
      title: '可直接加入',
      body: '這看起來是正常聊天截圖。請確認內容與「我說／她說」方向，這批會作為一次獨立分析。',
      tone: ScreenshotRecognitionGuidanceTone.stable,
    );
  }

  static String actionGuidance(RecognizedConversation recognized) {
    return guidance(recognized).body;
  }

}
