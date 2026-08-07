// lib/features/learning/presentation/screens/ebook_detail_screen.dart
//
// 書籍目錄頁：封面、書籍說明、總完成度、開始／繼續閱讀、章節清單。
//
// 約束：
//   - 完成章節用 icon＋文字標示，不只靠顏色。
//   - unknown book 顯示「找不到這本書」與返回學習頁 CTA（不導 paywall）。
//   - premium 內容一定在 EbookAccessGate 之後才建立。
//   - 直接 deep link 沒有可 pop 的 route 時，返回鍵回 `/?tab=learning`。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../data/providers/ebook_providers.dart';
import '../../domain/ebook_reading_position.dart';
import '../../domain/models/ebook.dart';
import '../widgets/ebook_access_gate.dart';
import '../widgets/ebook_cover_badge.dart';

/// 章節閱讀路由。集中在這裡組字串，避免各處拼錯。
///
/// [entryId] 是交叉指涉用的定位點：帶著它進閱讀器，目標條目會自動展開並捲到
/// 畫面上。用 query 而非路徑段，是因為它是可有可無的定位，不是資源身分。
String ebookChapterRoute(String bookId, String chapterId, {String? entryId}) {
  final base = '/learning/books/$bookId/chapters/$chapterId';
  if (entryId == null || entryId.isEmpty) return base;
  return '$base?entry=${Uri.encodeQueryComponent(entryId)}';
}

String ebookDetailRoute(String bookId) => '/learning/books/$bookId';

class EbookDetailScreen extends ConsumerWidget {
  const EbookDetailScreen({super.key, required this.bookId});

  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(ebookCatalogProvider);

    return catalog.when(
      loading: () => const _DetailLoading(),
      error: (error, _) => _DetailContentError(error: error),
      data: (catalog) => EbookAccessGate(
        book: catalog.findBook(bookId),
        builder: (context) => _EbookDetailBody(
          book: catalog.findBook(bookId)!,
        ),
        // 未訂閱者看有試讀章的書：可讀第一章，其餘章顯示鎖並導 paywall。
        previewBuilder: (context) => _EbookDetailBody(
          book: catalog.findBook(bookId)!,
          mode: EbookDetailMode.preview,
        ),
        // 沒有試讀章的付費書（第 3、4 本）：目錄仍然看得到，每一章都上鎖。
        lockedBuilder: (context) => _EbookDetailBody(
          book: catalog.findBook(bookId)!,
          mode: EbookDetailMode.locked,
        ),
      ),
    );
  }
}

class _DetailLoading extends StatelessWidget {
  const _DetailLoading();

  @override
  Widget build(BuildContext context) {
    return const BrandScaffold(
      title: kEbookCollectionTitle,
      body: Center(
        child: CircularProgressIndicator(
          strokeWidth: 2.6,
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.ctaStart),
        ),
      ),
    );
  }
}

