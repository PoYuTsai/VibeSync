import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/core/constants/app_constants.dart';
import 'package:vibesync/core/services/storage_service.dart';
import 'package:vibesync/features/coach_chat/domain/entities/coach_chat_result.dart';
import 'package:vibesync/features/coach_chat/domain/entities/unified_coach_result.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_repository.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation_summary.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/conversation/domain/entities/session_context.dart';

const _testHivePath = './.dart_tool/test_hive_conversation_coach_cleanup';
const _ownerId = 'u1';

Conversation _conversation(String id, {String ownerUserId = _ownerId}) {
  final now = DateTime(2026, 7, 21, 10);
  return Conversation(
    id: id,
    name: '對話 $id',
    messages: const [],
    createdAt: now,
    updatedAt: now,
    ownerUserId: ownerUserId,
  );
}

CoachChatResult _legacyResult(String id, {required String conversationId}) {
  return CoachChatResult(
    id: id,
    conversationId: conversationId,
    partnerId: 'p-1',
    question: '她是什麼意思？',
    mode: 'replyCraft',
    headline: '接住再反問',
    answer: '她是在丟觀察。',
    userState: '你可能急著解釋。',
    nextStep: '先用一句反問接回去。',
    boundaryReminder: '不要放大成壓力。',
    needsReflection: false,
    generatedAt: DateTime(2026, 7, 21, 11),
    provider: 'claude',
    modelUsed: 'claude-sonnet-5',
  );
}

UnifiedCoachResult _unifiedResult(
  String id, {
  required String scopeType,
  required String scopeId,
}) {
  return UnifiedCoachResult(
    id: id,
    conversationId: scopeType == 'conversation' ? scopeId : null,
    partnerId: scopeType == 'partner' ? scopeId : 'p-1',
    question: '她是什麼意思？',
    mode: 'replyCraft',
    headline: '接住再反問',
    answer: '她是在丟觀察。',
    userState: '你可能急著解釋。',
    nextStep: '先用一句反問接回去。',
    boundaryReminder: '不要放大成壓力。',
    needsReflection: false,
    generatedAt: DateTime(2026, 7, 21, 11),
    provider: 'claude',
    modelUsed: 'claude-sonnet-5',
    scopeType: scopeType,
    scopeId: scopeId,
  );
}

