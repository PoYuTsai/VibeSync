// test/unit/features/onboarding/onboarding_service_handoff_test.dart
//
// onboarding 轉換第 12 步：登入前交接暫存升版。
//   - stashPendingHandoff 寫一份有版本號的 JSON（路徑、目的地、目標、第 2 頁答對
//     沒有、時間），舊鍵一起清掉。
//   - readPendingHandoff 只讀不清；讀不懂（壞掉、版本不對）或過期（7 天）的清掉
//     回 null；沒有新格式時讀舊鍵 onboarding_pending_goals／route。
//   - applyPendingHandoff：讀取 → 套用 → 套用回報成功才清除；同一時間只套用一次。
//   - onboarding_completed 這個鍵名不改（改了會把已登入的舊用戶拉回 onboarding）。
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/features/onboarding/data/onboarding_service.dart';
import 'package:vibesync/features/onboarding/domain/onboarding_intent.dart';

final _t0 = DateTime.utc(2026, 10, 27, 1);

Future<Map<String, Object?>> _storedJson() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(OnboardingService.pendingHandoffKey);
  expect(raw, isNotNull);
  return (jsonDecode(raw!) as Map).cast<String, Object?>();
}

Future<bool> _hasAnyStash() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.containsKey(OnboardingService.pendingHandoffKey) ||
      prefs.containsKey(OnboardingService.legacyPendingRouteKey) ||
      prefs.containsKey(OnboardingService.legacyPendingGoalsKey);
}

