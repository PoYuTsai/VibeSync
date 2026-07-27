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
    this.entryId,
  });

  final String bookId;

  /// 只決定初始章節；頁內換章不改 route。
  final String? chapterId;

  /// 交叉指涉的定位點：目標條目會自動展開並捲到畫面上。找不到就當作沒有。
  final String? entryId;

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
          chapterId: chapterId,
          builder: (context) => _ReaderProgressLoader(
            book: book!,
            routeChapterId: chapterId,
            anchorEntryId: entryId,
          ),
          // 未訂閱者讀付費書的第一章：只給那一章，其餘章不進 PageView。
          previewBuilder: (context) => _EbookReaderBody(
            book: book!,
            initialIndex: 0,
            previewOnly: true,
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
    this.anchorEntryId,
  });

  final Ebook book;
  final String? routeChapterId;
  final String? anchorEntryId;

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
        anchorEntryId: anchorEntryId,
      ),
      data: (snapshot) => _EbookReaderBody(
        book: book,
        initialIndex: resolveInitialChapterIndex(
          book,
          routeChapterId: routeChapterId,
          progress: snapshot.bookProgress(book.id),
        ),
        anchorEntryId: anchorEntryId,
      ),
    );
  }
}

class _EbookReaderBody extends ConsumerStatefulWidget {
  const _EbookReaderBody({
    required this.book,
    required this.initialIndex,
    this.previewOnly = false,
    this.anchorEntryId,
  });

  /// 交叉指涉的定位點。只消費一次：讀者手動收合之後換章再回來，不該又自己打開。
  final String? anchorEntryId;

  final Ebook book;
  final int initialIndex;

  /// 試讀模式：只放行 [Ebook.freePreviewChapterCount] 章，主按鈕改成看方案。
  final bool previewOnly;

  @override
  ConsumerState<_EbookReaderBody> createState() => _EbookReaderBodyState();
}

class _EbookReaderBodyState extends ConsumerState<_EbookReaderBody> {
  late final PageController _pageController =
      PageController(initialPage: widget.initialIndex);
  late int _currentIndex = widget.initialIndex;
  late String? _anchorEntryId = widget.anchorEntryId;
  bool _saving = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Ebook get _book => widget.book;

