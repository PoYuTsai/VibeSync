import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/analysis/data/providers/analysis_providers.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/user_profile/data/providers/data_quality_flag_provider.dart';
import 'package:vibesync/features/user_profile/data/repositories/partner_data_quality_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_data_quality_state.dart';

/// Tests focus on the comparator logic (input candidates -> DataQualityFlag).
///
/// Inputs are fed via two override seams:
///   1. [conversationsByPartnerProvider] override — the candidate source.
///   2. [partnerDataQualityRepoProvider] override — the confirmed-pairs source
///      (real repo backed by an injected Hive box so `markSamePerson` works as
///      production would).
///
/// We deliberately do NOT touch the global `StorageService.conversationsBox`
/// because that path is auth-gated and would dominate test setup with
/// machinery unrelated to the comparator.
void main() {
  late Directory tmp;
  late Box<PartnerDataQualityState> box;
  late PartnerDataQualityRepository repo;

  setUpAll(() {
    if (!Hive.isAdapterRegistered(PartnerDataQualityStateAdapter().typeId)) {
      Hive.registerAdapter(PartnerDataQualityStateAdapter());
    }
    if (!Hive.isAdapterRegistered(NamePairAdapter().typeId)) {
      Hive.registerAdapter(NamePairAdapter());
    }
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('data_quality_flag_provider');
    Hive.init(tmp.path);
    box = await Hive.openBox<PartnerDataQualityState>(
      'dqf_${DateTime.now().microsecondsSinceEpoch}',
    );
    repo = PartnerDataQualityRepository(injectedBox: box);
  });

  tearDown(() async {
    await box.close();
    await tmp.delete(recursive: true);
  });

  Conversation makeConv({
    required String id,
    String name = '新對話',
    List<Message> messages = const [],
  }) {
    final now = DateTime.utc(2026, 5, 1);
    return Conversation(
      id: id,
      name: name,
      messages: messages,
      createdAt: now,
      updatedAt: now,
      partnerId: 'p1',
    );
  }

  Message msgFromThem(String id, String content) => Message(
        id: id,
        content: content,
        isFromMe: false,
        timestamp: DateTime.utc(2026, 5, 1),
      );

  ProviderContainer makeContainer(List<Conversation> convs) {
    return ProviderContainer(overrides: [
      conversationsByPartnerProvider('p1').overrideWithValue(convs),
      partnerDataQualityRepoProvider.overrideWithValue(repo),
    ]);
  }

  group('dataQualityFlagProvider(partnerId)', () {
    test('returns unflagged when conversations have only 1 candidate name',
        () {
      final convs = [
        makeConv(id: 'c1', name: 'May'),
        // Same name in conversation title — set has size 1.
        makeConv(id: 'c2', name: 'May'),
      ];
      final container = makeContainer(convs);
      addTearDown(container.dispose);

      final flag = container.read(dataQualityFlagProvider('p1'));
      expect(flag.isFlagged, isFalse);
      expect(flag.conflictingPair, isNull);
    });

    test('returns unflagged when all conversations have null candidate', () {
      final convs = [
        makeConv(id: 'c1', name: '新對話'), // placeholder — extractor returns null
        makeConv(id: 'c2', name: '第 1 段'), // segment — extractor returns null
        makeConv(id: 'c3', name: '2026/05/01'), // date — extractor returns null
      ];
      final container = makeContainer(convs);
      addTearDown(container.dispose);

      final flag = container.read(dataQualityFlagProvider('p1'));
      expect(flag.isFlagged, isFalse);
      expect(flag.conflictingPair, isNull);
    });

    test(
        'returns flagged when ≥ 2 distinct candidates and not in confirmed pairs',
        () {
      final convs = [
        makeConv(id: 'c1', name: 'May'),
        makeConv(id: 'c2', name: 'Anna'),
      ];
      final container = makeContainer(convs);
      addTearDown(container.dispose);

      final flag = container.read(dataQualityFlagProvider('p1'));
      expect(flag.isFlagged, isTrue);
      expect(flag.conflictingPair, NamePair.canonical('May', 'Anna'));
    });

    test('returns unflagged when the two candidates are in confirmed pairs',
        () async {
      // Pre-mark the pair as same-person.
      await repo.markSamePerson('p1', NamePair.canonical('May', 'Anna'));

      final convs = [
        makeConv(id: 'c1', name: 'May'),
        makeConv(id: 'c2', name: 'Anna'),
      ];
      final container = makeContainer(convs);
      addTearDown(container.dispose);

      final flag = container.read(dataQualityFlagProvider('p1'));
      expect(flag.isFlagged, isFalse);
      expect(flag.conflictingPair, isNull);
    });

    test('returns flagged with conflicting NamePair when 3rd new name appears',
        () async {
      // User already confirmed May≡Anna, but now a new "Bella" shows up.
      await repo.markSamePerson('p1', NamePair.canonical('May', 'Anna'));

      final convs = [
        makeConv(id: 'c1', name: 'May'),
        makeConv(id: 'c2', name: 'Anna'),
        makeConv(id: 'c3', name: 'Bella'),
      ];
      final container = makeContainer(convs);
      addTearDown(container.dispose);

      final flag = container.read(dataQualityFlagProvider('p1'));
      expect(flag.isFlagged, isTrue);
      // The flagged pair must involve 'bella' (the unconfirmed newcomer).
      // Pair iteration is sorted lexicographically, so the FIRST unconfirmed
      // pair encountered is (anna, bella).
      expect(flag.conflictingPair, NamePair.canonical('Anna', 'Bella'));
    });

    test(
        'falls back to fromMessages when conversation name is a placeholder',
        () {
      // c1: placeholder name, but explicit self-intro in messages.
      // c2: real name in title.
      final convs = [
        makeConv(
          id: 'c1',
          name: '新對話',
          messages: [msgFromThem('m1', '我叫 May')],
        ),
        makeConv(id: 'c2', name: 'Anna'),
      ];
      final container = makeContainer(convs);
      addTearDown(container.dispose);

      final flag = container.read(dataQualityFlagProvider('p1'));
      expect(flag.isFlagged, isTrue);
      expect(flag.conflictingPair, NamePair.canonical('May', 'Anna'));
    });
  });
}
