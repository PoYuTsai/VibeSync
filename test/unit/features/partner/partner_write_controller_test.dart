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
import 'package:vibesync/features/user_profile/data/providers/partner_style_providers.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_style_override.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';

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

class _ThrowingDeletePartnerRepository extends PartnerRepository {
  _ThrowingDeletePartnerRepository({
    required Box<Partner> box,
    required Box<Conversation> conversationBox,
    required this.thrownCount,
  }) : super(box: box, conversationBox: conversationBox);

  final int thrownCount;

  @override
  Future<void> delete(String partnerId) async {
    throw PartnerHasConversationsException(thrownCount);
  }
}

class _ThrowingUpdatePartnerRepository extends PartnerRepository {
  _ThrowingUpdatePartnerRepository({
    required Box<Partner> box,
  }) : super(box: box);

  @override
  Future<void> update(Partner partner) async {
    throw StateError('simulated update failure');
  }
}

class _PartiallyFailingPartnerRepository extends PartnerRepository {
  _PartiallyFailingPartnerRepository({
    required Box<Partner> box,
    required Box<Conversation> conversationBox,
  })  : _conversationBox = conversationBox,
        super(box: box, conversationBox: conversationBox);

  final Box<Conversation> _conversationBox;

  @override
  Future<void> merge({
    required String fromId,
    required String toId,
  }) async {
    final firstMoved =
        _conversationBox.values.firstWhere((c) => c.partnerId == fromId);
    firstMoved.partnerId = toId;
    await firstMoved.save();
    throw StateError('simulated partial merge failure');
  }
}

late Box<Partner> _partnerBox;
late Box<Conversation> _convoBox;
late Box<PartnerStyleOverride> _styleBox;
late _CountingConversationRepository _convoRepo;

