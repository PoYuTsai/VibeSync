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
import 'package:vibesync/features/practice_chat/data/services/practice_chat_api_service.dart';
import 'package:vibesync/features/practice_chat/presentation/screens/practice_moments_screen.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_girl_photo.dart';

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

/// 第一次載入失敗、之後成功——用來驗「重試鈕真的有接上」。
class _RecoveringMoments extends PracticeMomentsNotifier {
  _RecoveringMoments(this._posts);
  final List<PracticeMomentPost> _posts;
  int loads = 0;

  Future<List<PracticeMomentPost>> _fetch() async {
    loads++;
    if (loads == 1) throw Exception('boom');
    return _posts;
  }

  @override
  Future<List<PracticeMomentPost>> build() => _fetch();

  // 真的 refresh() 走的是私有的 _load()，不會回頭呼叫 build()——
  // 只覆寫 build 的話重試會落到真的 API service 去。這裡驗的是
  // 「重試鈕有沒有接到 refresh()」這條接線，所以假件同步覆寫它。
  @override
  Future<void> refresh() async {
    state = const AsyncLoading<List<PracticeMomentPost>>().copyWithPrevious(
      state,
    );
    state = await AsyncValue.guard(_fetch);
  }
}

/// 數 build 次數——用來驗 autoDispose（離頁再進要重新 build）。
/// 計數器刻意放在**外面**：provider 被 autoDispose 丟棄後會重新呼叫 factory，
/// 每次都是新的 notifier 實例，計數器放實例上會跟著歸零。
class _CountingMoments extends PracticeMomentsNotifier {
  _CountingMoments(this._posts, this._onBuild);
  final List<PracticeMomentPost> _posts;
  final void Function() _onBuild;

  @override
  Future<List<PracticeMomentPost>> build() async {
    _onBuild();
    return _posts;
  }
}

/// 可以離開動態頁再回來的殼。用同一個 notifier 實例，這樣 build 次數
/// 才反映「provider 有沒有被丟棄後重建」，而不是換了一個假件。
class _EnterLeaveHost extends StatefulWidget {
  const _EnterLeaveHost();

  @override
  State<_EnterLeaveHost> createState() => _EnterLeaveHostState();
}

class _EnterLeaveHostState extends State<_EnterLeaveHost> {
  bool _showing = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Row(
            children: [
              TextButton(
                key: const ValueKey('leave-moments'),
                onPressed: () => setState(() => _showing = false),
                child: const Text('離開'),
              ),
              TextButton(
                key: const ValueKey('enter-moments'),
                onPressed: () => setState(() => _showing = true),
                child: const Text('進入'),
              ),
            ],
          ),
          Expanded(
            child: _showing
                ? const PracticeMomentsScreen()
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// 走**真的** PracticeMomentsNotifier（含真的 .timeout）的殼。
/// 只換掉最外層的網路呼叫與登入身分，中間那段是產品程式碼本身。
Widget _realNotifierApp(PracticeChatInvoker invoker) {
  return ProviderScope(
    overrides: [
      practiceCollectionOwnerProvider.overrideWith(
        (ref) => Stream<String?>.value('user-1'),
      ),
      practiceChatApiServiceProvider.overrideWithValue(
        PracticeChatApiService(invoker: invoker),
      ),
    ],
    child: const MaterialApp(home: PracticeMomentsScreen()),
  );
}

Widget _countingApp(
  List<PracticeMomentPost> posts,
  void Function() onBuild,
) {
  return ProviderScope(
    overrides: [
      practiceMomentsProvider.overrideWith(
        () => _CountingMoments(posts, onBuild),
      ),
    ],
    child: const MaterialApp(home: _EnterLeaveHost()),
  );
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

      // 2026-08-24 複審：舊版只斷言 `find.byType(Image) findsWidgets`，
      // 那顆 Image 是頭像，純文字貼文本來就有——等於什麼都沒驗到。
      // 改成數 PracticeGirlPhoto（頭像與自拍配圖都是它）：純文字只有頭像那 1 個。
      // 配圖那一版是獨立一條測試，兩條合起來才證明得了「不帶圖」。
      expect(
        tester.widgetList(find.byType(PracticeGirlPhoto)).length,
        1,
        reason: '純文字貼文除了頭像不該再多出任何圖',
      );
    });

