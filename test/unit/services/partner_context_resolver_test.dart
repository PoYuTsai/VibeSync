import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/data/services/partner_context_resolver.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/services/partner_summary_builder.dart';
import 'package:vibesync/features/user_profile/data/repositories/partner_data_quality_repo_view.dart';

class _StubPartnerRepository implements PartnerRepoView {
  _StubPartnerRepository(this.partners);
  final Map<String, Partner> partners;

  @override
  Partner? getById(String id) => partners[id];
}

class _StubConversationListByPartner implements ConversationListByPartnerView {
  _StubConversationListByPartner(this.byPartner);
  final Map<String, List<Conversation>> byPartner;

  @override
  List<Conversation> listByPartner(String partnerId) =>
      byPartner[partnerId] ?? const [];
}

class _CountingBuilder extends PartnerSummaryBuilder {
  _CountingBuilder({required this.returnValue});
  final String returnValue;
  int calls = 0;

  @override
  String build({
    required Partner partner,
    required List<Conversation> conversations,
  }) {
    calls++;
    return returnValue;
  }
}

class _StubDataQualityRepo implements PartnerDataQualityRepoView {
  _StubDataQualityRepo({Map<String, bool> flagged = const {}})
      : _flagged = flagged;
  final Map<String, bool> _flagged;

  @override
  bool isFlaggedUnresolved(String partnerId) => _flagged[partnerId] ?? false;
}

Conversation _convo(String id,
    {String? partnerId, String ownerUserId = 'u-1'}) {
  return Conversation(
    id: id,
    name: 'c-$id',
    messages: <Message>[],
    createdAt: DateTime(2026, 4, 1),
    updatedAt: DateTime(2026, 4, 1),
    ownerUserId: ownerUserId,
    partnerId: partnerId,
  );
}

Partner _partner(String id) => Partner(
      id: id,
      name: '糖糖',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 4, 1),
      ownerUserId: 'u-1',
    );

