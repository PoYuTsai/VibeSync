import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../data/providers/practice_chat_providers.dart';
import '../../domain/entities/practice_girl_profile.dart';
import 'practice_draw_sfx.dart';
import 'practice_girl_photo.dart';

/// 每日翻牌「揭曉儀式」全螢幕 overlay（Batch 4 → Batch 4.5 高還原 polish）。
///
/// 純原生實作（無 lottie/rive/音檔）：抽牌中浮現一張**神秘卡背**（深紫＋金框＋圖騰
/// ＋星光，不顯名字／照片），server 抽中後以 `Transform`(rotateY) 做 3D 翻面，中點
/// 配 flash／金色光環 sweep 揭曉今日對象，短暫停留後整片淡出露出底下 hero。
///
/// 設計鐵則（Batch 4.5 仍嚴守）：
/// - 只靠單一 `drawStatus` 狀態機驅動，**不**新增任何計費／網路行為。
/// - 只有「真的進過 drawing 又成功 reveal 一位新對象」才慶祝；換一位失敗會回到
///   `revealed` 但帶 `errorMessage`，這種情況只做兜底淡出、不翻面慶祝。
/// - **全程零 `repeat()`／零 `Timer`／零 `Future.delayed`**：所有動效（卡背浮現、
///   星光、光環 sweep、flash、翻面、資訊落位、淡出）一律由 [_intro]／[_flip] 兩條
///   **有限** `AnimationController` 的進度推導。這保證 `pumpAndSettle` 必收斂、
///   widget test 不 hang；controller 在 dispose 先收。
/// - reduce-motion（`MediaQuery.disableAnimations`）：跳過 3D 翻面與強動畫，抽牌中
///   定住靜態卡背、reveal 直接收掉 overlay 露出 hero；haptic／音效掛勾仍照觸發。
/// - haptic 走 [HapticFeedback]（抽牌 light、翻開成功 medium）；音效走
///   [PracticeDrawSfx]（目前 no-op stub，未打包音檔）。
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

  // 翻面 → flash 揭曉 → 停留落位 → 整片淡出，全部塞進這一條時間軸（無 Timer）。
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1150),
  );

  _CeremonyPhase _phase = _CeremonyPhase.hidden;
  PracticeGirlProfile? _revealGirl;

  // 翻面時間軸切點（0..1）：
  //   0 → _kRotateEnd        rotateY 0→π 翻面（中點 _kRotateEnd/2 換正面＋flash 峰值）
  //   _kRotateEnd → _kHoldEnd 停留：正面金粉鑲邊發亮、資訊浮出落位
  //   _kHoldEnd → 1          整片淡出露出底下 hero（資訊往 hero 方向沉落）
  static const double _kRotateEnd = 0.5;
  static const double _kHoldEnd = 0.74;

  @override
  void initState() {
    super.initState();
    _intro.addListener(_onTick);
    _flip.addListener(_onTick);
    _flip.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _toHidden();
      }
    });
    _intro.addStatusListener((status) {
      // 失敗兜底淡出（reverse）走完 → 收掉 overlay。
      if (status == AnimationStatus.dismissed &&
          _phase != _CeremonyPhase.hidden &&
          !_flip.isAnimating) {
        _toHidden();
      }
    });
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  void _toHidden() {
    if (!mounted) return;
    setState(() {
      _phase = _CeremonyPhase.hidden;
      _revealGirl = null;
    });
    _flip.value = 0;
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
      PracticeDrawSfx.playWhoosh();
      setState(() {
        _phase = _CeremonyPhase.drawing;
        _revealGirl = null;
      });
      _flip
        ..stop()
        ..value = 0;
      if (_reduceMotion) {
        _intro.value = 1; // 不做淡入動畫，直接定住卡背。
      } else {
        _intro.forward(from: 0);
      }
      return;
    }

    if (!wasDrawing) return; // 以下都只處理「抽牌中 → 結果」的收斂。

    // 抽牌成功揭曉：revealed 且沒有錯誤訊息（換一位失敗會回 revealed 但帶錯誤）。
    final drawSucceeded =
        next.isRevealed && next.errorMessage == null && next.girl != null;
    if (drawSucceeded) {
      // 中觸覺＋叮聲掛勾：放在 reduce-motion 早退前，兩條路徑都有回饋。
      HapticFeedback.mediumImpact();
      PracticeDrawSfx.playRevealChime();
      if (_reduceMotion) {
        // reduce-motion：跳過 3D 翻面，直接收掉 overlay 露出 hero。
        _toHidden();
        return;
      }
      setState(() {
        _phase = _CeremonyPhase.revealing;
        _revealGirl = next.girl;
      });
      _intro.value = 1;
      _flip.forward(from: 0);
      return;
    }

    // 失敗兜底（error / locked / 換一位失敗回 revealed 帶錯誤）：淡出，不慶祝。
    if (_phase == _CeremonyPhase.drawing ||
        _phase == _CeremonyPhase.revealing) {
      _flip
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
    _intro.dispose();
    _flip.dispose();
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
      final t = ((_flip.value - _kHoldEnd) / (1 - _kHoldEnd)).clamp(0.0, 1.0);
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
    final isReveal = _phase == _CeremonyPhase.revealing && _flip.value > 0.05;
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

  // ── 翻牌舞台：卡片 ＋ 星光 ＋ 光環 sweep ＋ flash，全部疊在一個固定尺寸 Stack ──
  static const double _cardW = 214.0;
  static const double _cardH = 292.0;
  static const double _stageW = _cardW + 132;
  static const double _stageH = _cardH + 132;

  Widget _buildStage() {
    // 抽牌中：靜態神秘卡背（reduce-motion 則 intro 已定在 1）＋微放大入場＋入場星光。
    if (_phase == _CeremonyPhase.drawing) {
      final intro = Curves.easeOutBack.transform(_intro.value.clamp(0.0, 1.0));
      final scale = (0.84 + 0.16 * intro).clamp(0.0, 1.06);
      return SizedBox(
        width: _stageW,
        height: _stageH,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 入場星光（隨 intro 浮現，停在靜態，不無限重播）。
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _StarfieldPainter(
                    twinkle: _intro.value,
                    intensity: 0.55 + 0.45 * _intro.value,
                  ),
                ),
              ),
            ),
            Transform.scale(
              scale: scale,
              child: const _CeremonyCardBack(
                width: _cardW,
                height: _cardH,
                glow: 0.6,
              ),
            ),
          ],
        ),
      );
    }

    // 揭曉：rotateY 翻面（0→π），過半才換成正面並反鏡像修正。
    final f = _flip.value;
    final rot = (f / _kRotateEnd).clamp(0.0, 1.0); // 0..1 旋轉進度
    final angle = rot * math.pi;
    final showFront = angle > math.pi / 2;

    // 停留 / 淡出兩段進度，給正面資訊「浮出 → 落位」。
    final hold =
        ((f - _kRotateEnd) / (_kHoldEnd - _kRotateEnd)).clamp(0.0, 1.0);
    final depart = ((f - _kHoldEnd) / (1 - _kHoldEnd)).clamp(0.0, 1.0);

    // flash：在「換正面」那一刻（rot≈0.5）爆一下高斯峰，遮住翻面接縫＝揭曉感。
    final flash = math.exp(-math.pow((rot - 0.5) / 0.16, 2).toDouble());
    // 金色光環 sweep：旋轉期間環繞卡牌一圈，旋轉結束即收。
    final sweep = math.sin(math.pi * rot);

    final Widget faceFront = _CeremonyCardFront(
      girl: _revealGirl,
      width: _cardW,
      height: _cardH,
      appear: hold,
      depart: depart,
    );
    final Widget face = showFront
        ? Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()..rotateY(math.pi),
            child: faceFront,
          )
        : _CeremonyCardBack(
            width: _cardW,
            height: _cardH,
            glow: 0.6 + 0.4 * rot,
          );

    return SizedBox(
      width: _stageW,
      height: _stageH,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 翻面期間的環繞光軌＋外圈金光。
          if (sweep > 0.01)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _SweepGlowPainter(progress: rot, intensity: sweep),
                ),
              ),
            ),
          // 翻動中的卡片（rotateY）。
          Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001) // 透視，讓翻面有立體感
              ..rotateY(angle),
            child: face,
          ),
          // 星光：翻面期間圍繞卡牌閃爍，正面定住後快速退場（不干擾照片）。
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _StarfieldPainter(
                  twinkle: rot,
                  intensity: (sweep * 0.7 + flash * 0.6) * (1 - depart),
                ),
              ),
            ),
          ),
          // 中點揭曉 flash：白金徑向爆光，疊在最上層。
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

