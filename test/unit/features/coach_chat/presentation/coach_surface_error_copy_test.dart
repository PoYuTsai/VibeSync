import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/coach_chat/data/services/coach_chat_api_service.dart';
import 'package:vibesync/features/coach_chat/presentation/widgets/coach_surface.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';
import 'package:vibesync/features/subscription/presentation/paywall_entry.dart';
import 'package:vibesync/features/subscription/presentation/quota_copy.dart';

const _free = SubscriptionTierHelper.free;
const _starter = SubscriptionTierHelper.starter;
const _essential = SubscriptionTierHelper.essential;

CoachChatQuotaExceededException _daily() => CoachChatQuotaExceededException(
      'daily_limit_exceeded',
      code: 'DAILY_LIMIT_EXCEEDED',
      used: 15,
      limit: 15,
    );

CoachChatQuotaExceededException _monthly() => CoachChatQuotaExceededException(
      'monthly_limit_exceeded',
      code: 'MONTHLY_LIMIT_EXCEEDED',
      used: 120,
      limit: 120,
    );

void main() {
  test('quota error copy names quota instead of coach failure', () {
    final error = _daily();

    expect(CoachSurface.failureTitleFor(error), '今日額度已用完');
    expect(
      CoachSurface.failureSubtitleFor(error, tier: _free),
      contains('額度限制'),
    );
    expect(
      CoachSurface.failureMessageFor(error, tier: _free),
      contains('今日額度已用完'),
    );
    expect(
        CoachSurface.failureMessageFor(error, tier: _free), contains('15/15'));
    expect(
      CoachSurface.failureMessageFor(error, tier: _free),
      isNot(contains('沒接住')),
    );
    expect(CoachSurface.failureActionLabelFor(error, tier: _free), '查看升級');
  });

  // 額度說法照方案（Eric 2026-10-18）：Essential 已經是最高方案，不叫他升級，只說
  // 什麼時候恢復；免費、Starter 照舊說升級，Starter 不會被點名升級到 Starter。
  // 台灣早上 8 點才恢復，每日那句不說「明天」。
  group('額度說法照方案', () {
    test('Essential：每日、每月都只說什麼時候恢復，鈕寫查看方案', () {
      for (final (error, resetLine, otherResetLine) in [
        (_daily(), kDailyQuotaResetLine, kMonthlyQuotaResetLine),
        (_monthly(), kMonthlyQuotaResetLine, kDailyQuotaResetLine),
      ]) {
        final message = CoachSurface.failureMessageFor(error, tier: _essential);
        expect(message, contains(resetLine));
        expect(message, isNot(contains(otherResetLine)));
        expect(message, isNot(contains('升級')));
        expect(message, isNot(contains('明天')));
        expect(
          CoachSurface.failureSubtitleFor(error, tier: _essential),
          '這是額度限制，不是教練失敗。',
        );
        expect(
          CoachSurface.failureActionLabelFor(error, tier: _essential),
          '查看方案',
        );
      }
      // 恢復時間自己一行：接在用量後面，手機寬度會把最後一兩個字擠到第二行。
      expect(
        CoachSurface.failureMessageFor(_daily(), tier: _essential),
        '今日額度已用完（15/15）。\n$kDailyQuotaResetLine。',
      );
      expect(
        CoachSurface.failureMessageFor(_monthly(), tier: _essential),
        '本月額度已用完（120/120）。\n$kMonthlyQuotaResetLine。',
      );
    });

    // Onboarding 第 3 步：每月那句以前只叫人升級，現在跟每日一樣先說幾點恢復。
    test('免費、Starter：每日、每月都先說幾點恢復，再說也可以升級；不點名 Starter', () {
      for (final tier in [_free, _starter]) {
        final daily = CoachSurface.failureMessageFor(_daily(), tier: tier);
        expect(
          daily,
          '今日額度已用完（15/15），$kDailyQuotaResetLine；也可以升級解鎖更多教練建議。',
        );
        expect(
          CoachSurface.failureMessageFor(_monthly(), tier: tier),
          '本月額度已用完（120/120）。$kMonthlyQuotaResetLine；也可以升級繼續問教練。',
        );
        for (final error in [_daily(), _monthly()]) {
          expect(
            CoachSurface.failureMessageFor(error, tier: tier),
            isNot(contains('Starter')),
          );
          expect(
            CoachSurface.failureSubtitleFor(error, tier: tier),
            '這是額度限制，不是教練失敗。升級或等額度重置後再試。',
          );
          expect(CoachSurface.failureActionLabelFor(error, tier: tier), '查看升級');
        }
      }
    });

    test('付費頁入口照每月或每日、用完或只是不夠', () {
      expect(
        CoachSurface.paywallEntryFor(_daily()),
        PaywallEntry.dailyQuotaUsedUp,
      );
      expect(
        CoachSurface.paywallEntryFor(_monthly()),
        PaywallEntry.monthlyQuotaUsedUp,
      );
      // 伺服器沒帶 used／limit：不知道剩幾則，只說不夠這次用。
      expect(
        CoachSurface.paywallEntryFor(
          CoachChatQuotaExceededException('x', code: 'MONTHLY_LIMIT_EXCEEDED'),
        ),
        PaywallEntry.monthlyQuotaShort,
      );
    });
  });

  test('generation failure keeps non-quota retry copy', () {
    final error = CoachChatGenerationFailedException('invalid_card');

    expect(CoachSurface.failureTitleFor(error), '這題教練沒接住');
    expect(CoachSurface.failureActionLabelFor(error, tier: _free), '重試這題');
  });

  // 「未扣額度」只能出現在 server 保證沒走到扣費的路徑（4xx 驗證失敗）。
  // generation failure 含 client 端 parse 失敗（server 已扣）、未知錯誤含
  // 網路掉包（可能已扣），這兩處承諾未扣會說謊。
  test('no-charge promise only appears on guaranteed 4xx path', () {
    final apiError = CoachChatApiException('bad_request', status: 400);
    expect(
      CoachSurface.failureMessageFor(apiError, tier: _free),
      contains('未扣額度'),
    );

    final generationError = CoachChatGenerationFailedException('invalid_card');
    expect(
      CoachSurface.failureMessageFor(generationError, tier: _free),
      isNot(contains('未扣額度')),
    );
    expect(
      CoachSurface.failureSubtitleFor(generationError, tier: _free),
      isNot(contains('未扣額度')),
    );

    final unknownError = StateError('socket closed');
    expect(
      CoachSurface.failureMessageFor(unknownError, tier: _free),
      isNot(contains('未扣額度')),
    );
  });

  // server per-user 模型限流（MODEL_RATE_LIMITED 429）：非額度、不開 paywall，
  // 顯示 server 的「稍等再試」文案。
  test('rate-limit 429 shows server wait copy, not quota upsell', () {
    final error = CoachChatApiException(
      '操作太頻繁，請稍等一分鐘再試。',
      status: 429,
    );

    expect(CoachSurface.isQuotaError(error), isFalse);
    expect(CoachSurface.failureMessageFor(error, tier: _free), contains('太頻繁'));
    expect(
      CoachSurface.failureMessageFor(error, tier: _free),
      isNot(contains('連線暫時不穩')),
    );
    expect(CoachSurface.failureActionLabelFor(error, tier: _free), '重試這題');
  });
}
