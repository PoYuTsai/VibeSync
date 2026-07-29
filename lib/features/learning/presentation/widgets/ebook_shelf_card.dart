// lib/features/learning/presentation/widgets/ebook_shelf_card.dart
//
// 書架卡：書號／icon、標題／副標、章節數與估計時間、完成度、權限 pill。
//
// 鎖定的卡仍然顯示完成度——降級前讀過的進度不該假裝不存在——但點擊只會導向
// paywall，不會打開內容。
//
// 權限用三態 [EbookAccessDecision] 而不是 bool：訂閱狀態「還在確認」或
// 「無法確認」時，顯示中性標籤並進入書籍目錄（由閘門處理 loading／重試），
// 不得顯示成「訂閱解鎖」或直接跳 paywall。
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
import 'ebook_access_gate.dart';
import 'ebook_cover_badge.dart';

class EbookShelfCard extends ConsumerWidget {
  const EbookShelfCard({
    super.key,
    required this.book,
    required this.decision,
  });

  final Ebook book;

  /// 三態而不是 bool：訂閱狀態「還在確認」或「無法確認」時，
  /// 既不能顯示成「訂閱解鎖」，也不能點一下就跳 paywall——那會把技術
  /// 不確定包裝成 Free upsell。這兩種狀態一律進書籍目錄，交給
  /// [EbookAccessGate] 顯示 loading 或可重試錯誤。
  final EbookAccessDecision decision;

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
        // 鎖著的書也進目錄頁（2026-07-26 Eric 拍板開放第一章試讀）：目錄頁
        // 的 EbookAccessGate 會走試讀分支，顯示可讀的第一章與其餘章的鎖，
        // paywall 由那裡的按鈕或鎖定章列進入，不在書架就攔掉。
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
              // pill 給上限寬：標籤最長的「Essential 解鎖」在窄幕＋大字級下
              // 改成整顆等比縮小，不把書名欄擠爆。正常字體下 120 綽綽有餘，
              // FittedBox 不會動它。
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: _AccessPill(book: book, decision: decision),
                ),
              ),
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
                decision == EbookAccessDecision.allowed
                    ? AppColors.ctaStart
                    : AppColors.onBackgroundSecondary.withValues(alpha: 0.45),
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
  const _AccessPill({required this.book, required this.decision});

  final Ebook book;
  final EbookAccessDecision decision;

  @override
  Widget build(BuildContext context) {
    // pill 是狀態徽章：字級夾住，極端字級下「Essential 解鎖」才不會把
    // 書名那欄整個擠掉。
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.4);
    switch (decision) {
      // 試讀開放第一章不改變「這本要訂閱」這件事，書架標籤維持訂閱字樣。
      case EbookAccessDecision.preview:
      case EbookAccessDecision.locked:
        // Essential 專屬書要標出級別：Starter 已經付過錢，看到泛用的
        // 「訂閱解鎖」會以為壞掉了。文案分流與目錄頁閘門一致。
        return _pill(
          scaler: scaler,
          icon: Icons.lock_outline,
          label: book.isEssentialOnly ? 'Essential 解鎖' : '訂閱解鎖',
          color: AppColors.brandBlush,
        );

      case EbookAccessDecision.resolving:
      case EbookAccessDecision.unavailable:
        // 中性標籤：狀態未確認時不宣稱這本要訂閱，也不宣稱已解鎖。
        return _pill(
          scaler: scaler,
          icon: Icons.sync_outlined,
          label: '確認訂閱中',
          color: AppColors.info,
        );

      case EbookAccessDecision.allowed:
        if (book.isFree) {
          return _pill(
            scaler: scaler,
            icon: Icons.lock_open_outlined,
            label: '免費',
            color: AppColors.success,
          );
        }
        return _pill(
          scaler: scaler,
          icon: Icons.workspace_premium_outlined,
          label: '已解鎖',
          color: AppColors.ctaStart,
        );
    }
  }

  Widget _pill({
    required IconData icon,
    required String label,
    required Color color,
    required TextScaler scaler,
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
            textScaler: scaler,
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
