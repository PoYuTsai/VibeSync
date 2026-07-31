// lib/features/learning/domain/chat_quiz_access.dart
//
// 聊天測驗的關卡權限。純函式，重用電子書那套訂閱切片
// （[EbookSubscriptionAccess]），**不新增任何訂閱資料來源**。
//
// 硬規則：
//   - 一關的權限＝這一關所有題目來源書當中最高的那一層（free < premium <
//     essential）。權限跟著取材走，內容改了取材，權限就該跟著改——由
//     `chat_quiz_content_invariants_test.dart` 驗宣告值與推導值一致。
//   - essential 關**不得照抄 `isPremium`**：那個 bool 是 `isStarter ||
//     isEssential`，照抄會讓 Starter 讀到《成為獎賞》轉化出來的題目。這條在
//     電子書已經破過一次，測驗要有自己的一份守門。
//   - 訂閱狀態還在確認 → [ChatQuizGate.resolving]，不得顯示付費文案、不導
//     paywall。無法確認 → [ChatQuizGate.unavailable]，不得包裝成 Free upsell。
//
// 刻意不提供「這一關是不是鎖著」的 bool：那種寫法會把 resolving／unavailable
// 一起算成鎖著，而那正是「訂閱還在查就顯示快來訂閱」的來源。呼叫端請對
// [ChatQuizGate] 做 exhaustive switch，四種狀態各給各的畫面。
library;

import '../presentation/widgets/ebook_access_gate.dart';
import 'models/chat_quiz.dart';
import 'models/ebook.dart';

/// 一關現在能不能進。
enum ChatQuizGate {
  /// 可以進這一關。
  allowed,

  /// 已確認權限不足 → 導 paywall。
  locked,

  /// 訂閱狀態還在確認 → 顯示中性 loading，不顯示任何付費文案。
  resolving,

  /// 訂閱狀態無法確認 → 顯示可重試錯誤，不包裝成 Free upsell。
  unavailable,
}

/// 一關的權限＝它所有題目來源書當中最高的那一層。
///
/// 沒有 `source` 的題目視為 free（那種題目是純判讀，沒有引用任何付費教材）。
///
/// 找不到來源書時回 [EbookAccess.essential]（fail closed）：內容打錯字不該
/// 悄悄把一關降成免費。正常內容不會走到這裡——deep link 目標是否存在由
/// 內容不變式測試守。
EbookAccess accessForLevel(ChatQuizLevel level, EbookCatalog books) {
  var highest = EbookAccess.free;
  for (final question in level.questions) {
    final source = question.source;
    if (source == null) continue;
    final book = books.findBook(source.bookId);
    final access = book?.access ?? EbookAccess.essential;
    if (access.index > highest.index) highest = access;
  }
  return highest;
}

/// 三態＋一態：可進 / 鎖住 / 還在確認 / 查不到。
///
/// 快取授權的處理與電子書一致（2026-07-26 Eric 拍板）：測驗內容也是隨 App
/// bundle 發布的 JSON、完全離線可玩，所以只在「訂閱狀態已確認」或「本機保存
/// 的付費到期日仍在未來」時放行。兩者都不成立就當成未確認，不當成免費、
/// 也不放行。
///
/// 這不是 DRM。JSON 解包就拿得到，這道判斷關掉的是零成本的繞道。
ChatQuizGate gateFor(
  EbookAccess requiredAccess,
  EbookSubscriptionAccess subscription,
) {
  if (requiredAccess == EbookAccess.free) return ChatQuizGate.allowed;

  // essential 只認 isEssential。用 isPremium 的話 Starter 會整群解鎖。
  final meetsTier = requiredAccess == EbookAccess.essential
      ? subscription.isEssential
      : subscription.isPremium;
  if (meetsTier &&
      (subscription.isResolved || subscription.hasUnexpiredPaidEntitlement)) {
    return ChatQuizGate.allowed;
  }
  if (subscription.isResolving) return ChatQuizGate.resolving;
  if (subscription.hasError) return ChatQuizGate.unavailable;
  return ChatQuizGate.locked;
}

/// 關卡層的便利包裝。用內容宣告的 [ChatQuizLevel.access]——它與取材推導值
/// 一致這件事由內容不變式測試保證，runtime 不重算（重算會讓「哪一關要付費」
/// 隨內容檔飄動）。
ChatQuizGate gateForLevel(
  ChatQuizLevel level,
  EbookSubscriptionAccess subscription,
) =>
    gateFor(level.access, subscription);
