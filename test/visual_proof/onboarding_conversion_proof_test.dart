// Visual proof for the onboarding conversion batches (Tier 1 + Tier 2 批 2):
// page 1 Sydney greeting hero / page 2 demo signal card / page 3 demo styles
// card / page 4 questionnaire (批 2) / page 5 privacy / page 6 branching page
// with Sydney encouragement. Renders the REAL OnboardingScreen and steps
// through all six pages so the batch can be eyeballed without waiting for a
// build.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/features/onboarding/presentation/screens/onboarding_screen.dart';

import 'proof_support.dart';

/// 同 chat_quiz proof：先載微軟正黑當 AppTC，單靠 loadProofFonts 的
/// fc-match 路徑在部分環境會整頁豆腐字。絕不寫死單一本機路徑。
Future<void> _loadFonts() async {
  for (final path in const [
    '/mnt/c/Windows/Fonts/msjh.ttc',
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
  ]) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    await (FontLoader('AppTC')
          ..addFont(Future.value(ByteData.view(bytes.buffer))))
        .load();
    break;
  }
  await loadProofFonts();
}

void main() {
  setUpAll(_loadFonts);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('onboarding conversion — all six pages', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final rootKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'AppTC', useMaterial3: true),
        home: DefaultTextStyle.merge(
          style: const TextStyle(fontFamily: 'AppTC'),
          child: RepaintBoundary(
            key: rootKey,
            child: const ProviderScope(child: OnboardingScreen()),
          ),
        ),
      ),
    );

    Future<void> settleAndDecode() async {
      await tester.pump(const Duration(milliseconds: 400));
      // 讓 Sydney PNG 在真 async 裡完成 decode，否則截圖是空框。
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 600)),
      );
      await tester.pump();
    }

    Future<void> capture(String name) async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(rootKey),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 3.0);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        (File(outPath(name))..createSync(recursive: true))
            .writeAsBytesSync(data!.buffer.asUint8List());
      });
    }

    await settleAndDecode();
    await capture('onboarding_page1.png');

    const pageMarkers = {
      2: '即時看懂她的訊號',
      3: '五種風格，選最對的那句',
      4: '30 秒，讓建議更像你',
      5: 'AI 與你的隱私',
      6: '你現在有正在聊的對象嗎？',
    };
    for (var page = 2; page <= 6; page++) {
      // 用真實使用者路徑（「下一步」按鈕）翻頁；390 寬畫布上 fling 的
      // 手勢競技場行為與 800 寬預設畫布不同，不可靠。
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      await settleAndDecode();
      expect(
        find.text(pageMarkers[page]!),
        findsOneWidget,
        reason: '應該已翻到第 $page 頁',
      );
      await capture('onboarding_page$page.png');
    }
  });
}
