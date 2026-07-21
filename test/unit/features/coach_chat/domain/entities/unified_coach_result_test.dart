import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/coach_chat/domain/entities/unified_coach_result.dart';

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
}
