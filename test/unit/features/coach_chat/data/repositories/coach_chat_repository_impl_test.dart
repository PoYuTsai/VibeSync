import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/coach_chat/data/repositories/coach_chat_repository_impl.dart';
import 'package:vibesync/features/coach_chat/domain/entities/coach_chat_result.dart';
import 'package:vibesync/features/coach_chat/domain/entities/unified_coach_result.dart';
import 'package:vibesync/features/coach_follow_up/domain/entities/coach_follow_up_result.dart';

const _testHivePath = './.dart_tool/test_hive_coach_chat_repo';
const _testUnifiedBoxName = 'test_unified_coach_results';
const _testLegacyChatBoxName = 'test_coach_chat_results';
const _testLegacyFollowUpBoxName = 'test_coach_follow_up_results';

CoachChatResult _result(
  String id, {
  String conversationId = 'c-1',
  DateTime? generatedAt,
}) {
  return CoachChatResult(
    id: id,
    conversationId: conversationId,
    partnerId: 'p-1',
    question: '她是什麼意思？',
    mode: 'replyCraft',
    headline: '接住再反問',
    answer: '她是在丟觀察，不是要你證明自己。',
    userState: '你可能急著解釋。',
    nextStep: '先用一句反問接回去。',
    suggestedLine: '被妳發現了。妳也是亂逛派嗎？',
    boundaryReminder: '不要把一句觀察放大成壓力。',
    needsReflection: false,
    reflectionQuestion: null,
    generatedAt: generatedAt ?? DateTime(2026, 5, 7, 12),
    provider: 'claude',
    modelUsed: 'claude-sonnet-4-20250514',
  );
}

UnifiedCoachResult _unified(
  String id, {
  String scopeType = 'conversation',
  String scopeId = 'c-1',
  DateTime? generatedAt,
  String? earlierSummary,
  int earlierResultCount = 0,
}) {
  return UnifiedCoachResult(
    id: id,
    conversationId: scopeType == 'conversation' ? scopeId : null,
    partnerId: scopeType == 'partner' ? scopeId : 'p-1',
    question: '她是什麼意思？',
    mode: 'replyCraft',
    headline: '接住再反問',
    answer: '她是在丟觀察，不是要你證明自己。',
    userState: '你可能急著解釋。',
    nextStep: '先用一句反問接回去。',
    suggestedLine: '被妳發現了。妳也是亂逛派嗎？',
    boundaryReminder: '不要把一句觀察放大成壓力。',
    needsReflection: false,
    generatedAt: generatedAt ?? DateTime(2026, 5, 7, 12),
    provider: 'claude',
    modelUsed: 'claude-sonnet-4-20250514',
    earlierSummary: earlierSummary,
    earlierResultCount: earlierResultCount,
    scopeType: scopeType,
    scopeId: scopeId,
  );
}

CoachFollowUpResult _followUp(String partnerId, {DateTime? generatedAt}) {
  return CoachFollowUpResult(
    partnerId: partnerId,
    phase: 'warming',
    headline: '維持輕鬆節奏',
    observation: '她回覆變快，話題也會延伸。',
    task: '今天丟一個開放式問題。',
    suggestedLine: '妳上次說的展覽後來去了嗎？',
    boundaryReminder: '不要連發三則。',
    generatedAt: generatedAt ?? DateTime(2026, 5, 7, 11),
    modelUsed: 'claude-sonnet-5',
  );
}

