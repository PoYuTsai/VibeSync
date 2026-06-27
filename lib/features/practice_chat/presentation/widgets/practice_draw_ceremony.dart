import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../data/providers/practice_chat_providers.dart';
import '../../domain/entities/practice_girl_profile.dart';
import 'practice_draw_sfx.dart';
import 'practice_girl_photo.dart';

/// 翻牌揭曉時間軸（公開供 widget 與 widget test 共用單一真相）。
/// fraction = ms / kPracticeRevealDuration。詳見 _buildStage 兩段升階分支。
// 時間軸對齊參考音軌「音檔.mp4」（E1）：0–0.5s 靜默→卡背登場；~3.0s 第一爆點→預覽
// 卡翻出；~5.0s 近靜音低谷→翻回卡背屏息；~6.5→8.5s 第二段 build＋第二爆點→高潮翻面
// 典藏卡落定。fraction = 絕對秒 / 9.0。
@visibleForTesting
const Duration kPracticeRevealDuration = Duration(milliseconds: 9000);
@visibleForTesting
const double kPracticeRevealFlip1Start = 0.28; // 卡背蓄力（音樂 build）→ 翻面起手（≈2.5s）
@visibleForTesting
const double kPracticeRevealFlip1End = 0.34; // 卡背→白卡預覽翻面落定（≈3.06s 第一爆點）
@visibleForTesting
const double kPracticeRevealPreviewEnd = 0.45; // 白卡停留、資訊浮出（屏息，≈4.05s）
@visibleForTesting
const double kPracticeRevealRechargeEnd = 0.56; // 翻回卡背（蓄力重啟，≈5.04s 低谷）
@visibleForTesting
const double kPracticeRevealHaloClimax = 0.82; // 卡背發亮、光環衝高潮（≈7.38s）
@visibleForTesting
const double kPracticeRevealGrandFlipEnd = 0.90; // 高潮翻面→典藏卡（≈8.1s）
@visibleForTesting
const double kPracticeRevealHoldEnd = 0.94; // 典藏卡落定、settle（≈8.46s 第二爆點）

