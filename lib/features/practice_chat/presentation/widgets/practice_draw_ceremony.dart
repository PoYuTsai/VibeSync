import 'dart:math' as math;
import 'dart:ui' show ImageFilter, PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../data/providers/practice_chat_providers.dart';
import '../../domain/entities/practice_girl_profile.dart';
import 'practice_draw_sfx.dart';
import 'practice_girl_photo.dart';

const String _kReferenceCardBackBaseAsset =
    'assets/images/practice/practice_draw_card_back_base.png';
const String _kReferenceCardBackNeonAsset =
    'assets/images/practice/practice_draw_card_back_neon.png';
const String _kReferenceExplosionAsset =
    'assets/images/practice/practice_draw_explosion_reference.webp';

/// 翻牌揭曉時間軸（公開供 widget 與 widget test 共用單一真相）。
/// fraction = ms / kPracticeRevealDuration。詳見 _buildStage 兩段升階分支。
// 第4輪 storyboard 重定時：總長 = 參考片「音檔.mp4」實測 10.000s（720×1280 24fps
// 240 幀）。錨定音軌實測三爆點＋屏息低谷（fraction = 絕對秒 / 10.0）：
//   0.0–0.5s 亮 UI 靜置卡背 → 0.5–1.0 轉暗星空升起 → 1.0–3.0 蓄力 neon 循環
//   → 3.0s **PEAK#1** 卡背立直→白卡預覽翻出 → 3.5–4.75 預覽懸停
//   → 5.0s **屏息**（−77dB 最深谷）預覽收最小 → 5.25–6.0 翻回卡背再蓄力
//   → 6.0–7.25 flip-explosion（6.5s **PEAK#2** 高潮）→ 7.25–8.0 grand 典藏卡
//   → 8.25–8.75 grand 縮、UI 淡回（8.5s **PEAK#3** 落定）→ 8.75–10.0 settle 亮 UI。
@visibleForTesting
const Duration kPracticeRevealDuration = Duration(milliseconds: 10000);
@visibleForTesting
const double kPracticeRevealFlip1Start = 0.30; // 3.0s PEAK#1：卡背立直→翻面起手
@visibleForTesting
const double kPracticeRevealFlip1End = 0.36; // 3.6s：卡背→白卡預覽翻面落定
@visibleForTesting
const double kPracticeRevealPreviewEnd = 0.50; // 5.0s 屏息：預覽收最小、之後翻回卡背
@visibleForTesting
const double kPracticeRevealRechargeEnd = 0.60; // 6.0s：翻回卡背蓄力完成（爆裂起手）
@visibleForTesting
const double kPracticeRevealHaloClimax = 0.65; // 6.5s PEAK#2：軌道光環爆裂高潮
@visibleForTesting
const double kPracticeRevealGrandFlipEnd = 0.725; // 7.25s：高潮翻面→金框典藏卡落定
@visibleForTesting
const double kPracticeRevealHoldEnd = 0.82; // 8.2s：典藏卡停留結束→settle（8.5 落定）

/// 揭曉舞台暗化程度（0＝亮 UI 全透出，1＝全暗聚焦）。隨 reveal 進度起落以復刻參考片
/// 「亮 UI→暗星空→亮 UI」的開收對稱：beat0（0–0.5s）亮 UI＋卡背 → beat1 轉暗 →
/// 中段全暗儀式 → beat9–10（8.2–10s）暗化退回、亮 UI 重現。drawing 等待期＝柔和聚焦。
/// widget 與 widget test 共用單一真相（改暗化曲線不會讓測試落點失準）。
@visibleForTesting
double practiceCeremonyDim({
  required bool drawing,
  required double revealFraction,
}) {
  if (drawing) return 0.45; // 等待 server：柔和聚焦，底下 UI 仍隱約可見。
  final f = revealFraction;
  const open = 0.12; // 開場/收場暗化底（亮 UI 透出的殘留 vignette）
  if (f < 0.05) return open; // beat0：亮 UI 靜置卡背
  if (f < 0.13) return open + (1 - open) * ((f - 0.05) / 0.08); // beat1：轉暗星空
  if (f < kPracticeRevealHoldEnd) return 1.0; // 中段：全暗儀式
  // beat9–10：暗化退回，亮 UI 重現（與 content 末段淡出同步交棒給底下 hero）。
  return (1 - (f - kPracticeRevealHoldEnd) / (1 - kPracticeRevealHoldEnd))
      .clamp(0.0, 1.0);
}

/// 爆裂高潮 burst：在 PEAK#2（[kPracticeRevealHaloClimax]＝6.5s）達峰的窄鐘形脈衝
/// （半寬 ≈ 0.45s），灌進全螢幕 flash／星爆／光環亮度，做出參考片 6.5s「光束 climax」
/// 的爆發感。0..1，遠離 climax 迅速歸零。widget 與 widget test 共用單一真相。
@visibleForTesting
double practiceCeremonyClimaxBurst(double revealFraction) {
  final d = (revealFraction - kPracticeRevealHaloClimax) / 0.045;
  return math.exp(-d * d);
}

@visibleForTesting
double practiceCeremonyIntroTilt(double revealFraction) {
  final t = (revealFraction / kPracticeRevealFlip1Start).clamp(0.0, 1.0);
  if (t <= 0 || t >= 1) return 0;
  return -0.18 * math.sin(math.pi * t);
}

@visibleForTesting
double practiceCeremonySettlePulse(double revealFraction) {
  final d = (revealFraction - 0.85) / 0.045;
  return math.exp(-d * d).clamp(0.0, 1.0);
}

@visibleForTesting
double practiceCeremonyRimIntensity(double revealFraction) {
  final introT = (revealFraction / kPracticeRevealFlip1Start).clamp(0.0, 1.0);
  final intro = revealFraction < kPracticeRevealFlip1Start
      ? Curves.easeOutCubic.transform(introT)
      : 0.0;
  final rechargeT = ((revealFraction - kPracticeRevealRechargeEnd) /
          (kPracticeRevealHaloClimax - kPracticeRevealRechargeEnd))
      .clamp(0.0, 1.0);
  final recharge = revealFraction >= kPracticeRevealRechargeEnd &&
          revealFraction < kPracticeRevealGrandFlipEnd
      ? rechargeT
      : 0.0;
  final settle = practiceCeremonySettlePulse(revealFraction) * 0.85;
  return math.max(intro, math.max(recharge, settle)).clamp(0.0, 1.0);
}

@visibleForTesting
double practiceCeremonyTumbleSpin(double revealFraction) {
  const start = 0.045;
  const end = 0.155;
  if (revealFraction <= start || revealFraction >= end) return 0;
  final t = ((revealFraction - start) / (end - start)).clamp(0.0, 1.0);
  return math.sin(math.pi * t).clamp(0.0, 1.0);
}

@visibleForTesting
double practiceCeremonyParticleBloom(double revealFraction) {
  final d = (revealFraction - 0.20) / 0.115;
  return math.exp(-d * d).clamp(0.0, 1.0);
}

@visibleForTesting
double practiceCeremonyNeonFrameTrace(double revealFraction) {
  final rise = ((revealFraction - 0.075) / 0.055).clamp(0.0, 1.0);
  final fall = (1 - ((revealFraction - 0.34) / 0.16).clamp(0.0, 1.0));
  return Curves.easeOutCubic.transform(rise) * fall;
}

@visibleForTesting
double practiceCeremonyNeonFrameProgress(double revealFraction) {
  return Curves.easeInOutCubic
      .transform(((revealFraction - 0.075) / 0.125).clamp(0.0, 1.0));
}

@visibleForTesting
double practiceCeremonyNeonParticleWall(double revealFraction) {
  final rise = ((revealFraction - 0.145) / 0.055).clamp(0.0, 1.0);
  final fall = (1 - ((revealFraction - 0.34) / 0.14).clamp(0.0, 1.0));
  return practiceCeremonyParticleBloom(revealFraction) *
      Curves.easeOutCubic.transform(rise) *
      fall;
}

@visibleForTesting
double practiceCeremonyFrameParticleFlow(double revealFraction) {
  final rise = ((revealFraction - 0.125) / 0.05).clamp(0.0, 1.0);
  final fall = (1 - ((revealFraction - 0.31) / 0.075).clamp(0.0, 1.0));
  final bloom = practiceCeremonyParticleBloom(revealFraction).clamp(0.0, 1.0);
  return Curves.easeOutCubic.transform(rise) * fall * bloom;
}

@visibleForTesting
double practiceCeremonyVolumetricBurst(double revealFraction) {
  if (revealFraction <= 0.585 || revealFraction >= 0.745) return 0;
  final fadeIn = ((revealFraction - 0.585) / 0.065).clamp(0.0, 1.0);
  final fadeOut = ((0.745 - revealFraction) / 0.095).clamp(0.0, 1.0);
  final envelope = math.min(fadeIn, fadeOut);
  final peak = practiceCeremonyClimaxBurst(revealFraction);
  return (envelope * (0.46 + 0.54 * peak)).clamp(0.0, 1.0);
}

@visibleForTesting
double practiceCeremonyPreviewRecede(double revealFraction) {
  if (revealFraction <= 0.40 || revealFraction >= 0.54) return 0;
  final d = (revealFraction - 0.48) / 0.045;
  return math.exp(-d * d).clamp(0.0, 1.0);
}

@visibleForTesting
double practiceCeremonyGlassWipe(double revealFraction) {
  final d = (revealFraction - 0.825) / 0.042;
  return math.exp(-d * d).clamp(0.0, 1.0);
}

@visibleForTesting
double practiceCeremonyFinalPolish(double revealFraction) {
  final d = (revealFraction - 0.835) / 0.034;
  return math.exp(-d * d).clamp(0.0, 1.0);
}

@visibleForTesting
double practiceCeremonyAfterglow(double revealFraction) {
  final d = (revealFraction - 0.86) / 0.035;
  return math.exp(-d * d).clamp(0.0, 1.0);
}

double _referenceExplosionOpacity(double revealFraction) {
  if (revealFraction <= kPracticeRevealRechargeEnd ||
      revealFraction >= kPracticeRevealGrandFlipEnd) {
    return 0;
  }
  final fadeIn = ((revealFraction - kPracticeRevealRechargeEnd) /
          (kPracticeRevealHaloClimax - kPracticeRevealRechargeEnd))
      .clamp(0.0, 1.0);
  final fadeOut = ((kPracticeRevealGrandFlipEnd - revealFraction) /
          (kPracticeRevealGrandFlipEnd - kPracticeRevealHaloClimax))
      .clamp(0.0, 1.0);
  final envelope = math.min(fadeIn, fadeOut);
  final pulse = 0.44 + 0.56 * practiceCeremonyClimaxBurst(revealFraction);
  return (envelope * pulse).clamp(0.0, 1.0);
}

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

