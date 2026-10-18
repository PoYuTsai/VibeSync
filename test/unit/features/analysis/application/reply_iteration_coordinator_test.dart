// 取代 optimize_message_request_contract / reply_refine_entry_points 的
// source scan：以可執行行為釘住潤飾／微調的計費契約。走與 production
// 相同的 data adapter（OptimizeBillingAdapter／ReplyRefineDraftAdapter）
// 實作 application port，等於同時驗證 port adapter 的 exactly-once 語意。
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vibesync/features/analysis/application/analysis_run_preparer.dart';
import 'package:vibesync/features/analysis/application/reply_iteration_coordinator.dart';
import 'package:vibesync/features/analysis/application/ports/reply_refine_draft_port.dart';
import 'package:vibesync/features/analysis/data/services/analysis_service.dart';
import 'package:vibesync/features/analysis/data/services/optimize_billing_adapter.dart';
import 'package:vibesync/features/analysis/data/services/optimize_message_request_session.dart';
import 'package:vibesync/features/analysis/data/services/reply_refine_draft_adapter.dart';
import 'package:vibesync/features/analysis/data/services/reply_refine_draft_store.dart';
import 'package:vibesync/features/analysis/domain/entities/guide_v3_result.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

Message _msg(String content, {bool fromMe = false}) {
  return Message(
    id: content,
    content: content,
    isFromMe: fromMe,
    timestamp: DateTime(2026, 5, 28, 12, 0, 0),
  );
}

const Map<String, dynamic> _successBody = {
  'enthusiasm': {'score': 70, 'level': 'warm'},
  'gameStage': {'current': 'premise', 'status': 'normal', 'nextStep': '繼續'},
  'psychology': {'subtext': '有興趣', 'qualificationSignal': true},
  'topicDepth': {'current': 'personal', 'suggestion': '可深入'},
  'replies': {
    'extend': 'a',
    'resonate': 'b',
    'tease': 'c',
    'humor': 'd',
    'coldRead': 'e',
  },
  'finalRecommendation': {
    'pick': 'tease',
    'content': 'c',
    'reason': 'r',
    'psychology': 'p',
  },
  'strategy': '保持沉穩',
  'optimizedMessage': {
    'original': '要不要喝咖啡',
    'optimized': '這週要不要一起喝杯咖啡？',
    'improvements': ['更自然'],
  },
};

class _ThrowingDraftPort implements ReplyRefineDraftPort {
  @override
  Future<ReplyRefineDraftSnapshot?> loadFor({
    required String ownerUserId,
    required String originText,
    String? scope,
  }) async =>
      throw StateError('load failed');

  @override
  Future<void> save({
    required String ownerUserId,
    required String originText,
    required String refinedText,
    String? requestId,
    String? scope,
  }) async =>
      throw StateError('save failed');
}

const _context = AuxiliaryAnalysisContext(
  requestMessages: [],
  conversationSummary: null,
  partnerSummary: null,
  effectiveStyleContext: null,
  knownContactName: null,
);

AuxiliaryAnalysisContext _contextWith(List<Message> messages) {
  return AuxiliaryAnalysisContext(
    requestMessages: messages,
    conversationSummary: null,
    partnerSummary: null,
    effectiveStyleContext: null,
    knownContactName: null,
  );
}

