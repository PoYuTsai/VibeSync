// lib/features/analysis/presentation/widgets/draft_polish_sheet.dart
//
// 「我已有草稿，幫我修自然」獨立面板（2026-08-16 Bruce 回饋：essential 功能
// 從分析頁的收合小卡升級成整頁式入口，版型對齊「再調一下」）。
//
// 這個 widget 只負責呈現與互動，**不自己打網路、不自己扣費**。實際請求由
// 呼叫端透過 [onPolish] 提供：exactly-once 帳本（requestId／replay）、同意、
// 額度與 paywall 都留在 analysis_screen 那條唯一路徑上；失敗與取消的提示
// 也由呼叫端顯示（root ScaffoldMessenger 會蓋在面板上方）。

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../domain/entities/analysis_models.dart';

/// 一次成功潤飾的結果；呼叫端已處理提示的失敗或使用者取消時回 null，
/// 面板只需要停止 loading。
typedef DraftPolishRequest = Future<OptimizedMessage?> Function(String draft);

Future<void> showDraftPolishSheet(
  BuildContext context, {
  required TextEditingController draftController,
  required DraftPolishRequest onPolish,
  required void Function(String polishedText) onCopy,
  required Future<void> Function(String polishedText) onRefine,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => DraftPolishSheet(
      draftController: draftController,
      onPolish: onPolish,
      onCopy: onCopy,
      onRefine: onRefine,
    ),
  );
}

class DraftPolishSheet extends StatefulWidget {
  const DraftPolishSheet({
    super.key,
    required this.draftController,
    required this.onPolish,
    required this.onCopy,
    required this.onRefine,
  });

  /// 由呼叫端持有：關掉面板再開，草稿還在。
  final TextEditingController draftController;
  final DraftPolishRequest onPolish;

  /// 複製潤飾結果：剪貼簿、成效帳與提示都由呼叫端做。
  final void Function(String polishedText) onCopy;

  /// 「再調一下」：呼叫端會把微調面板疊在本面板上（免費額度那條路）。
  final Future<void> Function(String polishedText) onRefine;

  @override
  State<DraftPolishSheet> createState() => _DraftPolishSheetState();
}

class _DraftPolishSheetState extends State<DraftPolishSheet> {
  bool _isPolishing = false;
  OptimizedMessage? _result;

  Future<void> _polish() async {
    final draft = widget.draftController.text.trim();
    if (draft.isEmpty || _isPolishing) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _isPolishing = true);
    final result = await widget.onPolish(draft);
    if (!mounted) return;
    setState(() {
      _isPolishing = false;
      // 失敗保留上一輪結果，提示已由呼叫端顯示。
      if (result != null) _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final result = _result;
    return FractionallySizedBox(
      heightFactor: 0.92,
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
                    '我已有草稿，幫我修自然',
                    style: AppTypography.titleLarge.copyWith(
                      color: AppColors.onBackgroundPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '這裡只修草稿；成功完成使用 1 則。想討論下一步，請用「問教練」。',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.onBackgroundSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView(
                      key: const ValueKey('draft-polish-body'),
                      padding: EdgeInsets.zero,
                      children: [
                        TextField(
                          key: const ValueKey('draft-polish-input'),
                          controller: widget.draftController,
                          enabled: !_isPolishing,
                          minLines: 3,
                          maxLines: 6,
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.onBackgroundPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: '貼上你原本想傳的訊息…',
                            hintStyle: AppTypography.bodyMedium.copyWith(
                              color: AppColors.onBackgroundSecondary
                                  .withValues(alpha: 0.6),
                            ),
                            filled: true,
                            fillColor:
                                AppColors.brandInk.withValues(alpha: 0.4),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.12),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.12),
                              ),
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            key: const ValueKey('draft-polish-submit'),
                            onPressed: _isPolishing ||
                                    widget.draftController.text.trim().isEmpty
                                ? null
                                : _polish,
                            icon: _isPolishing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.auto_fix_high),
                            label: Text(_isPolishing ? '優化中…' : '優化這段草稿'),
                          ),
                        ),
                        if (result != null &&
                            result.optimized.trim().isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              const Text('✨', style: TextStyle(fontSize: 18)),
                              const SizedBox(width: 8),
                              Text(
                                '優化後草稿',
                                style: AppTypography.titleMedium.copyWith(
                                  color: AppColors.onBackgroundPrimary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            key: const ValueKey('draft-polish-result'),
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.brandSurface2
                                      .withValues(alpha: 0.94),
                                  AppColors.brandSurface.withValues(alpha: 0.88),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color:
                                    AppColors.ctaStart.withValues(alpha: 0.55),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.22),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Text(
                              result.optimized,
                              style: AppTypography.bodyLarge.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (result.reason.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              '💡 ${result.reason}',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.onBackgroundPrimary,
                              ),
                            ),
                          ],
                          const SizedBox(height: 6),
                          SizedBox(
                            width: double.infinity,
                            height: 34,
                            child: TextButton.icon(
                              key: const ValueKey('draft-polish-refine'),
                              onPressed: _isPolishing
                                  ? null
                                  : () => widget.onRefine(result.optimized),
                              icon: const Icon(Icons.tune_rounded, size: 16),
                              label:
                                  Text('再調一下', style: AppTypography.labelMedium),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (result != null &&
                      result.optimized.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const ValueKey('draft-polish-copy'),
                        onPressed: () => widget.onCopy(result.optimized),
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('複製這段草稿'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
