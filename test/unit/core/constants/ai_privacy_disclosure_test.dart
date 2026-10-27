import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/constants/ai_privacy_disclosure.dart';
import 'package:vibesync/core/services/funnel_tracker.dart';
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

    // 2026-10-02：練習室的回覆部分輪次、提示與拆解卡走 Anthropic Claude，
    // 揭露只寫 DeepSeek 會少報一家供應商。設定頁與同意框都要點名兩家。
    test('練習室揭露同時點名 DeepSeek 與 Anthropic', () {
      expect(
        AiPrivacyDisclosure.description,
        contains('練習室用 DeepSeek 與 Anthropic Claude'),
      );
      expect(
          AiDataSharingConsent.practiceDestinationLabel, contains('DeepSeek'));
      expect(
        AiDataSharingConsent.practiceDestinationLabel,
        contains('Anthropic'),
      );
      expect(AiDataSharingConsent.practicePurposeText, contains('提示'));
    });

    // 規格 PR-5：「關於我」只在教練 1:1 跟著問題送出。同意框寫了，設定頁也要寫，
    // 兩邊都要講「只在教練 1:1」。
    test('「關於我」揭露：設定頁與同意框都說只在教練 1:1 送出', () {
      expect(
        AiPrivacyDisclosure.description,
        contains('使用教練 1:1 時，你在「關於我」填的內容也會跟問題一起送出'),
      );
      expect(
        AiPrivacyDisclosure.description,
        contains('開場救星、對話分析和新話題不會送'),
      );
      expect(
        AiDataSharingConsent.defaultDataDescriptionForTesting,
        contains('你在「關於我」填的內容（只在使用教練 1:1 時）'),
      );
    });

    test('onboarding 維持精簡版，不列廠商也不展開重播細節', () {
      // 廠商名刻意不在 onboarding 出現（避免誤解練習室女孩＝DeepSeek）。
      expect(AiPrivacyDisclosure.onboardingDescription,
          isNot(contains('DeepSeek')));
      expect(
          AiPrivacyDisclosure.onboardingDescription, isNot(contains('保留 7 天')));
    });
  });

  // onboarding 轉換第 4 步：登入前的使用事件先存在手機、登入後補送並連到帳號
  // （Eric 2026-10-27「照預設」補進設定頁）。揭露的數字跟 FunnelTracker 綁在一起。
  group('登入前的使用事件：設定頁寫明先存手機、登入後補送', () {
    test('設定頁逐字寫出這一段', () {
      expect(
        AiPrivacyDisclosure.description,
        contains('還沒登入時的使用事件（例如 onboarding 看到第幾頁、回答有沒有對象）\n'
            '會先存在這支手機，存的是事件名稱、固定選項值與發生時間，\n'
            '不含對話內容或名字，最多 50 筆。登入後才補送並連到登入的帳號；\n'
            '補送時已存超過 7 天的不送、直接刪除'),
      );
    });

    test('筆數上限與天數跟實作一致：改一邊就得改另一邊', () {
      expect(
        AiPrivacyDisclosure.description,
        contains('最多 ${FunnelTracker.maxPendingEvents} 筆'),
      );
      expect(
        AiPrivacyDisclosure.description,
        contains('已存超過 ${FunnelTracker.pendingMaxAge.inDays} 天的不送'),
      );
    });

    test('onboarding 精簡版不加這段', () {
      for (final phrase in ['還沒登入', '補送', '最多 50 筆']) {
        expect(
            AiPrivacyDisclosure.onboardingDescription, isNot(contains(phrase)));
      }
    });
  });
}
