import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation_summary.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/conversation/domain/entities/session_context.dart';
import 'package:vibesync/features/partner/data/repositories/partner_repository.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/user_profile/data/repositories/partner_data_quality_repository.dart';
import 'package:vibesync/features/user_profile/data/repositories/partner_style_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_data_quality_state.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_style_override.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';

late Box<Conversation> convoBox;
late Box<Partner> partnerBox;
late Box<PartnerStyleOverride> styleBox;
late Box<PartnerDataQualityState> qualityBox;
late PartnerStyleRepository styleRepo;
late PartnerDataQualityRepository qualityRepo;
late PartnerRepository repo;

const _newPartnerId = 'fixed-new-id';
String _idGenerator() => _newPartnerId;

Partner _partner({
  required String id,
  String name = 'p',
  String? ownerUserId = 'u-1',
  String? customNote,
}) {
  final now = DateTime(2026, 5, 1, 10, 0);
  return Partner(
    id: id,
    name: name,
    createdAt: now,
    updatedAt: now,
    ownerUserId: ownerUserId,
    customNote: customNote,
  );
}

Conversation _convo({
  required String id,
  String? partnerId,
  String name = 'c',
  String? ownerUserId = 'u-1',
}) {
  final now = DateTime(2026, 5, 1, 10, 0);
  return Conversation(
    id: id,
    name: name,
    messages: const [],
    createdAt: now,
    updatedAt: now,
    ownerUserId: ownerUserId,
    partnerId: partnerId,
  );
}

