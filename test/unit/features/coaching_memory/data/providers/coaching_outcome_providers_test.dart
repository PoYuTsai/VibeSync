import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/coach_chat/domain/entities/coach_chat_result.dart';
import 'package:vibesync/features/coach_chat/domain/entities/unified_coach_result.dart';
import 'package:vibesync/features/coaching_memory/data/providers/coaching_outcome_providers.dart';
import 'package:vibesync/features/coaching_memory/domain/entities/coaching_outcome_event.dart';

import '../../../../../helpers/memory_coaching_outcome_repository.dart';
import '../../../../../helpers/recording_coaching_outcome_uploader.dart';

// Phase E：recorder 改吃 unified 型別；fixture 沿用 legacy builder 經
// 1:1 映射轉入（機械調整，語意不變）。
UnifiedCoachResult _coachResult({
  String id = 'result-1',
  String? partnerId = 'partner-1',
  String conversationId = 'conversation-1',
  String nextStep = '先用一句輕鬆的話把球丟回去',
  String? suggestedLine = '你這句有點突然，但我可以接。',
  String headline = '先穩住節奏',
}) {
  return UnifiedCoachResult.fromCoachChatResult(CoachChatResult(
    id: id,
    conversationId: conversationId,
    partnerId: partnerId,
    question: '我現在該怎麼回？',
    mode: 'replyCraft',
    headline: headline,
    answer: '先接住她的情緒，再丟一個好回的小球。',
    userState: '有點急著想推進',
    nextStep: nextStep,
    suggestedLine: suggestedLine,
    boundaryReminder: '不要急著把對話推太重。',
    needsReflection: false,
    generatedAt: DateTime.utc(2026, 5, 15, 8),
    provider: 'claude',
    modelUsed: 'claude-sonnet-4-20250514',
  ));
}

CoachingAdviceContext _openerAdvice({String type = 'extend'}) {
  return CoachingAdviceContext(
    eventId: 'opener:req-1:$type',
    partnerId: 'partner-1',
    source: CoachingOutcomeSource.opener,
    adviceId: 'opener:req-1:$type',
    adviceType: type,
    suggestedMoveSummary: '妳週末也會去爬山嗎？',
  );
}

ProviderContainer _container({
  required MemoryCoachingOutcomeRepository repo,
  DateTime? now,
  RecordingCoachingOutcomeUploader? uploader,
}) {
  return ProviderContainer(overrides: [
    coachingOutcomeRepositoryProvider.overrideWithValue(repo),
    coachingOutcomeNowProvider.overrideWithValue(
      () => now ?? DateTime.utc(2026, 5, 15, 9),
    ),
    coachingOutcomeUploaderProvider.overrideWithValue(
      uploader ?? RecordingCoachingOutcomeUploader(),
    ),
  ]);
}

ProviderContainer _mutableNowContainer({
  required MemoryCoachingOutcomeRepository repo,
  required DateTime Function() now,
  RecordingCoachingOutcomeUploader? uploader,
}) {
  return ProviderContainer(overrides: [
    coachingOutcomeRepositoryProvider.overrideWithValue(repo),
    coachingOutcomeNowProvider.overrideWithValue(now),
    coachingOutcomeUploaderProvider.overrideWithValue(
      uploader ?? RecordingCoachingOutcomeUploader(),
    ),
  ]);
}

