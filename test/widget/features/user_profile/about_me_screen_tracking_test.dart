import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vibesync/core/services/funnel_tracker.dart';
import 'package:vibesync/features/user_profile/data/providers/user_profile_providers.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';
import 'package:vibesync/features/user_profile/presentation/screens/about_me_screen.dart';

import '_harness.dart' show FakeUserProfileRepo;

class _RecordedEvent {
  _RecordedEvent(this.event, this.properties);
  final String event;
  final Map<String, Object?> properties;
}

Future<void> _pump(
  WidgetTester tester, {
  required FakeUserProfileRepo repo,
  required List<_RecordedEvent> events,
  String? source,
}) async {
  final tracker = FunnelTracker(
    invoker: (fn, {required body}) async {
      final event = body['event'] as Map<String, dynamic>;
      events.add(
        _RecordedEvent(
          event['event'] as String,
          Map<String, Object?>.from(event['properties'] as Map),
        ),
      );
      return 200;
    },
  );
  final router = GoRouter(
    initialLocation: '/profile/about-me',
    routes: [
      GoRoute(
        path: '/profile/about-me',
        builder: (_, __) => AboutMeScreen(source: source),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userProfileRepositoryProvider.overrideWithValue(repo),
        authUserProfileScopeProvider
            .overrideWith((ref) => Stream.value(FakeUserProfileRepo.testUid)),
        funnelTrackerProvider.overrideWithValue(tracker),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('打開頁面帶 source=checklist → track about_me_opened', (
    tester,
  ) async {
    final events = <_RecordedEvent>[];
    await _pump(
      tester,
      repo: FakeUserProfileRepo(),
      events: events,
      source: 'checklist',
    );

    final opened = events.where((e) => e.event == 'about_me_opened').toList();
    expect(opened, hasLength(1));
    expect(opened.single.properties, {'source': 'checklist'});
  });

  testWidgets('沒帶 source → about_me_opened 沒有 source 鍵', (tester) async {
    final events = <_RecordedEvent>[];
    await _pump(tester, repo: FakeUserProfileRepo(), events: events);

    final opened = events.where((e) => e.event == 'about_me_opened').toList();
    expect(opened, hasLength(1));
    expect(opened.single.properties, isEmpty);
  });

  testWidgets('儲存成功 → track about_me_saved 帶正確欄位計數', (tester) async {
    final events = <_RecordedEvent>[];
    await _pump(
      tester,
      repo: FakeUserProfileRepo(),
      events: events,
      source: 'card',
    );

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '直接'));
    await tester.tap(find.widgetWithText(ChoiceChip, '直接'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '想約得出來'));
    await tester.tap(find.widgetWithText(ChoiceChip, '想約得出來'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '咖啡'));
    await tester.tap(find.widgetWithText(ChoiceChip, '咖啡'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('about-me-notes')),
      '我慢熟',
    );
    await tester.pumpAndSettle();

    final saveBtn = find.widgetWithText(ElevatedButton, '儲存');
    await tester.ensureVisible(saveBtn);
    await tester.pumpAndSettle();
    await tester.tap(saveBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final saved = events.where((e) => e.event == 'about_me_saved').toList();
    expect(saved, hasLength(1));
    expect(saved.single.properties, {
      'has_style': true,
      'goals_count': 1,
      'seeds_count': 1,
      'has_notes': true,
      'has_custom_topics': false,
    });
  });

  testWidgets('清除成功 → track about_me_cleared', (tester) async {
    final events = <_RecordedEvent>[];
    final repo = FakeUserProfileRepo(
      initial: UserProfile.create(
        interactionStyle: InteractionStyle.gentle,
        updatedAt: DateTime.utc(2026, 4, 30),
      ),
    );
    await _pump(tester, repo: repo, events: events, source: 'settings');

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '溫柔'));
    await tester.tap(find.widgetWithText(ChoiceChip, '溫柔'));
    await tester.pumpAndSettle();
    final clearBtn = find.widgetWithText(ElevatedButton, '清除設定');
    await tester.ensureVisible(clearBtn);
    await tester.pumpAndSettle();
    await tester.tap(clearBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final cleared =
        events.where((e) => e.event == 'about_me_cleared').toList();
    expect(cleared, hasLength(1));
    expect(cleared.single.properties, isEmpty);
  });

  testWidgets('略過（全空直接離開）不 track saved／cleared', (tester) async {
    final events = <_RecordedEvent>[];
    await _pump(tester, repo: FakeUserProfileRepo(), events: events);

    final skipBtn = find.widgetWithText(ElevatedButton, '略過');
    await tester.ensureVisible(skipBtn);
    await tester.pumpAndSettle();
    await tester.tap(skipBtn);
    await tester.pumpAndSettle();

    expect(events.where((e) => e.event == 'about_me_saved'), isEmpty);
    expect(events.where((e) => e.event == 'about_me_cleared'), isEmpty);
  });
}
