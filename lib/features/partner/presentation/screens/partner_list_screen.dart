// lib/features/partner/presentation/screens/partner_list_screen.dart
//
// Phase 2 Home tab body — partner-first replacement for the old
// conversation-centric home (deprecated donor removed in Phase 4 Task 6).
//
// Aggregate is watched AT THE LIST LEVEL (not inside the card) so each row
// re-evaluates only when its own partner's conversations change. This keeps
// the narrow-invalidation contract intact (Codex C1) and lets the card stay
// pure-render (Codex r1 P1.3b).
//
// Phase 4 Task 2 also captures the live `conversationsByPartner.length` per
// row and routes it into the two-mode delete dialog. Counting from the
// provider — NOT from `aggregate.totalRounds` — guards against the
// zero-round-conversation false-safe (Codex P1.2).
import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_feedback_snack_bar.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../../conversation/data/providers/conversation_providers.dart';
import '../../../subscription/presentation/widgets/home_quota_strip.dart';
import '../../data/providers/partner_banner_providers.dart';
import '../../data/providers/partner_write_controller.dart';
import '../../data/repositories/partner_repository.dart';
import '../../data/services/partner_banner_service.dart';
import '../../domain/entities/partner.dart';
import '../providers/partner_providers.dart';
import 'partner_detail_screen.dart';
import '../widgets/getting_started_checklist.dart';
import '../widgets/home_coach_presence.dart';
import '../widgets/home_feature_entries.dart';
import '../widgets/partner_list_card.dart';
import '../widgets/same_name_dedupe_banner.dart';

class PartnerListScreen extends ConsumerWidget {
  const PartnerListScreen({
    super.key,
    this.bottomPadding = 32,
    this.coachPose = HomeCoachPose.greeting,
  });

  final double bottomPadding;
  final HomeCoachPose coachPose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partners = ref.watch(partnerListProvider);
    if (partners.isEmpty) {
      return _EmptyHome(
        bottomPadding: bottomPadding,
        coachPose: coachPose,
        // 起步清單還在＝空態獨占「第二頁」（Sydney 偏右、頂端給往上提示）；
        // 清單收乾＝退回原本單頁排版與置中的 Sydney。
        paged: GettingStartedChecklist.blockVisible(ref),
      );
    }

    // Banner gating (Phase 4 Task 4):
    //   uid null  → no banner (no scope to key dismissal)
    //   no dup    → no banner
    //   dismissed → no banner (loading/error also treated as "don't show")
    final uid = ref.watch(authConversationScopeProvider).valueOrNull;
    final dupPair = uid == null ? null : _findFirstDupPair(partners);
    final dismissedAsync = uid == null
        ? const AsyncValue<bool>.data(true)
        : ref.watch(partnerDedupeBannerDismissedProvider(uid));
    final showBanner = dupPair != null && dismissedAsync.value == false;

