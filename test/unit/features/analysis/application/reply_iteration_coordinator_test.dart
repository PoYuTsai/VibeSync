// 取代 optimize_message_request_contract / reply_refine_entry_points 的
// source scan：以可執行行為釘住潤飾／微調的計費契約。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vibesync/features/analysis/application/analysis_run_preparer.dart';
import 'package:vibesync/features/analysis/application/reply_iteration_coordinator.dart';
import 'package:vibesync/features/analysis/data/services/analysis_service.dart';
import 'package:vibesync/features/analysis/data/services/optimize_message_request_session.dart';
import 'package:vibesync/features/analysis/data/services/reply_refine_draft_store.dart';
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

class _ThrowingDraftStore implements ReplyRefineDraftStore {
  @override
  Future<ReplyRefineDraft?> loadFor({
    required String ownerUserId,
    required String originText,
  }) async =>
      throw StateError('load failed');

  @override
  Future<void> save({
    required String ownerUserId,
    required String originText,
    required String refinedText,
    String? requestId,
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
  OptimizeMessageRequestIdSession session,
  ReplyRefineDraftStore draftStore,
}) _harness({
  Map<String, dynamic>? responseBody,
  ReplyRefineDraftStore? draftStore,
}) {
  final bodies = <Map<String, dynamic>>[];
  final client = AnalysisAuxiliaryClient(
    clientFactory: () => MockClient((request) async {
      bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
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
  final session = OptimizeMessageRequestIdSession(
    store: InMemoryOptimizeMessagePendingRequestStore(),
  );
  final resolvedDraftStore = draftStore ?? InMemoryReplyRefineDraftStore();
  return (
    coordinator: ReplyIterationCoordinator(
      session: session,
      draftStore: resolvedDraftStore,
      auxiliaryClient: client,
    ),
    bodies: bodies,
    session: session,
    draftStore: resolvedDraftStore,
  );
}

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
      final h = _harness(draftStore: _ThrowingDraftStore());
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