void main() {
  test('records a coach result outcome with stable local event fields',
      () async {
    final repo = MemoryCoachingOutcomeRepository();
    final c = _container(
      repo: repo,
      now: DateTime.utc(2026, 5, 15, 10),
    );
    addTearDown(c.dispose);

    expect(c.read(coachingOutcomeEventProvider('coach:result-1')), isNull);

    final event =
        await c.read(coachingOutcomeRecorderProvider).recordCoachResultOutcome(
              result: _coachResult(),
              userAction: CoachingUserAction.editedAndSent,
              outcome: CoachingOutcomeSignal.engaged,
            );

    expect(event.id, 'coach:result-1');
    expect(event.partnerId, 'partner-1');
    expect(event.conversationId, 'conversation-1');
    expect(event.source, CoachingOutcomeSource.coach);
    expect(event.adviceId, 'result-1');
    expect(event.adviceType, 'replyCraft');
    expect(event.userAction, CoachingUserAction.editedAndSent);
    expect(event.outcome, CoachingOutcomeSignal.engaged);
    expect(event.createdAt, DateTime.utc(2026, 5, 15, 10));
    expect(
      event.suggestedMoveSummary,
      '先用一句輕鬆的話把球丟回去 / 你這句有點突然，但我可以接。',
    );
    expect(c.read(coachingOutcomeEventProvider('coach:result-1'))?.id,
        'coach:result-1');
    final digest = c.read(coachingOutcomeDigestProvider('partner-1'));
    expect(digest.totalEvents, 1);
    expect(digest.engagedCount, 1);
    expect(digest.recentMoveSummaries.single, event.suggestedMoveSummary);
  });

  test('recording the same coach result overwrites the previous signal',
      () async {
    final repo = MemoryCoachingOutcomeRepository();
    final c = _container(repo: repo);
    addTearDown(c.dispose);
    final recorder = c.read(coachingOutcomeRecorderProvider);

    await recorder.recordCoachResultOutcome(
      result: _coachResult(),
      userAction: CoachingUserAction.unknown,
      outcome: CoachingOutcomeSignal.engaged,
    );
    await recorder.recordCoachResultOutcome(
      result: _coachResult(),
      userAction: CoachingUserAction.didNotSend,
      outcome: CoachingOutcomeSignal.pending,
    );

    final events = repo.listRecent();
    expect(events, hasLength(1));
    expect(events.single.userAction, CoachingUserAction.didNotSend);
    expect(events.single.outcome, CoachingOutcomeSignal.pending);
  });

  test('falls back to headline when next step and suggested line are empty',
      () async {
    final repo = MemoryCoachingOutcomeRepository();
    final c = _container(repo: repo);
    addTearDown(c.dispose);

    final event =
        await c.read(coachingOutcomeRecorderProvider).recordCoachResultOutcome(
              result: _coachResult(
                partnerId: null,
                nextStep: ' ',
                suggestedLine: ' ',
                headline: '先不要急著貼標籤',
              ),
              userAction: CoachingUserAction.askedCoach,
              outcome: CoachingOutcomeSignal.unknown,
            );

    expect(event.partnerId, isNull);
    expect(event.suggestedMoveSummary, '先不要急著貼標籤');
    expect(c.read(coachingUnboundOutcomesProvider).single.id, event.id);
    expect(c.read(coachingUnboundOutcomeDigestProvider).totalEvents, 1);
  });

  test('recordCoachResultReaction 保留第一段 userAction、只更新 outcome', () async {
    final repo = MemoryCoachingOutcomeRepository();
    final c = _container(repo: repo);
    addTearDown(c.dispose);
    final recorder = c.read(coachingOutcomeRecorderProvider);

    final first = await recorder.recordCoachResultOutcome(
      result: _coachResult(),
      userAction: CoachingUserAction.editedAndSent,
      outcome: CoachingOutcomeSignal.pending,
    );

    final updated = await recorder.recordCoachResultReaction(
      result: _coachResult(),
      outcome: CoachingOutcomeSignal.cold,
    );

    expect(updated, isNotNull);
    expect(updated!.id, first.id);
    expect(updated.adviceId, first.adviceId);
    expect(updated.suggestedMoveSummary, first.suggestedMoveSummary);
    expect(updated.userAction, CoachingUserAction.editedAndSent);
    expect(updated.outcome, CoachingOutcomeSignal.cold);

    final events = repo.listRecent();
    expect(events, hasLength(1));
    expect(events.single.userAction, CoachingUserAction.editedAndSent);
    expect(events.single.outcome, CoachingOutcomeSignal.cold);
  });

  test('recordCoachResultReaction 在沒有第一段紀錄時不寫入', () async {
    final repo = MemoryCoachingOutcomeRepository();
    final c = _container(repo: repo);
    addTearDown(c.dispose);

    final updated =
        await c.read(coachingOutcomeRecorderProvider).recordCoachResultReaction(
              result: _coachResult(),
              outcome: CoachingOutcomeSignal.engaged,
            );

    expect(updated, isNull);
    expect(repo.get('coach:result-1'), isNull);
  });

  test('recordCoachResultReaction 在 userAction=didNotSend 時不覆寫', () async {
    final repo = MemoryCoachingOutcomeRepository();
    final c = _container(repo: repo);
    addTearDown(c.dispose);
    final recorder = c.read(coachingOutcomeRecorderProvider);

    await recorder.recordCoachResultOutcome(
      result: _coachResult(),
      userAction: CoachingUserAction.didNotSend,
      outcome: CoachingOutcomeSignal.unknown,
    );

    final updated = await recorder.recordCoachResultReaction(
      result: _coachResult(),
      outcome: CoachingOutcomeSignal.engaged,
    );

    expect(updated, isNull);
    final event = repo.get('coach:result-1');
    expect(event, isNotNull);
    expect(event!.userAction, CoachingUserAction.didNotSend);
    expect(event.outcome, CoachingOutcomeSignal.unknown);
  });

  group('批2 recorder 泛化', () {
    test('coachingOutcomeForUserAction：send 類→pending、未送類→unknown', () {
      expect(coachingOutcomeForUserAction(CoachingUserAction.sentAsIs),
          CoachingOutcomeSignal.pending);
      expect(coachingOutcomeForUserAction(CoachingUserAction.editedAndSent),
          CoachingOutcomeSignal.pending);
      expect(coachingOutcomeForUserAction(CoachingUserAction.didNotSend),
          CoachingOutcomeSignal.unknown);
      expect(coachingOutcomeForUserAction(CoachingUserAction.askedCoach),
          CoachingOutcomeSignal.unknown);
    });

    test('recordAdviceCopied 建立 sentAsIs/pending 事件', () async {
      final repo = MemoryCoachingOutcomeRepository();
      final c = _container(repo: repo, now: DateTime.utc(2026, 7, 6, 10));
      addTearDown(c.dispose);

      final event = await c
          .read(coachingOutcomeRecorderProvider)
          .recordAdviceCopied(_openerAdvice());

      expect(event, isNotNull);
      expect(event!.id, 'opener:req-1:extend');
      expect(event.source, CoachingOutcomeSource.opener);
      expect(event.adviceId, 'opener:req-1:extend');
      expect(event.adviceType, 'extend');
      expect(event.userAction, CoachingUserAction.sentAsIs);
      expect(event.outcome, CoachingOutcomeSignal.pending);
      expect(event.partnerId, 'partner-1');
      expect(
          c.read(coachingOutcomeDigestProvider('partner-1')).totalEvents, 1);
    });

    test('recordAdviceCopied 已有事件時 no-op，不覆蓋已作答內容', () async {
      final repo = MemoryCoachingOutcomeRepository();
      var current = DateTime.utc(2026, 7, 6, 10);
      final c = _mutableNowContainer(repo: repo, now: () => current);
      addTearDown(c.dispose);
      final recorder = c.read(coachingOutcomeRecorderProvider);

      await recorder.recordAdviceUserAction(
        advice: _openerAdvice(),
        userAction: CoachingUserAction.didNotSend,
        outcome: CoachingOutcomeSignal.unknown,
      );
      current = DateTime.utc(2026, 7, 6, 11);
      final copied = await recorder.recordAdviceCopied(_openerAdvice());

      expect(copied, isNull);
      final stored = repo.get('opener:req-1:extend')!;
      expect(stored.userAction, CoachingUserAction.didNotSend);
      expect(stored.createdAt, DateTime.utc(2026, 7, 6, 10));
    });

    test('第一段同值重按 no-op：不洗第二段、不刷 createdAt', () async {
      final repo = MemoryCoachingOutcomeRepository();
      var current = DateTime.utc(2026, 7, 6, 10);
      final c = _mutableNowContainer(repo: repo, now: () => current);
      addTearDown(c.dispose);
      final recorder = c.read(coachingOutcomeRecorderProvider);

      await recorder.recordAdviceCopied(_openerAdvice()); // sentAsIs/pending @10
      current = DateTime.utc(2026, 7, 6, 11);
      await recorder.recordAdviceReaction(
        eventId: 'opener:req-1:extend',
        outcome: CoachingOutcomeSignal.engaged,
      ); // engaged @11
      current = DateTime.utc(2026, 7, 6, 12);
      await recorder.recordAdviceUserAction(
        advice: _openerAdvice(),
        userAction: CoachingUserAction.sentAsIs, // 同值重按
        outcome: CoachingOutcomeSignal.pending,
      );

      final stored = repo.get('opener:req-1:extend')!;
      expect(stored.userAction, CoachingUserAction.sentAsIs);
      expect(stored.outcome, CoachingOutcomeSignal.engaged); // 第二段答案保住
      expect(stored.createdAt, DateTime.utc(2026, 7, 6, 11)); // 沒刷
    });

    test('第一段改選保留 preview/note、第二段刻意洗回 pending', () async {
      final repo = MemoryCoachingOutcomeRepository();
      final c = _container(repo: repo, now: DateTime.utc(2026, 7, 6, 12));
      addTearDown(c.dispose);
      await repo.put(CoachingOutcomeEvent(
        id: 'opener:req-1:extend',
        partnerId: 'partner-1',
        source: CoachingOutcomeSource.opener,
        adviceId: 'opener:req-1:extend',
        adviceType: 'extend',
        suggestedMoveSummary: '妳週末也會去爬山嗎？',
        userAction: CoachingUserAction.sentAsIs,
        outcome: CoachingOutcomeSignal.engaged,
        outcomeTextPreview: '她回：真的假的你也爬山',
        userNote: '這招對戶外掛有效',
        createdAt: DateTime.utc(2026, 7, 6, 10),
      ));

      final updated = await c
          .read(coachingOutcomeRecorderProvider)
          .recordAdviceUserAction(
            advice: _openerAdvice(),
            userAction: CoachingUserAction.editedAndSent,
            outcome: coachingOutcomeForUserAction(
              CoachingUserAction.editedAndSent,
            ),
          );

      expect(updated.userAction, CoachingUserAction.editedAndSent);
      expect(updated.outcome, CoachingOutcomeSignal.pending); // 重問反應
      expect(updated.outcomeTextPreview, '她回：真的假的你也爬山'); // 保留
      expect(updated.userNote, '這招對戶外掛有效'); // 保留
      expect(updated.createdAt, DateTime.utc(2026, 7, 6, 12)); // 改選有寫入，刷新
    });

    test('第一段改選到未送類 outcome=unknown', () async {
      final repo = MemoryCoachingOutcomeRepository();
      final c = _container(repo: repo);
      addTearDown(c.dispose);
      final recorder = c.read(coachingOutcomeRecorderProvider);

      await recorder.recordAdviceCopied(_openerAdvice());
      final updated = await recorder.recordAdviceUserAction(
        advice: _openerAdvice(),
        userAction: CoachingUserAction.didNotSend,
        outcome: coachingOutcomeForUserAction(CoachingUserAction.didNotSend),
      );

      expect(updated.outcome, CoachingOutcomeSignal.unknown);
    });

    test('第二段同值重按 no-op：不刷 createdAt', () async {
      final repo = MemoryCoachingOutcomeRepository();
      var current = DateTime.utc(2026, 7, 6, 10);
      final c = _mutableNowContainer(repo: repo, now: () => current);
      addTearDown(c.dispose);
      final recorder = c.read(coachingOutcomeRecorderProvider);

      await recorder.recordAdviceCopied(_openerAdvice());
      current = DateTime.utc(2026, 7, 6, 11);
      await recorder.recordAdviceReaction(
        eventId: 'opener:req-1:extend',
        outcome: CoachingOutcomeSignal.cold,
      );
      current = DateTime.utc(2026, 7, 6, 12);
      final again = await recorder.recordAdviceReaction(
        eventId: 'opener:req-1:extend',
        outcome: CoachingOutcomeSignal.cold, // 同值
      );

      expect(again, isNotNull);
      expect(repo.get('opener:req-1:extend')!.createdAt,
          DateTime.utc(2026, 7, 6, 11));
    });

    test('coach 薄包裝：重按同一顆第一段晶片不再洗掉第二段（批2核心 bug 修）',
        () async {
      final repo = MemoryCoachingOutcomeRepository();
      final c = _container(repo: repo);
      addTearDown(c.dispose);
      final recorder = c.read(coachingOutcomeRecorderProvider);

      await recorder.recordCoachResultOutcome(
        result: _coachResult(),
        userAction: CoachingUserAction.editedAndSent,
        outcome: CoachingOutcomeSignal.pending,
      );
      await recorder.recordCoachResultReaction(
        result: _coachResult(),
        outcome: CoachingOutcomeSignal.cold,
      );
      await recorder.recordCoachResultOutcome(
        result: _coachResult(), // 重按同一顆
        userAction: CoachingUserAction.editedAndSent,
        outcome: CoachingOutcomeSignal.pending,
      );

      final stored = repo.get('coach:result-1')!;
      expect(stored.outcome, CoachingOutcomeSignal.cold); // 修前會被洗回 pending
    });
  });

  group('批3 best-effort 上傳 wiring', () {
    test('recordAdviceCopied 成功 put 後觸發一次上傳', () async {
      final repo = MemoryCoachingOutcomeRepository();
      final uploader = RecordingCoachingOutcomeUploader();
      final c = _container(repo: repo, uploader: uploader);
      addTearDown(c.dispose);

      await c
          .read(coachingOutcomeRecorderProvider)
          .recordAdviceCopied(_openerAdvice());

      expect(uploader.uploadCount, 1);
      expect(uploader.uploaded.single.id, 'opener:req-1:extend');
    });

    test('recordAdviceUserAction 成功 put 後觸發一次上傳', () async {
      final repo = MemoryCoachingOutcomeRepository();
      final uploader = RecordingCoachingOutcomeUploader();
      final c = _container(repo: repo, uploader: uploader);
      addTearDown(c.dispose);

      await c.read(coachingOutcomeRecorderProvider).recordAdviceUserAction(
            advice: _openerAdvice(),
            userAction: CoachingUserAction.editedAndSent,
            outcome: CoachingOutcomeSignal.pending,
          );

      expect(uploader.uploadCount, 1);
      expect(uploader.uploaded.single.userAction,
          CoachingUserAction.editedAndSent);
    });

    test('recordAdviceReaction 成功 put 後觸發一次上傳', () async {
      final repo = MemoryCoachingOutcomeRepository();
      final uploader = RecordingCoachingOutcomeUploader();
      final c = _container(repo: repo, uploader: uploader);
      addTearDown(c.dispose);
      final recorder = c.read(coachingOutcomeRecorderProvider);

      await recorder.recordAdviceCopied(_openerAdvice()); // upload #1
      final updated = await recorder.recordAdviceReaction(
        eventId: 'opener:req-1:extend',
        outcome: CoachingOutcomeSignal.engaged,
      ); // upload #2

      expect(updated, isNotNull);
      expect(uploader.uploadCount, 2);
      expect(uploader.uploaded.last.outcome, CoachingOutcomeSignal.engaged);
    });

    test('recordCoachResultOutcome 走 recordAdviceUserAction 也觸發一次上傳',
        () async {
      final repo = MemoryCoachingOutcomeRepository();
      final uploader = RecordingCoachingOutcomeUploader();
      final c = _container(repo: repo, uploader: uploader);
      addTearDown(c.dispose);

      await c.read(coachingOutcomeRecorderProvider).recordCoachResultOutcome(
            result: _coachResult(),
            userAction: CoachingUserAction.editedAndSent,
            outcome: CoachingOutcomeSignal.pending,
          );

      expect(uploader.uploadCount, 1);
      expect(uploader.uploaded.single.id, 'coach:result-1');
    });

    test('recordAdviceCopied 已有事件 no-op 短路時不觸發上傳', () async {
      final repo = MemoryCoachingOutcomeRepository();
      final uploader = RecordingCoachingOutcomeUploader();
      final c = _container(repo: repo, uploader: uploader);
      addTearDown(c.dispose);
      final recorder = c.read(coachingOutcomeRecorderProvider);

      await recorder.recordAdviceCopied(_openerAdvice()); // upload #1
      final again = await recorder.recordAdviceCopied(_openerAdvice()); // no-op

      expect(again, isNull);
      expect(uploader.uploadCount, 1);
    });

    test('recordAdviceUserAction 同值重按 no-op 短路時不觸發上傳', () async {
      final repo = MemoryCoachingOutcomeRepository();
      final uploader = RecordingCoachingOutcomeUploader();
      final c = _container(repo: repo, uploader: uploader);
      addTearDown(c.dispose);
      final recorder = c.read(coachingOutcomeRecorderProvider);

      await recorder.recordAdviceUserAction(
        advice: _openerAdvice(),
        userAction: CoachingUserAction.didNotSend,
        outcome: CoachingOutcomeSignal.unknown,
      ); // upload #1
      await recorder.recordAdviceUserAction(
        advice: _openerAdvice(),
        userAction: CoachingUserAction.didNotSend, // 同值
        outcome: CoachingOutcomeSignal.unknown,
      ); // no-op

      expect(uploader.uploadCount, 1);
    });

    test('recordAdviceReaction 冪等 return null 時不觸發上傳', () async {
      final repo = MemoryCoachingOutcomeRepository();
      final uploader = RecordingCoachingOutcomeUploader();
      final c = _container(repo: repo, uploader: uploader);
      addTearDown(c.dispose);

      // 沒有第一段紀錄 → recordAdviceReaction 回 null，不 put、不上傳
      final updated =
          await c.read(coachingOutcomeRecorderProvider).recordAdviceReaction(
                eventId: 'opener:req-1:extend',
                outcome: CoachingOutcomeSignal.engaged,
              );

      expect(updated, isNull);
      expect(uploader.uploadCount, 0);
    });

    test('recordAdviceReaction 同值重按 no-op 短路時不觸發上傳', () async {
      final repo = MemoryCoachingOutcomeRepository();
      final uploader = RecordingCoachingOutcomeUploader();
      final c = _container(repo: repo, uploader: uploader);
      addTearDown(c.dispose);
      final recorder = c.read(coachingOutcomeRecorderProvider);

      await recorder.recordAdviceCopied(_openerAdvice()); // upload #1
      await recorder.recordAdviceReaction(
        eventId: 'opener:req-1:extend',
        outcome: CoachingOutcomeSignal.cold,
      ); // upload #2
      await recorder.recordAdviceReaction(
        eventId: 'opener:req-1:extend',
        outcome: CoachingOutcomeSignal.cold, // 同值
      ); // no-op

      expect(uploader.uploadCount, 2);
    });
  });
}