({
  ReplyIterationCoordinator coordinator,
  List<Map<String, dynamic>> bodies,
}) _harness({
  Map<String, dynamic>? responseBody,
  ReplyRefineDraftPort? draftPort,
  List<http.Response>? responses,
  Future<void> Function()? beforeRespond,
}) {
  final bodies = <Map<String, dynamic>>[];
  final client = AnalysisAuxiliaryClient(
    clientFactory: () => MockClient((request) async {
      bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      // 有給 [beforeRespond] 就先等它：請求已經送到，回應還在路上。
      await beforeRespond?.call();
      // 有給 [responses] 就依序回給每一次請求。
      if (responses != null) return responses.removeAt(0);
      return http.Response(
        jsonEncode(responseBody ?? _successBody),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
    accessTokenProvider: () => 'fake-token',
    expectedTierProvider: () => null,
    revenueCatAppUserIdProvider: () async => null,
  );
  return (
    coordinator: ReplyIterationCoordinator(
      billing: OptimizeBillingAdapter(
        session: OptimizeMessageRequestIdSession(
          store: InMemoryOptimizeMessagePendingRequestStore(),
        ),
      ),
      draftStore: draftPort ??
          ReplyRefineDraftAdapter(store: InMemoryReplyRefineDraftStore()),
      optimizeDraft: client.optimizeDraft,
      refineReply: client.refineReply,
    ),
    bodies: bodies,
  );
}

/// 微調成功；[freeRemaining] 是伺服器帶回來的今天剩幾次免費（null＝沒帶）。
http.Response _refineOk({int? freeRemaining}) => http.Response(
      jsonEncode(Map<String, dynamic>.from(_successBody)
        ..['usage'] = {
          if (freeRemaining != null) 'refineFreeRemaining': freeRemaining,
          'shouldChargeQuota': false,
        }),
      200,
      headers: {'content-type': 'application/json'},
    );

/// 伺服器先用掉免費次數、結算才失敗（額度表沒有退款，已知取捨）。
http.Response _settlementFailed() => http.Response(
      jsonEncode({
        'error': 'OPTIMIZE_MESSAGE_SETTLEMENT_FAILED',
        'code': 'OPTIMIZE_MESSAGE_SETTLEMENT_FAILED',
      }),
      500,
      headers: {'content-type': 'application/json'},
    );

void main() {
  const owner = 'owner-1';

  group('runPolish — exactly-once 計費', () {
    test('wire 上帶 pending.requestId；acknowledge 前重跑沿用同一顆', () async {
      final h = _harness();
      final messages = [_msg('最近有空嗎？')];

      final first = await h.coordinator.runPolish(
        ownerUserId: owner,
        context: _contextWith(messages),
        sessionContext: null,
        draft: '要不要喝咖啡',
        onReadyToSend: () async => true,
        onTelemetry: (_) {},
      );
      expect(first, isNotNull);
      expect(h.bodies.single['requestId'], first!.pending.requestId);
      expect(h.bodies.single['userDraft'], '要不要喝咖啡');
      expect(
        h.coordinator.pendingAwaitingPresentation?.requestId,
        first.pending.requestId,
      );

      // 尚未 acknowledge（付費結果還沒被看到）：同一份輸入重跑必須 replay
      // 同一顆 requestId，不得鑄新身分再扣一次。
      final second = await h.coordinator.runPolish(
        ownerUserId: owner,
        context: _contextWith(messages),
        sessionContext: null,
        draft: '要不要喝咖啡',
        onReadyToSend: () async => true,
        onTelemetry: (_) {},
      );
      expect(second!.pending.requestId, first.pending.requestId);
      expect(h.bodies, hasLength(2));
      expect(h.bodies[1]['requestId'], first.pending.requestId);
    });

    test('acknowledgePolishPresented 之後才結案：pending 清空、下一輪鑄新身分', () async {
      final h = _harness();
      final messages = [_msg('最近有空嗎？')];
      final first = await h.coordinator.runPolish(
        ownerUserId: owner,
        context: _contextWith(messages),
        sessionContext: null,
        draft: '要不要喝咖啡',
        onReadyToSend: () async => true,
        onTelemetry: (_) {},
      );

      await h.coordinator.acknowledgePolishPresented(first!.pending);
      expect(h.coordinator.pendingAwaitingPresentation, isNull);

      final next = await h.coordinator.runPolish(
        ownerUserId: owner,
        context: _contextWith(messages),
        sessionContext: null,
        draft: '要不要喝咖啡',
        onReadyToSend: () async => true,
        onTelemetry: (_) {},
      );
      expect(next!.pending.requestId, isNot(first.pending.requestId));
    });

    test('身分不符的 acknowledge no-op：較新一輪的 pending 不被舊回呼清掉', () async {
      final h = _harness();
      final first = await h.coordinator.runPolish(
        ownerUserId: owner,
        context: _contextWith([_msg('hi')]),
        sessionContext: null,
        draft: '第一版',
        onReadyToSend: () async => true,
        onTelemetry: (_) {},
      );
      final second = await h.coordinator.runPolish(
        ownerUserId: owner,
        context: _contextWith([_msg('hi')]),
        sessionContext: null,
        draft: '第二版（不同 fingerprint）',
        onReadyToSend: () async => true,
        onTelemetry: (_) {},
      );
      expect(second!.pending.requestId, isNot(first!.pending.requestId));

      // 舊 pending 的可見幀回呼晚到：不得清掉新一輪的 awaiting 身分。
      await h.coordinator.acknowledgePolishPresented(first.pending);
      expect(
        h.coordinator.pendingAwaitingPresentation?.requestId,
        second.pending.requestId,
      );
    });

    test('onReadyToSend 拒絕：不送出、不鑄身分', () async {
      final h = _harness();
      final outcome = await h.coordinator.runPolish(
        ownerUserId: owner,
        context: _context,
        sessionContext: null,
        draft: '要不要喝咖啡',
        onReadyToSend: () async => false,
        onTelemetry: (_) {},
      );
      expect(outcome, isNull);
      expect(h.bodies, isEmpty);
      expect(h.coordinator.pendingAwaitingPresentation, isNull);
    });
  });

  group('runRefineRound — 指令入 fingerprint 與 durable 暫存順序', () {
    test('同一句話兩種指令用不同 requestId；指令與錨句都上 wire', () async {
      final h = _harness();
      final messages = [_msg('最近有空嗎？')];

      final shorter = await h.coordinator.runRefineRound(
        ownerUserId: owner,
        context: _contextWith(messages),
        sessionContext: null,
        currentText: '要不要喝咖啡',
        instruction: '短一點',
        anchorText: '原始那句話',
        onReadyToSend: () async => true,
        onTelemetry: (_) {},
      );
      final warmer = await h.coordinator.runRefineRound(
        ownerUserId: owner,
        context: _contextWith(messages),
        sessionContext: null,
        currentText: '要不要喝咖啡',
        instruction: '溫柔一點',
        anchorText: '原始那句話',
        onReadyToSend: () async => true,
        onTelemetry: (_) {},
      );

      expect(
        shorter!.pending.requestId,
        isNot(warmer!.pending.requestId),
        reason: '指令沒進 fingerprint 的話，第二種指令會 replay 出第一輪結果',
      );
      expect(h.bodies[0]['refineInstruction'], '短一點');
      expect(h.bodies[0]['refineAnchorText'], '原始那句話');
      expect(h.bodies[0]['requestId'], shorter.pending.requestId);
      expect(h.bodies[1]['refineInstruction'], '溫柔一點');
    });

    test('任務卡的再調：卡片規格上 wire、進 fingerprint；多則草稿用換行接著送', () async {
      final h = _harness(
        responseBody: Map<String, dynamic>.from(_successBody)
          ..['guideV3CardChecked'] = true,
      );
      final messages = [_msg('最近有空嗎？')];
      const spec = GuideV3RefineSpec(
        task: 'push',
        voice: 'default',
        method: 'reaction',
      );
      Future<RefineRoundResult?> round({GuideV3RefineSpec? card}) =>
          h.coordinator.runRefineRound(
            ownerUserId: owner,
            context: _contextWith(messages),
            sessionContext: null,
            currentText: '好啊\n那就週六',
            instruction: '更直接',
            anchorText: '好啊\n那就週六',
            onReadyToSend: () async => true,
            onTelemetry: (_) {},
            guideV3Card: card,
          );

      final v3 = await round(card: spec);
      final plain = await round();

      expect(h.bodies[0]['guideV3Card'], {
        'task': 'push',
        'voice': 'default',
        'method': 'reaction',
      });
      expect(h.bodies[0]['userDraft'], '好啊\n那就週六');
      expect(h.bodies[0]['refineInstruction'], '更直接');
      expect(h.bodies[1].containsKey('guideV3Card'), isFalse);
      expect(
        v3!.pending.requestId,
        isNot(plain!.pending.requestId),
        reason: '卡片規格會改伺服器的提示詞；伺服器 hash 不含規格，靠 fingerprint 分開 requestId',
      );
    });

    test('任務卡的再調：原稿有空格、結果沒照則留住空格就不給（舊版 Edge 把空格填掉）', () async {
      Map<String, dynamic> body(String optimized) =>
          Map<String, dynamic>.from(_successBody)
            ..['optimizedMessage'] = {
              'original': '原稿',
              'optimized': optimized,
            }
            ..['guideV3CardChecked'] = true;
      const spec = GuideV3RefineSpec(
        task: 'accept',
        voice: 'default',
        method: 'blank',
      );
      final messages = [_msg('你是做什麼的？')];

      Future<RefineRoundResult?> round(
        ({
          ReplyIterationCoordinator coordinator,
          List<Map<String, dynamic>> bodies,
        }) h,
        String currentText,
      ) =>
          h.coordinator.runRefineRound(
            ownerUserId: owner,
            context: _contextWith(messages),
            sessionContext: null,
            currentText: currentText,
            instruction: '自然一點',
            anchorText: currentText,
            onReadyToSend: () async => true,
            onTelemetry: (_) {},
            guideV3Card: spec,
          );

      // 空格被填成編的職業與興趣：不給採用，顯示既有的無效結果文案。
      final filled = _harness(responseBody: body('我是工程師\n週末常爬山'));
      await expectLater(
        round(filled, '我是＿＿\n週末常去＿＿'),
        throwsA(
          isA<AnalysisException>()
              .having((e) => e.code, 'code', 'OPTIMIZE_MESSAGE_RESULT_INVALID')
              .having((e) => e.message, 'message', '這次沒有調出可用的版本，請再試一次。'),
        ),
      );
      // 不換身分：同一份輸入再按一次，帶的還是同一顆 requestId（伺服器會 replay，不再扣）。
      await expectLater(
        round(filled, '我是＿＿\n週末常去＿＿'),
        throwsA(isA<AnalysisException>()),
      );
      expect(filled.bodies, hasLength(2));
      expect(filled.bodies[1]['requestId'], filled.bodies[0]['requestId']);

      // 總數一樣也不行：第一則的空格被填掉、第二則多一個。
      final moved = _harness(responseBody: body('我做設計\n住＿＿，週末去＿＿'));
      await expectLater(
        round(moved, '我做＿＿\n住＿＿'),
        throwsA(isA<AnalysisException>()),
      );

      // 每一則照原樣留住：照常給。
      final kept = _harness(responseBody: body('我做＿＿啦\n住＿＿附近'));
      final ok = await round(kept, '我做＿＿\n住＿＿');
      expect(ok!.refinedText, '我做＿＿啦\n住＿＿附近');
    });

    test('微調稿快取：任務卡（依規格）與一般微調各存各的，不會互相預選', () async {
      final draftPort =
          ReplyRefineDraftAdapter(store: InMemoryReplyRefineDraftStore());
      const push = GuideV3RefineSpec(
        task: 'push',
        voice: 'default',
        method: 'reaction',
      );
      const tension = GuideV3RefineSpec(
        task: 'tension',
        voice: 'default',
        method: 'reaction',
      );
      const origin = '星期六去喝咖啡';
      Future<void> round({
        required String optimized,
        GuideV3RefineSpec? card,
      }) async {
        final h = _harness(
          responseBody: Map<String, dynamic>.from(_successBody)
            ..['optimizedMessage'] = {
              'original': origin,
              'optimized': optimized,
            }
            ..['guideV3CardChecked'] = true,
          draftPort: draftPort,
        );
        await h.coordinator.runRefineRound(
          ownerUserId: owner,
          context: _contextWith([_msg('週末要幹嘛')]),
          sessionContext: null,
          currentText: origin,
          instruction: '短一點',
          anchorText: origin,
          onReadyToSend: () async => true,
          onTelemetry: (_) {},
          guideV3Card: card,
        );
      }

      // 一般微調存的稿（推進卡不能有的徵求同意問句）不會被任務卡讀到。
      await round(optimized: '星期六一起喝咖啡，好嗎？');
      final coordinator = _harness(draftPort: draftPort).coordinator;
      expect(
        await coordinator.restoreRefineDraft(
          ownerUserId: owner,
          originText: origin,
          guideV3Card: push,
        ),
        isNull,
      );
      expect(
        (await coordinator.restoreRefineDraft(
          ownerUserId: owner,
          originText: origin,
        ))
            ?.refinedText,
        '星期六一起喝咖啡，好嗎？',
      );

      // 任務卡存的稿只給同一個規格。
      await round(optimized: '星期六去喝咖啡，我來挑地方', card: push);
      expect(
        (await coordinator.restoreRefineDraft(
          ownerUserId: owner,
          originText: origin,
          guideV3Card: push,
        ))
            ?.refinedText,
        '星期六去喝咖啡，我來挑地方',
      );
      expect(
        await coordinator.restoreRefineDraft(
          ownerUserId: owner,
          originText: origin,
          guideV3Card: tension,
        ),
        isNull,
      );
      expect(
        (await coordinator.restoreRefineDraft(
          ownerUserId: owner,
          originText: origin,
        ))
            ?.refinedText,
        '星期六一起喝咖啡，好嗎？',
      );
    });

    test('任務卡的再調：伺服器沒標「已過任務卡檢查」（還沒升版的 Edge）就不給採用、不存稿、不換身分', () async {
      final draftPort =
          ReplyRefineDraftAdapter(store: InMemoryReplyRefineDraftStore());
      final h = _harness(
        responseBody: Map<String, dynamic>.from(_successBody)
          ..['optimizedMessage'] = {
            'original': '那就週六',
            'optimized': '那就週六，我來訂位',
          },
        draftPort: draftPort,
      );
      const spec = GuideV3RefineSpec(
        task: 'push',
        voice: 'default',
        method: 'reaction',
      );
      Future<RefineRoundResult?> round({GuideV3RefineSpec? card}) =>
          h.coordinator.runRefineRound(
            ownerUserId: owner,
            context: _contextWith([_msg('週末要幹嘛')]),
            sessionContext: null,
            currentText: '那就週六',
            instruction: '短一點',
            anchorText: '那就週六',
            onReadyToSend: () async => true,
            onTelemetry: (_) {},
            guideV3Card: card,
          );

      await expectLater(
        round(card: spec),
        throwsA(
          isA<AnalysisException>()
              .having((e) => e.code, 'code', 'OPTIMIZE_MESSAGE_RESULT_INVALID')
              .having((e) => e.message, 'message', '這次沒有調出可用的版本，請再試一次。'),
        ),
      );
      // 不換身分：再按一次帶的還是同一顆 requestId（伺服器 replay、不再扣）。
      await expectLater(round(card: spec), throwsA(isA<AnalysisException>()));
      expect(h.bodies, hasLength(2));
      expect(h.bodies[1]['requestId'], h.bodies[0]['requestId']);
      // 沒標記的結果不存成任務卡的稿。
      expect(
        await h.coordinator.restoreRefineDraft(
          ownerUserId: owner,
          originText: '那就週六',
          guideV3Card: spec,
        ),
        isNull,
      );
      // 一般微調不看這個標記。
      final plain = await round();
      expect(plain!.refinedText, '那就週六，我來訂位');
    });

    test('durable 暫存先落地才 restorable，restoreRefineDraft 讀得回同一版', () async {
      final h = _harness();
      final round = await h.coordinator.runRefineRound(
        ownerUserId: owner,
        context: _contextWith([_msg('hi')]),
        sessionContext: null,
        currentText: '要不要喝咖啡',
        instruction: '短一點',
        anchorText: '原始那句話',
        onReadyToSend: () async => true,
        onTelemetry: (_) {},
      );
      expect(round!.restorable, isTrue);
      final restored = await h.coordinator.restoreRefineDraft(
        ownerUserId: owner,
        originText: '原始那句話',
      );
      expect(restored?.refinedText, round.refinedText);
      expect(restored?.requestId, round.pending.requestId);
    });

    test('暫存寫入失敗：restorable=false（pending 保留走 replay），round 不炸', () async {
      final h = _harness(draftPort: _ThrowingDraftPort());
      final round = await h.coordinator.runRefineRound(
        ownerUserId: owner,
        context: _contextWith([_msg('hi')]),
        sessionContext: null,
        currentText: '要不要喝咖啡',
        instruction: '短一點',
        anchorText: '原始那句話',
        onReadyToSend: () async => true,
        onTelemetry: (_) {},
      );
      expect(round!.restorable, isFalse);
      expect(round.refinedText, '這週要不要一起喝杯咖啡？');
    });

    test('免費剩餘次數只信 server 回來的數字；沒帶就維持原值', () async {
      final withUsage = Map<String, dynamic>.from(_successBody)
        ..['usage'] = {
          'refineFreeRemaining': 2,
          'refineFreeDailyLimit': 3,
          'shouldChargeQuota': false,
        };
      final h = _harness(responseBody: withUsage);
      final round = await h.coordinator.runRefineRound(
        ownerUserId: owner,
        context: _contextWith([_msg('hi')]),
        sessionContext: null,
        currentText: '要不要喝咖啡',
        instruction: '短一點',
        anchorText: '原始那句話',
        onReadyToSend: () async => true,
        onTelemetry: (_) {},
      );
      expect(round!.freeRemaining, 2);
      expect(round.freeDailyLimit, 3);
      expect(round.chargedQuota, isFalse);
      expect(h.coordinator.refineFreeRemaining, 2);

      // 下一輪 server 沒帶 usage：本地不得自行遞減或亂猜。
      final h2 = _harness();
      expect(h2.coordinator.refineFreeRemaining, isNull);
    });

    test('一輪丟出例外：免費次數記成待確認，重開面板照樣標；之後成功帶回數字才清掉（主審第 1 輪 P2）', () async {
      final h = _harness(responses: [
        _refineOk(freeRemaining: 1),
        _settlementFailed(),
        _refineOk(),
        _refineOk(freeRemaining: 0),
      ]);
      Future<RefineRoundResult?> round(String instruction) =>
          h.coordinator.runRefineRound(
            ownerUserId: owner,
            context: _contextWith([_msg('hi')]),
            sessionContext: null,
            currentText: '要不要喝咖啡',
            instruction: instruction,
            anchorText: '要不要喝咖啡',
            onReadyToSend: () async => true,
            onTelemetry: (_) {},
          );

      await round('短一點');
      expect(h.coordinator.refineFreeRemaining, 1);
      expect(h.coordinator.refineFreeRemainingStale, isFalse);

      // 伺服器可能已用掉那次免費、結算才失敗：數字還在，但不再可信，也不自己減。
      await expectLater(round('白話一點'), throwsA(isA<AnalysisException>()));
      expect(h.coordinator.refineFreeRemainingStale, isTrue);
      expect(h.coordinator.refineFreeRemaining, 1);

      // 成功但沒帶數字：還是不知道剩幾次，維持待確認。
      await round('語氣溫和一點');
      expect(h.coordinator.refineFreeRemainingStale, isTrue);

      await round('太油了，自然一點');
      expect(h.coordinator.refineFreeRemaining, 0);
      expect(h.coordinator.refineFreeRemainingStale, isFalse);
      expect(h.bodies, hasLength(4));
    });

    test('取消（同意書拒絕、什麼都沒送）：待確認與否都維持原狀', () async {
      final h = _harness(responses: [_settlementFailed()]);
      Future<RefineRoundResult?> round({required bool consent}) =>
          h.coordinator.runRefineRound(
            ownerUserId: owner,
            context: _contextWith([_msg('hi')]),
            sessionContext: null,
            currentText: '要不要喝咖啡',
            instruction: '短一點',
            anchorText: '要不要喝咖啡',
            onReadyToSend: () async => consent,
            onTelemetry: (_) {},
          );

      expect(await round(consent: false), isNull);
      expect(h.coordinator.refineFreeRemainingStale, isFalse);

      await expectLater(
        round(consent: true),
        throwsA(isA<AnalysisException>()),
      );
      expect(h.coordinator.refineFreeRemainingStale, isTrue);

      expect(await round(consent: false), isNull);
      expect(h.coordinator.refineFreeRemainingStale, isTrue);
      expect(h.bodies, hasLength(1));
    });

    test('請求一送出就記成待確認（還在路上就關掉重開也標）；帶數字成功才清掉，沒帶數字維持，送出前取消不動（主審第 2 輪 P2）',
        () async {
      var arrived = Completer<void>();
      var release = Completer<void>();
      final h = _harness(
        responses: [
          _refineOk(freeRemaining: 1),
          _refineOk(),
          _refineOk(freeRemaining: 0),
        ],
        beforeRespond: () {
          arrived.complete();
          return release.future;
        },
      );
      Future<RefineRoundResult?> round(
        String instruction, {
        bool consent = true,
      }) =>
          h.coordinator.runRefineRound(
            ownerUserId: owner,
            context: _contextWith([_msg('hi')]),
            sessionContext: null,
            currentText: '要不要喝咖啡',
            instruction: instruction,
            anchorText: '要不要喝咖啡',
            onReadyToSend: () async => consent,
            onTelemetry: (_) {},
          );

      // 送出前取消（同意書拒絕）：什麼都沒送，不動它。
      expect(await round('短一點', consent: false), isNull);
      expect(h.coordinator.refineFreeRemainingStale, isFalse);
      expect(h.bodies, isEmpty);

      // 請求送到了、回應還沒回來：已經是待確認。
      var inFlight = round('短一點');
      await arrived.future;
      expect(h.coordinator.refineFreeRemainingStale, isTrue);
      release.complete();
      await inFlight;
      expect(h.coordinator.refineFreeRemaining, 1);
      expect(h.coordinator.refineFreeRemainingStale, isFalse);

      // 成功但沒帶數字：送出時記的待確認維持。
      arrived = Completer<void>();
      release = Completer<void>();
      inFlight = round('白話一點');
      await arrived.future;
      expect(h.coordinator.refineFreeRemainingStale, isTrue);
      release.complete();
      await inFlight;
      expect(h.coordinator.refineFreeRemainingStale, isTrue);

      // 已經是待確認時送出前取消：維持待確認。
      expect(await round('語氣溫和一點', consent: false), isNull);
      expect(h.coordinator.refineFreeRemainingStale, isTrue);

      // 帶數字成功才清掉。
      arrived = Completer<void>();
      release = Completer<void>();
      inFlight = round('太油了，自然一點');
      await arrived.future;
      release.complete();
      await inFlight;
      expect(h.coordinator.refineFreeRemaining, 0);
      expect(h.coordinator.refineFreeRemainingStale, isFalse);
      expect(h.bodies, hasLength(3));
    });

    test('acknowledgeRefinePresented 結案後，同輸入下一輪鑄新身分', () async {
      final h = _harness();
      final round = await h.coordinator.runRefineRound(
        ownerUserId: owner,
        context: _contextWith([_msg('hi')]),
        sessionContext: null,
        currentText: '要不要喝咖啡',
        instruction: '短一點',
        anchorText: '原始那句話',
        onReadyToSend: () async => true,
        onTelemetry: (_) {},
      );
      await h.coordinator.acknowledgeRefinePresented(round!.pending);
      final next = await h.coordinator.runRefineRound(
        ownerUserId: owner,
        context: _contextWith([_msg('hi')]),
        sessionContext: null,
        currentText: '要不要喝咖啡',
        instruction: '短一點',
        anchorText: '原始那句話',
        onReadyToSend: () async => true,
        onTelemetry: (_) {},
      );
      expect(next!.pending.requestId, isNot(round.pending.requestId));
    });
  });

  group('refineCopyEventId — 微調後複製記成獨立事件', () {
    test('帶原卡 adviceId 與這一輪 requestId（冪等鍵）', () {
      expect(
        ReplyIterationCoordinator.refineCopyEventId(
          originAdviceId: 'analyze:conv:run:final',
          requestId: 'req-1',
        ),
        'refine:analyze:conv:run:final:req-1',
      );
    });

    test('沒有穩定冪等鍵就不記', () {
      expect(
        ReplyIterationCoordinator.refineCopyEventId(
          originAdviceId: null,
          requestId: 'req-1',
        ),
        isNull,
      );
      expect(
        ReplyIterationCoordinator.refineCopyEventId(
          originAdviceId: 'analyze:conv:run:final',
          requestId: null,
        ),
        isNull,
      );
      expect(
        ReplyIterationCoordinator.refineCopyEventId(
          originAdviceId: 'analyze:conv:run:final',
          requestId: '',
        ),
        isNull,
      );
    });
  });
}