void main() {
  setUpAll(() {
    Hive.init(_testHivePath);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ConversationAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(MessageAdapter());
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(ConversationSummaryAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(MeetingContextAdapter());
    }
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(AcquaintanceDurationAdapter());
    }
    if (!Hive.isAdapterRegistered(5)) Hive.registerAdapter(UserGoalAdapter());
    if (!Hive.isAdapterRegistered(6)) {
      Hive.registerAdapter(SessionContextAdapter());
    }
    if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(UserStyleAdapter());
    if (!Hive.isAdapterRegistered(17)) {
      Hive.registerAdapter(CoachChatResultAdapter());
    }
    if (!Hive.isAdapterRegistered(26)) {
      Hive.registerAdapter(UnifiedCoachResultAdapter());
    }
  });

  late ConversationRepository repo;

  setUp(() async {
    await Hive.openBox<Conversation>(AppConstants.conversationsBox);
    await Hive.openBox(AppConstants.settingsBox);
    await Hive.openBox<CoachChatResult>('coach_chat_results');
    await Hive.openBox<UnifiedCoachResult>('unified_coach_results');
    repo = ConversationRepository(currentUserIdOverride: () => _ownerId);
  });

  tearDown(() async {
    await Hive.deleteBoxFromDisk(AppConstants.conversationsBox);
    await Hive.deleteBoxFromDisk(AppConstants.settingsBox);
    await Hive.deleteBoxFromDisk('coach_chat_results');
    await Hive.deleteBoxFromDisk('unified_coach_results');
  });

  tearDownAll(() async {
    await Hive.close();
    final dir = Directory(_testHivePath);
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test(
      'deleteConversation 清掉該對話的 unified conversation rows，'
      '其他 conversation 與 partner scope 保留，legacy-17 清理照舊', () async {
    final c1 = _conversation('c1');
    await StorageService.conversationsBox.put(c1.id, c1);

    final legacyBox = StorageService.coachChatResultsBox;
    await legacyBox.put('l-c1', _legacyResult('l-c1', conversationId: 'c1'));
    await legacyBox.put('l-c2', _legacyResult('l-c2', conversationId: 'c2'));

    final unifiedBox = StorageService.unifiedCoachResultsBox;
    await unifiedBox.put(
      'u-c1-a',
      _unifiedResult('u-c1-a', scopeType: 'conversation', scopeId: 'c1'),
    );
    await unifiedBox.put(
      'u-c1-b',
      _unifiedResult('u-c1-b', scopeType: 'conversation', scopeId: 'c1'),
    );
    await unifiedBox.put(
      'u-c2',
      _unifiedResult('u-c2', scopeType: 'conversation', scopeId: 'c2'),
    );
    await unifiedBox.put(
      'u-p1',
      _unifiedResult('u-p1', scopeType: 'partner', scopeId: 'p1'),
    );

    final outcome = await repo.deleteConversation('c1');

    expect(outcome.deleted, isTrue);
    expect(outcome.cleanupError, isNull);
    expect(StorageService.conversationsBox.containsKey('c1'), isFalse);
    // unified：c1 的 conversation rows 清空，其他 scope 不波及。
    expect(
      unifiedBox.values.where(
        (r) => r.scopeType == 'conversation' && r.scopeId == 'c1',
      ),
      isEmpty,
    );
    expect(unifiedBox.keys, containsAll(['u-c2', 'u-p1']));
    expect(unifiedBox.length, 2);
    // legacy-17 既有清理行為不變。
    expect(legacyBox.keys, ['l-c2']);
  });

  test('unified box 未開時 deleteConversation 不炸，legacy 清理照舊', () async {
    final c1 = _conversation('c1');
    await StorageService.conversationsBox.put(c1.id, c1);
    await StorageService.coachChatResultsBox
        .put('l-c1', _legacyResult('l-c1', conversationId: 'c1'));

    await Hive.box<UnifiedCoachResult>('unified_coach_results').close();

    final outcome = await repo.deleteConversation('c1');

    expect(outcome.deleted, isTrue);
    expect(outcome.cleanupError, isNull);
    expect(StorageService.coachChatResultsBox.values, isEmpty);
  });

  test(
      'legacy-17 清理拋錯時 unified rows 仍被清掉，'
      '錯誤仍經 cleanupError 回報（review P2-1）', () async {
    final c1 = _conversation('c1');
    await StorageService.conversationsBox.put(c1.id, c1);

    final unifiedBox = StorageService.unifiedCoachResultsBox;
    await unifiedBox.put(
      'u-c1',
      _unifiedResult('u-c1', scopeType: 'conversation', scopeId: 'c1'),
    );
    await unifiedBox.put(
      'u-p1',
      _unifiedResult('u-p1', scopeType: 'partner', scopeId: 'p1'),
    );

    // 讓 legacy-17 段真的拋錯：把 coach_chat_results 換成 dynamic 型別重開，
    // isBoxOpen 仍為 true，但 typed accessor 取 Box<CoachChatResult> 會丟
    // HiveError（型別不符）。
    await Hive.box<CoachChatResult>('coach_chat_results').close();
    await Hive.openBox<dynamic>('coach_chat_results');

    final outcome = await repo.deleteConversation('c1');

    expect(outcome.deleted, isTrue);
    // 錯誤照既有慣例經 cleanupError 浮出，不被吞掉。
    expect(outcome.cleanupError, isNotNull);
    // legacy 段失敗不得連坐 unified 清理：c1 rows 必須清空。
    expect(
      unifiedBox.values.where(
        (r) => r.scopeType == 'conversation' && r.scopeId == 'c1',
      ),
      isEmpty,
    );
    expect(unifiedBox.keys, ['u-p1']);
  });

  test('deleteAll 清掉本人全部對話的 unified conversation rows', () async {
    final c1 = _conversation('c1');
    final c2 = _conversation('c2');
    final other = _conversation('c-other', ownerUserId: 'u2');
    await StorageService.conversationsBox.put(c1.id, c1);
    await StorageService.conversationsBox.put(c2.id, c2);
    await StorageService.conversationsBox.put(other.id, other);

    final unifiedBox = StorageService.unifiedCoachResultsBox;
    await unifiedBox.put(
      'u-c1',
      _unifiedResult('u-c1', scopeType: 'conversation', scopeId: 'c1'),
    );
    await unifiedBox.put(
      'u-c2',
      _unifiedResult('u-c2', scopeType: 'conversation', scopeId: 'c2'),
    );
    await unifiedBox.put(
      'u-other',
      _unifiedResult('u-other', scopeType: 'conversation', scopeId: 'c-other'),
    );
    await unifiedBox.put(
      'u-p1',
      _unifiedResult('u-p1', scopeType: 'partner', scopeId: 'p1'),
    );

    await repo.deleteAll();

    // 本人對話 c1/c2 的 unified rows 清空；他人對話與 partner scope 不波及。
    expect(unifiedBox.keys, containsAll(['u-other', 'u-p1']));
    expect(unifiedBox.length, 2);
    expect(StorageService.conversationsBox.keys, ['c-other']);
  });
}
