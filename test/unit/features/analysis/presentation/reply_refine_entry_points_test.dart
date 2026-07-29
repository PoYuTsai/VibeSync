import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _screenPath =
    'lib/features/analysis/presentation/screens/analysis_screen.dart';

void main() {
  late String source;

  setUpAll(() => source = File(_screenPath).readAsStringSync());

  test('三個入口都接上「再調一下」', () {
    // AI 推薦回覆：單段、舊 ①② 段落、結構化分段三種渲染路徑都要有。
    expect(source, contains('_buildRefineButton(content)'));
    expect(source, contains('_buildRefineButton(replyText)'));
    expect(source, contains('_buildRefineButton(reply)'));
    // 五張風格卡。
    expect(source, contains('onRefine: (text) => unawaited(_refineReply('));
    // 草稿潤飾結果可以續調：複製草稿與 polish 追蹤列之間要有微調按鈕。
    final copyDraftAt = source.indexOf("label: const Text('複製草稿')");
    final polishOutcomeBarAt = source.indexOf("cardKey: 'polish',", copyDraftAt);
    expect(copyDraftAt, greaterThanOrEqualTo(0));
    expect(polishOutcomeBarAt, greaterThan(copyDraftAt));
    expect(
      source.substring(copyDraftAt, polishOutcomeBarAt),
      contains('_buildRefineButton('),
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
    final methodStart = source.indexOf(
      'Future<void> _refineReply({required String originText}) async {',
    );
    expect(methodStart, greaterThanOrEqualTo(0));
    final method = source.substring(methodStart, methodStart + 5000);

    final fingerprint = method.indexOf('fingerprintFor(');
    final runnerCall = method.indexOf('_optimizeRequestRunner.run<AnalysisResult>(');
    final send = method.indexOf('analyzeConversation(');
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

  test('免費剩餘次數只信 server 回來的數字', () {
    expect(source, contains("usage['refineFreeRemaining']"));
    // client 不自己遞減：面板顯示的次數和真正扣費的帳本必須是同一本。
    expect(source.contains('_refineFreeRemaining--'), isFalse);
    expect(source.contains('_refineFreeRemaining -= '), isFalse);
  });
}
