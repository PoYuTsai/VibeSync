// 角色圖鑑（gacha Collection）：陪練女孩的收藏頁。
//
// 稀有度每卡獨立（鏡像 server 真相源）；抽中機率由 server 加權（SR 10%／R 30%／
// N 60%），本頁只負責呈現（邊框／badge／星等），不影響扣費。解鎖集合來自
// practiceCollectionProvider（server 的翻牌事件為唯一真相源），翻牌成功即時 +1。
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/app_haptics.dart';
import '../../../../core/services/funnel_tracker.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../subscription/data/providers/subscription_providers.dart';
import '../../../subscription/presentation/paywall_entry.dart';
import '../../../subscription/presentation/quota_copy.dart';
import '../../data/providers/practice_chat_providers.dart';
import '../../domain/entities/practice_girl_catalog.dart';
import '../../domain/entities/practice_girl_profile.dart';
import '../../domain/entities/practice_girl_rarity.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../widgets/practice_draw_ceremony.dart';
import '../widgets/practice_rarity_style.dart';
import '../widgets/practice_reveal_theme.dart';

/// 新卡那一格的發光長度（亮起→停留→淡出）。由儀式收卡的光球落位那一刻起跑，
/// 不再固定等一段時間（V3 停多久由使用者決定）。
@visibleForTesting
const Duration kCollectionHighlightGlow = Duration(milliseconds: 1500);

/// 首抽還在發的時候按翻牌，最多等它這麼久；逾時就照常送出、由 server 裁決（首抽之後
/// 才到時，補水會解除 402 的鎖）。
@visibleForTesting
const Duration kFirstDrawGrantWait = Duration(seconds: 10);

/// 發光時間軸（0→1）映強度：前 8%（約 120 ms）快速亮起，接住光球落位那一下 →
/// 停留到 40% → 淡出，收尾歸 0 不殘留。
@visibleForTesting
double collectionHighlightIntensityAt(double t) {
  final g = t.clamp(0.0, 1.0);
  if (g < 0.08) return g / 0.08;
  if (g < 0.4) return 1;
  return (1 - (g - 0.4) / 0.6).clamp(0.0, 1.0);
}

/// 鎖卡剪影：灰階×0.07 近全黑，只留人形輪廓隱約可辨。
const List<double> _silhouetteMatrix = <double>[
  0.0149, 0.0501, 0.0051, 0, 0, //
  0.0149, 0.0501, 0.0051, 0, 0, //
  0.0149, 0.0501, 0.0051, 0, 0, //
  0, 0, 0, 1, 0, //
];

class PracticeCollectionScreen extends ConsumerStatefulWidget {
  const PracticeCollectionScreen({
    super.key,
    this.showOnboardingGuide = false,
  });

  /// onboarding 第 1 頁「還沒有對象，想先練」落地引導：Sydney 泡泡指向翻牌鈕。
  /// 只由 `/practice-collection?guide=1` 帶進來（onboarding 一生只完成一次，
  /// 查詢參數天然只出現那一次），其他入口一律 false，不需要持久化旗標。
  final bool showOnboardingGuide;

  @override
  ConsumerState<PracticeCollectionScreen> createState() =>
      _PracticeCollectionScreenState();
}

