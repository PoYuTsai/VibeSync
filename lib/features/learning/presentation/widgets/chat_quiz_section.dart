// lib/features/learning/presentation/widgets/chat_quiz_section.dart
//
// 學習頁的「聊天測驗」區塊。
//
// 位置在 Practice Hero 之後、互動電子書之前（§11 決定 1）：電子書是讀的，
// 測驗是練的，練的東西放前面。
//
// 第 1 期只有入口卡：標題 ＋ 一句定位 ＋「全部關卡 →」。今日 3 題、弱點推薦、
// 各技能準確率、連續天數、錯題入口**全部是第 2 期**，這裡不畫。
//
// **這裡不放付費入口**：整個功能唯一的升級提示在關卡地圖那一列。
//
// 內容載入失敗時只讓這個區塊降級成錯誤卡，不影響同頁的電子書與 24 篇文章。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../data/providers/chat_quiz_providers.dart';
import '../../domain/models/chat_quiz.dart';

class ChatQuizSection extends ConsumerWidget {
  const ChatQuizSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(chatQuizCatalogProvider);

    return catalog.when(
      loading: () => const _QuizEntryCard(),
      error: (error, _) => const _QuizError(),
      data: (data) => _QuizEntryCard(catalog: data),
    );
  }
}

class _QuizEntryCard extends StatelessWidget {
  const _QuizEntryCard({this.catalog});

  final ChatQuizCatalog? catalog;

  @override
  Widget build(BuildContext context) {
    final levelCount = catalog?.allLevels.length;
    final questionCount = catalog?.allQuestions.length;

    return BrandSurfaceCard(
      onTap: () => context.push('/learning/quiz'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BrandIconBadge(icon: Icons.traffic_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '聊天測驗',
                      style: AppTypography.titleMedium.copyWith(
                        color: AppColors.onBackgroundPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '判讀訓練場',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.ctaStart,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '一次一題：先讀懂她現在是哪一種，再決定怎麼回。答錯不扣任何東西。',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (levelCount != null && questionCount != null)
                Expanded(
                  child: Text(
                    '$levelCount 關 · $questionCount 題',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.onBackgroundSecondary
                          .withValues(alpha: 0.85),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                const Spacer(),
              Text(
                '全部關卡 →',
                style: AppTypography.caption.copyWith(
                  color: AppColors.ctaStart,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuizError extends StatelessWidget {
  const _QuizError();

  @override
  Widget build(BuildContext context) {
    return BrandSurfaceCard(
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 18,
            color: AppColors.error.withValues(alpha: 0.9),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '聊天測驗暫時讀不到，其他內容不受影響。',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.onBackgroundSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
