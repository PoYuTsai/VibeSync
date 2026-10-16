import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/app_haptics.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/practice_reveal_palette.dart';
import '../../data/providers/practice_chat_providers.dart';
import '../../domain/entities/practice_girl_profile.dart';
import '../../domain/entities/practice_girl_rarity.dart';
import 'practice_draw_sfx.dart';
import 'practice_reveal_card.dart';
import 'practice_reveal_painters.dart';
import 'practice_reveal_theme.dart';
import 'practice_reveal_timing.dart';

/// 蓄力三下輕震（規格 D8：先全開，真機嫌吵就關這一個開關）。
const bool _kChargeTicksEnabled = true;

/// 稀有度牌烙上那一下輕震（規格 D8：同上，單一開關）。
const bool _kStampTapEnabled = true;

/// 揭曉背景：高斯模糊 σ 與暗化的最大值（規格 §6.2）。
const double _kBackdropSigma = 24;
const double _kBackdropDim = 0.85;

/// 等待呼吸一圈的長度；環境星塵也以它為一圈。
const Duration _kWaitingCycle = Duration(milliseconds: 2600);

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

/// 每日翻牌「揭曉儀式」全螢幕 overlay（V3：單次翻牌＋停住等點擊＋收卡飛行）。
///
/// 規格：`docs/plans/2026-10-15-card-draw-v3-luxury-reveal-spec.md`。第二刀換上 V3 外觀：
/// 背景模糊、銀色卡背依稀有度染色（銀 → 藍 → 金，只升到真實稀有度）、光刃與星塵、
/// 全息掃光、膠囊稀有度牌、兩行毛玻璃資訊欄與亮星；卡片元件在 `practice_reveal_card.dart`，
/// 特效 painter 在 `practice_reveal_painters.dart`。聲音（第三刀）：N／R／SR 同一條揭曉配樂
/// （翻牌紙聲混在裡面），點擊收卡時一聲收卡音；稀有度差別只靠畫面與觸覺（規格 D3）。
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
///   reduce-motion 啟動，其他出口一律 `stop()`。holding 期間沒有任何動畫（星塵凍結、
///   爆發星塵已燃盡），所以 `pumpAndSettle` 會停在 holding 收斂；要點「繼續」才收掉。
/// - reduce-motion（`MediaQuery.disableAnimations`）：沒有儀式畫面；抽中當下給觸覺，並立刻
///   通知圖鑑頁捲動與點亮那一格。
/// - haptic 走 [AppHaptics]（規格 §9 對拍表；稀有的手感必須不同）；音效走
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

/// 揭曉對拍點（`_reveal` 經過的毫秒，規格 §5.3）。配樂重音與翻牌紙聲都在 bed 裡，這裡
/// 只負責觸覺。
enum _RevealBeat {
  chargeTick0(0),
  chargeTick1(PracticeRevealTiming.chargeTick1Ms),
  chargeTick2(PracticeRevealTiming.chargeTick2Ms),

  /// 染成電光藍：R 一下 light、SR 一下 tap（N 不變色、不震）。
  dyeBlue(PracticeRevealTiming.dyeBlueMs),

  /// 只有 SR：染成香檳金的一下 light。
  dyeGold(PracticeRevealTiming.dyeGoldMs),

  /// 只有 SR：celebrate 三下共 200 ms，第三下重擊落在翻牌峰值。
  srBuild(PracticeRevealTiming.srBuildMs),

  /// 卡片正好側立：N／R 的重擊（翻牌紙聲已混在配樂 bed 的 1.35 s）。
  flipPeak(PracticeRevealTiming.flipPeakMs),

  /// 稀有度牌烙上：一下 tap。
  stamp(PracticeRevealTiming.stampStartMs),

