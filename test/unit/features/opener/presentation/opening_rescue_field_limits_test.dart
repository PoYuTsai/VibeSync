// P3-1（Bruce opener 掃描）：手動輸入欄位過去無長度上限，超長 bio 會整段
// 字串插值進 server prompt（flat 3 額度、token 成本平台吸收）。server 端
// normalizeOpenerProfileInfo 已加權威截斷（name/meetingContext 200、
// bio/interests 2000）；這裡驗 client 鏡像上限（LengthLimitingTextInputFormatter，
// 無 counter UI、不擋操作）。認識場景是 chip 無自由文字，client 不需上限。
//
// Pump idiom 同 opener_brandkit_proof_test：initState → _reloadDrafts() 讀
// StorageService.settingsBox，開真實（空）Hive box；subscription 種子 free。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import 'package:vibesync/core/constants/app_constants.dart';
import 'package:vibesync/features/opener/presentation/screens/opening_rescue_screen.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';

class _SeededSubscriptionNotifier extends SubscriptionNotifier {
  _SeededSubscriptionNotifier(SubscriptionState seed) {
    state = seed;
  }
}

Widget _opener() => ProviderScope(
      overrides: [
        subscriptionProvider.overrideWith(
          (ref) => _SeededSubscriptionNotifier(
            const SubscriptionState(tier: SubscriptionTierHelper.free),
          ),
        ),
      ],
      child: const OpeningRescueScreen(),
    );

Future<void> _pumpManualTab(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 1180));
  await tester.pumpWidget(MaterialApp(home: _opener()));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.tap(find.text('手動輸入'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('opener_limits').path);
    if (!Hive.isBoxOpen(AppConstants.settingsBox)) {
      await Hive.openBox(AppConstants.settingsBox);
    }
  });

  tearDownAll(() async {
    await Hive.close();
  });

  testWidgets('名字欄位輸入超過 200 字元會被截斷在 200', (tester) async {
    await _pumpManualTab(tester);

    final nameField = find.byType(TextField).at(0);
    await tester.enterText(nameField, 'n' * 300);
    await tester.pump();

    final controller = tester.widget<TextField>(nameField).controller!;
    expect(controller.text.length, 200);
  });

  testWidgets('Bio 欄位輸入超過 2000 字元會被截斷在 2000', (tester) async {
    await _pumpManualTab(tester);

    final bioField = find.byType(TextField).at(1);
    await tester.enterText(bioField, 'b' * 2500);
    await tester.pump();

    final controller = tester.widget<TextField>(bioField).controller!;
    expect(controller.text.length, 2000);
  });

  testWidgets('興趣欄位輸入超過 2000 字元會被截斷在 2000', (tester) async {
    await _pumpManualTab(tester);

    final interestsField = find.byType(TextField).at(2);
    await tester.enterText(interestsField, 'i' * 2500);
    await tester.pump();

    final controller = tester.widget<TextField>(interestsField).controller!;
    expect(controller.text.length, 2000);
  });

  testWidgets('上限內的輸入不受影響', (tester) async {
    await _pumpManualTab(tester);

    final nameField = find.byType(TextField).at(0);
    await tester.enterText(nameField, '小美');
    await tester.pump();

    final controller = tester.widget<TextField>(nameField).controller!;
    expect(controller.text, '小美');
  });
}
