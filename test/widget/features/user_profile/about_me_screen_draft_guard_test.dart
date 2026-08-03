import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vibesync/features/user_profile/data/providers/user_profile_providers.dart';
import 'package:vibesync/features/user_profile/presentation/screens/about_me_screen.dart';

import '_harness.dart' show FakeUserProfileRepo;

// 返回鍵保護草稿（「關於我」重新定位 report 批 1 #3）：改了東西按返回
// 要跳確認，避免手滑漏改。用真的 push 出來的頁面（有 back stack）測，
// 單一路由的 harness 不會渲染 AppBar 返回鍵。
Future<void> _pumpWithBackStack(
  WidgetTester tester, {
  required FakeUserProfileRepo repo,
}) async {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (context, state) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => context.push('/profile/about-me'),
              child: const Text('open-about-me'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/profile/about-me',
        builder: (_, __) => const AboutMeScreen(),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userProfileRepositoryProvider.overrideWithValue(repo),
        authUserProfileScopeProvider
            .overrideWith((ref) => Stream.value(FakeUserProfileRepo.testUid)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open-about-me'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('改了東西按返回鍵 → 跳確認，選「繼續編輯」留在頁面', (tester) async {
    await _pumpWithBackStack(tester, repo: FakeUserProfileRepo());

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '溫柔'));
    await tester.tap(find.widgetWithText(ChoiceChip, '溫柔'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('放棄變更？'), findsOneWidget);

    await tester.tap(find.text('繼續編輯'));
    await tester.pumpAndSettle();

    expect(find.text('放棄變更？'), findsNothing);
    expect(find.text('open-about-me'), findsNothing);
    final chip =
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '溫柔'));
    expect(chip.selected, isTrue);
  });

  testWidgets('改了東西按返回鍵 → 跳確認，選「放棄變更」真的離開', (tester) async {
    await _pumpWithBackStack(tester, repo: FakeUserProfileRepo());

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '溫柔'));
    await tester.tap(find.widgetWithText(ChoiceChip, '溫柔'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await tester.tap(find.text('放棄變更'));
    await tester.pumpAndSettle();

    expect(find.text('open-about-me'), findsOneWidget);
  });

  testWidgets('沒有改動按返回鍵 → 直接離開，不跳確認', (tester) async {
    await _pumpWithBackStack(tester, repo: FakeUserProfileRepo());

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('放棄變更？'), findsNothing);
    expect(find.text('open-about-me'), findsOneWidget);
  });
}