void main() {
  setUpAll(() {
    Hive.init(_testHivePath);
    if (!Hive.isAdapterRegistered(17)) {
      Hive.registerAdapter(CoachChatResultAdapter());
    }
    if (!Hive.isAdapterRegistered(16)) {
      Hive.registerAdapter(CoachFollowUpResultAdapter());
    }
    if (!Hive.isAdapterRegistered(26)) {
      Hive.registerAdapter(UnifiedCoachResultAdapter());
    }
  });

  late Box<UnifiedCoachResult> unifiedBox;
  late Box<CoachChatResult> legacyChatBox;
  late Box<CoachFollowUpResult> legacyFollowUpBox;
  late CoachChatRepositoryImpl repo;

  setUp(() async {
    unifiedBox = await Hive.openBox<UnifiedCoachResult>(_testUnifiedBoxName);
    legacyChatBox = await Hive.openBox<CoachChatResult>(_testLegacyChatBoxName);
    legacyFollowUpBox =
        await Hive.openBox<CoachFollowUpResult>(_testLegacyFollowUpBoxName);
    repo = CoachChatRepositoryImpl(unifiedBox, legacyChatBox, legacyFollowUpBox);
  });

  tearDown(() async {
    await unifiedBox.deleteFromDisk();
    await legacyChatBox.deleteFromDisk();
    await legacyFollowUpBox.deleteFromDisk();
  });

  tearDownAll(() async {
    await Hive.close();
    final dir = Directory(_testHivePath);
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('put + latestForConversation returns newest result', () async {
    await repo.put(_result('old', generatedAt: DateTime(2026, 5, 7, 11)));
    await repo.put(_result('new', generatedAt: DateTime(2026, 5, 7, 12)));

    expect(repo.latestForConversation('c-1')?.id, 'new');
    // Phase D: writes land only in the unified box, never in legacy.
    expect(unifiedBox.keys, containsAll(['old', 'new']));
    expect(unifiedBox.get('new')?.scopeType, 'conversation');
    expect(unifiedBox.get('new')?.scopeId, 'c-1');
    expect(legacyChatBox.values, isEmpty);
    expect(legacyFollowUpBox.values, isEmpty);
  });

  test('put trims to latest 10 results per conversation', () async {
    for (var i = 0; i < 12; i++) {
      await repo.put(_result(
        'r-$i',
        generatedAt: DateTime(2026, 5, 7, 10).add(Duration(minutes: i)),
      ));
    }

    final list = repo.listByConversation('c-1');
    expect(
      list.map((r) => r.id),
      ['r-11', 'r-10', 'r-9', 'r-8', 'r-7', 'r-6', 'r-5', 'r-4', 'r-3', 'r-2'],
    );
    // Phase D: trim happens in the unified box; legacy stays untouched.
    expect(unifiedBox.length, 10);
    expect(legacyChatBox.values, isEmpty);
  });

  test('put rolls trimmed coach results into the latest summary', () async {
    for (var i = 0; i < 12; i++) {
      await repo.put(_result(
        'r-$i',
        generatedAt: DateTime(2026, 5, 7, 10).add(Duration(minutes: i)),
      ));
    }

    final latest = repo.latestForConversation('c-1')!;

    expect(latest.earlierResultCount, 2);
    expect(latest.earlierSummary, contains('問「她是什麼意思？」'));
    expect(latest.earlierSummary, contains('先做：先用一句反問接回去。'));
  });

  test('put carries existing earlier summary onto a newer latest result',
      () async {
    await repo.put(_result('old').copyWith(
      earlierSummary: '- 問「她是什麼意思？」；舊摘要',
      earlierResultCount: 3,
    ));
    await repo.put(_result(
      'new',
      generatedAt: DateTime(2026, 5, 7, 13),
    ));

    final latest = repo.latestForConversation('c-1')!;

    expect(latest.id, 'new');
    expect(latest.earlierResultCount, 3);
    expect(latest.earlierSummary, contains('舊摘要'));
  });

  test('deleteConversation removes only that conversation', () async {
    await repo.put(_result('a', conversationId: 'c-1'));
    await repo.put(_result('b', conversationId: 'c-2'));

    await repo.deleteConversation('c-1');

    expect(repo.listByConversation('c-1'), isEmpty);
    expect(repo.listByConversation('c-2').single.id, 'b');
  });

  test('clearAll wipes the unified store but never the legacy boxes',
      () async {
    await legacyChatBox.put('l-keep', _result('l-keep', conversationId: 'c-3'));
    await legacyFollowUpBox.put('p-keep', _followUp('p-keep'));
    await repo.put(_result('a', conversationId: 'c-1'));
    await repo.put(_result('b', conversationId: 'c-2'));

    await repo.clearAll();

    expect(unifiedBox.values, isEmpty);
    expect(repo.listByConversation('c-1'), isEmpty);
    expect(repo.listByConversation('c-2'), isEmpty);
    // Legacy cleanup is owned by StorageService.clearAll / delete paths only.
    expect(legacyChatBox.keys, ['l-keep']);
    expect(legacyFollowUpBox.keys, ['p-keep']);
  });

  group('scope-keyed unified storage', () {
    test('putUnified writes only the unified box, legacy boxes untouched',
        () async {
      await legacyChatBox.put('legacy-1', _result('legacy-1'));

      await repo.putUnified(_unified('u-1'));

      expect(unifiedBox.length, 1);
      expect(unifiedBox.get('u-1')?.id, 'u-1');
      expect(legacyChatBox.length, 1);
      expect(legacyChatBox.get('legacy-1')?.id, 'legacy-1');
      expect(legacyFollowUpBox.values, isEmpty);
    });

    test('putUnified trims to keepPerScope per scope in the unified box only',
        () async {
      await legacyChatBox.put('legacy-1', _result('legacy-1'));
      for (var i = 0; i < 12; i++) {
        await repo.putUnified(_unified(
          'u-$i',
          generatedAt: DateTime(2026, 5, 7, 10).add(Duration(minutes: i)),
        ));
      }

      expect(unifiedBox.length, 10);
      final ids = unifiedBox.values.map((r) => r.id).toSet();
      expect(ids.contains('u-0'), isFalse);
      expect(ids.contains('u-1'), isFalse);
      expect(ids.contains('u-11'), isTrue);
      expect(legacyChatBox.length, 1);
    });

    test('putUnified rolls trimmed results into the latest scope summary',
        () async {
      for (var i = 0; i < 12; i++) {
        await repo.putUnified(_unified(
          'u-$i',
          generatedAt: DateTime(2026, 5, 7, 10).add(Duration(minutes: i)),
        ));
      }

      final latest = repo.latestForScope('conversation', 'c-1')!;

      expect(latest.id, 'u-11');
      expect(latest.earlierResultCount, 2);
      expect(latest.earlierSummary, contains('問「她是什麼意思？」'));
      expect(latest.earlierSummary, contains('先做：先用一句反問接回去。'));
    });

    test('putUnified carries existing earlier summary onto a newer latest',
        () async {
      await repo.putUnified(_unified(
        'u-old',
        earlierSummary: '- 問「她是什麼意思？」；舊摘要',
        earlierResultCount: 3,
      ));
      await repo.putUnified(_unified(
        'u-new',
        generatedAt: DateTime(2026, 5, 7, 13),
      ));

      final latest = repo.latestForScope('conversation', 'c-1')!;

      expect(latest.id, 'u-new');
      expect(latest.earlierResultCount, 3);
      expect(latest.earlierSummary, contains('舊摘要'));
    });

    test('deleteScope removes only that scope from the unified box', () async {
      await legacyChatBox.put('legacy-1', _result('legacy-1'));
      await repo.putUnified(_unified('u-a', scopeId: 'c-1'));
      await repo.putUnified(_unified('u-b', scopeId: 'c-2'));
      await repo.putUnified(
          _unified('u-c', scopeType: 'partner', scopeId: 'p-9'));

      await repo.deleteScope('conversation', 'c-1');

      // Unified rows for c-1 are gone; the legacy row survives and is still
      // visible through the read-bridge (deleteScope never touches legacy).
      expect(
        unifiedBox.values.where(
          (r) => r.scopeType == 'conversation' && r.scopeId == 'c-1',
        ),
        isEmpty,
      );
      expect(
        repo.listByScope('conversation', 'c-1').map((r) => r.id),
        ['legacy-1'],
      );
      expect(repo.listByScope('conversation', 'c-2').single.id, 'u-b');
      expect(repo.listByScope('partner', 'p-9').single.id, 'u-c');
      expect(legacyChatBox.length, 1);
    });

    test('partner scope shares the same trim + rollup pipeline', () async {
      for (var i = 0; i < 12; i++) {
        await repo.putUnified(_unified(
          'p-$i',
          scopeType: 'partner',
          scopeId: 'p-9',
          generatedAt: DateTime(2026, 5, 7, 10).add(Duration(minutes: i)),
        ));
      }

      final list = repo.listByScope('partner', 'p-9');
      expect(list, hasLength(10));
      expect(list.first.id, 'p-11');
      expect(list.first.earlierResultCount, 2);
      expect(list.first.earlierSummary, contains('問「她是什麼意思？」'));
      expect(legacyFollowUpBox.values, isEmpty);
    });
  });

  group('read-bridge merged reads', () {
    test('conversation scope merges unified + legacy-17 sorted descending',
        () async {
      await legacyChatBox.put(
        'l-1',
        _result('l-1', generatedAt: DateTime(2026, 5, 7, 10)),
      );
      await legacyChatBox.put(
        'l-2',
        _result('l-2', generatedAt: DateTime(2026, 5, 7, 12)),
      );
      await repo.putUnified(
        _unified('u-1', generatedAt: DateTime(2026, 5, 7, 11)),
      );
      await repo.putUnified(
        _unified('u-2', generatedAt: DateTime(2026, 5, 7, 13)),
      );

      final list = repo.listByScope('conversation', 'c-1');

      expect(list.map((r) => r.id), ['u-2', 'l-2', 'u-1', 'l-1']);
      expect(repo.latestForScope('conversation', 'c-1')?.id, 'u-2');
    });

    test('id collision keeps the unified row over the legacy one', () async {
      await legacyChatBox.put(
        'same-id',
        _result('same-id', generatedAt: DateTime(2026, 5, 7, 10)),
      );
      await repo.putUnified(
        _unified('same-id', generatedAt: DateTime(2026, 5, 7, 12)),
      );

      final list = repo.listByScope('conversation', 'c-1');

      expect(list, hasLength(1));
      expect(list.single.id, 'same-id');
      expect(list.single.generatedAt, DateTime(2026, 5, 7, 12));
    });

    test('partner scope merges unified + legacy-16 with mapped fields',
        () async {
      await legacyFollowUpBox.put('p-9', _followUp('p-9'));
      await repo.putUnified(_unified(
        'u-p',
        scopeType: 'partner',
        scopeId: 'p-9',
        generatedAt: DateTime(2026, 5, 7, 12),
      ));

      final list = repo.listByScope('partner', 'p-9');

      expect(list.map((r) => r.id), ['u-p', 'legacy-followup-p-9']);
      final legacy = list.last;
      expect(legacy.userState, '她回覆變快，話題也會延伸。');
      expect(legacy.answer, legacy.userState);
      expect(legacy.nextStep, '今天丟一個開放式問題。');
      expect(legacy.lifecyclePhase, 'warming');
      expect(legacy.costDeducted, 0);
      expect(legacy.scopeType, 'partner');
      expect(legacy.scopeId, 'p-9');
    });

    test('other conversations and partners do not leak into a scope',
        () async {
      await legacyChatBox.put(
        'l-other',
        _result('l-other', conversationId: 'c-2'),
      );
      await legacyFollowUpBox.put('p-other', _followUp('p-other'));
      await repo.putUnified(_unified('u-other', scopeId: 'c-2'));
      await repo.putUnified(
          _unified('u-p-other', scopeType: 'partner', scopeId: 'p-other'));

      expect(repo.listByScope('conversation', 'c-1'), isEmpty);
      expect(repo.listByScope('partner', 'p-9'), isEmpty);
    });

    test('merged reads never mutate the legacy boxes (Invariant #7)',
        () async {
      await legacyChatBox.put('l-1', _result('l-1'));
      await legacyFollowUpBox.put('p-9', _followUp('p-9'));
      await repo.putUnified(_unified('u-1'));
      await repo.putUnified(
          _unified('u-p', scopeType: 'partner', scopeId: 'p-9'));

      repo.listByScope('conversation', 'c-1');
      repo.listByScope('partner', 'p-9');
      repo.latestForScope('conversation', 'c-1');
      repo.latestForScope('partner', 'p-9');

      expect(legacyChatBox.keys, ['l-1']);
      expect(legacyChatBox.get('l-1')?.question, '她是什麼意思？');
      expect(legacyFollowUpBox.keys, ['p-9']);
      expect(legacyFollowUpBox.get('p-9')?.task, '今天丟一個開放式問題。');
    });
  });
}