  /// 星星逐顆點亮：只對亮星 tick（N 2、R 3、SR 4）。
  star0(PracticeRevealTiming.starsStartMs),
  star1(PracticeRevealTiming.starsStartMs + PracticeRevealTiming.starStaggerMs),
  star2(PracticeRevealTiming.starsStartMs +
      2 * PracticeRevealTiming.starStaggerMs),
  star3(PracticeRevealTiming.starsStartMs +
      3 * PracticeRevealTiming.starStaggerMs);

  const _RevealBeat(this.ms);

  final double ms;
}

/// 卡片在等待呼吸中的姿態；揭曉起手時抓下來，前 150 ms 混到蓄力姿態，避免跳格。
@immutable
class _CardPose {
  const _CardPose({
    required this.dy,
    required this.scale,
    required this.yaw,
    required this.emblem,
  });

  static const rest = _CardPose(dy: 0, scale: 1, yaw: 0, emblem: 0.35);

  final double dy;
  final double scale;

  /// 左右微擺（度）。
  final double yaw;

  /// 徽記銀光亮度。
  final double emblem;
}

class _PracticeDrawCeremonyState extends ConsumerState<PracticeDrawCeremony>
    with TickerProviderStateMixin {
  // 卡背入場（背景模糊暗化＋卡背浮現）；失敗時 reverse 當作淡出。
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: PracticeRevealTiming.intro,
  );

  // 等待字樣：server 超過 900 ms 還沒回來才淡入。
  late final AnimationController _caption = AnimationController(
    vsync: this,
    duration: PracticeRevealTiming.caption,
  );

  // 抽牌「等待 server 回應」期間的持續微動（上下浮動＋左右微擺＋銀光呼吸＋星塵上漂）。
  // 這是**唯一**會 `repeat()` 的 controller，故嚴格 gate：只在真實 drawing 階段且
  // 非 reduce-motion 才啟動，reveal／error／hidden／dispose 一律明確 `stop()`，確保
  // `pumpAndSettle` 不會因無限重播而 hang。一個迴圈 = 一次 sin 週期（首尾相接無跳變）。
  late final AnimationController _waiting = AnimationController(
    vsync: this,
    duration: _kWaitingCycle,
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

  /// 揭曉起手時環境星塵的相位：揭曉中接著往上漂，不跳格。
  double _dustPhaseAtRevealStart = 0;
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
    // 進入抽牌：浮現銀色卡背，觸覺＋咻聲。
    AppHaptics.light();
    _sfx.playWhoosh();
    // 揭曉配樂先載好：server 回來時從頭 resume，bed 裡的重音才對得上畫面。
    _sfx.preloadReveal();
    _precacheBack();
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
      _intro.value = 1; // 不做入場動畫：背景直接定在模糊暗化、卡背直接定住。
      _caption.value = 1;
      _waiting.stop(); // reduce-motion：等待期間靜止，不啟動持續微動。
      _sfx.stopWaitingLoop(); // reduce-motion：不啟動等待 loop（防殘留）。
    } else {
      _intro.forward(from: 0);
      _caption.forward(from: 0);
      _waiting.repeat(); // 等待 server 期間持續微動。
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
      _precacheBack();
      setState(() => _phase = _CeremonyPhase.drawing);
      _intro.forward();
    }
  }

  /// 卡背四張素材先解碼好，入場第一幀就有卡背。
  void _precacheBack() {
    for (final asset in kPracticeRevealBackAssets) {
      unawaited(
        precacheImage(AssetImage(asset), context, onError: (_, __) {}),
      );
    }
  }

  void _beginReveal() {
    final girl = _revealGirl;
    if (!mounted || girl == null) return;
    _startPose = _waitingPose();
    _captionAtRevealStart = _captionOpacity(); // 還在 drawing：取等待字樣當下透明度。
    _dustPhaseAtRevealStart = _waiting.value;
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
    final rarity = _revealGirl?.rarity ?? PracticeGirlRarity.n;
    final isSr = rarity == PracticeGirlRarity.sr;
    switch (beat) {
      case _RevealBeat.chargeTick0:
      case _RevealBeat.chargeTick1:
      case _RevealBeat.chargeTick2:
        if (_kChargeTicksEnabled) AppHaptics.tick();
      case _RevealBeat.dyeBlue:
        if (rarity == PracticeGirlRarity.r) AppHaptics.light();
        if (isSr) AppHaptics.tap();
      case _RevealBeat.dyeGold:
        if (isSr) AppHaptics.light();
      case _RevealBeat.srBuild:
        if (isSr) unawaited(AppHaptics.celebrate());
      case _RevealBeat.flipPeak:
        if (!isSr) AppHaptics.medium();
      case _RevealBeat.stamp:
        if (_kStampTapEnabled) AppHaptics.tap();
      case _RevealBeat.star0:
      case _RevealBeat.star1:
      case _RevealBeat.star2:
      case _RevealBeat.star3:
        if (beat.index - _RevealBeat.star0.index < rarity.stars) {
          AppHaptics.tick();
        }
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
    // 收卡：播收卡音；配樂與咻聲尾巴都淡出，不帶到圖鑑頁。
    _sfx.playArchive();
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
          child: LayoutBuilder(
            builder: (context, constraints) => AnimatedBuilder(
              animation: _ceremonyMotion,
              builder: (context, _) => _buildOverlay(constraints.biggest),
            ),
          ),
        ),
      ),
    );
  }

  // ── 疊加層 ──
  // 卡周圍留給 3D 透視的 padding；stage 寬再夾進螢幕寬，避免大卡溢出。
  static const double _stagePadding = 132;
  static const Alignment _stageAlignment = Alignment(0, -0.08);
  static const double _hintMaxOpacity = 0.72;

  /// 提示字淡入時同步上浮的距離（規格 §4：translateY +6 → 0）。
  static const double _hintRise = 6;

  Widget _buildOverlay(Size size) {
    final cardSize = practiceCeremonyCardSize(MediaQuery.sizeOf(context));
    final stageSize = Size(
      math.min(cardSize.width + _stagePadding, size.width),
      cardSize.height + _stagePadding,
    );
    final stageOrigin = _stageAlignment.alongOffset(
      Offset(size.width - stageSize.width, size.height - stageSize.height),
    );
    final cardCenter = stageOrigin + stageSize.center(Offset.zero);
    final holding = _phase == _CeremonyPhase.holding;
    final drawing = _phase == _CeremonyPhase.drawing;
    final archiving = _phase == _CeremonyPhase.archiving;
    final girl = _revealGirl;
    final rarity = girl?.rarity ?? PracticeGirlRarity.n;
    final theme = PracticeRevealTheme.of(rarity);
    final ms = _revealMs;
    final archiveMs = _archiveMs;
    final backdrop = _backdropFactor();
    final hint = _hintOpacity();

    // 環境光與環境星塵跟著卡背染色走（等待期與 N 全程是銀）。
    final backColors = drawing || girl == null
        ? PracticeRevealBackColors.silver
        : PracticeRevealBackColors.at(ms, rarity);
    final cardPresence = drawing
        ? practiceIntroCardOpacity(_introMs)
        : archiving
            ? practiceArchiveCardOpacity(archiveMs)
            : 1.0;
    final cardScale = drawing
        ? _waitingPose().scale
        : practiceRevealPose(ms).scale *
            (archiving ? practiceArchiveCardScale(archiveMs) : 1.0);
    final ambientScale = drawing ? 1.0 : practiceRevealAmbientScale(ms, rarity);
    final dustPhase = drawing
        ? _waiting.value
        : _dustPhaseAtRevealStart + ms / _kWaitingCycle.inMilliseconds;
    final burstMs = ms - PracticeRevealTiming.flipPeakMs;
    final showBurst = !drawing &&
        girl != null &&
        burstMs > 0 &&
        burstMs < kPracticeRevealBurstMaxLifeMs;
    final bladeHalo = drawing ? 0.0 : practiceRevealBladeWidth(ms);
    final bladeCore = drawing ? 0.0 : practiceRevealBladeCore(ms);
    final cross = drawing ? 0.0 : practiceRevealCross(ms, rarity);
    final showBlade = bladeHalo > 0 || bladeCore > 0 || cross > 0;

    return Stack(
      fit: StackFit.expand,
      children: [
        // L7 全螢幕點擊層（放最底下收點擊，其餘圖層一律 IgnorePointer）：drawing 只吞
        // 點擊（背景看不清，不讓誤點穿透到圖鑑）；揭曉起處理跳過與收卡。
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
        // L0 背景：高斯模糊＋暗化＋暗角。BackdropFilter 不包 Opacity，直接動 σ 與暗化
        // 的 alpha（規格 §6.2）；整段看不到底下的字。
        IgnorePointer(
          child: RepaintBoundary(
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: _kBackdropSigma * backdrop,
                sigmaY: _kBackdropSigma * backdrop,
              ),
              child: DecoratedBox(
                key: const ValueKey('practice-draw-ceremony-dim'),
                decoration: BoxDecoration(
                  color: PracticeRevealPalette.dim
                      .withValues(alpha: _kBackdropDim * backdrop),
                ),
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.06),
                radius: 0.95,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.55 * backdrop),
                ],
                stops: const [0.55, 1.0],
              ),
            ),
          ),
        ),
        // L1 環境光：卡片背後的稀有度色徑向光。
        IgnorePointer(
          child: CustomPaint(
            painter: PracticeRevealGlowPainter(
              center: cardCenter,
              radius: cardSize.height * 0.75 * ambientScale * cardScale,
              color: backColors.glow,
              alpha: backColors.ambientAlpha * cardPresence,
            ),
          ),
        ),
        // L2 環境星塵：慢慢往上漂；停住期間凍結。
        IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: PracticeRevealAmbientDustPainter(
                phase: dustPhase,
                color: backColors.glow,
                opacity: backdrop,
              ),
            ),
          ),
        ),
        // L3 卡片。
        Positioned(
          left: stageOrigin.dx,
          top: stageOrigin.dy,
          width: stageSize.width,
          height: stageSize.height,
          child: IgnorePointer(
            child: KeyedSubtree(
              key: _stageKey,
              child: RepaintBoundary(
                child: Center(child: _buildCard(cardSize)),
              ),
            ),
          ),
        ),
        // 翻牌爆發星塵：從光刃噴出，畫在卡片前面；停住前全部燃盡。
        if (showBurst)
          IgnorePointer(
            child: CustomPaint(
              painter: PracticeRevealBurstPainter(
                center: cardCenter,
                cardSize: cardSize,
                tauMs: burstMs,
                count: theme.burstCount,
                color: theme.star,
                holo: theme.holo,
                opacity: cardPresence,
              ),
            ),
          ),
        // L4 光刃：卡片側立那一刻（SR 加橫向十字）。
        if (showBlade)
          IgnorePointer(
            child: CustomPaint(
              key: const ValueKey('practice-draw-ceremony-light-blade'),
              painter: PracticeRevealBladePainter(
                center: cardCenter,
                cardSize: cardSize,
                halo: bladeHalo,
                core: bladeCore,
                coreAlpha: practiceRevealBladeCoreAlpha(ms),
                cross: cross,
                tint: theme.glow,
              ),
            ),
          ),
        // L5 等待字樣（卡片下方 24）與點擊提示（底部安全區上方 24）。
        Positioned(
          left: 16,
          right: 16,
          top: cardCenter.dy + cardSize.height / 2 + 24,
          child: IgnorePointer(
            child: Opacity(
              opacity: _captionOpacity(),
              child: _buildCaption(),
            ),
          ),
        ),
        if (hint > 0.001)
          Positioned(
            left: 16,
            right: 16,
            bottom: MediaQuery.paddingOf(context).bottom + 24,
            child: IgnorePointer(
              child: Transform.translate(
                offset: Offset(0, _hintDy()),
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
          ),
        // L6 收卡光球。
        if (archiving)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                key: const ValueKey('practice-draw-ceremony-archive-orb'),
                painter: PracticeRevealOrbPainter(
                  ms: archiveMs,
                  origin: _archiveOrigin,
                  control: _archiveControl,
                  target: _archiveTarget,
                  color: theme.orb,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 背景模糊與暗化的進度（0..1）：抽牌入場 0.3 s 進場；揭曉、停住全開；收卡淡出。
  double _backdropFactor() {
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

  /// 提示字的上浮位移：跟著淡入一起從下方 6 px 浮到原位；停住、收卡時定在原位。
  double _hintDy() => _phase == _CeremonyPhase.revealing
      ? _hintRise * (1 - practiceRevealHintIn(_revealMs))
      : 0;

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
      textAlign: TextAlign.center,
      style: AppTypography.caption.copyWith(
        color: Colors.white.withValues(alpha: 0.60),
        fontWeight: FontWeight.w600,
        letterSpacing: 1.5,
      ),
    );
  }

  /// 等待呼吸中的卡片姿態（入場＋上下浮動 ±3 px＋呼吸縮放 1.010＋左右微擺 ±2°＋徽記
  /// 銀光 0.30–0.45）。全由 [_intro] 與 [_waiting] 的單一 sin 週期推導；reduce-motion／
  /// 已停時 `_waiting.value` 不前進＝靜止。
  _CardPose _waitingPose() {
    final enter = practiceIntroCard(_introMs);
    final wphase = _waiting.value * 2 * math.pi;
    // 入場未完成時壓低等待微動，避免和入場位移互相打架。
    final settle = Curves.easeIn.transform(_intro.value.clamp(0.0, 1.0));
    final breath = 0.5 + 0.5 * math.sin(wphase); // 0..1 呼吸相位
    return _CardPose(
      dy: math.sin(wphase) * 3 * settle + 30 * (1 - enter),
      scale: (0.85 + 0.15 * enter) * (1 + 0.010 * breath * settle),
      yaw: -2 * math.sin(wphase) * settle,
      emblem: 0.30 + 0.15 * breath,
    );
  }

  Matrix4 _card3d({required double yaw, double pitch = 0}) => Matrix4.identity()
    ..setEntry(3, 2, 1 / 1200)
    ..rotateX(pitch * math.pi / 180)
    ..rotateY(yaw * math.pi / 180);

  /// 卡片：抽牌中＝銀色卡背入場＋等待呼吸；揭曉後＝蓄力、染色、單次翻牌（側立那一刻
  /// 光刃遮住換面）、正面落定；收卡＝縮小、變成光、淡出（光球接手）。
  Widget _buildCard(Size cardSize) {
    final girl = _revealGirl;
    if (_phase == _CeremonyPhase.drawing || girl == null) {
      final pose = _waitingPose();
      return Opacity(
        opacity: practiceIntroCardOpacity(_introMs),
        child: Transform.translate(
          key: const ValueKey('practice-draw-ceremony-waiting-motion'),
          offset: Offset(0, pose.dy),
          child: Transform.scale(
            scale: pose.scale,
            child: Transform(
              alignment: Alignment.center,
              transform: _card3d(yaw: pose.yaw),
              child: PracticeRevealCardBack(
                width: cardSize.width,
                height: cardSize.height,
                colors: PracticeRevealBackColors.silver,
                emblemGlow: pose.emblem,
                frameGlow: practiceRevealFrameGlow(0),
              ),
            ),
          ),
        ),
      );
    }

    final ms = _revealMs;
    final rarity = girl.rarity;
    final pose = practiceRevealPose(ms);
    final blend = practiceRevealSeg(ms, 0, PracticeRevealTiming.poseBlendMs);
    final archiving = _phase == _CeremonyPhase.archiving;
    final archiveMs = _archiveMs;
    final cardOpacity = archiving ? practiceArchiveCardOpacity(archiveMs) : 1.0;
    if (cardOpacity <= 0.001) return const SizedBox.shrink();
    final collapse = archiving ? practiceArchiveCardScale(archiveMs) : 1.0;
    final dy = lerpDouble(_startPose.dy, 0, blend)!;
    final scale =
        pose.scale * lerpDouble(_startPose.scale, 1, blend)! * collapse;
    final yaw = pose.yaw + _startPose.yaw * (1 - blend);

    final Widget face = practiceRevealShowsFront(ms)
        ? Transform(
            alignment: Alignment.center,
            transform: Matrix4.rotationY(math.pi),
            child: PracticeRevealCardFront(
              girl: girl,
              width: cardSize.width,
              height: cardSize.height,
              state: PracticeRevealFaceState.at(
                ms,
                archiveMs: archiving ? archiveMs : null,
              ),
            ),
          )
        : PracticeRevealCardBack(
            width: cardSize.width,
            height: cardSize.height,
            colors: PracticeRevealBackColors.at(ms, rarity),
            emblemGlow: lerpDouble(
              _startPose.emblem,
              practiceRevealEmblemGlow(ms, rarity),
              blend,
            )!,
            frameGlow: practiceRevealFrameGlow(ms),
            goldFlash: practiceRevealGoldFlash(ms, rarity),
          );

    return Opacity(
      opacity: cardOpacity,
      child: Transform.translate(
        offset: Offset(0, dy),
        child: Transform.scale(
          scale: scale,
          child: Transform(
            key: const ValueKey('practice-draw-ceremony-card-3d'),
            alignment: Alignment.center,
            transform: _card3d(yaw: yaw, pitch: pose.pitch),
            child: face,
          ),
        ),
      ),
    );
  }
}

/// 揭曉「結果卡」的 test/preview seam：免跑整條儀式時間軸即可單獨渲染卡面。
/// [settled]＝揭曉走完停住的樣子（稀有度牌已烙上、亮星全亮）；false＝剛翻開落定。
@visibleForTesting
Widget debugCeremonyCardFront({
  required PracticeGirlProfile girl,
  required double width,
  required double height,
  bool settled = true,
}) =>
    PracticeRevealCardFront(
      girl: girl,
      width: width,
      height: height,
      state: settled
          ? PracticeRevealFaceState.settled
          : PracticeRevealFaceState.at(PracticeRevealTiming.flipEndMs),
    );

/// 卡背的 test/preview seam：讓 still-recorder 與 widget test 免跑整條儀式即可單獨渲染
/// 某個稀有度染色完成後的卡背（N 銀、R 藍、SR 金）。[glow]＝徽記亮度。
@visibleForTesting
Widget debugCeremonyCardBack({
  required double width,
  required double height,
  PracticeGirlRarity rarity = PracticeGirlRarity.n,
  double glow = 0.6,
}) =>
    PracticeRevealCardBack(
      width: width,
      height: height,
      colors:
          PracticeRevealBackColors.at(PracticeRevealTiming.flipStartMs, rarity),
      emblemGlow: glow,
      frameGlow: practiceRevealFrameGlow(PracticeRevealTiming.flipStartMs),
    );

/// 收卡光球的目標格（overlay 本地座標）：widget test 驗「光球飛向剛抽到的那一格」。
/// 沒有目標（原地收束）或不是收卡光球的 painter 都回 null。
@visibleForTesting
Rect? debugArchiveOrbTarget(CustomPainter painter) =>
    painter is PracticeRevealOrbPainter ? painter.target : null;
