// test/helpers/chat_quiz_widget_harness.dart
//
// 聊天測驗畫面用的 widget test 鷹架：內容 catalog、可變的訂閱切片、帳號隔離
// 的進度 repository，以及含 /paywall、電子書章節與關卡地圖 stub 的 GoRouter。
//
// 進度用記憶體版 Hive box：`Box.put` 是真磁碟 I/O，在 testWidgets 的 fake
// async 下不會完成，測試會卡死。真 Hive 的行為由
// `chat_quiz_progress_repository_test.dart` 覆蓋。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/learning/data/providers/chat_quiz_providers.dart';
import 'package:vibesync/features/learning/data/repositories/chat_quiz_progress_repository.dart';
import 'package:vibesync/features/learning/domain/models/chat_quiz.dart';
import 'package:vibesync/features/learning/presentation/screens/chat_quiz_player_screen.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_access_gate.dart';

import 'ebook_widget_harness.dart'
    show InMemoryHiveBox, paywallStubText, testSubscriptionAccessProvider;

const chatQuizMapStubText = 'QUIZ_MAP_STUB';
const ebookChapterStubText = 'EBOOK_CHAPTER_STUB';

class ChatQuizHarness {
  ChatQuizHarness({
    required this.container,
    required this.repository,
    required this.box,
    required this.router,
  });

  final ProviderContainer container;
  final ChatQuizProgressRepository repository;
  final Box box;
  final GoRouter router;

  void setAccess(EbookSubscriptionAccess access) {
    container.read(testSubscriptionAccessProvider.notifier).state = access;
  }

  String get location =>
      router.routerDelegate.currentConfiguration.uri.toString();
}

Future<ChatQuizHarness> pumpChatQuizApp(
  WidgetTester tester, {
  required String initialLocation,
  ChatQuizCatalog? catalog,
  Object? catalogError,
  bool catalogPending = false,
  EbookSubscriptionAccess access = const EbookSubscriptionAccess.premium(),
  Box? progressBox,
  String? ownerUserId = 'quiz-harness-owner',
  double textScale = 1.0,
  Size size = const Size(390, 900),
  Widget Function(BuildContext, GoRouterState)? mapBuilder,
}) async {
  final box = progressBox ?? InMemoryHiveBox();
  final repository = ChatQuizProgressRepository(box: box);

  final container = ProviderContainer(
    overrides: [
      testSubscriptionAccessProvider.overrideWith((ref) => access),
      ebookSubscriptionAccessProvider
          .overrideWith((ref) => ref.watch(testSubscriptionAccessProvider)),
      chatQuizProgressOwnerProvider
          .overrideWith((ref) => Stream<String?>.value(ownerUserId)),
      chatQuizProgressRepositoryProvider.overrideWithValue(repository),
      if (catalogPending)
        chatQuizCatalogProvider
            .overrideWith((ref) => Completer<ChatQuizCatalog>().future)
      else if (catalogError != null)
        chatQuizCatalogProvider.overrideWith((ref) async => throw catalogError)
      else
        chatQuizCatalogProvider.overrideWith((ref) async => catalog!),
    ],
  );
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/', builder: (_, __) => const _Stub('HOME_STUB')),
      GoRoute(
        path: '/paywall',
        builder: (_, __) => const _Stub(paywallStubText),
      ),
      GoRoute(
        path: '/learning/quiz',
        builder: mapBuilder ?? (_, __) => const _Stub(chatQuizMapStubText),
      ),
      GoRoute(
        path: '/learning/quiz/levels/:levelId',
        builder: (context, state) => ChatQuizPlayerScreen(
          levelId: state.pathParameters['levelId']!,
        ),
      ),
      GoRoute(
        path: '/learning/books/:bookId/chapters/:chapterId',
        builder: (_, __) => const _Stub(ebookChapterStubText),
      ),
    ],
  );
  addTearDown(router.dispose);

  // setSurfaceSize 才會真的改變 layout 約束；只改 MediaQueryData.size 不會，
  // 那樣「大字級不 overflow」的宣稱會是假的。
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );

  return ChatQuizHarness(
    container: container,
    repository: repository,
    box: box,
    router: router,
  );
}

class _Stub extends StatelessWidget {
  const _Stub(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text(label)));
  }
}
