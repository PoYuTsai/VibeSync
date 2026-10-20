import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../../core/services/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../analysis/presentation/sections/guide_v3_result_section.dart'
    show guideV3LightColor;
import '../../../partner/domain/entities/partner.dart';
import '../../../partner/domain/extensions/partner_aggregates.dart';
import 'partner_stage_assets.dart';

/// 報告頁底部「對象作戰板」dock（2026-08-14 對標夥伴示意稿）。
///
/// 每個對象一張玻璃卡：寫實 3D 階段物件＋名字＋階段＋身份色點。最近分析是 v3 的對象
/// 多一盞燈號小燈＋短狀態（輪到你回／先等她／先停，跟首頁對象卡同一組字；Bruce
/// 2026-10-19 路線二選的是 B1 的物件加燈號）；改版前分析、沒有階段的 v3 對象，物件的
/// 位置放大燈號，不再說「尚未分析」。
/// 手指按住在列上左右滑，靠近手指的卡會像 macOS Dock 一樣放大，
/// 焦點換到另一張卡時給一下 selection 震動；放開全部回彈。
/// 系統關閉動畫（disableAnimations）時不放大，只保留點擊。
///
/// 純資料 widget（partners + stageLabelOf + guideV3SignalsOf + onTapPartner），
/// 不碰 provider，測試零 stub。
class PartnerMindMapCardList extends StatefulWidget {
  final List<Partner> partners;
  final String? Function(String partnerId) stageLabelOf;

  /// 最近分析過的那段是 v3 時的訊號（燈號、決定）；不是 v3 回 null。
  final PartnerGuideV3Signals? Function(String partnerId)? guideV3SignalsOf;
  final ValueChanged<String> onTapPartner;

  const PartnerMindMapCardList({
    super.key,
    required this.partners,
    required this.stageLabelOf,
    this.guideV3SignalsOf,
    required this.onTapPartner,
  });

  @override
  State<PartnerMindMapCardList> createState() => _PartnerMindMapCardListState();
}

class _PartnerMindMapCardListState extends State<PartnerMindMapCardList> {
  static const _tileWidth = 88.0;
  static const _tileGap = 12.0;
  static const _baseCardHeight = 132.0;
  // 物件＋階段之外多一列燈號狀態（v3 對象）：卡片加高一列，物件不縮小。只有 v2 對象時照舊。
  static const _statusCardHeight = 152.0;
  static const _stageImageSize = 60.0;
  static const _lampSize = 36.0;
  static const _identityDotSize = 9.0;
  // 放大最多 22%，向上長；列高留足空間讓放大不被裁掉。
  static const _maxBoost = 0.22;
  // 外層霧面托盤的內距；卡片坐在托盤裡，放大時往上凸出托盤。
  static const _trayPadding = 12.0;

  double get _cardHeight => widget.partners.any(
        (partner) =>
            widget.stageLabelOf(partner.id) != null &&
            _statusOf(partner.id) != null,
      )
          ? _statusCardHeight
          : _baseCardHeight;

  PartnerGuideV3Signals? _signalsOf(String partnerId) =>
      widget.guideV3SignalsOf?.call(partnerId);

  String? _statusOf(String partnerId) => _signalsOf(partnerId)?.status;
  // 距手指多遠內受影響（px）
  static const _influence = 120.0;

