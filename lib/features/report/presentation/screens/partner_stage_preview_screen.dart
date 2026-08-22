import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../analysis/domain/entities/game_stage.dart';
import '../widgets/partner_stage_assets.dart';

/// 六狀態資產預覽（開發／測試入口，零額度）：一次渲染問號＋五張 stage
/// 圖，逐一標示可見標籤。不呼叫 AnalyzeChat、不碰 provider 與網路——
/// 純資料 widget，用來在不燒額度的情況下驗收作戰板六種畫面。
/// 只掛在 kDebugMode 路由（見 routes.dart），不是正式功能入口。
class PartnerStagePreviewScreen extends StatelessWidget {
  const PartnerStagePreviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final entries = <({String label, String asset})>[
      (label: '尚未分析', asset: kPartnerStageUnknownAsset),
      for (final stage in GameStage.values)
        (label: stage.label, asset: partnerStageAssetFor(stage.label)),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('對象階段資產預覽')),
      body: GridView.count(
        crossAxisCount: 2,
        padding: const EdgeInsets.all(16),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        children: [
          for (final entry in entries)
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  entry.asset,
                  key: ValueKey('stage-preview-${entry.asset}'),
                  width: 96,
                  height: 96,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 8),
                Text(
                  entry.label,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.onBackgroundPrimary,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