    final bannerCount = showBanner ? 1 : 0;
    final listItemCount = partners.length + bannerCount;
    // Five rows fill a typical phone body. Start Sydney on the next viewport
    // so a partial head or hand never peeks out beneath the bottom navigation.
    final startsCoachOnNextViewport = listItemCount >= 5;
    final coachFooter = Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: HomeCoachPresence(pose: coachPose),
      ),
    );

    return CustomScrollView(
      slivers: [
        // Tier 2 批 1：頂部掛額度小條＋功能入口列。用 SliverToBoxAdapter
        // 而非塞進 SliverList，banner／partner 的 index 算法完全不動。
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              children: [
                HomeQuotaStrip(),
                GettingStartedChecklist(),
                HomeFeatureEntries(),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          sliver: SliverList.builder(
            itemCount: listItemCount,
            itemBuilder: (context, i) {
              if (showBanner && i == 0) {
                return SameNameDedupeBanner(
                  partnerName: dupPair.newer.name,
                  onMergeTap: () =>
                      _onMergeDuplicate(context, ref, uid!, dupPair),
                  onDismissTap: () async {
                    await PartnerBannerService.markDismissed(uid!);
                    try {
                      // Guard against widget disposal during the await above —
                      // sign-out / nav-away invalidates ref before this lands.
                      ref.invalidate(partnerDedupeBannerDismissedProvider(uid));
                    } catch (e, st) {
                      // Widget disposed; invalidation is moot, but keep a breadcrumb
                      // in debug logs so real dismiss failures are not silent.
                      debugPrint(
                        'PartnerListScreen banner dismiss invalidation skipped: '
                        '$e\n$st',
                      );
                    }
                  },
                );
              }
              final pIndex = showBanner ? i - 1 : i;
              final p = partners[pIndex];
              final agg = ref.watch(partnerAggregateProvider(p.id));
              // Codex P1.2 — count real conversation rows, not aggregate.totalRounds
              // (zero-round conversations would otherwise be invisible to the
              // delete dialog and let the user fall straight into the repo throw).
              final convCount =
                  ref.watch(conversationsByPartnerProvider(p.id)).length;
              // OpenContainer 與系統 reduced-motion 整合不完整，
              // reduce motion 時退回原本的 go_router push。
              final reduceMotion =
                  MediaQuery.maybeOf(context)?.disableAnimations ?? false;
              if (reduceMotion) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: PartnerListCard(
                    partner: p,
                    aggregate: agg,
                    onTap: () => context.push('/partner/${p.id}'),
                    onDelete: () => _onDelete(context, ref, p, convCount),
                  ),
                );
              }
              // 卡片原地長成詳情頁（container transform）。走 Navigator 自家
              // route、不經 go_router；/partner/:partnerId GoRoute 保留給
              // deep link 等其他入口。
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: OpenContainer(
                  transitionType: ContainerTransitionType.fadeThrough,
                  transitionDuration: AppMotion.containerTransform,
                  closedElevation: 0,
                  openElevation: 0,
                  closedColor: Colors.transparent,
                  openColor: AppColors.partnerDetailBgTop,
                  middleColor: AppColors.partnerDetailBgTop,
                  closedShape: RoundedRectangleBorder(
                    // 對齊 PartnerListCard 實際圓角（22）。
                    borderRadius: BorderRadius.circular(22),
                  ),
                  closedBuilder: (context, open) => PartnerListCard(
                    partner: p,
                    aggregate: agg,
                    onTap: open,
                    onDelete: () => _onDelete(context, ref, p, convCount),
                  ),
                  openBuilder: (context, _) =>
                      PartnerDetailScreen(partnerId: p.id),
                ),
              );
            },
          ),
        ),
        if (startsCoachOnNextViewport) ...[
          const SliverFillRemaining(
            hasScrollBody: false,
            child: SizedBox.shrink(),
          ),
          SliverToBoxAdapter(child: coachFooter),
        ] else
          SliverFillRemaining(
            hasScrollBody: false,
            child: coachFooter,
          ),
      ],
    );
  }

  /// First same-name pair, ordered by createdAt ASC.
  /// Returns null when no group of size ≥2 exists.
  /// older=earliest createdAt (survivor); newer=second earliest (absorbed).
  /// (D-P4-2: keep the older identity, absorb the newer duplicate into it.)
  ({Partner older, Partner newer})? _findFirstDupPair(List<Partner> partners) {
    final byName = <String, List<Partner>>{};
    for (final p in partners) {
      byName.putIfAbsent(p.name, () => []).add(p);
    }
    for (final entry in byName.entries) {
      if (entry.value.length >= 2) {
        final sorted = [...entry.value]
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        return (older: sorted[0], newer: sorted[1]);
      }
    }
    return null;
  }

  Future<void> _onMergeDuplicate(
    BuildContext context,
    WidgetRef ref,
    String uid,
    ({Partner older, Partner newer}) dupPair,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(partnerWriteControllerProvider.notifier).merge(
            fromId: dupPair.newer.id,
            toId: dupPair.older.id,
          );
      await PartnerBannerService.markDismissed(uid);
      try {
        ref.invalidate(partnerDedupeBannerDismissedProvider(uid));
      } catch (e, st) {
        debugPrint(
          'PartnerListScreen merge invalidation skipped: $e\n$st',
        );
      }
      messenger.showSnackBar(
        buildBrandFeedbackSnackBar(
          title: '已合併「${dupPair.older.name}」',
        ),
      );
    } catch (e, st) {
      debugPrint('PartnerListScreen direct merge failed: $e\n$st');
      messenger.showSnackBar(
        buildBrandFeedbackSnackBar(
          title: '合併失敗，請稍後再試',
          icon: Icons.error_outline_rounded,
          accentColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _onDelete(
    BuildContext context,
    WidgetRef ref,
    Partner partner,
    int conversationCount,
  ) async {
    if (conversationCount > 0) {
      await _showInformationalDialog(context, partner, conversationCount);
      return;
    }
    await _showConfirmDialog(context, ref, partner);
  }

  Future<void> _showInformationalDialog(
    BuildContext context,
    Partner partner,
    int conversationCount,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.glassWhite,
        title: Text(
          '還不能刪除',
          style: const TextStyle(color: AppColors.glassTextPrimary),
        ),
        content: Text(
          '「${partner.name}」這張對象卡裡還有 $conversationCount 段對話\n\n'
          '請先打開對象頁，把紀錄刪掉或移到其他對象，清空後就能刪除這張對象卡',
          style: const TextStyle(color: AppColors.glassTextPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _showConfirmDialog(
    BuildContext context,
    WidgetRef ref,
    Partner partner,
  ) async {
    // Capture messenger before any await so we don't reuse `context` across
    // async gaps (avoids `use_build_context_synchronously` lint).
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.glassWhite,
        title: Text(
          '刪除對象',
          style: const TextStyle(color: AppColors.glassTextPrimary),
        ),
        content: Text(
          '確定刪除「${partner.name}」？',
          style: const TextStyle(color: AppColors.glassTextPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              '取消',
              style: const TextStyle(color: AppColors.unselectedText),
            ),
          ),
          TextButton(
            onPressed: AppHaptics.onPress(() => Navigator.of(ctx).pop(true)),
            style:
                TextButton.styleFrom(foregroundColor: AppColors.errorOnGlass),
            child: const Text('刪除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(partnerWriteControllerProvider.notifier).delete(partner);
      messenger.showSnackBar(
        buildBrandFeedbackSnackBar(
          title: '已刪除「${partner.name}」',
          icon: Icons.delete_outline_rounded,
        ),
      );
    } on PartnerHasConversationsException catch (e) {
      // Defensive — a conversation may have been created between the
      // dialog open and the repo call. Surface the live count.
      messenger.showSnackBar(
        buildBrandFeedbackSnackBar(
          title: '刪除失敗：仍有 ${e.conversationCount} 段對話',
          icon: Icons.error_outline_rounded,
          accentColor: AppColors.error,
        ),
      );
    } catch (e, st) {
      debugPrint('PartnerListScreen delete failed: $e\n$st');
      messenger.showSnackBar(
        buildBrandFeedbackSnackBar(
          title: '刪除失敗，請稍後再試',
          icon: Icons.error_outline_rounded,
          accentColor: AppColors.error,
        ),
      );
    }
  }
}

/// 首頁空態。夥伴稿 2／3 讀起來是兩頁，但兩頁之間靠「下一頁的標題露一截」
/// 當捲動提示（稿 2 底部就是「先建立第一張對象卡」被折線切），不是硬分頁：
/// 硬分頁會在第一頁底部留一塊死白，也沒東西告訴使用者下面還有內容。
///
/// 「往上查看起步清單與快捷入口」不排進捲動內容，而是捲下去之後才淡入的
/// 頂部提示——這樣稿 2（沒有提示）與稿 3（有提示）才會同時成立。
class _EmptyHome extends StatefulWidget {
  const _EmptyHome({
    required this.bottomPadding,
    required this.coachPose,
    required this.paged,
  });

  final double bottomPadding;
  final HomeCoachPose coachPose;

  /// 起步清單還在＝兩頁語意（有往上提示、Sydney 偏右）。
  final bool paged;

  @override
  State<_EmptyHome> createState() => _EmptyHomeState();
}

class _EmptyHomeState extends State<_EmptyHome> {
  final _controller = ScrollController();
  bool _scrolled = false;

  /// 捲過這個距離就當使用者已經進到第二頁。
  static const _hintThreshold = 120.0;

  /// 第二頁「往回看」的距離：捲到底時視窗上緣會落在第一頁底部往上這麼多的
  /// 位置。取 248＝標題段（[_EmptyHead] 約 132）再往上留 116，讓標題落在頂部
  /// 提示之下、不被蓋住；那 116 在第一頁是 Spacer 的空白，所以第一頁不受影響。
  static const _peekHeight = 236.0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  void _onScroll() {
    final scrolled = _controller.offset > _hintThreshold;
    if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  /// 兩頁版面。夥伴稿 2 的第一屏底部剛好是「標題＋兩行說明」被折線切住，
  /// 稿 3 則是同一段落到了第二屏頂端——這不是兩份內容，是同一段在兩個捲動
  /// 位置。所以第一頁把標題段釘在底部，第二頁的高度再扣掉那段
  /// （[_peekHeight]），捲到底時視窗上緣就正好落在標題上。
  ///
  /// 不用魔術數字硬湊間距：換螢幕高度也不會切到字。
  Widget _pagedBody(double pageHeight) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: pageHeight - 24,
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Tier 2 批 1：額度小條＋功能入口列，空／非空兩態都掛。
              // 批 2：起步清單卡插在 QuotaStrip 之下、入口列之上。
              HomeQuotaStrip(),
              GettingStartedChecklist(),
              HomeFeatureEntries(),
              Spacer(),
              _EmptyHead(),
            ],
          ),
        ),
        SizedBox(
          height: pageHeight - _peekHeight,
          child: _EmptyTail(coachPose: widget.coachPose),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 空態底部不留保留區：這一頁沒有 FAB（空態把它收起來了），Sydney
        // 要像夥伴稿一樣被導覽列切齊，留 padding 會在她腳下開一條死白。
        final pageHeight = constraints.maxHeight;
        return Stack(
          children: [
            // SingleChildScrollView 而非 ListView：空態整塊會落在 lazy sliver
            // 的 cache extent 之外，惰性建構會讓它根本不 build。
            SingleChildScrollView(
              controller: _controller,
              padding: EdgeInsets.fromLTRB(
                24,
                24,
                24,
                // 兩頁模式讓 Sydney 貼齊導覽列；單頁模式維持原本的底部留白。
                widget.paged ? 0 : widget.bottomPadding,
              ),
              child: widget.paged && pageHeight > 620
                  ? _pagedBody(pageHeight)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const HomeQuotaStrip(),
                        const GettingStartedChecklist(),
                        const HomeFeatureEntries(),
                        const SizedBox(height: 20),
                        _EmptyBlock(
                          coachPose: widget.coachPose,
                          // 清單還在＝使用者還沒起步，冷啟動分流要留著；
                          // 這裡也涵蓋「矮視窗退回單頁」的情況。
                          showWarmUpLink: widget.paged,
                        ),
                      ],
                    ),
            ),
            if (widget.paged)
              Positioned(
                top: 8,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _scrolled ? 1 : 0,
                    duration: AppMotion.enter,
                    curve: AppMotion.easeOut,
                    // 內容是從提示底下捲過去的，補一層由上而下淡出的遮罩，
                    // 不然標題會跟提示字疊在一起。
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppColors.brandInk,
                            AppColors.brandInk.withValues(alpha: 0.92),
                            AppColors.brandInk.withValues(alpha: 0),
                          ],
                          stops: const [0, 0.55, 1],
                        ),
                      ),
                      child: Padding(
                        // 夥伴稿 3：提示置頂靠左，跟頁面左邊界對齊，不是置中。
                        padding: const EdgeInsets.fromLTRB(24, 6, 24, 18),
                        child: Row(
                          children: [
                            Icon(
                              Icons.arrow_upward_rounded,
                              size: 15,
                              color: AppColors.onBackgroundSecondary
                                  .withValues(alpha: 0.7),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '往上查看起步清單與快捷入口',
                              style: AppTypography.bodySmall.copyWith(
                                fontSize: 13,
                                color: AppColors.onBackgroundSecondary
                                    .withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 空態主圖示：對象「卡」＋人＋橘色加號（夥伴稿 3）。Material 沒有單一字形
/// 同時有卡框、人像與加號，用 account_box_outlined 疊一顆橘 + 合成。
class _AddPartnerCardIcon extends StatelessWidget {
  const _AddPartnerCardIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            Icons.account_box_outlined,
            size: size,
            color: Colors.white.withValues(alpha: 0.32),
          ),
          Positioned(
            right: -2,
            bottom: size * 0.12,
            child: Icon(
              Icons.add_rounded,
              size: size * 0.42,
              color: AppColors.ctaStart,
            ),
          ),
        ],
      ),
    );
  }
}

/// 第一頁底部釘住的標題段（夥伴稿 2 的折線就切在這段之後）。
/// 高度＝標題 + 14 + 兩行說明 + 24 下緣，對應 [_EmptyHomeState._peekHeight]。
class _EmptyHead extends StatelessWidget {
  const _EmptyHead();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 圖示填掉第一頁卡片區與標題之間那塊空白（Eric 2026-08-13 回報太空）。
        const Center(child: _AddPartnerCardIcon(size: 62)),
        const SizedBox(height: 24),
        Text(
          '先建立第一張對象卡',
          textAlign: TextAlign.center,
          style: AppTypography.headlineMedium.copyWith(
            color: AppColors.onBackgroundPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'VibeSync 會記得你和每個對象，幫你看懂互動，陪你練下一步。',
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.onBackgroundSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// 第二頁：接在標題段之後的說明、主 CTA，以及「先去練習室熱身」在左、
/// Sydney 在右的底部帶狀區（夥伴稿 3 量測值換算到 393×852pt）。
class _EmptyTail extends StatelessWidget {
  const _EmptyTail({required this.coachPose});

  final HomeCoachPose coachPose;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '一個人一張卡。不同日期、IG、LINE 或交友軟體的聊天，都整理在同一張卡裡。',
          textAlign: TextAlign.center,
          style: AppTypography.bodySmall.copyWith(
            fontSize: 13,
            color: AppColors.onBackgroundSecondary.withValues(alpha: 0.8),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 32),
        BrandPrimaryButton(
          label: '建立對象卡，開始分析',
          icon: Icons.person_add_alt_1_rounded,
          onPressed: () => context.push('/partner/new'),
        ),
        const SizedBox(height: 16),
        // Sydney 吃掉 CTA 以下的全部剩餘高度（上限 340），避免中間開洞；
        // 只平移不變形，「先去練習室熱身」疊在她左邊（夥伴稿 3）。
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final figureHeight = constraints.maxHeight.clamp(200.0, 340.0);
              return Stack(
                children: [
                  Positioned.fill(
                    child: FractionalTranslation(
                      translation: const Offset(0.19, 0),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: HomeCoachPresence(
                          pose: coachPose,
                          height: figureHeight,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    bottom: figureHeight * 0.42,
                    child: _warmUpLink(context),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

Widget _warmUpLink(BuildContext context) => TextButton(
      onPressed: () => context.push('/practice-collection'),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.ctaStart,
        minimumSize: const Size(44, 44),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '先去練習室熱身',
            style: AppTypography.titleSmall.copyWith(
              fontSize: 17,
              color: AppColors.ctaStart,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: AppColors.ctaStart,
          ),
        ],
      ),
    );

/// 單頁模式（起步清單完成後）：維持原本的排版與置中的 Sydney h340。
class _EmptyBlock extends StatelessWidget {
  const _EmptyBlock({required this.coachPose, required this.showWarmUpLink});

  final HomeCoachPose coachPose;

  /// 起步清單完成後就不再顯示「先去練習室熱身」（Eric 2026-08-13 拍板）；
  /// 練習室入口仍在學習分頁。
  final bool showWarmUpLink;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _EmptyHead(),
        Text(
          '一個人一張卡。不同日期、IG、LINE 或交友軟體的聊天，都整理在同一張卡裡。',
          textAlign: TextAlign.center,
          style: AppTypography.bodySmall.copyWith(
            fontSize: 13,
            color: AppColors.onBackgroundSecondary.withValues(alpha: 0.8),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 32),
        BrandPrimaryButton(
          label: '建立對象卡，開始分析',
          icon: Icons.person_add_alt_1_rounded,
          onPressed: () => context.push('/partner/new'),
        ),
        if (showWarmUpLink) ...[
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerLeft, child: _warmUpLink(context)),
        ],
        // Sydney 維持原本的置中 h340。
        HomeCoachPresence(pose: coachPose, height: 340),
      ],
    );
  }
}
