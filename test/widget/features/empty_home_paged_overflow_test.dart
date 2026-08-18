// test/widget/features/empty_home_paged_overflow_test.dart
//
// 首頁空態兩頁式排版的溢出迴歸：第一頁若鎖死高度，矮螢幕（812pt 機身）或
// iOS 字級調大時內容會溢出，_EmptyHead 的說明直接疊在 _EmptyTail 的說明上
// （release 無警告；2026-08 dogfood 疊字回報）。掃描多組高度×字級，斷言兩段
// 說明文字的矩形永不相交。預設測試畫布 600 高進不了兩頁分支（>620 門檻），
// 所以必須自訂 view size 才蓋得到這條路。
import 'dart:ui' show Size;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/partner/presentation/screens/partner_list_screen.dart';

import '../../helpers/home_screen_overrides.dart';

void main() {
  const line1 = 'VibeSync 會記得你和每個對象，幫你看懂互動，陪你練下一步。';
  const line2 = '一個人一張卡。不同日期、IG、LINE 或交友軟體的聊天，都整理在同一張卡裡。';

  Future<void> pumpAt(
    WidgetTester t, {
    required Size logicalSize,
    required double textScale,
  }) async {
    t.view.physicalSize = logicalSize;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        ...homeScreenSignalOverrides(),
        partnerListProvider.overrideWith((_) => const <Partner>[]),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: logicalSize,
            textScaler: TextScaler.linear(textScale),
          ),
          child: const Scaffold(body: PartnerListScreen()),
        ),
      ),
    ));
    await t.pumpAndSettle();
  }

  // 630＝剛過 620 門檻的最壞情況；740＝原本就塞得下的對照組。
  for (final height in [630.0, 660.0, 700.0, 740.0]) {
    for (final scale in [1.0, 1.15, 1.3]) {
      testWidgets('empty home paged: no text overlap @h=$height scale=$scale',
          (t) async {
        await pumpAt(t, logicalSize: Size(390, height), textScale: scale);
        final r1 = t.getRect(find.text(line1));
        final r2 = t.getRect(find.text(line2));
        expect(r1.overlaps(r2), isFalse,
            reason: '兩段說明文字疊在一起（h=$height, scale=$scale）——'
                '第一頁內容高過可用高度時必須長高而不是畫過去。');
      });
    }
  }
}
