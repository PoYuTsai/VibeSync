// 資產預覽 seam（對象卡互動階段閉環驗收 10）：開發／測試入口一次渲染
// 六個狀態（問號＋五階段），逐一斷言 asset path 與可見標籤，全程零網路、
// 零 AnalyzeChat 呼叫（純資料 widget，不碰 provider 與 HTTP client）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/report/presentation/screens/partner_stage_preview_screen.dart';

void main() {
  testWidgets('六狀態一次渲染：問號＋五張 stage 圖，asset path 與標籤逐一正確', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: PartnerStagePreviewScreen()),
    );
    await tester.pump();

    const expected = {
      '尚未分析': 'assets/images/partner_stage_unknown.webp',
      '破冰階段': 'assets/images/partner_stage_opening.webp',
      '建立男女感': 'assets/images/partner_stage_premise.webp',
      '互相評估': 'assets/images/partner_stage_qualification.webp',
      '展現個人魅力': 'assets/images/partner_stage_narrative.webp',
      '準備邀約': 'assets/images/partner_stage_close.webp',
    };

    for (final entry in expected.entries) {
      expect(find.text(entry.key), findsOneWidget,
          reason: '缺可見標籤 ${entry.key}');
      final image = tester.widget<Image>(
        find.byKey(ValueKey('stage-preview-${entry.value}')),
      );
      expect((image.image as AssetImage).assetName, entry.value);
      // 資產真的存在於 repo（載入不會豆腐）。
      expect(File(entry.value).existsSync(), isTrue,
          reason: '資產檔缺失：${entry.value}');
    }

    expect(find.byType(Image), findsNWidgets(6));
  });
}
