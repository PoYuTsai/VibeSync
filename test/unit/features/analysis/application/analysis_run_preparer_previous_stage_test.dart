// 跨次連續性 seam（對象卡互動階段閉環）：第二個分析片段送出前，
// 請求組裝器能取得上一個 partner-scoped 有效 stage（弱先驗），
// 並隨 AnalyzeStreamRequest 進 wire payload。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/application/analysis_run_preparer.dart';
import 'package:vibesync/features/analysis/application/ports/conversation_memory_port.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/conversation/domain/entities/session_context.dart';

class _NoopMemory implements ConversationMemoryPort {
  @override
  String? persistedHistoricalSummary(Conversation conversation) => null;

  @override
  Future<String> formatEphemeralSummary(
    Conversation conversation,
    int olderRounds,
  ) async =>
      '';

  @override
  List<Message> clipToRecentRounds(List<Message> messages, int maxRounds) =>
      messages;

  @override
  int get maxRecentRounds => 15;

  @override
  int get minRoundsPerSummary => 3;
}

class _SuffixMemory extends _NoopMemory {
  @override
  String? persistedHistoricalSummary(Conversation conversation) => '舊摘要';

  @override
  List<Message> clipToRecentRounds(List<Message> messages, int maxRounds) =>
      messages.sublist(1);
}

Conversation _conversation() => Conversation(
      id: 'c-1',
      name: '小雲',
      messages: [
        Message(
          id: 'm1',
          content: '嗨嗨',
          isFromMe: false,
          timestamp: DateTime(2026, 8, 22),
        ),
      ],
      createdAt: DateTime(2026, 8, 22),
      updatedAt: DateTime(2026, 8, 22),
      partnerId: 'p-1',
    );

