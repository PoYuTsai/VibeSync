// Shared support for VibeSync scoped visual-proof screenshots.
//
// All design experimentation lives here — lib/ is NOT touched. "Before" renders
// the real shared warm-theme widgets; "After" renders the Calm* proof variants.
// If Eric/Bruce approve the direction from the screenshots, the Calm* knobs get
// folded into the real shared widgets as a follow-up.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads a real Traditional-Chinese face so headless renders aren't tofu.
/// Registered as 'AppTC'; harness wraps content in a DefaultTextStyle so the
/// app's family-less AppTypography styles inherit it (instead of test Ahem).
String _firstExistingPath(List<String> candidates) {
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  throw StateError('No visual proof asset found in: ${candidates.join(', ')}');
}

Future<void> loadProofFonts() async {
  final tc = File(_firstExistingPath(const [
    'C:/Windows/Fonts/NotoSansTC-VF.ttf',
    '/mnt/c/Windows/Fonts/NotoSansTC-VF.ttf',
  ])).readAsBytesSync();
  await (FontLoader('AppTC')..addFont(Future.value(ByteData.view(tc.buffer))))
      .load();
  // Material icons aren't auto-resolved headlessly once a global default font
  // is in play — load the real glyph font so icons aren't tofu.
  final mi = File(_firstExistingPath(const [
    'D:/tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    'D:/tools/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    '/home/eric1/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ])).readAsBytesSync();
  await (FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.view(mi.buffer))))
      .load();
}

/// iPhone 13/14-class logical canvas.
const Size kPhone = Size(390, 844);

Future<void> pumpAndCapture(
  WidgetTester tester, {
  required Widget child,
  required String outPath,
  Size size = kPhone,
  Duration settle = const Duration(milliseconds: 1500),
}) async {
  await tester.binding.setSurfaceSize(size);
  final rootKey = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'AppTC', useMaterial3: true),
      home: DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: 'AppTC'),
        child: RepaintBoundary(key: rootKey, child: child),
      ),
    ),
  );
  await tester.pump(settle); // advance any repeating animation to a still frame
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(rootKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    (File(outPath)..createSync(recursive: true))
        .writeAsBytesSync(data!.buffer.asUint8List());
  });
  await tester.binding.setSurfaceSize(null);
}

String outPath(String name) =>
    '${Directory.current.path}/build/visual_proof/$name';

// ---------------------------------------------------------------------------
// ProofTheme: the only thing that differs between before & after.
// ---------------------------------------------------------------------------

typedef CardBuilder = Widget Function({
  required Widget child,
  EdgeInsetsGeometry padding,
});

class ProofTheme {
  const ProofTheme({
    required this.label,
    required this.background,
    required this.card,
    required this.cardLow,
    required this.cta,
    required this.onBgPrimary,
    required this.onBgSecondary,
    required this.onCardPrimary,
    required this.onCardSecondary,
    required this.onCardHint,
    required this.accent,
    required this.appBarTitleColor,
  });

  final String label;
  final Widget Function(Widget child) background;
  final CardBuilder card; // primary tier — foreground
  final CardBuilder cardLow; // secondary tier — recedes one step
  final Widget Function(String text) cta;
  final Color onBgPrimary;
  final Color onBgSecondary;
  final Color onCardPrimary;
  final Color onCardSecondary;
  final Color onCardHint;
  final Color accent;
  final Color appBarTitleColor;
}