void main() {
  setUpAll(() {
    Hive.init('./.dart_tool/test_hive_partner_repo_split');
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
    if (!Hive.isAdapterRegistered(14)) {
      Hive.registerAdapter(PartnerDataQualityStateAdapter());
    }
    if (!Hive.isAdapterRegistered(15)) {
      Hive.registerAdapter(NamePairAdapter());
    }
  });

  tearDownAll(() async {
    await Hive.close();
  });

  setUp(() async {
    final ts = DateTime.now().microsecondsSinceEpoch;
    convoBox = await Hive.openBox<Conversation>('split_conv_$ts');
    partnerBox = await Hive.openBox<Partner>('split_partner_$ts');
    styleBox = await Hive.openBox<PartnerStyleOverride>('split_style_$ts');
    qualityBox =
        await Hive.openBox<PartnerDataQualityState>('split_quality_$ts');
    styleRepo = PartnerStyleRepository(box: styleBox);
    qualityRepo = PartnerDataQualityRepository(injectedBox: qualityBox);
    repo = PartnerRepository(
      box: partnerBox,
      conversationBox: convoBox,
      styleRepo: styleRepo,
      qualityRepo: qualityRepo,
    );
  });

  tearDown(() async {
    await qualityBox.deleteFromDisk();
    await styleBox.deleteFromDisk();
    await convoBox.deleteFromDisk();
    await partnerBox.deleteFromDisk();
  });

  group('PartnerRepository.split', () {
    test('moves only conversations matching the new-partner name', () async {
      // Source partner "May" with three conversations: two have name "Anna"
      // (matched, will be split off), one has name "May" (stays on source).
      await partnerBox.put('p-source', _partner(id: 'p-source', name: 'May'));
      await convoBox.put(
        'c-anna-1',
        _convo(id: 'c-anna-1', partnerId: 'p-source', name: 'Anna'),
      );
      await convoBox.put(
        'c-anna-2',
        _convo(id: 'c-anna-2', partnerId: 'p-source', name: 'Anna'),
      );
      await convoBox.put(
        'c-may-1',
        _convo(id: 'c-may-1', partnerId: 'p-source', name: 'May'),
      );

      final newId = await repo.split(
        sourcePartnerId: 'p-source',
        newPartnerName: 'Anna',
        matchedConversationIds: const ['c-anna-1', 'c-anna-2'],
        idGenerator: _idGenerator,
      );

      expect(newId, _newPartnerId);
      expect(convoBox.get('c-anna-1')!.partnerId, _newPartnerId);
      expect(convoBox.get('c-anna-2')!.partnerId, _newPartnerId);
      expect(convoBox.get('c-may-1')!.partnerId, 'p-source');
    });

    test('source partner keeps its name + style override', () async {
      await partnerBox.put('p-source', _partner(id: 'p-source', name: 'May'));
      await convoBox.put(
        'c-anna-1',
        _convo(id: 'c-anna-1', partnerId: 'p-source', name: 'Anna'),
      );
      await styleRepo.save(PartnerStyleOverride.create(
        partnerId: 'p-source',
        interactionStyle: InteractionStyle.humorous,
        notes: '對方慢熟',
        updatedAt: DateTime.utc(2026, 5, 1),
      ));

      await repo.split(
        sourcePartnerId: 'p-source',
        newPartnerName: 'Anna',
        matchedConversationIds: const ['c-anna-1'],
        idGenerator: _idGenerator,
      );

      // Source partner row preserved with its name.
      final source = partnerBox.get('p-source');
      expect(source, isNotNull);
      expect(source!.name, 'May');
      // Source's style override preserved.
      final sourceStyle = await styleRepo.load('p-source');
      expect(sourceStyle, isNotNull);
      expect(sourceStyle!.interactionStyle, InteractionStyle.humorous);
      expect(sourceStyle.notes, '對方慢熟');
    });

    test('new partner has empty PartnerStyleOverride (走 global About Me)',
        () async {
      await partnerBox.put('p-source', _partner(id: 'p-source', name: 'May'));
      await convoBox.put(
        'c-anna-1',
        _convo(id: 'c-anna-1', partnerId: 'p-source', name: 'Anna'),
      );
      await styleRepo.save(PartnerStyleOverride.create(
        partnerId: 'p-source',
        interactionStyle: InteractionStyle.humorous,
        notes: '對方慢熟',
        updatedAt: DateTime.utc(2026, 5, 1),
      ));

      final newId = await repo.split(
        sourcePartnerId: 'p-source',
        newPartnerName: 'Anna',
        matchedConversationIds: const ['c-anna-1'],
        idGenerator: _idGenerator,
      );

      // New partner has NO style override row → load returns null →
      // resolver falls back to global About Me.
      expect(await styleRepo.load(newId), isNull);
    });

    test(
        'source partner keeps its data-quality state '
        '(confirmed pairs 仍對源卡有意義)', () async {
      await partnerBox.put('p-source', _partner(id: 'p-source', name: 'May'));
      await convoBox.put(
        'c-anna-1',
        _convo(id: 'c-anna-1', partnerId: 'p-source', name: 'Anna'),
      );
      // Source has a pre-existing confirmed "same person" pair.
      await qualityRepo.markSamePerson(
        'p-source',
        NamePair.canonical('May', 'Mei'),
      );
      expect(qualityBox.get('p-source'), isNotNull);

      await repo.split(
        sourcePartnerId: 'p-source',
        newPartnerName: 'Anna',
        matchedConversationIds: const ['c-anna-1'],
        idGenerator: _idGenerator,
      );

      final sourceState = qualityBox.get('p-source');
      expect(sourceState, isNotNull);
      expect(
        sourceState!.confirmsSamePerson(NamePair.canonical('May', 'Mei')),
        isTrue,
      );
    });

    test('new partner has empty data-quality state', () async {
      await partnerBox.put('p-source', _partner(id: 'p-source', name: 'May'));
      await convoBox.put(
        'c-anna-1',
        _convo(id: 'c-anna-1', partnerId: 'p-source', name: 'Anna'),
      );
      await qualityRepo.markSamePerson(
        'p-source',
        NamePair.canonical('May', 'Mei'),
      );

      final newId = await repo.split(
        sourcePartnerId: 'p-source',
        newPartnerName: 'Anna',
        matchedConversationIds: const ['c-anna-1'],
        idGenerator: _idGenerator,
      );

      // New partner has NO quality state row.
      expect(qualityBox.get(newId), isNull);
    });

    test('throws when matching conversation list is empty (no-op guard)',
        () async {
      await partnerBox.put('p-source', _partner(id: 'p-source', name: 'May'));
      await convoBox.put(
        'c-anna-1',
        _convo(id: 'c-anna-1', partnerId: 'p-source', name: 'Anna'),
      );

      await expectLater(
        repo.split(
          sourcePartnerId: 'p-source',
          newPartnerName: 'Anna',
          matchedConversationIds: const [],
          idGenerator: _idGenerator,
        ),
        throwsArgumentError,
      );
      // No new partner created; source untouched.
      expect(partnerBox.get(_newPartnerId), isNull);
      expect(convoBox.get('c-anna-1')!.partnerId, 'p-source');
    });

    test('mixed-name conversation stays on source (per design §6.3)',
        () async {
      // Caller pre-filters: matchedConversationIds contains only the
      // unambiguous "Anna" conversations. The mixed-name conversation
      // (c-mixed) is intentionally EXCLUDED from the list, so split()
      // must leave it alone.
      await partnerBox.put('p-source', _partner(id: 'p-source', name: 'May'));
      await convoBox.put(
        'c-anna-1',
        _convo(id: 'c-anna-1', partnerId: 'p-source', name: 'Anna'),
      );
      await convoBox.put(
        'c-mixed',
        _convo(id: 'c-mixed', partnerId: 'p-source', name: 'May / Anna'),
      );

      await repo.split(
        sourcePartnerId: 'p-source',
        newPartnerName: 'Anna',
        matchedConversationIds: const ['c-anna-1'],
        idGenerator: _idGenerator,
      );

      // Only the explicitly-matched conversation moved; mixed-name stays.
      expect(convoBox.get('c-anna-1')!.partnerId, _newPartnerId);
      expect(convoBox.get('c-mixed')!.partnerId, 'p-source');
    });
  });
}
