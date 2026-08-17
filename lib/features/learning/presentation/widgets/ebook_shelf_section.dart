// lib/features/learning/presentation/widgets/ebook_shelf_section.dart
//
// 學習頁的「互動電子書」區塊。
//
// 位置在 Practice Hero 之後、短篇文章之前。這裡刻意不顯示任何文章每日額度提示：
// 電子書不消耗文章額度，把額度文案放在書架上方會造成錯誤聯想。
//
// 2026-08-09 學習頁減長批：七本書卡不再全部攤開。每個單元收成一張可展開的
// 群組卡（標題＋進度摘要＋chevron），點了才展開該單元的書卡。展開狀態只留在
// 這個 session（StatefulWidget），刻意不進 Hive——這是瀏覽姿勢不是進度。
//
// 預設展開規則：
//   - 沒有任何一本書開始過 → 展開第一單元（終極指引），新用戶進來仍直接
//     看得到書；第二單元收合。
//   - 有任何一本開始過 → 兩單元都收合，改在群組上方放一張「繼續閱讀」捷徑
//     卡，直接進最適合接續的那本書的目錄頁。
//
// 內容載入失敗時只讓這個區塊降級成錯誤卡，不影響同頁的 24 篇文章。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../data/providers/ebook_providers.dart';
import '../../domain/models/ebook.dart';
import '../../domain/models/ebook_progress.dart';
import '../screens/ebook_detail_screen.dart';
import 'ebook_access_gate.dart';
import 'ebook_shelf_card.dart';

/// 單元群組卡與繼續閱讀卡的測試用 key。
Key ebookUnitGroupKey(EbookUnit unit) =>
    ValueKey('ebook-unit-group-${unit.name}');
const Key ebookResumeCardKey = ValueKey('ebook-resume-card');

class EbookShelfSection extends ConsumerStatefulWidget {
  const EbookShelfSection({super.key});

  @override
  ConsumerState<EbookShelfSection> createState() => _EbookShelfSectionState();
}

class _EbookShelfSectionState extends ConsumerState<EbookShelfSection> {
  /// 展開中的單元。`null` = 進度資料還沒到，預設值尚未決定。
  ///
  /// 進度 provider 第一幀是 loading（讀 Hive），那時每本書都看起來「沒開始」；
  /// 若在那一幀就拍板預設，有進度的使用者會先看到第一單元攤開、下一幀又冒出
  /// 繼續閱讀卡。所以等 [ebookProgressControllerProvider] 真的變成 data 才決定。
  Set<EbookUnit>? _expandedUnits;

  /// 「開始過」＝讀過任何一章（resume 記錄）或完成過任何一章。
  /// quiz／checklist 狀態必然伴隨讀章，不另列條件。
  bool _isStarted(EbookBookProgress progress) =>
      progress.lastChapterId != null || progress.completedChapterIds.isNotEmpty;

  bool _isFullyCompleted(Ebook book, EbookBookProgress progress) =>
      book.chapters.isNotEmpty &&
      book.chapters.every((chapter) => progress.isChapterCompleted(chapter.id));

  void _toggleUnit(EbookUnit unit) {
    setState(() {
      final expanded = _expandedUnits ?? <EbookUnit>{};
      if (!expanded.remove(unit)) expanded.add(unit);
      _expandedUnits = expanded;
    });
  }

