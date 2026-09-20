import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/theme/opener_home_style.dart';
import 'package:vibesync/shared/widgets/brand/opener_entry_icon.dart';
import '../../../visual_proof/proof_support.dart';

void main() {
  setUpAll(loadProofFonts);
  testWidgets('entry artwork at production sizes', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 220));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final root = GlobalKey();
    await t.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'AppTC'),
      home: RepaintBoundary(
          key: root,
          child: Material(
            color: OpenerHomeStyle.panel,
            child: DefaultTextStyle.merge(
              style: const TextStyle(fontFamily: 'AppTC'),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final kind in OpenerEntryKind.values)
                    Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          OpenerEntryIcon(
                              kind: kind,
                              size: kind == OpenerEntryKind.photos ? 120 : 128),
                          const SizedBox(height: 16),
                          Text(
                              kind == OpenerEntryKind.photos ? '自介或照片' : '聊天對象',
                              style: OpenerHomeStyle.label),
                        ]),
                ],
              ),
            ),
          )),
    ));
    await t.pump();
    expect(t.takeException(), isNull);
    await t.runAsync(() async {
      final image = await t
          .renderObject<RenderRepaintBoundary>(find.byKey(root))
          .toImage(pixelRatio: 4);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      File('build/visual_proof/v3/icon-details.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(data!.buffer.asUint8List());
      image.dispose();
    });
  });
}
