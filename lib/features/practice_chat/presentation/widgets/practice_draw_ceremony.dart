import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter, PathMetric, lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../data/providers/practice_chat_providers.dart';
import '../../domain/entities/practice_girl_profile.dart';
import '../../domain/entities/practice_girl_rarity.dart';
import 'practice_draw_sfx.dart';
import 'practice_girl_photo.dart';
import 'practice_rarity_style.dart';
import 'practice_reveal_timing.dart';

const String _kReferenceCardBackBaseAsset =
    'assets/images/practice/practice_draw_card_back_base.png';
const String _kReferenceCardBackNeonAsset =
    'assets/images/practice/practice_draw_card_back_neon.png';

/// 蓄力三下輕震（規格 D8：先全開，真機嫌吵就關這一個開關）。
const bool _kChargeTicksEnabled = true;

/// 揭曉卡片尺寸（G2 放大／復刻 音檔.mp4 的近滿版高卡）：寬 ≈ 0.84×螢幕寬、直式 2:3
/// （高 = 寬 × 1.5，比舊 4/3 更高更主導，貼合參考片塔羅卡比例）。大螢幕（平板）寬封頂
/// [kPracticeCardMaxWidth]；矮螢幕再被可用高度夾住，確保 stage＋caption 不溢出。
/// widget 與 widget test 共用單一真相。
@visibleForTesting
const double kPracticeCardWidthFactor = 0.90;
@visibleForTesting
const double kPracticeCardMaxWidth = 390;
@visibleForTesting
const double kPracticeCardHeightRatio = 1.5; // 直式 2:3 → 高 = 寬 × 1.5（塔羅卡比例）
@visibleForTesting
const double kPracticeCardMaxHeightFactor = 0.64; // 卡高最多佔螢幕高，留白給 caption／光暈

@visibleForTesting
Size practiceCeremonyCardSize(Size screen) {
  var w = (screen.width * kPracticeCardWidthFactor)
      .clamp(0.0, kPracticeCardMaxWidth);
  var h = w * kPracticeCardHeightRatio;
  final maxH = screen.height * kPracticeCardMaxHeightFactor;
  if (h > maxH) {
    h = maxH;
    w = h / kPracticeCardHeightRatio;
  }
  return Size(w, h);
}

/// 每日翻牌「揭曉儀式」全螢幕 overlay（V3 第一刀：單次翻牌＋停住等點擊＋收卡飛行）。
///
/// 規格：`docs/plans/2026-10-15-card-draw-v3-luxury-reveal-spec.md`。這一刀只換結構與
/// 節奏；卡背、正面卡、資訊欄仍是 V2 的外觀，稀有度染色、新卡背、全息掃光與新配樂在
/// 後續刀次。
///
/// 流程：hidden → drawing（卡背入場＋等待呼吸）→ revealing（蓄力 → 單次翻牌 → 資訊浮出，
/// 共 2.7 s）→ holding（畫面靜止，等使用者點）→ archiving（縮成光球飛進圖鑑那一格，
/// 0.55 s）→ hidden。各節點見 [PracticeRevealTiming]。
///
/// 設計鐵則（沿用 V2）：
/// - 只靠單一 `drawStatus` 狀態機驅動，**不**新增任何計費／網路行為。
/// - 只有「真的進過 drawing 又成功 reveal 一位新對象」才慶祝；換一位失敗會回到
///   `revealed` 但帶 `errorMessage`，這種情況只做兜底淡出、不翻面慶祝。
/// - **零 `Timer`／零 `Future.delayed`**：時間軸一律由有限 `AnimationController` 推導。唯一
///   會 `repeat()` 的是 [_waiting]（抽牌等待 server 期間的持續微動），只在 drawing 且非
///   reduce-motion 啟動，其他出口一律 `stop()`。holding 期間沒有任何動畫，所以
///   `pumpAndSettle` 會停在 holding 收斂；要點「繼續」才收掉。
/// - reduce-motion（`MediaQuery.disableAnimations`）：沒有儀式畫面；抽中當下給觸覺，並立刻
///   通知圖鑑頁捲動與點亮那一格。
/// - haptic 走 [AppHaptics]（翻牌峰值重擊，SR 改成 celebrate 三連、第三下落在峰值）；音效走
///   [PracticeDrawSfx]（由 [practiceDrawSfxProvider] 注入）。等待期不跑循環音效。
///
/// 由角色圖鑑頁以 `Positioned.fill` 疊在整頁（含 AppBar）最上層；idle 時整片透明且
/// `IgnorePointer`，不攔截底下的點擊。
class PracticeDrawCeremony extends ConsumerStatefulWidget {
  const PracticeDrawCeremony({
    super.key,
    this.onRevealTarget,
    this.archiveTargetRect,
    this.onArchived,
  });

  /// 揭曉開始（reduce-motion 為抽中當下）：圖鑑頁收 filter、標記並捲到這張卡。
  /// 新卡與重複角色都會呼叫。
  final ValueChanged<PracticeGirlProfile>? onRevealTarget;

  /// 收卡起飛前查目標格的 global rect；回 null 或不在畫面內 → 光球原地收束。
  final Rect? Function(String profileId)? archiveTargetRect;

  /// 光球落位（收卡 450 ms；reduce-motion 為抽中當下）：圖鑑頁點亮那一格。
  final ValueChanged<String>? onArchived;

  @override
  ConsumerState<PracticeDrawCeremony> createState() =>
      _PracticeDrawCeremonyState();
}

enum _CeremonyPhase { hidden, drawing, revealing, holding, archiving }

/// 揭曉對拍點（`_reveal` 經過的毫秒）。配樂重音都在 bed 裡，這裡只補翻牌紙聲與觸覺。
enum _RevealBeat {
  chargeTick0(0),
  chargeTick1(PracticeRevealTiming.chargeTick1Ms),
  chargeTick2(PracticeRevealTiming.chargeTick2Ms),

  /// 只有 SR：celebrate 三下共 200 ms，第三下重擊落在翻牌峰值。
  srBuild(PracticeRevealTiming.srBuildMs),

  /// 卡片正好側立：翻牌紙聲；N／R 的重擊。
  flipPeak(PracticeRevealTiming.flipPeakMs);

  const _RevealBeat(this.ms);

  final double ms;
}

/// 卡片在等待呼吸中的姿態；揭曉起手時抓下來，前 150 ms 混到蓄力姿態，避免跳格。
@immutable
class _CardPose {
  const _CardPose({required this.dy, required this.scale, required this.glow});

  static const rest = _CardPose(dy: 0, scale: 1, glow: 0.6);

  final double dy;
  final double scale;
  final double glow;
}