/// 每日翻牌「揭曉儀式」全螢幕 overlay（Batch 4 → 4.5 高還原 → 4.6 等待微動）。
///
/// 純原生實作（無 lottie/rive/音檔）：抽牌中浮現一張**神秘卡背**（深紫＋金框＋圖騰
/// ＋星光，不顯名字／照片），server 抽中後以兩段升階 `Transform`(rotateY) 做 3D 翻面
/// （白卡預覽→收回蓄力→盛大典藏卡），高潮配 flash／**軌道彗星 halo** 揭曉今日對象，
/// 短暫停留後整片淡出露出底下 hero。
///
/// 設計鐵則（Batch 4.6 仍嚴守）：
/// - 只靠單一 `drawStatus` 狀態機驅動，**不**新增任何計費／網路行為。
/// - 只有「真的進過 drawing 又成功 reveal 一位新對象」才慶祝；換一位失敗會回到
///   `revealed` 但帶 `errorMessage`，這種情況只做兜底淡出、不翻面慶祝。
/// - **零 `Timer`／零 `Future.delayed`**：揭曉時間軸（卡背浮現、星光、軌道彗星 halo、
///   flash、翻面、資訊落位、淡出）一律由 [_intro]／[_reveal] 兩條**有限**
///   `AnimationController` 的進度推導。唯一會 `repeat()` 的是 [_waiting]（抽牌等待
///   server 期間的持續微動），且嚴格 gate：只在 drawing 且非 reduce-motion 啟動，
///   reveal／error／hidden／dispose 一律明確 `stop()`。故 `pumpAndSettle` 仍必收斂、
///   widget test 不 hang；三條 controller 都在 dispose 先收。
/// - reduce-motion（`MediaQuery.disableAnimations`）：跳過 3D 翻面與強動畫，抽牌中
///   定住靜態卡背、reveal 直接收掉 overlay 露出 hero；haptic／一次性音效（咻聲、揭曉
///   叮聲）仍照觸發，但**不**啟動等待 shimmer loop（與 `_waiting` 微動同步靜止）。
/// - haptic 走 [HapticFeedback]（抽牌 light、翻開成功 medium）；音效走
///   [PracticeDrawSfx]（由 [practiceDrawSfxProvider] 注入，目前 no-op、未打包音檔）。
///   等待 loop 的播放／停止與 [_waiting] controller 的 repeat／stop 點一一對應：每個
///   離開 drawing 的出口（reveal／error／402／429／hidden／dispose）都 `stopWaitingLoop`，
///   絕不殘留背景音。
///
/// 由 [PracticeChatScreen] 以 `Positioned.fill` 疊在內容最上層；idle 時整片透明且
/// `IgnorePointer`，不攔截底下的點擊。
class PracticeDrawCeremony extends ConsumerStatefulWidget {
  const PracticeDrawCeremony({super.key});

  @override
  ConsumerState<PracticeDrawCeremony> createState() =>
      _PracticeDrawCeremonyState();
}

enum _CeremonyPhase { hidden, drawing, revealing }