    testWidgets('配圖貼文：自拍配圖真的多畫一張，不是只認得欄位', (tester) async {
      // 與上一條成對：沒有這條的話，「純文字只有 1 個」可能只是因為配圖
      // 這條路徑根本沒接上，兩種貼文都畫不出圖也會過。
      final now = DateTime.now();
      await tester.pumpWidget(_app(() => _SeededMoments([
            _post(
              postedAt: now.subtract(const Duration(minutes: 12)),
              body: '早上出門忘了帶傘，結果整條路上只有我一個人在跑。',
              imageId: 'moment_self_portrait',
            ),
          ])));
      await tester.pumpAndSettle();

      expect(
        tester.widgetList(find.byType(PracticeGirlPhoto)).length,
        2,
        reason: '頭像 1 ＋ 自拍配圖 1；只有 1 代表 imageId 沒被畫出來',
      );
    });

    testWidgets('不認得的 imageId 降級成純文字，不破圖也不 crash', (tester) async {
      // 向前相容鐵則：server 先開閘門、client 還沒更新時會收到不認得的 id。
      final now = DateTime.now();
      await tester.pumpWidget(_app(() => _SeededMoments([
            _post(
              postedAt: now.subtract(const Duration(minutes: 12)),
              body: '早上出門忘了帶傘，結果整條路上只有我一個人在跑。',
              imageId: 'moment_scene_not_shipped_yet',
            ),
          ])));
      await tester.pumpAndSettle();

      expect(find.textContaining('早上出門忘了帶傘'), findsOneWidget);
      expect(
        tester.widgetList(find.byType(PracticeGirlPhoto)).length,
        1,
        reason: '不認得的 id 應降級成純文字，只留頭像',
      );
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

    testWidgets('錯誤：按下重試會真的再打一次，成功後換成列表', (tester) async {
      // 2026-08-24 複審：舊版只確認畫面上有「重試」兩個字，沒有按下去。
      // 一顆 onPressed 接錯 provider 的按鈕也能通過那種斷言。
      final notifier = _RecoveringMoments([
        _post(
          postedAt: DateTime.now().subtract(const Duration(minutes: 5)),
          body: '重試之後才拿得到的這一則貼文內容。',
        ),
      ]);
      await tester.pumpWidget(_app(() => notifier));
      await tester.pumpAndSettle();

      expect(find.byKey(_errorKey), findsOneWidget);
      expect(notifier.loads, 1, reason: '第一次載入應該只打一次');

      await tester.tap(find.byKey(const ValueKey('moments-retry')));
      await tester.pumpAndSettle();

      expect(notifier.loads, 2, reason: '按了重試卻沒有再打一次');
      expect(find.byKey(_errorKey), findsNothing);
      expect(find.byKey(_listKey), findsOneWidget);
      expect(find.textContaining('重試之後才拿得到'), findsOneWidget);
    });

    testWidgets('請求永不完成：逾時後落到錯誤／重試畫面，不會永遠轉圈', (tester) async {
      // 複審 P1：沒有 timeout 時這一頁會**永遠**停在載入中，而載入態刻意
      // 沒有重試鈕，使用者完全沒有出路。用假時鐘把 14 秒走完。
      //
      // 這條刻意**不覆寫 notifier**——timeout 是加在真的 _load() 裡，
      // 假 notifier 會整個繞過它，測了等於沒測。改成餵一個永不回應的
      // invoker，讓真的 PracticeMomentsNotifier 跑真的那條路徑。
      await tester.pumpWidget(_realNotifierApp(
        (_, {required body}) => Completer<PracticeInvokeResponse>().future,
      ));
      await tester.pump();
      expect(find.byKey(_loadingKey), findsOneWidget);

      // 還沒到逾時：仍應停在載入中（證明不是一進來就報錯）。
      await tester.pump(kPracticeMomentsRequestTimeout - const Duration(seconds: 1));
      expect(find.byKey(_loadingKey), findsOneWidget);
      expect(find.byKey(_errorKey), findsNothing);

      // 越過逾時：必須有出路。
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(
        find.byKey(_errorKey),
        findsOneWidget,
        reason: '逾時後仍未離開載入態＝網路懸停會永遠卡住',
      );
      expect(find.byKey(const ValueKey('moments-retry')), findsOneWidget);
      expect(find.byKey(_loadingKey), findsNothing);
      // 逾時是內部細節，不可外洩給使用者。
      expect(find.textContaining('TimeoutException'), findsNothing);
    });
  });