class _PracticeDrawCeremonyState extends ConsumerState<PracticeDrawCeremony>
    with TickerProviderStateMixin {
  // 卡背入場（背景暗化＋卡背浮現）；失敗時 reverse 當作淡出。
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: PracticeRevealTiming.intro,
  );

  // 等待字樣：server 超過 900 ms 還沒回來才淡入。
  late final AnimationController _caption = AnimationController(
    vsync: this,
    duration: PracticeRevealTiming.caption,
  );

  // 抽牌「等待 server 回應」期間的持續蓄力微動（上下浮動＋金光呼吸＋星光閃爍）。
  // 這是**唯一**會 `repeat()` 的 controller，故嚴格 gate：只在真實 drawing 階段且
  // 非 reduce-motion 才啟動，reveal／error／hidden／dispose 一律明確 `stop()`，確保
  // `pumpAndSettle` 不會因無限重播而 hang。一個迴圈 = 一次 sin 週期（首尾相接無跳變）。
  late final AnimationController _waiting = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  // 揭曉：蓄力 → 單次翻牌 → 資訊浮出（forward-only，走完進 holding）。
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: PracticeRevealTiming.reveal,
  );

  // 收卡：縮成光球飛進圖鑑那一格（forward-only，走完收掉 overlay）。
  late final AnimationController _archive = AnimationController(
    vsync: this,
    duration: PracticeRevealTiming.archive,
  );

  // 翻牌音效（咻／揭曉配樂）。於 initState 以 `ref.read` 鎖定實例（Provider 無 async／
  // context 依賴），故 dispose 取用時純欄位讀取、不再碰 ref。
  late final PracticeDrawSfx _sfx;

  /// 五條 controller 的合併訊號：疊加層由 AnimatedBuilder 訂閱它重繪，State.build
  /// 只在階段轉換時重跑。
  late final Listenable _ceremonyMotion =
      Listenable.merge([_intro, _caption, _waiting, _reveal, _archive]);

  /// 卡片舞台：收卡時用來取卡片中心（光球起點）。
  final GlobalKey _stageKey = GlobalKey();

  _CeremonyPhase _phase = _CeremonyPhase.hidden;
  PracticeGirlProfile? _revealGirl;

  /// server 比卡背入場還快回來：等 `_intro` 走完才開始揭曉。
  bool _pendingReveal = false;

  /// 失敗兜底淡出中：`_intro` 倒轉到 0 就收掉 overlay。
  bool _fadingOut = false;

  /// 收卡的光球已落位（`onArchived` 只呼叫一次）。
  bool _landed = false;

  _CardPose _startPose = _CardPose.rest;
  double _captionAtRevealStart = 0;
  Offset _archiveOrigin = Offset.zero;
  Offset _archiveControl = Offset.zero;
  Rect? _archiveTarget;

  // 已觸發的對拍點：`_reveal` 每幀 tick 比對門檻，這個集合確保每一拍在一次揭曉裡
  // 只觸發一次。揭曉起播前與收掉 overlay 時清空；跳過時一次標滿（不補震、不補聲）。
  final Set<_RevealBeat> _firedBeats = {};

  double get _introMs => _intro.value * PracticeRevealTiming.introMs;
  double get _captionMs => _caption.value * PracticeRevealTiming.captionMs;
  double get _revealMs => _reveal.value * PracticeRevealTiming.revealMs;
  double get _archiveMs => _archive.value * PracticeRevealTiming.archiveMs;

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  @override
  void initState() {
    super.initState();
    _sfx = ref.read(practiceDrawSfxProvider);
    _reveal.addListener(_onRevealTick);
    _reveal.addStatusListener((status) {
      if (status == AnimationStatus.completed &&
          _phase == _CeremonyPhase.revealing) {
        setState(() => _phase = _CeremonyPhase.holding);
      }
    });
    _archive.addListener(_onArchiveTick);
    _archive.addStatusListener((status) {
      if (status == AnimationStatus.completed &&
          _phase == _CeremonyPhase.archiving) {
        _toHidden();
      }
    });
    _intro.addStatusListener((status) {
      if (status == AnimationStatus.completed && _pendingReveal) {
        _pendingReveal = false;
        _beginReveal();
      } else if (status == AnimationStatus.dismissed && _fadingOut) {
        _toHidden();
      }
    });
  }

  /// 監看 `drawStatus` 轉場驅動儀式。只在「曾進入 drawing」後才有反應，避免進房就
  /// 已是 revealed（草稿／續玩還原）誤觸發。
  void _onStateChange(PracticeChatState? prev, PracticeChatState next) {
    final wasDrawing = prev?.isDrawing ?? false;

    if (!wasDrawing && next.isDrawing) {
      _startDrawing();
      return;
    }

    if (!wasDrawing) return; // 以下都只處理「抽牌中 → 結果」的收斂。

    // 抽牌中的其他狀態更新（例如練習室還在跑的提示、拆解剛好回來）不是結果：不理，
    // 否則會被當成失敗淡出，真正的結果回來時已經沒有儀式可接。
    if (next.isDrawing) return;

    // 抽牌成功揭曉：revealed 且沒有錯誤訊息（換一位失敗會回 revealed 但帶錯誤）。
    final drawSucceeded =
        next.isRevealed && next.errorMessage == null && next.girl != null;
    if (drawSucceeded) {
      _onDrawSucceeded(next.girl!);
      return;
    }

    // 失敗兜底（error / locked / 換一位失敗回 revealed 帶錯誤）：淡出，不慶祝。
    if (_phase == _CeremonyPhase.drawing ||
        _phase == _CeremonyPhase.revealing) {
      _failOut();
    }
  }

  void _startDrawing() {
    // 進入抽牌：浮現神秘卡背，觸覺＋咻聲。
    AppHaptics.light();
    _sfx.playWhoosh();
    // 揭曉配樂先載好：server 回來時從頭 resume，bed 裡的重音才對得上畫面。
    _sfx.preloadReveal();
    _reveal
      ..stop()
      ..value = 0;
    _archive
      ..stop()
      ..value = 0;
    _firedBeats.clear();
    _pendingReveal = false;
    _fadingOut = false;
    _landed = false;
    setState(() {
      _phase = _CeremonyPhase.drawing;
      _revealGirl = null;
      _archiveTarget = null;
    });
    if (_reduceMotion) {
      _intro.value = 1; // 不做入場動畫，直接定住卡背。
      _caption.value = 1;
      _waiting.stop(); // reduce-motion：等待期間靜止，不啟動持續微動。
      _sfx.stopWaitingLoop(); // reduce-motion：不啟動等待 loop（防殘留）。
    } else {
      _intro.forward(from: 0);
      _caption.forward(from: 0);
      _waiting.repeat(); // 等待 server 期間持續蓄力微動。
      // F3：等待 server 期間不跑循環音效；只有咻聲檔自帶的一次性暖尾巴接住等待。
    }
  }

  void _onDrawSucceeded(PracticeGirlProfile girl) {
    _sfx.stopWaitingLoop();
    if (_reduceMotion) {
      // reduce-motion：沒有翻面也就沒有對拍點，觸覺留在抽中當下。稀有（SR）給漸強慶祝，
      // 一般給單發重震——稀有的手感必須不一樣。
      if (girl.rarity == PracticeGirlRarity.sr) {
        unawaited(AppHaptics.celebrate());
      } else {
        AppHaptics.medium();
      }
      widget.onRevealTarget?.call(girl);
      widget.onArchived?.call(girl.profileId);
      // 沒有儀式也就沒有配樂可以交棒：咻聲的暖尾巴跟著收掉，不留在圖鑑上。
      _sfx.stopWhoosh();
      _toHidden();
      return;
    }
    _revealGirl = girl;
    if (_intro.isCompleted) {
      _beginReveal();
      return;
    }
    _pendingReveal = true; // 保證卡背入場走完才開始蓄力。
    // 卡背入場沒有在往前走：抽牌中離開圖鑑又回來（這個儀式還是 hidden），或正在淡出。
    // 接著把入場走完再揭曉，不重播咻聲與觸覺（那是按下翻牌那一刻的事）。
    if (_phase == _CeremonyPhase.hidden || _fadingOut) {
      _fadingOut = false;
      _sfx.preloadReveal();
      setState(() => _phase = _CeremonyPhase.drawing);
      _intro.forward();
    }
  }

  void _beginReveal() {
    final girl = _revealGirl;
    if (!mounted || girl == null) return;
    _startPose = _waitingPose();
    _captionAtRevealStart = _captionOpacity(); // 還在 drawing：取等待字樣當下透明度。
    _waiting.stop(); // 揭曉接管：停掉等待微動，避免與翻面疊動。
    _caption.stop();
    // 正面在 1.35 s 才露出：先把照片解碼好，翻開那一刻不會空白。
    unawaited(
      precacheImage(
        AssetImage(girl.photoAssetPath),
        context,
        onError: (_, __) {},
      ),
    );
    // 揭曉起始播一條與 `_reveal` 對好拍的配樂 bed（已預載）；咻聲尾巴不停，交棒給 bed。
    _sfx.playRevealBed();
    widget.onRevealTarget?.call(girl);
    _firedBeats.clear();
    setState(() => _phase = _CeremonyPhase.revealing);
    _reveal.forward(from: 0);
  }

  /// 揭曉時間軸的對拍：跨過門檻就觸發一次（測試一次 pump 跳過門檻也用 `>=`）。只播
  /// 音效、給觸覺——不 setState（重繪由 [_ceremonyMotion] 的 AnimatedBuilder 負責）。
  void _onRevealTick() {
    if (_phase != _CeremonyPhase.revealing) return;
    final ms = _revealMs;
    for (final beat in _RevealBeat.values) {
      if (ms >= beat.ms && _firedBeats.add(beat)) _fireBeat(beat);
    }
  }

  void _fireBeat(_RevealBeat beat) {
    final isSr = _revealGirl?.rarity == PracticeGirlRarity.sr;
    switch (beat) {
      case _RevealBeat.chargeTick0:
      case _RevealBeat.chargeTick1:
      case _RevealBeat.chargeTick2:
        if (_kChargeTicksEnabled) AppHaptics.tick();
      case _RevealBeat.srBuild:
        if (isSr) unawaited(AppHaptics.celebrate());
      case _RevealBeat.flipPeak:
        _sfx.playFlipSnap();
        if (!isSr) AppHaptics.medium();
    }
  }

  /// 全螢幕點擊（含 Android 返回鍵）：翻牌落定前不理；落定後跳到資訊全部落位；停住時收卡。
  void _onOverlayTap() {
    switch (_phase) {
      case _CeremonyPhase.revealing:
        if (_revealMs < PracticeRevealTiming.skipFromMs) return;
        // 跳過：剩下的對拍點不補震、不補聲，直接快轉到落定。
        _firedBeats.addAll(_RevealBeat.values);
        _reveal.animateTo(
          1,
          duration: PracticeRevealTiming.skip,
          curve: Curves.easeOut,
        );
      case _CeremonyPhase.holding:
        _startArchive();
      case _CeremonyPhase.hidden:
      case _CeremonyPhase.drawing:
      case _CeremonyPhase.archiving:
        break;
    }
  }

  void _startArchive() {
    final box = context.findRenderObject();
    final size =
        box is RenderBox && box.hasSize ? box.size : MediaQuery.sizeOf(context);
    final origin = _stageCenter(box) ?? size.center(Offset.zero);
    final girl = _revealGirl;
    final target =
        girl == null ? null : _resolveArchiveTarget(box, girl.profileId);
    // 收卡：配樂與咻聲尾巴都淡出，不帶到圖鑑頁。
    _sfx.stopRevealBed();
    _sfx.stopWhoosh();
    _landed = false;
    setState(() {
      _phase = _CeremonyPhase.archiving;
      _archiveOrigin = origin;
      _archiveTarget = target;
      _archiveControl = target == null
          ? origin
          : practiceArchiveControlPoint(origin, target.center, size);
    });
    _archive.forward(from: 0);
  }

  /// 卡片中心（overlay 本地座標）＝光球起點。
  Offset? _stageCenter(RenderObject? box) {
    final stage = _stageKey.currentContext?.findRenderObject();
    if (box is! RenderBox || stage is! RenderBox) return null;
    if (!box.hasSize || !stage.hasSize) return null;
    return box.globalToLocal(
      stage.localToGlobal(stage.size.center(Offset.zero)),
    );
  }

  /// 圖鑑頁回報的目標格（global）轉成 overlay 本地座標；中心不在畫面內就當作沒有。
  Rect? _resolveArchiveTarget(RenderObject? box, String profileId) {
    final global = widget.archiveTargetRect?.call(profileId);
    if (global == null || box is! RenderBox || !box.hasSize) return null;
    final local = box.globalToLocal(global.topLeft) & global.size;
    return (Offset.zero & box.size).contains(local.center) ? local : null;
  }

  void _onArchiveTick() {
    if (_phase != _CeremonyPhase.archiving || _landed) return;
    if (_archiveMs < PracticeRevealTiming.landMs) return;
    _landed = true;
    AppHaptics.light();
    final id = _revealGirl?.profileId;
    if (id != null) widget.onArchived?.call(id);
  }

  void _failOut() {
    _waiting.stop(); // 失敗兜底：先停等待微動，兩條淡出路徑都不殘留 repeat。
    _caption.stop();
    _pendingReveal = false;
    _sfx.stopWaitingLoop(); // 失敗兜底（error／402／429）：同步停等待 loop，不播叮聲。
    _sfx.stopRevealBed(); // 失敗兜底：配樂 bed 一律收掉（防殘留）。
    _sfx.stopWhoosh(); // 失敗兜底：咻聲尾巴淡出，不帶到付費牆／錯誤提示上。
    _reveal
      ..stop()
      ..value = 0;
    if (_reduceMotion || _intro.value == 0) {
      _toHidden();
      return;
    }
    _fadingOut = true;
    setState(() {
      _phase = _CeremonyPhase.drawing;
      _revealGirl = null;
    });
    _intro.reverse();
  }

  void _toHidden() {
    if (!mounted) return;
    // 旗標先歸零：下面把 controller 歸零時發出的 dismissed／completed 都不會再進來。
    _pendingReveal = false;
    _fadingOut = false;
    _landed = false;
    setState(() {
      _phase = _CeremonyPhase.hidden;
      _revealGirl = null;
      _archiveTarget = null;
    });
    _waiting.stop();
    _caption.stop();
    _sfx.stopWaitingLoop(); // 收掉 overlay（hidden／收卡完成／淡出完成）一律停等待 loop。
    _sfx.stopRevealBed(); // 揭曉結束／收掉 overlay → 配樂 bed 不殘留。
    _firedBeats.clear();
    _reveal.value = 0;
    _archive.value = 0;
    _intro.value = 0;
    _caption.value = 0;
  }

  @override
  void dispose() {
    _sfx.stopWaitingLoop(); // 卸載儀式：確保等待 loop 不在背景殘留。
    _sfx.stopRevealBed(); // 卸載儀式：確保配樂 bed 不在背景殘留。
    _sfx.stopWhoosh(); // 卸載儀式：抽牌中離開畫面，咻聲尾巴淡出，不帶到下一頁。
    _intro.dispose();
    _caption.dispose();
    _waiting.dispose();
    _reveal.dispose();
    _archive.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 螢幕（祖先）每次 state 變動都會重建本子樹，這裡用 ref.listen 收 drawStatus 轉場。
    ref.listen<PracticeChatState>(
        practiceChatControllerProvider, _onStateChange);

    if (_phase == _CeremonyPhase.hidden) {
      return const IgnorePointer(
        ignoring: true,
        child: SizedBox.expand(),
      );
    }

    // 揭曉起返回鍵＝點擊（跳過／收卡），不讓使用者在儀式中途被帶離頁面。
    final blocksPop = _phase == _CeremonyPhase.revealing ||
        _phase == _CeremonyPhase.holding ||
        _phase == _CeremonyPhase.archiving;
    return PopScope(
      canPop: !blocksPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onOverlayTap();
      },
      // 掛在 Scaffold 之外：自備透明 Material，文字才不會出現除錯底線。
      child: Material(
        type: MaterialType.transparency,
        // 疊加層整棵包 RepaintBoundary 與底下頁面隔離；動畫幀由 AnimatedBuilder 訂閱
        // 五條 controller 驅動。
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _ceremonyMotion,
            builder: (context, _) => _buildOverlay(),
          ),
        ),
      ),
    );
  }

  // ── 疊加層 ──
  // 卡周圍留給星光／閃光的 padding；stage 寬再夾進螢幕寬，避免大卡溢出。
  static const double _stagePadding = 132;
  static const Alignment _stageAlignment = Alignment(0, -0.06);
  static const double _hintMaxOpacity = 0.72;

  Widget _buildOverlay() {
    final screen = MediaQuery.sizeOf(context);
    final cardSize = practiceCeremonyCardSize(screen);
    final stageW = math.min(cardSize.width + _stagePadding, screen.width);
    final stageH = cardSize.height + _stagePadding;
    final holding = _phase == _CeremonyPhase.holding;
    final girl = _revealGirl;
    final hint = _hintOpacity();

    return Stack(
      fit: StackFit.expand,
      children: [
        // 全螢幕點擊層：drawing 只吞點擊（背景看不清，不讓誤點穿透到圖鑑）；揭曉起處理
        // 跳過與收卡。其餘圖層一律 IgnorePointer，點擊都落到這一層。
        // VoiceOver：停住時整層是一個按鈕並主動唸出抽到誰；之前只說正在翻牌。
        Semantics(
          container: true,
          button: holding,
          liveRegion: holding,
          label: holding && girl != null
              ? '已抽到 ${girl.displayName}，${girl.rarity.label} 卡'
              : '正在翻牌',
          hint: holding ? '點兩下收進圖鑑' : null,
          child: GestureDetector(
            key: const ValueKey('practice-draw-ceremony-continue'),
            behavior: HitTestBehavior.opaque,
            onTap: _onOverlayTap,
            child: const SizedBox.expand(),
          ),
        ),
        // 暗化舞台背景：中心微透紫光暈、邊緣近黑，像一方聚光的翻牌檯。
        IgnorePointer(
          child: Opacity(
            opacity: _backdropOpacity(),
            child: const DecoratedBox(
              key: ValueKey('practice-draw-ceremony-dim'),
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.12),
                  radius: 1.1,
                  colors: [
                    Color(0xD22A1248), // _kStageGlow @ ~0.82
                    Color(0xE6000000), // black @ ~0.9
                  ],
                  stops: [0.0, 1.0],
                ),
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: Align(
            alignment: _stageAlignment,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                KeyedSubtree(
                  key: _stageKey,
                  child: SizedBox(
                    width: stageW,
                    height: stageH,
                    child: _phase == _CeremonyPhase.drawing
                        ? _buildWaitingStage(cardSize)
                        : _buildRevealStage(cardSize),
                  ),
                ),
                const SizedBox(height: 24),
                Opacity(opacity: _captionOpacity(), child: _buildCaption()),
              ],
            ),
          ),
        ),
        if (hint > 0.001)
          Positioned(
            left: 16,
            right: 16,
            bottom: MediaQuery.paddingOf(context).bottom + 24,
            child: IgnorePointer(
              child: Opacity(
                opacity: hint,
                child: Text(
                  '點擊任意處繼續',
                  key: const ValueKey('practice-draw-ceremony-hint'),
                  textAlign: TextAlign.center,
                  style: AppTypography.caption.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
          ),
        if (_phase == _CeremonyPhase.archiving)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                key: const ValueKey('practice-draw-ceremony-archive-orb'),
                painter: _ArchiveOrbPainter(
                  ms: _archiveMs,
                  origin: _archiveOrigin,
                  control: _archiveControl,
                  target: _archiveTarget,
                ),
              ),
            ),
          ),
      ],
    );
  }

  double _backdropOpacity() {
    switch (_phase) {
      case _CeremonyPhase.drawing:
        return practiceIntroBackdrop(_introMs);
      case _CeremonyPhase.revealing:
      case _CeremonyPhase.holding:
        return 1;
      case _CeremonyPhase.archiving:
        return practiceArchiveBackdrop(_archiveMs);
      case _CeremonyPhase.hidden:
        return 0;
    }
  }

  double _captionOpacity() {
    switch (_phase) {
      case _CeremonyPhase.drawing:
        return practiceCaptionIn(_captionMs) *
            practiceIntroCardOpacity(_introMs);
      case _CeremonyPhase.revealing:
        return _captionAtRevealStart *
            (1 -
                practiceRevealSeg(
                  _revealMs,
                  0,
                  PracticeRevealTiming.captionOutMs,
                ));
      case _CeremonyPhase.hidden:
      case _CeremonyPhase.holding:
      case _CeremonyPhase.archiving:
        return 0;
    }
  }

  double _hintOpacity() {
    switch (_phase) {
      case _CeremonyPhase.revealing:
        return _hintMaxOpacity * practiceRevealHintIn(_revealMs);
      case _CeremonyPhase.holding:
        return _hintMaxOpacity;
      case _CeremonyPhase.archiving:
        return _hintMaxOpacity *
            (1 -
                practiceRevealSeg(
                  _archiveMs,
                  0,
                  PracticeRevealTiming.hintOutEndMs,
                ));
      case _CeremonyPhase.hidden:
      case _CeremonyPhase.drawing:
        return 0;
    }
  }

  Widget _buildCaption() {
    return Text(
      key: const ValueKey('practice-draw-ceremony-caption'),
      '正在為你翻牌…',
      style: AppTypography.titleSmall.copyWith(
        color: Colors.white.withValues(alpha: 0.94),
        fontWeight: FontWeight.w700,
        shadows: [
          Shadow(color: _kGold.withValues(alpha: 0.4), blurRadius: 12),
          Shadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 8),
        ],
      ),
    );
  }

  /// 等待呼吸中的卡片姿態（入場＋上下浮動＋呼吸縮放＋金光）。全由 [_intro] 與
  /// [_waiting] 的單一 sin 週期推導；reduce-motion／已停時 `_waiting.value` 不前進＝靜止。
  _CardPose _waitingPose() {
    final enter = practiceIntroCard(_introMs);
    final wphase = _waiting.value * 2 * math.pi;
    // 入場未完成時壓低等待微動，避免和入場位移互相打架。
    final settle = Curves.easeIn.transform(_intro.value.clamp(0.0, 1.0));
    final breath = 0.5 + 0.5 * math.sin(wphase); // 0..1 呼吸相位
    return _CardPose(
      dy: math.sin(wphase) * 3.6 * settle + 30 * (1 - enter),
      scale: (0.85 + 0.15 * enter) * (1 + 0.013 * breath * settle),
      glow: (0.52 + 0.26 * breath).clamp(0.0, 1.0),
    );
  }

  // 抽牌中：神秘卡背入場＋（等待 server 期間）持續蓄力微動。
  Widget _buildWaitingStage(Size cardSize) {
    final pose = _waitingPose();
    final opacity = practiceIntroCardOpacity(_introMs);
    return Stack(
      alignment: Alignment.center,
      children: [
        // 星光：入場浮現，之後改由等待相位持續閃爍（reduce-motion 靜止）。
        Positioned.fill(
          child: CustomPaint(
            painter: _StarfieldPainter(
              twinkle: _intro.value + _waiting.value,
              intensity: (0.55 + 0.45 * _intro.value) * opacity,
            ),
          ),
        ),
        Opacity(
          opacity: opacity,
          child: Transform.translate(
            key: const ValueKey('practice-draw-ceremony-waiting-motion'),
            offset: Offset(0, pose.dy),
            child: Transform.scale(
              scale: pose.scale,
              child: _CeremonyCardBack(
                width: cardSize.width,
                height: cardSize.height,
                glow: pose.glow,
                rimIntensity: pose.glow,
                rimProgress: _waiting.value,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 揭曉／停住／收卡：蓄力 → 單次翻牌（側立那一刻閃光遮住換面）→ 正面落定。
  Widget _buildRevealStage(Size cardSize) {
    final ms = _revealMs;
    final pose = practiceRevealPose(ms);
    final blend = practiceRevealSeg(ms, 0, PracticeRevealTiming.poseBlendMs);
    final charge = practiceRevealChargeGlow(ms);
    final flash = practiceRevealFlipFlash(ms);
    final archiving = _phase == _CeremonyPhase.archiving;
    final archiveMs = _archiveMs;
    final cardOpacity = archiving ? practiceArchiveCardOpacity(archiveMs) : 1.0;
    final collapse = archiving ? practiceArchiveCardScale(archiveMs) : 1.0;
    final fadeOut = archiving ? practiceArchiveBackdrop(archiveMs) : 1.0;
    final dy = lerpDouble(_startPose.dy, 0, blend)!;
    final scale =
        pose.scale * lerpDouble(_startPose.scale, 1, blend)! * collapse;
    final glow = lerpDouble(_startPose.glow, 0.6 + 0.4 * charge, blend)!;
    final girl = _revealGirl;

    final Widget face = pose.yaw > 90 && girl != null
        ? Transform(
            alignment: Alignment.center,
            transform: Matrix4.rotationY(math.pi),
            child: _CeremonyCardFront(
              girl: girl,
              width: cardSize.width,
              height: cardSize.height,
              appear: practiceRevealInfoAppear(ms),
              photoScale: practiceRevealPhotoScale(ms),
            ),
          )
        : _CeremonyCardBack(
            width: cardSize.width,
            height: cardSize.height,
            glow: glow,
            rimIntensity: (0.5 + 0.5 * charge).clamp(0.0, 1.0),
            rimProgress: ms / 1700,
          );

    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _StarfieldPainter(
              twinkle: ms / PracticeRevealTiming.revealMs,
              intensity: ((0.45 + 0.25 * charge + 0.6 * flash) * fadeOut)
                  .clamp(0.0, 1.0),
            ),
          ),
        ),
        if (cardOpacity > 0.001)
          Opacity(
            opacity: cardOpacity,
            child: Transform.translate(
              offset: Offset(0, dy),
              child: Transform.scale(
                scale: scale,
                child: Transform(
                  key: const ValueKey('practice-draw-ceremony-card-3d'),
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 1 / 1200)
                    ..rotateX(pose.pitch * math.pi / 180)
                    ..rotateY(pose.yaw * math.pi / 180),
                  child: face,
                ),
              ),
            ),
          ),
        if (flash > 0.02)
          Positioned.fill(
            child: CustomPaint(
              key: const ValueKey('practice-draw-ceremony-flip-flash'),
              painter: _RevealFlashPainter(intensity: flash),
            ),
          ),
      ],
    );
  }
}

// ── 儀式專屬色票（scoped，不污染全域 AppColors）─────────────────────────────
const Color _kGold = Color(0xFFF4D58D);
const Color _kGoldDeep = Color(0xFFCB962F);
const Color _kCrystalLight = Color(0xFFB892FF); // 紫水晶高光／徽記頂面、角寶石亮 facet
// G2 重做：復刻參考片「黑塔羅」卡背用色。
const Color _kInkDeep = Color(0xFF050409); // 卡背近黑底（四角最暗）／迷宮 bevel 暗底
const Color _kLavender = Color(0xFF9E86E0); // 方形紫光節點／徽記中段紫
const Color _kMagenta = Color(0xFFB773D6); // 徽記底段洋紫
// G2 第2刀（Eric Gate-fail 後逐幀 trace）：霓虹框＋拉絲面板灰。
const Color _kNeonCyan = Color(0xFF45DCF7); // 霓虹框上緣 cyan bloom
const Color _kPanelHi = Color(0xFF1B1822); // 背景斜向拉絲面板較亮灰
const Color _kPanelLo = Color(0xFF09080E); // 背景斜向拉絲面板較暗灰
const Color _kTeal = Color(0xFF4FE0C8); // 典藏卡 teal accent
const Color _kGrandGlass = Color(0xCC0E0A1C); // 典藏卡 frosted 深色玻璃資訊欄底

/// 神秘卡背：深紫漸層 ＋ 金色雙鑲邊 ＋ 中央發光圖騰 ＋ 角落金飾，刻意不顯任何
/// 身份線索。`glow` 控制外圈金光強度（抽牌中柔光、翻面前漸亮）。
class _CeremonyCardBack extends StatelessWidget {
  const _CeremonyCardBack({
    required this.width,
    required this.height,
    this.glow = 0.6,
    this.rimIntensity,
    this.rimProgress = 0,
  });

  final double width;
  final double height;
  final double glow;
  final double? rimIntensity;
  final double rimProgress;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(22);
    final neonOpacity = ((glow - 0.42) / 0.48).clamp(0.0, 1.0);
    final rim = (rimIntensity ?? neonOpacity).clamp(0.0, 1.0);
    return Container(
      key: const ValueKey('practice-draw-ceremony-back'),
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          // 外圈脈動能量光暈（參考片 cyan→gold neon border 的 bloom）。
          BoxShadow(
            color: _kGold.withValues(alpha: 0.20 + 0.26 * glow),
            blurRadius: 30,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: _kTeal.withValues(alpha: 0.10 + 0.16 * glow),
            blurRadius: 42,
            spreadRadius: 1,
          ),
        ],
      ),
      // G2 重做：卡背改「黑塔羅」——近黑底＋金羅盤紋章＋小紫立方徽記（_MysticBackPainter），
      // 上覆賽博金框（chamfer 倒角＋上下 bracket＋segment ticks，_CyberFramePainter）。
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              _kReferenceCardBackBaseAsset,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.high,
              gaplessPlayback: true,
            ),
            Opacity(
              opacity: neonOpacity,
              child: Image.asset(
                _kReferenceCardBackNeonAsset,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
              ),
            ),
            if (rim > 0.01)
              CustomPaint(
                key: const ValueKey('practice-draw-ceremony-reference-rim'),
                painter: _ReferenceRimGlowPainter(
                  progress: rimProgress,
                  intensity: rim,
                ),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.08 * glow),
                    Colors.transparent,
                    _kTeal.withValues(alpha: 0.06 * neonOpacity),
                  ],
                  stops: const [0.0, 0.46, 1.0],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReferenceRimGlowPainter extends CustomPainter {
  _ReferenceRimGlowPainter({
    required this.progress,
    required this.intensity,
  });

  final double progress;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0) return;
    final shortest = size.shortestSide;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(shortest * 0.018),
      Radius.circular(shortest * 0.068),
    );
    final baseShader = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        _kTeal.withValues(alpha: 0.62 * intensity),
        _kGold.withValues(alpha: 0.72 * intensity),
      ],
    ).createShader(rect);

    final bloom = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = shortest * 0.035
      ..shader = baseShader
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, shortest * 0.028);
    canvas.drawRRect(rrect, bloom);

    final core = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = shortest * 0.010
      ..shader = baseShader
      ..strokeCap = StrokeCap.round;
    canvas.drawRRect(rrect.deflate(shortest * 0.006), core);

    final path = Path()..addRRect(rrect.deflate(shortest * 0.012));
    final metric = path.computeMetrics().first;
    final sweep = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = shortest * 0.018
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.86 * intensity)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, shortest * 0.010);
    _drawMovingSegment(canvas, metric, progress, 0.16, sweep);

    final hot = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = shortest * 0.006
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.92 * intensity);
    _drawMovingSegment(canvas, metric, progress + 0.04, 0.08, hot);
  }

  void _drawMovingSegment(
    Canvas canvas,
    PathMetric metric,
    double p,
    double lenRatio,
    Paint paint,
  ) {
    final length = metric.length;
    final start = ((p % 1.0) * length).clamp(0.0, length);
    final segment = lenRatio * length;
    final end = start + segment;
    if (end <= length) {
      canvas.drawPath(metric.extractPath(start, end), paint);
      return;
    }
    canvas.drawPath(metric.extractPath(start, length), paint);
    canvas.drawPath(metric.extractPath(0, end - length), paint);
  }

  @override
  bool shouldRepaint(_ReferenceRimGlowPainter old) =>
      old.progress != progress || old.intensity != intensity;
}

