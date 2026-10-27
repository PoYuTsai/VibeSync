// 只分析最後 2000 字（Onboarding 第 15 步）：從整段請求的最後往前累加、計費字數不超過
// 2000 字的最長尾段。計費字數跟伺服器同一套算法（MessageCalculator 與 billing.ts
// 對拍），送出時不帶上次的基準，伺服器算的就是尾段的字數，一定在 10 則以內。成功後的
// 字數基準照整段存，下次續析只算之後新增的字。
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/services/message_calculator.dart';
import 'package:vibesync/features/analysis/application/analysis_run_preparer.dart';
import 'package:vibesync/features/analysis/data/services/conversation_memory_adapter.dart';
import 'package:vibesync/features/analysis/domain/entities/previous_round_context.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/conversation/domain/entities/session_context.dart';
import 'package:vibesync/features/conversation/domain/services/conversation_content_revision.dart';

const _cap = MessageCalculator.softCapBandMaxChars;

/// 一則 [chars] 字的訊息（trim 後就是這個長度）。
Message _msg(String id, int chars, {bool fromMe = false}) => Message(
      id: id,
      content: '好' * chars,
      isFromMe: fromMe,
      timestamp: DateTime(2026, 10, 27, 12),
    );

AnalysisRunPreparer _preparer() => AnalysisRunPreparer(
      memory: ConversationMemoryAdapter(),
      resolvePartnerSummary: (_) => null,
      resolveEffectiveStyleContext: (_) => null,
    );

final _sessionContext = SessionContext(
  meetingContext: MeetingContext.datingApp,
  duration: AcquaintanceDuration.justMet,
);

const _previousRound = PreviousRoundContext(
  decision: 'send',
  light: 'green',
  judgment: '她在反問你',
  messages: [PreviousRoundMessage(isFromMe: false, content: '你呢')],
);

/// 整段請求：[messages] 照送，其他欄位填認得出來的值，看尾段有沒有原樣帶過去。
AnalysisRunPreparation _full(List<Message> messages, {int fragmentStart = 0}) =>
    AnalysisRunPreparation(
      requestMessages: messages,
      conversationSummary: '前面聊過週末去哪',
      partnerSummary: '對象卡摘要',
      effectiveStyleContext: null,
      knownContactName: '小雲',
      sessionContext: _sessionContext,
      conversationPartnerId: 'partner-1',
      isReconnectContext: false,
      previousStage: 'premise',
      analysisFragmentStartIndex: fragmentStart,
      analyzedMessageCount: messages.length + 2,
      contentRevision: 'rev-1',
      previousRound: _previousRound,
    );

List<String> _ids(List<Message> messages) => [for (final m in messages) m.id];

/// 送出時不帶上次的基準：伺服器算的計費字數。
int _billableChars(List<Message> messages) =>
    MessageCalculator.previewAnalysisRequest(messages).billableChars;

