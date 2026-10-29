// 卡背靜態錄製器（opt-in 工具，非回歸測試）。
//
// 設定 RECORD_CARDBACK=1 才會跑；平常 `flutter test` 全量會 skip。
//   RECORD_CARDBACK=1 flutter test test/tools/card_back_still_recorder_test.dart
// 單獨渲染 `debugCeremonyCardBack`（不跑整條儀式），用真的 v4 素材（典藏材質規格 §5.4）截 PNG 到
// build/card_back_stills/，供目檢、對照示意圖（tools/practice-card-material/concept_match.py）與
// 調色迭代：
// - back_{n,r,sr}.png：轉化完、光在左上、沒有額外發光（成品圖靜止的樣子，對照示意圖一）。
// - back_{n,r,sr}_charged.png：翻牌起手那一刻（蓄力的徽記光還在）。
// - back_{n,r,sr}_tilt.png：翻牌前的回拉（yaw −25°）：高光帶滑到右下、浮雕補光換邊。
// - back_r_wipe.png、back_sr_wipe.png：轉化擴散到四成（R0＋612、R0＋865：擴散用 `enter` 曲線，
//   染色那一段的前 10% 就走到四成）。
// - back_fallback.png：素材還沒解好的退路（§6.8）。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_rarity.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_card_material.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_draw_ceremony.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_reveal_timing.dart';

final _outDir = '${Directory.current.path}/build/card_back_stills';

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

    Future<void> shoot(String name, Widget back) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ColoredBox(
            // 暗紫舞台底，貼近儀式中段全暗背景。
            color: const Color(0xFF120A1F),
            child: Center(child: RepaintBoundary(key: captureKey, child: back)),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 32));
      await tester.runAsync(() async {
        final boundary = captureKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: _dpr);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$_outDir/$name.png')
            .writeAsBytesSync(Uint8List.fromList(data!.buffer.asUint8List()));
        image.dispose();
      });
    }

    await shoot(
      'back_fallback',
      debugCeremonyCardBack(width: size.width, height: size.height),
    );
    // 素材真的解碼好（解成卡片實際像素寬，同儀式）才截圖。
    final ctx = tester.element(find.byKey(captureKey));
    final images = (await tester.runAsync(
      () => debugLoadCardMaterial(
        createLocalImageConfiguration(ctx),
        cardPixelWidth: (size.width * _dpr).ceil(),
      ),
    ))!;
    for (final slot in PracticeCardMaterialSlot.values) {
      expect(images[slot], isNotNull, reason: slot.asset);
    }

    for (final rarity in PracticeGirlRarity.values) {
      final tag = rarity.label.toLowerCase();
      Widget back({
        double ms = PracticeRevealTiming.flipStartMs,
        double yaw = PracticeRevealTiming.waitingYaw,
        PracticeCardBackEnergy? energy,
      }) =>
          debugCeremonyCardBack(
            width: size.width,
            height: size.height,
            rarity: rarity,
            images: images,
            ms: ms,
            yawDeg: yaw,
            energy: energy,
          );
      await shoot('back_$tag', back(energy: PracticeCardBackEnergy.none));
      await shoot('back_${tag}_charged', back());
      await shoot('back_${tag}_tilt', back(yaw: -25));
    }
    await shoot(
      'back_r_wipe',
      debugCeremonyCardBack(
        width: size.width,
        height: size.height,
        rarity: PracticeGirlRarity.r,
        images: images,
        ms: 612,
      ),
    );
    await shoot(
      'back_sr_wipe',
      debugCeremonyCardBack(
        width: size.width,
        height: size.height,
        rarity: PracticeGirlRarity.sr,
        images: images,
        ms: 865,
      ),
    );

    final n = dir.listSync().whereType<File>().length;
    expect(n, 12);
    // ignore: avoid_print
    print('RECORDED $n card-back stills → $_outDir');
  }, skip: !record);
}
