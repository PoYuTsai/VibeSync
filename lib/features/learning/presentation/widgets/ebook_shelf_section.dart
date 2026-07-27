// lib/features/learning/presentation/widgets/ebook_shelf_section.dart
//
// 學習頁的「互動電子書」區塊。
//
// 位置在 Practice Hero 之後、短篇文章之前。這裡刻意不顯示任何文章每日額度提示：
// 電子書不消耗文章額度，把額度文案放在書架上方會造成錯誤聯想。
//
// 內容載入失敗時只讓這個區塊降級成錯誤卡，不影響同頁的 24 篇文章。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../data/providers/ebook_providers.dart';
import '../../domain/models/ebook.dart';
import 'ebook_access_gate.dart';
import 'ebook_shelf_card.dart';

class EbookShelfSection extends ConsumerWidget {
  const EbookShelfSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(ebookCatalogProvider);
    final access = ref.watch(ebookSubscriptionAccessProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 「互動電子書」那一列拿掉（2026-07-27 Eric）：標題卡自己就說得清楚，
        // 多一列只是佔高度。
        const _ShelfHero(),
        const SizedBox(height: 12),
        catalog.when(
          loading: () => const _ShelfPlaceholder(),
          error: (error, _) => const _ShelfError(),
          data: (catalog) => Column(
            children: [
              for (final book in catalog.books)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: EbookShelfCard(
                    book: book,
                    decision: ebookAccessFor(book, access),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 書架上方的標題卡。
///
/// 2026-07-27 夥伴回饋：原本只有「互動電子書」四個字＋一行說明，看不出這是
/// 一整套教材。標題與導言直接沿用他原檔的用字（THE FIELD GUIDE／交友軟體
/// 實戰 · 終極指引），四本書是那份指引拆出來的。
class _ShelfHero extends StatelessWidget {
  const _ShelfHero();

  @override
  Widget build(BuildContext context) {
    return BrandSurfaceCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BrandIconBadge(icon: Icons.menu_book_outlined, size: 26,
                  iconSize: 14),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  kEbookCollectionKicker,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.ctaStart,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 標題與品牌點刻意分成兩段：字級大時「·」才不會被換行拆到下一行開頭。
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: '交友軟體實戰'),
                TextSpan(
                  text: ' · ',
                  style: TextStyle(
                    color: AppColors.brandBlush.withValues(alpha: 0.9),
                  ),
                ),
                const TextSpan(text: '終極指引'),
              ],
            ),
            style: AppTypography.headlineLarge.copyWith(
              color: AppColors.onBackgroundPrimary,
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '從配對到把她約出來。先診斷你卡在哪一階，只練那一階'
            '——這是報酬率最高的事。',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.85),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShelfPlaceholder extends StatelessWidget {
  const _ShelfPlaceholder();

  @override
  Widget build(BuildContext context) {
    return BrandSurfaceCard(
      elevated: false,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.ctaStart),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '正在載入電子書…',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShelfError extends StatelessWidget {
  const _ShelfError();

  @override
  Widget build(BuildContext context) {
    return BrandSurfaceCard(
      elevated: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline,
              size: 18, color: AppColors.error.withValues(alpha: 0.9)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '電子書內容暫時無法載入。下面的短篇文章仍然可以閱讀。',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.onBackgroundSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