/// 正面卡的外框厚度與圓角：內圓角＝外圓角−框厚，四角保持同心。
const double _kFrontRadius = 24;
const double _kFrontFrameWidth = 4;

/// 翻開後的正面（沿用 V2 金框典藏卡外觀）：今日對象照片 ＋ 稀有度色邊框 ＋ badge ＋
/// frosted 資訊欄（名字、年齡·城市·職業、星等）。名字單獨成行、meta 用 `·` 串接，
/// **刻意避開** 練習室 hero 的「名字，年齡」精確字串。`appear` 讓資訊浮出、
/// `photoScale` 讓照片從 1.08 緩縮到 1.00。
class _CeremonyCardFront extends StatelessWidget {
  const _CeremonyCardFront({
    required this.girl,
    required this.width,
    required this.height,
    this.appear = 1,
    this.photoScale = 1,
  });

  final PracticeGirlProfile? girl;
  final double width;
  final double height;
  final double appear;
  final double photoScale;

  @override
  Widget build(BuildContext context) {
    // 結果卡稀有度呈現：邊框／光暈套 rarity 色（SR 金、R 青藍、N 銀灰），badge＋星等
    // 沿用圖鑑元件。girl 未知（理論上必有）兜底原金色。
    final PracticeGirlRarity? rarity = girl?.rarity;
    final Color frameColor =
        rarity == null ? _kGold : practiceRarityColor(rarity);
    final Color frameDeep = rarity == null
        ? _kGoldDeep
        : Color.lerp(frameColor, Colors.black, 0.35)!;
    final radius = BorderRadius.circular(_kFrontRadius);
    final innerRadius =
        BorderRadius.circular(_kFrontRadius - _kFrontFrameWidth);
    // 揭曉後資訊「浮出」：自下方 14px 上升到定位。
    final infoRise = (1 - Curves.easeOutCubic.transform(appear)) * 14;
    final infoOpacity = Curves.easeOut.transform(appear).clamp(0.0, 1.0);

    return Container(
      key: const ValueKey('practice-draw-ceremony-front'),
      width: width,
      height: height,
      // padding 即卡框厚度：金框稍薄讓金邊銳利。
      padding: const EdgeInsets.all(_kFrontFrameWidth),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [frameColor, frameDeep, frameColor],
          stops: const [0.0, 0.5, 1.0],
        ),
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: frameColor.withValues(alpha: 0.46 + 0.32 * appear),
            blurRadius: 46,
            spreadRadius: 2,
          ),
          BoxShadow(
            color: _kTeal.withValues(alpha: 0.20),
            blurRadius: 34,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: innerRadius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (girl != null)
              // 照片緩縮只作用在照片本身（clip 內），卡框不動。
              Transform.scale(
                scale: photoScale,
                alignment: const Alignment(0, -0.3),
                child: PracticeGirlPhoto(
                  profile: girl!,
                  width: width,
                  height: height,
                  borderRadius: innerRadius,
                ),
              )
            else
              const ColoredBox(color: AppColors.brandSurface2),
            // 底部漸層 scrim 讓名字可讀。
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.46, 1.0],
                  colors: [Colors.transparent, Color(0xE6000000)],
                ),
              ),
            ),
            // 細內框，呼應卡背的鑲邊語彙（套 rarity 色）。
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: innerRadius,
                border: Border.all(
                  color: frameColor.withValues(alpha: 0.72),
                  width: 1.4,
                ),
              ),
            ),
            // 稀有度 badge（沿用圖鑑樣式）：翻開第一幀就是正確稀有度。
            if (rarity != null)
              Positioned(
                top: 10,
                left: 10,
                child: KeyedSubtree(
                  key: const ValueKey('practice-draw-ceremony-rarity-badge'),
                  child: PracticeRarityBadge(rarity: rarity, fontSize: 12),
                ),
              ),
            if (girl != null)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Transform.translate(
                  offset: Offset(0, infoRise),
                  child: Opacity(
                    opacity: infoOpacity,
                    child: _GrandInfoBar(girl: girl!),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// grand 典藏卡專屬資訊欄：frosted 深色玻璃（背景模糊）＋ teal accent meta。
/// 同 [_FrontInfo] 欄位、同避開 hero「名字，年齡」精確字串，只是升階成玻璃質感。
class _GrandInfoBar extends StatelessWidget {
  const _GrandInfoBar({required this.girl});

  final PracticeGirlProfile girl;

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary 隔離 blur：BackdropFilter 底下全是每幀在動的東西，
    // 不隔離會整片合成回讀。
    return RepaintBoundary(
      child: ClipRRect(
        key: const ValueKey('practice-draw-ceremony-grand-info'),
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _kGrandGlass,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: _kTeal.withValues(alpha: 0.42),
                width: 1,
              ),
            ),
            child: _FrontInfo(girl: girl, accent: _kTeal, rarity: girl.rarity),
          ),
        ),
      ),
    );
  }
}

