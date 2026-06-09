import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/coach_chat/data/services/coach_chat_api_service.dart';
import 'package:vibesync/features/coach_chat/presentation/widgets/coach_chat_card.dart';

void main() {
  test('quota error copy names quota instead of coach failure', () {
    final error = CoachChatQuotaExceededException(
      'daily_limit_exceeded',
      code: 'DAILY_LIMIT_EXCEEDED',
      used: 15,
      limit: 15,
    );

    expect(CoachChatCard.failureTitleFor(error), '今日額度已用完');
    expect(CoachChatCard.failureSubtitleFor(error), contains('額度限制'));
    expect(CoachChatCard.failureMessageFor(error), contains('今日額度已用完'));
    expect(CoachChatCard.failureMessageFor(error), contains('15/15'));
    expect(CoachChatCard.failureMessageFor(error), isNot(contains('沒接住')));
    expect(CoachChatCard.failureActionLabelFor(error), '查看升級');
  });

  test('generation failure keeps non-quota retry copy', () {
    final error = CoachChatGenerationFailedException('invalid_card');

    expect(CoachChatCard.failureTitleFor(error), '這題教練沒接住');
    expect(CoachChatCard.failureMessageFor(error), contains('未扣額度'));
    expect(CoachChatCard.failureActionLabelFor(error), '重試這題');
  });
}