class _PracticeDrawCeremonyState extends ConsumerState<PracticeDrawCeremony>
    with TickerProviderStateMixin {
  // 卡背浮現（淡入＋微放大＋入場星光）；失敗時 reverse 當作淡出。
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  // 兩段升階揭曉時間軸（白卡預覽→收回蓄力→盛大典藏卡→淡出），全部塞進這一條
  // forward-only controller（無 Timer/repeat）。退役舊 `_flip`（單段 2400ms）。
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: kPracticeRevealDuration,
  );

  // 抽牌「等待 server 回應」期間的持續蓄力微動（上下浮動＋金光呼吸＋星光閃爍）。
  // 這是**唯一**會 `repeat()` 的 controller，故嚴格 gate：只在真實 drawing 階段且
  // 非 reduce-motion 才啟動，reveal／error／hidden／dispose 一律明確 `stop()`，確保
  // `pumpAndSettle` 不會因無限重播而 hang。一個迴圈 = 一次 sin 週期（首尾相接無跳變）。
  late final AnimationController _waiting = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  // 翻牌音效（咻／等待 loop／揭曉叮）。預設 no-op（未打包音檔），測試以
  // [practiceDrawSfxProvider] override 注入 spy。於 initState 以 `ref.read` 鎖定實例
  // （Provider 無 async／context 依賴，initState read 安全），故 dispose 取用時純欄位
  // 讀取、不再碰 ref。
  late final PracticeDrawSfx _sfx;

  _CeremonyPhase _phase = _CeremonyPhase.hidden;
  PracticeGirlProfile? _revealGirl;

  // 揭曉叮聲 edge-detect：跨白卡預覽翻面門檻觸發一次的 idempotent 旗標。
  // `_reveal` 是有限 forward-only controller，每幀 tick 比對門檻；旗標確保整條時間軸
  // E2/Eric reset：整條配樂 bed（`playRevealBed`）在揭曉起始就起播；舊 chime
  // 不再疊在 master audio 上，避免真機聽感回到上一版。

  @override
  void initState() {
    super.initState();
    _sfx = ref.read(practiceDrawSfxProvider);
    _intro.addListener(_onTick);
    _reveal.addListener(_onTick);
    _reveal.addListener(_onRevealEdge);
    _waiting.addListener(_onTick);
    _reveal.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _toHidden();
      }
    });
    _intro.addStatusListener((status) {
      // 失敗兜底淡出（reverse）走完 → 收掉 overlay。
      if (status == AnimationStatus.dismissed &&
          _phase != _CeremonyPhase.hidden &&
          !_reveal.isAnimating) {
        _toHidden();
      }
    });
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  /// 揭曉時間軸跨白卡預覽翻面門檻觸發一次叮聲。只比對門檻、設旗標、播一聲——不
  /// setState（`_onTick` 已負責重繪）。跨幅再大（測試一次 pump 跳過門檻）也用 `>=`
  /// Kept as a timeline edge hook, but intentionally does not play the old
  /// reveal chime. The reference master audio owns all reveal accents.
  void _onRevealEdge() {}

  void _toHidden() {
    if (!mounted) return;
    setState(() {
      _phase = _CeremonyPhase.hidden;
      _revealGirl = null;
    });
    _waiting.stop();
    _sfx.stopWaitingLoop(); // 收掉 overlay（hidden／翻面完成／淡出完成）一律停等待 loop。
    _sfx.stopRevealBed(); // E2：揭曉結束／收掉 overlay → 配樂 bed 不殘留。
    _reveal.value = 0;
  }

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  /// 監看 `drawStatus` 轉場驅動儀式。只在「曾進入 drawing」後才有反應，避免進房就
  /// 已是 revealed（草稿／續玩還原）誤觸發。
  void _onStateChange(PracticeChatState? prev, PracticeChatState next) {
    final wasDrawing = prev?.isDrawing ?? false;

    // 進入抽牌：浮現神秘卡背，輕觸覺＋咻聲掛勾。
    if (!wasDrawing && next.isDrawing) {
      HapticFeedback.lightImpact();
      _sfx.playWhoosh();
      setState(() {
        _phase = _CeremonyPhase.drawing;
        _revealGirl = null;
      });
      _reveal
        ..stop()
        ..value = 0;
      if (_reduceMotion) {
        _intro.value = 1; // 不做淡入動畫，直接定住卡背。
        _waiting.stop(); // reduce-motion：等待期間靜止，不啟動持續微動。
        _sfx.stopWaitingLoop(); // reduce-motion：不啟動等待 loop（防殘留）。
      } else {
        _intro.forward(from: 0);
        _waiting.repeat(); // 等待 server 期間持續蓄力微動。
        _sfx.playWaitingLoop(); // 與微動同步：等待 server 期間的 shimmer loop。
      }
      return;
    }

    if (!wasDrawing) return; // 以下都只處理「抽牌中 → 結果」的收斂。

    // 抽牌成功揭曉：revealed 且沒有錯誤訊息（換一位失敗會回 revealed 但帶錯誤）。
    final drawSucceeded =
        next.isRevealed && next.errorMessage == null && next.girl != null;
    if (drawSucceeded) {
      // 中觸覺＋即時停等待 loop（兩條路徑都不等翻面跑完，shimmer loop 在揭曉當下就收）。
      HapticFeedback.mediumImpact();
      _sfx.stopWaitingLoop();
      if (_reduceMotion) {
        // reduce-motion：跳過 3D 翻面；不疊舊 chime，避免與 master audio 語意分裂。
        _toHidden();
        return;
      }
      setState(() {
        _phase = _CeremonyPhase.revealing;
        _revealGirl = next.girl;
      });
      _waiting.stop(); // 揭曉接管：停掉等待微動，避免與翻面疊動。
      _intro.value = 1;
      _sfx.playRevealBed(); // E2：揭曉起始播一條與 `_reveal`（~9s）同長同步的配樂 bed。
      _reveal.forward(from: 0);
      return;
    }

    // 失敗兜底（error / locked / 換一位失敗回 revealed 帶錯誤）：淡出，不慶祝。
    if (_phase == _CeremonyPhase.drawing ||
        _phase == _CeremonyPhase.revealing) {
      _waiting.stop(); // 失敗兜底：先停等待微動，兩條淡出路徑都不殘留 repeat。
      _sfx.stopWaitingLoop(); // 失敗兜底（error／402／429）：同步停等待 loop，不播叮聲。
      _sfx.stopRevealBed(); // 失敗兜底：配樂 bed 一律收掉（防殘留）。
      _reveal
        ..stop()
        ..value = 0;
      if (_reduceMotion || _intro.value == 0) {
        _toHidden();
      } else {
        _intro.reverse();
      }
    }
  }

  @override
  void dispose() {
    _sfx.stopWaitingLoop(); // 卸載儀式：確保等待 loop 不在背景殘留。
    _sfx.stopRevealBed(); // 卸載儀式：確保配樂 bed 不在背景殘留。
    _intro.dispose();
    _reveal.dispose();
    _waiting.dispose();
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

    // 卡片／特效內容不透明度：抽牌時跟著卡背浮現；reveal 末段（HoldEnd→1）淡出交棒。
    final base = _intro.value;
    double revealFade = 1;
    final revealing = _phase == _CeremonyPhase.revealing;
    if (revealing) {
      final t = ((_reveal.value - kPracticeRevealHoldEnd) /
              (1 - kPracticeRevealHoldEnd))
          .clamp(0.0, 1.0);
      revealFade = 1 - Curves.easeIn.transform(t);
    }
    final contentOpacity = (base * revealFade).clamp(0.0, 1.0);

    // 暗化背景與卡片**分層**：背景暗化隨 reveal 進度起落（開場/收場亮 UI 透出），
    // 卡片始終在自己的 beat 內全亮，兩者各自有獨立不透明度。復刻參考片亮→暗→亮。
    final dim = practiceCeremonyDim(
      drawing: _phase == _CeremonyPhase.drawing,
      revealFraction: revealing ? _reveal.value : 0,
    );
    final bgOpacity = (dim * base).clamp(0.0, 1.0);

    // PEAK#2（6.5s）全螢幕爆裂 flash：在 stage-confined flash 之外再加一層**滿版**
    // 徑向爆光，做出參考片高潮「光束 climax」鋪滿螢幕的爆發感。reduce-motion 不跑
    // _reveal → burst≈0 → 不渲染（守鐵則）。
    final climaxFlash =
        revealing ? practiceCeremonyClimaxBurst(_reveal.value) : 0.0;
    final referenceExplosion =
        revealing ? _referenceExplosionOpacity(_reveal.value) : 0.0;

    return IgnorePointer(
      ignoring: false,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 暗化舞台背景：中心微透紫光暈、邊緣近黑，像一方聚光的翻牌檯。
          // 開場（beat0）/收場（beat10）暗化低 → 底下亮 UI（practice room）透出。
          IgnorePointer(
            child: Opacity(
              opacity: bgOpacity,
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
          // 卡片＋星光＋光環＋能量邊框＋flash：始終在各自 beat 全亮。
          Opacity(
            opacity: contentOpacity,
            child: Align(
              alignment: const Alignment(0, -0.06),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildStage(),
                  const SizedBox(height: 20),
                  _buildCaption(),
                ],
              ),
            ),
          ),
          if (referenceExplosion > 0.01)
            Positioned.fill(
              key: const ValueKey(
                'practice-draw-ceremony-reference-explosion',
              ),
              child: IgnorePointer(
                child: Opacity(
                  opacity: contentOpacity * referenceExplosion * 0.82,
                  child: Image.asset(
                    _kReferenceExplosionAsset,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.high,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
          // 滿版爆裂 flash（PEAK#2）：疊在最上，金白徑向爆光washes 過整個螢幕。
          if (climaxFlash > 0.02)
            Positioned.fill(
              key: const ValueKey('practice-draw-ceremony-climax-flash'),
              child: IgnorePointer(
                child: Opacity(
                  opacity: contentOpacity,
                  child: CustomPaint(
                    painter: _RevealFlashPainter(intensity: climaxFlash * 0.6),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCaption() {
    final isReveal = _phase == _CeremonyPhase.revealing && _reveal.value > 0.05;
    final text = isReveal ? '今日對象登場' : '正在為你翻牌…';
    return Text(
      key: const ValueKey('practice-draw-ceremony-caption'),
      text,
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

  // ── 翻牌舞台：卡片 ＋ 星光 ＋ 光環 sweep ＋ flash，全部疊在一個 Stack ──
  // 卡周圍留給星光／光環／能量邊框的 padding；stage 寬再夾進螢幕寬，避免大卡溢出。
  static const double _stagePadding = 132;

  Widget _buildStage() {
    final screen = MediaQuery.sizeOf(context);
    final cardSize = practiceCeremonyCardSize(screen);
    final cardW = cardSize.width;
    final cardH = cardSize.height;
    final stageW = math.min(cardW + _stagePadding, screen.width);
    final stageH = cardH + _stagePadding;

    // 抽牌中：神秘卡背＋微放大入場＋（等待 server 期間）持續蓄力微動。
    if (_phase == _CeremonyPhase.drawing) {
      final intro = Curves.easeOutBack.transform(_intro.value.clamp(0.0, 1.0));
      final introScale = (0.84 + 0.16 * intro).clamp(0.0, 1.06);

      // 等待蓄力微動：全由 [_waiting] 的單一 sin 週期推導。reduce-motion／已停時
      // `_waiting.value` 不前進＝靜止（floatDy 恆 0、scale/glow 恆定）。入場未完成
      // 時用 `settle` 壓低幅度，避免和 easeOutBack 的入場彈跳互相打架。
      final w = _waiting.value;
      final wphase = w * 2 * math.pi;
      final settle = Curves.easeIn.transform(_intro.value.clamp(0.0, 1.0));
      final breath = 0.5 + 0.5 * math.sin(wphase); // 0..1 呼吸相位
      final floatDy = math.sin(wphase) * 3.6 * settle; // 上下浮動 ±3.6px
      final breathScale = 1 + 0.013 * breath * settle; // 極克制的呼吸縮放
      final breathGlow = (0.52 + 0.26 * breath).clamp(0.0, 1.0); // 金光呼吸

      return SizedBox(
        width: stageW,
        height: stageH,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 星光：入場由 intro 浮現，之後改由等待相位持續閃爍（reduce-motion 靜止）。
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _StarfieldPainter(
                    twinkle: _intro.value + w,
                    intensity: 0.55 + 0.45 * _intro.value,
                  ),
                ),
              ),
            ),
            Transform.translate(
              key: const ValueKey('practice-draw-ceremony-waiting-motion'),
              offset: Offset(0, floatDy),
              child: Transform.scale(
                scale: introScale * breathScale,
                child: _CeremonyCardBack(
                  width: cardW,
                  height: cardH,
                  glow: breathGlow,
                  rimIntensity: breathGlow,
                  rimProgress: w,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ── 兩段升階揭曉：白卡預覽 → 收回蓄力 → 盛大典藏卡 → 淡出 ──
    final f = _reveal.value;
    double seg(double from, double to) =>
        ((f - from) / (to - from)).clamp(0.0, 1.0);

    double angle; // rotateY 角度
    bool showFront; // 過半才換正面
    double frontAppear = 1; // 正面資訊浮出
    double frontDepart = 0; // 落位下沉
    double backGlow = 0.6; // 卡背金光
    double haloIntensity = 0; // 軌道彗星 halo 強度（只在蓄力→高潮亮）
    double energyIntensity = 0; // 能量邊框強度（只在蓄力 recharge→climax 亮）
    double energyProgress = 0; // 能量彗星沿卡框周長的位置（0..1）
    double beamProgress = 0; // 橫掃光束位置（只在高潮翻面段 0→1 掃一道）
    double flashCenter = -1; // 觸發 flash 的旋轉中點（rot 0..1）；<0 不畫
    double introRoll = 0;
    double cardRoll = 0;
    double cardScale = 1;
    double cardDy = 0;

    if (f < kPracticeRevealFlip1Start) {
      // 卡背蓄力：對齊音樂第一爆點前的 build。卡背持續、金光漸亮，先不翻面。
      final intro = seg(0, kPracticeRevealFlip1Start);
      final introTilt = practiceCeremonyIntroTilt(f);
      final tumble = practiceCeremonyTumbleSpin(f);
      const tumbleStart = 0.045;
      const tumbleEnd = 0.135;
      final tumbleT =
          ((f - tumbleStart) / (tumbleEnd - tumbleStart)).clamp(0.0, 1.0);
      final tumbleTurn = Curves.easeInOutCubic.transform(tumbleT);
      angle = introTilt + tumbleTurn * math.pi * 2;
      introRoll = introTilt * 0.42 + tumble * 0.46;
      showFront = false;
      backGlow = math.max(0.6 + 0.25 * intro, practiceCeremonyRimIntensity(f));
    } else if (f < kPracticeRevealFlip1End) {
      // 第一段：卡背→白卡預覽（rotateY 0→π），落在第一爆點。halo 尚未啟動（留給高潮）。
      final rot = seg(kPracticeRevealFlip1Start, kPracticeRevealFlip1End);
      angle = rot * math.pi;
      showFront = angle > math.pi / 2;
      frontAppear = 0;
      flashCenter = rot;
    } else if (f < kPracticeRevealPreviewEnd) {
      // 白卡停留、資訊浮出（屏息）。
      angle = math.pi;
      showFront = true;
      frontAppear = Curves.easeOut
          .transform(seg(kPracticeRevealFlip1End, kPracticeRevealPreviewEnd));
      final previewT = seg(kPracticeRevealFlip1End, kPracticeRevealPreviewEnd);
      final recede = practiceCeremonyPreviewRecede(f);
      cardScale = 1 - 0.09 * recede;
      cardDy = -18 * recede;
      cardRoll = (-0.04 + 0.07 * previewT) * (0.45 + 0.55 * recede);
    } else if (f < kPracticeRevealRechargeEnd) {
      // 翻回卡背（蓄力重啟），rotateY π→0。
      final rot =
          1 - seg(kPracticeRevealPreviewEnd, kPracticeRevealRechargeEnd);
      angle = rot * math.pi;
      showFront = angle > math.pi / 2;
      frontAppear = 1;
      flashCenter = rot;
      final recede = practiceCeremonyPreviewRecede(f);
      cardScale = 1 - 0.08 * recede;
      cardDy = -16 * recede;
    } else if (f < kPracticeRevealHaloClimax) {
      // 卡背發亮、軌道彗星 halo 衝高潮（Batch B：兩夾層 _OrbitalHaloPainter）。
      final climb = seg(kPracticeRevealRechargeEnd, kPracticeRevealHaloClimax);
      angle = 0;
      showFront = false;
      backGlow = 0.6 + 0.4 * climb;
      haloIntensity = climb;
      energyIntensity = climb; // 能量邊框與 halo 同步在蓄力段灌入卡牌
      energyProgress = climb;
    } else if (f < kPracticeRevealGrandFlipEnd) {
      // 高潮翻面：卡背→典藏卡（Batch A 仍用現有正面，Batch C 換金框）。halo 隨翻面
      // 淡出。
      final rot = seg(kPracticeRevealHaloClimax, kPracticeRevealGrandFlipEnd);
      angle = rot * math.pi;
      showFront = angle > math.pi / 2;
      frontAppear = 0;
      backGlow = 1;
      flashCenter = rot;
      haloIntensity = 1 - rot;
      beamProgress = rot; // 翻面同時一道光束由上而下橫掃
    } else if (f < kPracticeRevealHoldEnd) {
      // 典藏卡停留、資訊落位、光環 settle。
      angle = math.pi;
      showFront = true;
      frontAppear = Curves.easeOut
          .transform(seg(kPracticeRevealGrandFlipEnd, kPracticeRevealHoldEnd));
    } else {
      // 淡出，露出底下 hero。
      angle = math.pi;
      showFront = true;
      frontAppear = 1;
      frontDepart = seg(kPracticeRevealHoldEnd, 1);
    }

    // 軌道彗星繞行進度：蓄力→高潮窗內掃一圈（halo 亮時才用）。
    final haloProgress = ((f - kPracticeRevealRechargeEnd) /
            (kPracticeRevealGrandFlipEnd - kPracticeRevealRechargeEnd))
        .clamp(0.0, 1.0);

    final flipFlash = flashCenter < 0
        ? 0.0
        : math.exp(-math.pow((flashCenter - 0.5) / 0.16, 2).toDouble());
    // 翻面中點的柔 flash 與 PEAK#2 爆裂 burst 取大者：6.5s 高潮一道強閃。
    final climaxBurst = practiceCeremonyClimaxBurst(f);
    final flash = math.max(flipFlash, climaxBurst);
    final settlePulse = practiceCeremonySettlePulse(f) * (1 - frontDepart);
    final particleBloom = practiceCeremonyParticleBloom(f) * (1 - frontDepart);
    final neonTrace = practiceCeremonyNeonFrameTrace(f) * (1 - frontDepart);
    final neonTraceProgress = practiceCeremonyNeonFrameProgress(f);
    final neonParticleWall =
        practiceCeremonyNeonParticleWall(f) * (1 - frontDepart);
    final frameParticleFlow =
        practiceCeremonyFrameParticleFlow(f) * (1 - frontDepart);
    final volumetricBurst =
        practiceCeremonyVolumetricBurst(f) * (1 - frontDepart);
    final glassWipe = practiceCeremonyGlassWipe(f) * (1 - frontDepart);
    final finalPolish = practiceCeremonyFinalPolish(f) * (1 - frontDepart);
    final afterglow = practiceCeremonyAfterglow(f) * (1 - frontDepart);

    // 正面卡升階：高潮翻面前的白卡用 preview，高潮起換金框典藏卡 grand。
    final cardVariant = f < kPracticeRevealHaloClimax
        ? _CeremonyCardVariant.preview
        : _CeremonyCardVariant.grand;

    final Widget face = showFront
        ? Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()..rotateY(math.pi),
            child: _CeremonyCardFront(
              girl: _revealGirl,
              width: cardW,
              height: cardH,
              variant: cardVariant,
              appear: frontAppear,
              depart: frontDepart,
            ),
          )
        : _CeremonyCardBack(
            width: cardW,
            height: cardH,
            glow: backGlow,
            rimIntensity: practiceCeremonyRimIntensity(f),
            rimProgress: f,
          );

    return SizedBox(
      width: stageW,
      height: stageH,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 後半弧 halo（投影 z<0）：畫在卡片**下方**，做繞到卡背的景深。
          if (haloIntensity > 0.01)
            Positioned.fill(
              key: const ValueKey('practice-draw-ceremony-halo-back'),
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _OrbitalHaloPainter(
                    progress: haloProgress,
                    intensity: haloIntensity,
                    half: PracticeHaloHalf.back,
                  ),
                ),
              ),
            ),
          Transform.translate(
            offset: Offset(0, cardDy),
            child: Transform.scale(
              scale: cardScale,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.001)
                  ..rotateZ(introRoll + cardRoll)
                  ..rotateY(angle),
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    face,
                    if (neonTrace > 0.02)
                      SizedBox(
                        key: const ValueKey(
                          'practice-draw-ceremony-neon-trace-frame',
                        ),
                        width: cardW,
                        height: cardH,
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _NeonTraceFramePainter(
                              progress: f,
                              intensity: neonTrace,
                              traceProgress: neonTraceProgress,
                              particleIntensity: neonParticleWall,
                            ),
                          ),
                        ),
                      ),
                    if (frameParticleFlow > 0.03)
                      SizedBox(
                        key: const ValueKey(
                          'practice-draw-ceremony-frame-particle-flow',
                        ),
                        width: cardW,
                        height: cardH,
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _FrameParticleFlowPainter(
                              progress: f,
                              intensity: frameParticleFlow,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (particleBloom > 0.06)
            Positioned.fill(
              key: const ValueKey('practice-draw-ceremony-particle-bloom'),
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _ParticleBloomPainter(
                    progress: f,
                    intensity: particleBloom * 0.22,
                    cardSize: Size(cardW, cardH),
                  ),
                ),
              ),
            ),
          // 能量邊框：蓄力段沿卡框描邊掃動＋底邊噴火花，緊貼卡上方做「能量灌入」感。
          if (energyIntensity > 0.01)
            Positioned.fill(
              key: const ValueKey('practice-draw-ceremony-energy-border'),
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _EnergyBorderPainter(
                    progress: energyProgress,
                    intensity: energyIntensity,
                    cardSize: Size(cardW, cardH),
                  ),
                ),
              ),
            ),
          // 前半弧 halo（投影 z>0）：畫在卡片**上方**，與後半夾出彗星繞行卡片。
          if (haloIntensity > 0.01)
            Positioned.fill(
              key: const ValueKey('practice-draw-ceremony-halo-front'),
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _OrbitalHaloPainter(
                    progress: haloProgress,
                    intensity: haloIntensity,
                    half: PracticeHaloHalf.front,
                  ),
                ),
              ),
            ),
          if (volumetricBurst > 0.02)
            Positioned.fill(
              key: const ValueKey('practice-draw-ceremony-volumetric-burst'),
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _VolumetricBurstPainter(
                    progress: f,
                    intensity: volumetricBurst,
                    cardSize: Size(cardW, cardH),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _StarfieldPainter(
                  twinkle: f,
                  // PEAK#2 burst 額外灌入星爆亮度，做出 6.5s 高潮的爆發。
                  intensity: (particleBloom * 0.55 +
                          haloIntensity * 0.7 +
                          flash * 0.6 +
                          climaxBurst * 0.7) *
                      (1 - frontDepart),
                  beam: beamProgress,
                ),
              ),
            ),
          ),
          if (settlePulse > 0.02)
            Positioned.fill(
              key: const ValueKey('practice-draw-ceremony-settle-pulse'),
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _SettlePulsePainter(
                    progress: f,
                    intensity: settlePulse,
                    cardSize: Size(cardW, cardH),
                  ),
                ),
              ),
            ),
          if (glassWipe > 0.02)
            Positioned.fill(
              key: const ValueKey('practice-draw-ceremony-glass-wipe'),
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _GlassWipePainter(
                    progress: f,
                    intensity: glassWipe,
                    cardSize: Size(cardW, cardH),
                  ),
                ),
              ),
            ),
          if (finalPolish > 0.02)
            Positioned.fill(
              key: const ValueKey('practice-draw-ceremony-final-polish'),
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _FinalPolishPainter(
                    progress: f,
                    intensity: finalPolish,
                    cardSize: Size(cardW, cardH),
                  ),
                ),
              ),
            ),
          if (afterglow > 0.02)
            Positioned.fill(
              key: const ValueKey('practice-draw-ceremony-afterglow'),
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _AfterglowPainter(
                    progress: f,
                    intensity: afterglow,
                    cardSize: Size(cardW, cardH),
                  ),
                ),
              ),
            ),
          if (flash > 0.02)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _RevealFlashPainter(intensity: flash),
                ),
              ),
            ),
        ],
      ),
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
const Color _kCardMatte = Color(0xFFFDF2F6); // 正面卡白／粉系鑲邊
const Color _kTeal = Color(0xFF4FE0C8); // grand 典藏卡 teal accent（Batch C 目檢可退純金）
const Color _kGrandGlass = Color(0xCC0E0A1C); // grand frosted 深色玻璃資訊欄底

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