void main() {
  test('assemble 帶出上一個 partner-scoped 有效 stage（弱先驗）', () async {
    String? askedPartnerScope;
    final preparer = AnalysisRunPreparer(
      memory: _NoopMemory(),
      resolvePartnerSummary: (_) => null,
      resolveEffectiveStyleContext: (_) => null,
      resolvePreviousStage: (conversation) {
        askedPartnerScope = conversation.partnerId;
        return 'qualification';
      },
    );
    final conversation = _conversation();
    final gate = preparer.gate(conversation: conversation);
    expect(gate.failure, isNull);

    final preparation = await preparer.assemble(
      conversation: conversation,
      gate: gate,
    );

    expect(preparation.previousStage, 'qualification');
    expect(askedPartnerScope, 'p-1');
  });

  test('沒有上一個有效 stage 時 previousStage 為 null（不偽造弱先驗）', () async {
    final preparer = AnalysisRunPreparer(
      memory: _NoopMemory(),
      resolvePartnerSummary: (_) => null,
      resolveEffectiveStyleContext: (_) => null,
      resolvePreviousStage: (_) => null,
    );
    final conversation = _conversation();
    final gate = preparer.gate(conversation: conversation);

    final preparation = await preparer.assemble(
      conversation: conversation,
      gate: gate,
    );

    expect(preparation.previousStage, isNull);
  });

  test('主 AnalyzeChat 不帶 About Me style context；新片段採最新對象設定', () async {
    final conversation = _conversation()
      ..sessionContext = SessionContext(
        meetingContext: MeetingContext.datingApp,
        duration: AcquaintanceDuration.justMet,
        goal: UserGoal.dateInvite,
      );
    final latestDefaults = SessionContext(
      meetingContext: MeetingContext.committedPartner,
      duration: AcquaintanceDuration.monthPlus,
      goal: UserGoal.justChat,
    );
    final preparer = AnalysisRunPreparer(
      memory: _NoopMemory(),
      resolvePartnerSummary: (_) => null,
      resolveEffectiveStyleContext: (_) => 'About Me should not be sent',
      resolveSessionContext: (_) => latestDefaults,
    );

    final gate = preparer.gate(conversation: conversation);
    final preparation = await preparer.assemble(
      conversation: conversation,
      gate: gate,
    );

    expect(preparation.effectiveStyleContext, isNull);
    expect(
      preparation.sessionContext?.meetingContext,
      MeetingContext.committedPartner,
    );
  });

  test('舊 snapshot 同一訊息邊界重跑沿用 Conversation context', () async {
    final originalContext = SessionContext(
      meetingContext: MeetingContext.datingApp,
      duration: AcquaintanceDuration.fewWeeks,
      goal: UserGoal.maintainHeat,
    );
    final conversation = _conversation()
      ..sessionContext = originalContext
      ..lastAnalyzedMessageCount = 1;
    final preparer = AnalysisRunPreparer(
      memory: _NoopMemory(),
      resolvePartnerSummary: (_) => null,
      resolveEffectiveStyleContext: (_) => null,
      resolveSessionContext: (_) => SessionContext(
        meetingContext: MeetingContext.committedPartner,
        duration: AcquaintanceDuration.monthPlus,
        goal: UserGoal.justChat,
      ),
    );

    final gate = preparer.gate(conversation: conversation);
    final preparation = await preparer.assemble(
      conversation: conversation,
      gate: gate,
    );

    expect(preparation.sessionContext, same(originalContext));
  });

  test('同一訊息邊界重跑讀 snapshot 凍結的完整 context', () async {
    final conversation = _conversation()
      ..sessionContext = SessionContext(
        meetingContext: MeetingContext.inPerson,
        duration: AcquaintanceDuration.justMet,
      )
      ..lastAnalyzedMessageCount = 1
      ..lastAnalysisSnapshotJson = jsonEncode({
        '__vibesync_snapshot_meta_v1': {
          'sessionContext': {
            'meetingContext': 'committedPartner',
            'duration': 'monthPlus',
            'goal': 'maintainHeat',
            'userStyle': 'gentle',
            'userInterests': '旅行、咖啡',
            'targetDescription': '慢熟',
            'analysisContextNote': '剛吵完架',
          },
        },
      });
    final preparer = AnalysisRunPreparer(
      memory: _NoopMemory(),
      resolvePartnerSummary: (_) => null,
      resolveEffectiveStyleContext: (_) => null,
      resolveSessionContext: (_) => SessionContext(
        meetingContext: MeetingContext.datingApp,
        duration: AcquaintanceDuration.fewWeeks,
      ),
    );

    final preparation = await preparer.assemble(
      conversation: conversation,
      gate: preparer.gate(conversation: conversation),
    );

    expect(
      preparation.sessionContext?.meetingContext,
      MeetingContext.committedPartner,
    );
    expect(
      preparation.sessionContext?.duration,
      AcquaintanceDuration.monthPlus,
    );
    expect(preparation.sessionContext?.goal, UserGoal.maintainHeat);
    expect(preparation.sessionContext?.userStyle, UserStyle.gentle);
    expect(preparation.sessionContext?.userInterests, '旅行、咖啡');
    expect(preparation.sessionContext?.targetDescription, '慢熟');
    expect(preparation.sessionContext?.analysisContextNote, '剛吵完架');
  });

  test('snapshot 明確凍結為無 context 時不回退到今天的設定', () async {
    final conversation = _conversation()
      ..sessionContext = SessionContext(
        meetingContext: MeetingContext.committedPartner,
        duration: AcquaintanceDuration.monthPlus,
      )
      ..lastAnalyzedMessageCount = 1
      ..lastAnalysisSnapshotJson = jsonEncode({
        '__vibesync_snapshot_meta_v1': {'sessionContext': null},
      });
    final preparer = AnalysisRunPreparer(
      memory: _NoopMemory(),
      resolvePartnerSummary: (_) => null,
      resolveEffectiveStyleContext: (_) => null,
      resolveSessionContext: (_) => conversation.sessionContext,
    );

    final preparation = await preparer.assemble(
      conversation: conversation,
      gate: preparer.gate(conversation: conversation),
    );

    expect(preparation.sessionContext, isNull);
    expect(preparation.isReconnectContext, isFalse);
  });

  test('新片段起點以 requestMessages 的相對索引送出', () async {
    final conversation = _conversation()
      ..messages.addAll([
        Message(
          id: 'm2',
          content: '我先回一句',
          isFromMe: true,
          timestamp: DateTime(2026, 8, 22, 0, 1),
        ),
        Message(
          id: 'm3',
          content: '她的新片段 1',
          isFromMe: false,
          timestamp: DateTime(2026, 8, 22, 0, 2),
        ),
        Message(
          id: 'm4',
          content: '她的新片段 2',
          isFromMe: false,
          timestamp: DateTime(2026, 8, 22, 0, 3),
        ),
      ])
      ..lastAnalyzedMessageCount = 2;
    final preparer = AnalysisRunPreparer(
      memory: _NoopMemory(),
      resolvePartnerSummary: (_) => null,
      resolveEffectiveStyleContext: (_) => null,
    );
    final gate = preparer.gate(conversation: conversation);
    final preparation = await preparer.assemble(
      conversation: conversation,
      gate: gate,
    );

    expect(preparation.requestMessages, hasLength(4));
    expect(preparation.analysisFragmentStartIndex, 2);
  });

  test('摘要裁切後片段起點會換算成裁切 payload 的相對索引', () async {
    final conversation = _conversation()
      ..messages.addAll([
        Message(
          id: 'm2',
          content: '我先回一句',
          isFromMe: true,
          timestamp: DateTime(2026, 8, 22, 0, 1),
        ),
        Message(
          id: 'm3',
          content: '她的新片段',
          isFromMe: false,
          timestamp: DateTime(2026, 8, 22, 0, 2),
        ),
      ])
      ..lastAnalyzedMessageCount = 2;
    final preparer = AnalysisRunPreparer(
      memory: _SuffixMemory(),
      resolvePartnerSummary: (_) => null,
      resolveEffectiveStyleContext: (_) => null,
    );
    final gate = preparer.gate(conversation: conversation);
    final preparation = await preparer.assemble(
      conversation: conversation,
      gate: gate,
    );

    expect(preparation.requestMessages.map((message) => message.id), [
      'm2',
      'm3',
    ]);
    expect(preparation.analysisFragmentStartIndex, 1);
  });

  test('同內容重跑只評最後一組連續的她方訊息', () async {
    final conversation = _conversation()
      ..messages.addAll([
        Message(
          id: 'm2',
          content: '我先回一句',
          isFromMe: true,
          timestamp: DateTime(2026, 8, 22, 0, 1),
        ),
        Message(
          id: 'm3',
          content: '她的最後一組 1',
          isFromMe: false,
          timestamp: DateTime(2026, 8, 22, 0, 2),
        ),
        Message(
          id: 'm4',
          content: '她的最後一組 2',
          isFromMe: false,
          timestamp: DateTime(2026, 8, 22, 0, 3),
        ),
      ])
      ..lastAnalyzedMessageCount = 4;
    final preparer = AnalysisRunPreparer(
      memory: _NoopMemory(),
      resolvePartnerSummary: (_) => null,
      resolveEffectiveStyleContext: (_) => null,
    );
    final gate = preparer.gate(conversation: conversation);
    final preparation = await preparer.assemble(
      conversation: conversation,
      gate: gate,
    );

    expect(preparation.analysisFragmentStartIndex, 2);
  });
}