  group('AI 模擬內容揭露', () {
    testWidgets('三種狀態下揭露都在場，且文案固定', (tester) async {
      // 誤認成真人動態的風險與「這次有沒有貼文」無關，所以三態都要有。
      final cases = <String, PracticeMomentsNotifier Function()>{
        '有貼文': () => _SeededMoments([
              _post(postedAt: DateTime.now().subtract(const Duration(minutes: 3))),
            ]),
        '空清單': () => _SeededMoments(const <PracticeMomentPost>[]),
        '錯誤': _FailingMoments.new,
      };
      for (final entry in cases.entries) {
        await tester.pumpWidget(_app(entry.value));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('moments-ai-disclosure')),
          findsOneWidget,
          reason: '${entry.key} 狀態下缺少 AI 揭露',
        );
        expect(
          find.text('AI 模擬練習內容，不是真人動態'),
          findsOneWidget,
          reason: '${entry.key} 狀態下揭露文案不符',
        );
      }
    });

    testWidgets('揭露不跟著列表捲走', (tester) async {
      // 跟著捲動的揭露＝捲一下就消失，形同沒有。
      final now = DateTime.now();
      await tester.pumpWidget(_app(() => _SeededMoments([
            for (var i = 0; i < 30; i++)
              _post(
                postedAt: now.subtract(Duration(minutes: i + 1)),
                body: '第 $i 則貼文的內容，用來把列表撐到需要捲動的長度。',
              ),
          ])));
      await tester.pumpAndSettle();

      await tester.drag(find.byKey(_listKey), const Offset(0, -1200));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('moments-ai-disclosure')),
        findsOneWidget,
        reason: '捲動後揭露消失了——它必須在列表外面',
      );
    });
  });

  group('每次進頁重抓（autoDispose）', () {
    testWidgets('離頁再回來會再打一次 API，不吃舊資料', (tester) async {
      // 複審 P2：常駐 provider 會讓離頁再回來仍顯示舊 feed，只有手動下拉
      // 才更新——那不是「不做快取」，是換個地方做快取（違反 D7）。
      var builds = 0;
      await tester.pumpWidget(_countingApp(
        [
          _post(
            postedAt: DateTime.now().subtract(const Duration(minutes: 2)),
            body: '這一則用來確認畫面真的有被渲染出來。',
          ),
        ],
        () => builds++,
      ));
      await tester.pumpAndSettle();
      expect(builds, 1);

      // 離開動態頁（唯一的監聽者消失）→ autoDispose 應丟棄狀態。
      await tester.tap(find.byKey(const ValueKey('leave-moments')));
      await tester.pumpAndSettle();
      expect(find.byKey(_listKey), findsNothing);

      // 再進來一次。
      await tester.tap(find.byKey(const ValueKey('enter-moments')));
      await tester.pumpAndSettle();

      expect(
        builds,
        2,
        reason: '離頁再進沒有重新 build＝provider 沒有 autoDispose，'
            '使用者看到的是上次的舊 feed',
      );
    });
  });
}
