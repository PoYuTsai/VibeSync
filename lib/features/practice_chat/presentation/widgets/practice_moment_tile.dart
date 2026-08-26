// 動態 feed 的一則貼文（Threads 版面，D5b）。
//
// **這是 tile，不是 card**：頭像靠左、文字欄是主體、配圖單張且次要，
// 用細分隔線區隔而不是每則包一張帶陰影的卡片。卡片流會把密度殺光——
// 一屏要看得到至少 3 則純文字貼文才算對。
//
// 明確不做（PLAN §4.0 的「不要做什麼」清單）：九宮格、全寬大圖、
// 把圖當視覺主角、BoxShadow 卡片。
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/practice_girl_profile.dart';
import '../../domain/entities/practice_moment_image.dart';
import '../../domain/entities/practice_moment_post.dart';
import '../../domain/entities/practice_moment_relative_time.dart';
import 'practice_girl_photo.dart';

/// 頭像直徑（Threads 尺度：小、靠左、不搶焦點）。
const double kMomentAvatarSize = 40;

/// 頭像與文字欄之間的間距。
const double kMomentAvatarGap = 12;

/// 配圖佔文字欄寬度的比例上限——**刻意小於 1**：圖是節奏變化，不是主角。
const double kMomentImageWidthRatio = 0.72;

/// 配圖高度上限。
const double kMomentImageMaxHeight = 180;

/// 配圖長寬比（4:3）。頭像是圓形 topCenter 裁切，這裡刻意用較寬的框＋不同
/// alignment，同一張圖鑑照在一則裡出現兩次時讀起來是「同一個人的另一個構圖」。
const double kMomentImageAspectRatio = 4 / 3;

class PracticeMomentTile extends StatelessWidget {
  const PracticeMomentTile({
    super.key,
    required this.post,
    required this.profile,
    required this.now,
  });

  final PracticeMomentPost post;

  /// 發文者；catalog 查不到（舊 build 撞新角色）時傳 null，畫面照樣顯示文字。
  final PracticeGirlProfile? profile;

  /// 相對時間的基準（測試可注入固定時鐘）。
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final displayName = profile?.displayName ?? '練習對象';
    final imageSource = post.imageSource;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MomentAvatar(profile: profile, displayName: displayName),
          const SizedBox(width: kMomentAvatarGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 名字與相對時間同一行；時間次級色、不換行搶空間。
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.titleMedium.copyWith(
                          color: AppColors.onBackgroundPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '· ${momentRelativeLabel(post.postedAt, now)}',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.onBackgroundSecondary
                            .withValues(alpha: 0.68),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // 內文貼齊文字欄左緣，與名字同一條垂直線。
                Text(
                  post.body,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.onBackgroundPrimary,
                    height: 1.45,
                  ),
                ),
                // 無圖時完全不留空塊——這是 Threads 與朋友圈最大的差別。
                if (imageSource != null) ...[
                  const SizedBox(height: 10),
                  _MomentImage(
                    source: imageSource,
                    profile: profile,
                    displayName: displayName,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MomentAvatar extends StatelessWidget {
  const _MomentAvatar({required this.profile, required this.displayName});

  final PracticeGirlProfile? profile;
  final String displayName;

  @override
  Widget build(BuildContext context) {
    final girl = profile;
    if (girl != null) {
      return PracticeGirlPhoto(
        profile: girl,
        width: kMomentAvatarSize,
        height: kMomentAvatarSize,
        circle: true,
      );
    }
    // catalog 查不到時的兜底圓：不 crash、不留破圖框。
    return Container(
      width: kMomentAvatarSize,
      height: kMomentAvatarSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.brandSurface2,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Text(
        displayName.characters.isEmpty ? '?' : displayName.characters.first,
        style: AppTypography.bodySmall.copyWith(
          color: AppColors.onBackgroundSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 單張配圖：寬度上限＝文字欄的 [kMomentImageWidthRatio]，高度再夾一次
/// [kMomentImageMaxHeight]，貼齊文字欄左緣。**永遠不會全寬。**
class _MomentImage extends StatelessWidget {
  const _MomentImage({
    required this.source,
    required this.profile,
    required this.displayName,
  });

  final MomentImageSource source;
  final PracticeGirlProfile? profile;
  final String displayName;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth * kMomentImageWidthRatio;
        final height =
            (width / kMomentImageAspectRatio).clamp(0.0, kMomentImageMaxHeight);
        return Align(
          alignment: Alignment.centerLeft,
          child: _buildImage(context, width, height),
        );
      },
    );
  }

  Widget _buildImage(BuildContext context, double width, double height) {
    final girl = profile;
    switch (source) {
      case MomentSelfPortraitImage():
        if (girl == null) return const SizedBox.shrink();
        // 頭像是 circle + topCenter；這裡用 4:3 框＋略高於中線的 alignment，
        // 讀起來是同一個人的另一個構圖，而不是同一張圖貼兩次。
        return PracticeGirlPhoto(
          profile: girl,
          width: width,
          height: height,
          borderRadius: BorderRadius.circular(18),
          alignment: const Alignment(0, -0.55),
        );
      case MomentSceneImage(:final assetPath):
        return ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Image.asset(
            assetPath,
            width: width,
            height: height,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            // 素材缺檔時降級成純文字，不顯示破圖。
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        );
      case MomentRemoteImage(:final url):
        // server 生成的配圖（PR-5）。磁碟快取是必要的：D7 每次進畫面重抓
        // feed，沒有快取等於每次進頁重載全部圖。載入中用素色圓角塊佔住
        // 4:3 空間（防 layout shift，比 shimmer 更貼 Threads 版面）；
        // 載不出（弱網／物件已過期刪除）降級純文字＝現行鐵則。
        final reduceMotion = MediaQuery.of(context).disableAnimations;
        return ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: CachedNetworkImage(
            imageUrl: url,
            width: width,
            height: height,
            fit: BoxFit.cover,
            fadeInDuration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 200),
            fadeOutDuration: Duration.zero,
            placeholder: (_, __) => Container(
              width: width,
              height: height,
              color: AppColors.glassBorder.withValues(alpha: 0.35),
            ),
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          ),
        );
    }
  }
}

/// 貼文之間的細分隔線。**不是卡片陰影**——分隔用線與間距，密度才留得住。
class PracticeMomentDivider extends StatelessWidget {
  const PracticeMomentDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 16,
      endIndent: 16,
      color: Colors.white.withValues(alpha: 0.07),
    );
  }
}
