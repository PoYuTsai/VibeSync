import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/core/constants/app_constants.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_archive_providers.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_write_controller.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_archive_store.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_repository.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation_summary.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/conversation/domain/entities/session_context.dart';
import 'package:vibesync/features/analysis/data/providers/analysis_providers.dart';
import 'package:vibesync/features/analysis/data/providers/analysis_record_providers.dart';
import 'package:vibesync/features/partner/data/repositories/partner_repository.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/partner/presentation/utils/conversation_archive_sections.dart';
import 'package:vibesync/features/user_profile/data/providers/data_quality_flag_provider.dart';
import 'package:vibesync/features/user_profile/data/repositories/partner_data_quality_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_data_quality_state.dart';

/// In-memory ConversationRepository stub. Subclasses the real type so
/// `conversationRepositoryProvider.overrideWithValue(...)` accepts it.
/// Tracks how many times each partner's data source was queried — that
/// counter is what proves the narrow-invalidation contract.
class _FakeConversationRepository extends ConversationRepository {
  _FakeConversationRepository();

  final Map<String, Conversation> store = {};
  final Map<String, int> listByPartnerCalls = {};
  int globalListCalls = 0;
  int _idCounter = 0;
  Object? throwOnUpdate;
  void Function(Conversation)? onUpdate;
  Future<void> Function()? onDelete;
  Object? deleteCleanupError;

  @override
  Future<Conversation> createConversation({
    required String name,
    required List<Message> messages,
    String? partnerId,
  }) async {
    final c = Conversation(
      id: 'fake-${++_idCounter}',
      name: name,
      messages: messages,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      ownerUserId: 'u-1',
      partnerId: partnerId,
    );
    store[c.id] = c;
    return c;
  }

  @override
  Future<void> updateConversation(Conversation c) async {
    if (throwOnUpdate != null) throw throwOnUpdate!;
    store[c.id] = c;
    onUpdate?.call(c);
  }

  @override
  Future<ConversationDeleteOutcome> deleteConversation(String id) async {
    final removed = store.remove(id);
    if (removed == null) return const ConversationDeleteOutcome.notFound();
    await onDelete?.call();
    return ConversationDeleteOutcome(
      deleted: true,
      deletedOwnerUserId: removed.ownerUserId,
      cleanupError: deleteCleanupError,
      cleanupStackTrace: deleteCleanupError == null ? null : StackTrace.current,
    );
  }

  @override
  Conversation? getConversation(String id) => store[id];

  @override
  List<Conversation> listByPartner(String partnerId) {
    listByPartnerCalls[partnerId] = (listByPartnerCalls[partnerId] ?? 0) + 1;
    return store.values.where((c) => c.partnerId == partnerId).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  @override
  List<Conversation> getAllConversations() {
    globalListCalls++;
    return store.values.toList();
  }
}

class _MemoryConversationArchiveStore implements ConversationArchiveStore {
  final Map<String, ConversationArchiveEntry> entries = {};
  bool throwOnMarkActive = false;

  @override
  ConversationArchiveEntry? entryFor(Conversation conversation) =>
      entries[conversation.id];

  @override
  Future<void> markActive(
    Conversation conversation, {
    DateTime? changedAt,
    String? analyzedContentRevision,
  }) async {
    if (throwOnMarkActive) throw StateError('marker write failed');
    entries[conversation.id] = ConversationArchiveEntry.active(
      changedAt: changedAt ?? DateTime.now(),
      contentRevision:
          analyzedContentRevision ?? entries[conversation.id]?.contentRevision,
    );
  }

  @override
  Future<void> markArchived(
    Conversation conversation, {
    required DateTime archivedAt,
  }) async {
    entries[conversation.id] = ConversationArchiveEntry.archived(
      archivedAt: archivedAt,
      contentRevision: conversationContentRevision(conversation),
    );
  }