/// 揭曉卡片尺寸（E1 放大／復刻 音檔.mp4 的近滿版大卡）：寬 ≈ 0.84×螢幕寬、直式 3:4
/// （高 = 寬 × 4/3）。大螢幕（平板）寬封頂 [kPracticeCardMaxWidth]；矮螢幕再被可用
/// 高度夾住，確保 stage＋caption 不溢出。widget 與 widget test 共用單一真相。
@visibleForTesting
const double kPracticeCardWidthFactor = 0.84;
@visibleForTesting
const double kPracticeCardMaxWidth = 360;
@visibleForTesting
const double kPracticeCardHeightRatio = 4 / 3; // 直式 3:4 → 高 = 寬 × 4/3
@visibleForTesting
const double kPracticeCardMaxHeightFactor = 0.6; // 卡高最多佔螢幕高，留白給 caption／光暈

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

  // 揭曉音效 edge-detect：跨白卡預覽翻面／蓄力／高潮門檻各觸發一次的 idempotent 旗標。
  // `_reveal` 是有限 forward-only controller，每幀 tick 比對門檻；旗標確保整條時間軸
  // 只各播一次。`forward(from:0)`（重抽）與 `_toHidden`（收掉 overlay）一律重置。零 Timer。
  // 註：reduce-motion 不跑 `_reveal`，叮聲改在 `_onStateChange` 即時播（見該處）。
  bool _firedChime = false;
  bool _firedRiser = false;
  bool _firedSettle = false;

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

  /// 揭曉時間軸跨「蓄力 riser」「高潮 settle」門檻各觸發一次。只比對門檻、設旗標、
  /// 播一聲——不 setState（`_onTick` 已負責重繪）。跨幅再大（測試一次 pump 跳過門檻）
  /// 也用 `>=` 邊緣判定，故不漏觸發。
  void _onRevealEdge() {
    final v = _reveal.value;
    // 叮聲落在 Stage-1 白卡預覽翻面那一刻（卡面翻出 = 揭曉），而非 server 回應瞬間。
    if (!_firedChime && v >= kPracticeRevealFlip1End) {
      _firedChime = true;
      _sfx.playRevealChime();
    }
    if (!_firedRiser && v >= kPracticeRevealRechargeEnd) {
      _firedRiser = true;
      _sfx.playRiser();
    }
    if (!_firedSettle && v >= kPracticeRevealGrandFlipEnd) {
      _firedSettle = true;
      _sfx.playSettle();
    }
  }

  void _toHidden() {
    if (!mounted) return;
    setState(() {
      _phase = _CeremonyPhase.hidden;
      _revealGirl = null;
    });
    _waiting.stop();
    _sfx.stopWaitingLoop(); // 收掉 overlay（hidden／翻面完成／淡出完成）一律停等待 loop。
    _firedChime = false; // 下次揭曉重新 edge-detect。
    _firedRiser = false;
    _firedSettle = false;
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
        // reduce-motion：跳過 3D 翻面，沒有可對齊的揭曉幀 → 即時播叮聲後收掉 overlay。
        _sfx.playRevealChime();
        _toHidden();
        return;
      }
      setState(() {
        _phase = _CeremonyPhase.revealing;
        _revealGirl = next.girl;
      });
      _waiting.stop(); // 揭曉接管：停掉等待微動，避免與翻面疊動。
      _intro.value = 1;
      // 叮聲改由 `_onRevealEdge` 在白卡預覽翻面（kPracticeRevealFlip1End）觸發，
      // 讓「叮」落在卡面翻出那一刻、而非 server 回應的瞬間。
      _firedChime = false; // 重抽：edge bool 歸零，本輪揭曉重新各觸發一次。
      _firedRiser = false;
      _firedSettle = false;
      _reveal.forward(from: 0);
      return;
    }

    // 失敗兜底（error / locked / 換一位失敗回 revealed 帶錯誤）：淡出，不慶祝。
    if (_phase == _CeremonyPhase.drawing ||
        _phase == _CeremonyPhase.revealing) {
      _waiting.stop(); // 失敗兜底：先停等待微動，兩條淡出路徑都不殘留 repeat。
      _sfx.stopWaitingLoop(); // 失敗兜底（error／402／429）：同步停等待 loop，不播叮聲。
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

    // overlay 整體不透明度：抽牌時跟著卡背浮現；reveal 末段淡出。
    final base = _intro.value;
    double revealFade = 1;
    if (_phase == _CeremonyPhase.revealing) {
      final t = ((_reveal.value - kPracticeRevealHoldEnd) / (1 - kPracticeRevealHoldEnd)).clamp(0.0, 1.0);
      revealFade = 1 - Curves.easeIn.transform(t);
    }
    final overlayOpacity = (base * revealFade).clamp(0.0, 1.0);

    return IgnorePointer(
      ignoring: false,
      child: Opacity(
        opacity: overlayOpacity,
        child: DecoratedBox(
          // 抽牌舞台：中心微透紫光暈、邊緣近黑，像一方聚光的翻牌檯。
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.12),
              radius: 1.1,
              colors: [
                _kStageGlow.withValues(alpha: 0.82),
                Colors.black.withValues(alpha: 0.9),
              ],
              stops: const [0.0, 1.0],
            ),
          ),
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

    if (f < kPracticeRevealFlip1Start) {
      // 卡背蓄力：對齊音樂第一爆點前的 build。卡背持續、金光漸亮，先不翻面。
      angle = 0;
      showFront = false;
      backGlow = 0.6 + 0.25 * seg(0, kPracticeRevealFlip1Start);
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
      frontAppear = Curves.easeOut.transform(seg(kPracticeRevealFlip1End, kPracticeRevealPreviewEnd));
    } else if (f < kPracticeRevealRechargeEnd) {
      // 翻回卡背（蓄力重啟），rotateY π→0。
      final rot = 1 - seg(kPracticeRevealPreviewEnd, kPracticeRevealRechargeEnd);
      angle = rot * math.pi;
      showFront = angle > math.pi / 2;
      frontAppear = 1;
      flashCenter = rot;
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
      frontAppear = Curves.easeOut.transform(seg(kPracticeRevealGrandFlipEnd, kPracticeRevealHoldEnd));
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

    final flash = flashCenter < 0
        ? 0.0
        : math.exp(-math.pow((flashCenter - 0.5) / 0.16, 2).toDouble());

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
        : _CeremonyCardBack(width: cardW, height: cardH, glow: backGlow);

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
          Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(angle),
            child: face,
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
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _StarfieldPainter(
                  twinkle: f,
                  intensity:
                      (haloIntensity * 0.7 + flash * 0.6) * (1 - frontDepart),
                  beam: beamProgress,
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
const Color _kPurpleHi = Color(0xFF3A1E63);
const Color _kPurpleLo = Color(0xFF130A24);
const Color _kStageGlow = Color(0xFF2A1248);
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
  });

  final double width;
  final double height;
  final double glow;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(24);
    return Container(
      key: const ValueKey('practice-draw-ceremony-back'),
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kPurpleHi, _kPurpleLo],
        ),
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: _kGold.withValues(alpha: 0.22 + 0.26 * glow),
            blurRadius: 34,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: AppColors.brandBlush.withValues(alpha: 0.18 * glow),
            blurRadius: 44,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 金色圖騰／光環／角飾（CustomPaint，靜態、隨 glow 微亮）。
          ClipRRect(
            borderRadius: radius,
            child: CustomPaint(painter: _MysticBackPainter(glow: glow)),
          ),
          // 金色雙鑲邊：外細框＋內細框，讓它讀起來是一張「牌」。
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: _kGold.withValues(alpha: 0.85),
                width: 1.6,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(7),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _kGoldDeep.withValues(alpha: 0.55),
                  width: 1,
                ),
              ),
            ),
          ),
          // 中央發光圖騰核心。
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_kGold, _kGoldDeep],
                ),
                boxShadow: [
                  BoxShadow(
                    color: _kGold.withValues(alpha: 0.45 + 0.35 * glow),
                    blurRadius: 26,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Icon(
                Icons.auto_awesome,
                size: 46,
                color: Color(0xFF3A2406),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
class _MysticBackPainter extends CustomPainter {
  _MysticBackPainter({required this.glow});

  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // 中央放射光芒（12 道細金線），象徵「抽出」的能量。
    final rayPaint = Paint()
      ..color = _kGold.withValues(alpha: 0.10 + 0.06 * glow)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    const rays = 12;
    final rayLen = size.height * 0.42;
    for (var i = 0; i < rays; i++) {
      final a = (i / rays) * 2 * math.pi;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        center + dir * 30,
        center + dir * rayLen,
        rayPaint,
      );
    }

    // 雙同心金環。
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = _kGold.withValues(alpha: 0.32 + 0.18 * glow)
      ..strokeWidth = 1.4;
    canvas.drawCircle(center, 58, ringPaint);
    canvas.drawCircle(
      center,
      70,
      ringPaint..color = _kGoldDeep.withValues(alpha: 0.28 + 0.16 * glow),
    );

    // 環上 8 顆星點（rune 感）。
    final dotPaint = Paint()..color = _kGold.withValues(alpha: 0.55);
    for (var i = 0; i < 8; i++) {
      final a = (i / 8) * 2 * math.pi - math.pi / 2;
      final p = center + Offset(math.cos(a), math.sin(a)) * 70;
      canvas.drawCircle(p, 1.8, dotPaint);
    }

    // 四角金飾：小菱形（45°方塊）。
    final cornerPaint = Paint()..color = _kGold.withValues(alpha: 0.7);
    const inset = 20.0;
    final corners = [
      Offset(inset, inset),
      Offset(size.width - inset, inset),
      Offset(inset, size.height - inset),
      Offset(size.width - inset, size.height - inset),
    ];
    for (final c in corners) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(math.pi / 4);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: 6, height: 6),
        cornerPaint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_MysticBackPainter old) => old.glow != glow;
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
  static const List<double> _radiusRatio = [0.52, 0.46, 0.58]; // 相對 shortestSide
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
        Offset(rect.left + 12 + along * (rect.width - 24), rect.bottom - 2 - rise),
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
      old.twinkle != twinkle ||
      old.intensity != intensity ||
      old.beam != beam;
}
