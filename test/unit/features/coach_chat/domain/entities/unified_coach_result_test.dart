import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/coach_chat/domain/entities/coach_chat_result.dart';
import 'package:vibesync/features/coach_chat/domain/entities/unified_coach_result.dart';
import 'package:vibesync/features/coach_follow_up/domain/entities/coach_follow_up_result.dart';

const _testHivePath = './.dart_tool/test_hive_unified_coach_result';
const _testBoxName = 'test_unified_coach_results';

UnifiedCoachResult _fullResult() {
  return UnifiedCoachResult(
    id: 'u-1',
    conversationId: 'c-1',
    partnerId: 'p-1',
    question: '她是什麼意思？',
    mode: 'replyCraft',
    headline: '接住再反問',
    answer: '她是在丟觀察，不是要你證明自己。',
    userState: '你可能急著解釋。',
    nextStep: '先用一句反問接回去。',
    suggestedLine: '被妳發現了。妳也是亂逛派嗎？',
    boundaryReminder: '不要把一句觀察放大成壓力。',
    needsReflection: true,
    reflectionQuestion: '你希望她怎麼看你？',
    generatedAt: DateTime(2026, 7, 21, 12),
    provider: 'claude',
    modelUsed: 'claude-sonnet-5',
    responseType: 'clarifyingQuestion',
    sessionId: 's-1',
    userTruth: '我怕被句點。',
    rewriteDecision: 'rewritten',
    rewriteReason: '原句太像審問。',
    costDeducted: 2,
    frictionType: 'overexplain',
    earlierSummary: '之前聊過破冰。',
    earlierResultCount: 3,
    scopeType: 'conversation',
    scopeId: 'c-1',
    lifecyclePhase: 'warming',
  );
}

