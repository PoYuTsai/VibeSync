import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../partner/domain/entities/partner.dart';

/// 報告頁底部「對象作戰板」dock（2026-08-14 對標夥伴示意稿）。
///
/// 每個對象一張玻璃卡：方形漸層圖示（名字首字）＋名字＋階段＋色點。
/// 手指按住在列上左右滑，靠近手指的卡會像 macOS Dock 一樣放大，
/// 焦點換到另一張卡時給一下 selection 震動；放開全部回彈。
/// 系統關閉動畫（disableAnimations）時不放大，只保留點擊。
///
/// 純資料 widget（partners + stageLabelOf + onTapPartner），不碰 provider，
/// 測試零 stub。
class PartnerMindMapCardList extends StatefulWidget {
  final List<Partner> partners;
  final String? Function(String partnerId) stageLabelOf;
  final ValueChanged<String> onTapPartner;

  const PartnerMindMapCardList({
    super.key,
    required this.partners,
    required this.stageLabelOf,
    required this.onTapPartner,
  });

  @override
  State<PartnerMindMapCardList> createState() => _PartnerMindMapCardListState();
}

class _PartnerMindMapCardListState extends State<PartnerMindMapCardList> {
  static const _tileWidth = 88.0;
  static const _tileGap = 12.0;
  static const _cardHeight = 132.0;
  // 放大最多 22%，向上長；列高留足空間讓放大不被裁掉。
  static const _maxBoost = 0.22;
  // 外層霧面托盤的內距；卡片坐在托盤裡，放大時往上凸出托盤。
  static const _trayPadding = 12.0;
  static const _dockHeight = _cardHeight * (1 + _maxBoost) + _trayPadding + 16;
  // 距手指多遠內受影響（px）
  static const _influence = 120.0;

  // 圖示磚漸層＝對象識別色（下方色點同色），依對象 id 定色。
  // 色值取自夥伴示意稿（2026-08-15 Eric 拍板），色票本體在 AppColors。
  static const _tileGradients = [
    [AppColors.partnerRoseStart, AppColors.partnerRoseEnd], // 霧玫瑰
    [AppColors.partnerGoldStart, AppColors.partnerGoldEnd], // 古銅金
    [AppColors.partnerOrangeStart, AppColors.partnerOrangeEnd], // 鮮橘
    [AppColors.partnerOrchidStart, AppColors.partnerOrchidEnd], // 蘭花粉
  ];

  final _scrollController = ScrollController();
  final _dockKey = GlobalKey();

  /// 手指目前在 dock 內容座標系的 x；null = 沒按著。
  /// ValueNotifier 而非 setState：指針最高 120 次/秒，只有受影響 tile 的
  /// 縮放/亮度該重繪，整個 dock（含 ListView）不該每次重建。
  final _pointerContentX = ValueNotifier<double?>(null);

  /// 只做 haptic edge-detect，不影響 UI，不進 setState。
  int? _focusedIndex;

