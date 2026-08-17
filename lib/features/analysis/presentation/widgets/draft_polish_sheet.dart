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
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../domain/entities/analysis_models.dart';
import '../../../../shared/widgets/brand/app_sheet.dart';

/// 一次潤飾請求的面板層結果。
///
/// - [result]：成功的潤飾結果。
/// - [notice]：被擋下時要**留在面板上**給使用者看的說明（亂碼防呆、
///   安全守門、格式無效都不扣費）——snackbar 一閃就過，使用者看不懂
///   為什麼沒結果（2026-08-16 Eric 真機回饋）。
///
/// 呼叫端已自行提示的情況（額度／登入／泛用失敗／取消）仍回 null，
/// 面板只停止 loading。
class DraftPolishOutcome {
  final OptimizedMessage? result;
  final String? notice;

  const DraftPolishOutcome.success(OptimizedMessage this.result)
      : notice = null;
  const DraftPolishOutcome.blocked(String this.notice) : result = null;
}

typedef DraftPolishRequest = Future<DraftPolishOutcome?> Function(String draft);

Future<void> showDraftPolishSheet(
  BuildContext context, {
  required TextEditingController draftController,
  required DraftPolishRequest onPolish,
  required void Function(String polishedText) onCopy,
  required Future<void> Function(String polishedText) onRefine,
}) {
  return showAppSheet<void>(
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
  String? _notice;
  final FocusNode _draftFocusNode = FocusNode();

  @override
  void dispose() {
    _draftFocusNode.dispose();
    super.dispose();
  }

  Future<void> _polish() async {
    final draft = widget.draftController.text.trim();
    if (draft.isEmpty || _isPolishing) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _isPolishing = true;
      _notice = null;
    });
    final outcome = await widget.onPolish(draft);
    if (!mounted) return;
    setState(() {
      _isPolishing = false;
      // null＝呼叫端已提示（額度／登入／泛用失敗），保留上一輪結果。
      if (outcome == null) return;
      if (outcome.result != null) {
        _result = outcome.result;
      } else {
        // 被擋下（亂碼／安全／格式無效、皆不扣費）：說明留在面板上。
        _notice = outcome.notice;
      }
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
                  const SizedBox(height: 8),
                  // 面板高度接近整頁，補明確的關閉鍵（2026-08-16 Bruce 回饋：
                  // 「沒有上一頁」）；下滑手勢仍可關。
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '我已有草稿，幫我修自然',
                          style: AppTypography.titleLarge.copyWith(
                            color: AppColors.onBackgroundPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('draft-polish-close'),
                        icon: const Icon(Icons.close_rounded),
                        color: AppColors.onBackgroundSecondary,
                        tooltip: '關閉',
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ],
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
                      // 打完往下滑就收鍵盤（聊天視窗慣例，同練習室）。
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      children: [
                        // 輸入列配方對齊練習室（2026-08-16 Bruce 回饋）：
                        // 白 12% 框底＋白 18% 框線＋聚焦橘框與橘色瞬態光暈、
                        // 失焦中性黑陰影分層。
                        ListenableBuilder(
                          listenable: _draftFocusNode,
                          builder: (context, child) => AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: _draftFocusNode.hasFocus
                                  ? [
                                      BoxShadow(
                                        color: AppColors.ctaStart
                                            .withValues(alpha: 0.22),
                                        blurRadius: 14,
                                        offset: const Offset(0, 3),
                                      ),
                                    ]
                                  : [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.18),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                            ),
                            child: child,
                          ),
                          child: TextField(
                            key: const ValueKey('draft-polish-input'),
                            controller: widget.draftController,
                            focusNode: _draftFocusNode,
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
                                    .withValues(alpha: 0.85),
                              ),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.18),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.18),
                                ),
                              ),
                              focusedBorder: const OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.all(Radius.circular(18)),
                                borderSide: BorderSide(
                                  color: AppColors.ctaStart,
                                  width: 1.4,
                                ),
                              ),
                            ),
                            onTapOutside: (_) => _draftFocusNode.unfocus(),
                            // 改了草稿就收掉上一輪的擋下說明。
                            onChanged: (_) => setState(() => _notice = null),
                          ),
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
                        if (_notice != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            key: const ValueKey('draft-polish-notice'),
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color:
                                    AppColors.warning.withValues(alpha: 0.30),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.info_outline_rounded,
                                  size: 18,
                                  color: AppColors.warning,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _notice!,
                                    style: AppTypography.bodySmall.copyWith(
                                      color: AppColors.onBackgroundPrimary,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (result != null &&
                            result.optimized.trim().isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              const Icon(TablerIcons.sparkles, size: 18, color: AppColors.ctaStart),
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
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(TablerIcons.bulb,
                                    size: 14, color: AppColors.warning),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    result.reason,
                                    style: AppTypography.caption.copyWith(
                                      color: AppColors.onBackgroundPrimary,
                                    ),
                                  ),
                                ),
                              ],
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
