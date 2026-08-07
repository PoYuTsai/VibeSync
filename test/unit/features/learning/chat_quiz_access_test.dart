// test/unit/features/learning/chat_quiz_access_test.dart
//
// 聊天測驗的關卡權限。形狀照 `ebook_essential_unit_test.dart`。
//
// 這一支守的是同一個很容易破、破了也不會有錯誤訊息的洞：
// `SubscriptionState.isPremium` 是 `isStarter || isEssential`，任何「照抄
// isPremium」的判斷都會讓 Starter 進到取材《成為獎賞》的關卡。
//
// 另一半守的是三態：訂閱還在確認時不得顯示付費文案。那個 bug 的外觀是
// 「一開 App 就被推銷」，而不是任何錯誤。
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/learning/domain/chat_quiz_access.dart';
import 'package:vibesync/features/learning/domain/models/ebook.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_access_gate.dart';

import '../../../helpers/chat_quiz_test_content.dart';

// `accessForLevel`（access＝取材推導）已隨 ADR #38 移除：關卡 access 只表達
// 訂閱檔位，取材的付費保護交給電子書自己的 EbookAccessGate。

void main() {
  group('gateFor', () {
    test('free 關永不鎖，任何訂閱狀態都可進', () {
      const states = <EbookSubscriptionAccess>[
        EbookSubscriptionAccess.free(),
        EbookSubscriptionAccess.premium(),
        EbookSubscriptionAccess.essential(),
        EbookSubscriptionAccess.resolving(),
        EbookSubscriptionAccess.unavailable(),
      ];
      for (final state in states) {
        expect(gateFor(EbookAccess.free, state), ChatQuizGate.allowed);
      }
    });

    test('premium 關：Starter 進得去、Essential 進得去、免費進不去', () {
      expect(
        gateFor(EbookAccess.premium, const EbookSubscriptionAccess.premium()),
        ChatQuizGate.allowed,
      );
      expect(
        gateFor(EbookAccess.premium, const EbookSubscriptionAccess.essential()),
        ChatQuizGate.allowed,
      );
      expect(
        gateFor(EbookAccess.premium, const EbookSubscriptionAccess.free()),
        ChatQuizGate.locked,
      );
    });

    test('essential 關：Starter 進不去（不得照抄 isPremium）', () {
      const starter = EbookSubscriptionAccess.premium();
      expect(starter.isPremium, isTrue, reason: 'Starter 的 isPremium 就是 true');
      expect(
        gateFor(EbookAccess.essential, starter),
        ChatQuizGate.locked,
        reason: '照抄 isPremium 會讓 Starter 進到取材《成為獎賞》的關卡',
      );
      expect(
        gateFor(
          EbookAccess.essential,
          const EbookSubscriptionAccess.essential(),
        ),
        ChatQuizGate.allowed,
      );
    });

    test('isResolving 時回 resolving，不回 locked、不導 paywall', () {
      expect(
        gateFor(EbookAccess.premium, const EbookSubscriptionAccess.resolving()),
        ChatQuizGate.resolving,
      );
      expect(
        gateFor(
          EbookAccess.essential,
          const EbookSubscriptionAccess.resolving(),
        ),
        ChatQuizGate.resolving,
      );
    });

    test('hasError 時回 unavailable，不包裝成 Free upsell', () {
      expect(
        gateFor(
          EbookAccess.premium,
          const EbookSubscriptionAccess.unavailable(),
        ),
        ChatQuizGate.unavailable,
      );
    });

    test('離線快取顯示 Starter：premium 關進得去，essential 關仍讀不到', () {
      const cachedStarter = EbookSubscriptionAccess.cachedPremium();
      expect(cachedStarter.isResolving, isTrue);
      expect(
        gateFor(EbookAccess.premium, cachedStarter),
        ChatQuizGate.allowed,
        reason: '本機到期日還沒過，離線也該讓付費使用者玩',
      );
      // 讀不到，但狀態是 resolving 而不是 locked：訂閱還沒確認就宣告
      // 「你沒買」是錯的，畫面該給中性 loading 而不是付費文案。
      expect(
        gateFor(EbookAccess.essential, cachedStarter),
        ChatQuizGate.resolving,
        reason: 'Starter 的快取授權不會變成 Essential 授權',
      );
      expect(
        gateFor(EbookAccess.essential, cachedStarter),
        isNot(ChatQuizGate.allowed),
      );
    });

    test('快取授權已過期又離線：不放行，但也不當成免費使用者', () {
      const expired = EbookSubscriptionAccess.cachedPremium(unexpired: false);
      expect(gateFor(EbookAccess.premium, expired), ChatQuizGate.resolving);
    });

    test('離線快取顯示 Essential：essential 關進得去', () {
      const cachedEssential =
          EbookSubscriptionAccess.cachedPremium(essential: true);
      expect(
        gateFor(EbookAccess.essential, cachedEssential),
        ChatQuizGate.allowed,
      );
    });
  });

  group('gateForLevel', () {
    test('用內容宣告的 access，不在 runtime 重算', () {
      final level = buildTestChatQuizLevel(access: EbookAccess.essential);
      expect(
        gateForLevel(level, const EbookSubscriptionAccess.premium()),
        ChatQuizGate.locked,
      );
      expect(
        gateForLevel(level, const EbookSubscriptionAccess.essential()),
        ChatQuizGate.allowed,
      );
    });
  });
}
