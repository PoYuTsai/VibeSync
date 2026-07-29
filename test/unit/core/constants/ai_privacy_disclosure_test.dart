import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/constants/ai_privacy_disclosure.dart';
import 'package:vibesync/shared/widgets/ai_data_sharing_consent.dart';

void main() {
  group('重播揭露：設定頁與同意框不得各說各話', () {
    // 「我幫你修」與「再調一下」走同一條重播流程、同一把同意 key、同一份
    // 7 天保留期。兩處揭露只要有一處漏掉微調，使用者看到的資料處理說明就
    // 與實際送出的東西對不上。
    test('設定頁 AI 隱私揭露同時涵蓋潤飾與微調', () {
      expect(AiPrivacyDisclosure.description, contains('我幫你修'));
      expect(AiPrivacyDisclosure.description, contains('再調一下'));
      expect(AiPrivacyDisclosure.description, contains('微調指令'));
      expect(AiPrivacyDisclosure.description, contains('保留 7 天'));
    });

    test('同意框文案同時涵蓋潤飾與微調', () {
      expect(
        AiDataSharingConsent.optimizeReplayPurposeText,
        contains('草稿潤飾或回覆微調'),
      );
      expect(
        AiDataSharingConsent.optimizeReplayDataDescription,
        contains('微調指令'),
      );
    });

    test('兩處的保留期一致：改一邊就得改另一邊', () {
      expect(AiPrivacyDisclosure.description, contains('保留 7 天並每小時清除'));
      expect(
        AiDataSharingConsent.optimizeReplayPurposeText,
        contains('保留 7 天並每小時清除'),
      );
    });

    test('兩處都不得宣稱另存原始草稿或指令', () {
      for (final text in [
        AiPrivacyDisclosure.description,
        AiDataSharingConsent.optimizeReplayPurposeText,
      ]) {
        expect(text, contains('不另存原始草稿、微調指令或完整對話輸入'));
      }
    });

    test('onboarding 維持精簡版，不列廠商也不展開重播細節', () {
      // 廠商名刻意不在 onboarding 出現（避免誤解練習室女孩＝DeepSeek）。
      expect(AiPrivacyDisclosure.onboardingDescription, isNot(contains('DeepSeek')));
      expect(AiPrivacyDisclosure.onboardingDescription, isNot(contains('保留 7 天')));
    });
  });
}
