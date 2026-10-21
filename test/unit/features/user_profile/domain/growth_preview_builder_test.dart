import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';
import 'package:vibesync/features/user_profile/domain/services/growth_preview_builder.dart';

void main() {
  const builder = GrowthPreviewBuilder();

  test('both A1 and A2 filled', () {
    final text = builder.build(
      stuckPoints: [StuckPoint.fadesOut],
      goals: [PracticeGoal.softInvite],
      hasNotes: false,
    );
    expect(text, contains('你想'));
    expect(text, contains('教練會盯著你'));
  });

  test('only A2 filled', () {
    final text = builder.build(
      stuckPoints: const [],
      goals: [PracticeGoal.softInvite],
      hasNotes: false,
    );
    expect(text, contains('教練會照著這個方向'));
  });

  test('only A1 filled', () {
    final text = builder.build(
      stuckPoints: [StuckPoint.fadesOut],
      goals: const [],
      hasNotes: false,
    );
    expect(text, contains('教練會盯著你'));
    expect(text, isNot(contains('你想')));
  });

  // 規格 PR-7：只說教練真的會讀的東西。
  test('only notes filled: says the coach reads what you wrote for AI', () {
    final text = builder.build(
      stuckPoints: const [],
      goals: const [],
      hasNotes: true,
    );
    expect(text, '教練會參考你寫的「想讓 AI 知道的事」，抓對時機幫你往前推一步。');
    expect(text, isNot(contains('說話習慣')));
  });

  test('only topics filled: no preview, topics never reach the coach', () {
    expect(
      builder.build(stuckPoints: const [], goals: const [], hasNotes: false),
      isNull,
    );
  });

  test('never claims the coach knows your interaction style', () {
    for (final hasNotes in [false, true]) {
      final text = builder.build(
        stuckPoints: [StuckPoint.fadesOut],
        goals: [PracticeGoal.softInvite],
        hasNotes: hasNotes,
      );
      expect(text, isNot(contains('教練知道你平常偏')));
    }
  });
}