/// 翻開後的正面：今日對象照片 ＋ 白／粉系卡框 ＋ 名字 ＋（年齡·城市·職業）。
/// 名字單獨成行、meta 用 `·` 串接，**刻意避開** hero 的「名字，年齡」精確字串，
/// 完整資訊仍由底下 hero 呈現。`appear` 讓資訊浮出、`depart` 讓卡片往 hero 落位。
class _CeremonyCardFront extends StatelessWidget {
  const _CeremonyCardFront({
    required this.girl,
    required this.width,
    required this.height,
    this.appear = 1,
    this.depart = 0,
  });

  final PracticeGirlProfile? girl;
  final double width;
  final double height;
  final double appear;
  final double depart;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(24);
    // 揭曉後資訊「浮出」：自下方 14px 上升到定位。
    final infoRise = (1 - Curves.easeOutCubic.transform(appear)) * 14;
    // 淡出時整張卡微縮＋下沉，像把資訊交棒給底下 hero。
    final departE = Curves.easeIn.transform(depart);

    final card = Container(
      key: const ValueKey('practice-draw-ceremony-front'),
      width: width,
      height: height,
      // 白／粉系卡框（matte）＋金粉外光，讀起來像一張角色牌。
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
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
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (girl != null)
              PracticeGirlPhoto(
                profile: girl!,
                width: width,
                height: height,
                borderRadius: BorderRadius.circular(18),
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
            // 細金內框，呼應卡背的鑲邊語彙。
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _kGold.withValues(alpha: 0.55),
                  width: 1,
                ),
              ),
            ),
            if (girl != null)
              Positioned(
                left: 14,
                right: 14,
                bottom: 14,
                child: Transform.translate(
                  offset: Offset(0, infoRise),
                  child: Opacity(
                    opacity: Curves.easeOut.transform(appear).clamp(0.0, 1.0),
                    child: _FrontInfo(girl: girl!),
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

/// 正面卡的文字資訊塊：名字（大）＋ 年齡·城市·職業（meta 行）。
class _FrontInfo extends StatelessWidget {
  const _FrontInfo({required this.girl});

  final PracticeGirlProfile girl;

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
            color: _kGold.withValues(alpha: 0.95),
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

/// 翻面期間環繞卡牌的金色光環 sweep：一段旋轉的發光弧線 ＋ 外圈柔光環。
/// `progress` 0..1 為旋轉進度（決定弧線起點），`intensity` 控制整體亮度。
class _SweepGlowPainter extends CustomPainter {
  _SweepGlowPainter({required this.progress, required this.intensity});

  final double progress;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide * 0.46;
    final rect = Rect.fromCircle(center: center, radius: r);

    // 外圈柔光環（金）。
    final halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..color = _kGold.withValues(alpha: 0.18 * intensity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(center, r, halo);

    // 旋轉的亮弧（120° 長，跟著 progress 轉一圈）。
    final start = progress * 2 * math.pi - math.pi / 2;
    const sweepAngle = 2.0; // ~115°
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: start,
        endAngle: start + sweepAngle,
        colors: [
          _kGold.withValues(alpha: 0.0),
          _kGold.withValues(alpha: 0.9 * intensity),
          Colors.white.withValues(alpha: 0.95 * intensity),
        ],
        stops: const [0.0, 0.7, 1.0],
        transform: GradientRotation(start),
      ).createShader(rect)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawArc(rect, start, sweepAngle, false, arc);

    // 弧線前緣亮點（領頭的光珠）。
    final headA = start + sweepAngle;
    final head = center + Offset(math.cos(headA), math.sin(headA)) * r;
    canvas.drawCircle(
      head,
      4,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.95 * intensity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }

  @override
  bool shouldRepaint(_SweepGlowPainter old) =>
      old.progress != progress || old.intensity != intensity;
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
class _StarfieldPainter extends CustomPainter {
  _StarfieldPainter({required this.twinkle, required this.intensity});

  final double twinkle;
  final double intensity;

  static const int _count = 22;
  // golden angle，讓佈點均勻不打結。
  static const double _goldenAngle = 2.399963229728653;

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.shortestSide * 0.62;

    for (var i = 0; i < _count; i++) {
      // 佈在 0.42~0.62 半徑的環帶 → 圍繞卡牌、不蓋住中央照片。
      final ring = 0.42 + 0.20 * ((i * 7) % 11) / 11.0;
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
  }

  @override
  bool shouldRepaint(_StarfieldPainter old) =>
      old.twinkle != twinkle || old.intensity != intensity;
}
