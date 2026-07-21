import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/coach_chat/data/services/coach_chat_api_service.dart';
import 'package:vibesync/features/coach_chat/presentation/widgets/coach_surface.dart';

void main() {
  test('quota error copy names quota instead of coach failure', () {
    final error = CoachChatQuotaExceededException(
      'daily_limit_exceeded',
      code: 'DAILY_LIMIT_EXCEEDED',
      used: 15,
      limit: 15,
    );

    expect(CoachSurface.failureTitleFor(error), '今日額度已用完');
    expect(CoachSurface.failureSubtitleFor(error), contains('額度限制'));
    expect(CoachSurface.failureMessageFor(error), contains('今日額度已用完'));
    expect(CoachSurface.failureMessageFor(error), contains('15/15'));
    expect(CoachSurface.failureMessageFor(error), isNot(contains('沒接住')));
    expect(CoachSurface.failureActionLabelFor(error), '查看升級');
  });

  test('generation failure keeps non-quota retry copy', () {
    final error = CoachChatGenerationFailedException('invalid_card');

    expect(CoachSurface.failureTitleFor(error), '這題教練沒接住');
    expect(CoachSurface.failureActionLabelFor(error), '重試這題');
  });

  // 「未扣額度」只能出現在 server 保證沒走到扣費的路徑（4xx 驗證失敗）。
  // generation failure 含 client 端 parse 失敗（server 已扣）、未知錯誤含
  // 網路掉包（可能已扣），這兩處承諾未扣會說謊。
  test('no-charge promise only appears on guaranteed 4xx path', () {
    final apiError = CoachChatApiException('bad_request', status: 400);
    expect(CoachSurface.failureMessageFor(apiError), contains('未扣額度'));

    final generationError = CoachChatGenerationFailedException('invalid_card');
    expect(
      CoachSurface.failureMessageFor(generationError),
      isNot(contains('未扣額度')),
    );
    expect(
      CoachSurface.failureSubtitleFor(generationError),
      isNot(contains('未扣額度')),
    );

    final unknownError = StateError('socket closed');
    expect(
      CoachSurface.failureMessageFor(unknownError),
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
    expect(CoachSurface.failureMessageFor(error), contains('太頻繁'));
    expect(
      CoachSurface.failureMessageFor(error),
      isNot(contains('連線暫時不穩')),
    );
    expect(CoachSurface.failureActionLabelFor(error), '重試這題');
  });
}