/// 正面卡兩態（Batch C）：[preview] 第一段白／粉預覽卡（近原樣）、[grand] 第二段
/// 高潮金框典藏卡（金漸層厚框＋frosted 深色玻璃資訊欄＋teal accent）。同照片同欄位。
enum _CeremonyCardVariant { preview, grand }

/// 翻開後的正面：今日對象照片 ＋ 卡框 ＋ 名字 ＋（年齡·城市·職業）。
/// 名字單獨成行、meta 用 `·` 串接，**刻意避開** hero 的「名字，年齡」精確字串，
/// 完整資訊仍由底下 hero 呈現。`appear` 讓資訊浮出、`depart` 讓卡片往 hero 落位。
/// `variant` 控制白卡預覽 vs 金框典藏卡兩態（見 [_CeremonyCardVariant]）。
class _CeremonyCardFront extends StatelessWidget {
  const _CeremonyCardFront({
    required this.girl,
    required this.width,
    required this.height,
    this.variant = _CeremonyCardVariant.preview,
    this.appear = 1,
    this.depart = 0,
  });

  final PracticeGirlProfile? girl;
  final double width;
  final double height;
  final _CeremonyCardVariant variant;
  final double appear;
  final double depart;

  @override
  Widget build(BuildContext context) {
    final isGrand = variant == _CeremonyCardVariant.grand;
    final radius = BorderRadius.circular(24);
    // 揭曉後資訊「浮出」：自下方 14px 上升到定位。
    final infoRise = (1 - Curves.easeOutCubic.transform(appear)) * 14;
    // 淡出時整張卡微縮＋下沉，像把資訊交棒給底下 hero。
    final departE = Curves.easeIn.transform(depart);
    final infoOpacity = Curves.easeOut.transform(appear).clamp(0.0, 1.0);
    final innerRadius = BorderRadius.circular(isGrand ? 20 : 18);

    // 卡框：preview = 白／粉 matte＋金粉外光；grand = 金漸層厚框＋teal 染光，讀起來
    // 像一張盛大的典藏角色牌。
    final BoxDecoration frame = isGrand
        ? BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_kGold, _kGoldDeep, _kGold],
              stops: [0.0, 0.5, 1.0],
            ),
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: _kGold.withValues(alpha: 0.46 + 0.32 * appear),
                blurRadius: 46,
                spreadRadius: 2,
              ),
              BoxShadow(
                color: _kTeal.withValues(alpha: 0.20),
                blurRadius: 34,
                spreadRadius: 1,
              ),
            ],
          )
        : BoxDecoration(
            color: _kCardMatte,
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: _kGold.withValues(alpha: 0.4 + 0.25 * appear),
                blurRadius: 36,
                spreadRadius: 1,
              ),
              BoxShadow(
                color: AppColors.brandBlush.withValues(alpha: 0.22),
                blurRadius: 30,
                spreadRadius: 1,
              ),
            ],
          );

    final card = Container(
      key: const ValueKey('practice-draw-ceremony-front'),
      width: width,
      height: height,
      // padding 即卡框厚度：grand 金框稍薄讓金邊銳利、preview matte 維持原樣。
      padding: EdgeInsets.all(isGrand ? 4 : 6),
      decoration: frame,
      child: ClipRRect(
        borderRadius: innerRadius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (girl != null)
              PracticeGirlPhoto(
                profile: girl!,
                width: width,
                height: height,
                borderRadius: innerRadius,
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
            // 細金內框，呼應卡背的鑲邊語彙（grand 略強）。
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: innerRadius,
                border: Border.all(
                  color: _kGold.withValues(alpha: isGrand ? 0.72 : 0.55),
                  width: isGrand ? 1.4 : 1,
                ),
              ),
            ),
            if (girl != null)
              Positioned(
                left: isGrand ? 12 : 14,
                right: isGrand ? 12 : 14,
                bottom: isGrand ? 12 : 14,
                child: Transform.translate(
                  offset: Offset(0, infoRise),
                  child: Opacity(
                    opacity: infoOpacity,
                    child: isGrand
                        ? _GrandInfoBar(girl: girl!)
                        : _FrontInfo(girl: girl!),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return Transform.translate(
      offset: Offset(0, 10 * departE),
      child: Transform.scale(
        scale: 1 - 0.05 * departE,
        child: card,
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
    return ClipRRect(
      key: const ValueKey('practice-draw-ceremony-grand-info'),
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: _kGrandGlass,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _kTeal.withValues(alpha: 0.42),
              width: 1,
            ),
          ),
          child: _FrontInfo(girl: girl, accent: _kTeal),
        ),
      ),
    );
  }
}

/// 正面卡的文字資訊塊：名字（大）＋ 年齡·城市·職業（meta 行）。
class _FrontInfo extends StatelessWidget {
  const _FrontInfo({required this.girl, this.accent = _kGold});

