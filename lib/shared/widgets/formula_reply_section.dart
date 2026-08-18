import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// 公式回覆共用顯示區塊（2026-07-24 公式回覆計畫 §10.1）。
///
/// Opener＝「公式開場」、New Topic＝「公式新話題」共用同一語意：
/// - 每張卡顯示完整 openingLine（可直接傳）＋「為什麼好接」教練註解。
/// - 複製只複製 openingLine（snackbar 語氣由呼叫端沿用該頁既有樣式）。
/// - 空清單時整區不渲染由呼叫端負責（`if (entries.isNotEmpty)`），
///   不留標題／間距；只有一則時只渲染一張，不補空卡。
/// - 垂直自適應高度：不套 opener 固定 220 高橫卡，180/300 cap 內容
///   不會被 ellipsis。
/// - 本案不掛 outcome/reaction bar（拍板）。
class FormulaReplyEntry {
  const FormulaReplyEntry({
    required this.openingLine,
    required this.whyItWorks,
  });

  final String openingLine;
  final String whyItWorks;
}

class FormulaReplySection extends StatefulWidget {
  const FormulaReplySection({
    super.key,
    required this.title,
    required this.entries,
    required this.onCopyOpeningLine,
  });

  static const subtitle = '具體線索＋你的當下反應＋一個好接的開口';

  final String title;
  final List<FormulaReplyEntry> entries;
  final ValueChanged<FormulaReplyEntry> onCopyOpeningLine;

  @override
  State<FormulaReplySection> createState() => _FormulaReplySectionState();
}

class _FormulaReplySectionState extends State<FormulaReplySection> {
  /// 2026-08-18 拍板：第 1 則主推常駐，其餘收在「再看一組」後——一次一張卡
  /// 的視覺重量，密度與「兩則怎麼區別」一起解（主推＋備選）。
  bool _showMore = false;

  @override
  void didUpdateWidget(FormulaReplySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.entries, widget.entries)) _showMore = false;
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    if (entries.isEmpty) return const SizedBox.shrink();
    final visibleEntries = _showMore ? entries : entries.sublist(0, 1);
    return Container(
      key: const ValueKey('formula-reply-section'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            AppColors.coachSurfaceRaised,
            AppColors.coachBackgroundMid,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.coachAccent.withValues(alpha: 0.36),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: AppTypography.titleMedium.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      FormulaReplySection.subtitle,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.onBackgroundSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                key: const ValueKey('formula-reply-method-badge'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.coachAccent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppColors.coachAccent.withValues(alpha: 0.34),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.functions_rounded,
                      size: 13,
                      color: AppColors.coachAccentBright,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '固定結構',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.coachAccentBright,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < visibleEntries.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _FormulaReplyCard(
                    index: i,
                    entry: visibleEntries[i],
                    onCopyOpeningLine: () =>
                        widget.onCopyOpeningLine(visibleEntries[i]),
                  ),
                ],
              ],
            ),
          ),
          if (entries.length > 1) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.center,
              child: TextButton.icon(
                key: const ValueKey('formula-reply-toggle-more'),
                onPressed: () => setState(() => _showMore = !_showMore),
                icon: Icon(
                  _showMore
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                ),
                label: Text(_showMore ? '收起備選' : '再看一組'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.coachAccentBright,
                  minimumSize: const Size(72, 44),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FormulaReplyCard extends StatelessWidget {
  const _FormulaReplyCard({
    required this.index,
    required this.entry,
    required this.onCopyOpeningLine,
  });

  final int index;
  final FormulaReplyEntry entry;
  final VoidCallback onCopyOpeningLine;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('formula-reply-card-$index'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.coachBackgroundMid.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.coachAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '可直接傳',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.coachAccentBright,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onCopyOpeningLine,
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('複製'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.ctaStart,
                  minimumSize: const Size(72, 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            entry.openingLine,
            key: ValueKey('formula-reply-opening-line-$index'),
            style: AppTypography.bodyMedium.copyWith(
              color: Colors.white,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Divider(
            key: ValueKey('formula-reply-divider-$index'),
            height: 1,
            color: AppColors.coachAccent.withValues(alpha: 0.18),
          ),
          const SizedBox(height: 8),
          Text(
            '為什麼好接',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.coachAccentBright.withValues(alpha: 0.92),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            entry.whyItWorks,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundPrimary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
