// Actual GlobalCoachScreen / CoachSurface captures for the Sydney reading layout.
// Run in WSL after the environment doctor:
//   flutter test test/visual_proof/sydney_reading_layout_capture_test.dart
// Output: build/visual_proof/sydney_reading_{entry,summary,expanded,keyboard_inset}.png
//
// Only data and device insets are faked. The production widgets, controller,
// theme, static Sydney asset and expand interaction are rendered unchanged.
// The keyboard capture proves reserved space; Flutter's test renderer cannot
// paint an iOS system keyboard or prove physical-device behavior.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/core/theme/app_theme.dart';
import 'package:vibesync/features/coach_chat/data/providers/coach_chat_providers.dart';
import 'package:vibesync/features/coach_chat/data/services/coach_chat_api_service.dart';
import 'package:vibesync/features/coach_chat/presentation/screens/global_coach_screen.dart';
import 'package:vibesync/features/coach_chat/presentation/widgets/coach_surface.dart';
import 'package:vibesync/features/coaching_memory/data/providers/coaching_outcome_providers.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/user_profile/data/providers/data_quality_flag_provider.dart';
import 'package:vibesync/shared/widgets/ai_data_sharing_consent.dart';

import '../helpers/memory_coach_chat_repository.dart';
import '../helpers/memory_coaching_outcome_repository.dart';
import 'proof_support.dart';

const _question = '對方回得很短，我該怎麼判斷？';
const _headline = '先看有沒有接話，不急著判斷降溫';
const _longAnswer = '單次短回還不足以判斷對方的想法。先看這句有沒有接住你的話題、'
    '反問你，或補充一個小細節。這些線索比單純計算字數更值得留意。\n\n'
    '例如，對方雖然只回一句，卻問了你週末想去哪裡，這仍然是讓對話往下走的邀請。'
    '你可以自然回答那個問題，不需要立刻追問她是不是沒有興趣。\n\n'
    '如果最近幾次都只是句點式回覆，沒有接話，也沒有新的問題，先慢下來觀察。'
    '留一點空間，是讓雙方都有機會主動，而不是用更多訊息換一個確定的答案。\n\n'
    '回顧最近三則互動，只記下有沒有延伸話題。先看模式，不用把某一次簡短回覆'
    '當成整段關係的結論。你也可以看看自己的問句是不是太難回答，或一次問了太多。\n\n'
    '這次先保留原本自然的節奏。如果有真實想分享的事情，就分享一小段；如果只是'
    '焦慮地想確認關係，先停一下，等自己整理好再決定要不要傳。\n\n'
    '重點不是找到一個完美的句子，而是讓對話有來有往。先觀察對方能否接住，'
    '再根據新的互動調整，不替對方補上她沒有說過的想法。';

class _ProofSubscription extends SubscriptionNotifier {
  _ProofSubscription() {
    state = const SubscriptionState(
      dailyLimit: 5,
      monthlyLimit: 30,
      dailyMessagesUsed: 1,
    );
  }
}

class _ProofHarness {
  final repo = MemoryCoachChatRepository();
  final pending = Completer<CoachChatInvokeResponse>();
  final keyboardInset = ValueNotifier<double>(0);
  var calls = 0;

  Future<CoachChatInvokeResponse> invoke(
    String _, {
    required Map<String, dynamic> body,
  }) {
    calls++;
    return pending.future;
  }

  void completeAnswer() {
    pending.complete(
      CoachChatInvokeResponse(
        status: 200,
        data: {
          'card': {
            'responseType': 'coachAnswer',
            'mode': 'replyCraft',
            'headline': _headline,
            'answer': _longAnswer,
            'userState': '擔心自己把短回看得太重',
            'frictionType': 'unclearIntent',
            'nextStep': '回顧最近三則回覆，看看有沒有反問或延伸話題。',
            'suggestedLine': null,
            'messageDecision': 'no_message_needed',
            'rewriteReason': '先觀察互動模式，不急著補一則訊息。',
            'boundaryReminder': '別為了確認而連續追問，也別替她補上沒有說過的想法。',
            'needsReflection': false,
            'reflectionQuestion': null,
            'costDeducted': 1,
          },
          'provider': 'test',
          'model': 'visual-proof',
          'generatedAt': '2026-09-06T01:00:00Z',
          'sessionId': 'sydney-reading-proof',
        },
      ),
    );
  }
}

Future<void> _loadFonts() async {
  await loadProofFonts();
  // Some production RichText spans omit a family. Resolve their default family
  // to a real TC font as well, without altering the production TextStyles.
  final file = File([
    '/usr/share/fonts/opentype/noto/NotoSansCJKtc-Regular.otf',
    '/mnt/c/Windows/Fonts/NotoSansTC-VF.ttf',
    'C:/Windows/Fonts/NotoSansTC-VF.ttf',
  ].firstWhere((path) => File(path).existsSync()));
  final bytes = file.readAsBytesSync();
  await (FontLoader('Roboto')
        ..addFont(Future.value(ByteData.view(bytes.buffer))))
      .load();
}

Finder get _input => find.descendant(
      of: find.byType(CoachSurface),
      matching: find.byType(TextField),
    );

ScrollPosition _readingPosition(WidgetTester tester) => tester
    .state<ScrollableState>(find
        .descendant(
          of: find.byKey(const Key('coach-reading-scroll')),
          matching: find.byType(Scrollable),
        )
        .first)
    .position;

