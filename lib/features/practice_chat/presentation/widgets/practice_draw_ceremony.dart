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

/// 每日翻牌「揭曉儀式」全螢幕 overlay（Batch 4 commit 2）。
///
/// 純原生實作（無 lottie/rive/音檔）：抽牌中浮現一張**神秘卡背**（不顯名字／不
/// 顯照片，因為 locked 階段本就還不知道是誰），server 抽中後以 `Transform`
/// (rotateY) 做 3D 翻面把卡翻成今日對象，短暫停留後整片淡出露出底下 hero。
///
/// 設計鐵則：
/// - 只靠單一 `drawStatus` 狀態機驅動，**不**新增任何計費／網路行為。
/// - 只有「真的進過 drawing 又成功 reveal 一位新對象」才慶祝；換一位失敗會回到
///   `revealed` 但帶 `errorMessage`，這種情況只做兜底淡出、不翻面慶祝。
/// - reduce-motion（`MediaQuery.disableAnimations`）：跳過 3D 翻面，reveal 直接
///   讓 overlay 收掉、露出 hero；但 haptic／音效掛勾仍照觸發（屬觸覺回饋非動畫）。
/// - haptic 走 [HapticFeedback]（抽牌 light、翻開成功 medium）；音效走
///   [PracticeDrawSfx]（目前 no-op stub，未打包音檔）。
/// - 全程用 `AnimationController`（ticker）驅動，**不**用 `Timer`/`Future.delayed`，
///   避免測試殘留 pending timer；controller 在 dispose 先收。
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
  // 卡背浮現（淡入＋微放大）；失敗時 reverse 當作淡出。
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  // 翻面 → 停留 → 整片淡出，全部塞進這一條時間軸（無 Timer）。
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 860),
  );

  _CeremonyPhase _phase = _CeremonyPhase.hidden;
  PracticeGirlProfile? _revealGirl;

  // 翻面時間軸切點：0→_kRotateEnd 完成 0→π 翻面；停留到 _kHoldEnd；之後整片淡出。
  static const double _kRotateEnd = 0.6;
  static const double _kHoldEnd = 0.78;

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
        child: Container(
          color: Colors.black.withValues(alpha: 0.78),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildCard(),
              const SizedBox(height: 22),
              _buildCaption(),
            ],
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
        color: Colors.white.withValues(alpha: 0.92),
        fontWeight: FontWeight.w700,
        shadows: [
          Shadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 8),
        ],
      ),
    );
  }

  Widget _buildCard() {
    const cardW = 212.0;
    const cardH = 286.0;

    // 抽牌中：靜態卡背（reduce-motion 則 intro 已定在 1）＋微放大入場。
    if (_phase == _CeremonyPhase.drawing) {
      final scale = 0.86 + 0.14 * Curves.easeOutBack.transform(_intro.value);
      return Transform.scale(
        scale: scale.clamp(0.0, 1.08),
        child: const _CeremonyCardBack(width: cardW, height: cardH),
      );
    }

    // 揭曉：rotateY 翻面（0→π），過半才換成正面並反鏡像修正。
    final angle = (_flip.value / _kRotateEnd).clamp(0.0, 1.0) * math.pi;
    final showFront = angle > math.pi / 2;
    final Widget face = showFront
        ? Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()..rotateY(math.pi),
            child: _CeremonyCardFront(
              girl: _revealGirl,
              width: cardW,
              height: cardH,
            ),
          )
        : const _CeremonyCardBack(width: cardW, height: cardH);

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.001) // 透視，讓翻面有立體感
        ..rotateY(angle),
      child: face,
    );
  }
}

/// 神秘卡背：品牌漸層＋光暈邊框＋中央 sparkle，刻意不顯任何身份線索。
class _CeremonyCardBack extends StatelessWidget {
  const _CeremonyCardBack({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('practice-draw-ceremony-back'),
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.brandSurface2, AppColors.brandInk],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.ctaStart.withValues(alpha: 0.7),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.ctaStart.withValues(alpha: 0.38),
            blurRadius: 30,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                AppColors.ctaStart.withValues(alpha: 0.9),
                AppColors.ctaEnd.withValues(alpha: 0.9),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.ctaStart.withValues(alpha: 0.5),
                blurRadius: 22,
              ),
            ],
          ),
          child: const Icon(
            Icons.auto_awesome,
            size: 44,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// 翻開後的正面：今日對象照片＋名字（只放名字，不放「名字，年齡」，避免與 hero
/// 文案精確字串相撞；完整資訊由底下 hero 呈現）。
class _CeremonyCardFront extends StatelessWidget {
  const _CeremonyCardFront({
    required this.girl,
    required this.width,
    required this.height,
  });

  final PracticeGirlProfile? girl;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(22);
    return Container(
      key: const ValueKey('practice-draw-ceremony-front'),
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: AppColors.ctaStart.withValues(alpha: 0.85),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.ctaStart.withValues(alpha: 0.45),
            blurRadius: 34,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (girl != null)
              PracticeGirlPhoto(
                profile: girl!,
                width: width,
                height: height,
                borderRadius: radius,
              )
            else
              const ColoredBox(color: AppColors.brandSurface2),
            // 底部漸層 scrim 讓名字可讀。
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.5, 1.0],
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.72),
                  ],
                ),
              ),
            ),
            if (girl != null)
              Positioned(
                left: 14,
                right: 14,
                bottom: 14,
                child: Text(
                  girl!.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.titleMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
