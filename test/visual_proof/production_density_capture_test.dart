// Production still-frames for the 2026-06-10 layout-density fold.
//
// Unlike density_proof_test.dart (replica widgets, before/after comparison),
// this pumps the REAL lib/ screens so Eric/Bruce can eyeball exactly what
// ships. Run after any layout change to these screens:
//   flutter test test/visual_proof/production_density_capture_test.dart
// Out (build/visual_proof/):
//   prod_add_partner.png
//   prod_new_conversation_collapsed.png
//   prod_new_conversation_expanded.png
//   prod_new_conversation_partner_entry.png  (partnerId set — composer first)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/conversation/presentation/screens/new_conversation_screen.dart';
import 'package:vibesync/features/partner/presentation/screens/add_partner_screen.dart';

import 'proof_support.dart';

/// pumpAndCapture variant with an optional [interact] step between first
/// frame and capture (e.g. tap the settings expander).
Future<void> _captureScreen(
  WidgetTester tester, {
  required Widget screen,
  required String fileName,
  Size size = kPhone,
  Future<void> Function(WidgetTester)? interact,
}) async {
  await tester.binding.setSurfaceSize(size);
  final rootKey = GlobalKey();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Auth scope ready → CTA enabled, no「請先登入」notice in the shot.
        authConversationScopeProvider
            .overrideWith((ref) => Stream.value('u-proof')),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'AppTC', useMaterial3: true),
        home: DefaultTextStyle.merge(
          style: const TextStyle(fontFamily: 'AppTC'),
          child: RepaintBoundary(key: rootKey, child: screen),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 1500));
  if (interact != null) {
    await interact(tester);
    await tester.pump(const Duration(milliseconds: 300));
  }
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(rootKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    (File(outPath(fileName))..createSync(recursive: true))
        .writeAsBytesSync(data!.buffer.asUint8List());
  });
  await tester.binding.setSurfaceSize(null);
}

void main() {
  setUpAll(loadProofFonts);

  testWidgets('prod add_partner', (tester) async {
    await _captureScreen(
      tester,
      screen: const AddPartnerScreen(),
      fileName: 'prod_add_partner.png',
    );
  });

  testWidgets('prod new_conversation collapsed (legacy entry)', (tester) async {
    await _captureScreen(
      tester,
      screen: const NewConversationScreen(),
      fileName: 'prod_new_conversation_collapsed.png',
    );
  });

  testWidgets('prod new_conversation expanded (legacy entry)', (tester) async {
    await _captureScreen(
      tester,
      screen: const NewConversationScreen(),
      fileName: 'prod_new_conversation_expanded.png',
      size: const Size(390, 1400), // tall canvas so the expanded form fits
      interact: (t) => t.tap(find.text('這次分析設定（可不改）')),
    );
  });

  testWidgets('prod new_conversation from partner detail', (tester) async {
    await _captureScreen(
      tester,
      screen: const NewConversationScreen(partnerId: 'p-proof'),
      fileName: 'prod_new_conversation_partner_entry.png',
    );
  });
}
