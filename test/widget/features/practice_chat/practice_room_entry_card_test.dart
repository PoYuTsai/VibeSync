import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_room_entry_card.dart';

void main() {
  testWidgets(
      'practice room entry uses the yoga girl hero and keeps daily badge',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(child: PracticeRoomEntryCard()),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('practice-room-entry-bg-image')),
        findsOneWidget);
    final image = tester.widget<Image>(
      find.byKey(const ValueKey('practice-room-entry-bg-image')),
    );
    expect((image.image as AssetImage).assetName,
        'assets/images/practice_girls/practice_girl_038.jpg');
    expect(find.byKey(const ValueKey('practice-room-entry-bg-blur')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('practice-room-entry-glass-panel')),
        findsOneWidget);
    expect(find.text('每日登入就送新女孩'), findsOneWidget);
    expect(find.text('AI 實戰練習室'), findsOneWidget);
    expect(find.text('NEW'), findsOneWidget);
    expect(find.text('跟模擬對象直接聊天，\n練你的真實反應。'), findsOneWidget);
  });

  testWidgets('點 hero 導航到 /practice-collection（圖鑑為 gacha hub）',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(
            body: SizedBox.expand(child: PracticeRoomEntryCard()),
          ),
        ),
        GoRoute(
          path: '/practice-collection',
          builder: (context, state) => const Scaffold(
            body: Text(
              'practice-collection-stub',
              key: ValueKey('practice-collection-stub'),
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();

    await tester.tap(find.byKey(
      const ValueKey('practice-room-entry-glass-panel'),
    ));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('practice-collection-stub')),
      findsOneWidget,
    );
  });
}
