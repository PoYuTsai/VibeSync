import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('草稿潤飾跨手動重試沿用 requestId，成功後才結束請求', () {
    final source = File(
      'lib/features/analysis/presentation/screens/analysis_screen.dart',
    ).readAsStringSync();
    final methodStart = source.indexOf('Future<void> _optimizeMessage()');
    final methodEnd = source.indexOf('// ===== 分析輔助方法', methodStart);
    expect(methodStart, greaterThanOrEqualTo(0));
    expect(methodEnd, greaterThan(methodStart));
    final method = source.substring(methodStart, methodEnd);

    final beginAttempt =
        method.indexOf('await _optimizeRequestSession.beginAttempt');
    final findPending =
        method.indexOf('await _optimizeRequestSession.findPending');
    final entitlementPolicy = method.indexOf('canSendOptimizeMessageRequest(');
    final apiCall = method.indexOf('analysisService.analyzeConversation');
    final requestIdWire = method.indexOf('requestId: pending.requestId');
    final success =
        method.indexOf('_optimizeRequestSession.markSuccess(pending)');
    expect(findPending, inInclusiveRange(0, entitlementPolicy - 1));
    expect(entitlementPolicy, inInclusiveRange(0, beginAttempt - 1));
    expect(beginAttempt, inInclusiveRange(0, apiCall - 1));
    expect(requestIdWire, greaterThan(apiCall));
    expect(success, greaterThan(requestIdWire));

    expect(method, contains("e.code == 'INVALID_OPTIMIZE_MESSAGE_REQUEST_ID'"));
    expect(
      method,
      contains("e.code == 'OPTIMIZE_MESSAGE_REQUEST_REPLAY_MISMATCH'"),
    );
    expect(method, contains('_optimizeRequestSession.reset(optimizePending)'));
    expect(method, contains('ModalRoute.of(context)?.isCurrent != true'));
    expect(
      source,
      contains('HiveOptimizeMessagePendingRequestStore('),
    );
    expect(source, contains('() => StorageService.settingsBox'));
    expect(source, contains('恢復已付結果'));
    expect(source, contains('新的潤飾仍需 Essential'));
  });

  test('草稿潤飾在操作前明示成功固定使用一則', () {
    final source = File(
      'lib/features/analysis/presentation/screens/analysis_screen.dart',
    ).readAsStringSync();
    expect(source, contains('成功完成使用 1 則'));
  });
}
