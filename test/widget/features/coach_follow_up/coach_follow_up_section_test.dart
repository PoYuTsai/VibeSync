// Spec 5 C24 — CoachFollowUpSection widget TDD spec.
//
// The section sits between PartnerRadarSummaryCard and the conversations
// list on partner detail. Two visual states (default / with-result) plus a
// telemetry callback contract that survives until X25 wires a real SDK.
//
// Design choices locked at C24 kickoff (see commit body):
//   • Insert anchor B — between Style+Radar cluster and conversations list
//     (preserves existing profile cluster, doesn't reorder shipped widgets).
//   • 換情境 = local UI flag only — does NOT delete the Hive result. Latest-
//     only persistence still holds because the next successful generate
//     overwrites.
//   • Telemetry = typed sealed callback contract emitted now, wired to a
//     stub at the screen layer until X25 swaps in the real sink.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/features/coach_follow_up/data/providers/coach_follow_up_providers.dart';
import 'package:vibesync/features/coach_follow_up/data/services/coach_follow_up_api_service.dart';
import 'package:vibesync/features/coach_follow_up/domain/entities/coach_follow_up_phase.dart';
import 'package:vibesync/features/coach_follow_up/domain/entities/coach_follow_up_result.dart';
import 'package:vibesync/features/coach_follow_up/domain/repositories/coach_follow_up_repository.dart';
import 'package:vibesync/features/coach_follow_up/presentation/widgets/coach_follow_up_section.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/user_profile/data/providers/data_quality_flag_provider.dart';
import 'package:vibesync/shared/widgets/ai_data_sharing_consent.dart';

// ── Fixtures ──────────────────────────────────────────────────────────────

const _partnerId = 'p1';

Partner _partner() => Partner(
      id: _partnerId,
      name: 'Mia',
      ownerUserId: 'u1',
      createdAt: DateTime(2026, 5, 1),
      updatedAt: DateTime(2026, 5, 1),
    );

Message _msg(String content, {bool fromMe = false}) => Message(
      id: 'm-${content.hashCode}',
      content: content,
      isFromMe: fromMe,
      timestamp: DateTime(2026, 5, 1, 17),
    );

Conversation _convo({
  List<Message> messages = const [],
  int? heat,
  String? gameStage,
}) =>
    Conversation(
      id: 'c1',
      name: '對話',
      messages: List.of(messages),
      createdAt: DateTime(2026, 5, 1),
      updatedAt: DateTime(2026, 5, 1, 18),
      partnerId: _partnerId,
      ownerUserId: 'u1',
      lastEnthusiasmScore: heat,
      currentGameStage: gameStage,
    );

CoachFollowUpResult _stored({
  CoachFollowUpPhase phase = CoachFollowUpPhase.prepareInvite,
  String headline = 'STORED_HEADLINE',
}) =>
    CoachFollowUpResult(
      partnerId: _partnerId,
      phase: phase.name,
      headline: headline,
      observation: 'STORED_OBS',
      task: 'STORED_TASK',
      suggestedLine: null,
      boundaryReminder: 'STORED_BR',
      generatedAt: DateTime(2026, 5, 1),
      modelUsed: 'claude-haiku-4-5-20251001',
    );

// ── Test doubles ──────────────────────────────────────────────────────────

class _FakeRepo implements CoachFollowUpRepository {
  final Map<String, CoachFollowUpResult> _store = {};

  void seed(CoachFollowUpResult r) => _store[r.partnerId] = r;

  @override
  CoachFollowUpResult? get(String id) => _store[id];

  @override
  Future<void> put(CoachFollowUpResult r) async => _store[r.partnerId] = r;

  @override
  Future<void> delete(String id) async => _store.remove(id);

  @override
  Future<void> clearAll() async => _store.clear();
}

CoachFollowUpInvoker _stubInvoker({
  String phase = 'prepareInvite',
  String headline = 'GEN_HEADLINE',
}) {
  return (String _, {required Map<String, dynamic> body}) async {
    return CoachFollowUpInvokeResponse(
      status: 200,
      data: <String, dynamic>{
        'phase': phase,
        'card': <String, dynamic>{
          'headline': headline,
          'observation': 'GEN_OBS',
          'task': 'GEN_TASK',
          'boundaryReminder': 'GEN_BR',
        },
        'model': 'claude-haiku-4-5-20251001',
        'generatedAt': '2026-05-02T12:00:00.000Z',
      },
    );
  };
}

