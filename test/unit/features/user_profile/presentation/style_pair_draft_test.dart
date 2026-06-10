import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';
import 'package:vibesync/features/user_profile/presentation/style_pair_draft.dart';

void main() {
  group('StylePairDraft.tap — 5 條點擊規則', () {
    test('規則 1：未選 chip、0 選 → 成為主', () {
      final next = StylePairDraft.empty.tap(InteractionStyle.steady);
      expect(next.primary, InteractionStyle.steady);
      expect(next.secondary, isNull);
    });

    test('規則 2：未選 chip、1 選 → 成為副', () {
      const one = StylePairDraft(primary: InteractionStyle.steady);
      final next = one.tap(InteractionStyle.humorous);
      expect(next.primary, InteractionStyle.steady);
      expect(next.secondary, InteractionStyle.humorous);
    });

    test('規則 3：未選 chip、2 選 → 取代副（主不被路過點擊偷換）', () {
      const two = StylePairDraft(
        primary: InteractionStyle.steady,
        secondary: InteractionStyle.humorous,
      );
      final next = two.tap(InteractionStyle.playful);
      expect(next.primary, InteractionStyle.steady);
      expect(next.secondary, InteractionStyle.playful);
    });

    test('規則 4：點主 chip → 取消主；有副 → 副升格為主', () {
      const two = StylePairDraft(
        primary: InteractionStyle.steady,
        secondary: InteractionStyle.humorous,
      );
      final next = two.tap(InteractionStyle.steady);
      expect(next.primary, InteractionStyle.humorous);
      expect(next.secondary, isNull);

      // 無副時取消主 → 全空。
      const one = StylePairDraft(primary: InteractionStyle.steady);
      final cleared = one.tap(InteractionStyle.steady);
      expect(cleared.primary, isNull);
      expect(cleared.secondary, isNull);
    });

    test('規則 5：點副 chip → 取消副', () {
      const two = StylePairDraft(
        primary: InteractionStyle.steady,
        secondary: InteractionStyle.humorous,
      );
      final next = two.tap(InteractionStyle.humorous);
      expect(next.primary, InteractionStyle.steady);
      expect(next.secondary, isNull);
    });

    test('任意點擊序列永遠停在合法狀態（無「有副無主」、副!=主）', () {
      var state = StylePairDraft.empty;
      const taps = [
        InteractionStyle.steady,
        InteractionStyle.humorous,
        InteractionStyle.playful,
        InteractionStyle.steady,
        InteractionStyle.playful,
        InteractionStyle.gentle,
        InteractionStyle.gentle,
        InteractionStyle.direct,
      ];
      for (final tap in taps) {
        state = state.tap(tap);
        expect(state.secondary == null || state.primary != null, isTrue,
            reason: '有副必有主 violated after tapping $tap');
        expect(state.primary == null || state.primary != state.secondary,
            isTrue,
            reason: '副 != 主 violated after tapping $tap');
      }
    });
  });

  group('StylePairDraft helpers', () {
    test('contains / badgeOf reflect 主/副 roles', () {
      const pair = StylePairDraft(
        primary: InteractionStyle.steady,
        secondary: InteractionStyle.humorous,
      );
      expect(pair.contains(InteractionStyle.steady), isTrue);
      expect(pair.contains(InteractionStyle.humorous), isTrue);
      expect(pair.contains(InteractionStyle.playful), isFalse);
      expect(pair.badgeOf(InteractionStyle.steady), '主');
      expect(pair.badgeOf(InteractionStyle.humorous), '副');
      expect(pair.badgeOf(InteractionStyle.playful), isNull);
    });
  });
}
