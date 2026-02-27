// lib/features/analysis/presentation/widgets/analysis_error_widget.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// Error types for analysis failures
enum AnalysisErrorType {
  network,
  timeout,
  serverError,
  rateLimited,
  unsafeInput,
  unknown,
}

/// Widget showing analysis error with retry option
class AnalysisErrorWidget extends StatelessWidget {
  final AnalysisErrorType errorType;
  final String? message;
  final bool retryable;
  final VoidCallback? onRetry;

  const AnalysisErrorWidget({
    super.key,
    required this.errorType,
    this.message,
    this.retryable = true,
    this.onRetry,
  });

  /// Factory constructor from error code
  factory AnalysisErrorWidget.fromCode(
    String code, {
    String? message,
    VoidCallback? onRetry,
  }) {
    final type = _parseErrorCode(code);
    final retryable = _isRetryable(code);
    return AnalysisErrorWidget(
      errorType: type,
      message: message,
      retryable: retryable,
      onRetry: onRetry,
    );
  }

  static AnalysisErrorType _parseErrorCode(String code) {
    switch (code) {
      case 'RATE_LIMITED':
        return AnalysisErrorType.rateLimited;
      case 'SERVER_ERROR':
      case 'ALL_MODELS_FAILED':
        return AnalysisErrorType.serverError;
      case 'UNSAFE_INPUT':
        return AnalysisErrorType.unsafeInput;
      case 'TIMEOUT':
        return AnalysisErrorType.timeout;
      case 'NETWORK_ERROR':
        return AnalysisErrorType.network;
      default:
        return AnalysisErrorType.unknown;
    }
  }

  static bool _isRetryable(String code) {
    return code == 'RATE_LIMITED' ||
        code == 'SERVER_ERROR' ||
        code == 'ALL_MODELS_FAILED' ||
        code == 'TIMEOUT' ||
        code == 'NETWORK_ERROR';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.error.withAlpha(25), // ~0.1 opacity
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error.withAlpha(77)), // ~0.3 opacity
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Error icon
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.error.withAlpha(25),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _getIcon(),
              size: 32,
              color: AppColors.error,
            ),
          ),
          const SizedBox(height: 16),

          // Title
          Text(
            _getTitle(),
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.error,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),

          // Description
          Text(
            message ?? _getDefaultMessage(),
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),

          // Retry button
          if (retryable && onRetry != null) ...[
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重試'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _getIcon() {
    switch (errorType) {
      case AnalysisErrorType.network:
        return Icons.wifi_off;
      case AnalysisErrorType.timeout:
        return Icons.timer_off;
      case AnalysisErrorType.serverError:
        return Icons.cloud_off;
      case AnalysisErrorType.rateLimited:
        return Icons.hourglass_empty;
      case AnalysisErrorType.unsafeInput:
        return Icons.warning_amber;
      case AnalysisErrorType.unknown:
        return Icons.error_outline;
    }
  }

  String _getTitle() {
    switch (errorType) {
      case AnalysisErrorType.network:
        return '網路連線失敗';
      case AnalysisErrorType.timeout:
        return '請求逾時';
      case AnalysisErrorType.serverError:
        return 'AI 服務暫時無法使用';
      case AnalysisErrorType.rateLimited:
        return '服務繁忙';
      case AnalysisErrorType.unsafeInput:
        return '無法處理此內容';
      case AnalysisErrorType.unknown:
        return '發生錯誤';
    }
  }

  String _getDefaultMessage() {
    switch (errorType) {
      case AnalysisErrorType.network:
        return '請檢查網路連線後再試一次';
      case AnalysisErrorType.timeout:
        return 'AI 回應時間過長，請稍後再試';
      case AnalysisErrorType.serverError:
        return 'AI 服務暫時無法回應，請稍後再試';
      case AnalysisErrorType.rateLimited:
        return '請求過於頻繁，請稍後再試';
      case AnalysisErrorType.unsafeInput:
        return '偵測到不適當的內容，無法提供建議';
      case AnalysisErrorType.unknown:
        return '發生未知錯誤，請稍後再試';
    }
  }
}