class _DetailContentError extends StatelessWidget {
  const _DetailContentError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return BrandScaffold(
      title: kEbookCollectionTitle,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const BrandIconBadge(
                icon: Icons.error_outline,
                size: 48,
                iconSize: 24,
              ),
              const SizedBox(height: 16),
              Text(
                '電子書內容載入失敗',
                style: AppTypography.titleMedium.copyWith(
                  color: AppColors.onBackgroundPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '內容檔案讀取時出了問題，我們會修。先回學習頁看看其他內容。',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.onBackgroundSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              BrandPrimaryButton(
                label: '回學習頁',
                onPressed: () => context.go('/?tab=learning'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 目錄頁的三種模式。
enum EbookDetailMode {
  /// 可讀：整本都能點。
  full,

  /// 有試讀章的付費書：第一章可點，其餘章上鎖。
  preview,

  /// 沒有試讀章的付費書：目錄看得到，每一章都上鎖。
  locked,
}

class _EbookDetailBody extends ConsumerWidget {
  const _EbookDetailBody({
    required this.book,
    this.mode = EbookDetailMode.full,
  });

  final Ebook book;
  final EbookDetailMode mode;

  bool get isPreview => mode == EbookDetailMode.preview;
  bool get isLocked => mode == EbookDetailMode.locked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(ebookBookProgressProvider(book.id));
    final completed = book.chapters
        .where((chapter) => progress.isChapterCompleted(chapter.id))
        .length;
    final started = ebookHasStarted(book, progress);
    final resumeChapterId = resolveResumeChapterId(book, progress);

    return BrandScaffold(
      title: kEbookCollectionTitle,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () {
          // 直接 deep link 進來時沒有可 pop 的 route，退回學習頁而不是退出 App。
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/?tab=learning');
          }
        },
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          BrandSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    EbookCoverBadge(book: book),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            book.title,
                            style: AppTypography.titleLarge.copyWith(
                              color: AppColors.onBackgroundPrimary,
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            book.subtitle,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.onBackgroundSecondary
                                  .withValues(alpha: 0.82),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  book.goal,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.onBackgroundSecondary,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MetaPill(
                      icon: Icons.auto_stories_outlined,
                      label: '${book.chapterCount} 章',
                    ),
                    _MetaPill(
                      icon: Icons.schedule,
                      label: '約 ${book.estimatedMinutes} 分鐘',
                    ),
                    _MetaPill(
                      icon: book.isFree
                          ? Icons.lock_open_outlined
                          : Icons.workspace_premium_outlined,
                      label: book.isFree ? '免費' : '訂閱內容',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (isPreview)
            _PreviewNoticeCard(
              lockedChapterCount:
                  book.chapterCount - book.freePreviewChapterCount,
            )
          else if (isLocked)
            _LockedNoticeCard(isEssentialOnly: book.isEssentialOnly)
          else
            _CompletionCard(
              completed: completed,
              total: book.chapterCount,
            ),
          const SizedBox(height: 14),
          if (isLocked)
            BrandPrimaryButton(
              label: '訂閱後解鎖',
              icon: Icons.workspace_premium_outlined,
              onPressed: () => context.push('/paywall'),
            )
          else if (isPreview) ...[
            BrandPrimaryButton(
              label: '免費試讀第一章',
              icon: Icons.auto_stories,
              onPressed: () => context.push(
                ebookChapterRoute(
                  book.id,
                  book.previewChapterId ?? book.chapters.first.id,
                ),
              ),
            ),
            const SizedBox(height: 10),
            BrandSecondaryButton(
              label: '看訂閱方案',
              onPressed: () => context.push('/paywall'),
            ),
          ] else
            BrandPrimaryButton(
              label: started ? '繼續閱讀' : '開始閱讀',
              icon: started ? Icons.play_arrow_rounded : Icons.auto_stories,
              onPressed: () => context.push(
                ebookChapterRoute(book.id, resumeChapterId),
              ),
            ),
          const SizedBox(height: 24),
          const BrandSectionHeader(
            title: '章節',
            subtitle: '每章只回答一個問題，讀完帶走一個可以練的動作。',
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < book.chapters.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ChapterRow(
                book: book,
                chapter: book.chapters[index],
                isCompleted:
                    progress.isChapterCompleted(book.chapters[index].id),
                isResumeTarget: mode == EbookDetailMode.full &&
                    book.chapters[index].id == resumeChapterId,
                isLocked: isLocked ||
                    (isPreview &&
                        !book.isPreviewChapter(book.chapters[index].id)),
              ),
            ),
        ],
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 13,
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.85)),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.88),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompletionCard extends StatelessWidget {
  const _CompletionCard({required this.completed, required this.total});

  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final ratio = total <= 0 ? 0.0 : completed / total;
    return BrandSurfaceCard(
      elevated: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events_outlined,
                  size: 16, color: AppColors.ctaStart),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  // 「完成度」與閱讀器裡的「位置進度」是兩件事，標籤刻意不同。
                  '完成度',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.ctaStart,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '已完成 $completed / $total 章',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.onBackgroundSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: AppColors.brandInk.withValues(alpha: 0.6),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.ctaStart),
            ),
          ),
        ],
      ),
    );
  }
}

