// test/helpers/ebook_widget_harness.dart
//
// 電子書畫面用的 widget test 鷹架：內容 catalog、訂閱切片、帳號隔離的進度
// repository、以及一個含 /paywall 與首頁 stub 的 GoRouter。
//
// 訂閱狀態用可變的 override 提供，方便在同一個測試裡從「還在確認」切到
// 「已確認免費」，驗證 paywall 導向與內容不閃現。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/learning/data/providers/ebook_providers.dart';
import 'package:vibesync/features/learning/data/repositories/ebook_progress_repository.dart';
import 'package:vibesync/features/learning/domain/models/ebook.dart';
import 'package:vibesync/features/learning/presentation/screens/ebook_detail_screen.dart';
import 'package:vibesync/features/learning/presentation/screens/ebook_reader_screen.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_access_gate.dart';

const paywallStubText = 'PAYWALL_STUB';
const homeStubText = 'HOME_STUB';

/// 測試用的可變訂閱切片來源。
final testSubscriptionAccessProvider = StateProvider<EbookSubscriptionAccess>(
  (ref) => const EbookSubscriptionAccess.premium(),
);

class EbookHarness {
  EbookHarness({
    required this.container,
    required this.repository,
    required this.ownerUserId,
  });

  final ProviderContainer container;
  final EbookProgressRepository repository;
  final String? ownerUserId;

  void setAccess(EbookSubscriptionAccess access) {
    container.read(testSubscriptionAccessProvider.notifier).state = access;
  }
}

/// 記憶體版 Hive box。
///
/// 為什麼不在 widget test 裡用真 Hive：`Box.put` 是真磁碟 I/O，在
/// `testWidgets` 的 fake async 下不會完成，測試會卡死。真 Hive 的行為由
/// `ebook_progress_repository_test.dart` 覆蓋，這裡只需要一個可讀寫的鍵值儲存。
class InMemoryHiveBox extends Fake implements Box {
  final Map<dynamic, dynamic> data = <dynamic, dynamic>{};

  @override
  bool get isOpen => true;

  @override
  Iterable<dynamic> get keys => data.keys;

  @override
  bool containsKey(dynamic key) => data.containsKey(key);

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      data.containsKey(key) ? data[key] : defaultValue;

  @override
  Future<void> put(dynamic key, dynamic value) async {
    data[key] = value;
  }

  @override
  Future<void> delete(dynamic key) async {
    data.remove(key);
  }

  @override
  Future<int> clear() async {
    final removed = data.length;
    data.clear();
    return removed;
  }
}

Future<EbookHarness> pumpEbookApp(
  WidgetTester tester, {
  required String initialLocation,
  EbookCatalog? catalog,
  Object? catalogError,
  bool catalogPending = false,
  EbookSubscriptionAccess access = const EbookSubscriptionAccess.premium(),
  Box? progressBox,
  String? ownerUserId = 'harness-owner',
  double textScale = 1.0,
  Size size = const Size(390, 900),
  bool disableAnimations = false,
}) async {
  final repository =
      EbookProgressRepository(box: progressBox ?? InMemoryHiveBox());

  final container = ProviderContainer(
    overrides: [
      testSubscriptionAccessProvider.overrideWith((ref) => access),
      ebookSubscriptionAccessProvider
          .overrideWith((ref) => ref.watch(testSubscriptionAccessProvider)),
      ebookProgressOwnerProvider
          .overrideWith((ref) => Stream<String?>.value(ownerUserId)),
      ebookProgressRepositoryProvider.overrideWithValue(repository),
      if (catalogPending)
        ebookCatalogProvider
            .overrideWith((ref) => Completer<EbookCatalog>().future)
      else if (catalogError != null)
        ebookCatalogProvider.overrideWith((ref) async => throw catalogError)
      else
        ebookCatalogProvider.overrideWith((ref) async => catalog!),
    ],
  );
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/', builder: (_, __) => const _Stub(homeStubText)),
      GoRoute(
        path: '/paywall',
        builder: (_, __) => const _Stub(paywallStubText),
      ),
      GoRoute(
        path: '/learning/books/:bookId',
        builder: (context, state) => EbookDetailScreen(
          bookId: state.pathParameters['bookId']!,
        ),
      ),
      GoRoute(
        path: '/learning/books/:bookId/chapters/:chapterId',
        builder: (context, state) => EbookReaderScreen(
          bookId: state.pathParameters['bookId']!,
          chapterId: state.pathParameters['chapterId'],
        ),
      ),
    ],
  );
  addTearDown(router.dispose);

  // setSurfaceSize 才會真的改變 layout 約束；只改 MediaQueryData.size 不會，
  // 那樣「320px 不 overflow」等宣稱會是假的。
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: disableAnimations,
          ),
          child: child!,
        ),
      ),
    ),
  );

  return EbookHarness(
    container: container,
    repository: repository,
    ownerUserId: ownerUserId,
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
