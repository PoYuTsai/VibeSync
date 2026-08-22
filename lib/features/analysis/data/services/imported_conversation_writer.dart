/// data 端深 write operation：截圖匯入的「對話存檔＋讀取快取刷新」
/// 封裝為單一操作。順序固定：save 成功後才 refresh、且恰好一次；
/// save 失敗或未執行絕不 refresh。coordinator 只看到 application-neutral
/// 的 persist callable，不知道 Riverpod provider 失效這件事。
library;

import '../../../conversation/domain/entities/conversation.dart';

class ImportedConversationWriter {
  ImportedConversationWriter({
    required Future<void> Function(Conversation conversation) save,
    required void Function() refreshConversationViews,
  })  : _save = save,
        _refreshConversationViews = refreshConversationViews;

  final Future<void> Function(Conversation conversation) _save;
  final void Function() _refreshConversationViews;

  Future<void> persist(Conversation conversation) async {
    await _save(conversation);
    _refreshConversationViews();
  }
}
