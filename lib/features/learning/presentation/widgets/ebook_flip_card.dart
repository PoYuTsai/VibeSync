// lib/features/learning/presentation/widgets/ebook_flip_card.dart
//
// 翻卡：正面情境／對話，背面機制與修正。
//
// 無障礙與韌性約束：
//   - 點擊或鍵盤 activate 都能翻面（InkWell 已註冊 ActivateIntent）。
//   - Semantics label 明確說「顯示解析／返回情境」，不只依賴視覺。
//   - MediaQuery.disableAnimations（reduced motion）時直接切換，不跑旋轉。
//   - 不使用固定高度：背面比正面長時容器要能長高，不能裁字。
//   - 翻面狀態刻意不持久化。
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/models/ebook_block.dart';

class EbookFlipCard extends StatefulWidget {
  const EbookFlipCard({super.key, required this.block});

  final EbookFlipCardBlock block;

  static const Duration flipDuration = Duration(milliseconds: 320);

  @override
  State<EbookFlipCard> createState() => _EbookFlipCardState();
}

class _EbookFlipCardState extends State<EbookFlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: EbookFlipCard.flipDuration,
  );

  bool _showBack = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _animationsDisabled =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  void _toggle() {
    setState(() => _showBack = !_showBack);
    if (_animationsDisabled) {
      // reduced motion：直接跳到終點，不跑旋轉動畫。
      _controller.value = _showBack ? 1 : 0;
      return;
    }
    if (_showBack) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final semanticsLabel = _showBack
        ? '${widget.block.backTitle}。點兩下返回情境。'
        : '${widget.block.frontTitle}。點兩下顯示解析。';

    return Semantics(
      button: true,
      label: semanticsLabel,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _toggle,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final value = _controller.value;
              // 前半段轉正面、後半段轉背面；背面再翻轉一次避免鏡像文字。
              final angle = value * 3.1415926;
              final showingBack = value >= 0.5;
              final content = showingBack ? _buildBack() : _buildFront();
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.001)
                  ..rotateY(showingBack ? angle - 3.1415926 : angle),
                child: content,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFace({
    required IconData icon,
    required Color accent,
    required String kicker,
    required String title,
    required String body,
    required List<String> points,
    required String hint,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.brandSurface2.withValues(alpha: 0.92),
            AppColors.brandSurface.withValues(alpha: 0.96),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  kicker,
                  style: AppTypography.caption.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: AppTypography.titleSmall.copyWith(
              color: AppColors.onBackgroundPrimary,
              fontWeight: FontWeight.w800,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundSecondary,
              height: 1.5,
            ),
          ),
          if (points.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final point in points)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6, right: 8),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.8),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        point,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.onBackgroundSecondary
                              .withValues(alpha: 0.88),
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.touch_app_outlined,
                  size: 14, color: accent.withValues(alpha: 0.85)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  hint,
                  style: AppTypography.caption.copyWith(
                    color: accent.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFront() => _buildFace(
        icon: Icons.visibility_outlined,
        accent: AppColors.ctaStart,
        kicker: '翻卡 · 情境',
        title: widget.block.frontTitle,
        body: widget.block.frontText,
        points: const <String>[],
        hint: '點一下看解析',
      );

  Widget _buildBack() => _buildFace(
        icon: Icons.lightbulb_outline,
        accent: AppColors.coachAccentBright,
        kicker: '翻卡 · 解析',
        title: widget.block.backTitle,
        body: widget.block.backText,
        points: widget.block.backPoints,
        hint: '點一下返回情境',
      );
}