/// 正面卡的文字資訊塊：名字（大）＋ 年齡·城市·職業（meta 行）＋（grand）星等。
class _FrontInfo extends StatelessWidget {
  const _FrontInfo({required this.girl, this.accent = _kGold, this.rarity});

  final PracticeGirlProfile girl;
  // meta 行的 accent 色：preview 用金、grand 典藏卡用 teal。
  final Color accent;

  // 有值＝grand 結果卡：meta 下加星等列（沿用圖鑑樣式）；preview 白卡不顯。
  final PracticeGirlRarity? rarity;

  @override
  Widget build(BuildContext context) {
    // meta：年齡·城市·職業，過濾空欄，避開 hero 的「名字，年齡」精確字串。
    final meta = <String>[
      '${girl.age}',
      if (girl.city.isNotEmpty) girl.city,
      if (girl.professionLabel.isNotEmpty) girl.professionLabel,
    ].join(' · ');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          girl.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.titleMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            shadows: [
              Shadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 8),
            ],
          ),
        ),
        const SizedBox(height: 3),
        Text(
          meta,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodySmall.copyWith(
            color: accent.withValues(alpha: 0.95),
            fontWeight: FontWeight.w700,
            shadows: [
              Shadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 6),
            ],
          ),
        ),
        if (rarity != null) ...[
          const SizedBox(height: 6),
          KeyedSubtree(
            key: const ValueKey('practice-draw-ceremony-rarity-stars'),
            child: PracticeRarityStars(rarity: rarity!, size: 16),
          ),
        ],
      ],
    );
  }
}