  @override
  Widget build(BuildContext context) {
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
          data: (catalog) => _buildShelf(context, catalog, access),
        ),
      ],
    );
  }

  Widget _buildShelf(
    BuildContext context,
    EbookCatalog catalog,
    EbookSubscriptionAccess access,
  ) {
    final sections = catalog.unitSections;
    final progressReady = ref.watch(ebookProgressControllerProvider)
        is AsyncData<EbookProgressSnapshot>;
    final progressByBook = <String, EbookBookProgress>{
      for (final book in catalog.books)
        book.id: ref.watch(ebookBookProgressProvider(book.id)),
    };
    final startedBooks = [
      for (final book in catalog.books)
        if (_isStarted(progressByBook[book.id]!)) book,
    ];

    // 進度資料第一次到位時決定預設展開；之後只由使用者點擊改變。
    // 在 build 內直接賦值（不 setState）：本幀就用得到，不需要再排一次重建。
    if (_expandedUnits == null && progressReady) {
      _expandedUnits = startedBooks.isEmpty && sections.isNotEmpty
          ? <EbookUnit>{sections.first.unit}
          : <EbookUnit>{};
    }
    final expandedUnits = _expandedUnits ?? const <EbookUnit>{};

    // 繼續閱讀的目標：進度沒有「最近讀的是哪本」的時間戳（snapshot 只有全域
    // updatedAt），所以取 catalog 順序第一本「開始過且還沒讀完」的書；全都讀完
    // 就退回第一本開始過的。
    Ebook? resumeBook;
    for (final book in startedBooks) {
      if (!_isFullyCompleted(book, progressByBook[book.id]!)) {
        resumeBook = book;
        break;
      }
    }
    resumeBook ??= startedBooks.isEmpty ? null : startedBooks.first;

    return Column(
      children: [
        if (resumeBook != null) ...[
          _ResumeCard(
            book: resumeBook,
            progress: progressByBook[resumeBook.id]!,
          ),
          const SizedBox(height: 8),
        ],
        for (final section in sections) ...[
          _UnitGroupHeader(
            unit: section.unit,
            startedCount: section.books
                .where((book) => _isStarted(progressByBook[book.id]!))
                .length,
            totalCount: section.books.length,
            expanded: expandedUnits.contains(section.unit),
            onTap: () => _toggleUnit(section.unit),
          ),
          const SizedBox(height: 8),
          // 展開／收合走結構性條件渲染，不做淡入淡出：App 已因真機文字殘影
          // 全面拆除入場動畫，這裡不重新引入。
          if (expandedUnits.contains(section.unit))
            for (final book in section.books)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: EbookShelfCard(
                  book: book,
                  decision: ebookAccessFor(book, access),
                ),
              ),
        ],
      ],
    );
  }
}

/// 有進度時書架頂端的「繼續閱讀」捷徑卡，直接進該書目錄頁。
class _ResumeCard extends StatelessWidget {
  const _ResumeCard({required this.book, required this.progress});

  final Ebook book;
  final EbookBookProgress progress;

  @override
  Widget build(BuildContext context) {
    final lastChapterId = progress.lastChapterId;
    final chapter =
        lastChapterId == null ? null : book.findChapter(lastChapterId);
    return BrandSurfaceCard(
      key: ebookResumeCardKey,
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      borderRadius: 20,
      // 與書卡相同的入口：目錄頁自己處理權限閘門與試讀。
      onTap: () => context.push(ebookDetailRoute(book.id)),
      child: Row(
        children: [
          const BrandIconBadge(
              icon: Icons.auto_stories_outlined, size: 34, iconSize: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '繼續閱讀',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.ctaStart,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.onBackgroundPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  chapter == null
                      ? '接續上次的進度'
                      : '上次讀到 ${chapter.number} ${chapter.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    color:
                        AppColors.onBackgroundSecondary.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right,
              size: 20, color: AppColors.onBackgroundSecondary),
        ],
      ),
    );
  }
}

/// 單元群組卡：kicker＋單元全名＋開始進度摘要＋chevron。點擊展開／收合。
class _UnitGroupHeader extends StatelessWidget {
  const _UnitGroupHeader({
    required this.unit,
    required this.startedCount,
    required this.totalCount,
    required this.expanded,
    required this.onTap,
  });

