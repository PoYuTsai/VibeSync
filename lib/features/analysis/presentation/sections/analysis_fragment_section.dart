import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../conversation/domain/entities/message.dart';
import '../../../conversation/presentation/widgets/message_bubble.dart';

/// 片段卡的動作介面：來源設定與訊息編修（對話寫入、對話框）由 screen 實作。
abstract interface class AnalysisFragmentActions {
  void chooseConversationSource();
  void editFragmentMessage(Message message);
  void swapFragmentMessageSide(Message message);
  void deleteFragmentMessage(Message message);
}

/// 片段內單則訊息的展示規格（可否編修由 screen 依分析狀態與已封存
/// 界線算好）。
@immutable
class FragmentMessageItem {
  const FragmentMessageItem({required this.message, required this.mutable});

  final Message message;
  final bool mutable;
}

/// 本次分析片段卡：標頭（狀態標題＋來源 pill）、封存說明、紀錄修復警告、
/// 空片段主視覺與訊息泡泡列表。
class AnalysisFragmentCard extends StatelessWidget {
  const AnalysisFragmentCard({
    super.key,
    required this.isEmptyFragmentSetup,
    required this.isPendingFragment,
    required this.isCompletedFragment,
    required this.showRecordRepairWarning,
    required this.isScreenshotOnlyEmptyState,
    required this.showEmptyState,
    required this.messages,
    required this.sourceLabel,
    required this.sourceEditable,
    required this.actions,
  });

  final bool isEmptyFragmentSetup;
  final bool isPendingFragment;
  final bool isCompletedFragment;
  final bool showRecordRepairWarning;
  final bool isScreenshotOnlyEmptyState;

  /// 片段沒有訊息且空態主視覺未讓位給選圖列時顯示「還沒有訊息」。
  final bool showEmptyState;
  final List<FragmentMessageItem> messages;
  final String sourceLabel;
  final bool sourceEditable;
  final AnalysisFragmentActions actions;

  @override
  Widget build(BuildContext context) {
    // Messages preview（空白新片段時平鋪深色、不上白卡）
    return Container(
      width: double.infinity,
      padding:
          isEmptyFragmentSetup ? EdgeInsets.zero : const EdgeInsets.all(14),
      decoration: isEmptyFragmentSetup
          ? null
          : BoxDecoration(
              color: Colors.white.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppColors.ctaStart.withValues(alpha: 0.24),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isPendingFragment
                      ? '待分析的新片段'
                      : isCompletedFragment
                          ? '本次分析片段'
                          : '新的分析片段',
                  style: AppTypography.titleMedium.copyWith(
                    color: isEmptyFragmentSetup
                        ? AppColors.onBackgroundPrimary
                        : AppColors.glassTextPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ConversationSourcePill(
                sourceLabel: sourceLabel,
                canEdit: sourceEditable,
                onTap: actions.chooseConversationSource,
              ),
            ],
          ),
          // 空片段與待分析片段都不放副標（2026-08-14 對標示意稿拆
          // 「先加入…」；2026-08-16 Bruce 回饋再拆「這批新聊天會獨立
          // 分析…」）。只有封存片段需要唯讀說明。
          if (isCompletedFragment) ...[
            const SizedBox(height: 4),
            Text(
              '這次分析已獨立封存，內容唯讀；新內容請另開分析片段。',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.glassTextSecondary,
                height: 1.35,
              ),
            ),
          ],
          if (showRecordRepairWarning) ...[
            const SizedBox(height: 7),
            Text(
              '分析已完成，但紀錄尚未儲存；系統會自動重試。',
              key: const ValueKey(
                'analysis-record-repair-warning',
              ),
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.warning,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 10),
          // 已選圖時空態主視覺讓位給選圖列＋辨識 CTA，整頁不用捲就看得到
          // 下一步。
          if (showEmptyState)
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 20,
                horizontal: 8,
              ),
              child: Column(
                children: [
                  if (isEmptyFragmentSetup)
                    // 對標示意稿：紫色聊天泡泡直接放大，
                    // 不加圓框（2026-08-14 Eric 拍板拆框）
                    const Icon(
                      Icons.sms_outlined,
                      color: AppColors.coachAccentBright,
                      size: 72,
                    )
                  else
                    Icon(
                      Icons.chat_bubble_outline,
                      color: AppColors.ctaStart,
                      size: 34,
                    ),
                  SizedBox(
                    height: isEmptyFragmentSetup ? 14 : 10,
                  ),
                  Text(
                    '還沒有訊息',
                    style: (isEmptyFragmentSetup
                            ? AppTypography.titleLarge
                            : AppTypography.titleMedium)
                        .copyWith(
                      color: isEmptyFragmentSetup
                          ? AppColors.onBackgroundPrimary
                          : AppColors.glassTextPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isScreenshotOnlyEmptyState
                        ? '先上傳 1–3 張聊天截圖，確認文字後作為本次片段。'
                        : '請回到上一頁建立新的獨立分析片段。',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySmall.copyWith(
                      color: isEmptyFragmentSetup
                          ? AppColors.onBackgroundSecondary
                          : AppColors.glassTextSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ...messages.map(
            (item) => MessageBubble(
              message: item.message,
              onEdit: item.mutable
                  ? () => actions.editFragmentMessage(item.message)
                  : null,
              onSwapSide: item.mutable
                  ? () => actions.swapFragmentMessageSide(item.message)
                  : null,
              onDelete: item.mutable
                  ? () => actions.deleteFragmentMessage(item.message)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// 聊天來源 pill（「來源：Tinder」／「來源未設定」）。
class ConversationSourcePill extends StatelessWidget {
  const ConversationSourcePill({
    super.key,
    required this.sourceLabel,
    required this.canEdit,
    required this.onTap,
  });

  final String sourceLabel;
  final bool canEdit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.ctaStart.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        key: const ValueKey('analysis-source-pill'),
        borderRadius: BorderRadius.circular(999),
        onTap: canEdit ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.layers_outlined,
                size: 15,
                color: AppColors.ctaStart,
              ),
              const SizedBox(width: 5),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 96),
                child: Text(
                  sourceLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.ctaStart,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (canEdit) ...[
                const SizedBox(width: 2),
                Icon(
                  Icons.arrow_drop_down_rounded,
                  size: 18,
                  color: AppColors.ctaStart,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
