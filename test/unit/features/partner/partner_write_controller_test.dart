// Asserts that PartnerWriteController.merge invalidates the full set of
// partner-scoped + conversation-scoped Riverpod providers around both
// sides of a merge. PartnerRepository (no Ref) cannot do this itself;
// the controller is the single invalidation owner for partner writes.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/core/constants/app_constants.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_repository.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation_summary.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/conversation/domain/entities/session_context.dart';
import 'package:vibesync/features/partner/data/providers/partner_write_controller.dart';
import 'package:vibesync/features/partner/data/repositories/partner_repository.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';

/// Counting subclass — delegates to the real Hive-backed implementation but
/// records call counts. We need real reads (so post-merge state surfaces) AND
/// counters (so we can prove `conversationsProvider` was invalidated even
/// though its returned list size doesn't change after a re-point).
class _CountingConversationRepository extends ConversationRepository {
  _CountingConversationRepository();

  int globalListCalls = 0;
  final Map<String, int> listByPartnerCalls = {};

  @override
  List<Conversation> getAllConversations() {
    globalListCalls++;
    return super.getAllConversations();
  }

  @override
  List<Conversation> listByPartner(String partnerId) {
    listByPartnerCalls[partnerId] = (listByPartnerCalls[partnerId] ?? 0) + 1;
    return super.listByPartner(partnerId);
  }
}

late Box<Partner> partnerBox;
late Box<Conversation> convoBox;
late _CountingConversationRepository convoRepo;

Future<ProviderContainer> _makeContainer() async {
  final container = ProviderContainer(overrides: [
    conversationRepositoryProvider.overrideWithValue(convoRepo),
    partnerRepositoryProvider
        .overrideWithValue(PartnerRepository(box: partnerBox)),
    authConversationScopeProvider.overrideWith((ref) => Stream.value('u-1')),
  ]);
  // Settle the StreamProvider loading→data transition before any partner
  // read; otherwise the auth-state change would invalidate downstream
  // providers mid-test and double our call counters (see Phase 1 test).
  await container.read(authConversationScopeProvider.future);
  return container;
}

Partner _partner(String id, {String name = ''}) => Partner(
      id: id,
      name: name.isEmpty ? id : name,
      ownerUserId: 'u-1',
      createdAt: DateTime(2026, 4, 27),
      updatedAt: DateTime(2026, 4, 27),
    );

Conversation _convo(String id, {required String partnerId, int rounds = 1}) {
  final c = Conversation(
    id: id,
    name: 'c-$id',
    messages: const [],
    createdAt: DateTime(2026, 4, 27),
    updatedAt: DateTime(2026, 4, 27),
    ownerUserId: 'u-1',
    partnerId: partnerId,
  );
  c.currentRound = rounds;
  return c;
}

void main() {
  setUpAll(() {
    Hive.init('./.dart_tool/test_hive_partner_write_controller');
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
    final ts = DateTime.now().microsecondsSinceEpoch;
    partnerBox = await Hive.openBox<Partner>('pwc_partner_$ts');
    // Open the canonical conversations box because PartnerRepository.merge
    // and the real ConversationRepository both reach for
    // StorageService.conversationsBox = Hive.box(AppConstants.conversationsBox).
    convoBox =
        await Hive.openBox<Conversation>(AppConstants.conversationsBox);
    convoRepo = _CountingConversationRepository();
  });

  tearDown(() async {
    await partnerBox.deleteFromDisk();
    await convoBox.deleteFromDisk();
  });

  group('PartnerWriteController.merge invalidations', () {
    test(
        'merge invalidates both partner sides + their conversation scopes + '
        'partner list + legacy global', () async {
      // Seed: A with 2 conversations (1 round each), B with 0
      await partnerBox.put('A', _partner('A', name: 'Alice'));
      await partnerBox.put('B', _partner('B', name: 'Bob'));
      await convoBox.put('c1', _convo('c1', partnerId: 'A'));
      await convoBox.put('c2', _convo('c2', partnerId: 'A'));

      final container = await _makeContainer();
      addTearDown(container.dispose);

      // Prime providers — force them to subscribe and cache pre-merge values.
      expect(container.read(partnerByIdProvider('A')), isNotNull);
      expect(container.read(partnerListProvider).length, 2);
      expect(container.read(conversationsByPartnerProvider('A')).length, 2);
      expect(container.read(conversationsByPartnerProvider('B')), isEmpty);
      expect(container.read(partnerAggregateProvider('A')).totalRounds, 2);
      expect(container.read(partnerAggregateProvider('B')).totalRounds, 0);
      container.read(conversationsProvider);
      final globalBefore = convoRepo.globalListCalls;

      // Action
      await container
          .read(partnerWriteControllerProvider.notifier)
          .merge(fromId: 'A', toId: 'B');

      // Re-reads — values must reflect post-merge Hive state. If invalidate
      // wasn't called, Riverpod returns the cached pre-merge value and these
      // assertions fail.
      expect(container.read(partnerByIdProvider('A')), isNull,
          reason: 'A is deleted; partnerByIdProvider(A) must not stale-cache');
      expect(container.read(partnerByIdProvider('B')), isNotNull);
      expect(container.read(partnerListProvider).map((p) => p.id), ['B']);
      expect(container.read(conversationsByPartnerProvider('A')), isEmpty,
          reason: 'A scope must re-query after invalidate');
      expect(container.read(conversationsByPartnerProvider('B')).length, 2,
          reason: 'B scope must re-query after invalidate');
      expect(container.read(partnerAggregateProvider('B')).totalRounds, 2,
          reason: 'B aggregate must re-evaluate after invalidate');

      container.read(conversationsProvider);
      expect(convoRepo.globalListCalls, greaterThan(globalBefore),
          reason: 'legacy global feed must be invalidated (A2 transition)');
    });

    test('same-id merge is a no-op (no throw, no provider thrash)', () async {
      await partnerBox.put('A', _partner('A'));
      await convoBox.put('c1', _convo('c1', partnerId: 'A'));

      final container = await _makeContainer();
      addTearDown(container.dispose);

      // Prime
      container.read(partnerListProvider);
      container.read(conversationsByPartnerProvider('A'));
      final aQueriesBefore = convoRepo.listByPartnerCalls['A'] ?? 0;

      await container
          .read(partnerWriteControllerProvider.notifier)
          .merge(fromId: 'A', toId: 'A');

      // No throw. Force re-read; if no invalidation happened, count is unchanged.
      container.read(conversationsByPartnerProvider('A'));
      expect(convoRepo.listByPartnerCalls['A'], aQueriesBefore,
          reason: 'same-id merge must not invalidate any partner scope');
      expect(container.read(partnerByIdProvider('A')), isNotNull,
          reason: 'partner A still exists');
    });

    test('merge throws ArgumentError when source missing', () async {
      await partnerBox.put('B', _partner('B'));
      final container = await _makeContainer();
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(partnerWriteControllerProvider.notifier)
            .merge(fromId: 'ghost', toId: 'B'),
        throwsArgumentError,
      );
    });

    test('merge throws ArgumentError when target missing', () async {
      await partnerBox.put('A', _partner('A'));
      final container = await _makeContainer();
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(partnerWriteControllerProvider.notifier)
            .merge(fromId: 'A', toId: 'ghost'),
        throwsArgumentError,
      );
    });
  });
}
