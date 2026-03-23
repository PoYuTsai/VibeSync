import '../../../conversation/domain/entities/conversation.dart';
import '../entities/analysis_models.dart';

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
      warnings.add('這張截圖辨識信心較低，匯入前請先確認預覽內容是否正確。');
    }

    if (serverWarning != null && _looksLikeMixedThreadWarning(serverWarning)) {
      warnings.add('若這批截圖不是同一個人的同一段對話，建議改用「另存成新對話」避免污染目前 thread。');
    }

    final sideWarning = sideConfidenceWarning(recognized);
    if (sideWarning != null) {
      warnings.add(sideWarning);
    }

    if (recognized.importPolicy == 'reject' && warnings.isEmpty) {
      final fallback = fallbackWarningForClassification(recognized.classification);
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
    final nameMismatch =
        hasNamedThread &&
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
        return '低信心';
      case 'social_feed':
        return '社群內容';
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
        return '不支援';
      case 'valid_chat':
      default:
        return '聊天截圖';
    }
  }

  static String confidenceLabel(String confidence) {
    switch (confidence) {
      case 'low':
        return '信心偏低';
      case 'medium':
        return '信心中等';
      case 'high':
      default:
        return '信心高';
    }
  }

  static String sideConfidenceLabel(String confidence) {
    switch (confidence) {
      case 'low':
        return '方向待確認';
      case 'medium':
        return '方向中等';
      case 'high':
      default:
        return '方向穩定';
    }
  }

  static String? sideConfidenceWarning(RecognizedConversation recognized) {
    if (recognized.uncertainSideCount > 0) {
      return '有 ${recognized.uncertainSideCount} 則訊息的左右方向不夠確定，匯入前請特別檢查「我說 / 她說」是否正確。';
    }

    if (recognized.sideConfidence == 'medium') {
      return '這批訊息的左右方向有部分是系統協助校正後得到的，建議匯入前再快速確認一次。';
    }

    if (recognized.sideConfidence == 'low') {
      return '這批訊息的左右方向信心偏低，建議逐則檢查後再匯入。';
    }

    return null;
  }

  static String actionGuidance(RecognizedConversation recognized) {
    final warning = recognized.warning?.trim() ?? '';
    final looksLikeCallRecord =
        warning.contains('通話紀錄') || warning.contains('未接來電');
    final looksLikeMixedThread = _looksLikeMixedThreadWarning(warning);

    if (recognized.importPolicy == 'reject') {
      switch (recognized.classification) {
        case 'social_feed':
          return '這看起來比較像社群貼文或留言串，建議改截雙人聊天畫面再試。';
        case 'group_chat':
          return '這看起來像群組聊天，目前產品只支援一對一對話分析，建議改截和單一對象的聊天視窗。';
        case 'gallery_album':
          return '這看起來像相簿或選圖畫面，建議回到聊天 App 內重新截圖。';
        case 'call_log_screen':
          return '這看起來像手機的通話紀錄頁。若你想匯入聊天 thread 裡的來電事件，請保留聊天標題列與上下文後再重截。';
        case 'system_ui':
          return '這看起來像系統畫面或通知頁，不是可分析的聊天截圖。請改傳聊天視窗。';
        case 'sensitive_content':
          return '這張圖包含不適合辨識的敏感內容，請改傳純聊天截圖。';
      }
      return '這張圖目前不適合匯入，建議重截更清楚的聊天畫面，保留完整對話泡泡與標題列。';
    }

    if (looksLikeCallRecord) {
      return '這張圖像是聊天視窗裡的未接來電或通話紀錄。若確認是同一段對話，先檢查方向與順序，再決定是否匯入。';
    }

    if (looksLikeMixedThread) {
      return '這批截圖可能混入了不同人的對話，建議先逐則檢查預覽；如果不是同一段續聊，請改用「另存成新對話」。';
    }

    if (recognized.sideConfidence == 'low') {
      return '這批訊息的左右方向還不夠穩，建議先檢查每則是「我說」還是「她說」，再決定是否匯入。';
    }

    if (recognized.uncertainSideCount > 0) {
      return '大部分內容可用，但有少數訊息的左右方向不夠確定。建議先修正「我說 / 她說」後再匯入。';
    }

    if (recognized.importPolicy == 'confirm' ||
        recognized.confidence != 'high') {
      return '這張圖可以先確認再匯入。若有模糊、截到一半，或是 LINE 的回覆引用框，建議保留完整泡泡後重截一次。';
    }

    return '這看起來是正常聊天截圖。如果不是最新續聊，建議改用「另存成新對話」避免污染目前 thread。';
  }
}
