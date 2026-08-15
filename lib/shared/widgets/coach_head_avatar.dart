import 'package:flutter/material.dart';

/// 教練 Sydney 圓形頭像：從 greeting 立繪裁出頭部方框（canvas 1023×1537、
/// 人物中心 x≈0.503、頭頂約 y=154），再縮到指定直徑。原生於首頁入口卡，
/// 問教練 Sydney 視窗開場泡泡共用；量測值變動時只要改這裡的裁切框。
class CoachHeadAvatar extends StatelessWidget {
  const CoachHeadAvatar({super.key, required this.size});

  final double size;

  static const _assetPath = 'assets/images/coach/sydney_greeting.png';
  static const _canvasWidth = 1023.0;
  static const _canvasHeight = 1537.0;
  static const _cropLeft = 269.0;
  static const _cropTop = 154.0;
  static const _cropSide = 492.0;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: Colors.white.withValues(alpha: 0.10),
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox.square(
            dimension: _cropSide,
            // OverflowBox 給原圖無界約束：直接塞進 492 方框會被壓成 492×492
            // （比例全歪），位移後裁到的是手不是臉。
            child: OverflowBox(
              minWidth: 0,
              maxWidth: double.infinity,
              minHeight: 0,
              maxHeight: double.infinity,
              alignment: Alignment.topLeft,
              child: Transform.translate(
                offset: const Offset(-_cropLeft, -_cropTop),
                child: Image.asset(
                  _assetPath,
                  width: _canvasWidth,
                  height: _canvasHeight,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.medium,
                  excludeFromSemantics: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
