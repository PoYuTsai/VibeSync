// 卡背靜態還原度錄製器（opt-in 工具，非回歸測試）。
//
// 設定 RECORD_CARDBACK=1 才會跑；平常 `flutter test` 全量會 skip。
//   RECORD_CARDBACK=1 flutter test test/tools/card_back_still_recorder_test.dart
// 單獨渲染 `debugCeremonyCardBack`（不跑整條儀式），逐 glow 截一張 PNG 到
// scratchpad/cardrep/still/，供與參考片卡背 side-by-side 目檢，做為快速 render→compare
// 迭代迴圈（比 240 幀全儀式錄製快得多）。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_draw_ceremony.dart';

const _outDir = '/tmp/claude-1000/-mnt-c-Users-eric1-OneDrive-Desktop-VibeSync/'
    'a7e2e299-8914-4fff-807b-49dd540a6cf8/scratchpad/cardrep/still';

const double _dpr = 3.0;

void main() {
  final record = Platform.environment['RECORD_CARDBACK'] == '1';

  testWidgets('record card back stills', (tester) async {
    final captureKey = GlobalKey();
    // 對齊 390×844 螢幕的揭曉卡尺寸。
    final size = practiceCeremonyCardSize(const Size(390, 844));

    await tester.binding.setSurfaceSize(const Size(420, 560));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final dir = Directory(_outDir);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);

    for (final glow in const [0.35, 0.6, 0.9]) {
      await tester.pumpWidget(
        MaterialApp(
          home: ColoredBox(
            // 暗紫舞台底，貼近儀式中段全暗背景。
            color: const Color(0xFF120A1F),
            child: Center(
              child: RepaintBoundary(
                key: captureKey,
                child: debugCeremonyCardBack(
                  width: size.width,
                  height: size.height,
                  glow: glow,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 32));

      await tester.runAsync(() async {
        final boundary = captureKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: _dpr);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final bytes = data!.buffer.asUint8List();
        final tag = (glow * 100).round();
        File('$_outDir/back_glow$tag.png')
            .writeAsBytesSync(Uint8List.fromList(bytes));
        image.dispose();
      });
    }

    final n = dir.listSync().whereType<File>().length;
    expect(n, 3);
    // ignore: avoid_print
    print('RECORDED $n card-back stills → $_outDir');
  }, skip: !record);
}