CoachFollowUpInvoker _errorInvoker({
  int status = 500,
  String error = 'schema_invalid',
}) {
  return (String _, {required Map<String, dynamic> body}) async {
    return CoachFollowUpInvokeResponse(
      status: status,
      data: <String, dynamic>{'error': error},
    );
  };
}

CoachFollowUpInvoker _quotaInvoker() {
  return (String _, {required Map<String, dynamic> body}) async {
    return CoachFollowUpInvokeResponse(
      status: 429,
      data: <String, dynamic>{
        'error': 'Daily limit exceeded',
        'used': 15,
        'limit': 15,
      },
    );
  };
}

// ── Pump helper ───────────────────────────────────────────────────────────

Future<void> _pump(
  WidgetTester tester, {
  required _FakeRepo repo,
  CoachFollowUpInvoker? invoker,
  Partner? partner,
  List<Conversation> conversations = const [],
  DataQualityFlag flag = const DataQualityFlag.unflagged(),
  ValueChanged<CoachFollowUpTelemetryEvent>? onTelemetry,
  Future<void> Function()? onQuotaExceeded,
  Key? openCoachEntryAnchorKey,
  bool openCoachInputOnFirstBuild = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coachFollowUpRepositoryProvider.overrideWithValue(repo),
        coachFollowUpApiServiceProvider.overrideWithValue(
          CoachFollowUpApiService(invoker: invoker ?? _stubInvoker()),
        ),
        partnerByIdProvider(_partnerId).overrideWithValue(partner),
        conversationsByPartnerProvider(_partnerId)
            .overrideWithValue(conversations),
        dataQualityFlagProvider(_partnerId).overrideWithValue(flag),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CoachFollowUpSection(
              partnerId: _partnerId,
              onTelemetry: onTelemetry,
              onQuotaExceeded: onQuotaExceeded,
              openCoachEntryAnchorKey: openCoachEntryAnchorKey,
              openCoachInputOnFirstBuild: openCoachInputOnFirstBuild,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// ── Tests ─────────────────────────────────────────────────────────────────

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(
      {AiDataSharingConsent.acceptedKeyForTesting: true},
    );
  });

  group('CoachFollowUpSection — default state (no stored result)', () {
    testWidgets('exposes an anchor on the open coach input entry', (t) async {
      final anchorKey = GlobalKey();
      await _pump(
        t,
        repo: _FakeRepo(),
        partner: _partner(),
        openCoachEntryAnchorKey: anchorKey,
      );

      final anchoredEntry = find.byKey(anchorKey);
      expect(anchoredEntry, findsOneWidget);
      expect(
        find.descendant(
          of: anchoredEntry,
          matching: find.text('或直接問教練一個問題...'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('auto-opens the open coach input sheet on first build',
        (t) async {
      await _pump(
        t,
        repo: _FakeRepo(),
        partner: _partner(),
        openCoachInputOnFirstBuild: true,
      );

      final fieldFinder = find.byType(TextField);
      expect(fieldFinder, findsOneWidget);
      final field = t.widget<TextField>(fieldFinder);
      expect(field.maxLength, 120);
      expect(field.maxLines, 4);
    });

    testWidgets('renders 3 chips + quota caption, no result-card surface',
        (t) async {
      await _pump(t, repo: _FakeRepo(), partner: _partner());

      expect(find.text('準備邀約'), findsOneWidget);
      expect(find.text('約會前提醒'), findsOneWidget);
      expect(find.text('約會後復盤'), findsOneWidget);
      expect(find.text('或直接問教練一個問題...'), findsOneWidget);
      expect(find.textContaining('生成會使用 1 則額度'), findsOneWidget);

      // With-result state widgets must be absent.
      expect(find.text('重新生成'), findsNothing);
      expect(find.text('換情境'), findsNothing);
    });

    testWidgets('shows AI hint line when hint resolver returns a phase',
        (t) async {
      // preDateReminder is the only hint phase that fires from a single
      // keyword in the last 5 messages — keeps the test cheap.
      await _pump(
        t,
        repo: _FakeRepo(),
        partner: _partner(),
        conversations: [
          _convo(messages: [_msg('我們明天見面吧')]),
        ],
      );

      expect(find.textContaining('💡'), findsOneWidget);
    });

    testWidgets('hides AI hint line when resolver returns null', (t) async {
      await _pump(
        t,
        repo: _FakeRepo(),
        partner: _partner(),
        conversations: const [],
      );

      expect(find.textContaining('💡'), findsNothing);
    });
  });

  group('CoachFollowUpSection — with-result state', () {
    testWidgets('renders result card + 重新生成 + 換情境 buttons + caption',
        (t) async {
      final repo = _FakeRepo()..seed(_stored());
      await _pump(t, repo: repo, partner: _partner());

      expect(find.text('STORED_HEADLINE'), findsOneWidget);
      expect(find.text('重新生成'), findsOneWidget);
      expect(find.text('換情境'), findsOneWidget);
      expect(find.textContaining('再扣 1 則額度'), findsOneWidget);
    });

    testWidgets(
        '重新生成 disabled when answers unknown (hydrated from prior session)',
        (t) async {
      final repo = _FakeRepo()..seed(_stored());
      await _pump(t, repo: repo, partner: _partner());

      final btn = t.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, '重新生成'),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('換情境 returns to chip row but does NOT delete the Hive result',
        (t) async {
      final repo = _FakeRepo()..seed(_stored());
      await _pump(t, repo: repo, partner: _partner());

      await t.tap(find.text('換情境'));
      await t.pumpAndSettle();

      // Default-state surface visible again.
      expect(find.text('準備邀約'), findsOneWidget);
      expect(find.text('約會前提醒'), findsOneWidget);
      // But the repo entry is untouched — latest-only contract still holds.
      expect(repo.get(_partnerId), isNotNull);
    });
  });

  group('CoachFollowUpSection — generate flow', () {
    testWidgets('chip tap opens the input sheet', (t) async {
      await _pump(t, repo: _FakeRepo(), partner: _partner());

      await t.tap(find.text('準備邀約'));
      await t.pumpAndSettle();

      // The sheet's submit button label is unique to the input sheet —
      // its presence confirms the modal opened.
      expect(find.text('產生跟進建議'), findsOneWidget);
    });

    testWidgets('open coach entry opens the open question sheet', (t) async {
      await _pump(t, repo: _FakeRepo(), partner: _partner());

      await t.tap(find.text('或直接問教練一個問題...'));
      await t.pumpAndSettle();

      expect(find.text('我有其他問題'), findsOneWidget);
      expect(find.text('讓教練看一下'), findsOneWidget);
      expect(find.textContaining('把你現在卡住的點寫下來'), findsOneWidget);
    });

    testWidgets('submitting the sheet generates + transitions to with-result',
        (t) async {
      await _pump(
        t,
        repo: _FakeRepo(),
        partner: _partner(),
        invoker: _stubInvoker(headline: 'BRAND_NEW'),
      );

      await t.tap(find.text('準備邀約'));
      await t.pumpAndSettle();
      await t.tap(find.text('還沒想好'));
      await t.pumpAndSettle();
      await t.tap(find.text('產生跟進建議'));
      await t.pumpAndSettle();

      expect(find.text('BRAND_NEW'), findsOneWidget);
      expect(find.text('重新生成'), findsOneWidget);
      expect(find.text('換情境'), findsOneWidget);
    });

    testWidgets('submitting open coach question generates an openCoach card',
        (t) async {
      await _pump(
        t,
        repo: _FakeRepo(),
        partner: _partner(),
        invoker: _stubInvoker(headline: 'OPEN_COACH'),
      );

      await t.tap(find.text('或直接問教練一個問題...'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '我太有邊界感，不知道怎麼推進');
      await t.pumpAndSettle();
      await t.tap(find.text('讓教練看一下'));
      await t.pumpAndSettle();

      expect(find.text('OPEN_COACH'), findsOneWidget);
      expect(find.text('我有其他問題'), findsOneWidget);
    });

    testWidgets('重新生成 enabled after a fresh same-session generate', (t) async {
      await _pump(t, repo: _FakeRepo(), partner: _partner());

      await t.tap(find.text('準備邀約'));
      await t.pumpAndSettle();
      await t.tap(find.text('還沒想好'));
      await t.pumpAndSettle();
      await t.tap(find.text('產生跟進建議'));
      await t.pumpAndSettle();

      final btn = t.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, '重新生成'),
      );
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('shows a low-pressure error message when generation fails',
        (t) async {
      await _pump(
        t,
        repo: _FakeRepo(),
        partner: _partner(),
        invoker: _errorInvoker(),
      );

      await t.tap(find.text('準備邀約'));
      await t.pumpAndSettle();
      await t.tap(find.text('還沒想好'));
      await t.pumpAndSettle();
      await t.tap(find.text('產生跟進建議'));
      await t.pumpAndSettle();

      expect(find.textContaining('未扣額度'), findsOneWidget);
      expect(find.text('GEN_HEADLINE'), findsNothing);
    });

    testWidgets('quota exceeded opens the upgrade surface callback', (t) async {
      var paywallOpenCount = 0;
      await _pump(
        t,
        repo: _FakeRepo(),
        partner: _partner(),
        invoker: _quotaInvoker(),
        onQuotaExceeded: () async {
          paywallOpenCount += 1;
        },
      );

      await t.tap(find.text('準備邀約'));
      await t.pumpAndSettle();
      await t.tap(find.text('還沒想好'));
      await t.pumpAndSettle();
      await t.tap(find.text('產生跟進建議'));
      await t.pump();
      await t.pump();

      expect(paywallOpenCount, 1);
      expect(find.textContaining('額度已用完'), findsOneWidget);
    });

    testWidgets('monthly quota 429 shows the server monthly copy, not 明天再試',
        (t) async {
      await _pump(
        t,
        repo: _FakeRepo(),
        partner: _partner(),
        invoker: (String _, {required Map<String, dynamic> body}) async {
          return CoachFollowUpInvokeResponse(
            status: 429,
            data: <String, dynamic>{
              'error': 'Monthly limit exceeded',
              'message': '本月額度已用完，升級方案可取得更多分析與教練額度。',
              'used': 300,
              'limit': 300,
            },
          );
        },
        onQuotaExceeded: () async {},
      );

      await t.tap(find.text('準備邀約'));
      await t.pumpAndSettle();
      await t.tap(find.text('還沒想好'));
      await t.pumpAndSettle();
      await t.tap(find.text('產生跟進建議'));
      await t.pump();
      await t.pump();

      expect(find.textContaining('本月額度已用完'), findsOneWidget);
      expect(find.textContaining('明天再試'), findsNothing);
    });

    testWidgets(
        'quota 429 without a display message falls back to neutral copy',
        (t) async {
      await _pump(
        t,
        repo: _FakeRepo(),
        partner: _partner(),
        invoker: _quotaInvoker(),
        onQuotaExceeded: () async {},
      );

      await t.tap(find.text('準備邀約'));
      await t.pumpAndSettle();
      await t.tap(find.text('還沒想好'));
      await t.pumpAndSettle();
      await t.tap(find.text('產生跟進建議'));
      await t.pump();
      await t.pump();

      expect(find.textContaining('額度已用完'), findsOneWidget);
      expect(find.textContaining('明天再試'), findsNothing);
      expect(find.textContaining('Daily limit exceeded'), findsNothing);
    });
  });

  group('CoachFollowUpSection — telemetry contract', () {
    testWidgets('emits Invoked event after successful sheet submit', (t) async {
      final events = <CoachFollowUpTelemetryEvent>[];
      await _pump(
        t,
        repo: _FakeRepo(),
        partner: _partner(),
        onTelemetry: events.add,
      );

      await t.tap(find.text('準備邀約'));
      await t.pumpAndSettle();
      await t.tap(find.text('還沒想好'));
      await t.pumpAndSettle();
      await t.tap(find.text('產生跟進建議'));
      await t.pumpAndSettle();

      final invoked = events.whereType<CoachFollowUpInvokedEvent>().toList();
      expect(invoked, hasLength(1));
      expect(invoked.first.phase, CoachFollowUpPhase.prepareInvite);
      expect(invoked.first.hasOptionalText, isFalse);
    });

    testWidgets('open coach Invoked event uses openCoach + optional text',
        (t) async {
      final events = <CoachFollowUpTelemetryEvent>[];
      await _pump(
        t,
        repo: _FakeRepo(),
        partner: _partner(),
        onTelemetry: events.add,
      );

      await t.tap(find.text('或直接問教練一個問題...'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '她回很慢，我該等還是約？');
      await t.pumpAndSettle();
      await t.tap(find.text('讓教練看一下'));
      await t.pumpAndSettle();

      final invoked = events.whereType<CoachFollowUpInvokedEvent>().single;
      expect(invoked.phase, CoachFollowUpPhase.openCoach);
      expect(invoked.hasOptionalText, isTrue);
    });

    testWidgets('Invoked.hasOptionalText true when q3 free-text filled',
        (t) async {
      final events = <CoachFollowUpTelemetryEvent>[];
      await _pump(
        t,
        repo: _FakeRepo(),
        partner: _partner(),
        onTelemetry: events.add,
      );

      await t.tap(find.text('準備邀約'));
      await t.pumpAndSettle();
      await t.tap(find.text('還沒想好'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '想練約她吃飯');
      await t.pumpAndSettle();
      await t.tap(find.text('產生跟進建議'));
      await t.pumpAndSettle();

      final invoked = events.whereType<CoachFollowUpInvokedEvent>().single;
      expect(invoked.hasOptionalText, isTrue);
    });

    testWidgets('emits Regenerated event on regenerate tap (after gen)',
        (t) async {
      final events = <CoachFollowUpTelemetryEvent>[];
      await _pump(
        t,
        repo: _FakeRepo(),
        partner: _partner(),
        onTelemetry: events.add,
      );

      // Establish session-known answers via a fresh generate first.
      await t.tap(find.text('準備邀約'));
      await t.pumpAndSettle();
      await t.tap(find.text('還沒想好'));
      await t.pumpAndSettle();
      await t.tap(find.text('產生跟進建議'));
      await t.pumpAndSettle();
      events.clear();

      await t.tap(find.text('重新生成'));
      await t.pumpAndSettle();

      final regen = events.whereType<CoachFollowUpRegeneratedEvent>().toList();
      expect(regen, hasLength(1));
      expect(regen.first.phase, CoachFollowUpPhase.prepareInvite);
    });

    testWidgets('does NOT emit PhaseSwitched on the very first chip tap',
        (t) async {
      final events = <CoachFollowUpTelemetryEvent>[];
      await _pump(
        t,
        repo: _FakeRepo(),
        partner: _partner(),
        onTelemetry: events.add,
      );

      await t.tap(find.text('準備邀約'));
      await t.pumpAndSettle();

      expect(
        events.whereType<CoachFollowUpPhaseSwitchedEvent>(),
        isEmpty,
      );
    });

    testWidgets(
        'emits PhaseSwitched(hadResultBefore=true) when stored result phase changes',
        (t) async {
      // User has a stored result on prepareInvite, hits 換情境, then taps
      // 約會前提醒. Switch event fires from the chip tap, not from 換情境.
      final repo = _FakeRepo()..seed(_stored());
      final events = <CoachFollowUpTelemetryEvent>[];
      await _pump(
        t,
        repo: repo,
        partner: _partner(),
        onTelemetry: events.add,
      );

      await t.tap(find.text('換情境'));
      await t.pumpAndSettle();
      await t.tap(find.text('約會前提醒'));
      await t.pumpAndSettle();

      final switches =
          events.whereType<CoachFollowUpPhaseSwitchedEvent>().toList();
      expect(switches, hasLength(1));
      expect(switches.first.fromPhase, CoachFollowUpPhase.prepareInvite);
      expect(switches.first.toPhase, CoachFollowUpPhase.preDateReminder);
      expect(switches.first.hadResultBefore, isTrue);
    });
  });
}
