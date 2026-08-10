// 去 slop 第一批對照 proof：
// 1) B4 Collection hero 標題——漸層文字（before）vs 純白 w900（after）
// 2) B1 主 CTA 字色——白字（現況）vs brandInk 深墨字（提案，等 Eric 拍板）
// 兩組各出一張上下對照 PNG。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/theme/app_colors.dart';
import 'package:vibesync/core/theme/app_typography.dart';

import 'proof_support.dart';

Widget _collectionHero({required bool gradient}) {
  final title = Text(
    'Collection',
    style: AppTypography.headlineLarge.copyWith(
      color: gradient ? Colors.white : Colors.white,
      fontSize: 40,
      fontWeight: FontWeight.w900,
      height: 1.05,
    ),
  );
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'VIBESYNC · GACHA',
        style: AppTypography.caption.copyWith(
          color: AppColors.brandFlame,
          fontWeight: FontWeight.w700,
          letterSpacing: 3,
        ),
      ),
      const SizedBox(height: 6),
      if (gradient)
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => const LinearGradient(
            colors: [
              Color(0xFFFFC24D),
              AppColors.brandFlame,
              AppColors.brandBlush,
            ],
          ).createShader(bounds),
          child: title,
        )
      else
        title,
    ],
  );
}

Widget _ctaButton({required Color labelColor, required String caption}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        caption,
        style: AppTypography.caption.copyWith(
          color: AppColors.onBackgroundSecondary,
        ),
      ),
      const SizedBox(height: 8),
      Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.ctaStart, AppColors.ctaEnd],
          ),
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.38),
              blurRadius: 18,
              offset: const Offset(0, 9),
            ),
          ],
        ),
        child: Center(
          child: Text(
            '立即解鎖完整功能',
            style: AppTypography.titleSmall.copyWith(
              color: labelColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    ],
  );
}

Widget _section(String label, Widget child) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: AppTypography.labelMedium.copyWith(
          color: Colors.white.withValues(alpha: 0.6),
        ),
      ),
      const SizedBox(height: 10),
      child,
    ],
  );
}

Widget _sectionHeaderDemo({required double barWidth}) {
  return Row(
    children: [
      Container(
        width: barWidth,
        height: 18,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.ctaStart, AppColors.brandBlush],
          ),
          borderRadius: BorderRadius.circular(99),
        ),
      ),
      const SizedBox(width: 10),
      Text(
        '互動風格',
        style: AppTypography.titleSmall.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

void main() {
  setUpAll(loadProofFonts);

  testWidgets('capture B2 section header bar comparison', (tester) async {
    await pumpAndCapture(
      tester,
      size: const Size(390, 560),
      child: Material(
        color: AppColors.brandInk,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _section('BEFORE：4px 粗條（實際大小）',
                  _sectionHeaderDemo(barWidth: 4)),
              const SizedBox(height: 24),
              _section('AFTER：2px 細條（實際大小）',
                  _sectionHeaderDemo(barWidth: 2)),
              const SizedBox(height: 40),
              _section(
                '放大 3 倍看差別',
                Row(
                  children: [
                    Transform.scale(
                      scale: 3,
                      alignment: Alignment.topLeft,
                      child: _sectionHeaderDemo(barWidth: 4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 80),
              Transform.scale(
                scale: 3,
                alignment: Alignment.topLeft,
                child: _sectionHeaderDemo(barWidth: 2),
              ),
            ],
          ),
        ),
      ),
      outPath: outPath('compare_b2_section_bar.png'),
    );
  });

  testWidgets('capture B3 shadow zoom comparison', (tester) async {
    Widget button({required BoxShadow shadow}) {
      return Container(
        width: 220,
        height: 44,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.ctaStart, AppColors.ctaEnd],
          ),
          borderRadius: BorderRadius.circular(999),
          boxShadow: [shadow],
        ),
        child: Center(
          child: Text(
            '✓ 儲存',
            style: AppTypography.titleSmall.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
    }

    await pumpAndCapture(
      tester,
      size: const Size(390, 620),
      child: Material(
        color: AppColors.brandInk,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _section(
                'BEFORE：橘色光暈（放大 1.6 倍）',
                Padding(
                  padding: const EdgeInsets.only(left: 60, top: 30),
                  child: Transform.scale(
                    scale: 1.6,
                    child: button(
                      shadow: BoxShadow(
                        color: AppColors.ctaStart.withValues(alpha: 0.30),
                        blurRadius: 18,
                        offset: const Offset(0, 9),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 90),
              _section(
                'AFTER：中性黑影（放大 1.6 倍）',
                Padding(
                  padding: const EdgeInsets.only(left: 60, top: 30),
                  child: Transform.scale(
                    scale: 1.6,
                    child: button(
                      shadow: BoxShadow(
                        color: Colors.black.withValues(alpha: 0.38),
                        blurRadius: 18,
                        offset: const Offset(0, 9),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      outPath: outPath('compare_b3_shadow_zoom.png'),
    );
  });

  testWidgets('capture B4 collection title and B1 CTA label comparisons',
      (tester) async {
    await pumpAndCapture(
      tester,
      size: const Size(390, 500),
      child: Material(
        color: AppColors.brandInk,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _section('BEFORE：漸層文字', _collectionHero(gradient: true)),
              const SizedBox(height: 32),
              _section('AFTER：純白 w900（對標書架 hero）',
                  _collectionHero(gradient: false)),
            ],
          ),
        ),
      ),
      outPath: outPath('compare_b4_collection_title.png'),
    );

    await pumpAndCapture(
      tester,
      size: const Size(390, 420),
      child: Material(
        color: AppColors.brandInk,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ctaButton(
                labelColor: Colors.white,
                caption: '現況：白字（對比 2.86:1，戶外強光弱）',
              ),
              const SizedBox(height: 28),
              _ctaButton(
                labelColor: AppColors.brandInk,
                caption: '提案：深墨字 brandInk（對比 6.62:1）',
              ),
            ],
          ),
        ),
      ),
      outPath: outPath('compare_b1_cta_label.png'),
    );
  });
}
