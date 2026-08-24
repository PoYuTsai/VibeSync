// PR C 版面驗收證據（D5b：Threads，不是朋友圈）。
//
// 這幾張截圖就是 D5b 的驗收條件：
// 1. 一屏 feed（純文字＋圖文混排）→ 量「一屏至少 3 則純文字」與 Threads 密度
// 2. 空畫面
// 3. 錯誤狀態
// 另附：純文字密度（把圖全拿掉，最嚴格的量法）與載入中。
//
// 貼文素材直接用 lib/ 內的 **debug-only fixtures**（D3），所以這幾張圖＝
// Eric 在自己手機 debug build 上會看到的同一份東西，不是另做一套樣本。
// 產出落在 build/visual_proof/。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:vibesync/features/practice_chat/data/providers/practice_chat_providers.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_moment_post.dart';
import 'package:vibesync/features/practice_chat/presentation/screens/practice_moments_screen.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_moments_debug_fixtures.dart';

import 'proof_support.dart';

/// 假資料的時間基準**必須跟畫面用的時鐘同一個**。
///
/// 這裡踩過一次坑：原本寫死 `DateTime(2026, 8, 24, 21, 40)`，但
/// `PracticeMomentsScreen` 內部是 `DateTime.now()`，於是所有 postedAt 都
/// 落在「未來」，全部命中 momentRelativeLabel 的時鐘偏差防護，截圖上每則
/// 都顯示「剛剛」——版面看起來沒問題，時間標籤卻完全驗不到。
///
/// 真機 debug build 沒有這個問題（畫面把同一個 now 同時餵給 fixtures 與
/// tile），純粹是截圖測試繞過了那條路徑才失真。用真實時鐘就對齊了。
final DateTime _now = DateTime.now();

List<PracticeMomentPost> _feed() {
  final feed = practiceMomentsDebugFeed(kMomentsDebugMixedFeed, _now);
  return feed?.value ?? const <PracticeMomentPost>[];
}

/// 假 notifier：build() 直接回固定清單／丟例外／永不完成，**永不打網路**。
class _SeededMoments extends PracticeMomentsNotifier {
  _SeededMoments(this._posts);

  final List<PracticeMomentPost> _posts;

  @override
  Future<List<PracticeMomentPost>> build() async => _posts;
}

class _FailingMoments extends PracticeMomentsNotifier {
  @override
  Future<List<PracticeMomentPost>> build() async =>
      throw Exception('practice_moments_failed');
}

class _PendingMoments extends PracticeMomentsNotifier {
  @override
  Future<List<PracticeMomentPost>> build() =>
      Completer<List<PracticeMomentPost>>().future;
}

Widget _app(PracticeMomentsNotifier Function() notifier) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => const PracticeMomentsScreen()),
    ],
  );
  return ProviderScope(
    overrides: [practiceMomentsProvider.overrideWith(notifier)],
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'AppTC', useMaterial3: true),
      routerConfig: router,
    ),
  );
}

void main() {
  setUpAll(loadProofFonts);

  testWidgets('動態 feed：純文字＋圖文混排（Threads 密度驗收）', (tester) async {
    await pumpAndCapture(
      tester,
      child: _app(() => _SeededMoments(_feed())),
      // 圖文貼文要真的 decode 出來才截得到，不然是空框。
      rasterDecodeWait: const Duration(milliseconds: 900),
      outPath: outPath('practice_moments_feed.png'),
    );
  });

  testWidgets('動態 feed：捲到第一張圖（驗圖沒有搶焦點）', (tester) async {
    await pumpAndCapture(
      tester,
      child: _app(() => _SeededMoments(_feed())),
      rasterDecodeWait: const Duration(milliseconds: 900),
      beforeCapture: (tester) async {
        await tester.drag(
          find.byKey(const ValueKey('moments-list')),
          const Offset(0, -120),
        );
        await tester.pump(const Duration(milliseconds: 400));
      },
      outPath: outPath('practice_moments_with_image.png'),
    );
  });

  testWidgets('動態 feed：純文字密度（最嚴格的一屏 ≥ 3 則量法）', (tester) async {
    final textOnly = _feed().where((p) => p.imageId == null).toList();
    await pumpAndCapture(
      tester,
      child: _app(() => _SeededMoments(textOnly)),
      outPath: outPath('practice_moments_text_density.png'),
    );
  });

  testWidgets('動態 feed：空畫面', (tester) async {
    await pumpAndCapture(
      tester,
      child: _app(() => _SeededMoments(const <PracticeMomentPost>[])),
      outPath: outPath('practice_moments_empty.png'),
    );
  });

  testWidgets('動態 feed：錯誤狀態', (tester) async {
    await pumpAndCapture(
      tester,
      child: _app(_FailingMoments.new),
      outPath: outPath('practice_moments_error.png'),
    );
  });

  testWidgets('動態 feed：載入中', (tester) async {
    await pumpAndCapture(
      tester,
      child: _app(_PendingMoments.new),
      outPath: outPath('practice_moments_loading.png'),
    );
  });
}