/// 測試用 seam：建立 [_MysticBackPainter]（painter 本體 library-private，與其他
/// painter 一致；僅此 seam 對 widget test 暴露具名建構）。
@visibleForTesting
CustomPainter debugMysticBackPainter({required double glow}) =>
    _MysticBackPainter(glow: glow);

/// 揭曉「結果卡」的 test/preview seam：免跑整條儀式時間軸即可單獨渲染結果卡，
/// 驗稀有度邊框／badge／星等（動畫本體不在此 seam 範圍）。
@visibleForTesting
Widget debugCeremonyGrandCardFront({
  required PracticeGirlProfile girl,
  required double width,
  required double height,
}) =>
    _CeremonyCardFront(girl: girl, width: width, height: height);

/// 卡背整體（背景＋賽博金框＋羅盤紋章）的 test/preview seam：讓 still-recorder 與
/// widget test 免跑整條儀式即可單獨渲染、目檢卡背還原度。
@visibleForTesting
Widget debugCeremonyCardBack({
  required double width,
  required double height,
  double glow = 0.6,
}) =>
    _CeremonyCardBack(width: width, height: height, glow: glow);

/// 收卡光球的目標格（overlay 本地座標）：widget test 驗「光球飛向剛抽到的那一格」。
/// 沒有目標（原地收束）或不是收卡光球的 painter 都回 null。
@visibleForTesting
Rect? debugArchiveOrbTarget(CustomPainter painter) =>
    painter is _ArchiveOrbPainter ? painter.target : null;