class _PracticeCollectionScreenState
    extends ConsumerState<PracticeCollectionScreen>
    with TickerProviderStateMixin {
  /// 落地引導是否還在畫面上；任一點擊即收，不重現。
  late bool _guideVisible = widget.showOnboardingGuide;

  /// null＝全部；否則只顯示該稀有度。
  PracticeGirlRarity? _filter;

  @override
  void initState() {
    super.initState();
    // 額度列 v2：進場唯讀補水本窗翻牌額度（跨 session 也準確）。fail-quiet
    // 在 controller 內；post-frame 才 read＝避開 initState 期碰 provider。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref
            .read(practiceChatControllerProvider.notifier)
            .refreshDrawQuotaStatus(),
      );
      final grant = _maybeGrantFirstDraw();
      _firstDrawGrant = grant;
      unawaited(grant.whenComplete(() => _firstDrawGrant = null));
    });
  }

  /// 進場發首抽還在路上（付費帳號、已有角色時馬上就結束）；結束就清掉。
  Future<void>? _firstDrawGrant;

  /// 按了翻牌、正在等首抽發完：翻牌鈕轉圈、先不送出（Codex 主審第 1 輪 P2）。
  bool _waitingForFirstDrawGrant = false;

  /// 沒對象的新用戶不能一按翻牌就撞付費頁（Onboarding 第 1 步，決策 C，Eric
  /// 2026-10-27）：免費帳號走進練習室、圖鑑一張都沒有，就先把那一次免費翻牌發給他。
  /// onboarding、首頁、學習頁、起步清單四個入口都走到這一頁，所以發在這裡。
  /// 伺服器一人一列、重呼冪等（`grant_onboarding_draw_bonus`），發過再呼叫也不會多。
  /// 發成功才重新補水額度列（「免費首抽 剩 1 次」）；任何失敗都吞掉、不擋畫面，
  /// 按翻牌照舊走 402 → 付費頁。
  Future<void> _maybeGrantFirstDraw() async {
    try {
      if (!ref.read(subscriptionProvider).isFreeUser) return;
      // 圖鑑還在讀時的 0 不算數：等讀完、確定一張都沒有才發；讀不到就不發。
      await ref.read(practiceCollectionProvider.future);
      if (!mounted) return;
      if (!ref.read(subscriptionProvider).isFreeUser ||
          ref.read(unlockedPracticeGirlCountProvider) > 0) {
        return;
      }
      await ref.read(practiceChatApiServiceProvider).grantOnboardingDrawBonus();
      if (!mounted) return;
      await ref
          .read(practiceChatControllerProvider.notifier)
          .refreshDrawQuotaStatus();
    } catch (_) {
      // fail-quiet：沒發成就維持現狀，額度列照舊、翻牌由 server 裁決。
    }
  }

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

  /// 剛抽到那一格的邊框發光：**單次** forward（[kCollectionHighlightGlow]）。
  ///
  /// 由儀式收卡的光球落位（[_onCeremonyArchived]）起跑——儀式停多久由使用者決定，
  /// 不能再固定等一段時間。捲動還沒到位時先記著，到位才亮，免得亮在畫面外。
  /// 走完即在 status listener 清掉 [_highlightProfileId]，絕不 repeat。
  late final AnimationController _highlight = AnimationController(
    vsync: this,
    duration: kCollectionHighlightGlow,
  )..addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _highlightProfileId = null);
      }
    });

  final ScrollController _scrollController = ScrollController();

  /// 揭曉中的這張卡；掛 [GlobalKey] 供捲動定位與收卡光球找目標格。
  String? _highlightProfileId;
  final GlobalKey _highlightCardKey = GlobalKey();

  /// 捲到這張卡的兩段捲動還在跑。
  bool _scrollingToHighlight = false;

  /// 光球已落位但捲動還沒到位：到位後才亮。
  bool _glowPending = false;

  /// 這次抽牌開始時的已解鎖集合：揭曉時判斷新角色或重複角色（V3.1 規格 §5.14）。
  /// null＝沒有紀錄（抽牌中離開圖鑑又回來），儀式不掛 NEW 也不寫「已收藏」。
  Set<String>? _unlockedAtDrawStart;

  /// 儀式期間標題先顯示抽之前的數字（抽中後的 +1 會先在儀式底下到）；光球落位才換成
  /// 新數字並跳一下。null＝照實際數字顯示。
  int? _heldUnlockedCount;

  /// 這次抽到的新角色已經落位、但她的解鎖還沒到（存草稿比儀式慢）：解鎖到的那一刻才跳。
  /// 只等這一位；別的角色造成的數字變化只更新、不跳。
  String? _bumpOnUnlockProfileId;

  /// 「已收集」數字落位時跳一下：放大到 1.25 倍再回來、顏色閃一下那張卡的光色。單次
  /// forward，不 repeat；長度用 AppMotion 的慶祝檔。
  late final AnimationController _countBump = AnimationController(
    vsync: this,
    duration: AppMotion.celebrate,
  );
  Color _countBumpColor = AppColors.ctaStart;

  @override
  void dispose() {
    _drawPulse.dispose();
    _highlight.dispose();
    _countBump.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 目前 filter 下 grid 實際顯示的清單（build 與捲動估算共用）。
  /// 已解鎖置頂、鎖卡沉底，兩組內都維持 catalog 原序。
  List<PracticeGirlProfile> _visibleProfiles() {
    final unlocked = {
      ...ref.read(practiceUnlockedProfileIdsProvider),
      // 揭曉中的這張卡已經抽中，但圖鑑的樂觀 +1 要等抽卡流程存完草稿才到，可能晚一兩幀。
      // 先把它排進已解鎖那一段，捲動估算與收卡光球的目標才不會指到它還沒解鎖時的位置。
      if (_highlightProfileId != null) _highlightProfileId!,
    };
    final filtered = _filter == null
        ? practiceGirlProfiles
        : practiceGirlProfiles.where((p) => p.rarity == _filter);
    return [
      ...filtered.where((p) => unlocked.contains(p.profileId)),
      ...filtered.where((p) => !unlocked.contains(p.profileId)),
    ];
  }

  /// 儀式揭曉開始（reduce-motion 為抽中當下）：收掉會濾掉這張卡的稀有度 filter、
  /// 標記並捲動到位。新卡與集滿後抽到的重複角色都走這裡；發光等光球落位。
  void _onRevealTarget(PracticeGirlProfile profile) {
    if (!mounted) return;
    setState(() {
      if (_filter != null && profile.rarity != _filter) {
        _filter = null; // filter 開著時這張卡可能不在 visible 清單：先收掉。
      }
      _highlightProfileId = profile.profileId;
    });
    _highlight
      ..stop()
      ..value = 0;
    _glowPending = false;
    _scrollingToHighlight = true;
    // 等 filter／highlight 的重建落地後才捲（這張卡要先進 visible 清單）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_scrollToHighlight(profile.profileId));
    });
  }

  /// 儀式揭曉時問：這位是不是這次才解鎖（抽牌前的紀錄裡沒有她）。
  bool? _isNewProfile(String profileId) {
    final before = _unlockedAtDrawStart;
    if (before == null) return null;
    return !before.contains(profileId);
  }

  /// 標題數字換回實際值。只有這次抽到的是新角色、而且她的解鎖已經到了才跳一下；解鎖晚到
  /// 就等到的那一刻再跳。重複角色、別的角色造成的數字變化只更新、不跳。
  void _releaseHeldCount(String profileId) {
    final isNew = _isNewProfile(profileId) ?? false;
    _unlockedAtDrawStart = null;
    if (_heldUnlockedCount == null) return;
    setState(() => _heldUnlockedCount = null);
    if (!isNew) return;
    if (ref.read(practiceUnlockedProfileIdsProvider).contains(profileId)) {
      _bumpCount(profileId);
    } else {
      _bumpOnUnlockProfileId = profileId;
    }
  }

  /// 「已收集」數字跳一下，顏色閃那張卡的光色（reduce-motion 不跳）。
  void _bumpCount(String profileId) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return;
    setState(() {
      _countBumpColor =
          PracticeRevealTheme.of(practiceGirlRarityFor(profileId)).orb;
    });
    _countBump.forward(from: 0);
  }

  /// 收卡光球落位：標題數字 +1、點亮那一格。捲動還沒到位就先記著，到位再亮
  /// （reduce-motion 在抽中當下就會呼叫，這時捲動通常還在跑）。
  void _onCeremonyArchived(String profileId) {
    if (!mounted) return;
    _releaseHeldCount(profileId);
    if (_highlightProfileId != profileId) return;
    if (_scrollingToHighlight) {
      _glowPending = true;
      return;
    }
    _highlight.forward(from: 0);
  }

  /// 收卡光球的目標格（global rect）：這張卡已建出來、而且中心在畫面內才回，
  /// 否則回 null，光球在原地收束（不飛到別張卡上誤導）。
  Rect? _archiveTargetRect(String profileId) {
    if (_highlightProfileId != profileId) return null;
    final card = _highlightCardKey.currentContext?.findRenderObject();
    final page = context.findRenderObject();
    if (card is! RenderBox || page is! RenderBox) return null;
    if (!card.attached || !card.hasSize || !page.hasSize) return null;
    final rect = card.localToGlobal(Offset.zero) & card.size;
    final pageRect = page.localToGlobal(Offset.zero) & page.size;
    return pageRect.contains(rect.center) ? rect : null;
  }

  /// 兩段捲動定位：builder 惰性 grid 裡遠處的卡尚未 build（拿不到 context），
  /// 先用版面常數估算 offset 捲近，讓卡片 build 出來後再 ensureVisible 精準對齊。
  /// 捲動在儀式背景下進行；光球落位時若捲動已到位就直接亮，否則到位後補亮。
  Future<void> _scrollToHighlight(String profileId) async {
    try {
      if (!mounted || _highlightProfileId != profileId) return;
      if (_highlightCardKey.currentContext == null &&
          _scrollController.hasClients) {
        final estimated = _estimatedCardOffset(profileId);
        if (estimated != null) {
          await _scrollController.animateTo(
            estimated.clamp(0.0, _scrollController.position.maxScrollExtent),
            duration: AppMotion.scroll,
            curve: AppMotion.easeOut,
          );
        }
      }
      if (!mounted || _highlightProfileId != profileId) return;
      final cardContext = _highlightCardKey.currentContext;
      if (cardContext != null && cardContext.mounted) {
        await Scrollable.ensureVisible(
          cardContext,
          alignment: 0.35,
          duration: AppMotion.scroll,
          curve: AppMotion.easeOut,
        );
      }
    } finally {
      if (mounted && _highlightProfileId == profileId) {
        _scrollingToHighlight = false;
        if (_glowPending) {
          _glowPending = false;
          _highlight.forward(from: 0);
        }
      }
    }
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

  /// 額度列 v2（2026-08-09）：值來自進場唯讀 status 補水
  /// （[PracticeChatController.refreshDrawQuotaStatus]）與本 session draw
  /// 回應，何者較新用何者（epoch 防倒流）。仍只顯示已知真值：補水失敗／
  /// 過了 nextResetAt（窗已翻轉、數字失真）一律不顯示，寧缺勿誤。
  ({int remaining, int allowance})? _currentFreeQuota(PracticeChatState state) {
    final allowance = state.drawFreeAllowance;
    final remaining = state.drawFreeRemaining;
    if (allowance == null || remaining == null || allowance <= 0) return null;
    // resetAt 缺失或 parse 失敗＝無法判斷窗是否翻轉 → fail-quiet 不顯示。
    final resetAt = DateTime.tryParse(state.drawNextResetAt ?? '');
    if (resetAt == null) return null;
    // 語意對齊 server：now >= nextResetAt 即失效（雙審 finding）。
    // 已知取捨：停留本頁跨過重置點時，要到下次 rebuild 才會消失——不掛
    // Timer（pending timer 會炸 widget 測試），重置點在台北中午、值極低。
    if (!DateTime.now().isBefore(resetAt)) return null;
    return (remaining: remaining.clamp(0, allowance), allowance: allowance);
  }

  /// 翻牌鈕 gating（練習室舊 _requestNewPartner 的語義搬家，原件已刪，兩態分流）。
  /// 鐵律：本頁絕不 read-then-navigate autoDispose controller；build 有 watch
  /// 掛著 listener，這裡的 read 只是取當下值。
  void _onDrawPressed() {
    final state = ref.read(practiceChatControllerProvider);
    if (state.isDrawing ||
        state.isPersistingTurn ||
        _waitingForFirstDrawGrant) {
      return;
    }
    // 首抽還在發：先等它回來再翻。搶在發放生效前送出，server 還沒有那一次首抽，會回
    // 402 把人鎖在付費頁（Codex 主審第 1 輪 P2）。
    final pendingGrant = _firstDrawGrant;
    if (pendingGrant != null) {
      unawaited(_drawAfterFirstDrawGrant(pendingGrant));
      return;
    }

    final notifier = ref.read(practiceChatControllerProvider.notifier);
    final unlockedCount = ref.read(unlockedPracticeGirlCountProvider);
    final collectionComplete = unlockedCount >= practiceGirlProfiles.length;

    if (!state.isRevealed) {
      // locked（今日首抽）：client 不預判額度直接翻，額度由 server 裁決
      // （Free 每日免費抽已於 2026-08-02 移除，只剩一次性首抽，進練習室就發，
      // 見 _maybeGrantFirstDraw；Free 無額度時 server 回 402 走 drawUpgradeRequired 分支）。
      if (state.drawUpgradeRequired) {
        context.push('/paywall', extra: PaywallEntry.practiceDraw);
        return;
      }
      if (state.drawQuotaExceeded) {
        _showDrawSnackBar(
          state.errorMessage ??
              practiceDrawUsedUpMessage(ref.read(subscriptionProvider).tier),
        );
        return;
      }
      if (collectionComplete) {
        _confirmDraw(
          state,
          collectionComplete: true,
          unlockedCount: unlockedCount,
        );
        return;
      }
      notifier.drawNewPracticeGirl();
      return;
    }

    // revealed（換一位）：Free／已標升級 → 付費牆。
    final subscription = ref.read(subscriptionProvider);
    if (subscription.isFreeUser || state.drawUpgradeRequired) {
      _trackDrawQuotaBlock(QuotaBlockSource.precheck);
      context.push('/paywall', extra: PaywallEntry.practiceDraw);
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
      _trackDrawQuotaBlock(QuotaBlockSource.precheck);
      context.push('/paywall', extra: PaywallEntry.practiceDraw);
      return;
    }

    // 翻牌窗是台北中午 12 點換（不是「明天」）；Essential 不叫他升級。
    final drawUsedUp = practiceDrawUsedUpMessage(subscription.tier);
    if (state.drawQuotaExceeded) {
      notifier.lockDrawQuotaExceeded(message: drawUsedUp);
      _showDrawSnackBar(
        ref.read(practiceChatControllerProvider).errorMessage ?? drawUsedUp,
      );
      return;
    }

    if (_hasInsufficientPaidDrawQuota(subscription, state)) {
      _trackDrawQuotaBlock(QuotaBlockSource.precheck);
      notifier.lockDrawQuotaExceeded(message: drawUsedUp);
      _showDrawSnackBar(
        ref.read(practiceChatControllerProvider).errorMessage ?? drawUsedUp,
      );
      return;
    }

    if (_needsPaidDrawConfirmation(state) || collectionComplete) {
      _confirmDraw(
        state,
        collectionComplete: collectionComplete,
        unlockedCount: unlockedCount,
      );
      return;
    }

    notifier.drawNewPracticeGirl();
  }

  /// 額度不足事件（onboarding 轉換第 6 步）：翻牌被額度擋下、告訴使用者的那一刻。
  /// 只記錄，不影響額度判斷與付費頁；翻牌這邊分不出每日或每月，scope 一律 unknown。
  void _trackDrawQuotaBlock(QuotaBlockSource source) => unawaited(
        ref.read(funnelTrackerProvider).trackQuotaBlockShown(
              feature: QuotaBlockFeature.practice,
              scope: QuotaBlockScope.unknown,
              source: source,
            ),
      );

  /// 首抽還在發的時候按了翻牌：翻牌鈕轉圈等它回來（最多 [kFirstDrawGrantWait]），
  /// 再照常走一次翻牌判斷。發放失敗或逾時也照常送出、由 server 裁決，402 → 付費頁的
  /// 後備路徑不變；逾時之後首抽才到，補水會解除 402 的鎖。
  Future<void> _drawAfterFirstDrawGrant(Future<void> grant) async {
    setState(() => _waitingForFirstDrawGrant = true);
    await grant.timeout(kFirstDrawGrantWait, onTimeout: () {});
    if (!mounted) return;
    setState(() => _waitingForFirstDrawGrant = false);
    _firstDrawGrant = null; // 逾時也只等這一次
    _onDrawPressed();
  }

  /// SR 限定翻牌券抽：券固定 SR、不扣額度，沒有「值不值」的猶豫 → 不彈確認框，
  /// 儀式本身就是慶祝。完成後刷新券狀態（成功→金券收起；已用 409→同樣收起）。
  Future<void> _onSrTicketPressed() async {
    final state = ref.read(practiceChatControllerProvider);
    if (state.isDrawing || state.isPersistingTurn) return;
    final notifier = ref.read(practiceChatControllerProvider.notifier);
    await notifier.drawNewPracticeGirl(srTicket: true);
    if (!mounted) return;
    ref.invalidate(srTicketStatusProvider);
  }

  /// 滿池後再抽可能重複、免費次數用完則會扣額度；兩者同時發生時合併成同一個
  /// AlertDialog，避免使用者連續確認兩次。
  Future<void> _confirmDraw(
    PracticeChatState state, {
    required bool collectionComplete,
    required int unlockedCount,
  }) async {
    final paidConfirmation = _needsPaidDrawConfirmation(state);
    final messageParts = <String>[
      if (collectionComplete)
        '已收藏 $unlockedCount/${practiceGirlProfiles.length}，接下來可能抽到重複角色。',
      if (paidConfirmation) _paidDrawSpendMessage(state),
    ];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.brandSurface,
        title: Text(
          collectionComplete ? '角色已集滿' : '要扣額度翻牌嗎？',
          style: AppTypography.titleMedium.copyWith(
            color: AppColors.onBackgroundPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          messageParts.join('\n\n'),
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.onBackgroundSecondary,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('collection-draw-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.onBackgroundSecondary,
            ),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('collection-draw-confirm'),
            onPressed: AppHaptics.onPress(() => Navigator.of(dialogContext).pop(true)),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.ctaStart,
              foregroundColor: AppColors.onCta,
            ),
            child: Text(collectionComplete ? '仍要翻牌' : '確認翻牌'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final latest = ref.read(practiceChatControllerProvider);
    if (latest.isDrawing || latest.isPersistingTurn) return;
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
    final unlocked = ref.watch(practiceUnlockedProfileIdsProvider);
    final unlockedCount = ref.watch(unlockedPracticeGirlCountProvider);
    // 翻牌鈕兩態顯示必須 watch：同時讓 autoDispose controller 在本頁存活。
    final chatState = ref.watch(practiceChatControllerProvider);
    final isFreeUser =
        ref.watch(subscriptionProvider.select((s) => s.isFreeUser));
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _syncDrawPulse(
      shouldPulse:
          !chatState.isRevealed && !chatState.isPersistingTurn && !reduceMotion,
    );

    // 402/429 事後錯誤呈現：只攔「翻牌在途 → 收場」的轉場（同步 gating 的
    // snackbar 由 _onDrawPressed 自己出，不會雙發）。
    ref.listen(practiceChatControllerProvider, (prev, next) {
      // 抽牌開始：拍下抽之前的已解鎖集合與數字（一般抽、確認後抽、SR 券都走這裡）。
      // 解鎖的 +1 要等抽中後存完草稿才到，這一刻一定還是抽之前的樣子。圖鑑還沒載到
      // （網路慢、讀取失敗）就不拍：空集合會讓每張卡都被當成新角色，寧可不掛 NEW。
      if (prev != null && !prev.isDrawing && next.isDrawing) {
        final loaded = ref.read(practiceCollectionProvider).valueOrNull;
        _unlockedAtDrawStart = loaded?.toSet();
        _heldUnlockedCount =
            loaded == null ? null : ref.read(unlockedPracticeGirlCountProvider);
        _bumpOnUnlockProfileId = null; // 上一抽還沒等到的跳動不留到這一抽
        return;
      }
      if (prev == null || !prev.isDrawing || next.isDrawing) return;
      // 抽牌沒成功（錯誤、402／429、換一位失敗）：儀式只淡出不收卡，數字直接放回。
      final drawSucceeded =
          next.isRevealed && next.errorMessage == null && next.girl != null;
      if (!drawSucceeded) {
        _unlockedAtDrawStart = null;
        _heldUnlockedCount = null;
      }
      if (next.drawUpgradeRequired) {
        // 402＝Free 額度用完（產品拍板：絕不宣傳加抽）→ 直接進付費牆。
        // 402 常代表訂閱快照 stale（付費過期降 free 未同步）→ 順帶重同步一次
        // （沿用 paywall/settings 的 refresh seam；paywall 本身 initState 也會
        // refresh，重複呼叫 idempotent）。
        if (!mounted) return;
        _trackDrawQuotaBlock(QuotaBlockSource.server);
        AppHaptics.failure();
        unawaited(ref.read(subscriptionScreenRefreshProvider)());
        context.push('/paywall', extra: PaywallEntry.practiceDraw);
      } else if (next.drawQuotaExceeded || next.errorMessage != null) {
        if (next.drawQuotaExceeded) {
          _trackDrawQuotaBlock(QuotaBlockSource.server);
        }
        AppHaptics.failure();
        _showDrawSnackBar(next.errorMessage ?? '翻牌失敗了，再試一次。');
      }
    });

    // 這次抽到的新角色落位時解鎖還沒到：解鎖到的那一刻才 +1 並跳（V3.1 規格 §5.14）。
    ref.listen(practiceUnlockedProfileIdsProvider, (prev, next) {
      final pending = _bumpOnUnlockProfileId;
      if (pending == null || !next.contains(pending)) return;
      _bumpOnUnlockProfileId = null;
      _bumpCount(pending);
    });

    // 剛抽到那張卡的捲動與發光改由翻牌儀式通知（onRevealTarget／onArchived），
    // 不再監聽集合變大：重新整理圖鑑不會亂捲亂亮，集滿後抽到重複角色也標得到。

    final total = practiceGirlProfiles.length;
    final visible = _visibleProfiles();

    // 翻牌揭曉儀式疊在整頁（含 AppBar）最上層：揭曉期間標題列與返回鍵都被蓋住，
    // idle 時透明＋IgnorePointer，不影響底下互動。全 app 唯一掛載點。
    return Stack(
      children: [
        _buildScaffold(
          chatState: chatState,
          unlocked: unlocked,
          unlockedCount: unlockedCount,
          total: total,
          visible: visible,
          isFreeUser: isFreeUser,
        ),
        Positioned.fill(
          child: PracticeDrawCeremony(
            onRevealTarget: _onRevealTarget,
            archiveTargetRect: _archiveTargetRect,
            onArchived: _onCeremonyArchived,
            isNewProfile: _isNewProfile,
          ),
        ),
      ],
    );
  }

  Widget _buildScaffold({
    required PracticeChatState chatState,
    required Set<String> unlocked,
    required int unlockedCount,
    required int total,
    required List<PracticeGirlProfile> visible,
    required bool isFreeUser,
  }) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        // debrief「去圖鑑換人」用 context.go 收斂 stack 進來時 canPop 為
        // false，預設 AppBar 不會生返回鍵；顯式補一顆，落回首頁而不是卡死。
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back,
            color: AppColors.onBackgroundPrimary,
          ),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
        title: Text(
          '角色圖鑑',
          style: AppTypography.titleLarge.copyWith(
            color: AppColors.onBackgroundPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.onBackgroundPrimary),
      ),
      body: Stack(
        children: [
          BrandPageBackground(
            child: SafeArea(
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  SliverToBoxAdapter(
                    child: _CollectionHeader(
                      unlockedCount: _heldUnlockedCount ?? unlockedCount,
                      countBump: _countBump,
                      countBumpColor: _countBumpColor,
                      total: total,
                      drawPulse: _drawPulse,
                      // 等首抽發完的那一下也轉圈、不能再按。
                      drawIsDrawing:
                          chatState.isDrawing || _waitingForFirstDrawGrant,
                      drawEnabled: !chatState.isDrawing &&
                          !chatState.isPersistingTurn &&
                          !_waitingForFirstDrawGrant,
                      onDrawPressed: _onDrawPressed,
                      freeQuota: _currentFreeQuota(chatState),
                      isFreeUser: isFreeUser,
                    ),
                  ),
                  // 模擬社群動態入口（Threads 版面）：唯讀 feed，只顯示已抽到
                  // 角色的貼文。放在標頭下方＝「認識了誰」之後自然接「她們最近
                  // 在做什麼」。
                  const SliverToBoxAdapter(child: _MomentsEntry()),
                  // SR 限定翻牌券（訂閱一次性權益，2026-08-08 拍板）三態：
                  // premium＋未用＝金券（點了直接券抽，儀式即慶祝）；free＝鎖定
                  // 灰券導 paywall；已用/載入中/讀取失敗＝不顯示（fail-quiet）。
                  SliverToBoxAdapter(
                    child: _SrTicketSection(
                      onDrawTicket: _onSrTicketPressed,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                      // 夥伴稿：稀有度 filter 是一條連體 segmented bar。
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: AppColors.brandInk.withValues(alpha: 0.58),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.10),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _RarityFilterChip(
                                chipKey:
                                    const ValueKey('collection-filter-all'),
                                label: '全部',
                                selected: _filter == null,
                                onTap: () {
                                  AppHaptics.tap();
                                  setState(() => _filter = null);
                                },
                              ),
                            ),
                            for (final rarity in PracticeGirlRarity.values)
                              Expanded(
                                child: _RarityFilterChip(
                                  chipKey: ValueKey(
                                      'collection-filter-${rarity.label.toLowerCase()}'),
                                  label: rarity.label,
                                  selected: _filter == rarity,
                                  onTap: () {
                                    AppHaptics.tap();
                                    setState(() => _filter = rarity);
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // 圖鑑清單來自 server：載入中／連不上時格子會全是鎖卡，
                  // 不說一聲就像收藏被清空了。這條狀態列負責講實話。
                  SliverToBoxAdapter(
                    child: _CollectionLoadState(
                      collection: ref.watch(practiceCollectionProvider),
                      onRetry: () => ref
                          .read(practiceCollectionProvider.notifier)
                          .refresh(),
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
          if (_guideVisible)
            Positioned.fill(
              child: _OnboardingGuideOverlay(
                onDismiss: () => setState(() => _guideVisible = false),
              ),
            ),
        ],
      ),
    );
  }
}

/// onboarding 落地引導層：淡 scrim＋右下角 Sydney＋白泡泡，點任何地方收掉。
///
/// 進場淡入＋微上移用 [TweenAnimationBuilder]（單次收斂，pumpAndSettle 可推完）；
/// 絕不用 Timer 自動消失——fake async 下計時器不收斂是踩過的坑。
class _OnboardingGuideOverlay extends StatelessWidget {
  const _OnboardingGuideOverlay({required this.onDismiss});

  final VoidCallback onDismiss;

  static const String guideMessage = '哈囉！這裡是角色圖鑑～先按右上角的『翻牌』，抽出你的第一位練習夥伴吧！';

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return GestureDetector(
      key: const ValueKey('collection-onboarding-guide'),
      behavior: HitTestBehavior.opaque,
      onTap: onDismiss,
      child: Container(
        color: Colors.black.withValues(alpha: 0.35),
        alignment: Alignment.bottomRight,
        child: SafeArea(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: reduceMotion
                ? Duration.zero
                : AppMotion.enter,
            curve: AppMotion.easeOut,
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, (1 - t) * 16),
                child: child,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * 0.72,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        guideMessage,
                        style: AppTypography.bodyMedium.copyWith(
                          color: Colors.black87,
                          fontWeight: FontWeight.w600,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Semantics(
                    image: true,
                    label: 'VibeSync Coach Sydney，欣欣',
                    child: Image.asset(
                      'assets/images/coach/sydney_greeting.png',
                      height: 160,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                      excludeFromSemantics: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 揭曉後新卡的單次微光高亮：光球落進來那一刻邊框亮起→淡出，由單一 forward-only
/// controller 驅動（走完由 screen 清掉高亮 id，本 widget 隨之卸載，絕不常駐）。強度映射
/// 見 [collectionHighlightIntensityAt]；顏色和收卡光球同一色（稀有度主題的 orb）。
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
        final orb =
            PracticeRevealTheme.of(practiceGirlRarityFor(profileId)).orb;
        return Container(
          key: ValueKey('collection-highlight-$profileId'),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              width: 2,
              color: orb.withValues(alpha: 0.9 * intensity),
            ),
          ),
          decoration: intensity <= 0.001
              ? null
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: orb.withValues(alpha: 0.5 * intensity),
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
    required this.countBump,
    required this.countBumpColor,
    required this.total,
    required this.drawPulse,
    required this.drawIsDrawing,
    required this.drawEnabled,
    required this.onDrawPressed,
    required this.freeQuota,
    required this.isFreeUser,
  });

  final int unlockedCount;

  /// 收卡落位時「已收集」數字跳一下（0→1 單次）；顏色閃一下 [countBumpColor]。
  final Animation<double> countBump;
  final Color countBumpColor;
  final int total;
  final Animation<double> drawPulse;
  final bool drawIsDrawing;
  final bool drawEnabled;
  final VoidCallback onDrawPressed;

  /// 本窗免費翻牌（remaining/allowance）；null＝本 session 尚無可信資料，不顯示。
  final ({int remaining, int allowance})? freeQuota;

  /// 免費帳號沒有每日免費翻牌，額度列裡只會是那一次首抽，字要跟著換。
  final bool isFreeUser;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : (unlockedCount / total).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'VIBESYNC COLLECTION',
            style: AppTypography.caption.copyWith(
              color: AppColors.onBackgroundSecondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.brandSurface.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Text(
                              '已收集 ',
                              style: AppTypography.titleLarge.copyWith(
                                color: AppColors.onBackgroundPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            AnimatedBuilder(
                              animation: countBump,
                              builder: (context, child) {
                                final bump =
                                    math.sin(math.pi * countBump.value);
                                return Transform.scale(
                                  scale: 1 + 0.25 * bump,
                                  child: Text(
                                    '$unlockedCount',
                                    key: const ValueKey(
                                        'collection-completion-count'),
                                    style: AppTypography.titleLarge.copyWith(
                                      color: Color.lerp(
                                        AppColors.ctaStart,
                                        countBumpColor,
                                        bump,
                                      ),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                );
                              },
                            ),
                            Text(
                              ' / $total',
                              style: AppTypography.titleLarge.copyWith(
                                color: AppColors.onBackgroundSecondary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _CollectionDrawButton(
                        pulse: drawPulse,
                        isDrawing: drawIsDrawing,
                        enabled: drawEnabled,
                        onPressed: onDrawPressed,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '收藏完成度',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.onBackgroundSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
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
                            color: AppColors.ctaStart,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (freeQuota != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.style_outlined,
                          size: 14,
                          color: AppColors.onBackgroundSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          // 免費帳號的額度只有那一次首抽（Onboarding 第 1 步）：不寫
                          // 「今日」（ADR #35 §5：免費版不寫每日）。付費照舊。
                          isFreeUser
                              ? '免費首抽 剩 ${freeQuota!.remaining} 次'
                              : '今日免費翻牌 剩 ${freeQuota!.remaining} / ${freeQuota!.allowance}',
                          key: const ValueKey('collection-free-quota-line'),
                          style: AppTypography.caption.copyWith(
                            color: AppColors.onBackgroundSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 標題右側的翻牌鈕：實色橘 CTA。今日未翻時仍可保留極淡 pulse，但不常駐彩色 glow。
/// [pulse]（repeat 呼吸）驅動 boxShadow alpha；revealed 時 pulse 停在 0＝定光。
class _CollectionDrawButton extends StatelessWidget {
  const _CollectionDrawButton({
    required this.pulse,
    required this.isDrawing,
    required this.enabled,
    required this.onPressed,
  });

  final Animation<double> pulse;
  final bool isDrawing;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, child) {
        return GestureDetector(
          key: const ValueKey('collection-draw-button'),
          behavior: HitTestBehavior.opaque,
          // 翻牌是全 app 最有儀式感的按鈕：按下就給最重一級（dogfood 點名要重）。
          onTap: enabled
              ? () {
                  AppHaptics.medium();
                  onPressed();
                }
              : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.ctaStart,
                borderRadius: BorderRadius.circular(18),
              ),
              child: child,
            ),
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
          const SizedBox(width: 2),
          const Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: AppColors.brandInk,
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
    return PressableScale(
      child: GestureDetector(
        key: chipKey,
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.enter,
          curve: AppMotion.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.ctaStart.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? AppColors.ctaStart.withValues(alpha: 0.45)
                  : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(
              color: selected
                  ? AppColors.brandFlame
                  : AppColors.onBackgroundSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _CollectionCard extends ConsumerWidget {
  const _CollectionCard({
    required this.profile,
    required this.unlocked,
  });

  final PracticeGirlProfile profile;
  final bool unlocked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rarity = profile.rarity;
    // 批 3：free 每日免費抽已移除，「每日」字樣只對付費 tier 為真。
    final isPremium = ref.watch(subscriptionProvider).isPremium;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
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
                  // 夥伴稿：鎖卡是剪影＋圓形鎖頭，不再用問號。
                  Center(
                    child: Container(
                      key: ValueKey('collection-mystery-${profile.profileId}'),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                      child: Icon(
                        Icons.lock_rounded,
                        size: 22,
                        color: Colors.white.withValues(alpha: 0.62),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (unlocked) ...[
          Text(
            profile.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.titleSmall.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            profile.professionLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption.copyWith(
              color: AppColors.onBackgroundSecondary,
            ),
          ),
          const SizedBox(height: 6),
          PracticeRarityStars(rarity: rarity),
        ] else
          SizedBox(
            width: double.infinity,
            child: Text(
              // 「每日」字樣只對付費 tier 為真（批 3）。
              isPremium ? '尚未解鎖 · 每日翻牌' : '尚未解鎖',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTypography.caption.copyWith(color: Colors.white54),
            ),
          ),
      ],
    );

    // 夥伴稿：卡片本身不帶稀有度彩邊，稀有度只由左上角 badge 與星等表示。
    final body = Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.brandSurface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: content,
    );

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
          ..showSnackBar(SnackBar(
            content: Text(isPremium ? '每日翻牌有機會遇到她' : '翻牌有機會遇到她'),
          ));
      },
      child: body,
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
          fontSize: 30,
        ),
      ),
    );
  }
}

/// SR 限定翻牌券卡（訂閱一次性權益）三態呈現；同一張卡的鎖定/可用兩個狀態，
/// 訂閱前後視覺連續（Free 的鎖定灰券就是升級鉤子）。已用/載入中/讀取失敗
/// 一律收起：券是 bonus 不是主流程，絕不因它擋圖鑑。
class _SrTicketSection extends ConsumerWidget {
  const _SrTicketSection({required this.onDrawTicket});

  final Future<void> Function() onDrawTicket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPremium =
        ref.watch(subscriptionProvider.select((s) => s.isPremium));
    if (!isPremium) {
      return _SrTicketCard(
        cardKey: const ValueKey('collection-sr-ticket-locked'),
        locked: true,
        onTap: () => context.push('/paywall', extra: PaywallEntry.practiceDraw),
      );
    }
    final status = ref.watch(srTicketStatusProvider);
    final available = status.maybeWhen(
      data: (s) => s.granted && !s.consumed,
      orElse: () => false,
    );
    if (!available) return const SizedBox.shrink();
    return _SrTicketCard(
      cardKey: const ValueKey('collection-sr-ticket'),
      locked: false,
      onTap: onDrawTicket,
    );
  }
}

class _SrTicketCard extends StatelessWidget {
  const _SrTicketCard({
    required this.cardKey,
    required this.locked,
    required this.onTap,
  });

  final Key cardKey;
  final bool locked;
  final void Function() onTap;

  static const _gold = AppColors.avatarHerEnd;

  @override
  Widget build(BuildContext context) {
    final accent = locked ? AppColors.onBackgroundSecondary : _gold;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: GestureDetector(
        key: cardKey,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: locked ? 0.06 : 0.10),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withValues(alpha: 0.55)),
            boxShadow: locked
                ? const []
                : [
                    BoxShadow(
                      color: _gold.withValues(alpha: 0.18),
                      blurRadius: 14,
                    ),
                  ],
          ),
          child: Row(
            children: [
              Icon(
                locked ? Icons.lock_outline : Icons.auto_awesome,
                size: 20,
                color: accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SR 限定翻牌 ×1',
                      style: AppTypography.labelMedium.copyWith(
                        color: locked
                            ? AppColors.onBackgroundPrimary
                                .withValues(alpha: 0.8)
                            : _gold,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      locked ? '訂閱就送，翻開必得 SR、直接解鎖 Game' : '保底 SR，翻開直接解鎖 Game',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.onBackgroundSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: locked ? 0.14 : 0.22),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  locked ? '訂閱解鎖' : '翻開',
                  style: AppTypography.caption.copyWith(
                    color: locked ? AppColors.onBackgroundPrimary : _gold,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 圖鑑載入狀態列。已有集合（含樂觀 +1 後的重抓）時完全不出現——只在
/// 「還沒拿到清單」時講話，避免把整片鎖卡誤讀成收藏被清空。
class _CollectionLoadState extends StatelessWidget {
  const _CollectionLoadState({required this.collection, required this.onRetry});

  static const loadingKey = ValueKey('collection-load-state-loading');
  static const errorKey = ValueKey('collection-load-state-error');

  final AsyncValue<Set<String>> collection;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (collection.hasValue) return const SizedBox.shrink();
    final failed = collection.hasError;
    return Padding(
      key: failed ? errorKey : loadingKey,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              failed ? '連不上，圖鑑先顯示不出來。' : '正在讀取你的收藏…',
              style: AppTypography.caption.copyWith(
                color: AppColors.onBackgroundSecondary,
              ),
            ),
          ),
          if (failed)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.ctaStart,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('重試'),
            ),
        ],
      ),
    );
  }
}


/// 動態 feed 入口。刻意是一條緊湊的列，不是又一張大卡——圖鑑本身已經很滿，
/// 入口只要看得到、按得到就夠。
class _MomentsEntry extends StatelessWidget {
  const _MomentsEntry();

  static const entryKey = ValueKey('collection-moments-entry');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: PressableScale(
        child: GestureDetector(
          key: entryKey,
          behavior: HitTestBehavior.opaque,
          onTap: AppHaptics.onPress(() => context.push('/practice-moments')),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.brandSurface.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Padding(
              // 右內距 18：品牌標記的墨跡貼齊自身邊框，不像 Icon 字面自帶留白，
              // 補回留白才能維持原本 chevron 的視覺右間距。
              padding: const EdgeInsets.fromLTRB(14, 12, 18, 12),
              child: Row(
                children: [
                  Icon(
                    Icons.forum_outlined,
                    size: 20,
                    color: AppColors.ctaStart.withValues(alpha: 0.9),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '她們的動態',
                          style: AppTypography.titleMedium.copyWith(
                            color: AppColors.onBackgroundPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '看看已經抽到的角色最近在做什麼',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.onBackgroundSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 標記墨跡左右都貼齊自身邊框，Expanded 會讓副標直接抵住它；
                  // 補一段與左側圖示同寬的間距，放大字級時才不會黏在一起。
                  const SizedBox(width: 12),
                  SvgPicture.asset(
                    'assets/images/vibesync_logo.svg',
                    width: 32,
                    height: 32,
                    colorFilter: const ColorFilter.mode(
                      AppColors.onBackgroundSecondary,
                      BlendMode.srcIn,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
