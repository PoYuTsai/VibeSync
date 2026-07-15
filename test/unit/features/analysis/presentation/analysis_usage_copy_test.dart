import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/presentation/helpers/analysis_usage_copy.dart';

void main() {
  group('buildAnalysisUsageChargeToast', () {
    test('optimize success says exactly one polish message', () {
      expect(
        buildAnalysisUsageChargeToast(
          const {'messagesUsed': 1, 'isTestAccount': false},
          actionLabel: '潤飾',
        ),
        '本次潤飾使用 1 則',
      );
    });

    test('idempotent replay and test account do not show a charge toast', () {
      expect(
        buildAnalysisUsageChargeToast(
          const {'messagesUsed': 0, 'isTestAccount': false},
          actionLabel: '潤飾',
        ),
        isNull,
      );
      expect(
        buildAnalysisUsageChargeToast(
          const {'messagesUsed': 1, 'isTestAccount': true},
          actionLabel: '潤飾',
        ),
        isNull,
      );
    });
  });
}