void main() {
  setUpAll(() {
    Hive.init(_testHivePath);
    if (!Hive.isAdapterRegistered(26)) {
      Hive.registerAdapter(UnifiedCoachResultAdapter());
    }
  });

  late Box<UnifiedCoachResult> box;

  setUp(() async {
    box = await Hive.openBox<UnifiedCoachResult>(_testBoxName);
  });

  tearDown(() async {
    await box.deleteFromDisk();
  });

  tearDownAll(() async {
    await Hive.close();
    final dir = Directory(_testHivePath);
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  group('UnifiedCoachResult Hive round-trip', () {
    test('writes and reads back every field (all populated)', () async {
      await box.put('u-1', _fullResult());
      final read = box.get('u-1')!;

      expect(read.id, 'u-1');
      expect(read.conversationId, 'c-1');
      expect(read.partnerId, 'p-1');
      expect(read.question, '她是什麼意思？');
      expect(read.mode, 'replyCraft');
      expect(read.headline, '接住再反問');
      expect(read.answer, '她是在丟觀察，不是要你證明自己。');
      expect(read.userState, '你可能急著解釋。');
      expect(read.nextStep, '先用一句反問接回去。');
      expect(read.suggestedLine, '被妳發現了。妳也是亂逛派嗎？');
      expect(read.boundaryReminder, '不要把一句觀察放大成壓力。');
      expect(read.needsReflection, isTrue);
      expect(read.reflectionQuestion, '你希望她怎麼看你？');
      expect(read.generatedAt, DateTime(2026, 7, 21, 12));
      expect(read.provider, 'claude');
      expect(read.modelUsed, 'claude-sonnet-5');
      expect(read.responseType, 'clarifyingQuestion');
      expect(read.sessionId, 's-1');
      expect(read.userTruth, '我怕被句點。');
      expect(read.rewriteDecision, 'rewritten');
      expect(read.rewriteReason, '原句太像審問。');
      expect(read.costDeducted, 2);
      expect(read.frictionType, 'overexplain');
      expect(read.earlierSummary, '之前聊過破冰。');
      expect(read.earlierResultCount, 3);
      expect(read.scopeType, 'conversation');
      expect(read.scopeId, 'c-1');
      expect(read.lifecyclePhase, 'warming');
    });

    test('writes and reads back nullable fields as null (partner scope)',
        () async {
      final result = UnifiedCoachResult(
        id: 'u-2',
        conversationId: null,
        question: '',
        mode: 'partnerFollowUp',
        headline: '推進約會',
        answer: '她最近回覆變快。',
        userState: '她最近回覆變快。',
        nextStep: '約她週末喝咖啡。',
        boundaryReminder: '不要連發追問。',
        needsReflection: false,
        generatedAt: DateTime(2026, 7, 20, 9),
        provider: 'legacy',
        modelUsed: 'claude-sonnet-5',
        scopeType: 'partner',
        scopeId: 'p-2',
      );
      await box.put('u-2', result);
      final read = box.get('u-2')!;

      expect(read.conversationId, isNull);
      expect(read.partnerId, isNull);
      expect(read.suggestedLine, isNull);
      expect(read.reflectionQuestion, isNull);
      expect(read.sessionId, isNull);
      expect(read.userTruth, isNull);
      expect(read.rewriteDecision, isNull);
      expect(read.rewriteReason, isNull);
      expect(read.earlierSummary, isNull);
      expect(read.lifecyclePhase, isNull);
      expect(read.scopeType, 'partner');
      expect(read.scopeId, 'p-2');
      // 預設值照舊。
      expect(read.responseType, 'coachAnswer');
      expect(read.costDeducted, 1);
      expect(read.frictionType, 'unclearIntent');
      expect(read.earlierResultCount, 0);
    });
  });

  group('UnifiedCoachResult getters and copyWith', () {
    test('isClarifyingQuestion / isCoachAnswer follow responseType', () {
      final clarifying = _fullResult();
      expect(clarifying.isClarifyingQuestion, isTrue);
      expect(clarifying.isCoachAnswer, isFalse);

      final answer = UnifiedCoachResult(
        id: 'u-3',
        question: 'q',
        mode: 'replyCraft',
        headline: 'h',
        answer: 'a',
        userState: 'u',
        nextStep: 'n',
        boundaryReminder: 'b',
        needsReflection: false,
        generatedAt: DateTime(2026, 7, 21),
        provider: 'claude',
        modelUsed: 'claude-sonnet-5',
        scopeType: 'conversation',
        scopeId: 'c-3',
      );
      expect(answer.isCoachAnswer, isTrue);
      expect(answer.isClarifyingQuestion, isFalse);
    });

    test('copyWith replaces earlierSummary/earlierResultCount only', () {
      final base = _fullResult();
      final copy = base.copyWith(
        earlierSummary: '新的摘要',
        earlierResultCount: 5,
      );

      expect(copy.earlierSummary, '新的摘要');
      expect(copy.earlierResultCount, 5);
      // 其餘欄位不變。
      expect(copy.id, base.id);
      expect(copy.conversationId, base.conversationId);
      expect(copy.scopeType, base.scopeType);
      expect(copy.scopeId, base.scopeId);
      expect(copy.lifecyclePhase, base.lifecyclePhase);
      expect(copy.responseType, base.responseType);
      expect(copy.costDeducted, base.costDeducted);
    });
  });

  group('UnifiedCoachResult legacy mapping factories', () {
    test('fromCoachChatResult keeps every field and sets conversation scope',
        () {
      final legacy = CoachChatResult(
        id: 'cc-1',
        conversationId: 'c-9',
        partnerId: 'p-9',
        question: '她是什麼意思？',
        mode: 'replyCraft',
        headline: '接住再反問',
        answer: '她是在丟觀察。',
        userState: '你可能急著解釋。',
        nextStep: '先用一句反問接回去。',
        suggestedLine: '被妳發現了。',
        boundaryReminder: '不要放大成壓力。',
        needsReflection: true,
        reflectionQuestion: '你希望她怎麼看你？',
        generatedAt: DateTime(2026, 7, 19, 8),
        provider: 'claude',
        modelUsed: 'claude-sonnet-5',
        responseType: 'clarifyingQuestion',
        sessionId: 's-9',
        userTruth: '我怕被句點。',
        rewriteDecision: 'rewritten',
        rewriteReason: '原句太像審問。',
        costDeducted: 2,
        frictionType: 'overexplain',
        earlierSummary: '之前聊過破冰。',
        earlierResultCount: 4,
      );

      final unified = UnifiedCoachResult.fromCoachChatResult(legacy);

      expect(unified.id, 'cc-1');
      expect(unified.conversationId, 'c-9');
      expect(unified.partnerId, 'p-9');
      expect(unified.question, '她是什麼意思？');
      expect(unified.mode, 'replyCraft');
      expect(unified.headline, '接住再反問');
      expect(unified.answer, '她是在丟觀察。');
      expect(unified.userState, '你可能急著解釋。');
      expect(unified.nextStep, '先用一句反問接回去。');
      expect(unified.suggestedLine, '被妳發現了。');
      expect(unified.boundaryReminder, '不要放大成壓力。');
      expect(unified.needsReflection, isTrue);
      expect(unified.reflectionQuestion, '你希望她怎麼看你？');
      expect(unified.generatedAt, DateTime(2026, 7, 19, 8));
      expect(unified.provider, 'claude');
      expect(unified.modelUsed, 'claude-sonnet-5');
      expect(unified.responseType, 'clarifyingQuestion');
      expect(unified.sessionId, 's-9');
      expect(unified.userTruth, '我怕被句點。');
      expect(unified.rewriteDecision, 'rewritten');
      expect(unified.rewriteReason, '原句太像審問。');
      expect(unified.costDeducted, 2);
      expect(unified.frictionType, 'overexplain');
      expect(unified.earlierSummary, '之前聊過破冰。');
      expect(unified.earlierResultCount, 4);
      expect(unified.scopeType, 'conversation');
      expect(unified.scopeId, 'c-9');
      expect(unified.lifecyclePhase, isNull);
    });

    // Task 4 Minor 1：conversation scope 送出 lifecyclePhase 時，本地卡
    // 也要保存同值（wire 送了、本地卡不得硬編 null）；不傳維持 null。
    test('fromCoachChatResult keeps lifecyclePhase when provided', () {
      final legacy = CoachChatResult(
        id: 'cc-2',
        conversationId: 'c-9',
        question: 'q',
        mode: 'replyCraft',
        headline: 'h',
        answer: 'a',
        userState: 'u',
        nextStep: 'n',
        boundaryReminder: 'b',
        needsReflection: false,
        generatedAt: DateTime(2026, 7, 22, 8),
        provider: 'claude',
        modelUsed: 'claude-sonnet-5',
      );

      final unified = UnifiedCoachResult.fromCoachChatResult(
        legacy,
        lifecyclePhase: 'warming',
      );
      expect(unified.lifecyclePhase, 'warming');

      final withoutPhase = UnifiedCoachResult.fromCoachChatResult(legacy);
      expect(withoutPhase.lifecyclePhase, isNull);
    });

    test('fromFollowUpResult maps card fields and sets partner scope', () {
      final legacy = CoachFollowUpResult(
        partnerId: 'p-7',
        phase: 'warming',
        headline: '推進約會',
        observation: '她最近回覆變快。',
        task: '約她週末喝咖啡。',
        suggestedLine: '週末要不要去那家咖啡店？',
        boundaryReminder: '不要連發追問。',
        generatedAt: DateTime(2026, 7, 18, 20),
        modelUsed: 'claude-sonnet-5',
      );

      final unified = UnifiedCoachResult.fromFollowUpResult(legacy);

      expect(unified.id, 'legacy-followup-p-7');
      expect(unified.scopeType, 'partner');
      expect(unified.scopeId, 'p-7');
      expect(unified.partnerId, 'p-7');
      expect(unified.conversationId, isNull);
      expect(unified.lifecyclePhase, 'warming');
      expect(unified.headline, '推進約會');
      // observation → userState 且 → answer。
      expect(unified.userState, '她最近回覆變快。');
      expect(unified.answer, '她最近回覆變快。');
      // task → nextStep。
      expect(unified.nextStep, '約她週末喝咖啡。');
      expect(unified.suggestedLine, '週末要不要去那家咖啡店？');
      expect(unified.boundaryReminder, '不要連發追問。');
      expect(unified.generatedAt, DateTime(2026, 7, 18, 20));
      expect(unified.modelUsed, 'claude-sonnet-5');
      // 合成常數。
      expect(unified.question, '');
      expect(unified.mode, 'partnerFollowUp');
      expect(unified.provider, 'legacy');
      expect(unified.needsReflection, isFalse);
      expect(unified.costDeducted, 0);
      // 其餘 nullable 欄位＝null，非 nullable 走預設。
      expect(unified.reflectionQuestion, isNull);
      expect(unified.sessionId, isNull);
      expect(unified.userTruth, isNull);
      expect(unified.rewriteDecision, isNull);
      expect(unified.rewriteReason, isNull);
      expect(unified.earlierSummary, isNull);
      expect(unified.responseType, 'coachAnswer');
      expect(unified.frictionType, 'unclearIntent');
      expect(unified.earlierResultCount, 0);
    });

    test('fromFollowUpResult null suggestedLine stays null', () {
      final legacy = CoachFollowUpResult(
        partnerId: 'p-8',
        phase: 'opening',
        headline: '先破冰',
        observation: '還沒開始聊。',
        task: '先送出開場白。',
        suggestedLine: null,
        boundaryReminder: '不要一次丟三個問題。',
        generatedAt: DateTime(2026, 7, 17, 10),
        modelUsed: 'claude-sonnet-5',
      );

      final unified = UnifiedCoachResult.fromFollowUpResult(legacy);

      expect(unified.suggestedLine, isNull);
      expect(unified.id, 'legacy-followup-p-8');
    });
  });
}