  // 對象識別色只留在下方圓點，依對象 id 穩定定色；階段辨識改由上方
  // 3D 物件負責，避免「身份」和「進度」兩套語意擠在同一個色塊裡。
  static const _identityGradients = [
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
      AppHaptics.tap();
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
    final cardHeight = _cardHeight;

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
            height: cardHeight * (1 + _maxBoost) + _trayPadding + 16,
            // 對標示意稿的「雙重玻璃」：底層一個大霧面托盤包整排，
            // 每張卡自己再一層更淡的玻璃；放大的卡往上凸出托盤。
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: cardHeight + _trayPadding * 2,
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
                          duration: AppMotion.pressDown,
                          curve: AppMotion.easeOut,
                          alignment: Alignment.bottomCenter,
                          child: _buildTileShell(
                            index,
                            focus,
                            tileContent!,
                            cardHeight,
                          ),
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
  Widget _buildTileShell(
    int index,
    double focus,
    Widget content,
    double cardHeight,
  ) {
    final partner = widget.partners[index];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onTapPartner(partner.id),
      child: Container(
        width: _tileWidth,
        height: cardHeight,
        // 3D 階段圖固定 60px、身份點放大至 9px；保留 4px 內垂直餘裕，
        // 避免小螢幕／測試字型的 Text line metrics 讓內容溢出卡片。
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
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

  /// 不隨指針變的內容（3D 階段物件＋名字＋階段＋燈號狀態＋身份色點）。
  Widget _buildTileContent(int index) {
    final partner = widget.partners[index];
    final stage = widget.stageLabelOf(partner.id);
    final signals = _signalsOf(partner.id);
    final status = signals?.status;
    // 身份色跟 id 走（同一人永遠同色，不受列表增刪影響）；
    // 不用 String.hashCode（跨 Dart 版本不保證穩定）。
    final colorKey =
        partner.id.codeUnits.fold<int>(0, (sum, unit) => sum + unit);
    final identityGradient =
        _identityGradients[colorKey % _identityGradients.length];
    // 改版前分析的 v3 對象沒有階段：物件的位置放大燈號，不說「尚未分析」（他分析過）。
    final lampOnly = stage == null && signals != null;
    final shortStageLabel = partnerStageShortLabelFor(stage);
    final lampColor = signals?.light == null
        ? AppColors.onBackgroundSecondary
        : guideV3LightColor(signals!.light!);
    final statusStyle = AppTypography.caption.copyWith(
      // 字留白色（綠紅字在這張卡上不到 4.5:1），顏色由燈號帶（跟首頁對象卡一樣）。
      color: Colors.white.withValues(alpha: 0.88),
      fontWeight: FontWeight.w700,
    );

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (lampOnly)
          _BigLamp(
            key: ValueKey('partner-stage-lamp-${partner.id}'),
            color: lampColor,
            size: _lampSize,
            semanticsLabel: signals.light?.label,
          )
        else
          Image.asset(
            partnerStageAssetFor(stage),
            key: ValueKey('partner-stage-image-${partner.id}'),
            width: _stageImageSize,
            height: _stageImageSize,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
            isAntiAlias: true,
            // 下方已有可朗讀的階段文字，圖片純裝飾，避免 VoiceOver 重複播報。
            excludeFromSemantics: true,
          ),
        SizedBox(height: lampOnly ? 6 : 5),
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
        if (!lampOnly) ...[
          const SizedBox(height: 2),
          Text(
            shortStageLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption.copyWith(
              color: stage != null
                  ? AppColors.onBackgroundSecondary
                  : AppColors.onBackgroundSecondary.withValues(alpha: 0.6),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (status != null) ...[
          const SizedBox(height: 2),
          if (lampOnly)
            Text(
              status,
              key: ValueKey('partner-stage-status-${partner.id}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: statusStyle,
            )
          else
            Row(
              key: ValueKey('partner-stage-status-${partner.id}'),
              mainAxisSize: MainAxisSize.min,
              children: [
                _SmallLamp(
                  color: lampColor,
                  semanticsLabel: signals?.light?.label,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: statusStyle,
                  ),
                ),
              ],
            ),
        ],
        const SizedBox(height: 4),
        Container(
          key: ValueKey('partner-identity-dot-${partner.id}'),
          width: _identityDotSize,
          height: _identityDotSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: identityGradient.first,
          ),
        ),
      ],
    );
  }
}

/// 改版前分析、沒有階段的 v3 對象：物件的位置放一盞平面燈號（沒有光暈，B3 的樣子）。
class _BigLamp extends StatelessWidget {
  const _BigLamp({
    super.key,
    required this.color,
    required this.size,
    this.semanticsLabel,
  });

  final Color color;
  final double size;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.16),
          border: Border.all(color: color.withValues(alpha: 0.7), width: 1.5),
        ),
        alignment: Alignment.center,
        child: Container(
          width: size * 0.39,
          height: size * 0.39,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

/// 物件下面狀態字旁的小燈（燈號讀不懂時是灰的）。
class _SmallLamp extends StatelessWidget {
  const _SmallLamp({required this.color, this.semanticsLabel});

  final Color color;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