void main() {
  test(
      'resolve returns summary when conversation has partnerId + builder non-empty',
      () {
    final partner = _partner('p-1');
    final convo = _convo('c-1', partnerId: 'p-1');
    final resolver = PartnerContextResolver(
      partnerRepo: _StubPartnerRepository({'p-1': partner}),
      conversationRepo: _StubConversationListByPartner({
        'p-1': [convo]
      }),
      summaryBuilder: _CountingBuilder(returnValue: 'SUMMARY'),
      dataQualityRepo: _StubDataQualityRepo(),
    );

    expect(resolver.resolve(convo), 'SUMMARY');
  });

  test(
      'resolve returns null when conversation.partnerId is null (legacy / unmigrated)',
      () {
    final builder = _CountingBuilder(returnValue: 'unused');
    final resolver = PartnerContextResolver(
      partnerRepo: _StubPartnerRepository({}),
      conversationRepo: _StubConversationListByPartner({}),
      summaryBuilder: builder,
      dataQualityRepo: _StubDataQualityRepo(),
    );

    expect(resolver.resolve(_convo('c-1', partnerId: null)), isNull);
    expect(builder.calls, 0,
        reason: 'should short-circuit before invoking builder');
  });

  test('resolve invokes builder.build() once per call (no caching)', () {
    final partner = _partner('p-1');
    final convo = _convo('c-1', partnerId: 'p-1');
    final builder = _CountingBuilder(returnValue: 'SUMMARY');
    final resolver = PartnerContextResolver(
      partnerRepo: _StubPartnerRepository({'p-1': partner}),
      conversationRepo: _StubConversationListByPartner({
        'p-1': [convo]
      }),
      summaryBuilder: builder,
      dataQualityRepo: _StubDataQualityRepo(),
    );

    resolver.resolve(convo);
    resolver.resolve(convo);
    resolver.resolve(convo);

    expect(builder.calls, 3,
        reason:
            'each resolve must rebuild — partner aggregate is fresh per call');
  });

  test(
      'resolve returns null when builder returns empty (ownerUserId mismatch fallback)',
      () {
    final partner = _partner('p-1');
    final convo = _convo('c-1', partnerId: 'p-1');
    final resolver = PartnerContextResolver(
      partnerRepo: _StubPartnerRepository({'p-1': partner}),
      conversationRepo: _StubConversationListByPartner({
        'p-1': [convo]
      }),
      summaryBuilder: _CountingBuilder(returnValue: ''),
      dataQualityRepo: _StubDataQualityRepo(),
    );

    expect(resolver.resolve(convo), isNull,
        reason:
            'empty string from builder means owner-mismatch / unrenderable; treat as no context');
  });

  test(
      'resolve returns null when partner is missing despite partnerId being set',
      () {
    // Defensive: stale partnerId pointing to a deleted partner.
    final convo = _convo('c-1', partnerId: 'missing');
    final builder = _CountingBuilder(returnValue: 'SUMMARY');
    final resolver = PartnerContextResolver(
      partnerRepo: _StubPartnerRepository({}),
      conversationRepo: _StubConversationListByPartner({}),
      summaryBuilder: builder,
      dataQualityRepo: _StubDataQualityRepo(),
    );

    expect(resolver.resolve(convo), isNull);
    expect(builder.calls, 0, reason: 'no partner row → no builder call');
  });

  group('flagged-unresolved gating', () {
    test('returns null when partner has unresolved data-quality flag', () {
      final partner = _partner('p-1');
      final convo = _convo('c-1', partnerId: 'p-1');
      final builder = _CountingBuilder(returnValue: 'SUMMARY');
      final resolver = PartnerContextResolver(
        partnerRepo: _StubPartnerRepository({'p-1': partner}),
        conversationRepo: _StubConversationListByPartner({
          'p-1': [convo]
        }),
        summaryBuilder: builder,
        dataQualityRepo: _StubDataQualityRepo(flagged: {'p-1': true}),
      );

      expect(resolver.resolve(convo), isNull,
          reason:
              'unresolved data-quality flag must short-circuit AI context — Spec 3 P1 contract: never feed flagged partner summary into prompts');
      expect(builder.calls, 0,
          reason:
              'gating is upstream of summary building — flagged partner must not pay builder cost');
    });

    test('returns full summary when partner is unflagged', () {
      final partner = _partner('p-1');
      final convo = _convo('c-1', partnerId: 'p-1');
      final builder = _CountingBuilder(returnValue: 'SUMMARY');
      final resolver = PartnerContextResolver(
        partnerRepo: _StubPartnerRepository({'p-1': partner}),
        conversationRepo: _StubConversationListByPartner({
          'p-1': [convo]
        }),
        summaryBuilder: builder,
        dataQualityRepo: _StubDataQualityRepo(),
      );

      expect(resolver.resolve(convo), 'SUMMARY',
          reason:
              'no flag entry → behave identically to pre-Spec-3 baseline; gating is opt-in by flag presence');
      expect(builder.calls, 1,
          reason: 'unflagged partner must invoke builder exactly once');
    });

    test(
        'returns full summary when partner flag is resolved (confirmed same person)',
        () {
      // Flag exists in store but resolved=true → isFlaggedUnresolved returns false.
      // This is the "user confirmed same person" path: data-quality alert was
      // raised, user reviewed it, and chose to keep the partner unified.
      final partner = _partner('p-1');
      final convo = _convo('c-1', partnerId: 'p-1');
      final builder = _CountingBuilder(returnValue: 'SUMMARY');
      final resolver = PartnerContextResolver(
        partnerRepo: _StubPartnerRepository({'p-1': partner}),
        conversationRepo: _StubConversationListByPartner({
          'p-1': [convo]
        }),
        summaryBuilder: builder,
        dataQualityRepo: _StubDataQualityRepo(flagged: {'p-1': false}),
      );

      expect(resolver.resolve(convo), 'SUMMARY',
          reason:
              'resolved flag (false) means user已確認同一人 — must behave identically to unflagged path');
      expect(builder.calls, 1,
          reason: 'resolved flag must not block builder — gating is on UNRESOLVED only');
    });
  });
}
