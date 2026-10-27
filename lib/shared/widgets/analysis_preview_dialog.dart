// lib/shared/widgets/analysis_preview_dialog.dart
//
// ADR #19 r3 分析前預覽：
// - standard 帶（≤2000 字）：顯示算出的精確則數（Eric 2026-10-18：算法跟伺服器
//   對拍過，不再只報「1–10 則」的區間；分析後照樣顯示 server 實扣）。
// - overcharge 帶（2001~4000 字）：本 dialog 即是「>2000 字確認框」，
//   顯示精確「本次將使用 20 則」。額度檢查先於確認（定案 #4）：額度不足
//   時 caller 已走額度不足路徑，這裡的 canProceed 只是防禦層。
// - reject 帶（4001+）：caller 在呼叫本 dialog 前就擋下，不會進來。
// - [AnalysisQuotaLine]：額度夠、又是一般長度時不跳本 dialog，改在分析鈕旁寫一行。
// - 只分析最後 2000 字（Onboarding 第 15 步）：overcharge 帶付不起、最後那段付得起時
//   多一顆鈕；最後那段由 caller 截好、則數一起給。
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/services/message_calculator.dart';
import '../../core/services/usage_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/services/app_haptics.dart';
import '../../features/subscription/presentation/quota_copy.dart';

/// 額度夠、又是一般長度（≤2000 字、最多 10 則）時不跳確認框，分析鈕旁改寫一行
/// 「這次會用 N 則，剩 M 則」（Eric 2026-10-18）。超過 2000 字或額度不夠照舊跳框。
class AnalysisQuotaLine {
  const AnalysisQuotaLine._({
    required this.units,
    required this.remainingAfter,
  });

  /// 這次會用幾則（跟確認框同一個算法）。
  final int units;

  /// 用完之後剩幾則：本月、今日取少的。先別回、停也照字數扣；只有關心、未成年說明
  /// 不扣，實際只會一樣或更多（照 Bruce 10/18，Eric 2026-10-19）。
  final int remainingAfter;

  String get text => '這次會用 $units 則，剩 $remainingAfter 則';

  /// 按下去時重算的這一行跟畫面上那一行兩個數字都一樣，才算同一件事（主審 r1 P2：
  /// 不一樣就照舊跳確認框，不論多算還是少算）。
  @override
  bool operator ==(Object other) =>
      other is AnalysisQuotaLine &&
      other.units == units &&
      other.remainingAfter == remainingAfter;

  @override
  int get hashCode => Object.hash(units, remainingAfter);

  /// null＝要跳確認框（超過 2000 字、或額度不夠）。
  static AnalysisQuotaLine? of(
    MessagePreview preview, {
    required int monthlyRemaining,
    required int dailyRemaining,
  }) {
    if (preview.band.kind != BillingBandKind.standard) return null;
    final units = preview.band.units ?? 0;
    final remaining = math.min(monthlyRemaining, dailyRemaining);
    if (units <= 0 || remaining < units) return null;
    return AnalysisQuotaLine._(units: units, remainingAfter: remaining - units);
  }
}

/// Dialog shown before analysis to preview billed usage.
class AnalysisPreviewDialog extends StatelessWidget {
  final MessagePreview preview;
  final UsageData usage;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final VoidCallback? onUpgrade;

  /// 只分析最後 2000 字要用幾則（Onboarding 第 15 步）；null＝沒有這個選項（例如
  /// 她最後一則就超過 2000 字）。
  final int? tailUnits;
  final VoidCallback? onAnalyzeTail;

  static const tailButtonKey = ValueKey('analysis-preview-analyze-tail');

  const AnalysisPreviewDialog({
    super.key,
    required this.preview,
    required this.usage,
    required this.onConfirm,
    required this.onCancel,
    this.onUpgrade,
    this.tailUnits,
    this.onAnalyzeTail,
  });

  bool get _isOvercharge => preview.band.kind == BillingBandKind.overcharge;

  int get _requiredUnits => preview.band.units ?? 0;

  /// 只在超過 2000 字、這次付不起，而且最後那段付得起時才給「只分析最後 2000 字」。
  bool _showsTailOption({required bool canProceed}) {
    final units = tailUnits;
    return _isOvercharge &&
        !canProceed &&
        onAnalyzeTail != null &&
        units != null &&
        units > 0 &&
        usage.monthlyRemaining >= units &&
        usage.dailyRemaining >= units;
  }

