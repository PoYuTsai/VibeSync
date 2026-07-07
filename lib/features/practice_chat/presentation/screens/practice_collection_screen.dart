// 角色圖鑑（gacha Collection）：陪練女孩的收藏頁。
//
// 稀有度每卡獨立（鏡像 server 真相源）；抽中機率由 server 加權（SR 10%／R 30%／
// N 60%），本頁只負責呈現（邊框／badge／星等），不影響扣費。解鎖集合來自
// practiceCollectionProvider（settings box 持久化），翻牌成功／還原舊場即時 +1。
import 'dart:async';

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
import '../widgets/practice_draw_ceremony.dart';
import '../widgets/practice_rarity_style.dart';

/// 揭曉後新卡微光的等待段：等整條儀式 reveal 時間軸走完才點亮（儀式 scrim 中段
/// 全黑，蓋著點了也看不到）。與儀式共用同一常數＝儀式重定時不會讓微光搶跑。
@visibleForTesting
const Duration kCollectionHighlightWait = kPracticeRevealDuration;

/// 揭曉後新卡微光的微光段長度（亮起→停留→淡出）。
@visibleForTesting
const Duration kCollectionHighlightGlow = Duration(milliseconds: 1500);

/// 高亮時間軸（0→1）映微光強度：等待段（儀式收場前）恆 0；進微光段後
/// 快亮起（前 18%）→ 停留 → 淡出（後 38%），收尾歸 0 不殘留。
@visibleForTesting
double collectionHighlightIntensityAt(double t) {
  final totalMs =
      (kCollectionHighlightWait + kCollectionHighlightGlow).inMilliseconds;
  final glowStart = kCollectionHighlightWait.inMilliseconds / totalMs;
  if (t <= glowStart) return 0;
  final g = ((t - glowStart) / (1 - glowStart)).clamp(0.0, 1.0);
  if (g < 0.18) return g / 0.18;
  if (g < 0.62) return 1;
  return (1 - (g - 0.62) / 0.38).clamp(0.0, 1.0);
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
    with TickerProviderStateMixin {
  /// null＝全部；否則只顯示該稀有度。
  PracticeGirlRarity? _filter;

  /// grid 版面常數：估算新卡捲動位置（[_estimatedCardOffset]）與 sliver 版面
  /// 共用單一真相，改版面不會讓捲動定位漂掉。
  static const int _gridCrossAxisCount = 2;
  static const double _gridSidePadding = 16;
  static const double _gridTopPadding = 16;
  static const double _gridBottomPadding = 32;
  static const double _gridSpacing = 12;
  static const double _gridAspectRatio = 0.62;

  /// 今日未翻的翻牌鈕脈動微光。repeat 鐵則：只在 !isRevealed && !reduceMotion
  /// 時跑；revealed／reduce-motion／dispose 一律 stop（不然 pumpAndSettle 會 hang）。
  late final AnimationController _drawPulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  /// 揭曉後新卡的邊框微光：**單次** forward，時間軸＝「等待段＋微光段」
  /// （[kCollectionHighlightWait] + [kCollectionHighlightGlow]）。
  ///
  /// 等待段的存在理由：解鎖通知在抽牌成功當下發＝儀式 reveal 時間軸起點，而儀式
  /// scrim 中段全黑不透明會把圖鑑整頁蓋死——微光若即時點亮，交棒時早已走完、
  /// 使用者根本看不到。故非 reduce-motion 從 0 起跑（前段強度恆 0，等儀式收場才
  /// 亮）；reduce-motion 沒有儀式時間軸，直接從微光段起跑。等待用 controller 幀
  /// 驅動而非 `Future.delayed`：不留 pending Timer（pumpAndSettle 可推完收斂）。
  /// 走完即在 status listener 清掉 [_highlightProfileId]，絕不 repeat。
  late final AnimationController _highlight = AnimationController(
    vsync: this,
    duration: kCollectionHighlightWait + kCollectionHighlightGlow,
  )..addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _highlightProfileId = null);
      }
    });

  /// 微光段在整條高亮時間軸上的起點 fraction（reduce-motion 的 forward 起點）。
  static final double _glowStartFraction =
      kCollectionHighlightWait.inMilliseconds /
          (kCollectionHighlightWait + kCollectionHighlightGlow).inMilliseconds;

  final ScrollController _scrollController = ScrollController();

  /// 新解鎖待高亮的卡；掛 [GlobalKey] 供 ensureVisible 精準定位。
  String? _highlightProfileId;
  final GlobalKey _highlightCardKey = GlobalKey();

  @override
  void dispose() {
    _drawPulse.dispose();
    _highlight.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 目前 filter 下 grid 實際顯示的清單（build 與捲動估算共用）。
  /// 已解鎖置頂、鎖卡沉底，兩組內都維持 catalog 原序。
  List<PracticeGirlProfile> _visibleProfiles() {
    final unlocked = ref.read(practiceCollectionProvider);
    final filtered = _filter == null
        ? practiceGirlProfiles
        : practiceGirlProfiles.where((p) => p.rarity == _filter);
    return [
      ...filtered.where((p) => unlocked.contains(p.profileId)),
      ...filtered.where((p) => !unlocked.contains(p.profileId)),
    ];
  }

  /// 集合新增（翻牌解鎖）→ 收掉會濾掉新卡的稀有度 filter、捲動定位＋微光高亮。
  void _onProfileUnlocked(PracticeGirlProfile profile) {
    setState(() {
      if (_filter != null && profile.rarity != _filter) {
        _filter = null; // filter 開著時新卡可能不在 visible 清單：先收掉。
      }
      _highlightProfileId = profile.profileId;
    });
    _highlight
      ..stop()
      ..value = 0;
    // 等 filter／highlight 的重建落地後才捲（新卡要先進 visible 清單）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToHighlight(profile.profileId);
    });
  }

  /// 兩段捲動定位：builder 惰性 grid 裡遠處的新卡尚未 build（拿不到 context），
  /// 先用版面常數估算 offset 捲近，讓卡片 build 出來後再 ensureVisible 精準對齊，
  /// 最後才點亮單次微光。
  Future<void> _scrollToHighlight(String profileId) async {
    if (!mounted || _highlightProfileId != profileId) return;
    if (_highlightCardKey.currentContext == null &&
        _scrollController.hasClients) {
      final estimated = _estimatedCardOffset(profileId);
      if (estimated != null) {
        await _scrollController.animateTo(
          estimated.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      }
    }
    if (!mounted || _highlightProfileId != profileId) return;
    final cardContext = _highlightCardKey.currentContext;
    if (cardContext != null && cardContext.mounted) {
      await Scrollable.ensureVisible(
        cardContext,
        alignment: 0.35,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    }
    if (!mounted || _highlightProfileId != profileId) return;
    // 非 reduce-motion：儀式 scrim 還蓋在圖鑑上（捲動照舊即時做沒差，收掉時卡
    // 已在視野內），微光從等待段起跑、儀式收場才亮；reduce-motion 直接進微光段。
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _highlight.forward(from: reduceMotion ? _glowStartFraction : 0);
  }

  /// 由捲動 metrics 反推新卡所在 row 的 offset：
  /// 總內容高 = maxScrollExtent + viewport；grid 段高可由版面常數精算，
  /// 差值即 grid 之前（header＋filter chips）的高度。
  /// 注意：此推導假設 grid（含其 SliverPadding）是**最後一個 sliver**；
  /// 若之後在 grid 後面加 sliver，這裡要跟著扣掉其高度。
  double? _estimatedCardOffset(String profileId) {
    final visible = _visibleProfiles();
    final index = visible.indexWhere((p) => p.profileId == profileId);
    if (index < 0) return null;
    final position = _scrollController.position;
    final crossExtent =
        MediaQuery.of(context).size.width - _gridSidePadding * 2;
    if (crossExtent <= 0) return null;
    final tileWidth = (crossExtent - _gridSpacing * (_gridCrossAxisCount - 1)) /
        _gridCrossAxisCount;
    final rowExtent = tileWidth / _gridAspectRatio + _gridSpacing;
    final rows =
        (visible.length + _gridCrossAxisCount - 1) ~/ _gridCrossAxisCount;
    final gridExtent = rows * rowExtent - _gridSpacing;
    final total = position.maxScrollExtent + position.viewportDimension;
    final beforeGrid =
        total - gridExtent - _gridTopPadding - _gridBottomPadding;
    final row = index ~/ _gridCrossAxisCount;
    // 粗定位刻意比 ensureVisible 的 alignment 0.35 略高（視窗 1/4 處），讓卡片
    // 先 build 出來，fine-tune 只需再小捲一段。
    return beforeGrid +
        _gridTopPadding +
        row * rowExtent -
        position.viewportDimension * 0.25;
  }

  /// 翻牌鈕 gating（練習室舊 _requestNewPartner 的語義搬家，原件已刪，兩態分流）。
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
        _showDrawSnackBar(state.errorMessage ?? '今日額度已用完，明天再來或升級方案繼續練習。');
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

    // 免費額度用完且 payload 無加抽權（server 只對可付費加抽的 tier 帶
    // extraCost>0）→ 直接付費牆。訂閱快照 stale（付費過期降 free 未同步）時
    // 上面 isFreeUser 會放行，但 payload 是 server 真實 tier 的鏡子：這裡擋下，
    // 絕不彈「扣 5 則」dialog、絕不打 API 吃 402。
    final freeRemaining = state.drawFreeRemaining;
    if (freeRemaining != null &&
        freeRemaining <= 0 &&
        (state.drawExtraCost ?? 0) <= 0) {
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
      return '今日 $allowance 次免費換人已用完，再按一次會扣 $cost 則額度。';
    }
    return '再按一次會扣 $cost 則額度。';
  }

  void _showDrawSnackBar(String message, {SnackBarAction? action}) {
    if (!mounted) return;
    // clearSnackBars 而非 hideCurrentSnackBar：連點時後者只淡出當前那條，
    // 佇列會持續堆積並跨頁面輪播（root messenger 佇列不隨本頁 dispose）。
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
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
        // 402＝Free 額度用完（產品拍板：絕不宣傳加抽）→ 直接進付費牆。
        // 402 常代表訂閱快照 stale（付費過期降 free 未同步）→ 順帶重同步一次
        // （沿用 paywall/settings 的 refresh seam；paywall 本身 initState 也會
        // refresh，重複呼叫 idempotent）。
        if (!mounted) return;
        unawaited(ref.read(subscriptionScreenRefreshProvider)());
        context.push('/paywall');
      } else if (next.drawQuotaExceeded || next.errorMessage != null) {
        _showDrawSnackBar(next.errorMessage ?? '翻牌失敗了，再試一次。');
      }
    });

    // 揭曉後新卡高亮定位：集合新增（翻牌解鎖）時取新 id 捲動＋微光。
    ref.listen<Set<String>>(practiceCollectionProvider, (prev, next) {
      if (prev == null || next.length <= prev.length) return;
      final added = next.difference(prev);
      for (final profile in practiceGirlProfiles) {
        if (added.contains(profile.profileId)) {
          _onProfileUnlocked(profile);
          break;
        }
      }
    });

    final total = practiceGirlProfiles.length;
    final visible = _visibleProfiles();

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        // stack 被收斂（go／deep link）進本頁時 canPop=false，AppBar 自動返回
        // 鍵會消失＝死路。兜底補一顆回首頁的返回鍵；判斷用 ModalRoute.canPop
        // （與自動返回鍵同一訊號源），canPop 時交還 null 走原生自動返回鍵。
        leading: (ModalRoute.of(context)?.canPop ?? false)
            ? null
            : IconButton(
                key: const ValueKey('collection-home-back'),
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go('/'),
              ),
        title: Text(
          '角色圖鑑',
          style: AppTypography.titleMedium.copyWith(
            color: AppColors.onBackgroundPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.onBackgroundPrimary),
      ),
      body: Stack(
        children: [
          Container(
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
                controller: _scrollController,
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
                    padding: const EdgeInsets.fromLTRB(
                      _gridSidePadding,
                      _gridTopPadding,
                      _gridSidePadding,
                      _gridBottomPadding,
                    ),
                    sliver: SliverGrid.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: _gridCrossAxisCount,
                        crossAxisSpacing: _gridSpacing,
                        mainAxisSpacing: _gridSpacing,
                        childAspectRatio: _gridAspectRatio,
                      ),
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final profile = visible[index];
                        final card = _CollectionCard(
                          profile: profile,
                          unlocked: unlocked.contains(profile.profileId),
                        );
                        if (profile.profileId != _highlightProfileId) {
                          return card;
                        }
                        // 新解鎖高亮：GlobalKey 供 ensureVisible、微光包框。
                        return KeyedSubtree(
                          key: _highlightCardKey,
                          child: _UnlockHighlight(
                            profileId: profile.profileId,
                            glow: _highlight,
                            child: card,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 翻牌揭曉儀式 overlay：idle 時透明＋IgnorePointer，不影響底下互動。
          // 全 app 唯一掛載點（Task 4b 由練習室搬來：翻牌入口在本頁，儀式就地揭曉）。
          const Positioned.fill(child: PracticeDrawCeremony()),
        ],
      ),
    );
  }
}

