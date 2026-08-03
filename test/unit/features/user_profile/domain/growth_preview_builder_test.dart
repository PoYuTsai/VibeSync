import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';
import 'package:vibesync/features/user_profile/domain/services/growth_preview_builder.dart';

void main() {
  const builder = GrowthPreviewBuilder();

  test('both A1 and A2 filled', () {
    final text = builder.build(
      stuckPoints: [StuckPoint.fadesOut],
      goals: [PracticeGoal.softInvite],
      comfortStyle: null,
    );
    expect(text, contains('你想'));
    expect(text, contains('教練會盯著你'));
  });

  test('only A2 filled', () {
    final text = builder.build(
      stuckPoints: const [],
      goals: [PracticeGoal.softInvite],
      comfortStyle: null,
    );
    expect(text, contains('教練會照著這個方向'));
  });

  test('only A1 filled', () {
    final text = builder.build(
      stuckPoints: [StuckPoint.fadesOut],
      goals: const [],
      comfortStyle: null,
    );
    expect(text, contains('教練會盯著你'));
    expect(text, isNot(contains('你想')));
  });

  test('neither filled falls back to generic line', () {
    final text = builder.build(
      stuckPoints: const [],
      goals: const [],
      comfortStyle: null,
    );
    expect(text, contains('先摸清你的說話習慣和邊界'));
  });

  test('comfort style appends the pacing note', () {
    final text = builder.build(
      stuckPoints: const [],
      goals: const [],
      comfortStyle: InteractionStyle.steady,
    );
    expect(text, contains('教練知道你平常偏穩重'));
  });
}