  final PracticeGirlProfile girl;
  // meta 行的 accent 色：preview 用金、grand 典藏卡用 teal。
  final Color accent;

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
      ],
    );
  }
}

/// 卡背圖騰／光環／角飾畫筆：放射光芒、雙同心金環、四角金飾。靜態（隨 `glow`
/// 微亮），不自體動畫。
/// 測試用 seam：建立 [_MysticBackPainter]（painter 本體 library-private，與其他
/// painter 一致；僅此 seam 對 widget test 暴露具名建構）。
@visibleForTesting
CustomPainter debugMysticBackPainter({required double glow}) =>
    _MysticBackPainter(glow: glow);

/// 卡背整體（背景＋賽博金框＋羅盤紋章）的 test/preview seam：讓 still-recorder 與
/// widget test 免跑整條儀式即可單獨渲染、目檢卡背還原度。
@visibleForTesting
Widget debugCeremonyCardBack({
  required double width,
  required double height,
  double glow = 0.6,
}) =>
    _CeremonyCardBack(width: width, height: height, glow: glow);

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

/// 軌道彗星 halo 的夾層：`back` = 投影深度 z<0 的後半弧（畫在卡片**下方**）；
/// `front` = z>0 的前半弧（畫在卡片**上方**）。兩層夾出彗星繞行卡片的 3D 景深。
@visibleForTesting
enum PracticeHaloHalf { back, front }

/// 測試用 seam：建立 [_OrbitalHaloPainter]（painter 本體 library-private，與其他
/// painter 一致；僅此 seam 對 widget test 暴露具名建構）。
@visibleForTesting
CustomPainter debugOrbitalHaloPainter({
  required double progress,
  required double intensity,
  required PracticeHaloHalf half,
}) =>
    _OrbitalHaloPainter(progress: progress, intensity: intensity, half: half);

/// 高潮段「軌道彗星」halo：[_ringCount] 條繞 X 軸傾斜不同角度 θ 的 3D 圓軌，各帶
/// 一顆彗星 head＋遞減拖尾，沿 φ 繞行（[progress] 0..1 → φ 掃一圈）。3D 取樣點
/// (r·cosφ, r·sinφ·cosθ, r·sinφ·sinθ) 投影成 2D 橢圓，深度 z=r·sinφ·sinθ 決定該點
/// 屬於前半（卡上）或後半（卡下）夾層，並做近大遠小／近亮遠暗的景深縮放。
///
/// **確定性、零 Random**：軌道傾角／半徑／相位偏移全由環 index 查表決定，重建穩定
/// （`shouldRepaint` 只認 progress/intensity/half）。[intensity]<=0 早退不畫。
class _OrbitalHaloPainter extends CustomPainter {
  _OrbitalHaloPainter({
    required this.progress,
    required this.intensity,
    required this.half,
  });

  /// 彗星沿軌道繞行進度（0..1 → φ 掃一圈）。
  final double progress;

  /// 整體強度（0..1；≤0 不畫）。
  final double intensity;

  /// 夾層：後半弧（z<0、卡下）或前半弧（z>0、卡上）。
  final PracticeHaloHalf half;

  static const int _ringCount = 3;
  static const int _trailSteps = 16; // 拖尾取樣點數
  static const double _trailArc = 1.5; // 拖尾掃過的弧長（rad）

  // 各軌參數（確定性查表，index 對應一條軌道）：
  static const List<double> _tilt = [1.12, 0.74, 1.36]; // 繞 X 軸傾角 θ
  static const List<double> _radiusRatio = [
    0.52,
    0.46,
    0.58
  ]; // 相對 shortestSide
  static const List<double> _phaseOffset = [0.0, 2.3, 4.1]; // 彗星起始相位錯開

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final base = size.shortestSide;
    final wantFront = half == PracticeHaloHalf.front;

    for (var ring = 0; ring < _ringCount; ring++) {
      final theta = _tilt[ring];
      final cosT = math.cos(theta);
      final sinT = math.sin(theta);
      final r = base * _radiusRatio[ring];
      final headPhi = progress * 2 * math.pi + _phaseOffset[ring];

      for (var s = 0; s < _trailSteps; s++) {
        final frac = s / _trailSteps; // 0=head → 1=尾端
        final phi = headPhi - frac * _trailArc;

        // 3D → 2D 橢圓投影；z 為朝向觀者的深度。
        final z = r * math.sin(phi) * sinT;
        final isFrontPoint = z >= 0;
        if (isFrontPoint != wantFront) continue; // 只畫本夾層的弧段

        final px = center.dx + r * math.cos(phi);
        final py = center.dy + r * math.sin(phi) * cosT;

        // 景深：近（z 大）→ 大且亮；遠（z 小／負）→ 小且暗。
        final depth = sinT == 0 ? 0.0 : (z / (r * sinT)).clamp(-1.0, 1.0);
        final depthScale = 0.6 + 0.4 * ((depth + 1) / 2); // 0.6..1.0
        final taper = 1 - frac; // 拖尾遞減

        final dotR = (1.3 + 2.9 * taper) * depthScale;
        final alpha = taper * taper * 0.92 * depthScale * intensity;
        if (alpha <= 0.02) continue;

        // head 白熱、拖尾轉金，隨 frac 漸層。
        final color = Color.lerp(Colors.white, _kGold, frac)!
            .withValues(alpha: alpha.clamp(0.0, 1.0));

        // 柔光暈 + 亮核。
        canvas.drawCircle(
          Offset(px, py),
          dotR * 2.0,
          Paint()
            ..color = color.withValues(alpha: (alpha * 0.35).clamp(0.0, 1.0))
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
        canvas.drawCircle(Offset(px, py), dotR, Paint()..color = color);
      }
    }
  }

  @override
  bool shouldRepaint(_OrbitalHaloPainter old) =>
      old.progress != progress ||
      old.intensity != intensity ||
      old.half != half;
}

/// 測試用 seam：建立 [_EnergyBorderPainter]（painter 本體 library-private）。
/// 與 [debugOrbitalHaloPainter] 同手法，讓 widget test 免 harness 純驗 painter。
@visibleForTesting
CustomPainter debugEnergyBorderPainter({
  required double progress,
  required double intensity,
  required Size cardSize,
}) =>
    _EnergyBorderPainter(
        progress: progress, intensity: intensity, cardSize: cardSize);

/// 能量邊框（Batch C）：沿典藏卡矩形描邊掃動的 teal→gold 彗星光 ＋ 底邊
/// golden-angle 確定性火花。只在蓄力段（recharge→halo climax）由 [_buildStage]
/// 點亮，給「能量灌進卡牌」的蓄勢感。確定性：零 Random，火花靠 golden-angle 佈點＋
/// progress 推升相位。
class _EnergyBorderPainter extends CustomPainter {
  _EnergyBorderPainter({
    required this.progress,
    required this.intensity,
    required this.cardSize,
  });

  final double progress; // 0..1 彗星 head 沿周長的位置
  final double intensity; // 0..1 整體強度（蓄力 climb）
  final Size cardSize; // 卡牌尺寸（在 canvas 置中描邊）

  static const double _goldenAngle = 2.399963229728653; // 黃金角（弧度）
  static const int _sparkCount = 14;

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0) return;
    final i = intensity.clamp(0.0, 1.0);

    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: cardSize.width,
      height: cardSize.height,
    );
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(24)));

    // 整圈 teal 底光描邊。
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = _kTeal.withValues(alpha: 0.16 * i)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // 彗星掃動：沿周長取一段亮弧，head 在 progress 處、teal→gold 漸亮（單一 blur
    // Paint 重用，只變色與半徑，控制低階機繪製成本）。
    final comet = Paint()
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    for (final metric in path.computeMetrics()) {
      final len = metric.length;
      final head = (progress % 1.0) * len;
      final tailLen = len * 0.26; // 拖尾占周長比例
      const steps = 16;
      for (var s = 0; s < steps; s++) {
        final frac = s / (steps - 1); // 0=拖尾末端 .. 1=head
        final tan =
            metric.getTangentForOffset((head - tailLen * (1 - frac)) % len);
        if (tan == null) continue;
        comet.color = Color.lerp(_kTeal, _kGold, frac)!
            .withValues(alpha: ((0.10 + 0.55 * frac) * i).clamp(0.0, 1.0));
        canvas.drawCircle(tan.position, 1.6 + 2.6 * frac, comet);
      }
    }

    // 底邊火花：golden-angle 確定性佈點，沿底邊噴起後淡出。
    final spark = Paint()..style = PaintingStyle.fill;
    for (var k = 0; k < _sparkCount; k++) {
      final a = (k * _goldenAngle) % (2 * math.pi);
      final along = math.sin(a) * 0.5 + 0.5; // 0..1 沿底邊位置（確定）
      final phase = ((progress * 1.3) + a / (2 * math.pi)) % 1.0; // 上升相位
      final rise = phase * 26; // 噴起高度
      final fade = 1 - phase; // 越高越淡
      spark.color = Color.lerp(_kGold, _kTeal, along)!
          .withValues(alpha: (0.6 * fade * i).clamp(0.0, 1.0));
      canvas.drawCircle(
        Offset(
            rect.left + 12 + along * (rect.width - 24), rect.bottom - 2 - rise),
        1.2 + 1.4 * fade,
        spark,
      );
    }
  }

  @override
  bool shouldRepaint(_EnergyBorderPainter old) =>
      old.progress != progress ||
      old.intensity != intensity ||
      old.cardSize != cardSize;
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

class _NeonTraceFramePainter extends CustomPainter {
  _NeonTraceFramePainter({
    required this.progress,
    required this.intensity,
    required this.traceProgress,
    required this.particleIntensity,
  });

