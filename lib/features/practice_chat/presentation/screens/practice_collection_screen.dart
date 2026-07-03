// 角色圖鑑（gacha Collection）：60 位陪練女孩的收藏頁。
//
// display-only：稀有度／星等純前端呈現，不影響翻牌機率或扣費。解鎖集合來自
// practiceCollectionProvider（settings box 持久化），翻牌成功／還原舊場即時 +1。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../subscription/data/providers/subscription_providers.dart';
import '../../data/providers/practice_chat_providers.dart';
import '../../domain/entities/practice_girl_catalog.dart';
import '../../domain/entities/practice_girl_profile.dart';
import '../../domain/entities/practice_girl_rarity.dart';

/// 稀有度主色：SR 金、R 紫、N 冷灰藍。只用於邊框／badge／星等（display-only）。
Color _rarityColor(PracticeGirlRarity rarity) {
  switch (rarity) {
    case PracticeGirlRarity.sr:
      return const Color(0xFFFFB34D);
    case PracticeGirlRarity.r:
      return AppColors.primaryLight;
    case PracticeGirlRarity.n:
      return const Color(0xFF8FA0BE);
  }
}

/// 鎖卡剪影：灰階×0.07 近全黑，只留人形輪廓隱約可辨。
const List<double> _silhouetteMatrix = <double>[
  0.0149, 0.0501, 0.0051, 0, 0, //
  0.0149, 0.0501, 0.0051, 0, 0, //
  0.0149, 0.0501, 0.0051, 0, 0, //
  0, 0, 0, 1, 0, //
];

class PracticeCollectionScreen extends ConsumerStatefulWidget {
  const PracticeCollectionScreen({super.key});

  @override
  ConsumerState<PracticeCollectionScreen> createState() =>
      _PracticeCollectionScreenState();
}

