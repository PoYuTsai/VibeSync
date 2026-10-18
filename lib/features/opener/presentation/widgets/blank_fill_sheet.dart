import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/app_sheet.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../../analysis/domain/entities/guide_v3_result.dart';

/// 句子裡有沒有留給他填的「＿＿」（跟對話分析同一套判斷）。
bool blankFillNeeded(String text) => guideV3TextHasBlank(text);

/// 留「＿＿」的句子先填好再複製（Bruce 2026-10-18 #97：三個功能留空格一律用
/// 「＿＿」）。做法照對話分析的 `GuideV3EditSheet`：先選好第一個空格，空格還在或
/// 清空就不能按複製。開場救星「帶到自己」的範例與新話題共用。
/// 回傳填好的句子（去掉頭尾空白）；他關掉就回 null。
Future<String?> showBlankFillSheet(
  BuildContext context, {
  required String text,
}) {
  return showAppSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => BlankFillSheet(text: text),
  );
}

class BlankFillSheet extends StatefulWidget {
  const BlankFillSheet({super.key, required this.text});

  final String text;

  @override
  State<BlankFillSheet> createState() => _BlankFillSheetState();
}

class _BlankFillSheetState extends State<BlankFillSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.text);

  @override
  void initState() {
    super.initState();
    // 先選好第一個空格：打字就直接換掉＿＿，不用自己點到底線再刪。
    final match = RegExp('$guideV3BlankMark+').firstMatch(_controller.text);
    if (match != null) {
      _controller.selection = TextSelection(
        baseOffset: match.start,
        extentOffset: match.end,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _ready =>
      _controller.text.trim().isNotEmpty &&
      !guideV3TextHasBlank(_controller.text);

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final blanksLeft = guideV3TextHasBlank(_controller.text);
    return FractionallySizedBox(
      heightFactor: 0.6,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BrandPageBackground(
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottomInset),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '把＿＿換成你的',
                    style: AppTypography.titleLarge.copyWith(
                      color: AppColors.onBackgroundPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '空格填好才能複製，其他字也可以順手改。',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.onBackgroundSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        TextField(
                          key: const ValueKey('blank-fill-field'),
                          controller: _controller,
                          autofocus: true,
                          minLines: 1,
                          maxLines: 5,
                          onChanged: (_) => setState(() {}),
                          style: AppTypography.bodyLarge.copyWith(
                            color: AppColors.onBackgroundPrimary,
                          ),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor:
                                AppColors.brandInk.withValues(alpha: 0.45),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (blanksLeft) ...[
                    Text(
                      '還有＿＿沒填',
                      key: const ValueKey('blank-fill-blanks-left'),
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.warning,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    height: 46,
                    child: FilledButton.icon(
                      key: const ValueKey('blank-fill-copy'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.ctaStart,
                        foregroundColor: AppColors.onCta,
                      ),
                      onPressed: _ready
                          ? () => Navigator.of(context)
                              .pop(_controller.text.trim())
                          : null,
                      icon: const Icon(TablerIcons.copy, size: 18),
                      label: const Text('複製'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
