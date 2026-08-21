import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _runnerPath =
    'lib/features/analysis/data/services/optimize_request_runner.dart';
const _screenPath =
    'lib/features/analysis/presentation/screens/analysis_screen.dart';

void main() {
  test('共用 runner 的 exactly-once 順序：先找回、才鑄身分、才送出', () {
    final source = File(_runnerPath).readAsStringSync();
    final methodStart = source.indexOf('Future<OptimizeRunOutcome<T>> run<T>(');
    expect(methodStart, greaterThanOrEqualTo(0));
    final method = source.substring(methodStart);

    final findPending = method.indexOf('_session.findPending(');
    final beginAttempt = method.indexOf('_session.beginAttempt(');
    final apiCall = method.indexOf('await send(pending)');
    expect(findPending, greaterThanOrEqualTo(0));
    expect(beginAttempt, greaterThan(findPending));
    expect(apiCall, greaterThan(beginAttempt));

    // 被伺服器否認的身分必須清掉，否則之後每次重試都送同一個死 requestId。
    final resetCall = method.indexOf('_session.reset(pending)');
    expect(resetCall, greaterThan(apiCall));
    expect(
      source.indexOf("'INVALID_OPTIMIZE_MESSAGE_REQUEST_ID',"),
      greaterThanOrEqualTo(0),
    );
    expect(
      source.indexOf("'OPTIMIZE_MESSAGE_REQUEST_REPLAY_MISMATCH',"),
      greaterThanOrEqualTo(0),
    );

    // runner 不得自己收尾；收尾是呼叫端在畫面畫出付費結果後的責任。
    expect(source.contains('_session.markSuccess'), isFalse);
  });

  test('草稿潤飾跨手動重試沿用 requestId，成功後才結束請求', () {
    final source = File(_screenPath).readAsStringSync();
    // 2026-08-16 面板化：_optimizeMessage 改名 _polishDraft，改回傳結果
    // 給 DraftPolishSheet 顯示；同日改回傳 DraftPolishOutcome（擋下說明
    // 留在面板上）。計費順序契約不變。
    final methodStart =
        source.indexOf('Future<DraftPolishOutcome?> _polishDraft(');
    final methodEnd = source.indexOf(
      'Future<void> _openDraftPolishSheet()',
      methodStart,
    );
    expect(methodStart, greaterThanOrEqualTo(0));
    expect(methodEnd, greaterThan(methodStart));
    final method = source.substring(methodStart, methodEnd);

    final runnerCall =
        method.indexOf('_optimizeRequestRunner.run<AnalysisResult>(');
    final apiCall = method.indexOf('AnalysisAuxiliaryClient().optimizeDraft(');
    final requestIdWire = method.indexOf('requestId: pending.requestId,');
    final presented =
        method.indexOf('_clearOptimizePendingAfterVisibleFrame(pending)');
    expect(runnerCall, greaterThanOrEqualTo(0));
    expect(apiCall, greaterThan(runnerCall));
    expect(requestIdWire, greaterThan(apiCall));
    expect(presented, greaterThan(requestIdWire));

    // markSuccess 只能發生在畫面確實呈現付費結果之後。
    final clearStart =
        source.indexOf('Future<void> _clearOptimizePendingAfterVisibleFrame(');
    expect(clearStart, greaterThanOrEqualTo(0));
    final clearBody = source.substring(clearStart, clearStart + 1200);
    final routeGuard =
        clearBody.indexOf('ModalRoute.of(context)?.isCurrent !=');
    final markSuccess =
        clearBody.indexOf('_optimizeRequestSession.markSuccess(pending);');
    expect(routeGuard, greaterThanOrEqualTo(0));
    expect(markSuccess, greaterThan(routeGuard));

    expect(source, contains('HiveOptimizeMessagePendingRequestStore('));
    expect(source, contains('() => StorageService.settingsBox'));
  });

  test('草稿潤飾已對全方案開放：畫面不得再出現付費閘門文案', () {
    final source = File(_screenPath).readAsStringSync();
    expect(source.contains('草稿潤飾器是 Essential 功能'), isFalse);
    expect(source.contains('新的潤飾仍需 Essential'), isFalse);
    expect(source.contains('新的草稿潤飾需要 Essential'), isFalse);
    expect(source.contains('恢復已付結果'), isFalse);
  });

  test('草稿潤飾在操作前明示成功固定使用一則', () {
    // 2026-08-16 面板化：揭露文案跟著輸入框搬進 DraftPolishSheet。
    final sheetSource = File(
      'lib/features/analysis/presentation/widgets/draft_polish_sheet.dart',
    ).readAsStringSync();
    expect(sheetSource, contains('成功完成使用 1 則'));
  });
}
