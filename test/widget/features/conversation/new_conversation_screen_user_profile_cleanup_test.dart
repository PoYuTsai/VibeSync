// Spec 1 cleanup: 你的風格 / 你的興趣 chips/fields removed from manual input.
// Schema (`SessionContext.userStyle / userInterests`) intentionally kept for
// backward compatibility with existing Hive records — design §13 forbids
// silent migration.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:vibesync/features/conversation/data/providers/conversation_write_controller.dart';
import 'package:vibesync/features/conversation/presentation/screens/new_conversation_screen.dart';

import '_fakes/recording_conversation_write_controller.dart';

GoRouter _router() => GoRouter(
      initialLocation: '/new',
      routes: [
        GoRoute(
          path: '/new',
          builder: (_, __) => const NewConversationScreen(),
        ),
        GoRoute(
          path: '/conversation/:id',
          builder: (_, __) => const Scaffold(body: Text('post-create-stub')),
        ),
      ],
    );

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

Future<void> _expandPersonalization(WidgetTester t) async {
  final tile = find.text('個人化資訊（選填）');
  await t.ensureVisible(tile);
  await _settle(t);
  await t.tap(tile);
  await _settle(t);
}

Widget _harness({RecordingConversationWriteController? recorder}) {
  return ProviderScope(
    overrides: [
      if (recorder != null)
        conversationWriteControllerProvider.overrideWith(() => recorder),
    ],
    child: MaterialApp.router(routerConfig: _router()),
  );
}

void main() {
  testWidgets('Manual input no longer shows 你的風格', (tester) async {
    await tester.pumpWidget(_harness());
    await _settle(tester);
    await _expandPersonalization(tester);
    expect(find.text('你的風格'), findsNothing);
  });

  testWidgets('Manual input no longer shows 你的興趣', (tester) async {
    await tester.pumpWidget(_harness());
    await _settle(tester);
    await _expandPersonalization(tester);
    expect(find.text('你的興趣'), findsNothing);
  });

  testWidgets('Manual input still shows 認識情境', (tester) async {
    await tester.pumpWidget(_harness());
    await _settle(tester);
    await _expandPersonalization(tester);
    expect(find.text('認識情境'), findsOneWidget);
  });

  testWidgets('Manual input still shows 認識多久', (tester) async {
    await tester.pumpWidget(_harness());
    await _settle(tester);
    await _expandPersonalization(tester);
    expect(find.text('認識多久'), findsOneWidget);
  });

  testWidgets('Manual input still shows 目前目標', (tester) async {
    await tester.pumpWidget(_harness());
    await _settle(tester);
    await _expandPersonalization(tester);
    expect(find.text('目前目標'), findsOneWidget);
  });

  testWidgets('Manual input still shows 對方特質', (tester) async {
    await tester.pumpWidget(_harness());
    await _settle(tester);
    await _expandPersonalization(tester);
    expect(find.text('對方特質'), findsOneWidget);
  });

  testWidgets('Legacy user-style CTA no longer renders in manual input',
      (tester) async {
    await tester.pumpWidget(_harness());
    await _settle(tester);
    await _expandPersonalization(tester);
    expect(
      find.text('想讓建議更像你的語氣？可到「報告 > 關於我」設定一次。'),
      findsNothing,
    );
    expect(find.textContaining('我的報告 > 關於我'), findsNothing);
    expect(find.text('這些對方資訊可到對象卡的「對方特質」齒輪設定一次。'), findsOneWidget);
  });
}