/// 神秘卡背（G2 第2刀：Eric Gate-fail 後改「疊半透明 overlay 逐幀 trace」復刻
/// `音檔.mp4` t≈2.5s 卡背，非文字描述 redesign）：
/// 灰黑拉絲面板＋斜向柔光束底 → 淡電路幾何（長軸/淡弧/放射齒/對角線，**非**搶戲大環）
/// → 方形紫光節點（接在線路上）→ 中央一顆**扁平**大徽記（金線迷宮：頂部巢狀 chevron
/// ＋左右鏡像螺旋鉤，紫漸層底＋金邊，**非** 3D 立方體）。外框霓虹由 [_CyberFramePainter]
/// 蓋上（cyan→gold bloom 厚發光框）。
///
/// **確定性、零 Random**：佈點／明暗全由幾何決定（`shouldRepaint` 只認 [glow]）。
class _MysticBackPainter extends CustomPainter {
  _MysticBackPainter({required this.glow});

  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final s = size.shortestSide;
    _paintBackground(canvas, size);
    _paintCircuit(canvas, size, c, s);
    _paintNodes(canvas, c, s);
    _paintEmblem(canvas, c, s);
  }

  // 背景：灰黑徑向底（非純黑）＋ ~-28° 斜向拉絲面板（亮/暗灰交錯）＋ 2 道斜向柔光束
  // （blur，影片光暈感）＋ 角落 vignette。逐幀 trace 參考片的霧面金屬質感。
  void _paintBackground(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final w = size.width;
    final h = size.height;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.05),
          radius: 1.0,
          colors: [Color(0xFF17151E), Color(0xFF0E0D14), Color(0xFF070608)],
          stops: [0.0, 0.55, 1.0],
        ).createShader(rect),
    );
    canvas.save();
    canvas.clipRect(rect);
    final diag = Offset(math.cos(-0.49), math.sin(-0.49)); // ~-28°
    final perp = Offset(-diag.dy, diag.dx);
    final bandW = w * 0.27;
    final long = (h + w) * 1.2;
    for (var i = -3; i <= 4; i++) {
      final shade = i.isEven ? _kPanelHi : _kPanelLo;
      final mid = Offset(w / 2, h / 2) + perp * (i * bandW);
      canvas.drawPath(
        Path()
          ..addPolygon([
            mid + diag * long + perp * (bandW * 0.5),
            mid - diag * long + perp * (bandW * 0.5),
            mid - diag * long - perp * (bandW * 0.5),
            mid + diag * long - perp * (bandW * 0.5),
          ], true),
        Paint()..color = shade.withValues(alpha: 0.28),
      );
    }
    // 斜向柔光束（更寬更糊，霧面感不結帶）。
    for (final f in [0.34, 0.72]) {
      canvas.drawLine(
        Offset(w * f - w * 0.3, -h * 0.1),
        Offset(w * f + w * 0.28, h * 1.1),
        Paint()
          ..strokeWidth = w * 0.2
          ..color = Colors.white.withValues(alpha: 0.03 + 0.02 * glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 48),
      );
    }
    canvas.restore();
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          radius: 0.95,
          colors: [Colors.transparent, _kInkDeep.withValues(alpha: 0.55)],
          stops: const [0.58, 1.0],
        ).createShader(rect),
    );
  }

  // 淡電路幾何：垂直長軸＋水平軸＋四對角連接線＋上下兩段淡弧（取代搶戲大環）＋外圈
  // 放射短齒。全部低 alpha，弱化讓徽記主導（Eric：羅盤太重）。
  void _paintCircuit(Canvas canvas, Size size, Offset c, double s) {
    final axis = Paint()
      ..strokeWidth = 1
      ..color = _kGold.withValues(alpha: 0.16 + 0.1 * glow);
    canvas.drawLine(Offset(c.dx, size.height * 0.10),
        Offset(c.dx, size.height * 0.90), axis);
    final hx = s * 0.40;
    canvas.drawLine(Offset(c.dx - hx, c.dy), Offset(c.dx + hx, c.dy), axis);

    final diag = Paint()
      ..strokeWidth = 1
      ..color = _kGold.withValues(alpha: 0.09 + 0.05 * glow);
    for (final a in [
      -math.pi * 3 / 4,
      -math.pi / 4,
      math.pi / 4,
      math.pi * 3 / 4,
    ]) {
      canvas.drawLine(c, c + Offset(math.cos(a), math.sin(a)) * s * 0.42, diag);
    }

    final rArc = s * 0.34;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = _kGold.withValues(alpha: 0.12 + 0.07 * glow);
    canvas.drawArc(Rect.fromCircle(center: c, radius: rArc), -math.pi * 0.82,
        math.pi * 0.64, false, arc);
    canvas.drawArc(Rect.fromCircle(center: c, radius: rArc), math.pi * 0.18,
        math.pi * 0.64, false, arc);

    const ticks = 60;
    final tick = Paint()
      ..strokeWidth = 0.8
      ..color = _kGoldDeep.withValues(alpha: 0.15 + 0.1 * glow);
    for (var i = 0; i < ticks; i++) {
      final a = i * 2 * math.pi / ticks;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + d * (rArc * 1.02), c + d * (rArc * 1.1), tick);
    }
  }

  // 方形紫光節點：四對角主節點（接在對角線端）＋四方位金鑽（接軸線端）＋軸上小節點。
  // 皆 beveled 方塊，貼在線路上（Eric：方形節點接線路，非四顆獨立菱形寶石）。
  void _paintNodes(Canvas canvas, Offset c, double s) {
    for (final a in [
      -math.pi * 3 / 4,
      -math.pi / 4,
      math.pi / 4,
      math.pi * 3 / 4,
    ]) {
      _squareNode(
          canvas, c + Offset(math.cos(a), math.sin(a)) * s * 0.34, s * 0.036);
    }
    for (final a in [-math.pi / 2, 0.0, math.pi / 2, math.pi]) {
      _goldDiamond(
          canvas, c + Offset(math.cos(a), math.sin(a)) * s * 0.40, s * 0.02);
    }
    _goldDiamond(canvas, Offset(c.dx, c.dy - s * 0.40 * 0.62), s * 0.014);
    _goldDiamond(canvas, Offset(c.dx, c.dy + s * 0.40 * 0.62), s * 0.014);
  }

  // beveled 方形紫光節點（左上來光：上半亮 facet、下半暗 facet＋金邊＋白高光）。
  void _squareNode(Canvas canvas, Offset p, double half) {
    final rect = Rect.fromCenter(center: p, width: half * 2, height: half * 2);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kCrystalLight, _kLavender, _kMagenta],
        ).createShader(rect),
    );
    canvas.drawRect(
      Rect.fromCenter(center: p, width: half, height: half),
      Paint()..color = Colors.white.withValues(alpha: 0.22 + 0.1 * glow),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _kGold.withValues(alpha: 0.65),
    );
  }

  void _goldDiamond(Canvas canvas, Offset p, double r) {
    final path = Path()
      ..moveTo(p.dx, p.dy - r)
      ..lineTo(p.dx + r, p.dy)
      ..lineTo(p.dx, p.dy + r)
      ..lineTo(p.dx - r, p.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = _kGold.withValues(alpha: 0.85));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = _kGoldDeep,
    );
  }

  // 中央徽記（扁平、放大）：六邊紫漸層底＋金邊，上覆金線迷宮（頂部巢狀 chevron＋左右
  // 鏡像螺旋鉤）。非 3D 立方體、非三面陰影（Eric：退掉 cube，照參考扁平迷宮重畫且放大）。
  void _paintEmblem(Canvas canvas, Offset c, double s) {
    final rE = s * 0.175;
    final verts = [
      for (var k = 0; k < 6; k++)
        c +
            Offset(math.cos(-math.pi / 2 + k * math.pi / 3),
                    math.sin(-math.pi / 2 + k * math.pi / 3)) *
                rE,
    ];

    canvas.drawCircle(
      c,
      rE * 1.5,
      Paint()
        ..shader = RadialGradient(
          colors: [
            _kCrystalLight.withValues(alpha: 0.2 + 0.16 * glow),
            _kCrystalLight.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: rE * 1.5)),
    );

    final hex = Path()..addPolygon(verts, true);
    canvas.drawPath(
      hex,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          // 上亮（lavender-white）下深紫漸層，讓金線迷宮跳出（Eric：中心密、徽記主導）。
          colors: const [_kCrystalLight, _kMagenta, Color(0xFF512E72)],
        ).createShader(Rect.fromCircle(center: c, radius: rE)),
    );
    canvas.drawPath(
      hex,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round
        ..color = _kGold.withValues(alpha: 0.8 + 0.2 * glow),
    );

    _emblemMaze(canvas, c, rE);
  }

  // 金線迷宮（emblem-local 座標，單位 rE）：頂部 2 道巢狀 chevron＋中央立柱＋左右鏡像
  // 方形螺旋鉤（Greek key）。bevel 暗底＋亮金面。
  void _emblemMaze(Canvas canvas, Offset c, double rE) {
    // 頂部 3 道巢狀 chevron（填滿上 1/3），bevel 暗底＋亮金。
    for (var i = 0; i < 3; i++) {
      final y = -0.78 + i * 0.18;
      final hw = 0.46 - i * 0.1;
      _goldPolyline(
          canvas,
          c,
          rE,
          [
            [-hw, y + 0.2],
            [0, y],
            [hw, y + 0.2],
          ],
          w: 2.6);
    }
    // 中央立柱（chevron 底→近底點），貫穿迷宮中軸。
    _goldPolyline(
        canvas,
        c,
        rE,
        [
          [0, -0.16],
          [0, 0.78],
        ],
        w: 2.4);
    // 左右鏡像方形螺旋鉤（Greek key），放大填滿下 2/3。
    const left = [
      [-0.06, 0.02],
      [-0.64, 0.02],
      [-0.64, 0.74],
      [-0.04, 0.74],
      [-0.04, 0.34],
      [-0.4, 0.34],
      [-0.4, 0.52],
    ];
    _goldPolyline(canvas, c, rE, left, w: 2.4);
    _goldPolyline(
        canvas,
        c,
        rE,
        [
          for (final p in left) [-p[0], p[1]]
        ],
        w: 2.4);
  }

  void _goldPolyline(Canvas canvas, Offset c, double rE, List<List<num>> pts,
      {double w = 2.4}) {
    Offset map(List<num> ab) => Offset(c.dx + ab[0] * rE, c.dy + ab[1] * rE);
    final path = Path()..moveTo(map(pts.first).dx, map(pts.first).dy);
    for (final ab in pts.skip(1)) {
      final p = map(ab);
      path.lineTo(p.dx, p.dy);
    }
    // 金線柔光 bloom（影片發光感）。
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w + 3
        ..strokeJoin = StrokeJoin.round
        ..color = _kGold.withValues(alpha: 0.28 + 0.12 * glow)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    // bevel 暗底。
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w + 1.6
        ..strokeJoin = StrokeJoin.round
        ..color = _kInkDeep.withValues(alpha: 0.6),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = _kGold.withValues(alpha: 0.92),
    );
  }

  @override
  bool shouldRepaint(_MysticBackPainter old) => old.glow != glow;
}

