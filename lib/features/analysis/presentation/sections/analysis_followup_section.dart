import 'package:flutter/material.dart';

import '../../../../core/services/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';

/// 草稿潤飾的獨立面板入口（2026-08-16 Bruce 回饋，從收合卡升級成整頁式）。
/// 判斷/策略仍交給 Coach 1:1。
class DraftPolishEntryCard extends StatelessWidget {
  const DraftPolishEntryCard({
    super.key,
    required this.onOpen,
    required this.outcomeBar,
  });

  final VoidCallback onOpen;

  /// 複製過潤飾稿才浮出的成效回報列（依 provider 狀態渲染，screen 組好
  /// 插入；沒有事件時是空盒）。留在本頁：使用者發完訊息回來時，面板通常
  /// 已經關了。
  final Widget outcomeBar;

  @override
  Widget build(BuildContext context) {
    return BrandSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            key: const ValueKey('draft-polish-entry'),
            behavior: HitTestBehavior.opaque,
            onTap: onOpen,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(TablerIcons.pencil,
                        size: 20, color: AppColors.ctaStart),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '我已有草稿，幫我修自然',
                        style: AppTypography.titleMedium
                            .copyWith(color: AppColors.onBackgroundPrimary),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: AppColors.onBackgroundSecondary
                          .withValues(alpha: 0.6),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '適合你已經知道想回什麼，只想調整語氣、長度和壓迫感。還不確定該不該回，就用「問教練」。',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.onBackgroundSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          outcomeBar,
        ],
      ),
    );
  }
}

/// 對話延續輸入區（分析完成後的底部動作列）：問教練直達 Sydney 視窗、
/// 分析新片段另開獨立片段。可見性（分析中/未完成隱藏）由 screen 判斷。
class ConversationContinuationBar extends StatelessWidget {
  const ConversationContinuationBar({
    super.key,
    required this.onAskCoach,
    required this.onNewFragment,
  });

  final VoidCallback onAskCoach;
  final VoidCallback onNewFragment;

  @override
  Widget build(BuildContext context) {
    // 分析完成後關閉原片段；任何新內容都另開獨立片段。
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.brandSurface2,
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: AppHaptics.onPress(onAskCoach),
                icon: const Icon(Icons.forum_outlined),
                label: const Text('問教練：我現在該怎麼做？'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: AppColors.ctaStart,
                  foregroundColor: AppColors.onCta,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onNewFragment,
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('分析新片段'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(
                    color: AppColors.ctaStart.withValues(alpha: 0.45),
                  ),
                  foregroundColor: AppColors.ctaStart,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
