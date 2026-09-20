import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/core/services/app_haptics.dart';
import 'package:vibesync/shared/widgets/brand/brand_kit.dart';
import 'package:vibesync/shared/widgets/brand/opener_home_components.dart';

void main() {
  final haptics = <Object?>[];
  setUp(() {
    AppHaptics.enabled = true;
    haptics.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments);
      return null;
    });
  });
  tearDown(() {
    AppHaptics.enabled = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pump(WidgetTester t, Widget child,
          {bool reducedMotion = false}) =>
      t.pumpWidget(MaterialApp(
          home: MediaQuery(
              data: MediaQueryData(disableAnimations: reducedMotion),
              child: Scaffold(body: child))));

  testWidgets(
      'mode/source selection emits once and same or disabled emits none',
      (t) async {
    var mode = 0;
    var source = 0;
    var locked = false;
    late StateSetter update;
    await pump(t, StatefulBuilder(builder: (_, setState) {
      update = setState;
      return Column(children: [
        OpenerModeControl<int>(
            value: mode,
            options: const [(0, '開場白'), (1, '新話題')],
            onChanged: (value) => setState(() => mode = value)),
        OpenerSourceTabs(
            selected: source,
            onChanged:
                locked ? null : (value) => setState(() => source = value)),
      ]);
    }));
    await t.tap(find.text('開場白'));
    await t.tap(find.text('新話題'));
    await t.pump();
    await t.tap(find.text('新話題'));
    expect(haptics, ['HapticFeedbackType.mediumImpact']);
    await t.tap(find.text('手動輸入'));
    await t.pump();
    await t.tap(find.text('手動輸入'));
    expect(haptics, hasLength(2));
    update(() => locked = true);
    await t.pump();
    await t.tap(find.text('截圖自介'));
    expect(source, 1);
    expect(haptics, hasLength(2));
  });

  testWidgets(
      'footer and nested flow CTA emit once; disabled and preference off emit none',
      (t) async {
    var primary = 0;
    var quota = 0;
    var flow = 0;
    var enabled = true;
    late StateSetter update;
    await pump(t, StatefulBuilder(builder: (_, setState) {
      update = setState;
      return Column(children: [
        OpenerActionFooter(
            label: '分析開場方向',
            hint: '',
            onPressed: enabled ? () => primary++ : null,
            onQuota: () => quota++),
        BrandPrimaryButton(
            openerStyle: true,
            label: '生成回覆',
            onPressed: enabled ? () => flow++ : null),
      ]);
    }), reducedMotion: true);
    await t.tap(find.text('分析開場方向'));
    await t.tap(find.text('額度說明'));
    await t.tap(find.text('生成回覆'));
    await t.pump();
    expect((primary, quota, flow), (1, 1, 1));
    expect(haptics, List.filled(3, 'HapticFeedbackType.mediumImpact'),
        reason: 'PressableScale and onPressed must not both emit');
    expect(
        t.widgetList<AnimatedScale>(find.byType(AnimatedScale)).every(
            (scale) => scale.scale == 1 && scale.duration == Duration.zero),
        isTrue);
    update(() => enabled = false);
    await t.pump();
    await t.tap(find.text('分析開場方向'));
    await t.tap(find.text('生成回覆'));
    expect(haptics, hasLength(3));
    expect((primary, flow), (1, 1));

    // Load the same persisted preference used by the app, without replacing
    // the shared haptic API or guessing device vibration behavior.
    SharedPreferences.setMockInitialValues({'haptics_enabled': false});
    await AppHaptics.init();
    update(() => enabled = true);
    await t.pump();
    await t.tap(find.text('分析開場方向'));
    await t.tap(find.text('額度說明'));
    await t.tap(find.text('生成回覆'));
    expect((primary, quota, flow), (2, 2, 2));
    expect(haptics, hasLength(3));
  });

  testWidgets('situation deselection is an action, busy choices are not',
      (t) async {
    String? selected;
    var enabled = true;
    late StateSetter update;
    await pump(t, StatefulBuilder(builder: (_, setState) {
      update = setState;
      return Column(children: [
        OpenerSituationGrid(
            options: const [
              (label: '冷掉了', value: 'cold'),
              (label: '剛約完', value: 'date')
            ],
            selected: selected,
            onChanged: enabled
                ? (value) => setState(() {
                      selected = selected == value ? null : value;
                    })
                : null),
        BrandChoiceChip(
            label: '我有養狗', selected: false, enabled: enabled, onTap: () {}),
      ]);
    }));
    await t.tap(find.text('冷掉了'));
    await t.pump();
    expect(selected, 'cold');
    await t.tap(find.text('冷掉了'));
    await t.pump();
    expect(selected, isNull);
    await t.tap(find.text('我有養狗'));
    expect(haptics, hasLength(3));
    update(() => enabled = false);
    await t.pump();
    await t.tap(find.text('剛約完'));
    await t.tap(find.text('我有養狗'));
    expect(haptics, hasLength(3));
    expect(selected, isNull);
  });
}