  /// 試讀模式下 PageView 只有試讀章；非試讀時是整本。
  List<EbookChapter> get _readableChapters => widget.previewOnly
      ? _book.chapters.take(_book.freePreviewChapterCount).toList(growable: false)
      : _book.chapters;

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
    try {
      // 先確認寫入成功，再翻頁或返回目錄。
      await ref
          .read(ebookProgressControllerProvider.notifier)
          .markChapterCompleted(
            bookId: _book.id,
            chapterId: _book.chapters[index].id,
            contentVersion: _book.contentVersion,
          );
    } catch (error) {
      // 寫入失敗不能停在 loading：解除按鈕並讓使用者可以再按一次。
      debugPrint('[ebook-reader] 完成章節寫入失敗：$error');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('進度沒有存起來，請再按一次。')),
      );
      return;
    }
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
    final chapters = _readableChapters;
    // 標題列的分母永遠是整本章數：試讀時顯示「第 1 ／ 5 章」才誠實。
    final total = _book.chapters.length;
    final readable = chapters.length;
    final completedCount = _book.chapters
        .where((chapter) => progress.isChapterCompleted(chapter.id))
        .length;
    final safeIndex = _currentIndex.clamp(0, readable - 1);

    return BrandScaffold(
      title: _book.title,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: _leaveReader,
      ),
      body: Column(
        children: [
          _ReaderHeader(
            currentIndex: safeIndex,
            total: total,
            completedCount: completedCount,
            chapter: chapters[safeIndex],
            isPreview: widget.previewOnly,
          ),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: readable,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, index) {
                final chapter = chapters[index];
                return _ChapterPage(
                  book: _book,
                  chapter: chapter,
                  index: index,
                  isLast: index >= readable - 1,
                  isCompleted: progress.isChapterCompleted(chapter.id),
                  progress: progress,
                  saving: _saving,
                  isPreview: widget.previewOnly,
                  lockedChapterCount: total - readable,
                  onComplete: () => _completeChapter(index),
                  anchorEntryId: _anchorEntryId,
                  onAnchorConsumed: () {
                    if (_anchorEntryId == null) return;
                    setState(() => _anchorEntryId = null);
                  },
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
    this.isPreview = false,
  });

  final int currentIndex;
  final int total;
  final int completedCount;
  final EbookChapter chapter;
  final bool isPreview;

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
              // 試讀時不顯示完成度：那個分母會讓人以為整本都能讀。
              if (isPreview)
                Text(
                  '免費試讀章',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.brandBlush,
                    fontWeight: FontWeight.w800,
                  ),
                )
              else
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
    this.isPreview = false,
    this.lockedChapterCount = 0,
    this.anchorEntryId,
    this.onAnchorConsumed,
  });

  /// 交叉指涉的定位點與消費回呼。
  final String? anchorEntryId;
  final VoidCallback? onAnchorConsumed;

  final Ebook book;
  final EbookChapter chapter;
  final int index;
  final bool isLast;
  final bool isCompleted;
  final EbookBookProgress progress;
  final bool saving;
  final VoidCallback onComplete;

  /// 試讀模式：章尾的主按鈕改成看訂閱方案，不寫任何完成進度。
  final bool isPreview;
  final int lockedChapterCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(ebookProgressControllerProvider.notifier);

    final String buttonLabel;
    if (isPreview) {
      buttonLabel = lockedChapterCount > 0
          ? '訂閱後解鎖其餘 $lockedChapterCount 章'
          : '看訂閱方案';
    } else if (isLast) {
      buttonLabel = isCompleted ? '回章節目錄' : '完成本書';
    } else {
      buttonLabel = isCompleted ? '下一章' : '完成本章，下一章';
    }

    // 這兩個保存是 best-effort 的本機寫入，不阻擋閱讀；但失敗時要讓使用者
    // 知道進度沒存起來，而不是讓畫面繼續宣稱「已理解」。
    void reportSaveFailure(Object error) {
      debugPrint('[ebook-reader] 互動進度寫入失敗：$error');
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        const SnackBar(content: Text('這一題的作答沒有存起來。')),
      );
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
              anchorEntryId: anchorEntryId,
              onAnchorConsumed: onAnchorConsumed,
              onCrossRefTap: (crossRef) => _openEbookTarget(
                context,
                ref,
                targetBookId: crossRef.targetBookId,
                targetChapterId: crossRef.targetChapterId,
                targetEntryId: crossRef.targetEntryId,
              ),
              onQuizSubmitted: (quiz, choiceIds, solved) {
                controller
                    .recordQuizSubmission(
                      bookId: book.id,
                      quizId: quiz.id,
                      quizRevision: quiz.revision,
                      choiceIds: choiceIds.toList(growable: false),
                      solved: solved,
                    )
                    .catchError(reportSaveFailure);
              },
              onFunnelTargetTap: (_, stage) => _openEbookTarget(
                context,
                ref,
                targetBookId: stage.targetBookId,
                targetChapterId: stage.targetChapterId,
              ),
              onChecklistItemChanged: (checklist, itemId, checked) {
                controller
                    .setChecklistItem(
                      bookId: book.id,
                      blockId: checklist.id,
                      itemId: itemId,
                      checked: checked,
                    )
                    .catchError(reportSaveFailure);
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
        if (isPreview)
          BrandPrimaryButton(
            label: buttonLabel,
            icon: Icons.workspace_premium_outlined,
            onPressed: () => context.push('/paywall'),
          )
        else
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

/// 章內跳章（漏斗診斷、交叉指涉）的共用落點決策。
///
/// push 而非 go：讀者跳出去之後，返回鍵要能回到原本那一章。
///
/// 目標章若在尚未解鎖的書裡，改送到那本書的免費試讀章，讓按鈕一定落在讀得到
/// 的地方；權限最終仍由目標頁的 EbookAccessGate 判定，這裡只是選一個較好的
/// 落點。只有「已確認未訂閱」才降級：ebookLockedFor 會把 resolving／
/// unavailable 也算成鎖著，用它會在付費使用者冷啟動或離線時把 route 提前改成
/// 第一章，等狀態確認完也回不去原本指定的那一章。
void _openEbookTarget(
  BuildContext context,
  WidgetRef ref, {
  required String targetBookId,
  required String targetChapterId,
  String? targetEntryId,
}) {
  final target = ref.read(ebookCatalogProvider).value?.findBook(targetBookId);
  final locked = target != null &&
      ebookAccessFor(target, ref.read(ebookSubscriptionAccessProvider)) ==
          EbookAccessDecision.locked;
  final chapterId =
      locked ? (target.previewChapterId ?? targetChapterId) : targetChapterId;
  // 降到試讀章時，原本的條目定位點不在那一章，一起丟掉才不會留一個永遠不會
  // 命中的 anchor。
  final entryId = locked ? null : targetEntryId;
  context.push(ebookChapterRoute(targetBookId, chapterId, entryId: entryId));
}

class _ReaderLoading extends StatelessWidget {
  const _ReaderLoading();

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
      title: kEbookCollectionTitle,
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
