import 'package:flutter/material.dart';

import '../../../../core/services/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';

/// 反饋區的動作介面：section 只發出使用者意圖，狀態變更、觸覺回饋與
/// 送出流程全由 screen 實作。
abstract interface class AnalysisFeedbackActions {
  void submitPositiveFeedback();
  void openNegativeFeedbackForm();
  void selectFeedbackCategory(String? category);
  void setIncludeFeedbackContext(bool include);
  void submitNegativeFeedback();
  void dismissKeyboard();
}

/// 分析完成後的「這個建議有幫助嗎？」反饋區：讚/倒讚、倒讚展開的
/// 分類表單與補充欄，以及已送出的致謝態。
class AnalysisFeedbackSection extends StatelessWidget {
  const AnalysisFeedbackSection({
    super.key,
    required this.submitted,
    required this.showForm,
    required this.isSubmitting,
    required this.selectedCategory,
    required this.includeContext,
    required this.commentController,
    required this.actions,
  });

  final bool submitted;
  final bool showForm;
  final bool isSubmitting;
  final String? selectedCategory;
  final bool includeContext;
  final TextEditingController commentController;
  final AnalysisFeedbackActions actions;

  @override
  Widget build(BuildContext context) {
    if (submitted) {
      return Center(
        child: Text(
          '已收到你的回饋',
          style: AppTypography.bodyMedium
              .copyWith(color: AppColors.textSecondary),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(
            color: AppColors.onBackgroundSecondary.withValues(alpha: 0.5)),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('這個建議有幫助嗎？',
                style: AppTypography.bodyMedium
                    .copyWith(color: AppColors.onBackgroundPrimary)),
            const SizedBox(width: 16),
            IconButton(
              icon: const Icon(Icons.thumb_up_outlined),
              onPressed: isSubmitting ? null : actions.submitPositiveFeedback,
              tooltip: '有幫助',
              color: AppColors.success,
            ),
            IconButton(
              icon: const Icon(Icons.thumb_down_outlined),
              onPressed:
                  isSubmitting ? null : actions.openNegativeFeedbackForm,
              tooltip: '需要改進',
              color: AppColors.error,
            ),
          ],
        ),
        if (showForm) ...[
          const SizedBox(height: 16),
          BrandSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('哪裡需要改進？',
                    style: AppTypography.bodyLarge
                        .copyWith(color: AppColors.onBackgroundPrimary)),
                const SizedBox(height: 8),
                Text(
                  '預設只送評分類別與結構化分析資訊，不附原始對話。',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.onBackgroundSecondary
                        .withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _categoryChip('too_direct', '太直接'),
                    _categoryChip('unnatural', '不自然'),
                    _categoryChip('too_long', '回覆太長'),
                    _categoryChip('wrong_style', '不符合我的風格'),
                    _categoryChip('other', '其他'),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: includeContext,
                      onChanged: isSubmitting
                          ? null
                          : (value) =>
                              actions.setIncludeFeedbackContext(value ?? false),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          '附上最後 6 則對話片段，幫助我們排查（選填）',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.onBackgroundPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: commentController,
                  enabled: !isSubmitting,
                  style: AppTypography.bodyMedium
                      .copyWith(color: AppColors.onBackgroundPrimary),
                  decoration: InputDecoration(
                    hintText: '補充說明（選填）',
                    helperText: '輸入完可先收起鍵盤，再送出反饋。',
                    hintStyle: AppTypography.bodyMedium.copyWith(
                        color: AppColors.onBackgroundSecondary
                            .withValues(alpha: 0.6)),
                    helperStyle: AppTypography.caption.copyWith(
                      color: AppColors.onBackgroundSecondary
                          .withValues(alpha: 0.6),
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.brandInk.withValues(alpha: 0.4),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                          color: AppColors.ctaStart, width: 1.5),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(Icons.keyboard_hide,
                          color: AppColors.onBackgroundSecondary
                              .withValues(alpha: 0.6)),
                      onPressed: actions.dismissKeyboard,
                      tooltip: '收起鍵盤',
                    ),
                  ),
                  maxLength: 300,
                  maxLines: 3,
                  textInputAction: TextInputAction.done,
                  onEditingComplete: actions.dismissKeyboard,
                  onTapOutside: (_) => actions.dismissKeyboard(),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: AppHaptics.onPress(
                        selectedCategory != null && !isSubmitting
                            ? actions.submitNegativeFeedback
                            : null),
                    child: isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('送出反饋'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _categoryChip(String value, String label) {
    final isSelected = selectedCategory == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      // 勾勾淡入淡出在快速切換時會留殘影＋寬度跳動，全 App chips 一律不顯示。
      showCheckmark: false,
      onSelected: isSubmitting
          ? null
          : (selected) =>
              actions.selectFeedbackCategory(selected ? value : null),
    );
  }
}