/// 揭曉後新卡的單次微光高亮：邊框金光亮起→淡出，由單一 forward-only controller
/// 驅動（走完由 screen 清掉高亮 id，本 widget 隨之卸載，絕不常駐）。強度映射
/// 見 [collectionHighlightIntensityAt]（等待段恆 0＝儀式 scrim 蓋著時不白亮）。
class _UnlockHighlight extends StatelessWidget {
  const _UnlockHighlight({
    required this.profileId,
    required this.glow,
    required this.child,
  });

  final String profileId;
  final Animation<double> glow;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: glow,
      builder: (context, inner) {
        final intensity = collectionHighlightIntensityAt(glow.value);
        return Container(
          key: ValueKey('collection-highlight-$profileId'),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              width: 2,
              color: const Color(0xFFFFC24D).withValues(alpha: 0.9 * intensity),
            ),
          ),
          decoration: intensity <= 0.001
              ? null
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.brandFlame
                          .withValues(alpha: 0.5 * intensity),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
          child: inner,
        );
      },
      child: child,
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
    final progress = total == 0 ? 0.0 : (unlockedCount / total).clamp(0.0, 1.0);
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
            '收藏完成度',
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
    final rarity = profile.rarity;
    final color = practiceRarityColor(rarity);

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
          ..clearSnackBars()
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
                        child: PracticeRarityBadge(rarity: rarity),
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
                color:
                    unlocked ? AppColors.onBackgroundSecondary : Colors.white38,
              ),
            ),
            const SizedBox(height: 6),
            if (unlocked)
              PracticeRarityStars(rarity: rarity)
            else
              const SizedBox(height: 14), // 鎖卡無星等：佔位維持排版高度
          ],
        ),
      ),
    );
  }
}

/// 收藏頁專用縮圖：大量同屏時必 cacheWidth 降採樣，不解全尺寸原圖。
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
