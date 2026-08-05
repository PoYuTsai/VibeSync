// Visual proof for the low-risk entry screens migrated onto BrandKit (Task B).
// Renders each screen to a PNG so the暗紫橘統一 can be eyeballed against the
// shipped 關於我/作戰板 reference.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/conversation/presentation/screens/new_conversation_screen.dart';
import 'package:vibesync/features/partner/presentation/screens/add_partner_screen.dart';

import 'proof_support.dart';

void main() {
  setUpAll(loadProofFonts);

  testWidgets('add partner capture', (tester) async {
    await pumpAndCapture(
      tester,
      child: ProviderScope(
        overrides: [
          authConversationScopeProvider.overrideWith(
            (ref) => Stream.value('u-proof'),
          ),
        ],
        child: const AddPartnerScreen(),
      ),
      outPath: outPath('add_partner.png'),
    );
  });

  // NewConversation needs interaction (expand settings + add a message) to show
  // the segmented buttons + message list, so it uses a manual capture flow
  // rather than the one-shot pumpAndCapture.
  testWidgets('new conversation capture (expanded)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1280));
    final rootKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'AppTC', useMaterial3: true),
        home: DefaultTextStyle.merge(
          style: const TextStyle(fontFamily: 'AppTC'),
          child: RepaintBoundary(
            key: rootKey,
            child: const ProviderScope(child: NewConversationScreen()),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    // Type a「her」message into the composer, then expand the analysis
    // settings so the BrandSegmentedButtons render in the capture.
    await tester.enterText(find.byType(TextField).at(1), '你也喜歡爬山嗎？');
    await tester.pump();
    await tester.tap(find.text('這次分析設定（可不改）'));
    await tester.pump(const Duration(milliseconds: 400));

    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(rootKey));
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      (File(outPath('new_conversation.png'))..createSync(recursive: true))
          .writeAsBytesSync(data!.buffer.asUint8List());
    });
    await tester.binding.setSurfaceSize(null);
  });
}