Future<void> _capture(
  WidgetTester tester,
  GlobalKey rootKey,
  String name,
) async {
  await tester.pump();
  expect(tester.takeException(), isNull);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(rootKey),
  );
  expect(boundary.size, kPhone);
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(data, isNotNull);
      final file = File(outPath('sydney_reading_$name.png'));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(_loadFonts);
  setUp(() {
    SharedPreferences.setMockInitialValues({
      AiDataSharingConsent.acceptedKeyForTesting: true,
    });
  });

  testWidgets(
      'capture real Sydney entry, answer, long reading and keyboard inset',
      (tester) async {
    await tester.binding.setSurfaceSize(kPhone);
    final rootKey = GlobalKey();
    final harness = _ProofHarness();
    final partner = Partner(
      id: 'proof-partner',
      name: '示範對象',
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
      ownerUserId: 'visual-proof-owner',
    );
    final theme = AppTheme.darkTheme;
    addTearDown(() async {
      if (harness.calls > 0 && !harness.pending.isCompleted) {
        harness.completeAnswer();
        await tester.pump(const Duration(milliseconds: 350));
      }
      await tester.pumpWidget(const SizedBox.shrink());
      harness.keyboardInset.dispose();
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coachChatRepositoryProvider.overrideWithValue(harness.repo),
          coachChatApiServiceProvider.overrideWithValue(
            CoachChatApiService(invoker: harness.invoke),
          ),
          coachChatUsageSyncProvider.overrideWithValue(() async {}),
          coachChatStyleContextResolverProvider.overrideWithValue(({
            required String? partnerId,
            required bool includePartnerOverride,
          }) async =>
              null),
          coachingOutcomeRepositoryProvider.overrideWithValue(
            MemoryCoachingOutcomeRepository(),
          ),
          subscriptionProvider.overrideWith((_) => _ProofSubscription()),
          partnerListProvider.overrideWithValue([partner]),
          partnerByIdProvider(partner.id).overrideWithValue(partner),
          partnerAggregateProvider(partner.id)
              .overrideWithValue(PartnerAggregateView.empty()),
          conversationsByPartnerProvider(partner.id)
              .overrideWithValue(const []),
          dataQualityFlagProvider(partner.id)
              .overrideWith((_) => const DataQualityFlag.unflagged()),
        ],
        child: RepaintBoundary(
          key: rootKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme.copyWith(
              appBarTheme: theme.appBarTheme.copyWith(
                titleTextStyle: theme.appBarTheme.titleTextStyle
                    ?.copyWith(fontFamily: 'AppTC'),
              ),
              textTheme: theme.textTheme.apply(fontFamily: 'AppTC'),
              primaryTextTheme:
                  theme.primaryTextTheme.apply(fontFamily: 'AppTC'),
            ),
            builder: (context, child) => ValueListenableBuilder<double>(
              valueListenable: harness.keyboardInset,
              builder: (context, inset, _) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  disableAnimations: true,
                  padding: EdgeInsets.fromLTRB(0, 47, 0, inset > 0 ? 0 : 34),
                  viewPadding: const EdgeInsets.only(top: 47, bottom: 34),
                  viewInsets: EdgeInsets.only(bottom: inset),
                ),
                child: DefaultTextStyle.merge(
                  style: const TextStyle(fontFamily: 'AppTC'),
                  child: child!,
                ),
              ),
            ),
            // Use the real pushed-route shape so AppBar includes its back button.
            home: const SizedBox.shrink(),
            initialRoute: '/coach',
            routes: {'/coach': (_) => const GlobalCoachScreen()},
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage('assets/images/coach/sydney_performance_v3_poster.jpg'),
        tester.element(find.byType(GlobalCoachScreen)),
      );
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('coach-welcome')), findsOneWidget);
    expect(harness.calls, 0);
    await _capture(tester, rootKey, 'entry');

    await tester.enterText(_input, _question);
    await tester.pump(); // Rebuild the now-enabled send button after typing.
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(harness.calls, 1);
    harness.completeAnswer();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text(_headline), findsOneWidget);
    expect(find.byKey(const Key('coach-compact-avatar')), findsOneWidget);
    expect(find.byKey(const Key('coach-welcome')), findsNothing);
    await _capture(tester, rootKey, 'summary');

    await tester.ensureVisible(find.text('看完整教練分析'));
    await tester.tap(find.text('看完整教練分析'));
    await tester.pumpAndSettle();
    expect(find.text(_longAnswer), findsOneWidget);
    await tester.ensureVisible(find.text(_longAnswer));
    await tester.pumpAndSettle();
    await _capture(tester, rootKey, 'expanded');

    // A real focused TextField and a 300px OS inset, not a drawn keyboard.
    // Capture includes the reserved empty area so it cannot be mistaken for
    // actual iPhone keyboard / text-input validation.
    final offset = _readingPosition(tester).pixels;
    await tester.tap(_input);
    harness.keyboardInset.value = 300;
    await tester.pumpAndSettle();
    expect(find.text(_longAnswer), findsOneWidget);
    expect(find.text('收起完整分析'), findsOneWidget);
    expect(_readingPosition(tester).pixels, closeTo(offset, 1));
    expect(tester.getBottomRight(_input).dy, lessThanOrEqualTo(844 - 300));
    await _capture(tester, rootKey, 'keyboard_inset');
    expect(harness.calls, 1, reason: 'Capturing/focusing must not ask again');
  });
}
