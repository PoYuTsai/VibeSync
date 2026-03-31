import 'dart:math' as math;
import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const SplashScreen({super.key, required this.onComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // 光球動畫
  late final AnimationController _orb1Controller;
  late final AnimationController _orb2Controller;
  late final AnimationController _orb3Controller;

  // 主標題入場
  late final AnimationController _titleController;
  late final Animation<double> _titleOpacity;
  late final Animation<double> _titleTranslateY;
  late final Animation<double> _titleScale;
  // Shimmer 掃光
  late final AnimationController _shimmerController;
  late final Animation<double> _shimmerPosition;

  // 副標題入場
  late final AnimationController _subtitleController;
  late final Animation<double> _subtitleOpacity;
  late final Animation<double> _subtitleLetterSpacing;

  // 底部圓點
  late final AnimationController _dotController;
  late final Animation<double> _dotOpacity;
  late final AnimationController _dotPulseController;

  @override
  void initState() {
    super.initState();

    // ── 光球（持續動畫）──
    _orb1Controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat(reverse: true);

    _orb2Controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);

    _orb3Controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat(reverse: true);

    // ── 主標題入場（1.6 秒）──
    _titleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    _titleOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _titleController,
        curve: const Interval(0, 0.6, curve: Curves.easeOut),
      ),
    );

    _titleTranslateY = Tween<double>(begin: 30, end: 0).animate(
      CurvedAnimation(
        parent: _titleController,
        curve: Curves.easeOutCubic,
      ),
    );

    _titleScale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _titleController,
        curve: Curves.easeOutCubic,
      ),
    );

    // ── Shimmer（1 秒，延遲 1.8 秒）──
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _shimmerPosition = Tween<double>(begin: -0.6, end: 1.2).animate(
      CurvedAnimation(
        parent: _shimmerController,
        curve: Curves.easeInOut,
      ),
    );

    // ── 副標題（1.2 秒，延遲 1 秒）──
    _subtitleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _subtitleOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _subtitleController,
        curve: Curves.easeOut,
      ),
    );

    _subtitleLetterSpacing = Tween<double>(begin: 12, end: 6).animate(
      CurvedAnimation(
        parent: _subtitleController,
        curve: Curves.easeOut,
      ),
    );

    // ── 底部圓點（延遲 2 秒出現）──
    _dotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _dotOpacity = Tween<double>(begin: 0, end: 1).animate(_dotController);

    _dotPulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    // 啟動動畫序列
    _startAnimationSequence();
  }

  Future<void> _startAnimationSequence() async {
    // 標題入場
    _titleController.forward();

    // 1 秒後副標題入場
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    _subtitleController.forward();

    // 1.8 秒後 shimmer
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    _shimmerController.forward();

    // 2 秒後底部圓點
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    _dotController.forward();
    _dotPulseController.repeat(reverse: true);

    // 3.5 秒後完成 splash，進入 app
    await Future.delayed(const Duration(milliseconds: 1500));
    if (mounted) {
      widget.onComplete();
    }
  }

  @override
  void dispose() {
    _orb1Controller.dispose();
    _orb2Controller.dispose();
    _orb3Controller.dispose();
    _titleController.dispose();
    _shimmerController.dispose();
    _subtitleController.dispose();
    _dotController.dispose();
    _dotPulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          color: Color(0xFF0A0A0F),
        ),
        child: Stack(
          children: [
            // 底層環境光
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 0.7,
                    colors: [
                      const Color(0xFF783CC8).withValues(alpha: 0.12),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // 浮動光球
            _buildOrb(
              controller: _orb1Controller,
              color: const Color(0xFF8A3CDC).withValues(alpha: 0.35),
              size: 280,
              top: 0.2,
              left: 0.15,
              floatX: 30,
              floatY: -40,
              breatheDuration: 6,
            ),
            _buildOrb(
              controller: _orb2Controller,
              color: const Color(0xFFB450FF).withValues(alpha: 0.3),
              size: 200,
              top: 0.55,
              right: 0.1,
              floatX: -35,
              floatY: 25,
              breatheDuration: 5,
            ),
            _buildOrb(
              controller: _orb3Controller,
              color: const Color(0xFF6428B4).withValues(alpha: 0.25),
              size: 340,
              bottom: 0.1,
              left: 0.35,
              floatX: 25,
              floatY: 35,
              breatheDuration: 7,
            ),

            // 暗角 Vignette
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 0.85,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.6),
                    ],
                    stops: const [0.4, 1.0],
                  ),
                ),
              ),
            ),

            // 主要內容
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 主標題
                  AnimatedBuilder(
                    animation: Listenable.merge([
                      _titleController,
                      _shimmerController,
                    ]),
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, _titleTranslateY.value),
                        child: Transform.scale(
                          scale: _titleScale.value,
                          child: Opacity(
                            opacity: _titleOpacity.value,
                            child: _buildTitle(),
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 16),

                  // 副標題
                  AnimatedBuilder(
                    animation: _subtitleController,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _subtitleOpacity.value,
                        child: Text(
                          '你的AI專屬聊天教練',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.35),
                            letterSpacing: _subtitleLetterSpacing.value,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // 底部載入圓點
            Positioned(
              bottom: 60,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_dotController, _dotPulseController]),
                  builder: (context, child) {
                    final pulseScale = 1.0 + 0.3 * _dotPulseController.value;
                    final pulseGlow = 0.4 + 0.4 * _dotPulseController.value;
                    return Opacity(
                      opacity: _dotOpacity.value,
                      child: Transform.scale(
                        scale: pulseScale,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFA050FF).withValues(alpha: 0.6),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFA050FF).withValues(alpha: pulseGlow * 0.4),
                                blurRadius: 6 + 10 * _dotPulseController.value,
                                spreadRadius: 2 * _dotPulseController.value,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return ShaderMask(
      shaderCallback: (bounds) {
        // Shimmer 效果
        if (_shimmerController.isAnimating || _shimmerController.isCompleted) {
          return LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: const [
              Colors.white,
              Colors.white,
              Color(0x80FFFFFF),
              Colors.white,
              Colors.white,
            ],
            stops: [
              0.0,
              (_shimmerPosition.value - 0.1).clamp(0.0, 1.0),
              _shimmerPosition.value.clamp(0.0, 1.0),
              (_shimmerPosition.value + 0.1).clamp(0.0, 1.0),
              1.0,
            ],
          ).createShader(bounds);
        }
        return const LinearGradient(
          colors: [Colors.white, Colors.white],
        ).createShader(bounds);
      },
      blendMode: BlendMode.modulate,
      child: Text(
        'VibeSync',
        style: TextStyle(
          fontSize: MediaQuery.of(context).size.width * 0.14 < 48
              ? 48
              : (MediaQuery.of(context).size.width * 0.14 > 72
                  ? 72
                  : MediaQuery.of(context).size.width * 0.14),
          fontWeight: FontWeight.w900,
          color: Colors.white,
          shadows: const [
            Shadow(
              color: Color(0xCCA050FF),
              blurRadius: 10,
            ),
            Shadow(
              color: Color(0x998C3CF0),
              blurRadius: 30,
            ),
            Shadow(
              color: Color(0x667828DC),
              blurRadius: 60,
            ),
            Shadow(
              color: Color(0x40641EC8),
              blurRadius: 100,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrb({
    required AnimationController controller,
    required Color color,
    required double size,
    double? top,
    double? bottom,
    double? left,
    double? right,
    required double floatX,
    required double floatY,
    required double breatheDuration,
  }) {
    final screen = MediaQuery.of(context).size;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final progress = math.sin(controller.value * math.pi * 2);
        final breathe = 0.6 + 0.4 * math.sin(controller.value * math.pi * 2 * (9 / breatheDuration));
        final dx = floatX * progress;
        final dy = floatY * progress;
        final scale = 1.0 + 0.08 * progress;

        return Positioned(
          top: top != null ? screen.height * top + dy : null,
          bottom: bottom != null ? screen.height * bottom + dy : null,
          left: left != null ? screen.width * left + dx : null,
          right: right != null ? screen.width * right + dx : null,
          child: Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: breathe,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color,
                      blurRadius: 80,
                      spreadRadius: 40,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
