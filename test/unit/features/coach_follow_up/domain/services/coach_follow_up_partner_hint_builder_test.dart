// Spec 5 C17 — buildCoachFollowUpPartnerHint TDD spec.
//
// The helper packages caller-provided context (heatScore / gameStage / latest
// summary) into the partnerHint structure sent to the Edge function. It owns
// the privacy contract — privacy_test.ts (Edge side) locks "what may not
// reach Supabase / logs"; THIS file locks "what may not enter the wire
// payload in the first place."
//
// Forbidden in the helper file (asserted by the static guard at the bottom):
//   PartnerContextResolver, partnerSummary, partnerTraits, Message,
//   UserProfile / About Me, partner_style_override, cross-conversation
//   aggregate.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/game_stage.dart';
import 'package:vibesync/features/coach_follow_up/domain/services/coach_follow_up_partner_hint_builder.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation_summary.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/user_profile/data/providers/data_quality_flag_provider.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_data_quality_state.dart';

Partner _partner({String name = 'Mia'}) {
  final now = DateTime(2026, 5, 2);
  return Partner(
    id: 'p-1',
    name: name,
    ownerUserId: 'u-1',
    createdAt: now,
    updatedAt: now,
  );
}

ConversationSummary _summary(String content, {DateTime? createdAt}) =>
    ConversationSummary(
      id: 's-${content.hashCode}',
      roundsCovered: 5,
      content: content,
      keyTopics: const [],
      sharedInterests: const [],
      relationshipStage: 'warming',
      createdAt: createdAt ?? DateTime(2026, 5, 2, 16),
    );

Conversation _conversationWithSummaries(List<ConversationSummary> summaries) {
  final now = DateTime(2026, 5, 2);
  final c = Conversation(
    id: 'c-1',
    name: '對話',
    messages: const [],
    createdAt: now,
    updatedAt: now,
    ownerUserId: 'u-1',
    partnerId: 'p-1',
  );
  c.summaries = summaries.isEmpty ? null : List.of(summaries);
  return c;
}