/// 試讀說明卡。取代完成度卡：試讀時顯示「已完成 0 / 5 章」只會讓人以為
/// 整本都能讀。
/// 沒有試讀章的付費書：說清楚免費範圍到哪，不讓人以為這本也有第一章可讀。
class _LockedNoticeCard extends StatelessWidget {
  const _LockedNoticeCard({required this.isEssentialOnly});

  /// 《成為獎賞》三冊（第 5–7 冊）是 Essential 專屬，鎖卡文案要能把
  /// Essential 的多 3 冊賣出來，也不能對 Starter 謊稱「訂閱就全開」。
  final bool isEssentialOnly;

  @override
  Widget build(BuildContext context) {
    return BrandSurfaceCard(
      elevated: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(right: 8, top: 1),
            child: Icon(Icons.lock_outline,
                size: 16, color: AppColors.brandBlush),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '訂閱內容',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.brandBlush,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isEssentialOnly
                      ? '《成為獎賞》三冊是 Essential 方案專屬，'
                          '訂閱 Essential 一次全開；Starter 可讀第 2–4 冊。'
                      : '這本的每一章都要訂閱才能讀。免費可以讀完第 1 冊，'
                          '以及第 2 冊的第一章。訂閱後第 2–4 冊一次全開；'
                          '升級 Essential 再加開《成為獎賞》三冊。',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.onBackgroundSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewNoticeCard extends StatelessWidget {
  const _PreviewNoticeCard({required this.lockedChapterCount});

  final int lockedChapterCount;

  @override
  Widget build(BuildContext context) {
    return BrandSurfaceCard(
      elevated: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(right: 8, top: 1),
            child: Icon(Icons.auto_stories_outlined,
                size: 16, color: AppColors.brandBlush),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '免費試讀',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.brandBlush,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '第一章可以直接讀完，其餘 $lockedChapterCount 章訂閱後開放。'
                  '訂閱後第 2–4 冊一次全開，升級 Essential 再加開'
                  '《成為獎賞》三冊；不需要照順序讀。',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.onBackgroundSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChapterRow extends StatelessWidget {
  const _ChapterRow({
    required this.book,
    required this.chapter,
    required this.isCompleted,
    required this.isResumeTarget,
    this.isLocked = false,
  });

  final Ebook book;
  final EbookChapter chapter;
  final bool isCompleted;
  final bool isResumeTarget;

  /// 試讀模式下尚未解鎖的章：點擊導 paywall，不進閱讀器。
  final bool isLocked;

  @override
  Widget build(BuildContext context) {
    return BrandSurfaceCard(
      elevated: false,
      padding: const EdgeInsets.all(14),
      borderRadius: 18,
      borderColor: isResumeTarget
          ? AppColors.ctaStart.withValues(alpha: 0.45)
          : null,
      onTap: isLocked
          ? () => context.push('/paywall')
          : () => context.push(ebookChapterRoute(book.id, chapter.id)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 12),
            child: Icon(
              isLocked
                  ? Icons.lock_outline
                  : isCompleted
                      ? Icons.check_circle_outline
                      : Icons.radio_button_unchecked,
              size: 20,
              color: isLocked
                  ? AppColors.brandBlush
                  : isCompleted
                      ? AppColors.success
                      : AppColors.onBackgroundSecondary.withValues(alpha: 0.6),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${chapter.number}　${chapter.title}',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.onBackgroundPrimary,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  chapter.learningGoal,
                  style: AppTypography.bodySmall.copyWith(
                    color:
                        AppColors.onBackgroundSecondary.withValues(alpha: 0.78),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  children: [
                    Text(
                      '約 ${chapter.estimatedMinutes} 分鐘',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.onBackgroundSecondary
                            .withValues(alpha: 0.62),
                      ),
                    ),
                    // 狀態必須有文字，不能只靠鎖頭或打勾的顏色。
                    Text(
                      isLocked
                          ? '訂閱後解鎖'
                          : isCompleted
                              ? '已完成'
                              : '未完成',
                      style: AppTypography.caption.copyWith(
                        color: isLocked
                            ? AppColors.brandBlush
                            : isCompleted
                                ? AppColors.success
                                : AppColors.onBackgroundSecondary
                                    .withValues(alpha: 0.62),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