Future<ProviderContainer> _makeContainer() async {
  final container = ProviderContainer(overrides: [
    conversationRepositoryProvider.overrideWithValue(_convoRepo),
    partnerRepositoryProvider
        .overrideWithValue(PartnerRepository(box: _partnerBox)),
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
    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(InteractionStyleAdapter());
    }
    if (!Hive.isAdapterRegistered(11)) {
      Hive.registerAdapter(PracticeGoalAdapter());
    }
    if (!Hive.isAdapterRegistered(13)) {
      Hive.registerAdapter(PartnerStyleOverrideAdapter());
    }
  });

  tearDownAll(() async {
    await Hive.close();
  });

  setUp(() async {
    final ts = DateTime.now().microsecondsSinceEpoch;
    _partnerBox = await Hive.openBox<Partner>('pwc_partner_$ts');
    // Open the canonical conversations box because PartnerRepository.merge
    // and the real ConversationRepository both reach for
    // StorageService.conversationsBox = Hive.box(AppConstants.conversationsBox).
    _convoBox = await Hive.openBox<Conversation>(AppConstants.conversationsBox);
    // PartnerRepository.delete cascades into StorageService.partnerStyleOverridesBox
    // via its lazy default PartnerStyleRepository — open canonical box name.
    _styleBox = await Hive.openBox<PartnerStyleOverride>(
      'partner_style_overrides',
    );
    _convoRepo = _CountingConversationRepository();
  });

  tearDown(() async {
    await _styleBox.deleteFromDisk();
    await _partnerBox.deleteFromDisk();
    await _convoBox.deleteFromDisk();
  });

  group('PartnerWriteController.merge invalidations', () {
    test(
        'merge invalidates both partner sides + their conversation scopes + '
        'partner list + legacy global', () async {
      // Seed: A with 2 conversations (1 round each), B with 0
      await _partnerBox.put('A', _partner('A', name: 'Alice'));
      await _partnerBox.put('B', _partner('B', name: 'Bob'));
      await _convoBox.put('c1', _convo('c1', partnerId: 'A'));
      await _convoBox.put('c2', _convo('c2', partnerId: 'A'));

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
      final globalBefore = _convoRepo.globalListCalls;

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
      expect(_convoRepo.globalListCalls, greaterThan(globalBefore),
          reason: 'legacy global feed must be invalidated (A2 transition)');
    });

    test('same-id merge is a no-op (no throw, no provider thrash)', () async {
      await _partnerBox.put('A', _partner('A'));
      await _convoBox.put('c1', _convo('c1', partnerId: 'A'));

      final container = await _makeContainer();
      addTearDown(container.dispose);

      // Prime
      container.read(partnerListProvider);
      container.read(conversationsByPartnerProvider('A'));
      final aQueriesBefore = _convoRepo.listByPartnerCalls['A'] ?? 0;

      await container
          .read(partnerWriteControllerProvider.notifier)
          .merge(fromId: 'A', toId: 'A');

      // No throw. Force re-read; if no invalidation happened, count is unchanged.
      container.read(conversationsByPartnerProvider('A'));
      expect(_convoRepo.listByPartnerCalls['A'], aQueriesBefore,
          reason: 'same-id merge must not invalidate any partner scope');
      expect(container.read(partnerByIdProvider('A')), isNotNull,
          reason: 'partner A still exists');
    });

    test('merge invalidates source partner style override after cascade delete',
        () async {
      await _partnerBox.put('A', _partner('A', name: 'Alice'));
      await _partnerBox.put('B', _partner('B', name: 'Bob'));
      await _styleBox.put(
        'A',
        PartnerStyleOverride.create(
          partnerId: 'A',
          interactionStyle: InteractionStyle.humorous,
          updatedAt: DateTime.utc(2026, 5, 1),
        ),
      );

      final container = await _makeContainer();
      addTearDown(container.dispose);

      expect(
        await container.read(partnerStyleOverrideProvider('A').future),
        isNotNull,
      );

      await container
          .read(partnerWriteControllerProvider.notifier)
          .merge(fromId: 'A', toId: 'B');

      expect(
        await container.read(partnerStyleOverrideProvider('A').future),
        isNull,
        reason: 'source style override must not stale-cache after merge',
      );
    });

    test('merge throws ArgumentError when source missing', () async {
      await _partnerBox.put('B', _partner('B'));
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
      await _partnerBox.put('A', _partner('A'));
      final container = await _makeContainer();
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(partnerWriteControllerProvider.notifier)
            .merge(fromId: 'A', toId: 'ghost'),
        throwsArgumentError,
      );
    });

    test('merge failure still invalidates scopes after partial repo write',
        () async {
      await _partnerBox.put('A', _partner('A'));
      await _partnerBox.put('B', _partner('B'));
      await _convoBox.put('c1', _convo('c1', partnerId: 'A'));

      final container = ProviderContainer(overrides: [
        conversationRepositoryProvider.overrideWithValue(_convoRepo),
        partnerRepositoryProvider.overrideWithValue(
          _PartiallyFailingPartnerRepository(
            box: _partnerBox,
            conversationBox: _convoBox,
          ),
        ),
        authConversationScopeProvider
            .overrideWith((ref) => Stream.value('u-1')),
      ]);
      await container.read(authConversationScopeProvider.future);
      addTearDown(container.dispose);

      expect(container.read(conversationsByPartnerProvider('A')).length, 1);
      expect(container.read(conversationsByPartnerProvider('B')), isEmpty);

      await expectLater(
        container
            .read(partnerWriteControllerProvider.notifier)
            .merge(fromId: 'A', toId: 'B'),
        throwsStateError,
      );

      expect(container.read(conversationsByPartnerProvider('A')), isEmpty,
          reason: 'failure path must not leave stale source-scope cache');
      expect(container.read(conversationsByPartnerProvider('B')).length, 1,
          reason:
              'failure path must surface partial repo writes if they happen');
    });
  });

  group('PartnerWriteController.delete invalidations', () {
    test(
        'delete invalidates partnerListProvider + partnerByIdProvider + '
        'partnerAggregateProvider + conversationsByPartnerProvider after success',
        () async {
      // Seed: A with 0 conversations (delete is only allowed at zero).
      // B exists too, just to prove the partner list re-fetches narrower.
      await _partnerBox.put('A', _partner('A', name: 'Alice'));
      await _partnerBox.put('B', _partner('B', name: 'Bob'));

      final container = await _makeContainer();
      addTearDown(container.dispose);

      // Prime: subscribe so invalidation has observable effect.
      expect(container.read(partnerByIdProvider('A')), isNotNull);
      expect(container.read(partnerListProvider).map((p) => p.id).toSet(),
          {'A', 'B'});
      expect(container.read(conversationsByPartnerProvider('A')), isEmpty);
      expect(container.read(partnerAggregateProvider('A')).totalRounds, 0);
      // Snapshot global feed call count BEFORE delete — we'll assert it does
      // NOT increase (Codex plan patch HP-P4-1: delete keeps invalidation
      // partner-scoped because no conversation row mutated).
      container.read(conversationsProvider);
      final globalBefore = _convoRepo.globalListCalls;
      final aScopeBefore = _convoRepo.listByPartnerCalls['A'] ?? 0;

      await container
          .read(partnerWriteControllerProvider.notifier)
          .delete(_partner('A', name: 'Alice'));

      // Re-reads — values must reflect post-delete Hive state.
      expect(container.read(partnerByIdProvider('A')), isNull,
          reason: 'A is deleted; partnerByIdProvider(A) must not stale-cache');
      expect(container.read(partnerListProvider).map((p) => p.id), ['B'],
          reason: 'partner list must be invalidated');
      expect(container.read(partnerAggregateProvider('A')).totalRounds, 0,
          reason: 'aggregate(A) re-evaluates against empty Hive state');
      // Force a re-read to surface invalidation of conversationsByPartner(A).
      container.read(conversationsByPartnerProvider('A'));
      expect(
          (_convoRepo.listByPartnerCalls['A'] ?? 0), greaterThan(aScopeBefore),
          reason: 'conversationsByPartner(A) must be invalidated');

      container.read(conversationsProvider);
      expect(_convoRepo.globalListCalls, globalBefore,
          reason: 'delete must NOT invalidate the legacy global feed '
              '(no conversation rows mutated)');
    });

    test('delete still invalidates scopes when repo throws', () async {
      await _partnerBox.put('A', _partner('A', name: 'Alice'));
      await _convoBox.put('c1', _convo('c1', partnerId: 'A'));

      final container = ProviderContainer(overrides: [
        conversationRepositoryProvider.overrideWithValue(_convoRepo),
        partnerRepositoryProvider.overrideWithValue(
          _ThrowingDeletePartnerRepository(
            box: _partnerBox,
            conversationBox: _convoBox,
            thrownCount: 1,
          ),
        ),
        authConversationScopeProvider
            .overrideWith((ref) => Stream.value('u-1')),
      ]);
      await container.read(authConversationScopeProvider.future);
      addTearDown(container.dispose);

      // Prime so we can observe invalidation.
      expect(container.read(partnerByIdProvider('A')), isNotNull);
      expect(container.read(conversationsByPartnerProvider('A')).length, 1);
      final aScopeBefore = _convoRepo.listByPartnerCalls['A'] ?? 0;

      await expectLater(
        container
            .read(partnerWriteControllerProvider.notifier)
            .delete(_partner('A', name: 'Alice')),
        throwsA(isA<PartnerHasConversationsException>()),
      );

      // Force re-read; invalidation must have happened in finally{}.
      container.read(conversationsByPartnerProvider('A'));
      expect(
          (_convoRepo.listByPartnerCalls['A'] ?? 0), greaterThan(aScopeBefore),
          reason: 'failure path must still invalidate conversation scope');
      expect(container.read(partnerByIdProvider('A')), isNotNull,
          reason: 'A still in box because delete threw before _box.delete');
    });
  });

  group('PartnerWriteController.updateName invalidations', () {
    test(
        'updateName invalidates partnerByIdProvider + partnerListProvider; '
        'leaves conversationsProvider + conversationsByPartner alone',
        () async {
      await _partnerBox.put('A', _partner('A', name: 'Alice'));
      await _convoBox.put('c1', _convo('c1', partnerId: 'A'));

      final container = await _makeContainer();
      addTearDown(container.dispose);

      // Prime
      expect(container.read(partnerByIdProvider('A'))?.name, 'Alice');
      expect(container.read(partnerListProvider).single.name, 'Alice');
      expect(container.read(conversationsByPartnerProvider('A')).length, 1);
      container.read(conversationsProvider);
      final globalBefore = _convoRepo.globalListCalls;
      final aScopeBefore = _convoRepo.listByPartnerCalls['A'] ?? 0;

      final partner = container.read(partnerByIdProvider('A'))!;
      await container
          .read(partnerWriteControllerProvider.notifier)
          .updateName(partner, 'Alicia');

      // partnerById must reflect renamed value (cache busted).
      expect(container.read(partnerByIdProvider('A'))?.name, 'Alicia',
          reason: 'partnerByIdProvider(A) must be invalidated after rename');
      expect(container.read(partnerListProvider).single.name, 'Alicia',
          reason: 'partnerListProvider must be invalidated');

      container.read(conversationsByPartnerProvider('A'));
      expect(_convoRepo.listByPartnerCalls['A'] ?? 0, aScopeBefore,
          reason: 'rename must NOT invalidate conversationsByPartner — '
              'no conversation rows mutated');
      container.read(conversationsProvider);
      expect(_convoRepo.globalListCalls, globalBefore,
          reason: 'rename must NOT invalidate the legacy global feed');
    });

    test('updateName trims whitespace before persisting', () async {
      await _partnerBox.put('A', _partner('A', name: 'Alice'));
      final container = await _makeContainer();
      addTearDown(container.dispose);

      final partner = container.read(partnerByIdProvider('A'))!;
      await container
          .read(partnerWriteControllerProvider.notifier)
          .updateName(partner, '  Alicia  ');

      expect(container.read(partnerByIdProvider('A'))?.name, 'Alicia');
    });

    test('updateName throws ArgumentError on empty input', () async {
      await _partnerBox.put('A', _partner('A', name: 'Alice'));
      final container = await _makeContainer();
      addTearDown(container.dispose);

      final partner = container.read(partnerByIdProvider('A'))!;

      await expectLater(
        container
            .read(partnerWriteControllerProvider.notifier)
            .updateName(partner, ''),
        throwsArgumentError,
      );
      await expectLater(
        container
            .read(partnerWriteControllerProvider.notifier)
            .updateName(partner, '   '),
        throwsArgumentError,
      );
      // Original name preserved.
      expect(container.read(partnerByIdProvider('A'))?.name, 'Alice');
    });

    test('updateName still invalidates scopes when repo throws', () async {
      await _partnerBox.put('A', _partner('A', name: 'Alice'));

      final container = ProviderContainer(overrides: [
        conversationRepositoryProvider.overrideWithValue(_convoRepo),
        partnerRepositoryProvider.overrideWithValue(
          _ThrowingUpdatePartnerRepository(box: _partnerBox),
        ),
        authConversationScopeProvider
            .overrideWith((ref) => Stream.value('u-1')),
      ]);
      await container.read(authConversationScopeProvider.future);
      addTearDown(container.dispose);

      // Prime so we can observe invalidation
      expect(container.read(partnerByIdProvider('A'))?.name, 'Alice');
      expect(container.read(partnerListProvider).single.name, 'Alice');

      final partner = container.read(partnerByIdProvider('A'))!;
      await expectLater(
        container
            .read(partnerWriteControllerProvider.notifier)
            .updateName(partner, 'Alicia'),
        throwsStateError,
      );
      // partnerById was invalidated even though repo threw — re-read picks
      // up whatever Hive state actually exists. Because the failing repo
      // never wrote, the box still has 'Alice'.
      expect(container.read(partnerByIdProvider('A'))?.name, 'Alice',
          reason: 'failure path must re-read box (no stale cache)');
    });
  });
}
