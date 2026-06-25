import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/practice_girl_profile.dart';

/// 陪練對象照片：bundled JPEG asset 為主視覺，載入失敗時 fallback 到
/// 由 profileId 決定的穩定底色＋名字首字母，永不 crash。
///
/// - `circle: true` → 圓形，用於聊天 compact identity header。
/// - 否則 rounded-rect（預設圓角 16，或 caller 指定 `borderRadius`），用於首屏大卡。
///
/// 來源圖多為直幅，故 `BoxFit.cover` + `Alignment.topCenter` 以保住臉部。
class PracticeGirlPhoto extends StatelessWidget {
  const PracticeGirlPhoto({
    super.key,
    required this.profile,
    required this.width,
    required this.height,
    this.circle = false,
    this.borderRadius,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.topCenter,
  });

  final PracticeGirlProfile profile;
  final double width;
  final double height;
  final bool circle;
  final BorderRadius? borderRadius;
  final BoxFit fit;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      profile.photoAssetPath,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stack) => _PhotoFallback(
        profile: profile,
        width: width,
        height: height,
        fontSize: circle ? height * 0.42 : height / 3.4,
      ),
    );

    if (circle) {
      return ClipOval(
        child: SizedBox(width: width, height: height, child: image),
      );
    }
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(16),
      child: SizedBox(width: width, height: height, child: image),
    );
  }
}

Future<void> showPracticeGirlFullPhoto(
  BuildContext context,
  PracticeGirlProfile profile,
) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.92),
    builder: (_) => _PracticeGirlFullPhotoViewer(profile: profile),
  );
}

class _PracticeGirlFullPhotoViewer extends StatelessWidget {
  const _PracticeGirlFullPhotoViewer({required this.profile});

  final PracticeGirlProfile profile;

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      key: const ValueKey('practice-girl-full-photo-viewer'),
      backgroundColor: Colors.black,
      child: SafeArea(
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 3,
                child: Image.asset(
                  profile.photoAssetPath,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (context, error, stack) => _PhotoFallback(
                    profile: profile,
                    width: 220,
                    height: 220,
                    fontSize: 72,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                tooltip: '關閉',
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoFallback extends StatelessWidget {
  const _PhotoFallback({
    required this.profile,
    required this.width,
    required this.height,
    required this.fontSize,
  });

  final PracticeGirlProfile profile;
  final double width;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final hue = (profile.profileId.hashCode % 360).abs().toDouble();
    final bg = HSLColor.fromAHSL(1, hue, 0.42, 0.52).toColor();
    final initial = profile.displayName.isNotEmpty
        ? profile.displayName.substring(0, 1)
        : '?';
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      color: bg,
      child: Text(
        initial,
        style: AppTypography.bodyMedium.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: fontSize,
        ),
      ),
    );
  }
}
