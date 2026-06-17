// Visual proof for the shared brand UI primitives (Task A).
//
// Renders a gallery of every BrandKit primitive to a PNG so the暗紫橘質感
// can be eyeballed against the shipped 關於我/作戰板 reference before the rest
// of the screens are migrated onto these widgets.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/core/theme/app_colors.dart';
import 'package:vibesync/core/theme/app_typography.dart';
import 'package:vibesync/shared/widgets/brand/brand_kit.dart';

import 'proof_support.dart';

void main() {
  setUpAll(loadProofFonts);

  testWidgets('brand kit gallery capture', (tester) async {
    await pumpAndCapture(
      tester,
      size: const Size(390, 1180),
      child: BrandScaffold(
        title: '品牌元件',
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BrandSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const BrandSectionHeader(
                      title: '讓建議更像你',
                      subtitle: 'icon badge + 主層級漸層卡（elevated）。',
                      icon: Icons.tune_rounded,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'AI 會用這些設定調整語氣、練習方向與跟進建議，'
                      '不會替你假裝成另一個人。',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.onBackgroundSecondary
                            .withValues(alpha: 0.82),
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              BrandSurfaceCard(
                elevated: false,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const BrandSectionHeader(
                      title: '互動風格',
                      subtitle: '4px 豎條標題 + 次層級卡（elevated:false）+ chips。',
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        BrandChoiceChip(
                          label: '穩重',
                          selected: true,
                          onTap: () {},
                          trailing: const StyleRoleBadgePreview(text: '主'),
                        ),
                        BrandChoiceChip(
                            label: '幽默', selected: false, onTap: () {}),
                        BrandChoiceChip(
                            label: '溫柔', selected: false, onTap: () {}),
                        BrandChoiceChip(
                            label: '俏皮', selected: true, onTap: () {}),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              BrandSurfaceCard(
                elevated: false,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const BrandSectionHeader(title: '輸入框'),
                    const SizedBox(height: 12),
                    TextField(
                      style: AppTypography.bodyMedium
                          .copyWith(color: Colors.white),
                      decoration:
                          brandInputDecoration(hintText: '例如：日劇、週末探店'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const BrandInfoNote(
                text: '這些設定只用來讓建議更貼近你的語氣，不會顯示給任何對象。',
              ),
              const SizedBox(height: 18),
              BrandPrimaryButton(
                label: '儲存',
                icon: Icons.check_rounded,
                onPressed: () {},
              ),
              const SizedBox(height: 12),
              BrandSecondaryButton(
                label: '稍後再說',
                onPressed: () {},
              ),
              const SizedBox(height: 12),
              const BrandPrimaryButton(
                label: '載入中',
                isLoading: true,
                onPressed: null,
              ),
            ],
          ),
        ),
      ),
      outPath: outPath('brand_kit_gallery.png'),
    );
  });
}

/// Tiny 主/副 badge stand-in for the gallery (the real one lives in
/// profile_chip_section as StyleRoleBadge).
class StyleRoleBadgePreview extends StatelessWidget {
  const StyleRoleBadgePreview({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.ctaStart, AppColors.ctaEnd],
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: AppTypography.bodySmall.copyWith(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    );
  }
}