  final double progress;
  final double intensity;
  final double traceProgress;
  final double particleIntensity;

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0.01) return;

    final rect = (Offset.zero & size).inflate(size.width * 0.022);
    final left = rect.left;
    final right = rect.right;
    final top = rect.top;
    final bottom = rect.bottom;
    final w = rect.width;
    final h = rect.height;
    final corner = size.width * 0.085;
    final midX = rect.center.dx;

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.plus
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.030);
    final core = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.plus;

    void drawTrace(
      Offset a,
      Offset b,
      Color color,
      double start,
      double end, {
      double weight = 1.0,
    }) {
      final local = ((traceProgress - start) / (end - start)).clamp(0.0, 1.0);
      if (local <= 0.0) return;
      final target = Offset.lerp(a, b, Curves.easeOutCubic.transform(local))!;

      glow
        ..strokeWidth = size.width * 0.030 * weight
        ..color = color.withValues(alpha: intensity * 0.48);
      core
        ..strokeWidth = size.width * 0.010 * weight
        ..color = color.withValues(alpha: intensity * 0.9);
      canvas.drawLine(a, target, glow);
      canvas.drawLine(a, target, core);

      final head = Paint()
        ..blendMode = BlendMode.plus
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.018)
        ..color = color.withValues(alpha: intensity * 0.72);
      canvas.drawCircle(target, size.width * 0.016 * weight, head);
    }

    drawTrace(
      Offset(left + corner, top),
      Offset(midX - corner * 0.35, top),
      _kGold,
      0.00,
      0.54,
      weight: 1.05,
    );
    drawTrace(
      Offset(right - corner, top),
      Offset(midX + corner * 0.35, top),
      _kNeonCyan,
      0.04,
      0.66,
      weight: 1.05,
    );
    drawTrace(
      Offset(left, top + corner),
      Offset(left, top + h * 0.40),
      _kGold,
      0.00,
      0.48,
    );
    drawTrace(
      Offset(left, bottom - corner),
      Offset(left, top + h * 0.42),
      _kNeonCyan,
      0.10,
      0.78,
      weight: 1.08,
    );
    drawTrace(
      Offset(right, top + corner),
      Offset(right, top + h * 0.58),
      _kNeonCyan,
      0.02,
      0.62,
      weight: 1.08,
    );
    drawTrace(
      Offset(right, bottom - corner),
      Offset(right, top + h * 0.60),
      _kGold,
      0.14,
      0.82,
    );
    drawTrace(
      Offset(left + corner, bottom),
      Offset(midX - corner * 0.35, bottom),
      _kNeonCyan,
      0.12,
      0.76,
      weight: 1.05,
    );
    drawTrace(
      Offset(right - corner, bottom),
      Offset(midX + corner * 0.35, bottom),
      _kGold,
      0.08,
      0.72,
      weight: 1.05,
    );

    final wall = (particleIntensity * intensity).clamp(0.0, 1.0);
    if (wall <= 0.03) return;

    final sparkGlow = Paint()
      ..blendMode = BlendMode.plus
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.016);
    final sparkDot = Paint()..blendMode = BlendMode.plus;

    void spark(Offset p, Color color, double r, double alpha) {
      final a = alpha.clamp(0.0, 1.0);
      if (a <= 0.01) return;
      sparkGlow.color = color.withValues(alpha: a * 0.40);
      sparkDot.color = color.withValues(alpha: a * 0.88);
      canvas.drawCircle(p, r * 3.3, sparkGlow);
      canvas.drawCircle(p, r, sparkDot);
    }

    for (var i = 0; i < 520; i++) {
      final side = i % 4;
      final u = (i * 0.61803398875 + progress * 0.18) % 1.0;
      final jitterAlong =
          math.sin(i * 1.71 + progress * 31) * size.width * 0.012;
      final jitterOut = math.cos(i * 2.13 + progress * 37) * size.width * 0.030;
      final shimmer = 0.50 + 0.50 * math.sin(i * 1.37 + progress * 49);
      late final Offset p;
      late final Color color;
      switch (side) {
        case 0:
          color = Color.lerp(_kGold, _kNeonCyan, u)!;
          p = Offset(
            left + w * u + jitterAlong,
            top - size.width * 0.026 + jitterOut,
          );
          break;
        case 1:
          color = u < 0.38
              ? Color.lerp(_kGold, Colors.white, u * 0.55)!
              : Color.lerp(_kNeonCyan, Colors.white, (u - 0.38) * 0.22)!;
          p = Offset(
            left - size.width * 0.026 + jitterOut,
            top + h * u + jitterAlong,
          );
          break;
        case 2:
          color = u < 0.58
              ? Color.lerp(_kNeonCyan, Colors.white, u * 0.18)!
              : Color.lerp(_kGold, Colors.white, (u - 0.58) * 0.32)!;
          p = Offset(
            right + size.width * 0.026 + jitterOut,
            top + h * u + jitterAlong,
          );
          break;
        default:
          color = Color.lerp(_kNeonCyan, _kGold, u)!;
          p = Offset(
            left + w * u + jitterAlong,
            bottom + size.width * 0.026 + jitterOut,
          );
          break;
      }
      final r = size.width * (0.0036 + (i % 5) * 0.0011);
      spark(p, color, r, wall * shimmer * (0.72 + 0.36 * traceProgress));
    }
  }

  @override
  bool shouldRepaint(_NeonTraceFramePainter old) =>
      old.progress != progress ||
      old.intensity != intensity ||
      old.traceProgress != traceProgress ||
      old.particleIntensity != particleIntensity;
}

class _FrameParticleFlowPainter extends CustomPainter {
  _FrameParticleFlowPainter({
    required this.progress,
    required this.intensity,
  });

  final double progress;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0.01) return;

    final rect = (Offset.zero & size).inflate(size.width * 0.040);
    final center = rect.center;
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(size.width * 0.095),
    );
    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final len = metric.length;

    final railGlow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.plus
      ..strokeWidth = size.width * 0.017
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.012)
      ..shader = SweepGradient(
        colors: [
          _kGold.withValues(alpha: 0.30 * intensity),
          _kNeonCyan.withValues(alpha: 0.38 * intensity),
          _kGold.withValues(alpha: 0.34 * intensity),
          _kNeonCyan.withValues(alpha: 0.36 * intensity),
          _kGold.withValues(alpha: 0.30 * intensity),
        ],
        stops: const [0.0, 0.24, 0.50, 0.76, 1.0],
        transform: GradientRotation(progress * math.pi * 5.2),
      ).createShader(rect.inflate(size.width * 0.12));
    canvas.drawPath(path, railGlow);

    final railCore = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.plus
      ..strokeWidth = size.width * 0.006
      ..color = Colors.white.withValues(alpha: 0.08 * intensity);
    canvas.drawPath(path, railCore);

    final glow = Paint()
      ..blendMode = BlendMode.plus
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.014);
    final dot = Paint()..blendMode = BlendMode.plus;
    final streak = Paint()
      ..blendMode = BlendMode.plus
      ..strokeCap = StrokeCap.round;

    void spark(Offset p, Offset dir, Color color, double r, double alpha) {
      final a = alpha.clamp(0.0, 1.0);
      if (a <= 0.012) return;
      glow.color = color.withValues(alpha: a * 0.22);
      dot.color = color.withValues(alpha: a * 0.82);
      streak
        ..strokeWidth = r * 0.92
        ..color = color.withValues(alpha: a * 0.24);
      canvas.drawLine(p - dir * (size.width * 0.026), p, streak);
      canvas.drawCircle(p, r * 3.0, glow);
      canvas.drawCircle(p, r, dot);
    }

    for (var i = 0; i < 560; i++) {
      final lane = i % 5;
      final travel = (i * 0.0137 + progress * (1.55 + lane * 0.08)) % 1.0;
      final tangent = metric.getTangentForOffset(travel * len);
      if (tangent == null) continue;
      final outward = tangent.position - center;
      final outLen = outward.distance;
      final normal = outLen == 0 ? Offset.zero : outward / outLen;
      final dir = tangent.vector;
      final jitterOut = (lane - 2) * size.width * 0.014 +
          math.sin(i * 1.43 + progress * 42) * size.width * 0.018;
      final jitterAlong =
          math.cos(i * 2.17 + progress * 37) * size.width * 0.006;
      final p = tangent.position + normal * jitterOut + dir * jitterAlong;

      final xMix = ((p.dx - rect.left) / rect.width).clamp(0.0, 1.0);
      final yMix = ((p.dy - rect.top) / rect.height).clamp(0.0, 1.0);
      final isSideWall =
          xMix < 0.16 || xMix > 0.84 || yMix < 0.15 || yMix > 0.85;
      final sideBoost = isSideWall ? 0.70 : 0.38;
      final colorBias = (0.62 * xMix + 0.38 * (1 - yMix)).clamp(0.0, 1.0);
      final base = Color.lerp(_kGold, _kNeonCyan, colorBias)!;
      final shimmer = 0.46 + 0.54 * math.sin(i * 1.71 + progress * 68);
      final r = size.width * (0.0032 + (i % 7) * 0.00072);
      spark(
        p,
        dir,
        i % 41 == 0 ? Color.lerp(Colors.white, base, 0.65)! : base,
        r,
        intensity * shimmer * sideBoost,
      );
    }

    for (var i = 0; i < 72; i++) {
      final t = (i * 0.027 + progress * 2.4) % 1.0;
      final tangent = metric.getTangentForOffset(t * len);
      if (tangent == null) continue;
      final outward = tangent.position - center;
      final normal =
          outward.distance == 0 ? Offset.zero : outward / outward.distance;
      final pulse = math.exp(-math.pow(((i % 24) / 24 - 0.5) / 0.34, 2));
      final color = i.isEven ? _kGold : _kNeonCyan;
      spark(
        tangent.position + normal * size.width * 0.056,
        tangent.vector,
        color,
        size.width * (0.0048 + 0.0022 * pulse),
        intensity * (0.16 + 0.40 * pulse),
      );
    }
  }

  @override
  bool shouldRepaint(_FrameParticleFlowPainter old) =>
      old.progress != progress || old.intensity != intensity;
}

class _ParticleBloomPainter extends CustomPainter {
  _ParticleBloomPainter({
    required this.progress,
    required this.intensity,
    required this.cardSize,
  });