void main() {
  group('buildCoachFollowUpPartnerHint — name handling', () {
    test('trims whitespace from partner.name', () {
      final hint =
          buildCoachFollowUpPartnerHint(partner: _partner(name: '  Mia  '));
      expect(hint.name, 'Mia');
    });

    test('empty-after-trim name does NOT throw — returns empty string', () {
      final hint =
          buildCoachFollowUpPartnerHint(partner: _partner(name: '   '));
      expect(hint.name, '');
    });
  });

  group('buildCoachFollowUpPartnerHint — heatScore + gameStage passthrough',
      () {
    test('heatScore null when caller does not pass it', () {
      final hint = buildCoachFollowUpPartnerHint(partner: _partner());
      expect(hint.heatScore, isNull);
    });

    test('heatScore passes through verbatim from caller', () {
      final hint =
          buildCoachFollowUpPartnerHint(partner: _partner(), heatScore: 73);
      expect(hint.heatScore, 73);
    });

    test('gameStage serializes with .name stable key, NOT .label', () {
      final hint = buildCoachFollowUpPartnerHint(
        partner: _partner(),
        gameStage: GameStage.qualification,
      );
      expect(hint.gameStage, 'qualification');
      // Negative: make sure we serialize the stable key, not any display label.
      expect(hint.gameStage, isNot(GameStage.qualification.label));
    });

    test('gameStage null when caller does not pass it', () {
      final hint = buildCoachFollowUpPartnerHint(partner: _partner());
      expect(hint.gameStage, isNull);
    });
  });

  group('buildCoachFollowUpPartnerHint — lastConversationSummary', () {
    test('currentConversation null → lastConversationSummary is null', () {
      final hint = buildCoachFollowUpPartnerHint(partner: _partner());
      expect(hint.lastConversationSummary, isNull);
    });

    test(
        'summaries empty/null on conversation → lastConversationSummary is null',
        () {
      final hint = buildCoachFollowUpPartnerHint(
        partner: _partner(),
        currentConversation: _conversationWithSummaries(const []),
      );
      expect(hint.lastConversationSummary, isNull);
    });

    test('uses latest summary only (the last entry in summaries)', () {
      final hint = buildCoachFollowUpPartnerHint(
        partner: _partner(),
        currentConversation: _conversationWithSummaries([
          _summary('older summary content'),
          _summary('middle summary content'),
          _summary('latest summary content'),
        ]),
      );
      expect(hint.lastConversationSummary, 'latest summary content');
    });

    test('caps summary at 200 chars (truncates from start)', () {
      final long = 'x' * 250;
      final hint = buildCoachFollowUpPartnerHint(
        partner: _partner(),
        currentConversation: _conversationWithSummaries([_summary(long)]),
      );
      expect(hint.lastConversationSummary!.length, 200);
      expect(hint.lastConversationSummary, 'x' * 200);
    });

    test('summary at exactly 200 chars passes through unchanged', () {
      final exact = 'a' * 200;
      final hint = buildCoachFollowUpPartnerHint(
        partner: _partner(),
        currentConversation: _conversationWithSummaries([_summary(exact)]),
      );
      expect(hint.lastConversationSummary, exact);
    });
  });

  group('buildCoachFollowUpPartnerHint — Spec 3 flagged behaviour', () {
    test('Spec 3 flagged → lastConversationSummary forced to null', () {
      final hint = buildCoachFollowUpPartnerHint(
        partner: _partner(),
        currentConversation: _conversationWithSummaries(
          [_summary('would-leak content from possibly-mixed conversation')],
        ),
        dataQualityFlag: DataQualityFlag.flagged(
          NamePair.canonical('Mia', 'May'),
        ),
      );
      expect(hint.lastConversationSummary, isNull);
    });

    test('Spec 3 flagged → name / heatScore / gameStage are still passed', () {
      final hint = buildCoachFollowUpPartnerHint(
        partner: _partner(name: '  Mia  '),
        currentConversation: _conversationWithSummaries(
          [_summary('hidden')],
        ),
        dataQualityFlag: DataQualityFlag.flagged(
          NamePair.canonical('Mia', 'May'),
        ),
        heatScore: 50,
        gameStage: GameStage.narrative,
      );
      expect(hint.name, 'Mia');
      expect(hint.heatScore, 50);
      expect(hint.gameStage, 'narrative');
      expect(hint.lastConversationSummary, isNull);
    });

    test('unflagged DataQualityFlag → summary still flows through', () {
      final hint = buildCoachFollowUpPartnerHint(
        partner: _partner(),
        currentConversation: _conversationWithSummaries(
          [_summary('safe summary content')],
        ),
        dataQualityFlag: const DataQualityFlag.unflagged(),
      );
      expect(hint.lastConversationSummary, 'safe summary content');
    });

    test('null DataQualityFlag is treated as not flagged (summary flows)', () {
      final hint = buildCoachFollowUpPartnerHint(
        partner: _partner(),
        currentConversation: _conversationWithSummaries(
          [_summary('safe summary content')],
        ),
      );
      expect(hint.lastConversationSummary, 'safe summary content');
    });
  });

  group('buildCoachFollowUpPartnerHint — privacy static guard', () {
    // Tripwire: helper file's CODE (comments stripped) MUST NOT reference
    // any of these symbols. If anyone adds a "let's enrich the hint with X"
    // change that reaches into the forbidden surfaces, this catches it
    // before review. Comments are stripped so the docstring can name the
    // forbidden symbols for documentation without tripping itself.
    test('helper file does not import / reference forbidden privacy surfaces',
        () {
      const helperPath =
          'lib/features/coach_follow_up/domain/services/coach_follow_up_partner_hint_builder.dart';
      final source = File(helperPath).readAsStringSync();
      final code = _stripDartLineComments(source);

      const forbidden = <String>[
        'PartnerContextResolver',
        'partnerSummary',
        'partnerTraits',
        // About Me / global user profile must never enter wire payload.
        'UserProfile',
        // Style override is a per-partner ABOUT-ME-style hint; not allowed.
        'PartnerStyleOverride',
        // Cross-conversation aggregate is the same anti-pattern as Resolver.
        'partnerAggregate',
        // Raw conversation messages must not leave the device. Match the
        // import path so the conversation/Conversation type itself (which
        // we DO need for summaries access) is fine.
        "entities/message.dart",
      ];

      for (final tok in forbidden) {
        expect(
          code.contains(tok),
          isFalse,
          reason: 'forbidden privacy surface leaked into helper code: $tok',
        );
      }
    });
  });
}

/// Strips Dart `//` / `///` line comments so static-guard greps can target
/// real code references without false-positives from the docstring.
String _stripDartLineComments(String source) {
  return source.split('\n').map((line) {
    final idx = line.indexOf('//');
    return idx >= 0 ? line.substring(0, idx) : line;
  }).join('\n');
}
