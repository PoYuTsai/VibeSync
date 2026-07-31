// test/unit/app/chat_quiz_routes_test.dart
//
// 兩條新路由存在、路徑正確、而且指向對的畫面。
//
// 刻意只碰 `chatQuizRoutes` 而不是整個 `router`：後者初始化時會讀
// SupabaseService，在 unit test 裡直接拋「not initialized」。Dart 的 top-level
// final 是惰性初始化，所以只要不提到 router 就不會踩到它。
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vibesync/app/routes.dart';
import 'package:vibesync/features/learning/presentation/screens/chat_quiz_map_screen.dart';
import 'package:vibesync/features/learning/presentation/screens/chat_quiz_player_screen.dart';

GoRoute _routeAt(String path) {
  final matches =
      chatQuizRoutes.whereType<GoRoute>().where((route) => route.path == path);
  expect(matches, hasLength(1), reason: '找不到路由 $path');
  return matches.single;
}

/// 用 builder 產出畫面，不經過真的導航。
Future<Widget> _build(
  WidgetTester tester,
  GoRoute route, {
  Map<String, String> pathParameters = const {},
}) async {
  late Widget built;
  await tester.pumpWidget(
    Builder(
      builder: (context) {
        built = route.builder!(
          context,
          _FakeState(pathParameters: pathParameters),
        );
        return const SizedBox.shrink();
      },
    ),
  );
  return built;
}

void main() {
  testWidgets('關卡地圖路由指向 ChatQuizMapScreen', (tester) async {
    final built = await _build(tester, _routeAt('/learning/quiz'));
    expect(built, isA<ChatQuizMapScreen>());
  });

  testWidgets('答題器路由帶得到 levelId', (tester) async {
    final built = await _build(
      tester,
      _routeAt('/learning/quiz/levels/:levelId'),
      pathParameters: const {'levelId': 'quiz-level-1-2'},
    );
    expect(built, isA<ChatQuizPlayerScreen>());
    expect((built as ChatQuizPlayerScreen).levelId, 'quiz-level-1-2');
  });

  test('兩條路徑都在，而且沒有重複', () {
    final paths =
        chatQuizRoutes.whereType<GoRoute>().map((route) => route.path).toList();

    expect(paths, ['/learning/quiz', '/learning/quiz/levels/:levelId']);
    expect(paths.toSet(), hasLength(paths.length));
  });

  test('測驗路徑不與電子書路徑共用前綴段', () {
    // `/learning/books/...` 與 `/learning/quiz/...` 是兩個獨立的 id space。
    for (final route in chatQuizRoutes.whereType<GoRoute>()) {
      expect(route.path.startsWith('/learning/quiz'), isTrue);
      expect(route.path.contains('/books/'), isFalse);
    }
  });
}

class _FakeState extends GoRouterState {
  _FakeState({Map<String, String> pathParameters = const {}})
      : super(
          RouteConfiguration(
            ValueNotifier<RoutingConfig>(
              RoutingConfig(routes: chatQuizRoutes),
            ),
            navigatorKey: GlobalKey<NavigatorState>(),
          ),
          uri: Uri.parse('/'),
          matchedLocation: '/',
          pathParameters: pathParameters,
          fullPath: '/',
          pageKey: const ValueKey('test'),
        );
}