  final double progress;
  final double intensity;
  final Size cardSize;

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0) return;
    final center = size.center(Offset.zero);
    final cardRect = Rect.fromCenter(
      center: center,
      width: cardSize.width,
      height: cardSize.height,
    );
    final field = cardRect.inflate(cardSize.width * 0.32);
    final glow = Paint()
      ..blendMode = BlendMode.plus
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);
    final dot = Paint()..blendMode = BlendMode.plus;

    void spark(Offset p, Color color, double radius, double alpha) {
      final a = alpha.clamp(0.0, 1.0);
      if (a <= 0.01) return;
      glow.color = color.withValues(alpha: a * 0.72);
      dot.color = color.withValues(alpha: a * 0.92);
      canvas.drawCircle(p, radius * 3.2, glow);
      canvas.drawCircle(p, radius, dot);
    }

    for (var i = 0; i < 280; i++) {
      final side = i % 4;
      final phase = (i * 0.61803398875 + progress * 0.22) % 1.0;
      final shimmer = 0.56 + 0.44 * math.sin(i * 1.73 + progress * 36);
      final radius = 0.58 + (i % 6) * 0.14;
      final jitter =
          math.sin(i * 2.31 + progress * 18) * cardSize.width * 0.075;
      late final Offset p;
      late final Color color;
      var sideWeight = 1.95;
      switch (side) {
        case 0:
          color = Color.lerp(_kGold, Colors.white, (i % 5) / 9)!;
          p = Offset(
              field.left - jitter.abs(), field.top + field.height * phase);
          break;
        case 1:
          color = Color.lerp(_kNeonCyan, Colors.white, (i % 5) / 10)!;
          p = Offset(
              field.right + jitter.abs(), field.top + field.height * phase);
          break;
        case 2:
          color = Color.lerp(_kGold, _kNeonCyan, phase)!;
          sideWeight = 1.42;
          p = Offset(
            field.left +
                field.width * phase +
                math.sin(i * 1.11 + progress * 21) * cardSize.width * 0.045,
            field.top +
                math.cos(i * 1.47 + progress * 29) * cardSize.height * 0.055,
          );
          break;
        default:
          color = Color.lerp(_kGold, _kNeonCyan, 1 - phase)!;
          sideWeight = 1.18;
          p = Offset(
            field.left +
                field.width * phase +
                math.cos(i * 1.23 + progress * 19) * cardSize.width * 0.04,
            field.bottom +
                math.sin(i * 1.63 + progress * 27) * cardSize.height * 0.05,
          );
          break;
      }
      spark(p, color, radius, intensity * shimmer * sideWeight);
    }

    for (var i = 0; i < 96; i++) {
      final angle = i * 2.399963229728653 + progress * 5.2;
      final orbit = 0.60 + (i % 9) * 0.04;
      final p = center +
          Offset(
            math.cos(angle) * cardSize.width * orbit,
            math.sin(angle) * cardSize.height * orbit * 0.56,
          );
      final twinkle = 0.45 + 0.55 * math.sin(angle * 1.4 + progress * 40);
      spark(
        p,
        Color.lerp(Colors.white, _kNeonCyan, (i % 4) / 3)!,
        0.54 + 1.0 * twinkle,
        intensity * twinkle * 0.88,
      );
    }

    for (var i = 0; i < 240; i++) {
      final angle = i * 2.399963229728653 + progress * 2.8;
      final side = math.cos(angle).abs();
      final haloBand = 0.58 + 0.36 * ((i * 7) % 13) / 12;
      final x = center.dx +
          math.cos(angle) * cardSize.width * haloBand +
          math.sin(i * 1.19 + progress * 17) * cardSize.width * 0.08;
      final y = center.dy +
          math.sin(angle) * cardSize.height * (0.42 + 0.22 * side) +
          math.cos(i * 1.73 + progress * 13) * cardSize.height * 0.04;
      final shimmer = 0.45 + 0.55 * math.sin(i * 1.67 + progress * 44);
      final color = i % 11 == 0
          ? Colors.white
          : (math.cos(angle) < 0
              ? Color.lerp(_kGold, Colors.white, (i % 5) / 12)!
              : Color.lerp(_kNeonCyan, Colors.white, (i % 5) / 12)!);
      spark(
        Offset(x, y),
        color,
        0.42 + shimmer * 0.86,
        intensity * shimmer * (0.20 + 0.66 * side),
      );
    }
  }

  @override
  bool shouldRepaint(_ParticleBloomPainter old) =>
      old.progress != progress ||
      old.intensity != intensity ||
      old.cardSize != cardSize;
}

class _VolumetricBurstPainter extends CustomPainter {
  _VolumetricBurstPainter({
    required this.progress,
    required this.intensity,
    required this.cardSize,
  });

  final double progress;
  final double intensity;
  final Size cardSize;

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0.01) return;
    final center = size.center(Offset.zero);
    final rect = Rect.fromCenter(
      center: center,
      width: cardSize.width,
      height: cardSize.height,
    );
    final phase = ((progress - 0.585) / 0.16).clamp(0.0, 1.0);
    final peak = practiceCeremonyClimaxBurst(progress).clamp(0.0, 1.0);
    final i = intensity.clamp(0.0, 1.0);

    final radial = Paint()
      ..blendMode = BlendMode.plus
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.34 * i),
          _kGold.withValues(alpha: 0.26 * i),
          _kNeonCyan.withValues(alpha: 0.16 * i),
          Colors.transparent,
        ],
        stops: const [0.0, 0.24, 0.56, 1.0],
      ).createShader(
        Rect.fromCircle(
          center: center,
          radius: cardSize.width * (0.66 + 0.18 * peak),
        ),
      );
    canvas.drawCircle(center, cardSize.width * (0.72 + 0.24 * peak), radial);

    void beam(double angle, double width, double alpha, Color color) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);
      final beamRect = Rect.fromCenter(
        center: Offset.zero,
        width: cardSize.width * 2.25,
        height: width,
      );
      final paint = Paint()
        ..blendMode = BlendMode.plus
        ..shader = LinearGradient(
          colors: [
            Colors.transparent,
            color.withValues(alpha: 0.18 * alpha * i),
            Colors.white.withValues(alpha: 0.58 * alpha * i),
            color.withValues(alpha: 0.18 * alpha * i),
            Colors.transparent,
          ],
          stops: const [0.0, 0.28, 0.50, 0.72, 1.0],
        ).createShader(beamRect);
      canvas.drawRect(beamRect, paint);
      canvas.restore();
    }

    beam(-0.48 + phase * 0.08, cardSize.width * 0.26, 0.92, _kGold);
    beam(0.34 - phase * 0.06, cardSize.width * 0.21, 0.78, _kNeonCyan);
    beam(math.pi / 2 - 0.16, cardSize.width * 0.12, 0.44, Colors.white);

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.plus
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, cardSize.width * 0.018);
    for (var r = 0; r < 4; r++) {
      final t = (phase + r * 0.18).clamp(0.0, 1.0);
      final oval = Rect.fromCenter(
        center: center,
        width: cardSize.width * (0.86 + r * 0.18 + t * 0.36),
        height: cardSize.height * (0.33 + r * 0.05 + t * 0.08),
      );
      ringPaint
        ..strokeWidth = cardSize.width * (0.006 + r * 0.001)
        ..color = Color.lerp(_kGold, _kNeonCyan, r / 3)!
            .withValues(alpha: i * (0.42 - r * 0.055));
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(-0.40 + r * 0.22 + phase * 0.22);
      canvas.translate(-center.dx, -center.dy);
      canvas.drawArc(oval, -math.pi * 0.04, math.pi * 1.28, false, ringPaint);
      canvas.restore();
    }

    final sparkle = Paint()
      ..blendMode = BlendMode.plus
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.2);
    for (var k = 0; k < 132; k++) {
      final a = k * 2.399963229728653 + phase * 3.8;
      final lane = 0.22 + (k % 11) / 10 * 0.76;
      final spread = cardSize.width * (0.28 + lane * (0.62 + 0.18 * peak));
      final p = center +
          Offset(
            math.cos(a) * spread,
            math.sin(a) * spread * (0.52 + 0.24 * math.sin(a + phase)),
          );
      final tw = 0.45 + 0.55 * math.sin(k * 1.83 + progress * 72);
      final color = k % 7 == 0
          ? Colors.white
          : Color.lerp(_kGold, _kNeonCyan, (k % 9) / 8)!;
      sparkle.color = color.withValues(alpha: i * tw * 0.70);
      canvas.drawCircle(p, 0.9 + 2.4 * tw * i, sparkle);
    }

    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..blendMode = BlendMode.plus
      ..strokeWidth = cardSize.width * 0.010
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, cardSize.width * 0.015)
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          _kGold.withValues(alpha: 0.66 * i),
          Colors.white.withValues(alpha: 0.78 * i),
          _kNeonCyan.withValues(alpha: 0.62 * i),
        ],
      ).createShader(rect.inflate(cardSize.width * 0.08));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.inflate(cardSize.width * 0.030),
        Radius.circular(cardSize.width * 0.088),
      ),
      edge,
    );
  }

  @override
  bool shouldRepaint(_VolumetricBurstPainter old) =>
      old.progress != progress ||
      old.intensity != intensity ||
      old.cardSize != cardSize;
}

class _GlassWipePainter extends CustomPainter {
  _GlassWipePainter({
    required this.progress,
    required this.intensity,
    required this.cardSize,
  });

  final double progress;
  final double intensity;
  final Size cardSize;

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0) return;
    final center = size.center(Offset.zero);
    final rect = Rect.fromCenter(
      center: center,
      width: cardSize.width,
      height: cardSize.height,
    );
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(cardSize.width * 0.075),
    );
    final sweepT = ((progress - 0.765) / 0.15).clamp(0.0, 1.0);

    canvas.save();
    canvas.clipRRect(rrect);

    final veil = Paint()
      ..blendMode = BlendMode.plus
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.00),
          Colors.white.withValues(alpha: 0.10 * intensity),
          _kTeal.withValues(alpha: 0.04 * intensity),
          Colors.white.withValues(alpha: 0.00),
        ],
        stops: const [0.0, 0.42, 0.58, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, veil);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-0.42);
    final sweepX = -cardSize.width * 0.94 + cardSize.width * 1.88 * sweepT;
    final bandRect = Rect.fromCenter(
      center: Offset(sweepX, 0),
      width: cardSize.width * 0.48,
      height: cardSize.height * 1.72,
    );
    final band = Paint()
      ..blendMode = BlendMode.plus
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: 0.16 * intensity),
          Colors.white.withValues(alpha: 0.46 * intensity),
          _kGold.withValues(alpha: 0.14 * intensity),
          Colors.transparent,
        ],
        stops: const [0.0, 0.32, 0.50, 0.68, 1.0],
      ).createShader(bandRect);
    canvas.drawRect(bandRect, band);

    final edge = Paint()
      ..blendMode = BlendMode.plus
      ..color = Colors.white.withValues(alpha: 0.36 * intensity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(sweepX - cardSize.width * 0.13, 0),
        width: 2.2,
        height: cardSize.height * 1.55,
      ),
      edge,
    );
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(sweepX + cardSize.width * 0.15, 0),
        width: 1.4,
        height: cardSize.height * 1.38,
      ),
      edge..color = _kGold.withValues(alpha: 0.36 * intensity),
    );

    final bead = Paint()
      ..blendMode = BlendMode.plus
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    for (var i = 0; i < 18; i++) {
      final y = -cardSize.height * 0.68 +
          cardSize.height * 1.36 * ((i * 0.61803398875 + sweepT) % 1.0);
      final x =
          sweepX + math.sin(i * 1.91 + progress * 26) * cardSize.width * 0.20;
      final shimmer = 0.42 + 0.58 * math.sin(i * 2.2 + progress * 38);
      bead.color = Color.lerp(Colors.white, _kGold, (i % 3) / 2)!
          .withValues(alpha: intensity * shimmer * 0.72);
      canvas.drawCircle(Offset(x, y), 1.2 + shimmer * 1.8, bead);
    }
    canvas.restore();

    final bottomGloss = Paint()
      ..blendMode = BlendMode.plus
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: 0.08 * intensity),
          _kGold.withValues(alpha: 0.05 * intensity),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, bottomGloss);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlassWipePainter old) =>
      old.progress != progress ||
      old.intensity != intensity ||
      old.cardSize != cardSize;
}

class _FinalPolishPainter extends CustomPainter {
  _FinalPolishPainter({
    required this.progress,
    required this.intensity,
    required this.cardSize,
  });

