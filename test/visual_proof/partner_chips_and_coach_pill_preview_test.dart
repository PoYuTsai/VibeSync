// 2026-08-19 Eric 真機回饋後的兩張設計預覽：
// 1) 對象設定 chips——對標「關於我」選取語言（未選中性框／已選橘框粗體）
// 2) 「看完整教練分析」——懸浮深墨膠囊（對標「跟到最新」）＋展開態
// 圖 2 的膠囊與展開容器樣式值 1:1 抄自 coach_surface._FullAnalysisTile
//（private 無法直接 pump），改 lib 記得同步這裡。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/theme/app_colors.dart';
import 'package:vibesync/core/theme/app_typography.dart';
import 'package:vibesync/features/partner/presentation/dialogs/partner_settings_dialog.dart';

import 'proof_support.dart';

/// family-null 的文字（如 BrandAlertDialog 的 titleTextStyle）在 headless
/// 會落到 Ahem 全豆腐——把同一顆 TC 字型再註冊成測試預設 family。
Future<void> _loadDefaultFamilyFont() async {
  final tc = File([
    '/usr/share/fonts/opentype/noto/NotoSansCJKtc-Regular.otf',
    '/mnt/c/Windows/Fonts/NotoSansTC-VF.ttf',
  ].firstWhere((p) => File(p).existsSync())).readAsBytesSync();
  await (FontLoader('Roboto')
        ..addFont(Future.value(ByteData.view(tc.buffer))))
      .load();
}

Widget _label(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 20),
      child: Text(
        text,
        style: AppTypography.bodySmall.copyWith(
          color: Colors.white70,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

Widget _pill() => FilledButton.icon(
      onPressed: () {},
      icon: const Icon(
        Icons.keyboard_double_arrow_down_rounded,
        size: 21,
        color: AppColors.ctaStart,
      ),
      label: Text(
        '看完整教練分析',
        style: AppTypography.caption.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
      style: FilledButton.styleFrom(
        minimumSize: const Size(124, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        backgroundColor: AppColors.brandInk.withValues(alpha: 0.96),
        foregroundColor: Colors.white,
        elevation: 9,
        shadowColor: Colors.black.withValues(alpha: 0.38),
        shape: StadiumBorder(
          side: BorderSide(color: AppColors.ctaStart.withValues(alpha: 0.62)),
        ),
      ),
    );

Widget _expandedReplica() => Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '對方一次回短不代表沒興趣，多半是在忙或當下沒特別想接。真正的判斷點是「連續幾輪」的模式，不是這一句。',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.glassTextPrimary,
              height: 1.5,
            ),
          ),
          Center(
            child: TextButton.icon(
              onPressed: () {},
              icon: const Icon(
                Icons.keyboard_arrow_up_rounded,
                size: 20,
                color: AppColors.primary,
              ),
              label: Text(
                '收起完整分析',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );

void main() {
  setUpAll(() async {
    await loadProofFonts();
    await _loadDefaultFamilyFont();
  });
  // flutter_test 預設把陰影畫成實心灰框（debugDisableShadows），預覽圖要看
  // 真實 elevation 陰影；framework 在測試 body 結束當下就驗 painting
  // invariant（比 tearDown 早），所以只能在 body 內 try/finally 還原。
  Future<void> withRealShadows(Future<void> Function() run) async {
    debugDisableShadows = false;
    try {
      await run();
    } finally {
      debugDisableShadows = true;
    }
  }

  testWidgets('對象設定 chips 預覽', (tester) async {
    await withRealShadows(() => pumpAndCapture(
          tester,
          outPath: outPath('partner_dialog_chips.png'),
          child: ColoredBox(
            color: AppColors.brandInk,
            child: Center(
              child: PartnerSettingsDialog(
                initialName: '安安嗯',
                // 預填三個片語 → 圖裡同時看得到「已選橘」與「未選中性」兩態。
                initialNote: '慢熱、回覆慢但都會回、愛喝咖啡',
              ),
            ),
          ),
        ));
  });

  testWidgets('看完整教練分析膠囊 預覽', (tester) async {
    await withRealShadows(() => pumpAndCapture(
      tester,
      outPath: outPath('coach_full_analysis_pill.png'),
      child: Material(
        type: MaterialType.transparency,
        child: ColoredBox(
        color: AppColors.brandInk,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label('收合態（放在建議卡淡紫底上）'),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.glassWhite,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '邊界提醒：不要把對方的回覆速度或長度直接等同於對你的興趣。',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.glassTextPrimary,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Center(child: _pill()),
                  ],
                ),
              ),
              _label('展開態'),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.glassWhite,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: _expandedReplica(),
              ),
            ],
          ),
        ),
        ),
      ),
    ));
  });
}
