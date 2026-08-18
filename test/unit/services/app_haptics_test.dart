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
    await AppHaptics.success();
    await AppHaptics.failure();
    expect(vibrates, isEmpty);
  });

  test('強度階梯對應正確的系統觸覺', () {
    AppHaptics.tap();
    AppHaptics.light();
    AppHaptics.medium();
    expect(vibrates, [
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.mediumImpact',
    ]);
  });

  test('答對是輕→中兩下、答錯是中×2', () async {
    await AppHaptics.success();
    expect(vibrates, [
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.mediumImpact',
    ]);
    vibrates.clear();
    await AppHaptics.failure();
    expect(vibrates, [
      'HapticFeedbackType.mediumImpact',
      'HapticFeedbackType.mediumImpact',
    ]);
  });

  test('setEnabled 持久化，init 讀得回來', () async {
    await AppHaptics.setEnabled(false);
    expect(AppHaptics.enabled, isFalse);
    AppHaptics.enabled = true; // 模擬重啟前的殘留狀態
    await AppHaptics.init();
    expect(AppHaptics.enabled, isFalse);
  });
}