  final double progress;
  final double intensity;
  final Size cardSize;

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0.01) return;
    final center = size.center(Offset.zero);
    final rect = Rect.fromCenter(
      center: center,
      width: cardSize.width,
      height: cardSize.height,
    );
    final radius = Radius.circular(cardSize.width * 0.075);
    final rrect = RRect.fromRectAndRadius(rect, radius);
    final phase = ((progress - 0.785) / 0.105).clamp(0.0, 1.0);
    final i = intensity.clamp(0.0, 1.0);

    canvas.save();
    canvas.clipRRect(rrect);

    final mist = Paint()
      ..blendMode = BlendMode.plus
      ..shader = RadialGradient(
        center: const Alignment(-0.18, -0.36),
        radius: 0.96,
        colors: [
          Colors.white.withValues(alpha: 0.08 * i),
          _kGold.withValues(alpha: 0.05 * i),
          _kNeonCyan.withValues(alpha: 0.03 * i),
          Colors.transparent,
        ],
        stops: const [0.0, 0.28, 0.58, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, mist);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-0.50);
    final sweepX = -cardSize.width * 0.74 + cardSize.width * 1.58 * phase;
    for (var lane = 0; lane < 3; lane++) {
      final offset = (lane - 1) * cardSize.width * 0.105;
      final bandRect = Rect.fromCenter(
        center: Offset(sweepX + offset, 0),
        width: cardSize.width * (0.18 + lane * 0.08),
        height: cardSize.height * 1.66,
      );
      final band = Paint()
        ..blendMode = BlendMode.plus
        ..shader = LinearGradient(
          colors: [
            Colors.transparent,
            Colors.white.withValues(alpha: i * (0.08 + lane * 0.035)),
            (lane == 1 ? Colors.white : _kGold)
                .withValues(alpha: i * (0.22 + lane * 0.05)),
            Colors.white.withValues(alpha: i * (0.08 + lane * 0.03)),
            Colors.transparent,
          ],
          stops: const [0.0, 0.30, 0.50, 0.70, 1.0],
        ).createShader(bandRect);
      canvas.drawRect(bandRect, band);
    }

    final razor = Paint()
      ..blendMode = BlendMode.plus
      ..strokeCap = StrokeCap.round
      ..strokeWidth = cardSize.width * 0.006
      ..color = Colors.white.withValues(alpha: 0.48 * i)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawLine(
      Offset(sweepX - cardSize.width * 0.045, -cardSize.height * 0.76),
      Offset(sweepX + cardSize.width * 0.20, cardSize.height * 0.76),
      razor,
    );
    canvas.restore();

    final bead = Paint()
      ..blendMode = BlendMode.plus
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    for (var k = 0; k < 72; k++) {
      final t = (k * 0.61803398875 + phase * 0.62) % 1.0;
      final edge = k % 4;
      late final Offset p;
      switch (edge) {
        case 0:
          p = Offset(rect.left + rect.width * t, rect.top + 4);
          break;
        case 1:
          p = Offset(rect.right - 4, rect.top + rect.height * t);
          break;
        case 2:
          p = Offset(rect.left + rect.width * t, rect.bottom - 4);
          break;
        default:
          p = Offset(rect.left + 4, rect.top + rect.height * t);
          break;
      }
      final tw = 0.44 + 0.56 * math.sin(k * 1.91 + progress * 80);
      final color = k % 5 == 0
          ? Colors.white
          : Color.lerp(_kGold, _kNeonCyan, (edge + 1) / 5)!;
      bead.color = color.withValues(alpha: i * tw * 0.46);
      canvas.drawCircle(p, 0.9 + 1.8 * tw * i, bead);
    }
    canvas.restore();

    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = cardSize.width * 0.014
      ..blendMode = BlendMode.plus
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, cardSize.width * 0.026)
      ..shader = SweepGradient(
        colors: [
          _kGold.withValues(alpha: 0.12 * i),
          Colors.white.withValues(alpha: 0.54 * i),
          _kNeonCyan.withValues(alpha: 0.34 * i),
          _kGold.withValues(alpha: 0.36 * i),
          _kGold.withValues(alpha: 0.12 * i),
        ],
        stops: const [0.0, 0.30, 0.50, 0.76, 1.0],
        transform: GradientRotation(-math.pi * 0.24 + phase * math.pi * 0.55),
      ).createShader(rect.inflate(cardSize.width * 0.12));
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.inflate(cardSize.width * 0.022), radius),
      rim,
    );

    final star = Paint()
      ..blendMode = BlendMode.plus
      ..strokeCap = StrokeCap.round
      ..strokeWidth = cardSize.width * 0.006
      ..color = Colors.white.withValues(alpha: 0.54 * i)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final starP = rect.topLeft +
        Offset(cardSize.width * (0.22 + 0.46 * phase), cardSize.height * 0.18);
    canvas.drawLine(
      starP - Offset(cardSize.width * 0.065, 0),
      starP + Offset(cardSize.width * 0.065, 0),
      star,
    );
    canvas.drawLine(
      starP - Offset(0, cardSize.width * 0.065),
      starP + Offset(0, cardSize.width * 0.065),
      star,
    );
  }

  @override
  bool shouldRepaint(_FinalPolishPainter old) =>
      old.progress != progress ||
      old.intensity != intensity ||
      old.cardSize != cardSize;
}

class _AfterglowPainter extends CustomPainter {
  _AfterglowPainter({
    required this.progress,
    required this.intensity,
    required this.cardSize,
  });

  final double progress;
  final double intensity;
  final Size cardSize;

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0) return;
    final center = size.center(Offset.zero);
    final rect = Rect.fromCenter(
      center: center,
      width: cardSize.width,
      height: cardSize.height,
    );
    final rrect = RRect.fromRectAndRadius(
      rect.inflate(cardSize.width * 0.035),
      Radius.circular(cardSize.width * 0.09),
    );
    final phase = ((progress - 0.80) / 0.12).clamp(0.0, 1.0);

    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = cardSize.width * (0.01 + 0.01 * intensity)
      ..blendMode = BlendMode.plus
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, cardSize.width * 0.025)
      ..shader = SweepGradient(
        startAngle: -math.pi * 0.65,
        endAngle: math.pi * 1.35,
        colors: [
          _kGold.withValues(alpha: 0),
          _kGold.withValues(alpha: 0.54 * intensity),
          Colors.white.withValues(alpha: 0.70 * intensity),
          _kTeal.withValues(alpha: 0.44 * intensity),
          _kGold.withValues(alpha: 0),
        ],
        stops: const [0.0, 0.24, 0.42, 0.63, 1.0],
        transform: GradientRotation(progress * math.pi * 2.2),
      ).createShader(rect.inflate(cardSize.width * 0.2));
    canvas.drawRRect(rrect, rim);

    final membrane = Paint()
      ..blendMode = BlendMode.plus
      ..shader = RadialGradient(
        center: const Alignment(0.18, -0.28),
        radius: 0.78,
        colors: [
          Colors.white.withValues(alpha: 0.18 * intensity),
          _kGold.withValues(alpha: 0.07 * intensity),
          Colors.transparent,
        ],
        stops: const [0.0, 0.42, 1.0],
      ).createShader(rect);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(
      rect,
      Radius.circular(cardSize.width * 0.075),
    ));
    canvas.drawRect(rect, membrane);
    canvas.restore();

    final spark = Paint()
      ..blendMode = BlendMode.plus
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    for (var i = 0; i < 52; i++) {
      final lane = (i % 5) / 4;
      final fall = (phase + i * 0.071) % 1.0;
      final x = rect.left +
          cardSize.width * (0.04 + 0.92 * ((i * 0.61803398875) % 1.0)) +
          math.sin(i * 1.37 + progress * 28) * cardSize.width * 0.035;
      final y =
          rect.top - cardSize.height * 0.10 + cardSize.height * 1.18 * fall;
      final edgeBoost = (lane == 0 || lane == 1) ? 1.0 : 0.58;
      final twinkle = 0.42 + 0.58 * math.sin(i * 2.03 + progress * 42);
      final color = Color.lerp(_kGold, _kNeonCyan, lane)!;
      spark.color = color.withValues(
        alpha: intensity * twinkle * edgeBoost * (1 - 0.45 * phase),
      );
      canvas.drawCircle(
        Offset(x, y),
        0.9 + 1.9 * twinkle * intensity,
        spark,
      );
    }

    final flare = Paint()
      ..blendMode = BlendMode.plus
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7)
      ..color = Colors.white.withValues(alpha: 0.20 * intensity);
    for (var i = 0; i < 5; i++) {
      final a = -math.pi * 0.72 + i * math.pi * 0.36 + progress * 0.7;
      final p = center +
          Offset(
            math.cos(a) * cardSize.width * 0.62,
            math.sin(a) * cardSize.height * 0.42,
          );
      canvas.drawCircle(p, cardSize.width * (0.014 + i * 0.002), flare);
    }
  }

  @override
  bool shouldRepaint(_AfterglowPainter old) =>
      old.progress != progress ||
      old.intensity != intensity ||
      old.cardSize != cardSize;
}

class _SettlePulsePainter extends CustomPainter {
  _SettlePulsePainter({
    required this.progress,
    required this.intensity,
    required this.cardSize,
  });

  final double progress;
  final double intensity;
  final Size cardSize;

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0) return;
    final center = size.center(Offset.zero);
    final rect = Rect.fromCenter(
      center: center,
      width: cardSize.width,
      height: cardSize.height,
    );
    final phase =
        ((progress - kPracticeRevealHoldEnd) / (1 - kPracticeRevealHoldEnd))
            .clamp(0.0, 1.0);
    final inflate = 8 + 18 * Curves.easeOutCubic.transform(phase);
    final rrect = RRect.fromRectAndRadius(
      rect.inflate(inflate),
      Radius.circular(cardSize.width * 0.09),
    );

    final halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = cardSize.width * (0.018 + 0.008 * phase)
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          _kGold.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.52 * intensity),
          _kTeal.withValues(alpha: 0.46 * intensity),
          _kGold.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.42, 0.68, 1.0],
      ).createShader(rect.inflate(36))
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, cardSize.width * 0.035);
    canvas.drawRRect(rrect, halo);

    final core = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = cardSize.width * 0.006
      ..color = Colors.white.withValues(alpha: 0.42 * intensity)
      ..strokeCap = StrokeCap.round;
    canvas.drawRRect(rrect.deflate(cardSize.width * 0.012), core);

    final spark = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 24; i++) {
      final a = i * 2.399963229728653 + phase * math.pi * 1.7;
      final side = i.isEven ? 1.0 : -1.0;
      final rx = cardSize.width * (0.52 + 0.10 * phase);
      final ry = cardSize.height * (0.52 + 0.06 * phase);
      final pos = center +
          Offset(math.cos(a) * rx, math.sin(a) * ry * 0.58 + side * 10);
      final twinkle = 0.55 + 0.45 * math.sin(a * 1.7 + progress * 24);
      spark.color = Color.lerp(_kGold, _kTeal, i / 24)!
          .withValues(alpha: intensity * twinkle * 0.76);
      canvas.drawCircle(pos, 1.2 + 1.8 * twinkle * intensity, spark);
    }
  }

  @override
  bool shouldRepaint(_SettlePulsePainter old) =>
      old.progress != progress ||
      old.intensity != intensity ||
      old.cardSize != cardSize;
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