  @override
  Future<void> remove(Conversation conversation) async {
    entries.remove(conversation.id);
  }
}

late Box<Partner> partnerBox;
late _FakeConversationRepository _fakeRepo;
late _MemoryConversationArchiveStore _archiveStore;

Future<ProviderContainer> _makeContainer({String? ownerUserId = 'u-1'}) async {
  final container = ProviderContainer(overrides: [
    conversationRepositoryProvider.overrideWithValue(_fakeRepo),
    conversationArchiveStoreProvider.overrideWithValue(_archiveStore),
    analysisRecordOwnerProvider.overrideWithValue(ownerUserId),
    partnerRepositoryProvider
        .overrideWithValue(PartnerRepository(box: partnerBox)),
    authConversationScopeProvider
        .overrideWith((ref) => Stream.value(ownerUserId)),
  ]);
  // Settle the StreamProvider loading→data transition before any partner
  // read, so the auth state change doesn't invalidate downstream providers
  // mid-test and double our call counters.
  await container.read(authConversationScopeProvider.future);
  return container;
}

Conversation _convo(String id, {String? partnerId}) => Conversation(
      id: id,
      name: 'c-$id',
      messages: const [],
      createdAt: DateTime(2026, 4, 26, 10, 0),
      updatedAt: DateTime(2026, 4, 26, 10, 0),
      ownerUserId: 'u-1',
      partnerId: partnerId,
    );

Partner _partner(String id) => Partner(
      id: id,
      name: 'partner-$id',
      createdAt: DateTime(2026, 4, 26, 10, 0),
      updatedAt: DateTime(2026, 4, 26, 10, 0),
      ownerUserId: 'u-1',
    );

void main() {
  setUpAll(() {
    Hive.init('./.dart_tool/test_hive_write_controller');
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
    if (!Hive.isAdapterRegistered(8)) Hive.registerAdapter(PartnerAdapter());
    if (!Hive.isAdapterRegistered(14)) {
      Hive.registerAdapter(NamePairAdapter());
    }
    if (!Hive.isAdapterRegistered(15)) {
      Hive.registerAdapter(PartnerDataQualityStateAdapter());
    }
  });

  tearDownAll(() async {
    await Hive.close();
  });

  setUp(() async {
    _fakeRepo = _FakeConversationRepository();
    _archiveStore = _MemoryConversationArchiveStore();
    final ts = DateTime.now().microsecondsSinceEpoch;
    partnerBox = await Hive.openBox<Partner>('wc_partner_$ts');
    await partnerBox.put('p-X', _partner('p-X'));
    await partnerBox.put('p-Y', _partner('p-Y'));
    // conversationsProvider eventually reads this box via the real
    // ConversationRepository in production code; not used here directly,
    // but opening it keeps StorageService.conversationsBox happy if any
    // provider chain reaches it.
    await Hive.openBox<Conversation>(AppConstants.conversationsBox);
    await Hive.openBox<dynamic>(AppConstants.settingsBox);
  });

  tearDown(() async {
    await partnerBox.deleteFromDisk();
    await Hive.box<Conversation>(AppConstants.conversationsBox)
        .deleteFromDisk();
    await Hive.box<dynamic>(AppConstants.settingsBox).deleteFromDisk();
  });

  group('partnerListProvider', () {
    test('sorts partners by latest conversation interaction', () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);

      final xOld = _convo('x-old', partnerId: 'p-X')
        ..updatedAt = DateTime(2026, 4, 1);
      final yNew = _convo('y-new', partnerId: 'p-Y')
        ..updatedAt = DateTime(2026, 4, 3);
      _fakeRepo.store[xOld.id] = xOld;
      _fakeRepo.store[yNew.id] = yNew;

      final partners = container.read(partnerListProvider);

      expect(partners.map((p) => p.id), ['p-Y', 'p-X']);
    });

    test('reorders after controller save updates one partner activity',
        () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);

      final x = _convo('x', partnerId: 'p-X')..updatedAt = DateTime(2026, 4, 1);
      final y = _convo('y', partnerId: 'p-Y')..updatedAt = DateTime(2026, 4, 3);
      _fakeRepo.store[x.id] = x;
      _fakeRepo.store[y.id] = y;

      expect(
        container.read(partnerListProvider).map((p) => p.id),
        ['p-Y', 'p-X'],
      );

      x.updatedAt = DateTime(2026, 4, 4);
      await container
          .read(conversationWriteControllerProvider.notifier)
          .save(x);

      expect(
        container.read(partnerListProvider).map((p) => p.id),
        ['p-X', 'p-Y'],
      );
    });
  });

  group('ConversationWriteController.create', () {
    test('persists via repo with partnerId attached', () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);

      final c = await container
          .read(conversationWriteControllerProvider.notifier)
          .create(name: 'new', messages: const [], partnerId: 'p-X');

      expect(c.partnerId, 'p-X');
      expect(_fakeRepo.store[c.id]!.partnerId, 'p-X');
    });

    test('aggregate(X) reflects new conversation after create', () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);

      expect(container.read(partnerAggregateProvider('p-X')).totalMessages, 0);

      await container.read(conversationWriteControllerProvider.notifier).create(
            name: 'new',
            messages: [
              Message(
                id: 'm1',
                content: 'hi',
                isFromMe: false,
                timestamp: DateTime(2026, 4, 26),
              ),
            ],
            partnerId: 'p-X',
          );

      expect(container.read(partnerAggregateProvider('p-X')).totalMessages, 1);
    });

    test('null partnerId path persists conversation without partner scope',
        () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);

      // Prime partner data source so we can detect spurious invalidation.
      container.read(conversationsByPartnerProvider('p-X'));
      final xBefore = _fakeRepo.listByPartnerCalls['p-X']!;

      final c = await container
          .read(conversationWriteControllerProvider.notifier)
          .create(name: 'legacy', messages: const []);

      expect(c.partnerId, isNull,
          reason:
              'create without partnerId yields conversation with null partnerId');

      container.read(conversationsByPartnerProvider('p-X'));
      expect(_fakeRepo.listByPartnerCalls['p-X'], xBefore,
          reason: 'null partnerId on create must not touch any partner scope');
    });
  });

  group('ConversationWriteController.save', () {
    test('analysis completion archives only after the save succeeds', () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);
      final conversation = _convo('archive-me', partnerId: 'p-X');
      conversation.lastAnalysisSnapshotJson = '{"result":"saved"}';
      conversation.lastAnalyzedMessageCount = 0;
      _fakeRepo.store[conversation.id] = conversation;
      final analyzedRevision = conversationContentRevision(conversation);

      await container.read(conversationWriteControllerProvider.notifier).save(
            conversation,
            intent: ConversationSaveIntent.analysisCompleted,
            expectedContentRevision: analyzedRevision,
          );

      expect(
        _archiveStore.entryFor(conversation)?.status,
        ConversationArchiveStatus.archived,
      );
    });

    test('analysis completion without a durable snapshot stays active',
        () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);
      final conversation = _convo('no-snapshot', partnerId: 'p-X');
      _fakeRepo.store[conversation.id] = conversation;
      await _archiveStore.markArchived(
        conversation,
        archivedAt: DateTime.utc(2026, 7, 11),
      );

      await container.read(conversationWriteControllerProvider.notifier).save(
            conversation,
            intent: ConversationSaveIntent.analysisCompleted,
            expectedContentRevision: conversationContentRevision(conversation),
          );

      expect(
        _archiveStore.entryFor(conversation)?.status,
        ConversationArchiveStatus.active,
      );
      expect(
        _archiveStore.entryFor(conversation)?.contentRevision,
        conversationContentRevision(conversation),
      );
    });

    test('failed analysis snapshot save never archives the conversation',
        () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);
      final conversation = _convo('failed-analysis', partnerId: 'p-X');
      conversation.lastAnalysisSnapshotJson = '{"result":"not-saved"}';
      _fakeRepo.store[conversation.id] = conversation;
      _fakeRepo.throwOnUpdate = StateError('disk full');

      await expectLater(
        container.read(conversationWriteControllerProvider.notifier).save(
              conversation,
              intent: ConversationSaveIntent.analysisCompleted,
              expectedContentRevision:
                  conversationContentRevision(conversation),
            ),
        throwsA(isA<StateError>()),
      );

      expect(_archiveStore.entryFor(conversation), isNull);
    });

    test('missing analysis revision fails open instead of archiving', () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);
      final conversation = _convo('missing-revision', partnerId: 'p-X')
        ..lastAnalysisSnapshotJson = '{"result":"saved"}'
        ..lastAnalyzedMessageCount = 0;
      _fakeRepo.store[conversation.id] = conversation;

      await container.read(conversationWriteControllerProvider.notifier).save(
            conversation,
            intent: ConversationSaveIntent.analysisCompleted,
          );

      expect(
        _archiveStore.entryFor(conversation)?.status,
        ConversationArchiveStatus.active,
      );
    });

    test('same-count edit interleaved with analysis persistence stays active',
        () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);
      final conversation = _convo('stale-analysis', partnerId: 'p-X')
        ..messages = [
          Message(
            id: 'm-1',
            content: '分析時的內容',
            isFromMe: false,
            timestamp: DateTime(2026, 7, 11),
          ),
        ]
        ..lastAnalysisSnapshotJson = '{"result":"saved"}'
        ..lastAnalyzedMessageCount = 1;
      _fakeRepo.store[conversation.id] = conversation;
      final analyzedRevision = conversationContentRevision(conversation);
      _fakeRepo.onUpdate = (saved) {
        saved.messages = [
          Message(
            id: 'm-1',
            content: '分析完成前被改掉',
            isFromMe: false,
            timestamp: DateTime(2026, 7, 11),
          ),
        ];
      };

      await container.read(conversationWriteControllerProvider.notifier).save(
            conversation,
            intent: ConversationSaveIntent.analysisCompleted,
            expectedContentRevision: analyzedRevision,
          );

      expect(
        _archiveStore.entryFor(conversation)?.status,
        ConversationArchiveStatus.active,
      );
    });

    test('partial analysis snapshot stays active', () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);
      final conversation = _convo('partial-analysis', partnerId: 'p-X')
        ..messages = [
          Message(
            id: 'm-1',
            content: '她說',
            isFromMe: false,
            timestamp: DateTime(2026, 7, 11),
          ),
          Message(
            id: 'm-2',
            content: '我新增但這輪不分析',
            isFromMe: true,
            timestamp: DateTime(2026, 7, 11, 0, 1),
          ),
        ]
        ..lastAnalysisSnapshotJson = '{"result":"saved"}'
        ..lastAnalyzedMessageCount = 1;
      _fakeRepo.store[conversation.id] = conversation;

      await container.read(conversationWriteControllerProvider.notifier).save(
            conversation,
            intent: ConversationSaveIntent.analysisCompleted,
            expectedContentRevision: conversationContentRevision(conversation),
          );

      expect(
        _archiveStore.entryFor(conversation)?.status,
        ConversationArchiveStatus.active,
      );
      expect(
        _archiveStore.entryFor(conversation)?.contentRevision,
        conversationContentRevision(conversation, messageCount: 1),
      );
    });

    test('failed active-marker write cannot hide the saved content change',
        () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);
      final conversation = _convo('marker-failure', partnerId: 'p-X')
        ..messages = [
          Message(
            id: 'm-1',
            content: '舊內容',
            isFromMe: false,
            timestamp: DateTime(2026, 7, 11),
          ),
        ];
      _fakeRepo.store[conversation.id] = conversation;
      await _archiveStore.markArchived(
        conversation,
        archivedAt: DateTime.utc(2026, 7, 11),
      );
      conversation.messages = [
        Message(
          id: 'm-1',
          content: '已成功儲存的新內容',
          isFromMe: false,
          timestamp: DateTime(2026, 7, 11),
        ),
      ];
      _archiveStore.throwOnMarkActive = true;

      await container.read(conversationWriteControllerProvider.notifier).save(
            conversation,
            intent: ConversationSaveIntent.contentChanged,
          );

      final sections = partitionConversationsByArchive(
        [conversation],
        entryFor: _archiveStore.entryFor,
        latestAnalysisAtFor: (_) => null,
      );
      expect(sections.active.single.id, conversation.id);
      expect(sections.archived, isEmpty);
    });

    test('old archived marker cannot hide an invalid replacement snapshot',
        () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);
      final conversation = _convo('invalid-replacement', partnerId: 'p-X')
        ..lastAnalysisSnapshotJson = '{"result":"old"}'
        ..lastAnalyzedMessageCount = 0;
      _fakeRepo.store[conversation.id] = conversation;
      await _archiveStore.markArchived(
        conversation,
        archivedAt: DateTime.utc(2026, 7, 1),
      );
      final analyzedRevision = conversationContentRevision(conversation);
      conversation.lastAnalysisSnapshotJson = null;
      _archiveStore.throwOnMarkActive = true;

      await container.read(conversationWriteControllerProvider.notifier).save(
            conversation,
            intent: ConversationSaveIntent.analysisCompleted,
            expectedContentRevision: analyzedRevision,
          );

      final sections = partitionConversationsByArchive(
        [conversation],
        entryFor: _archiveStore.entryFor,
        latestAnalysisAtFor: (_) => null,
      );
      expect(sections.active.single.id, conversation.id);
      expect(sections.archived, isEmpty);
    });

    test('content change returns an archived conversation to active', () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);
      final conversation = _convo('edit-me', partnerId: 'p-X');
      _fakeRepo.store[conversation.id] = conversation;
      await _archiveStore.markArchived(
        conversation,
        archivedAt: DateTime.utc(2026, 7, 11),
      );

      await container
          .read(conversationWriteControllerProvider.notifier)
          .save(conversation);

      expect(
        _archiveStore.entryFor(conversation)?.status,
        ConversationArchiveStatus.active,
      );
    });

    test('metadata-only save preserves the archive state', () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);
      final conversation = _convo('move-me', partnerId: 'p-Y');
      _fakeRepo.store[conversation.id] = conversation;
      await _archiveStore.markArchived(
        conversation,
        archivedAt: DateTime.utc(2026, 7, 11),
      );

      await container.read(conversationWriteControllerProvider.notifier).save(
            conversation,
            previousPartnerId: 'p-X',
            intent: ConversationSaveIntent.metadataOnly,
          );

      expect(
        _archiveStore.entryFor(conversation)?.status,
        ConversationArchiveStatus.archived,
      );
    });

    test('metadata-only reassign can seed markerless legacy archive state',
        () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);
      final conversation = _convo('legacy-move', partnerId: 'p-Y')
        ..lastAnalysisSnapshotJson = '{"result":"saved"}'
        ..lastAnalyzedMessageCount = 0;
      _fakeRepo.store[conversation.id] = conversation;

      await container.read(conversationWriteControllerProvider.notifier).save(
            conversation,
            previousPartnerId: 'p-X',
            intent: ConversationSaveIntent.metadataOnly,
            preservedArchivedAt: DateTime.utc(2026, 7, 1),
          );

      final entry = _archiveStore.entryFor(conversation);
      expect(entry?.status, ConversationArchiveStatus.archived);
      expect(entry?.archivedAt, DateTime.utc(2026, 7, 1));
      expect(
        entry?.contentRevision,
        conversationContentRevision(conversation),
      );
    });

    test('persists then aggregate(X) reflects the saved conversation',
        () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);
      final c = _convo('c1', partnerId: 'p-X');
      _fakeRepo.store[c.id] = c;
      // Prime aggregate before the change so we observe a true rebuild.
      expect(container.read(partnerAggregateProvider('p-X')).totalRounds, 0);
      c.currentRound = 5;

      await container
          .read(conversationWriteControllerProvider.notifier)
          .save(c);

      expect(container.read(partnerAggregateProvider('p-X')).totalRounds, 5,
          reason: 'aggregate(X) must reflect updated round count');
    });

    test('reassign (previousPartnerId != current) re-queries BOTH partners',
        () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);
      final c = _convo('c1', partnerId: 'p-Y');
      _fakeRepo.store[c.id] = c;

      // Prime both partner data sources.
      container.read(conversationsByPartnerProvider('p-X'));
      container.read(conversationsByPartnerProvider('p-Y'));
      final xBefore = _fakeRepo.listByPartnerCalls['p-X'] ?? 0;
      final yBefore = _fakeRepo.listByPartnerCalls['p-Y'] ?? 0;

      await container
          .read(conversationWriteControllerProvider.notifier)
          .save(c, previousPartnerId: 'p-X');

      // Force re-read of both — invalidated providers should re-query.
      container.read(conversationsByPartnerProvider('p-X'));
      container.read(conversationsByPartnerProvider('p-Y'));
      expect(_fakeRepo.listByPartnerCalls['p-X']! - xBefore, 1,
          reason: 'old partner data source must be re-queried');
      expect(_fakeRepo.listByPartnerCalls['p-Y']! - yBefore, 1,
          reason: 'new partner data source must be re-queried');
    });

    test('null partnerId path skips partner-scope invalidation', () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);
      final c = _convo('c1', partnerId: null);
      _fakeRepo.store[c.id] = c;

      container.read(conversationsByPartnerProvider('p-X'));
      final xBefore = _fakeRepo.listByPartnerCalls['p-X']!;

      await container
          .read(conversationWriteControllerProvider.notifier)
          .save(c);

      // Re-read — if scope was untouched, Provider returns cached value
      // and listByPartner('p-X') is NOT called again.
      container.read(conversationsByPartnerProvider('p-X'));
      expect(_fakeRepo.listByPartnerCalls['p-X'], xBefore,
          reason: 'null partnerId must not touch any partner scope');
    });

    test('invalidates conversationProvider detail after save', () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);

      final firstMessage = Message(
        id: 'm1',
        content: '第一則她說',
        isFromMe: false,
        timestamp: DateTime(2026, 5, 5, 10),
      );
      final initial = _convo('detail-refresh', partnerId: 'p-X')
        ..messages = [firstMessage]
        ..lastAnalyzedMessageCount = 1;
      _fakeRepo.store[initial.id] = initial;

      expect(
        container
            .read(conversationProvider(initial.id))!
            .messages
            .map((message) => message.content),
        ['第一則她說'],
      );

      final updated = _convo('detail-refresh', partnerId: 'p-X')
        ..messages = [
          firstMessage,
          Message(
            id: 'm2',
            content: '第二則她說',
            isFromMe: false,
            timestamp: DateTime(2026, 5, 5, 10, 1),
          ),
        ]
        ..lastAnalyzedMessageCount = 1;

      await container
          .read(conversationWriteControllerProvider.notifier)
          .save(updated);

      final refreshed = container.read(conversationProvider(initial.id))!;
      expect(refreshed.messages.length, 2);
      expect(refreshed.messages.last.content, '第二則她說',
          reason:
              '續聊新增訊息後，AnalysisScreen 再讀 conversationProvider 時必須看到最新對話，否則會拿舊內容分析。');
    });
  });

  group('ConversationWriteController.delete', () {
    test('removes the archive marker with the conversation', () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);
      final conversation = _convo('delete-me', partnerId: 'p-X');
      _fakeRepo.store[conversation.id] = conversation;
      await _archiveStore.markArchived(
        conversation,
        archivedAt: DateTime.utc(2026, 7, 11),
      );

      await container
          .read(conversationWriteControllerProvider.notifier)
          .delete(conversation);

      expect(_archiveStore.entryFor(conversation), isNull);
    });

    test('removes current and archived independent analysis records', () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);
      final conversation = _convo('delete-private-records', partnerId: 'p-X')
        ..messages = [
          Message(
            id: 'm1',
            content: '第一段',
            isFromMe: false,
            timestamp: DateTime.utc(2026, 7, 15, 10),
          ),
        ];
      _fakeRepo.store[conversation.id] = conversation;
      final recordStore = container.read(analysisRecordStoreProvider);
      await recordStore.saveSuccessfulAnalysis(
        ownerUserId: 'u-1',
        conversation: conversation,
        completionKey: 'run-1',
        runStartPreviousCount: 0,
        analyzedMessageCount: 1,
        analyzedContentRevision: conversationContentRevision(conversation),
        analysisSnapshotJson: '{}',
        enthusiasmScore: 60,
        gameStageLabel: 'opening',
      );
      conversation.messages.add(
        Message(
          id: 'm2',
          content: '第二段',
          isFromMe: true,
          timestamp: DateTime.utc(2026, 7, 15, 10, 1),
        ),
      );
      await recordStore.saveSuccessfulAnalysis(
        ownerUserId: 'u-1',
        conversation: conversation,
        completionKey: 'run-2',
        runStartPreviousCount: 1,
        analyzedMessageCount: 2,
        analyzedContentRevision: conversationContentRevision(conversation),
        analysisSnapshotJson: '{}',
        enthusiasmScore: 62,
        gameStageLabel: 'opening',
      );
      expect(
        recordStore.listArchived(
          ownerUserId: 'u-1',
          conversationIds: [conversation.id],
        ),
        hasLength(1),
      );

      await container
          .read(conversationWriteControllerProvider.notifier)
          .delete(conversation);

      expect(
        recordStore.currentFor(
          ownerUserId: 'u-1',
          conversationId: conversation.id,
        ),
        isNull,
      );
      expect(
        recordStore.listArchived(
          ownerUserId: 'u-1',
          conversationIds: [conversation.id],
        ),
        isEmpty,
      );
    });

    test('expired session cannot erase a still-live conversation record',
        () async {
      final container = await _makeContainer(ownerUserId: null);
      addTearDown(container.dispose);
      final conversation = _convo('expired-delete', partnerId: 'p-X')
        ..messages = [
          Message(
            id: 'm-expired',
            content: '私密分析',
            isFromMe: false,
            timestamp: DateTime.utc(2026, 7, 15),
          ),
        ];
      _fakeRepo.store[conversation.id] = conversation;
      final recordStore = container.read(analysisRecordStoreProvider);
      await recordStore.saveSuccessfulAnalysis(
        ownerUserId: 'u-1',
        conversation: conversation,
        completionKey: 'expired-run',
        runStartPreviousCount: 0,
        analyzedMessageCount: 1,
        analyzedContentRevision: conversationContentRevision(conversation),
        analysisSnapshotJson: '{}',
        enthusiasmScore: 50,
        gameStageLabel: 'opening',
      );

      await expectLater(
        container
            .read(conversationWriteControllerProvider.notifier)
            .delete(conversation),
        throwsStateError,
      );

      expect(_fakeRepo.store.containsKey(conversation.id), isTrue);
      expect(
        recordStore.currentFor(
          ownerUserId: 'u-1',
          conversationId: conversation.id,
        ),
        isNotNull,
      );
    });

    test('active user cannot cascade-delete another owner record', () async {
      final container = await _makeContainer(ownerUserId: 'u-1');
      addTearDown(container.dispose);
      final conversation = _convo('owner-mismatch', partnerId: 'p-X')
        ..ownerUserId = 'u-2'
        ..messages = [
          Message(
            id: 'm-other-owner',
            content: '另一個帳號的私密分析',
            isFromMe: false,
            timestamp: DateTime.utc(2026, 7, 15),
          ),
        ];
      _fakeRepo.store[conversation.id] = conversation;
      final recordStore = container.read(analysisRecordStoreProvider);
      await recordStore.saveSuccessfulAnalysis(
        ownerUserId: 'u-2',
        conversation: conversation,
        completionKey: 'other-owner-run',
        runStartPreviousCount: 0,
        analyzedMessageCount: 1,
        analyzedContentRevision: conversationContentRevision(conversation),
        analysisSnapshotJson: '{}',
        enthusiasmScore: 50,
        gameStageLabel: 'opening',
      );

      await expectLater(
        container
            .read(conversationWriteControllerProvider.notifier)
            .delete(conversation),
        throwsStateError,
      );

      expect(_fakeRepo.store.containsKey(conversation.id), isTrue);
      expect(
        recordStore.currentFor(
          ownerUserId: 'u-2',
          conversationId: conversation.id,
        ),
        isNotNull,
      );
    });

    test('repository no-op cancels cleanup marker and preserves records',
        () async {
      final container = await _makeContainer(ownerUserId: 'u-1');
      addTearDown(container.dispose);
      final conversation = _convo('repo-no-op', partnerId: 'p-X')
        ..messages = [
          Message(
            id: 'm-no-op',
            content: '主對話已不可刪時仍須保留',
            isFromMe: false,
            timestamp: DateTime.utc(2026, 7, 15),
          ),
        ];
      final recordStore = container.read(analysisRecordStoreProvider);
      await recordStore.saveSuccessfulAnalysis(
        ownerUserId: 'u-1',
        conversation: conversation,
        completionKey: 'repo-no-op-run',
        runStartPreviousCount: 0,
        analyzedMessageCount: 1,
        analyzedContentRevision: conversationContentRevision(conversation),
        analysisSnapshotJson: '{}',
        enthusiasmScore: 50,
        gameStageLabel: 'opening',
      );
      // Deliberately do not insert the conversation into _fakeRepo: the
      // repository must report that no authoritative delete was committed.
      await expectLater(
        container
            .read(conversationWriteControllerProvider.notifier)
            .delete(conversation),
        throwsStateError,
      );

      expect(
        recordStore.currentFor(
          ownerUserId: 'u-1',
          conversationId: conversation.id,
        ),
        isNotNull,
      );
      expect(
        recordStore.hasPendingConversationRemovals(ownerUserId: 'u-1'),
        isFalse,
      );
    });

    test('post-commit repository cleanup error still finishes private cascades',
        () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);
      final conversation = _convo('coach-cleanup-failed', partnerId: 'p-X')
        ..messages = [
          Message(
            id: 'm-coach-cleanup',
            content: '保留到刪除完成的私密分析',
            isFromMe: false,
            timestamp: DateTime.utc(2026, 7, 15),
          ),
        ];
      _fakeRepo.store[conversation.id] = conversation;
      await _archiveStore.markArchived(
        conversation,
        archivedAt: DateTime.utc(2026, 7, 15),
      );
      final recordStore = container.read(analysisRecordStoreProvider);
      await recordStore.saveSuccessfulAnalysis(
        ownerUserId: 'u-1',
        conversation: conversation,
        completionKey: 'coach-cleanup-run',
        runStartPreviousCount: 0,
        analyzedMessageCount: 1,
        analyzedContentRevision: conversationContentRevision(conversation),
        analysisSnapshotJson: '{}',
        enthusiasmScore: 50,
        gameStageLabel: 'opening',
      );
      _fakeRepo.deleteCleanupError = StateError('coach cleanup failed');

      await expectLater(
        container
            .read(conversationWriteControllerProvider.notifier)
            .delete(conversation),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'coach cleanup failed',
          ),
        ),
      );

      expect(_fakeRepo.store.containsKey(conversation.id), isFalse);
      expect(_archiveStore.entryFor(conversation), isNull);
      expect(
        recordStore.currentFor(
          ownerUserId: 'u-1',
          conversationId: conversation.id,
        ),
        isNull,
      );
      expect(
        recordStore.hasPendingConversationRemovals(ownerUserId: 'u-1'),
        isFalse,
      );
    });

    test('cleanup failure keeps a durable marker and recovery finishes later',
        () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);
      final conversation = _convo('retry-private-cleanup', partnerId: 'p-X')
        ..messages = [
          Message(
            id: 'm-retry',
            content: '需要稍後清理的私密分析',
            isFromMe: false,
            timestamp: DateTime.utc(2026, 7, 15),
          ),
        ];
      _fakeRepo.store[conversation.id] = conversation;
      await _archiveStore.markArchived(
        conversation,
        archivedAt: DateTime.utc(2026, 7, 15),
      );
      final recordStore = container.read(analysisRecordStoreProvider);
      await recordStore.saveSuccessfulAnalysis(
        ownerUserId: 'u-1',
        conversation: conversation,
        completionKey: 'cleanup-retry-run',
        runStartPreviousCount: 0,
        analyzedMessageCount: 1,
        analyzedContentRevision: conversationContentRevision(conversation),
        analysisSnapshotJson: '{}',
        enthusiasmScore: 50,
        gameStageLabel: 'opening',
      );
      _fakeRepo.onDelete = () async {
        await Hive.box<dynamic>(AppConstants.settingsBox).close();
      };

      await expectLater(
        container
            .read(conversationWriteControllerProvider.notifier)
            .delete(conversation),
        throwsA(anything),
      );

      expect(_fakeRepo.store.containsKey(conversation.id), isFalse);
      expect(_archiveStore.entryFor(conversation), isNull);
      final reopened = await Hive.openBox<dynamic>(AppConstants.settingsBox);
      final cleanupKey = 'analysis_record_cleanup_v1:u-1:${conversation.id}';
      expect(reopened.containsKey(cleanupKey), isTrue);

      expect(
        await recordStore.recoverPendingConversationRemovals(
          ownerUserId: 'u-1',
          liveConversationIds: const [],
        ),
        1,
      );
      expect(reopened.containsKey(cleanupKey), isFalse);
      expect(
        recordStore.currentFor(
          ownerUserId: 'u-1',
          conversationId: conversation.id,
        ),
        isNull,
      );
    });

    test('removes from repo and aggregate(X) reflects removal', () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);
      final c = _convo('c1', partnerId: 'p-X');
      _fakeRepo.store[c.id] = c;
      // Prime so the aggregate sees the conversation first.
      expect(container.read(partnerAggregateProvider('p-X')).totalRounds, 0);

      await container
          .read(conversationWriteControllerProvider.notifier)
          .delete(c);

      expect(_fakeRepo.store.containsKey(c.id), isFalse);
      // After invalidate + re-read, list is empty again — proves invalidate ran.
      expect(container.read(conversationsByPartnerProvider('p-X')), isEmpty);
    });
  });

  group('Narrow contract — cross-partner fan-out防火 (HS-A2-1)', () {
    test(
        'writing partner X does NOT cause partner Y data source to be re-queried',
        () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);

      // Auth scope is a StreamProvider — let the loading→data transition
      // settle BEFORE priming partner reads, otherwise the auth state
      // change would invalidate both partners and double the call counts.
      await container.read(authConversationScopeProvider.future);

      // Prime both data sources.
      container.read(conversationsByPartnerProvider('p-X'));
      container.read(conversationsByPartnerProvider('p-Y'));
      final yPrime = _fakeRepo.listByPartnerCalls['p-Y']!;
      expect(yPrime, 1);

      await container
          .read(conversationWriteControllerProvider.notifier)
          .create(name: 'x-only', messages: const [], partnerId: 'p-X');

      // Force re-read of both — only X should re-query its source.
      container.read(conversationsByPartnerProvider('p-X'));
      container.read(conversationsByPartnerProvider('p-Y'));

      expect(_fakeRepo.listByPartnerCalls['p-X'], 2,
          reason: 'X data source must be re-queried after invalidate');
      expect(_fakeRepo.listByPartnerCalls['p-Y'], yPrime,
          reason: 'Y data source must NOT be re-queried — narrow contract');
    });
  });

  group('Spec 3 Task 17 — dataQualityFlagProvider invalidation', () {
    test('create with new candidate name flips flag from unflagged to flagged',
        () async {
      // Use a real PartnerDataQualityRepository backed by an injected Hive
      // box so `dataQualityFlagProvider` can read confirmed-pairs state
      // without touching auth-gated StorageService boxes.
      final ts = DateTime.now().microsecondsSinceEpoch;
      final dqBox = await Hive.openBox<PartnerDataQualityState>('dq_$ts');
      addTearDown(() async => dqBox.deleteFromDisk());
      final dqRepo = PartnerDataQualityRepository(injectedBox: dqBox);

      final container = ProviderContainer(overrides: [
        conversationRepositoryProvider.overrideWithValue(_fakeRepo),
        conversationArchiveStoreProvider.overrideWithValue(_archiveStore),
        partnerRepositoryProvider
            .overrideWithValue(PartnerRepository(box: partnerBox)),
        authConversationScopeProvider
            .overrideWith((ref) => Stream.value('u-1')),
        partnerDataQualityRepoProvider.overrideWithValue(dqRepo),
      ]);
      addTearDown(container.dispose);
      await container.read(authConversationScopeProvider.future);

      // Seed with one conversation whose name yields candidate "May".
      final c1 = Conversation(
        id: 'c1',
        name: 'May',
        messages: const [],
        createdAt: DateTime(2026, 5, 1),
        updatedAt: DateTime(2026, 5, 1),
        ownerUserId: 'u-1',
        partnerId: 'p-X',
      );
      _fakeRepo.store[c1.id] = c1;

      // First read: 1 candidate → unflagged.
      expect(container.read(dataQualityFlagProvider('p-X')).isFlagged, isFalse,
          reason: 'baseline 1 candidate must be unflagged');

      // Add a second conversation with a DIFFERENT candidate via the
      // controller — this is the change under test (Task 17 invalidation).
      await container
          .read(conversationWriteControllerProvider.notifier)
          .create(name: 'Anna', messages: const [], partnerId: 'p-X');

      // Second read: flag must re-evaluate and become flagged.
      // If the controller did NOT invalidate dataQualityFlagProvider, the
      // cached unflagged value would persist and this assertion would fail.
      final flag = container.read(dataQualityFlagProvider('p-X'));
      expect(flag.isFlagged, isTrue,
          reason:
              'controller.create must invalidate dataQualityFlagProvider so '
              'the new candidate triggers re-evaluation');
      expect(flag.conflictingPair, isNotNull);
    });
  });

  group('Legacy global contract — A2 transition (post-A2 cleanup retires this)',
      () {
    test('every write invalidates the legacy conversationsProvider', () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);

      // Prime the global feed via getAllConversations().
      container.read(conversationsProvider);
      final base = _fakeRepo.globalListCalls;

      await container
          .read(conversationWriteControllerProvider.notifier)
          .create(name: 'x', messages: const [], partnerId: 'p-X');
      container.read(conversationsProvider);
      expect(_fakeRepo.globalListCalls, base + 1,
          reason: 'create must invalidate legacy global');

      final c = _convo('c1', partnerId: 'p-X');
      _fakeRepo.store[c.id] = c;
      await container
          .read(conversationWriteControllerProvider.notifier)
          .save(c);
      container.read(conversationsProvider);
      expect(_fakeRepo.globalListCalls, base + 2,
          reason: 'save must invalidate legacy global');

      await container
          .read(conversationWriteControllerProvider.notifier)
          .delete(c);
      container.read(conversationsProvider);
      expect(_fakeRepo.globalListCalls, base + 3,
          reason: 'delete must invalidate legacy global');
    });
  });
}
