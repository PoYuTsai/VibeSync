import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/data/services/partner_context_resolver.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/services/partner_summary_builder.dart';

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
    );

    expect(resolver.resolve(convo), isNull);
    expect(builder.calls, 0, reason: 'no partner row → no builder call');
  });
}
