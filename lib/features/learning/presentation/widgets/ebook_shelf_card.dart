// lib/features/learning/presentation/widgets/ebook_shelf_card.dart
//
// 書架卡：書號／icon、標題／副標、章節數與估計時間、完成度、免費或鎖定 pill。
//
// 鎖定的卡仍然顯示完成度——降級前讀過的進度不該假裝不存在——但點擊只會導向
// paywall，不會打開內容。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../data/providers/ebook_providers.dart';
import '../../domain/models/ebook.dart';
import '../screens/ebook_detail_screen.dart';
import 'ebook_cover_badge.dart';

class EbookShelfCard extends ConsumerWidget {
  const EbookShelfCard({
    super.key,
    required this.book,
    required this.locked,
  });

  final Ebook book;
  final bool locked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(ebookBookProgressProvider(book.id));
    final completed = book.chapters
        .where((chapter) => progress.isChapterCompleted(chapter.id))
        .length;
    final ratio = book.chapterCount <= 0 ? 0.0 : completed / book.chapterCount;

    return BrandSurfaceCard(
      padding: const EdgeInsets.all(14),
      borderRadius: 20,
      onTap: () {
        if (locked) {
          context.push('/paywall');
          return;
        }
        context.push(ebookDetailRoute(book.id));
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EbookCoverBadge(book: book, size: 50),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      style: AppTypography.titleSmall.copyWith(
                        color: AppColors.onBackgroundPrimary,
                        fontWeight: FontWeight.w800,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      book.subtitle,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.onBackgroundSecondary
                            .withValues(alpha: 0.78),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _AccessPill(book: book, locked: locked),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _MetaText(text: '${book.chapterCount} 章'),
              _MetaText(text: '約 ${book.estimatedMinutes} 分鐘'),
              _MetaText(text: '已完成 $completed／${book.chapterCount} 章'),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 5,
              backgroundColor: AppColors.brandInk.withValues(alpha: 0.6),
              valueColor: AlwaysStoppedAnimation<Color>(
                locked
                    ? AppColors.onBackgroundSecondary.withValues(alpha: 0.45)
                    : AppColors.ctaStart,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaText extends StatelessWidget {
  const _MetaText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTypography.caption.copyWith(
        color: AppColors.onBackgroundSecondary.withValues(alpha: 0.68),
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _AccessPill extends StatelessWidget {
  const _AccessPill({required this.book, required this.locked});

  final Ebook book;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    if (locked) {
      return _pill(
        icon: Icons.lock_outline,
        label: '訂閱解鎖',
        color: AppColors.brandBlush,
      );
    }
    if (book.isFree) {
      return _pill(
        icon: Icons.lock_open_outlined,
        label: '免費',
        color: AppColors.success,
      );
    }
    return _pill(
      icon: Icons.workspace_premium_outlined,
      label: '已解鎖',
      color: AppColors.ctaStart,
    );
  }

  Widget _pill({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
