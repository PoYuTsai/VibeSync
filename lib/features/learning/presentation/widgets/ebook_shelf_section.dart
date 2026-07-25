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
        const BrandSectionHeader(
          title: '互動電子書',
          subtitle: '四本互動教材。先找到你真正的卡點，再只練那一段。',
          icon: Icons.menu_book_outlined,
        ),
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
                    locked: ebookLockedFor(book, access),
                  ),
                ),
            ],
          ),
        ),
      ],
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
