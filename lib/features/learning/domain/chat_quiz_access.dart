// lib/features/learning/domain/chat_quiz_access.dart
//
// 聊天測驗的關卡權限。純函式，重用電子書那套訂閱切片
// （[EbookSubscriptionAccess]），**不新增任何訂閱資料來源**。
//
// 硬規則：
//   - 關卡的 `access` 只表達「要不要訂閱才能玩這一關」，**不由取材推導**
//     （ADR #38，2026-08-07，推翻 ADR #36 時代的決定 5）。題目可自由取材
//     第 1–7 冊；原理的付費保護交給電子書自己的 `EbookAccessGate`——點
//     「讀原理」深連進書時，essential 書照樣擋 Starter。免費關不得取材
//     第 5–7 冊這條內容紅線仍由 `chat_quiz_content_invariants_test.dart` 守。
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

/// 關卡層的便利包裝。用內容宣告的 [ChatQuizLevel.access]——它就是真相
/// （ADR #38：access 只表達訂閱檔位，不由取材推導），runtime 不重算。
ChatQuizGate gateForLevel(
  ChatQuizLevel level,
  EbookSubscriptionAccess subscription,
) =>
    gateFor(level.access, subscription);
