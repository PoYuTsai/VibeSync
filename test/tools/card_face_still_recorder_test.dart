// 卡面靜態錄製器（opt-in 工具，非回歸測試）。
//
// 設定 RECORD_CARDFACE=1 才會跑；平常 `flutter test` 全量會 skip。
//   RECORD_CARDFACE=1 flutter test test/tools/card_face_still_recorder_test.dart
// 單獨渲染 `debugCeremonyCardFront`（停住的樣子、新角色掛 NEW，不跑整條儀式），
// N／R／SR 各截一張 PNG 到 build/card_face_stills/，給材質對照與改前改後比較用
// （規格 docs/plans/2026-10-28-card-collectible-material-spec.md §15 Gate-2b）。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_catalog.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_draw_ceremony.dart';

final _outDir = '${Directory.current.path}/build/card_face_stills';

const double _dpr = 3.0;

// 繁中字型與 Material 圖示：同 ceremony_preview_recorder_test.dart 的候選順序。
const _cjkFontCandidates = <String>[
  'C:/Windows/Fonts/NotoSansTC-VF.ttf',
  'C:/Windows/Fonts/msjh.ttc',
  '/mnt/c/Windows/Fonts/NotoSansTC-VF.ttf',
  '/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc',
  '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
];
const _materialIconsFontCandidates = <String>[
  'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
  'D:/tools/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
];

Future<void> _loadFirstAvailableFont(
  String family,
  List<String> candidates,
) async {
  for (final fontPath in candidates) {
    final font = File(fontPath);
    if (!font.existsSync()) continue;
    final fontBytes = font.readAsBytesSync();
    await (FontLoader(family)
          ..addFont(Future.value(ByteData.view(fontBytes.buffer))))
        .load();
    return;
  }
}

void main() {
  final record = Platform.environment['RECORD_CARDFACE'] == '1';

  // 錨點與 catalog 指定同步：001=N、010=R、004=SR（同揭曉錄製器）。
  final girls = {
    'n': practiceGirlProfiles.first,
    'r': practiceGirlProfiles[9],
    'sr': practiceGirlProfiles[3],
  };

  testWidgets('record card face stills', (tester) async {
    final captureKey = GlobalKey();
    // 對齊 390×844 螢幕的揭曉卡尺寸；舞台比卡片大一圈，留給外光與牌。
    final size = practiceCeremonyCardSize(const Size(390, 844));
    final stage = Size(size.width + 48, size.height + 48);

    await _loadFirstAvailableFont('NotoTC', _cjkFontCandidates);
    await _loadFirstAvailableFont(
      'MaterialIcons',
      _materialIconsFontCandidates,
    );
    tester.view.physicalSize = stage * _dpr;
    tester.view.devicePixelRatio = _dpr;
    addTearDown(tester.view.reset);

    final dir = Directory(_outDir);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);

    for (final MapEntry(key: tag, value: girl) in girls.entries) {
      expect(girl.rarity.label.toLowerCase(), tag); // 錨點保險
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'NotoTC'),
          home: Material(
            // 揭曉停住時的暗化底色附近；Material 提供預設字樣（字型才吃得到主題）。
            color: const Color(0xFF0B0A12),
            child: Center(
              child: RepaintBoundary(
                key: captureKey,
                child: SizedBox(
                  width: stage.width,
                  height: stage.height,
                  child: Center(
                    child: debugCeremonyCardFront(
                      girl: girl,
                      width: size.width,
                      height: size.height,
                      isNew: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      // 照片真的解碼好，截圖才有圖。
      final ctx = tester.element(find.byKey(captureKey));
      await tester.runAsync(() async {
        await precacheImage(AssetImage(girl.photoAssetPath), ctx);
      });
      await tester.pump(const Duration(milliseconds: 32));

      await tester.runAsync(() async {
        final boundary = captureKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: _dpr);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$_outDir/face_$tag.png')
            .writeAsBytesSync(data!.buffer.asUint8List());
        image.dispose();
      });
    }
  }, skip: !record);
}
