import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/core/constants/app_constants.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_write_controller.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_repository.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation_summary.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/conversation/domain/entities/session_context.dart';
import 'package:vibesync/features/partner/data/repositories/partner_repository.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';

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
    store[c.id] = c;
  }

  @override
  Future<void> deleteConversation(String id) async {
    store.remove(id);
  }

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

late Box<Partner> partnerBox;
late _FakeConversationRepository _fakeRepo;

Future<ProviderContainer> _makeContainer() async {
  final container = ProviderContainer(overrides: [
    conversationRepositoryProvider.overrideWithValue(_fakeRepo),
    partnerRepositoryProvider
        .overrideWithValue(PartnerRepository(box: partnerBox)),
    authConversationScopeProvider
        .overrideWith((ref) => Stream.value('u-1')),
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
  });

  tearDownAll(() async {
    await Hive.close();
  });

  setUp(() async {
    _fakeRepo = _FakeConversationRepository();
    final ts = DateTime.now().microsecondsSinceEpoch;
    partnerBox = await Hive.openBox<Partner>('wc_partner_$ts');
    await partnerBox.put('p-X', _partner('p-X'));
    await partnerBox.put('p-Y', _partner('p-Y'));
    // conversationsProvider eventually reads this box via the real
    // ConversationRepository in production code; not used here directly,
    // but opening it keeps StorageService.conversationsBox happy if any
    // provider chain reaches it.
    await Hive.openBox<Conversation>(AppConstants.conversationsBox);
  });

  tearDown(() async {
    await partnerBox.deleteFromDisk();
    await Hive.box<Conversation>(AppConstants.conversationsBox).deleteFromDisk();
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

      await container
          .read(conversationWriteControllerProvider.notifier)
          .create(
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
  });

  group('ConversationWriteController.save', () {
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

      expect(
          container.read(partnerAggregateProvider('p-X')).totalRounds, 5,
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
  });

  group('ConversationWriteController.delete', () {
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