  final EbookUnit unit;
  final int startedCount;
  final int totalCount;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // kicker 是導覽裝飾：夾住字級並允許截斷，極端字級下寧可短掉英文標語，
    // 也不能把整列擠爆。
    final kickerScaler =
        MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.4);
    return BrandSurfaceCard(
      key: ebookUnitGroupKey(unit),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      borderRadius: 20,
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 2026-08-09 拍板二輪：中文標題在上、橘色英文 kicker 在下，
                // 與書架 hero／聊天新手村的「大標上、副標下」階層一致。
                Text(
                  unit.fullTitle,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.onBackgroundPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  unit.kicker,
                  textScaler: kickerScaler,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.ctaStart,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$startedCount/$totalCount 本已開始',
                  style: AppTypography.caption.copyWith(
                    color:
                        AppColors.onBackgroundSecondary.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // chevron 旋轉是允許的殘留動畫（非文字、非透明度），不會殘影。
          AnimatedRotation(
            turns: expanded ? 0.5 : 0,
            duration: AppMotion.enter,
            curve: AppMotion.easeOut,
            child: const Icon(Icons.expand_more,
                size: 22, color: AppColors.onBackgroundSecondary),
          ),
        ],
      ),
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
    // 2026-08-09 拍板二輪：排版對標「聊天新手村」入口卡——icon＋中文大標在
    // 上、橘色副標在下。副標不再用 THE FIELD GUIDE（那是下方終極指引單元卡
    // 的 kicker，同字面會像重複列兩次），改為定位句「系統化實戰教材」，
    // 與新手村的「判讀訓練場」同句式。大標維持與單元卡標題脫鉤的總稱。
    return BrandSurfaceCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BrandIconBadge(
                  icon: Icons.menu_book_outlined, size: 26, iconSize: 14),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '高階互動指南',
                      style: AppTypography.headlineLarge.copyWith(
                        color: AppColors.onBackgroundPrimary,
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                      ),
                    ),
                    // 橘色副標進頁時掃一次 shimmer（splash wordmark 同款
                    // ShaderMask 技法，已核可的例外：modulate 調色、非透明度）。
                    _OneShotKickerShimmer(
                      child: Text(
                        '系統化實戰教材',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.ctaStart,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
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

/// 金色 kicker 的一次性 shimmer 掃光。
///
/// 技法沿用 splash wordmark：ShaderMask + BlendMode.modulate + 移動的
/// LinearGradient stops——調的是顏色不是透明度，是殘影禁令下已核可的例外。
/// 學習頁建出這個 State 時播一次（約 0.9 秒）；收合／展開等 rebuild 不會
/// 重播（State 不重掛載就不重播）。
///
/// 遵守 [MediaQuery.disableAnimations] 與 [TickerMode]：關閉動畫時直接停在
/// 終點（靜態白色 shader＝原色文字），pumpAndSettle 必收斂。
class _OneShotKickerShimmer extends StatefulWidget {
  const _OneShotKickerShimmer({required this.child});

  final Widget child;

  @override
  State<_OneShotKickerShimmer> createState() => _OneShotKickerShimmerState();
}

class _OneShotKickerShimmerState extends State<_OneShotKickerShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final Animation<double> _position =
      Tween<double>(begin: -0.6, end: 1.2).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
  );

  /// 是否已決定過要不要播（State 一生只決定一次）。
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  void _syncMotion() {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final enabled = TickerMode.valuesOf(context).enabled && !reduceMotion;

    if (!_decided) {
      _decided = true;
      if (enabled) {
        _controller.forward();
      } else {
        // 關閉動畫：直接停在終點（掃光已離場），文字維持原色。
        _controller.value = 1;
      }
      return;
    }

    if (!enabled && _controller.isAnimating) {
      _controller
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            if (_controller.isAnimating) {
              final x = _position.value;
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: const [
                  Colors.white,
                  Colors.white,
                  Color(0x80FFFFFF),
                  Colors.white,
                  Colors.white,
                ],
                stops: [
                  0.0,
                  (x - 0.1).clamp(0.0, 1.0),
                  x.clamp(0.0, 1.0),
                  (x + 0.1).clamp(0.0, 1.0),
                  1.0,
                ],
              ).createShader(bounds);
            }
            // 未播／播完：全白 shader，modulate 下等於原色。
            return const LinearGradient(
              colors: [Colors.white, Colors.white],
            ).createShader(bounds);
          },
          blendMode: BlendMode.modulate,
          child: child,
        );
      },
    );
  }
}

class _ShelfPlaceholder extends StatelessWidget {
  const _ShelfPlaceholder();

  @override
  Widget build(BuildContext context) {
    return BrandSurfaceCard(
      elevated: false,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
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
          const SizedBox(width: 8),
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
