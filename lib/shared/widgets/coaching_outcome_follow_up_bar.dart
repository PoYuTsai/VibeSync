import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../features/coaching_memory/domain/entities/coaching_outcome_event.dart';
import 'coaching_outcome_capture_card.dart';

/// 複製過建議後浮出的收合「後來呢？」條（opener / analyze 共用）。
/// [event] 為 null（尚未複製）時整條不渲染；展開後內嵌批 1 的
/// [CoachingOutcomeCaptureCard]，持久化仍由呼叫端 handler 負責。
class CoachingOutcomeFollowUpBar extends StatefulWidget {
  const CoachingOutcomeFollowUpBar({
    super.key,
    required this.event,
    this.label,
    required this.onUserActionSelected,
    required this.onOutcomeSelected,
  });

  final CoachingOutcomeEvent? event;

  /// 卡片型別短標（例：「延展」「AI 推薦回覆」），區分同一區多條。
  final String? label;
  final ValueChanged<CoachingUserAction> onUserActionSelected;
  final ValueChanged<CoachingOutcomeSignal> onOutcomeSelected;

  @override
  State<CoachingOutcomeFollowUpBar> createState() =>
      _CoachingOutcomeFollowUpBarState();
}

class _CoachingOutcomeFollowUpBarState
    extends State<CoachingOutcomeFollowUpBar> {
  bool _expanded = false;

  String _statusText(CoachingOutcomeEvent event) {
    final outcome = event.outcome;
    // 有第二段實際反應（engaged/cold/noReply/negative）→ 確定狀態。
    if (outcome != CoachingOutcomeSignal.pending &&
        outcome != CoachingOutcomeSignal.unknown) {
      return '已記下：${coachingOutcomeSignalLabel(outcome)}';
    }
    // 未送類（didNotSend/askedCoach）→ outcome==unknown，終態，報第一段動作。
    // 註：本流程 outcome==unknown 一律配非 unknown 的 userAction（copy 記
    // sentAsIs/pending、第一段未送類記 didNotSend|askedCoach/unknown），
    // 故舊版 `userAction==unknown → '回報一下結果'` 是走不到的 dead branch，
    // 本批移除。
    if (outcome == CoachingOutcomeSignal.unknown) {
      return '已記下：${coachingUserActionLabel(event.userAction)}';
    }
    // outcome==pending：可能是「複製自動記」的 sentAsIs，也可能是使用者手選
    // sentAsIs/editedAndSent 但還沒回報反應。現有欄位無法區分「自動記」與
    // 「手選」的 sentAsIs（兩者都是 sentAsIs/pending，無旗標），故統一用
    // outcome==pending 當 proxy 顯示中性文案——寧可對「已手選但沒回報反應」
    // 的使用者也顯示中性提示，也不對「只複製、沒真的確認發出」的使用者謊稱
    // 「已記下：照著發了」。使用者一旦回報第二段反應就落入上面的確定狀態分支。
    // 接受決策：手選「照著發了」但尚未答第二段時，收合標題仍顯示中性文案。
    return '已複製，發出後回報結果';
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    if (event == null) return const SizedBox.shrink();

    final title =
        widget.label == null ? '後來呢？' : '後來呢？（${widget.label}）';
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.flag_outlined,
                    size: 16,
                    color: AppColors.ctaStart,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$title・${_statusText(event)}',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.onBackgroundPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: AppColors.onBackgroundSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: CoachingOutcomeCaptureCard(
                event: event,
                onUserActionSelected: widget.onUserActionSelected,
                onOutcomeSelected: widget.onOutcomeSelected,
              ),
            ),
        ],
      ),
    );
  }
}