Future<void> _stash({
  OnboardingIntent intent = OnboardingIntent.analyze,
  String route = '/partner/new?next=screenshot',
  List<String> goals = const ['softInvite'],
  bool? quizCorrect = true,
  DateTime? at,
}) =>
    OnboardingService.stashPendingHandoff(
      intent: intent,
      route: route,
      goalNames: goals,
      quizCorrect: quizCorrect,
      now: at ?? _t0,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('stashPendingHandoff', () {
    test('寫一份有版本號的 JSON：路徑、目的地、目標、答對沒有、UTC 時間', () async {
      await _stash(
        intent: OnboardingIntent.practice,
        route: '/practice-collection?guide=1',
        goals: const ['humorousReply', 'softInvite'],
        quizCorrect: false,
        at: DateTime.parse('2026-10-27T09:30:00+08:00'),
      );

      expect(await _storedJson(), {
        'version': 2,
        'intent': 'practice',
        'route': '/practice-collection?guide=1',
        'goals': ['humorousReply', 'softInvite'],
        'quizCorrect': false,
        'stashedAt': '2026-10-27T01:30:00.000Z',
      });
    });

    test('沒作答（直接開始）存 null', () async {
      await _stash(quizCorrect: null);
      final stored = await _storedJson();
      expect(stored.containsKey('quizCorrect'), isTrue);
      expect(stored['quizCorrect'], isNull);
    });

    test('舊鍵若還在一起清掉，免得套用兩次', () async {
      SharedPreferences.setMockInitialValues({
        OnboardingService.legacyPendingRouteKey: '/partner/new',
        OnboardingService.legacyPendingGoalsKey: <String>['softInvite'],
      });

      await _stash();

      final prefs = await SharedPreferences.getInstance();
      expect(
          prefs.containsKey(OnboardingService.legacyPendingRouteKey), isFalse);
      expect(
          prefs.containsKey(OnboardingService.legacyPendingGoalsKey), isFalse);
      expect(prefs.containsKey(OnboardingService.pendingHandoffKey), isTrue);
    });
  });

  group('readPendingHandoff', () {
    test('新格式讀回同樣內容，而且不清除', () async {
      await _stash(goals: const ['softInvite', 'buildCloseness']);

      final handoff = await OnboardingService.readPendingHandoff(now: _t0);
      expect(handoff, isNotNull);
      expect(handoff!.intent, OnboardingIntent.analyze);
      expect(handoff.route, '/partner/new?next=screenshot');
      expect(handoff.goalNames, ['softInvite', 'buildCloseness']);
      expect(handoff.quizCorrect, isTrue);
      expect(handoff.stashedAt, _t0);

      // 只讀不清：再讀一次還在。
      expect(await OnboardingService.readPendingHandoff(now: _t0), isNotNull);
    });

    test('舊鍵照讀：目的地與目標；沒有路徑、答對沒有與時間', () async {
      SharedPreferences.setMockInitialValues({
        OnboardingService.legacyPendingRouteKey: '/practice-collection?guide=1',
        OnboardingService.legacyPendingGoalsKey: <String>['softInvite'],
      });

      final handoff = await OnboardingService.readPendingHandoff(now: _t0);
      expect(handoff!.route, '/practice-collection?guide=1');
      expect(handoff.goalNames, ['softInvite']);
      expect(handoff.intent, isNull);
      expect(handoff.quizCorrect, isNull);
      expect(handoff.stashedAt, isNull);
      // 舊鍵也不在讀的時候清。
      expect(await _hasAnyStash(), isTrue);
    });

    test('舊鍵只有目的地、沒有目標也照讀', () async {
      SharedPreferences.setMockInitialValues({
        OnboardingService.legacyPendingRouteKey: '/partner/new',
      });

      final handoff = await OnboardingService.readPendingHandoff(now: _t0);
      expect(handoff!.route, '/partner/new');
      expect(handoff.goalNames, isEmpty);
    });

    test('沒有暫存回 null', () async {
      expect(await OnboardingService.readPendingHandoff(now: _t0), isNull);
    });

    test('讀不懂的新格式：回 null 並清掉（連舊鍵）', () async {
      final unreadable = <Object>[
        'not json',
        '[]',
        jsonEncode({
          'version': 1,
          'route': '/opener',
          'stashedAt': '2026-10-27T01:00:00.000Z'
        }),
        jsonEncode({
          'version': 3,
          'route': '/opener',
          'stashedAt': '2026-10-27T01:00:00.000Z'
        }),
        jsonEncode({'version': 2, 'stashedAt': '2026-10-27T01:00:00.000Z'}),
        jsonEncode({
          'version': 2,
          'route': 'opener',
          'stashedAt': '2026-10-27T01:00:00.000Z'
        }),
        jsonEncode({
          'version': 2,
          'route': 42,
          'stashedAt': '2026-10-27T01:00:00.000Z'
        }),
        jsonEncode({'version': 2, 'route': '/opener'}),
        jsonEncode({'version': 2, 'route': '/opener', 'stashedAt': '昨天'}),
        42,
      ];
      for (final value in unreadable) {
        SharedPreferences.setMockInitialValues({
          OnboardingService.pendingHandoffKey: value,
          OnboardingService.legacyPendingRouteKey: '/partner/new',
        });

        expect(
          await OnboardingService.readPendingHandoff(now: _t0),
          isNull,
          reason: '$value',
        );
        expect(await _hasAnyStash(), isFalse, reason: '$value');
      }
    });

    test('不認得的路徑值、壞掉的目標與答對欄位：路徑當 null、目標只留字串、答對當沒作答', () async {
      SharedPreferences.setMockInitialValues({
        OnboardingService.pendingHandoffKey: jsonEncode({
          'version': 2,
          'intent': 'flirt',
          'route': '/opener',
          'goals': ['softInvite', 3, null],
          'quizCorrect': 'yes',
          'stashedAt': _t0.toIso8601String(),
        }),
      });

      final handoff = await OnboardingService.readPendingHandoff(now: _t0);
      expect(handoff!.intent, isNull);
      expect(handoff.route, '/opener');
      expect(handoff.goalNames, ['softInvite']);
      expect(handoff.quizCorrect, isNull);
    });

    test('7 天內照讀；超過 7 天的不套用、清掉', () async {
      await _stash(at: _t0);
      final within = _t0.add(const Duration(days: 7));
      expect(
          await OnboardingService.readPendingHandoff(now: within), isNotNull);

      final beyond = _t0.add(const Duration(days: 7, minutes: 1));
      expect(await OnboardingService.readPendingHandoff(now: beyond), isNull);
      expect(await _hasAnyStash(), isFalse);
    });

    test('時鐘被調過、暫存時間跑到未來超過 7 天也一樣不套用', () async {
      await _stash(at: _t0.add(const Duration(days: 8)));

      expect(await OnboardingService.readPendingHandoff(now: _t0), isNull);
      expect(await _hasAnyStash(), isFalse);
    });

    test('舊鍵沒有時間：不看過期，照舊套用', () async {
      SharedPreferences.setMockInitialValues({
        OnboardingService.legacyPendingRouteKey: '/opener',
      });

      final farFuture = _t0.add(const Duration(days: 365));
      expect(
        await OnboardingService.readPendingHandoff(now: farFuture),
        isNotNull,
      );
    });
  });

  group('applyPendingHandoff：讀取 → 套用 → 確認成功才清除', () {
    test('套用回 true 才清掉', () async {
      await _stash();
      OnboardingHandoff? seen;

      await OnboardingService.applyPendingHandoff((handoff) async {
        seen = handoff;
        // 套用期間暫存還在（不是讀到就清）。
        expect(await _hasAnyStash(), isTrue);
        return true;
      }, now: _t0);

      expect(seen?.route, '/partner/new?next=screenshot');
      expect(await _hasAnyStash(), isFalse);
    });

    test('套用回 false（例如畫面已經拆掉）：暫存留著，下次再套用', () async {
      await _stash();

      await OnboardingService.applyPendingHandoff((_) async => false, now: _t0);
      expect(await _hasAnyStash(), isTrue);

      var applied = 0;
      await OnboardingService.applyPendingHandoff((_) async {
        applied++;
        return true;
      }, now: _t0);
      expect(applied, 1);
      expect(await _hasAnyStash(), isFalse);
    });

    test('套用丟錯：不往外丟，暫存留著', () async {
      await _stash();

      await OnboardingService.applyPendingHandoff(
        (_) async => throw StateError('push 失敗'),
        now: _t0,
      );

      expect(await _hasAnyStash(), isTrue);
    });

    test('舊鍵套用成功後一起清掉', () async {
      SharedPreferences.setMockInitialValues({
        OnboardingService.legacyPendingRouteKey: '/partner/new',
        OnboardingService.legacyPendingGoalsKey: <String>['softInvite'],
      });

      await OnboardingService.applyPendingHandoff((_) async => true, now: _t0);

      expect(await _hasAnyStash(), isFalse);
    });

    test('沒有暫存：不呼叫套用', () async {
      var calls = 0;
      await OnboardingService.applyPendingHandoff((_) async {
        calls++;
        return true;
      }, now: _t0);
      expect(calls, 0);
    });

    test('同一時間只套用一次：第二個呼叫等同一份結果，不會導兩次頁', () async {
      await _stash();
      final gate = Completer<bool>();
      var calls = 0;
      Future<bool> apply(OnboardingHandoff _) {
        calls++;
        return gate.future;
      }

      final first = OnboardingService.applyPendingHandoff(apply, now: _t0);
      final second = OnboardingService.applyPendingHandoff(apply, now: _t0);
      await Future<void>.delayed(Duration.zero);
      gate.complete(true);
      await Future.wait([first, second]);

      expect(calls, 1);
      expect(await _hasAnyStash(), isFalse);

      // 跑完之後再呼叫：沒有暫存了，也不會卡在上一輪。
      await OnboardingService.applyPendingHandoff(apply, now: _t0);
      expect(calls, 1);
    });
  });

  test('onboarding_completed 鍵名不變：已登入的舊用戶不會被拉回 onboarding', () async {
    await OnboardingService.markCompleted();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('onboarding_completed'), isTrue);

    SharedPreferences.setMockInitialValues({'onboarding_completed': true});
    expect(await OnboardingService.load(), isTrue);
  });
}
