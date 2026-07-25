// lib/features/learning/presentation/screens/ebook_reader_screen.dart
//
// 章節閱讀器：一頁一章的 PageView，每章內部獨立垂直捲動。
//
// 約束：
//   - route 上的 chapterId 只決定初始章節；unknown chapter 依序 fallback 到
//     保存的 lastChapterId 再到第一章，不 crash、不空白。
//   - 「閱讀位置」與「完成度」是兩個不同標籤，不混為一談。
//   - 完成本章要 await 寫入成功才翻頁／返回，避免使用者看到未保存的進度。
//   - 橫滑換章不阻斷章節內的垂直捲動（PageView + 內層 ListView）。
//   - premium 內容一定在 EbookAccessGate 之後才建立。
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
import '../../domain/models/ebook_progress.dart';
import '../widgets/ebook_access_gate.dart';
import '../widgets/ebook_block_renderer.dart';
import 'ebook_detail_screen.dart';

class EbookReaderScreen extends ConsumerWidget {
  const EbookReaderScreen({
    super.key,
    required this.bookId,
    this.chapterId,
  });

  final String bookId;

  /// 只決定初始章節；頁內換章不改 route。
  final String? chapterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(ebookCatalogProvider);

    return catalog.when(
      loading: () => const _ReaderLoading(),
      error: (error, _) => _ReaderMessage(
        icon: Icons.error_outline,
        title: '電子書內容載入失敗',
        message: '內容檔案讀取時出了問題。先回學習頁，我們會修。',
        onPrimary: () => context.go('/?tab=learning'),
        primaryLabel: '回學習頁',
      ),
      data: (catalog) {
        final book = catalog.findBook(bookId);
        return EbookAccessGate(
          book: book,
          builder: (context) => _ReaderProgressLoader(
            book: book!,
            routeChapterId: chapterId,
          ),
        );
      },
    );
  }
}

/// 先等本機進度載入，才決定初始章節——否則會從第一章開始而不是續讀位置。
class _ReaderProgressLoader extends ConsumerWidget {
  const _ReaderProgressLoader({
    required this.book,
    required this.routeChapterId,
  });

  final Ebook book;
  final String? routeChapterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(ebookProgressControllerProvider);

    return progress.when(
      loading: () => const _ReaderLoading(),
      // 進度讀不到時仍然可以閱讀，只是從第一章開始。
      error: (_, __) => _EbookReaderBody(
        book: book,
        initialIndex: resolveInitialChapterIndex(
          book,
          routeChapterId: routeChapterId,
          progress: EbookBookProgress.empty,
        ),
      ),
      data: (snapshot) => _EbookReaderBody(
        book: book,
        initialIndex: resolveInitialChapterIndex(
          book,
          routeChapterId: routeChapterId,
          progress: snapshot.bookProgress(book.id),
        ),
      ),
    );
  }
}

class _EbookReaderBody extends ConsumerStatefulWidget {
  const _EbookReaderBody({required this.book, required this.initialIndex});

  final Ebook book;
  final int initialIndex;

  @override
  ConsumerState<_EbookReaderBody> createState() => _EbookReaderBodyState();
}