void main() {
  test('從尾端往前累加：取計費字數不超過 2000 字的最長尾段，其他欄位原樣帶過去', () {
    final messages = [for (var i = 1; i <= 5; i++) _msg('m$i', 600)];
    final full = _full(messages);

    final tail = _preparer().tailOnly(full)!;

    expect(_ids(tail.requestMessages), ['m3', 'm4', 'm5']);
    expect(_billableChars(tail.requestMessages), 1800);
    // 再往前加一則就超過。
    expect(_billableChars(messages.sublist(1)), greaterThan(_cap));
    expect(
      MessageCalculator.previewAnalysisRequest(tail.requestMessages).band.units,
      10,
    );
    expect(tail.isTailOnly, isTrue);
    expect(full.isTailOnly, isFalse);
    // 字數基準存整段的計費字數；訊息數基準、內容修訂跟整段一樣。
    expect(tail.fullRequestCharBaseline, 3000);
    expect(tail.analyzedMessageCount, full.analyzedMessageCount);
    expect(tail.contentRevision, full.contentRevision);
    expect(tail.analysisFragmentStartIndex, 0);
    expect(tail.conversationSummary, full.conversationSummary);
    expect(tail.partnerSummary, full.partnerSummary);
    expect(tail.knownContactName, full.knownContactName);
    expect(tail.sessionContext, same(_sessionContext));
    expect(tail.conversationPartnerId, full.conversationPartnerId);
    expect(tail.isReconnectContext, full.isReconnectContext);
    expect(tail.previousStage, full.previousStage);
    expect(tail.previousRound, same(_previousRound));
  });

  test('剛好 2000 字：算進去（不超過就收），落在 10 則、不用長內容確認', () {
    final messages = [_msg('a', 500), _msg('b', 1000), _msg('c', 1000)];

    final tail = _preparer().tailOnly(_full(messages))!;

    expect(_ids(tail.requestMessages), ['b', 'c']);
    expect(_billableChars(tail.requestMessages), _cap);
    final band = MessageCalculator.previewAnalysisRequest(
      tail.requestMessages,
    ).band;
    expect(band.kind, BillingBandKind.standard);
    expect(band.units, 10);
  });

  test('她最後一則剛好 2000 字：只送那一則', () {
    final tail =
        _preparer().tailOnly(_full([_msg('a', 600), _msg('b', _cap)]))!;

    expect(_ids(tail.requestMessages), ['b']);
  });

  test('她最後一則就超過 2000 字：不提供（不截斷她說的話）', () {
    final messages = [_msg('a', 600), _msg('b', 600), _msg('c', _cap + 1)];

    expect(_preparer().tailOnly(_full(messages)), isNull);
  });

  test('超長的那則在前面：尾段停在它後面，不跳過它去收更前面的', () {
    final messages = [
      _msg('a', 300),
      _msg('huge', 1900),
      _msg('b', 400),
      _msg('c', 500),
    ];

    final tail = _preparer().tailOnly(_full(messages))!;

    expect(_ids(tail.requestMessages), ['b', 'c']);
  });

  test('F04：她最後一則之後他傳的（上限內）照送、不算字數，尾段可以多收她的', () {
    final messages = [
      _msg('h1', 600),
      _msg('h2', 600),
      _msg('h3', 600),
      _msg('h4', 600),
      _msg('me', 200, fromMe: true),
    ];

    final tail = _preparer().tailOnly(_full(messages))!;

    expect(_ids(tail.requestMessages), ['h2', 'h3', 'h4', 'me']);
    expect(_billableChars(tail.requestMessages), 1800);
    // 整段的字數基準也照伺服器，不算最後面他傳的。
    expect(tail.fullRequestCharBaseline, 2400);
  });

  test('她最後一則之後他傳的超過 F04 上限（要算錢），連同她那則就超過：不提供', () {
    final messages = [
      _msg('a', 600),
      _msg('her', 1900),
      for (var i = 1; i <= 6; i++) _msg('me$i', 20, fromMe: true),
    ];

    expect(_preparer().tailOnly(_full(messages)), isNull);
  });

  test('整段本來就不超過 2000 字、沒有她的訊息、已經是尾段：不提供', () {
    final preparer = _preparer();
    expect(preparer.tailOnly(_full([_msg('a', 900), _msg('b', 900)])), isNull);
    expect(
      preparer.tailOnly(_full([
        _msg('me1', 1500, fromMe: true),
        _msg('me2', 1500, fromMe: true),
      ])),
      isNull,
    );
    final tail = preparer.tailOnly(
      _full([for (var i = 1; i <= 5; i++) _msg('m$i', 600)]),
    )!;
    expect(preparer.tailOnly(tail), isNull);
  });

  test('片段起點換成尾段裡的位置：起點在尾段裡照位置，在尾段之前就從頭', () {
    final messages = [for (var i = 1; i <= 5; i++) _msg('m$i', 600)];
    final preparer = _preparer();

    // 尾段是 m3–m5（整段第 2–4 則）。
    expect(
      preparer
          .tailOnly(_full(messages, fragmentStart: 3))!
          .analysisFragmentStartIndex,
      1,
    );
    expect(
      preparer
          .tailOnly(_full(messages, fragmentStart: 1))!
          .analysisFragmentStartIndex,
      0,
    );
  });

  test('續析基準：只分析最後那段之後，下次續析只算之後新增的字（跳過的不算、尾段不重算）', () {
    // 上次分析到 m1（600 字），之後又來了 m2–m6（3000 字）：整段要 20 則。
    final before = [for (var i = 1; i <= 6; i++) _msg('m$i', 600)];
    expect(
      MessageCalculator.previewAnalysisRequest(
        before,
        previousAnalyzedCharCount: 600,
      ).band.kind,
      BillingBandKind.overcharge,
    );

    final tail = _preparer().tailOnly(_full(before))!;
    expect(_ids(tail.requestMessages), ['m4', 'm5', 'm6']);
    expect(_billableChars(tail.requestMessages), 1800);
    expect(tail.fullRequestCharBaseline, 3600);

    // 成功後字數基準存整段的 3600；下次多了他一則、她一則各 50 字，只算這 100 字。
    final next = [...before, _msg('m7', 50, fromMe: true), _msg('m8', 50)];
    expect(
      MessageCalculator.previewAnalysisRequest(
        next,
        previousAnalyzedCharCount: tail.fullRequestCharBaseline!,
      ).billableChars,
      100,
    );
    // 對照：基準要是存成尾段的 1800，下次會多算 1800 字（上次分析過的 m1 加上跳過的
    // m2–m3），而且很容易又超過 2000 字。
    expect(
      MessageCalculator.previewAnalysisRequest(
        next,
        previousAnalyzedCharCount: 1800,
      ).billableChars,
      1900,
    );
  });

  test('從真的組好的請求截：訊息數基準是整段的則數，內容修訂不變', () async {
    final conversation = Conversation(
      id: 'tail-conv',
      name: '小雲',
      messages: [for (var i = 1; i <= 5; i++) _msg('m$i', 600)],
      createdAt: DateTime(2026, 10, 27),
      updatedAt: DateTime(2026, 10, 27),
    );
    final preparer = _preparer();
    final full = await preparer.assemble(
      conversation: conversation,
      gate: preparer.gate(conversation: conversation),
    );

    final tail = preparer.tailOnly(full)!;

    expect(_ids(tail.requestMessages), ['m3', 'm4', 'm5']);
    expect(tail.analyzedMessageCount, conversation.messages.length);
    expect(tail.contentRevision, conversationContentRevision(conversation));
    expect(tail.fullRequestCharBaseline, 3000);
  });
}