  @override
  Widget build(BuildContext context) {
    // 額度檢查與顯示都用實際算出的則數（定案 #4）。
    final canProceed = preview.band.kind != BillingBandKind.reject &&
        usage.monthlyRemaining >= _requiredUnits &&
        usage.dailyRemaining >= _requiredUnits;
    final showsTailOption = _showsTailOption(canProceed: canProceed);
    // 額度不夠的說法照目前方案（Eric 2026-10-18）：Essential 已經是最高方案，不叫他
    // 升級，只說什麼時候恢復（跟付費頁大標同一句），鈕也只寫「查看方案」。
    final canUpgrade = canUpgradeQuota(usage.tier);

    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        _isOvercharge ? '內容較長，確認後才會扣' : '開始分析前',
        style: AppTypography.titleLarge,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isOvercharge) ...[
            _buildRow('本次將使用', '$_requiredUnits 則'),
            const SizedBox(height: 12),
            _buildRow('新增內容長度', '約 ${preview.billableChars} 字'),
          ] else
            _buildRow('預計使用', '$_requiredUnits 則'),
          const SizedBox(height: 12),
          _buildRow(
            '本月剩餘',
            '${usage.monthlyRemaining} / ${usage.monthlyLimit} 則',
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: usage.monthlyPercentage,
            backgroundColor: AppColors.surfaceVariant,
            valueColor: AlwaysStoppedAnimation<Color>(
              usage.monthlyPercentage > 0.8
                  ? AppColors.warning
                  : AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          _buildRow(
            '今日剩餘',
            '${usage.dailyRemaining} / ${usage.dailyLimit} 則',
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: usage.dailyPercentage,
            backgroundColor: AppColors.surfaceVariant,
            valueColor: AlwaysStoppedAnimation<Color>(
              usage.dailyPercentage > 0.8
                  ? AppColors.warning
                  : AppColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          // 先講需要幾則、剩幾則，再講什麼時候恢復，能升級的方案才補升級（Onboarding
          // 第 3 步）。台灣早上 8 點恢復：凌晨不夠時當天早上就有，不說「明天」；跟額度卡
          // 同一句（主審第 1 輪 P3）。扣的是「則」，不寫「次數」。
          if (usage.monthlyRemaining < _requiredUnits)
            _buildWarning(
              '這個月的額度不夠這次用（需要 $_requiredUnits 則，'
              '剩 ${usage.monthlyRemaining} 則）。'
              '${quotaNextStepLine(tier: usage.tier, isMonthly: true)}。',
            )
          else if (usage.dailyRemaining < _requiredUnits)
            _buildWarning(
              '今天的額度不夠這次用（需要 $_requiredUnits 則，'
              '剩 ${usage.dailyRemaining} 則）。'
              '${quotaNextStepLine(tier: usage.tier, isMonthly: false)}。',
            ),
          const SizedBox(height: 12),
          if (_isOvercharge)
            Text(
              '新增內容超過 2000 字，本次分析會一次使用 20 則。'
              '分批分析（每批 2000 字以內，各 10 則）合計也是 20 則，'
              '不會比較貴；不過內容太長時分批分析的品質通常更好。',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            )
          else
            // 「重新分析會用目前整段對話…」說明已拆（2026-08-16 Bruce 回饋）。
            Text(
              '只有送出完整分析才會扣額度。先讀截圖、不做完整分析，不會扣額度。'
              '分析完成後會顯示實際使用的則數。',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
          if (showsTailOption) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: tailButtonKey,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.28),
                  ),
                ),
                onPressed: AppHaptics.onPress(onAnalyzeTail),
                child: Text(
                  '只分析最後 2000 字（$tailUnits 則）',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: onCancel,
          child: const Text('取消'),
        ),
        if (!canProceed && onUpgrade != null)
          TextButton(
            onPressed: onUpgrade,
            child: Text(
              canUpgrade ? '查看升級方案' : '查看方案',
              style: TextStyle(color: AppColors.primary),
            ),
          ),
        ElevatedButton(
          onPressed: AppHaptics.onPress(canProceed ? onConfirm : null),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: Text(_isOvercharge ? '確認使用 $_requiredUnits 則' : '開始分析'),
        ),
      ],
    );
  }

  Widget _buildRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTypography.bodyMedium),
        Text(
          value,
          style: AppTypography.bodyMedium.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildWarning(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withAlpha(25),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.warning.withAlpha(77)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool> showAnalysisPreviewDialog({
  required BuildContext context,
  required MessagePreview preview,
  required UsageData usage,
  VoidCallback? onUpgrade,
  int? tailUnits,
  VoidCallback? onAnalyzeTail,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AnalysisPreviewDialog(
      preview: preview,
      usage: usage,
      onConfirm: () => Navigator.of(dialogContext).pop(true),
      onCancel: () => Navigator.of(dialogContext).pop(false),
      onUpgrade: onUpgrade,
      tailUnits: tailUnits,
      onAnalyzeTail: onAnalyzeTail,
    ),
  );
  return result ?? false;
}
