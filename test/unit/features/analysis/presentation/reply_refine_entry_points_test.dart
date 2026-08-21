import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _screenPath =
    'lib/features/analysis/presentation/screens/analysis_screen.dart';
const _coordinatorPath =
    'lib/features/analysis/application/reply_iteration_coordinator.dart';

void main() {
  late String source;

  setUpAll(() => source = File(_screenPath).readAsStringSync());

  test('三個入口都接上「再調一下」', () {
    // AI 推薦回覆：單段、舊 ①② 段落、結構化分段三種渲染路徑都要有。
    expect(source,
        contains("_buildRefineButton(content, originCardKey: 'final')"));
    expect(
      source,
      contains("_buildRefineButton(replyText, originCardKey: 'final')"),
    );
    expect(
        source, contains("_buildRefineButton(reply, originCardKey: 'final')"));
    // 五張風格卡：來源卡別就是風格 type。
    expect(
      source,
      contains('_refineReply(originText: text, originCardKey: type)'),
    );
    // 草稿潤飾結果可以續調：2026-08-16 面板化後，「再調一下」按鈕
    // 畫在 DraftPolishSheet，onRefine 接回本畫面的 _refineReply。
    expect(
      source,
      contains("_refineReply(originText: text, originCardKey: 'polish')"),
    );
    final sheetSource = File(
      'lib/features/analysis/presentation/widgets/draft_polish_sheet.dart',
    ).readAsStringSync();
    final refineButtonAt = sheetSource.indexOf("Text('再調一下'");
    expect(refineButtonAt, greaterThanOrEqualTo(0));
    expect(
      sheetSource.substring(0, refineButtonAt),
      contains('widget.onRefine(result.optimized)'),
    );
  });

  test('整組合併的文字不給微調', () {
    // 「複製整組訊息」按鈕後面不得跟著微調按鈕：整組的「短一點」語意不清，
    // 多輪迭代還會撞到 server 的 userDraft 長度上限。
    final allCopyAt = source.indexOf("_copyRecommendationText(allContent");
    expect(allCopyAt, greaterThanOrEqualTo(0));
    final tail = source.substring(allCopyAt, allCopyAt + 600);
    expect(tail.contains('_buildRefineButton'), isFalse);
  });

  test('微調每一輪都走共用 runner，指令同時進 fingerprint 與 payload', () {
    // Work B：一輪微調的計費編排移入 ReplyIterationCoordinator。
    final coordinator = File(_coordinatorPath).readAsStringSync();
    final methodStart =
        coordinator.indexOf('Future<RefineRoundResult?> runRefineRound(');
    expect(methodStart, greaterThanOrEqualTo(0));
    final method = coordinator.substring(methodStart);

    final fingerprint = method.indexOf('fingerprintFor(');
    final runnerCall = method.indexOf('_runner.run<AnalysisResult>(');
    final send = method.indexOf('AnalysisAuxiliaryClient().refineReply(');
    expect(fingerprint, greaterThanOrEqualTo(0));
    expect(runnerCall, greaterThan(fingerprint));
    expect(send, greaterThan(runnerCall));

    // 指令沒進 fingerprint 的話，同一句話的兩種不同微調會共用同一顆
    // requestId，第二次會 replay 出第一次的結果。
    final fingerprintBlock = method.substring(fingerprint, runnerCall);
    expect(fingerprintBlock, contains('refineInstruction: instruction'));
    expect(
      method.substring(send, send + 900),
      contains('refineInstruction: instruction'),
    );
    expect(
      method.substring(send, send + 900),
      contains('requestId: pending.requestId'),
    );
  });

  test('微調後複製記成獨立事件，不覆寫原卡的 adviceId', () {
    final methodStart = source.indexOf('Future<void> _recordRefineCopy(');
    expect(methodStart, greaterThanOrEqualTo(0));
    final method = source.substring(methodStart, methodStart + 1600);

    // 事件 key 帶原卡 adviceId 與這一輪的 requestId（冪等鍵）。
    expect(method, contains(r"'refine:$originAdviceId:$requestId'"));
    expect(method, contains(r"adviceType: 'refine:$originCardKey'"));
    // eventId 與 adviceId 都用微調自己的 key，絕不落回原卡。
    expect(method, contains('eventId: eventId'));
    expect(method, contains('adviceId: eventId'));
    // 沒有穩定冪等鍵就不記。
    expect(method, contains('requestId.isEmpty'));

    // 採用微調版本後不得再走原卡的複製記錄，否則 suggestedMoveSummary 會被
    // 覆寫成微調後的句子，digest 回注 coach prompt 時就會說錯話。
    final refineStart = source.indexOf('Future<void> _refineReply(');
    final refineEnd = source.indexOf('Future<void> _recordRefineCopy(');
    expect(refineEnd, greaterThan(refineStart));
    expect(
      source.substring(refineStart, refineEnd).contains('_recordAnalysisCopy('),
      isFalse,
    );
  });

  test('先存得回來，才清掉付費身分', () {
    // 面板是可下滑關閉的 route：使用者可能在等待中就關掉它，結果回來時根本
    // 沒被看到。本機暫存是唯一還能把已付費結果接回來的東西，所以順序必須是
    // 「存檔成功 → markSuccess」。反過來寫且存檔失敗，requestId 就永久消失，
    // 下一次只能鑄新的再扣一次。
    final coordinator = File(_coordinatorPath).readAsStringSync();
    final methodStart =
        coordinator.indexOf('Future<RefineRoundResult?> runRefineRound(');
    expect(methodStart, greaterThanOrEqualTo(0));
    final method = coordinator.substring(methodStart);
    final save = method.indexOf('_draftStore.save(');
    expect(save, greaterThanOrEqualTo(0));
    // coordinator 先落地暫存並回報 restorable，畫面才在可見幀後 acknowledge。
    expect(method.substring(save, save + 400), contains('restorable = true'));

    final refineStart = source.indexOf('Future<void> _refineReply(');
    final refineEnd = source.indexOf('Future<void> _recordRefineCopy(');
    expect(refineStart, greaterThanOrEqualTo(0));
    expect(refineEnd, greaterThan(refineStart));
    final screenMethod = source.substring(refineStart, refineEnd);
    final mark = screenMethod.indexOf('_markRefinePendingAfterVisibleFrame(');
    expect(mark, greaterThanOrEqualTo(0));
    // 存檔失敗時必須跳過 markSuccess，讓 pending 留著走 replay。
    expect(
      screenMethod.substring(mark - 80, mark),
      contains('if (round.restorable)'),
    );
  });

  test('免費剩餘次數只信 server 回來的數字', () {
    final coordinator = File(_coordinatorPath).readAsStringSync();
    expect(coordinator, contains("usage['refineFreeRemaining']"));
    // client 不自己遞減：面板顯示的次數和真正扣費的帳本必須是同一本。
    expect(coordinator.contains('_refineFreeRemaining--'), isFalse);
    expect(coordinator.contains('_refineFreeRemaining -= '), isFalse);
    expect(source.contains('_refineFreeRemaining'), isFalse);
  });
}