/// 賽博霓虹外框（G2 第2刀，trace 參考片厚發光框）：cyan→gold 周邊漸層，多層 blur bloom
/// ＋亮核框＋白心 neon 高光；內倒角八邊細線＋上下中央 trapezoid bracket＋segment ticks。
@visibleForTesting
CustomPainter debugCyberFramePainter({required double glow}) =>
    _CyberFramePainter(glow: glow);

class _CyberFramePainter extends CustomPainter {
  _CyberFramePainter({required this.glow});

  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final s = size.shortestSide;
    final inset = s * 0.032;
    final rr = RRect.fromRectAndRadius(
      Rect.fromLTRB(inset, inset, w - inset, h - inset),
      Radius.circular(s * 0.07),
    );
    // 周邊霓虹：上緣 cyan → 左/下 gold（trace 參考片 neon 色相）。
    final glowShader = LinearGradient(
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
      colors: [
        _kNeonCyan.withValues(alpha: 0.5),
        _kGold.withValues(alpha: 0.55),
        _kGoldDeep.withValues(alpha: 0.5),
        _kGold.withValues(alpha: 0.55),
      ],
    ).createShader(rr.outerRect);
    final coreShader = const LinearGradient(
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
      colors: [_kNeonCyan, _kGold, _kGoldDeep, _kGold],
    ).createShader(rr.outerRect);

