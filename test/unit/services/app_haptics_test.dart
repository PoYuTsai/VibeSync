import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/core/services/app_haptics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final vibrates = <String>[];

  setUp(() {
    vibrates.clear();
    AppHaptics.enabled = true;
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        vibrates.add(call.arguments as String);
      }
      return null;
    });
  });

  test('開關關閉時所有觸覺都靜音', () async {
    AppHaptics.enabled = false;
    AppHaptics.tap();
    AppHaptics.light();
    AppHaptics.medium();
    await AppHaptics.strong();
    await AppHaptics.success();
    await AppHaptics.failure();
    expect(vibrates, isEmpty);
  });

  test('強度階梯對應正確的系統觸覺', () {
    AppHaptics.tap();
    AppHaptics.light();
    AppHaptics.medium();
    expect(vibrates, [
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.mediumImpact',
      'HapticFeedbackType.heavyImpact',
    ]);
  });

  test('strong 是重×2：比 medium 明顯重，給「開始和她聊」這種一次性轉場', () async {
    await AppHaptics.strong();
    expect(vibrates, [
      'HapticFeedbackType.heavyImpact',
      'HapticFeedbackType.heavyImpact',
    ]);
  });

  test('答對是中→重兩下、答錯是重×2', () async {
    await AppHaptics.success();
    expect(vibrates, [
      'HapticFeedbackType.mediumImpact',
      'HapticFeedbackType.heavyImpact',
    ]);
    vibrates.clear();
    await AppHaptics.failure();
    expect(vibrates, [
      'HapticFeedbackType.heavyImpact',
      'HapticFeedbackType.heavyImpact',
    ]);
  });

  test('celebrate 是漸強三下（輕→中→重）', () async {
    await AppHaptics.celebrate();
    expect(vibrates, [
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.mediumImpact',
      'HapticFeedbackType.heavyImpact',
    ]);
  });

  test('tick 有 70ms 節流：連呼只出第一聲，隔夠久再出', () async {
    AppHaptics.tick();
    AppHaptics.tick();
    AppHaptics.tick();
    expect(vibrates, ['HapticFeedbackType.selectionClick']);
    await Future<void>.delayed(const Duration(milliseconds: 90));
    AppHaptics.tick();
    expect(vibrates, [
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.selectionClick',
    ]);
  });

  test('onPress 包裝：null 保持 null，非 null 先震再執行', () {
    expect(AppHaptics.onPress(null), isNull);
    var called = false;
    AppHaptics.onPress(() => called = true)!();
    expect(called, isTrue);
    expect(vibrates, ['HapticFeedbackType.mediumImpact']);
  });

  test('setEnabled 持久化，init 讀得回來', () async {
    await AppHaptics.setEnabled(false);
    expect(AppHaptics.enabled, isFalse);
    AppHaptics.enabled = true; // 模擬重啟前的殘留狀態
    await AppHaptics.init();
    expect(AppHaptics.enabled, isFalse);
  });
}