  @override
  void dispose() {
    _pointerContentX.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  double _tileCenterX(int index) =>
      _trayPadding + index * (_tileWidth + _tileGap) + _tileWidth / 2;

  void _updatePointer(Offset globalPosition) {
    final box = _dockKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(globalPosition);
    final contentX = local.dx + _scrollController.offset;

    int? nearest;
    double nearestDistance = _influence;
    for (var i = 0; i < widget.partners.length; i++) {
      final d = (contentX - _tileCenterX(i)).abs();
      if (d < nearestDistance) {
        nearestDistance = d;
        nearest = i;
      }
    }
    if (nearest != null && nearest != _focusedIndex) {
      HapticFeedback.selectionClick();
    }
    _focusedIndex = nearest;
    _pointerContentX.value = contentX;
  }

  void _clearPointer() {
    _focusedIndex = null;
    _pointerContentX.value = null;
  }

  double _scaleFor(double? pointerX, int index) {
    if (pointerX == null) return 1.0;
    final d = (pointerX - _tileCenterX(index)).abs();
    if (d >= _influence) return 1.0;
    // 餘弦衰減：手指正下方最大，邊緣平滑歸零
    return 1.0 + _maxBoost * (0.5 + 0.5 * math.cos(math.pi * d / _influence));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.partners.isEmpty) return const SizedBox.shrink();
    final magnifyEnabled = !MediaQuery.of(context).disableAnimations;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '對象作戰板',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.ctaStart,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '每個對象的下一步，一張圖看懂',
          style: AppTypography.titleMedium
              .copyWith(color: AppColors.onBackgroundPrimary),
        ),
        const SizedBox(height: 12),
        Listener(
          onPointerDown:
              magnifyEnabled ? (e) => _updatePointer(e.position) : null,
          onPointerMove:
              magnifyEnabled ? (e) => _updatePointer(e.position) : null,
          onPointerUp: magnifyEnabled ? (_) => _clearPointer() : null,
          onPointerCancel: magnifyEnabled ? (_) => _clearPointer() : null,
          child: SizedBox(
            key: _dockKey,
            height: _dockHeight,
            // 對標示意稿的「雙重玻璃」：底層一個大霧面托盤包整排，
            // 每張卡自己再一層更淡的玻璃；放大的卡往上凸出托盤。
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: _cardHeight + _trayPadding * 2,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                ),
                ListView.separated(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(
                    left: _trayPadding,
                    right: _trayPadding,
                    bottom: _trayPadding,
                  ),
                  itemCount: widget.partners.length,
                  separatorBuilder: (_, __) => const SizedBox(width: _tileGap),
                  // 指針動時只有這層 builder 重跑；tile 內容（圖示/文字）走
                  // child passthrough，不隨指針重建。
                  itemBuilder: (context, index) =>
                      ValueListenableBuilder<double?>(
                    valueListenable: _pointerContentX,
                    child: _buildTileContent(index),
                    builder: (context, pointerX, tileContent) {
                      final scale = _scaleFor(pointerX, index);
                      final focus = ((scale - 1.0) / _maxBoost).clamp(0.0, 1.0);
                      return Align(
                        alignment: Alignment.bottomCenter,
                        child: AnimatedScale(
                          scale: scale,
                          duration: const Duration(milliseconds: 120),
                          curve: Curves.easeOut,
                          alignment: Alignment.bottomCenter,
                          child: _buildTileShell(index, focus, tileContent!),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 隨指針變的外殼：玻璃亮度吃 focus（0～1，被 dock 放大的程度）。
  Widget _buildTileShell(int index, double focus, Widget content) {
    final partner = widget.partners[index];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onTapPartner(partner.id),
      child: Container(
        width: _tileWidth,
        height: _cardHeight,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        decoration: BoxDecoration(
          // 深底上的淡玻璃，不用 glassWhite 實色（真機刺眼）。
          color: Colors.white.withValues(alpha: 0.08 + 0.10 * focus),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12 + 0.12 * focus),
          ),
        ),
        child: content,
      ),
    );
  }

  /// 不隨指針變的內容（圖示磚＋名字＋階段＋色點）。
  Widget _buildTileContent(int index) {
    final partner = widget.partners[index];
    final stage = widget.stageLabelOf(partner.id);
    // 身份色跟 id 走（同一人永遠同色，不受列表增刪影響）；
    // 不用 String.hashCode（跨 Dart 版本不保證穩定）。
    final colorKey =
        partner.id.codeUnits.fold<int>(0, (sum, unit) => sum + unit);
    final gradient = _tileGradients[colorKey % _tileGradients.length];
    final initial = partner.name.isEmpty
        ? '?'
        : partner.name.characters.first.toUpperCase();

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Text(
            initial,
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.onBackgroundPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          partner.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          // 深玻璃上用亮字（glassTextPrimary 是配舊白卡的墨字）。
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.onBackgroundPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          stage ?? '尚未分析',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.caption.copyWith(
            color: stage != null
                ? AppColors.onBackgroundSecondary
                : AppColors.onBackgroundSecondary.withValues(alpha: 0.6),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: gradient.first,
          ),
        ),
      ],
    );
  }
}
