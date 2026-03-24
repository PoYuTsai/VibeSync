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
  static const String importModeAppendCurrent = 'append_current';
  static const String importModeNewConversation = 'new_conversation';
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

  static String? fallbackWarningForClassification(String classification) {
    switch (classification) {
      case 'group_chat':
        return '這張圖看起來像群組聊天，目前只支援一對一聊天截圖。';
      case 'gallery_album':
        return '這張圖看起來像相簿或選圖畫面，不是聊天視窗。';
      case 'call_log_screen':
        return '這張圖比較像通話紀錄頁，不是可直接匯入的聊天畫面。';
      case 'system_ui':
        return '這張圖看起來像系統畫面或通知頁，不是聊天視窗。';
      case 'sensitive_content':
        return '這張圖包含不適合辨識的敏感內容，請改傳聊天截圖。';
      case 'social_feed':
        return '這張圖看起來比較像社群貼文或留言串，不像雙人聊天視窗。';
      case 'unsupported':
        return '這張圖目前不像可匯入的聊天截圖，請改傳完整聊天視窗後再試。';
      default:
        return null;
    }
  }

  static String? buildWarning({
    required RecognizedConversation recognized,
    required Conversation currentConversation,
  }) {
    final warnings = <String>[];
    final serverWarning = recognized.warning?.trim();
    if (serverWarning != null && serverWarning.isNotEmpty) {
      warnings.add(serverWarning);
    }

    final recognizedName = recognized.contactName?.trim();
    final currentName = currentConversation.name.trim();
    final hasExistingThread = currentConversation.messages.isNotEmpty;
    final hasNamedThread = !isPlaceholderConversationName(currentName);

    if (hasExistingThread &&
        hasNamedThread &&
        recognizedName != null &&
        recognizedName.isNotEmpty &&
        recognizedName != currentName) {
      warnings.add(
        '這張截圖辨識到的對方名字是「$recognizedName」，和目前對話名稱不同，請先確認沒有選錯截圖。',
      );
    }

    if (recognized.importPolicy == 'confirm' && warnings.isEmpty) {
      warnings.add('這張圖還不太確定，匯入前請先看一下內容有沒有抓對。');
    }

    if (serverWarning != null && _looksLikeMixedThreadWarning(serverWarning)) {
      warnings.add('如果這批截圖不是同一個人的同一段對話，建議改用「另存成新對話」，比較不會混在一起。');
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

  static String defaultImportMode({
    required RecognizedConversation recognized,
    required Conversation currentConversation,
  }) {
    final hasExistingThread = currentConversation.messages.isNotEmpty;
    if (!hasExistingThread) {
      return importModeAppendCurrent;
    }

    final recognizedName = recognized.contactName?.trim();
    final currentName = currentConversation.name.trim();
    final hasNamedThread = !isPlaceholderConversationName(currentName);
    final nameMismatch = hasNamedThread &&
        recognizedName != null &&
        recognizedName.isNotEmpty &&
        recognizedName != currentName;

    if (recognized.importPolicy == 'confirm' || nameMismatch) {
      return importModeNewConversation;
    }

    return importModeAppendCurrent;
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

  static String? sideConfidenceWarning(RecognizedConversation recognized) {
    if (recognized.uncertainSideCount > 0) {
      return '有 ${recognized.uncertainSideCount} 則訊息的左右還不夠清楚，匯入前請再看一下「我說 / 她說」有沒有判對。';
    }

    if (recognized.sideConfidence == 'medium') {
      return '這批訊息的左右有部分是系統幫你補判的，匯入前建議快速看一下。';
    }

    if (recognized.sideConfidence == 'low') {
      return '這批訊息的左右還不夠穩，建議先檢查後再匯入。';
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
            body: '這看起來像手機的通話紀錄頁。若你想匯入聊天對話裡的來電事件，請保留聊天標題列與上下文後再重截。',
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
        body: '這張圖目前不適合匯入，建議重截更清楚的聊天畫面，保留完整對話泡泡與標題列。',
        tone: ScreenshotRecognitionGuidanceTone.reject,
      );
    }

    if (looksLikeCallRecord) {
      return const ScreenshotRecognitionGuidance(
        title: '先確認再匯入',
        body: '這張圖像是聊天視窗裡的未接來電或通話紀錄。若確認是同一段對話，先檢查方向與順序，再決定是否匯入。',
        tone: ScreenshotRecognitionGuidanceTone.review,
      );
    }

    if (looksLikeMixedThread) {
        return const ScreenshotRecognitionGuidance(
          title: '建議另存成新對話',
          body: '這批截圖可能混到不同人的內容。先看一下預覽；如果不是同一段續聊，請改用「另存成新對話」。',
          tone: ScreenshotRecognitionGuidanceTone.caution,
        );
    }

    if (recognized.sideConfidence == 'low') {
      return const ScreenshotRecognitionGuidance(
        title: '先確認我說 / 她說',
        body: '這批訊息的左右還不夠穩，建議先檢查每則是「我說」還是「她說」，再決定是否匯入。',
        tone: ScreenshotRecognitionGuidanceTone.review,
      );
    }

    if (recognized.uncertainSideCount > 0) {
      return const ScreenshotRecognitionGuidance(
        title: '先修正幾則再匯入',
        body: '大部分內容可用，但有少數訊息的左右還不夠清楚。建議先修正「我說 / 她說」後再匯入。',
        tone: ScreenshotRecognitionGuidanceTone.review,
      );
    }

    if (recognized.importPolicy == 'confirm' ||
        recognized.confidence != 'high') {
      return const ScreenshotRecognitionGuidance(
        title: '先看一下再匯入',
        body: '這張圖可以先確認再匯入。若有模糊、截到一半，或是 LINE 的回覆引用框，建議保留完整泡泡後重截一次。',
        tone: ScreenshotRecognitionGuidanceTone.review,
      );
    }

    return const ScreenshotRecognitionGuidance(
      title: '可直接匯入',
      body: '這看起來是正常聊天截圖。如果不是最新續聊，建議改用「另存成新對話」避免污染目前對話。',
      tone: ScreenshotRecognitionGuidanceTone.stable,
    );
  }

  static String actionGuidance(RecognizedConversation recognized) {
    return guidance(recognized).body;
  }

  static String importModeDescription({
    required RecognizedConversation recognized,
    required Conversation currentConversation,
    required String selectedImportMode,
  }) {
    final hasExistingThread = currentConversation.messages.isNotEmpty;
    final recognizedName = recognized.contactName?.trim();
    final currentName = currentConversation.name.trim();
    final hasNamedThread = !isPlaceholderConversationName(currentName);
    final nameMismatch = hasExistingThread &&
        hasNamedThread &&
        recognizedName != null &&
        recognizedName.isNotEmpty &&
        recognizedName != currentName;
    final mixedThread =
        _looksLikeMixedThreadWarning(recognized.warning?.trim() ?? '');
    final shouldPreferNewConversation =
        recognized.importPolicy == 'confirm' || nameMismatch || mixedThread;

    if (selectedImportMode == importModeAppendCurrent) {
      if (!hasExistingThread) {
        return '會把這批訊息存進目前這個新對話，適合剛開始匯入第一批截圖。';
      }

      if (recognized.sideConfidence == 'low' ||
          recognized.uncertainSideCount > 0) {
        return '加入目前對話前，建議先把「我說 / 她說」看清楚，避免接錯。';
      }

      if (shouldPreferNewConversation) {
        return '只有在你確定這批截圖就是目前這段續聊時，才建議加入目前對話；不確定時改用「另存成新對話」會更安全。';
      }

      return '會把這批訊息接到目前對話尾端，適合剛截到最新續聊。';
    }

    if (shouldPreferNewConversation) {
      return '這是目前較安全的選擇，可避免把不同人的內容或不同段落混進目前對話。';
    }

    if (!hasExistingThread) {
      return '會用這批截圖建立新的對話，之後可再補手動輸入或新的截圖。';
    }

    return '會建立新的對話，不會污染目前這段聊天紀錄。';
  }
}
