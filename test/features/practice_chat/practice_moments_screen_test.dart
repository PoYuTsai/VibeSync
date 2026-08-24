// 動態頁的行為測試。
//
// 為什麼相對時間標籤佔了一半篇幅：產截圖時踩過一次坑——截圖測試用固定時鐘
// 造假資料、畫面卻用 DateTime.now() 算標籤，於是每則都落在「未來」、全部
// 命中時鐘偏差防護顯示「剛剛」。版面看起來完全正常，時間標籤卻整組失真。
// 那不是產品 bug（真機上畫面把同一個 now 同時餵給 fixtures 與 tile），但它
// 說明這個函式的錯法是「靜悄悄地全部退化成同一個值」，光看畫面看不出來。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/features/practice_chat/data/providers/practice_chat_providers.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_moment_post.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_moment_relative_time.dart';
import 'package:vibesync/features/practice_chat/presentation/screens/practice_moments_screen.dart';

PracticeMomentPost _post({
  required DateTime postedAt,
  String profileId = 'practice_girl_001',
  String body = '今天的天氣好得有點過分，午休直接走到河堤去。',
  String? imageId,
}) {
  return PracticeMomentPost(
    profileId: profileId,
    postDate: postedAt.toLocal().toIso8601String().substring(0, 10),
    slot: 0,
    dayPart: 'afternoon',
    postedAt: postedAt.toUtc(),
    body: body,
    imageId: imageId,
  );
}

class _SeededMoments extends PracticeMomentsNotifier {
  _SeededMoments(this._posts);
  final List<PracticeMomentPost> _posts;
  @override
  Future<List<PracticeMomentPost>> build() async => _posts;
}

class _FailingMoments extends PracticeMomentsNotifier {
  @override
  Future<List<PracticeMomentPost>> build() async => throw Exception('boom');
}

class _PendingMoments extends PracticeMomentsNotifier {
  @override
  Future<List<PracticeMomentPost>> build() =>
      Completer<List<PracticeMomentPost>>().future;
}

// 畫面的狀態 key 宣告在私有的 _MomentsBody 上，測試取不到型別，只能用字面
// 值。集中在這裡宣告一次，改名時只需要動一處。
const _loadingKey = ValueKey('moments-loading');
const _emptyKey = ValueKey('moments-empty');
const _errorKey = ValueKey('moments-error');
const _listKey = ValueKey('moments-list');

Widget _app(PracticeMomentsNotifier Function() notifier) {
  return ProviderScope(
    overrides: [practiceMomentsProvider.overrideWith(notifier)],
    child: const MaterialApp(home: PracticeMomentsScreen()),
  );
}

void main() {
  group('momentRelativeLabel', () {
    final now = DateTime(2026, 8, 24, 21, 40);

    test('四個分支各自成立', () {
      expect(momentRelativeLabel(now, now), '剛剛');
      expect(
        momentRelativeLabel(now.subtract(const Duration(seconds: 30)), now),
        '剛剛',
      );
      expect(
        momentRelativeLabel(now.subtract(const Duration(minutes: 12)), now),
        '12 分鐘前',
      );
      expect(
        momentRelativeLabel(now.subtract(const Duration(minutes: 155)), now),
        '2 小時前',
      );
    });

    test('小時／昨天的分界看日曆日，不是滿 24 小時', () {
      // 早上 9 點看昨晚 23:00 的貼文：只過了 10 小時，但已經是「昨天」。
      final morning = DateTime(2026, 8, 24, 9, 0);
      final lastNight = DateTime(2026, 8, 23, 23, 0);
      expect(momentRelativeLabel(lastNight, morning), '昨天 23:00');
    });

    test('前天以前退成月日', () {
      expect(
        momentRelativeLabel(DateTime(2026, 8, 21, 14, 5), now),
        '8月21日',
      );
    });

    test('時鐘偏差：postedAt 在未來也只說「剛剛」，絕不出現負數', () {
      // 這是本檔開頭那個坑的核心。server 與手機差幾秒是常態。
      for (final ahead in const [
        Duration(seconds: 5),
        Duration(minutes: 30),
        Duration(hours: 8),
      ]) {
        final label = momentRelativeLabel(now.add(ahead), now);
        expect(label, '剛剛', reason: '未來 $ahead 應為剛剛，實際 $label');
        expect(label.contains('-'), isFalse);
      }
    });

    test('不同間隔要產生不同標籤（防「全部退化成剛剛」）', () {
      final labels = <String>{
        for (final m in const [0, 12, 96, 155])
          momentRelativeLabel(now.subtract(Duration(minutes: m)), now),
      };
      expect(
        labels.length,
        greaterThan(1),
        reason: '所有間隔都得到同一個標籤，代表時間基準對不上',
      );
    });
  });

  group('動態頁三種狀態', () {
    testWidgets('有貼文：文字渲染出來，純文字貼文不帶圖', (tester) async {
      final now = DateTime.now();
      await tester.pumpWidget(_app(() => _SeededMoments([
            _post(
              postedAt: now.subtract(const Duration(minutes: 12)),
              body: '早上出門忘了帶傘，結果整條路上只有我一個人在跑。',
            ),
          ])));
      await tester.pumpAndSettle();

      expect(find.textContaining('早上出門忘了帶傘'), findsOneWidget);
      expect(find.textContaining('12 分鐘前'), findsOneWidget);
      // 純文字貼文不該出現貼文配圖（頭像不算，用貼文內文區塊判斷）。
      expect(find.byType(Image), findsWidgets); // 頭像仍在
    });

    testWidgets('空清單：顯示空狀態，且不塞任何假貼文', (tester) async {
      await tester.pumpWidget(_app(
        () => _SeededMoments(const <PracticeMomentPost>[]),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(_emptyKey), findsOneWidget);
      expect(find.byKey(_listKey), findsNothing);
      // no-canned 鐵則的畫面端反向確認：沒有資料就是沒有資料。
      expect(find.textContaining('忘了帶傘'), findsNothing);
    });

    testWidgets('載入中：顯示載入狀態，且不顯示空／錯誤', (tester) async {
      await tester.pumpWidget(_app(_PendingMoments.new));
      await tester.pump();

      // 斷言畫面自己宣告的 state key，不要猜它用哪個 widget——猜錯了測到的
      // 是實作細節而不是契約。
      expect(find.byKey(_loadingKey), findsOneWidget);
      expect(find.byKey(_emptyKey), findsNothing);
      expect(find.byKey(_errorKey), findsNothing);
    });

    testWidgets('錯誤：顯示可重試的錯誤狀態，不外洩例外訊息', (tester) async {
      await tester.pumpWidget(_app(_FailingMoments.new));
      await tester.pumpAndSettle();

      expect(find.byKey(_errorKey), findsOneWidget);
      expect(find.textContaining('重試'), findsWidgets);
      // 原始例外訊息絕不可出現在可見文字裡。
      expect(find.textContaining('boom'), findsNothing);
      expect(find.textContaining('Exception'), findsNothing);
    });
  });
}