    // 1) 外發光多層 blur（bloom）。
    for (final b in [24.0, 13.0, 6.0]) {
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.03
          ..shader = glowShader
          ..maskFilter =
              MaskFilter.blur(BlurStyle.normal, b * (0.7 + 0.5 * glow)),
      );
    }
    // 2) 亮核框。
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.02
        ..shader = coreShader,
    );
    // 3) 白心 neon 高光。
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.006
        ..color = Colors.white.withValues(alpha: 0.55 + 0.3 * glow),
    );

    // 4) 內倒角八邊細線（cut corners，灰白）。
    final cut = s * 0.11;
    final pad = s * 0.08;
    canvas.drawPath(
      Path()
        ..moveTo(pad + cut, pad)
        ..lineTo(w - pad - cut, pad)
        ..lineTo(w - pad, pad + cut)
        ..lineTo(w - pad, h - pad - cut)
        ..lineTo(w - pad - cut, h - pad)
        ..lineTo(pad + cut, h - pad)
        ..lineTo(pad, h - pad - cut)
        ..lineTo(pad, pad + cut)
        ..close(),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = Colors.white.withValues(alpha: 0.18 + 0.12 * glow),
    );

    // 5) 上/下中央 trapezoid bracket（金實心 bevel）。
    _bracket(canvas, size, s, top: true);
    _bracket(canvas, size, s, top: false);

    // 6) segment ticks（左上內線小亮段）。
    final tick = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (final fx in [0.32, 0.37]) {
      canvas.drawLine(
          Offset(w * fx, pad), Offset(w * fx + s * 0.022, pad), tick);
    }
  }

  void _bracket(Canvas canvas, Size size, double s, {required bool top}) {
    final w = size.width;
    final edge = s * 0.032;
    final yEdge = top ? edge : size.height - edge;
    final yIn = top ? yEdge + s * 0.06 : yEdge - s * 0.06;
    final x0 = w * 0.32;
    final x1 = w * 0.68;
    final taper = s * 0.045;
    final path = Path()
      ..moveTo(x0, yEdge)
      ..lineTo(x1, yEdge)
      ..lineTo(x1 - taper, yIn)
      ..lineTo(x0 + taper, yIn)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: top ? Alignment.topCenter : Alignment.bottomCenter,
          end: top ? Alignment.bottomCenter : Alignment.topCenter,
          colors: const [_kGold, _kGoldDeep],
        ).createShader(path.getBounds()),
    );
  }

  @override
  bool shouldRepaint(_CyberFramePainter old) => old.glow != glow;
}

/// 中點揭曉 flash：白金徑向爆光，遮住翻面接縫，給「眼睛一亮」的揭曉瞬間。
class _RevealFlashPainter extends CustomPainter {
  _RevealFlashPainter({required this.intensity});

  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * (0.5 + 0.35 * intensity);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.85 * intensity),
          _kGold.withValues(alpha: 0.5 * intensity),
          _kGold.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.4, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(_RevealFlashPainter old) => old.intensity != intensity;
}

/// 收卡光球：卡片縮成金色光球，沿二次貝茲弧線飛進圖鑑那一格（拖尾＝沿路徑回推的
/// 殘影），落位時擴一圈光環。沒有目標格時在原地縮到 0。全由 [ms] 解析計算、零 Random。
class _ArchiveOrbPainter extends CustomPainter {
  _ArchiveOrbPainter({
    required this.ms,
    required this.origin,
    required this.control,
    required this.target,
  });

  final double ms;
  final Offset origin;
  final Offset control;
  final Rect? target;

  static const double _startRadius = 18;
  static const double _endRadius = 10;
  static const int _trailCount = 10;
  static const double _trailStep = 0.035;

  @override
  void paint(Canvas canvas, Size size) {
    final appear = PracticeRevealTiming.enter.transform(
      practiceRevealSeg(
        ms,
        PracticeRevealTiming.orbAppearStartMs,
        PracticeRevealTiming.flightStartMs,
      ),
    );
    if (appear <= 0) return;

    final goal = target;
    if (goal == null) {
      // 找不到目標格：不飛到別的卡上誤導，原地縮掉。
      final shrink = practiceRevealSeg(
        ms,
        PracticeRevealTiming.flightStartMs,
        PracticeRevealTiming.implodeEndMs,
      );
      _paintOrb(
          canvas, origin, _startRadius * appear * (1 - shrink), 1 - shrink);
      return;
    }

    final end = goal.center;
    final t = practiceArchiveFlightT(ms);
    final vanish = practiceRevealSeg(
      ms,
      PracticeRevealTiming.landMs,
      PracticeRevealTiming.landMs + PracticeRevealTiming.orbVanishMs,
    );
    for (var k = _trailCount; k >= 1; k--) {
      final tk = t - k * _trailStep;
      if (tk <= 0) continue;
      final fade = math.pow(1 - k / _trailCount, 2).toDouble() * (1 - vanish);
      canvas.drawCircle(
        practiceQuadBezier(origin, control, end, tk),
        _radiusAt(tk) * (1 - k / 12),
        Paint()..color = _kGold.withValues(alpha: 0.5 * fade),
      );
    }
    _paintOrb(
      canvas,
      practiceQuadBezier(origin, control, end, t),
      _radiusAt(t) * appear * (1 - vanish),
      1 - vanish,
    );

    final ring = practiceRevealSeg(
      ms,
      PracticeRevealTiming.landMs,
      PracticeRevealTiming.archiveMs,
    );
    if (ring > 0) {
      final maxRadius = Offset(goal.width, goal.height).distance * 0.6;
      canvas.drawCircle(
        end,
        maxRadius * Curves.easeOut.transform(ring),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = _kGold.withValues(alpha: 0.9 * (1 - ring)),
      );
    }
  }

  double _radiusAt(double t) => lerpDouble(_startRadius, _endRadius, t)!;

  void _paintOrb(Canvas canvas, Offset center, double radius, double alpha) {
    if (radius <= 0.1 || alpha <= 0) return;
    final glowRadius = radius * 2.6;
    canvas.drawCircle(
      center,
      glowRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            _kGold.withValues(alpha: 0.55 * alpha),
            _kGold.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: glowRadius)),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: alpha),
            _kGold.withValues(alpha: 0.9 * alpha),
          ],
          stops: const [0.35, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_ArchiveOrbPainter old) =>
      old.ms != ms ||
      old.origin != origin ||
      old.control != control ||
      old.target != target;
}

/// 星光粒子場：環繞卡牌一圈的金／白閃爍點（halo 佈點，避開中央照片區）。
/// 位置以 golden-angle 決定（**確定性、零 Random**，重建穩定）；`twinkle` 驅動
/// 閃爍相位、`intensity` 控制整體亮度（≤0 不畫）。
/// 測試用 seam：建立 [_StarfieldPainter]（painter 本體 library-private）。
@visibleForTesting
CustomPainter debugStarfieldPainter({
  required double twinkle,
  required double intensity,
  double beam = 0,
}) =>
    _StarfieldPainter(twinkle: twinkle, intensity: intensity, beam: beam);

class _StarfieldPainter extends CustomPainter {
  _StarfieldPainter({
    required this.twinkle,
    required this.intensity,
    this.beam = 0,
  });

  final double twinkle;
  final double intensity;
  final double beam; // 0..1 橫掃光束位置（0＝不畫，由高潮翻面段驅動）

  static const int _count = 34; // Batch C 加密（原 22）
  // golden angle，讓佈點均勻不打結。
  static const double _goldenAngle = 2.399963229728653;

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.shortestSide * 0.62;

    for (var i = 0; i < _count; i++) {
      // 佈在 0.40~0.64 半徑的環帶 → 圍繞卡牌、不蓋住中央照片。
      final ring = 0.40 + 0.24 * ((i * 7) % 11) / 11.0;
      final a = i * _goldenAngle;
      final pos = center + Offset(math.cos(a), math.sin(a)) * (maxR * ring);

      // 各自的閃爍相位（由 index 決定，確定性）。
      final phase = (i * _goldenAngle) % (2 * math.pi);
      final tw = 0.45 + 0.55 * math.sin(twinkle * 2 * math.pi + phase);
      final alpha = (tw * intensity).clamp(0.0, 1.0);
      if (alpha <= 0.02) continue;

      final r = 1.1 + 1.6 * (((i * 5) % 7) / 7.0);
      final isGold = i.isEven;
      final color = (isGold ? _kGold : Colors.white).withValues(alpha: alpha);

      // 柔光暈 + 亮核。
      canvas.drawCircle(
        pos,
        r * 2.2,
        Paint()
          ..color = color.withValues(alpha: alpha * 0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawCircle(pos, r, Paint()..color = color);
    }

    // 橫掃光束：beam>0 時一道水平亮帶由上而下掃過（高潮翻面的揭曉感）。淡入淡出靠
    // sin(beam·π)，beam 進出 0/1 時自然消失；確定性、零 Random。
    final glow = beam <= 0 ? 0.0 : math.sin(beam.clamp(0.0, 1.0) * math.pi);
    if (glow > 0.02) {
      final by = beam.clamp(0.0, 1.0) * size.height;
      final bandH = size.height * 0.18;
      final rect = Rect.fromLTRB(0, by - bandH / 2, size.width, by + bandH / 2);
      final shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Color.lerp(_kTeal, _kGold, 0.5)!
              .withValues(alpha: (0.5 * glow * intensity).clamp(0.0, 1.0)),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(rect);
      canvas.drawRect(rect, Paint()..shader = shader);
    }
  }

  @override
  bool shouldRepaint(_StarfieldPainter old) =>
      old.twinkle != twinkle || old.intensity != intensity || old.beam != beam;
}