class _EbookReaderBodyState extends ConsumerState<_EbookReaderBody> {
  late final PageController _pageController =
      PageController(initialPage: widget.initialIndex);
  late int _currentIndex = widget.initialIndex;
  bool _saving = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Ebook get _book => widget.book;

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
    // 換章即更新續讀位置；repository 會序列化寫入，快速連滑不會亂序。
    ref.read(ebookProgressControllerProvider.notifier).setLastChapter(
          bookId: _book.id,
          chapterId: _book.chapters[index].id,
          contentVersion: _book.contentVersion,
        );
  }

  Future<void> _completeChapter(int index) async {
    if (_saving) return;
    setState(() => _saving = true);
    // 先確認寫入成功，再翻頁或返回目錄。
    await ref.read(ebookProgressControllerProvider.notifier).markChapterCompleted(
          bookId: _book.id,
          chapterId: _book.chapters[index].id,
          contentVersion: _book.contentVersion,
        );
    if (!mounted) return;
    setState(() => _saving = false);

    final isLast = index >= _book.chapters.length - 1;
    if (!isLast) {
      final reducedMotion =
          MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (reducedMotion) {
        _pageController.jumpToPage(index + 1);
      } else {
        await _pageController.animateToPage(
          index + 1,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
      return;
    }
    _leaveReader();
  }

  void _leaveReader() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(ebookDetailRoute(_book.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(ebookBookProgressProvider(_book.id));
    final total = _book.chapters.length;
    final completedCount = _book.chapters
        .where((chapter) => progress.isChapterCompleted(chapter.id))
        .length;

    return BrandScaffold(
      title: _book.title,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: _leaveReader,
      ),
      body: Column(
        children: [
          _ReaderHeader(
            currentIndex: _currentIndex,
            total: total,
            completedCount: completedCount,
            chapter: _book.chapters[_currentIndex],
          ),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: total,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, index) {
                final chapter = _book.chapters[index];
                return _ChapterPage(
                  book: _book,
                  chapter: chapter,
                  index: index,
                  isLast: index >= total - 1,
                  isCompleted: progress.isChapterCompleted(chapter.id),
                  progress: progress,
                  saving: _saving,
                  onComplete: () => _completeChapter(index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ReaderHeader extends StatelessWidget {
  const _ReaderHeader({
    required this.currentIndex,
    required this.total,
    required this.completedCount,
    required this.chapter,
  });

  final int currentIndex;
  final int total;
  final int completedCount;
  final EbookChapter chapter;

  @override
  Widget build(BuildContext context) {
    final positionRatio = total <= 0 ? 0.0 : (currentIndex + 1) / total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wrap 而非 Row：大字級時兩個標籤放不進一行，換行比裁字好。
          Wrap(
            spacing: 10,
            runSpacing: 2,
            children: [
              Text(
                '第 ${currentIndex + 1} ／ $total 章',
                style: AppTypography.caption.copyWith(
                  color: AppColors.ctaStart,
                  fontWeight: FontWeight.w800,
                ),
              ),
              // 「完成度」與「閱讀位置」是兩件事，標籤刻意分開。
              Text(
                '完成度 $completedCount ／ $total 章',
                style: AppTypography.caption.copyWith(
                  color: AppColors.onBackgroundSecondary
                      .withValues(alpha: 0.78),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Semantics(
            label: '閱讀位置：第 ${currentIndex + 1} 章，共 $total 章',
            excludeSemantics: true,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: positionRatio,
                minHeight: 5,
                backgroundColor: AppColors.brandInk.withValues(alpha: 0.6),
                valueColor: AlwaysStoppedAnimation<Color>(
                  AppColors.ctaStart.withValues(alpha: 0.85),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '閱讀位置',
            style: AppTypography.caption.copyWith(
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChapterPage extends ConsumerWidget {
  const _ChapterPage({
    required this.book,
    required this.chapter,
    required this.index,
    required this.isLast,
    required this.isCompleted,
    required this.progress,
    required this.saving,
    required this.onComplete,
  });

  final Ebook book;
  final EbookChapter chapter;
  final int index;
  final bool isLast;
  final bool isCompleted;
  final EbookBookProgress progress;
  final bool saving;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(ebookProgressControllerProvider.notifier);

    final String buttonLabel;
    if (isLast) {
      buttonLabel = isCompleted ? '回章節目錄' : '完成本書';
    } else {
      buttonLabel = isCompleted ? '下一章' : '完成本章，下一章';
    }

    return ListView(
      // PageStorageKey：換章再回來時保留這一章的捲動位置，也讓測試能定位到
      // 該章自己的 scrollable（一個 PageView 裡有多個垂直清單）。
      key: PageStorageKey<String>('ebook-chapter-${chapter.id}'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
      children: [
        Text(
          chapter.number,
          style: AppTypography.caption.copyWith(
            color: AppColors.ctaStart,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          chapter.title,
          style: AppTypography.headlineLarge.copyWith(
            color: AppColors.onBackgroundPrimary,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 20),
        for (final block in chapter.blocks)
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: EbookBlockRenderer(
              block: block,
              progress: progress,
              onQuizSubmitted: (quiz, choiceIds, solved) {
                controller.recordQuizSubmission(
                  bookId: book.id,
                  quizId: quiz.id,
                  quizRevision: quiz.revision,
                  choiceIds: choiceIds.toList(growable: false),
                  solved: solved,
                );
              },
              onChecklistItemChanged: (checklist, itemId, checked) {
                controller.setChecklistItem(
                  bookId: book.id,
                  blockId: checklist.id,
                  itemId: itemId,
                  checked: checked,
                );
              },
            ),
          ),
        const SizedBox(height: 4),
        if (isCompleted)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline,
                    size: 16, color: AppColors.success),
                const SizedBox(width: 6),
                Text(
                  '本章已完成',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        BrandPrimaryButton(
          label: buttonLabel,
          isLoading: saving,
          icon: isLast ? Icons.flag_outlined : Icons.arrow_forward_rounded,
          onPressed: saving ? null : onComplete,
        ),
      ],
    );
  }
}

class _ReaderLoading extends StatelessWidget {
  const _ReaderLoading();

  @override
  Widget build(BuildContext context) {
    return const BrandScaffold(
      title: '互動電子書',
      body: Center(
        child: CircularProgressIndicator(
          strokeWidth: 2.6,
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.ctaStart),
        ),
      ),
    );
  }
}

class _ReaderMessage extends StatelessWidget {
  const _ReaderMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    return BrandScaffold(
      title: '互動電子書',
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              BrandIconBadge(icon: icon, size: 48, iconSize: 24),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppTypography.titleMedium.copyWith(
                  color: AppColors.onBackgroundPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.onBackgroundSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              BrandPrimaryButton(label: primaryLabel, onPressed: onPrimary),
            ],
          ),
        ),
      ),
    );
  }
}