class _PracticeCollectionScreenState
    extends ConsumerState<PracticeCollectionScreen>
    with SingleTickerProviderStateMixin {
  /// null＝全部；否則只顯示該稀有度。
  PracticeGirlRarity? _filter;

  /// 今日未翻的翻牌鈕脈動微光。repeat 鐵則：只在 !isRevealed && !reduceMotion
  /// 時跑；revealed／reduce-motion／dispose 一律 stop（不然 pumpAndSettle 會 hang）。
  late final AnimationController _drawPulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void dispose() {
    _drawPulse.dispose();
    super.dispose();
  }

  /// 翻牌鈕 gating（語義照抄 practice_chat_screen._requestNewPartner，兩態分流）。
  /// 鐵律：本頁絕不 read-then-navigate autoDispose controller；build 有 watch
  /// 掛著 listener，這裡的 read 只是取當下值。
  void _onDrawPressed() {
    final state = ref.read(practiceChatControllerProvider);
    if (state.isDrawing) return; // 防連點

    final notifier = ref.read(practiceChatControllerProvider.notifier);

    if (!state.isRevealed) {
      // locked（今日首抽）：Free 每日首抽免費，直接翻（比照 _PracticeLockedEntry）。
      if (state.drawUpgradeRequired) {
        context.push('/paywall');
        return;
      }
      if (state.drawQuotaExceeded) {
        _showDrawSnackBar(state.errorMessage ?? '額度已用完，明天中午會重置。');
        return;
      }
      notifier.drawNewPracticeGirl();
      return;
    }

    // revealed（換一位）：Free／已標升級 → 付費牆。
    final subscription = ref.read(subscriptionProvider);
    if (subscription.isFreeUser || state.drawUpgradeRequired) {
      context.push('/paywall');
      return;
    }

    if (state.drawQuotaExceeded) {
      notifier.lockDrawQuotaExceeded();
      _showDrawSnackBar(
        ref.read(practiceChatControllerProvider).errorMessage ??
            '今日額度已用完，明天再來或升級方案繼續練習。',
      );
      return;
    }

    if (_hasInsufficientPaidDrawQuota(subscription, state)) {
      notifier.lockDrawQuotaExceeded();
      _showDrawSnackBar(
        ref.read(practiceChatControllerProvider).errorMessage ??
            '今日額度已用完，明天再來或升級方案繼續練習。',
      );
      return;
    }

    if (_needsPaidDrawConfirmation(state)) {
      _confirmPaidDraw(state);
      return;
    }

    notifier.drawNewPracticeGirl();
  }

  /// 免費次數用完要扣額度：圖鑑頁沒有 inline notice 區，改 AlertDialog 確認。
  Future<void> _confirmPaidDraw(PracticeChatState state) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.brandSurface,
        title: Text(
          '要扣額度翻牌嗎？',
          style: AppTypography.titleMedium.copyWith(
            color: AppColors.onBackgroundPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          _paidDrawSpendMessage(state),
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.onBackgroundSecondary,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('collection-draw-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('collection-draw-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.ctaStart,
              foregroundColor: Colors.white,
            ),
            child: const Text('確認翻牌'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    ref.read(practiceChatControllerProvider.notifier).drawNewPracticeGirl();
  }

  // ── 以下三個 helper 語義照抄 practice_chat_screen（Task 7 才收殺原件）──

  bool _needsPaidDrawConfirmation(PracticeChatState state) {
    final remaining = state.drawFreeRemaining;
    final cost = state.drawExtraCost ?? 0;
    return remaining != null && remaining <= 0 && cost > 0;
  }

  bool _hasInsufficientPaidDrawQuota(
    SubscriptionState subscription,
    PracticeChatState state,
  ) {
    final cost = state.drawExtraCost ?? 0;
    if (cost <= 0 || !_needsPaidDrawConfirmation(state)) return false;
    return subscription.dailyRemaining < cost ||
        subscription.monthlyRemaining < cost;
  }

  String _paidDrawSpendMessage(PracticeChatState state) {
    final allowance = state.drawFreeAllowance;
    final cost = state.drawExtraCost ?? 5;
    if (allowance != null && allowance > 0) {
      return '今日 $allowance 次免費換一位已用完，再按一次會扣 $cost 則額度。';
    }
    return '再按一次會扣 $cost 則額度。';
  }

  void _showDrawSnackBar(String message, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }

  /// repeat 嚴格 gate：build 期同步校正（watch 的 state 一變就會重進來）。
  void _syncDrawPulse({required bool shouldPulse}) {
    if (shouldPulse) {
      if (!_drawPulse.isAnimating) _drawPulse.repeat(reverse: true);
    } else if (_drawPulse.isAnimating || _drawPulse.value != 0) {
      _drawPulse.stop();
      _drawPulse.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = ref.watch(practiceCollectionProvider);
    final unlockedCount = ref.watch(unlockedPracticeGirlCountProvider);
    // 翻牌鈕兩態顯示必須 watch：同時讓 autoDispose controller 在本頁存活。
    final chatState = ref.watch(practiceChatControllerProvider);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _syncDrawPulse(shouldPulse: !chatState.isRevealed && !reduceMotion);

    // 402/429 事後錯誤呈現：只攔「翻牌在途 → 收場」的轉場（同步 gating 的
    // snackbar 由 _onDrawPressed 自己出，不會雙發）。
    ref.listen(practiceChatControllerProvider, (prev, next) {
      if (prev == null || !prev.isDrawing || next.isDrawing) return;
      if (next.drawUpgradeRequired) {
        _showDrawSnackBar(
          next.errorMessage ?? '升級後每天可以翻更多陪練女孩。',
          action: SnackBarAction(
            label: '升級',
            onPressed: () {
              if (mounted) context.push('/paywall');
            },
          ),
        );
      } else if (next.drawQuotaExceeded || next.errorMessage != null) {
        _showDrawSnackBar(next.errorMessage ?? '翻牌失敗了，再試一次。');
      }
    });

    final total = practiceGirlProfiles.length;
    final visible = _filter == null
        ? practiceGirlProfiles
        : practiceGirlProfiles
            .where((p) => practiceGirlRarityFor(p.personaId) == _filter)
            .toList(growable: false);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          '角色圖鑑',
          style: AppTypography.titleMedium.copyWith(
            color: AppColors.onBackgroundPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.onBackgroundPrimary),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.backgroundGradientStart,
              AppColors.backgroundGradientMid,
              AppColors.backgroundGradientEnd,
            ],
          ),
        ),
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _CollectionHeader(
                  unlockedCount: unlockedCount,
                  total: total,
                  drawPulse: _drawPulse,
                  drawIsDrawing: chatState.isDrawing,
                  onDrawPressed: _onDrawPressed,
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: Row(
                    children: [
                      _RarityFilterChip(
                        chipKey: const ValueKey('collection-filter-all'),
                        label: '全部',
                        selected: _filter == null,
                        onTap: () => setState(() => _filter = null),
                      ),
                      const SizedBox(width: 8),
                      for (final rarity in PracticeGirlRarity.values) ...[
                        _RarityFilterChip(
                          chipKey: ValueKey(
                              'collection-filter-${rarity.label.toLowerCase()}'),
                          label: rarity.label,
                          selected: _filter == rarity,
                          onTap: () => setState(() => _filter = rarity),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                sliver: SliverGrid.builder(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.62,
                  ),
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final profile = visible[index];
                    return _CollectionCard(
                      profile: profile,
                      unlocked: unlocked.contains(profile.profileId),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 頁首：eyebrow → 漸層大標＋右側翻牌鈕 → 圖鑑副標 → 完成度數字＋漸層進度條。
class _CollectionHeader extends StatelessWidget {
  const _CollectionHeader({
    required this.unlockedCount,
    required this.total,
    required this.drawPulse,
    required this.drawIsDrawing,
    required this.onDrawPressed,
  });

  final int unlockedCount;
  final int total;
  final Animation<double> drawPulse;
  final bool drawIsDrawing;
  final VoidCallback onDrawPressed;

  @override
  Widget build(BuildContext context) {
    final progress =
        total == 0 ? 0.0 : (unlockedCount / total).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'VIBESYNC · GACHA',
            style: AppTypography.caption.copyWith(
              color: AppColors.brandFlame,
              fontWeight: FontWeight.w700,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [
                      Color(0xFFFFC24D),
                      AppColors.brandFlame,
                      AppColors.brandBlush,
                    ],
                  ).createShader(bounds),
                  child: Text(
                    'Collection',
                    style: AppTypography.headlineLarge.copyWith(
                      color: Colors.white, // ShaderMask srcIn 取代此色
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _CollectionDrawButton(
                pulse: drawPulse,
                isDrawing: drawIsDrawing,
                onPressed: onDrawPressed,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '角 色 圖 鑑',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 6,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$unlockedCount',
                key: const ValueKey('collection-completion-count'),
                style: AppTypography.headlineLarge.copyWith(
                  color: AppColors.brandFlame,
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                ' / $total',
                style: AppTypography.titleLarge.copyWith(
                  color: AppColors.onBackgroundSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'COMPLETION 完成度',
            style: AppTypography.caption.copyWith(
              color: AppColors.onBackgroundSecondary,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: 8,
              color: Colors.white.withValues(alpha: 0.08),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: progress,
                heightFactor: 1,
                child: Container(
                  key: const ValueKey('collection-progress-fill'),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.brandBlush, AppColors.brandFlame],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 標題右側的翻牌鈕：金橘漸層膠囊（配頁面大標視覺）＋微光。今日未翻時由
/// [pulse]（repeat 呼吸）驅動 boxShadow alpha；revealed 時 pulse 停在 0＝定光。
class _CollectionDrawButton extends StatelessWidget {
  const _CollectionDrawButton({
    required this.pulse,
    required this.isDrawing,
    required this.onPressed,
  });

  final Animation<double> pulse;
  final bool isDrawing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, child) {
        final glow = 0.28 + 0.34 * pulse.value;
        return GestureDetector(
          key: const ValueKey('collection-draw-button'),
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFC24D), AppColors.brandFlame],
              ),
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandFlame.withValues(alpha: glow),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isDrawing)
            const SizedBox(
              height: 14,
              width: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.brandInk,
              ),
            )
          else
            const Icon(
              Icons.style_rounded,
              size: 16,
              color: AppColors.brandInk,
            ),
          const SizedBox(width: 6),
          Text(
            '翻牌',
            style: AppTypography.titleSmall.copyWith(
              color: AppColors.brandInk,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _RarityFilterChip extends StatelessWidget {
  const _RarityFilterChip({
    required this.chipKey,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Key chipKey;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: chipKey,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.brandFlame.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? AppColors.brandFlame
                : Colors.white.withValues(alpha: 0.14),
          ),
        ),
        child: Text(
          label,
          style: AppTypography.caption.copyWith(
            color: selected
                ? AppColors.brandFlame
                : AppColors.onBackgroundSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({required this.profile, required this.unlocked});

  final PracticeGirlProfile profile;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    final rarity = practiceGirlRarityFor(profile.personaId);
    final color = _rarityColor(rarity);

    return GestureDetector(
      key: ValueKey('collection-card-${profile.profileId}'),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (unlocked) {
          // 已抽卡直進練習室：profileId 走路由 query、開局由對話頁自己發起
          // （controller 是 autoDispose，在這裡先 read+seed 會在導航間隙零
          // listener 被 dispose）。看大圖由對話頁 profile sheet 承擔。
          context.push('/practice-chat?profileId=${profile.profileId}');
          return;
        }
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('每日翻牌有機會遇到她')));
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.brandSurface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            width: 1.5,
            color: unlocked
                ? color.withValues(alpha: 0.85)
                : Colors.white.withValues(alpha: 0.10),
          ),
          boxShadow: unlocked
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.24),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _CollectionCardPhoto(profile: profile, locked: !unlocked),
                    if (unlocked)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            rarity.label,
                            style: AppTypography.caption.copyWith(
                              color: AppColors.brandInk,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      )
                    else
                      Center(
                        child: Text(
                          '？',
                          key: ValueKey(
                              'collection-mystery-${profile.profileId}'),
                          style: AppTypography.headlineLarge.copyWith(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 44,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              unlocked ? profile.displayName : '？？？',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.titleSmall.copyWith(
                color: unlocked ? Colors.white : Colors.white70,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              unlocked ? profile.professionLabel : '每日翻牌解鎖',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption.copyWith(
                color: unlocked
                    ? AppColors.onBackgroundSecondary
                    : Colors.white38,
              ),
            ),
            const SizedBox(height: 6),
            if (unlocked)
              Row(
                children: [
                  for (var i = 0; i < 5; i++)
                    Icon(
                      i < rarity.stars
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 14,
                      color: i < rarity.stars
                          ? color
                          : Colors.white.withValues(alpha: 0.18),
                    ),
                ],
              )
            else
              const SizedBox(height: 14), // 鎖卡無星等：佔位維持排版高度
          ],
        ),
      ),
    );
  }
}

/// 收藏頁專用縮圖：60 張同屏必 cacheWidth 降採樣，不解全尺寸原圖。
/// PracticeGirlPhoto 不支援 cacheWidth，故此頁自建輕量版（fallback 行為比照）。
class _CollectionCardPhoto extends StatelessWidget {
  const _CollectionCardPhoto({required this.profile, required this.locked});

  final PracticeGirlProfile profile;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    Widget image = Image.asset(
      profile.photoAssetPath,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      filterQuality: FilterQuality.low,
      cacheWidth: 360,
      errorBuilder: (context, error, stack) => _fallback(),
    );
    if (!locked) return image;
    // 鎖卡：剪影矩陣壓到近全黑（保輪廓不露細節），overlay 只做勻化。
    image = ColorFiltered(
      colorFilter: const ColorFilter.matrix(_silhouetteMatrix),
      child: image,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        DecoratedBox(
          decoration:
              BoxDecoration(color: Colors.black.withValues(alpha: 0.25)),
        ),
      ],
    );
  }

  /// asset 載入失敗：profileId 決定的穩定底色＋首字母，永不 crash
  /// （比照 PracticeGirlPhoto 的 fallback 行為；鎖卡不顯示首字母）。
  Widget _fallback() {
    final hue = (profile.profileId.hashCode % 360).abs().toDouble();
    final bg = HSLColor.fromAHSL(1, hue, 0.42, 0.52).toColor();
    final initial = profile.displayName.isNotEmpty
        ? profile.displayName.substring(0, 1)
        : '?';
    return Container(
      alignment: Alignment.center,
      color: bg,
      child: Text(
        locked ? '?' : initial,
        style: AppTypography.bodyMedium.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 32,
        ),
      ),
    );
  }
}

/// learning 頁「練習專區」header 右側的圖鑑入口 chip（橘框膠囊）。
/// N 即時反映解鎖數（watch practiceCollectionProvider 衍生 count）。
class PracticeCollectionEntryChip extends ConsumerWidget {
  const PracticeCollectionEntryChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(unlockedPracticeGirlCountProvider);
    final total = practiceGirlProfiles.length;
    return GestureDetector(
      key: const ValueKey('practice-collection-entry-chip'),
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/practice-collection'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.brandFlame.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border:
              Border.all(color: AppColors.brandFlame.withValues(alpha: 0.7)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.style_rounded,
                size: 14, color: AppColors.brandFlame),
            const SizedBox(width: 5),
            Text(
              '角色圖鑑 $count/$total',
              style: AppTypography.caption.copyWith(
                color: AppColors.brandFlame,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
