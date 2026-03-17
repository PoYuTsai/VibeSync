import '../../../conversation/domain/entities/conversation.dart';
import '../entities/analysis_models.dart';

class ScreenshotRecognitionHelper {
  static const String importModeAppendCurrent = 'append_current';
  static const String importModeNewConversation = 'new_conversation';

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
    final hasNamedThread = currentName.isNotEmpty && currentName != '新對話';

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
    final hasNamedThread = currentName.isNotEmpty && currentName != '新對話';
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

    return '新對話';
  }

  static String classificationLabel(String classification) {
    switch (classification) {
      case 'low_confidence':
        return '低信心';
      case 'social_feed':
        return '社群內容';
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

  static String actionGuidance(RecognizedConversation recognized) {
    if (recognized.importPolicy == 'reject') {
      if (recognized.classification == 'social_feed') {
        return '這看起來比較像社群貼文或留言串，建議改截雙人聊天畫面再試。';
      }
      return '這張圖目前不適合匯入，建議重截更清楚的聊天畫面，保留完整對話泡泡與標題列。';
    }

    if (recognized.importPolicy == 'confirm' ||
        recognized.confidence != 'high') {
      return '這張圖可以先確認再匯入。若有模糊、截到一半，或是 LINE 的回覆引用框，建議保留完整泡泡後重截一次。';
    }

    return '這看起來是正常聊天截圖。如果不是最新續聊，建議改用「另存成新對話」避免污染目前 thread。';
  }
}
