// 18+ 年齡確認頁（AGE-01）接上真的 resolveAppRedirect：登入、看完 onboarding、
// 帳號還沒確認成年 → 只能在年齡確認頁；成年 → 回首頁；未成年 → 鎖住，只剩聯絡
// 客服與設定頁（登出、刪除帳號）；連不上 → 請他再按一次，不放行。路由只看 session
// 裡的帳號紀錄（主審第 1 輪 P2），換 token 失敗也不放行。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibesync/app/routes.dart';
import 'package:vibesync/features/age_gate/data/age_gate_repository.dart';
import 'package:vibesync/features/age_gate/domain/age_gate.dart';
import 'package:vibesync/features/age_gate/presentation/screens/age_gate_screen.dart';

const _at = '2026-10-30T08:00:00.000Z';

User _user(Map<String, dynamic> appMetadata) => User(
      id: 'u1',
      appMetadata: appMetadata,
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: _at,
    );

/// 目前的 session：路由每次導頁都讀它；換 token 成功時換成帶著新紀錄的使用者。
class _Session {
  _Session(Map<String, dynamic> appMetadata) : user = _user(appMetadata);

  User user;
}

/// 照伺服器的規則記下（未成年鎖住），換 token 成功就更新 session；也能模擬連不上、
/// 換 token 失敗。
class _FakeAgeGateRepository extends AgeGateRepository {
  _FakeAgeGateRepository(this.session) : super(currentUserId: () => 'u1');

  final _Session session;
  bool fail = false;
  bool refreshFails = false;
  final requests = <AgeGateResult>[];

  @override
  Future<AgeGateRecordOutcome> record(AgeGateResult result) async {
    requests.add(result);
    if (fail) throw const AgeGateRecordException('offline');
    final recorded =
        AgeGateService.resultFor(session.user) == AgeGateResult.minor
            ? AgeGateResult.minor
            : result;
    if (!refreshFails) {
      session.user = _user({
        'age_gate': {'result': recorded.name, 'policy': 1, 'at': _at},
      });
    }
    return (result: recorded, sessionUpdated: !refreshFails);
  }
}

void main() {
  Future<_FakeAgeGateRepository> pumpApp(
    WidgetTester tester, {
    Map<String, dynamic> appMetadata = const {},
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = _Session(appMetadata);
    final repository = _FakeAgeGateRepository(session);
    final router = GoRouter(
      initialLocation: '/',
      redirect: (context, state) => resolveAppRedirect(
        isLoggedIn: true,
        isOnboardingCompleted: true,
        isPasswordRecovery: false,
        isAdultConfirmed: AgeGateService.isAdultConfirmed(session.user),
        matchedLocation: state.matchedLocation,
      ),
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('main-shell')),
        ),
        GoRoute(
          path: '/age-gate',
          builder: (_, __) => AgeGateScreen(
            blocked:
                AgeGateService.resultFor(session.user) == AgeGateResult.minor,
            now: () => DateTime(2026, 10, 30),
          ),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, __) => const Scaffold(body: Text('settings-screen')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [ageGateRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  Future<void> pick(WidgetTester tester, String field, String item) async {
    await tester.tap(find.byKey(ValueKey('age-gate-$field')));
    await tester.pumpAndSettle();
    // 選單是長清單、往下才建出來：捲到看得到再點（還沒選過，只有選單裡有這個字）。
    final option = find.text(item);
    await tester.scrollUntilVisible(
      option,
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(option);
    await tester.pumpAndSettle();
  }

  bool submitEnabled(WidgetTester tester) =>
      tester
          .widget<ElevatedButton>(find.descendant(
            of: find.byKey(const ValueKey('age-gate-submit')),
            matching: find.byType(ElevatedButton),
          ))
          .onPressed !=
      null;

  Future<void> submitAndConfirm(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('age-gate-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('age-gate-confirm-submit')));
    await tester.pumpAndSettle();
  }

  testWidgets('沒有紀錄：導到年齡確認頁；年、月都沒預選，不寫門檻數字，選完才能按', (tester) async {
    await pumpApp(tester);

    expect(find.text('請選擇你的出生年月'), findsOneWidget);
    expect(find.text('只用來確認你是否已成年，不會保存你的生日。'), findsOneWidget);
    expect(find.text('年'), findsOneWidget);
    expect(find.text('月'), findsOneWidget);
    expect(find.textContaining('18'), findsNothing);
    expect(submitEnabled(tester), isFalse);

    await pick(tester, 'year', '1990 年');
    expect(submitEnabled(tester), isFalse, reason: '還沒選月');
    await pick(tester, 'month', '5 月');
    expect(submitEnabled(tester), isTrue);
  });

  testWidgets('出生年月還沒到：提示重選，不能送出', (tester) async {
    await pumpApp(tester);

    await pick(tester, 'year', '2026 年');
    await pick(tester, 'month', '11 月');

    expect(find.byKey(const ValueKey('age-gate-future')), findsOneWidget);
    expect(submitEnabled(tester), isFalse);
  });

  testWidgets('成年：確認窗講選了什麼、送出後不能自己改；返回修改不送，確定才送，送完回首頁', (tester) async {
    final repository = await pumpApp(tester);
    await pick(tester, 'year', '2008 年');
    await pick(tester, 'month', '10 月');

    await tester.tap(find.byKey(const ValueKey('age-gate-submit')));
    await tester.pumpAndSettle();
    expect(find.text('你選的是 2008 年 10 月。送出後不能自己修改，確定嗎？'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('age-gate-confirm-back')));
    await tester.pumpAndSettle();
    expect(repository.requests, isEmpty);

    await submitAndConfirm(tester);
    expect(repository.requests, [AgeGateResult.adult]);
    expect(find.text('main-shell'), findsOneWidget);
  });

  testWidgets('未成年：鎖住，只提供給成年人、填錯聯絡客服；設定頁（登出、刪除帳號）開著', (tester) async {
    final repository = await pumpApp(tester);
    await pick(tester, 'year', '2008 年');
    await pick(tester, 'month', '11 月');

    await submitAndConfirm(tester);

    expect(repository.requests, [AgeGateResult.minor]);
    expect(find.byKey(const ValueKey('age-gate-blocked')), findsOneWidget);
    expect(find.text(kAgeGateBlockedTitle), findsOneWidget);
    expect(find.text('vibesyncaiapp@gmail.com'), findsOneWidget);
    expect(find.text('main-shell'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('age-gate-blocked-settings')));
    await tester.pumpAndSettle();
    expect(find.text('settings-screen'), findsOneWidget);
  });

  testWidgets('帳號已經記成未成年：直接是鎖住的畫面，不能重填', (tester) async {
    await pumpApp(tester, appMetadata: const {
      'age_gate': {'result': 'minor', 'policy': 1, 'at': _at},
    });

    expect(find.byKey(const ValueKey('age-gate-blocked')), findsOneWidget);
    expect(find.byKey(const ValueKey('age-gate-year')), findsNothing);
    expect(find.byKey(const ValueKey('age-gate-submit')), findsNothing);
  });

  testWidgets('帳號已經確認成年：不會看到年齡確認頁', (tester) async {
    await pumpApp(tester, appMetadata: const {
      'age_gate': {'result': 'adult', 'policy': 1, 'at': _at},
    });

    expect(find.text('main-shell'), findsOneWidget);
    expect(find.text('請選擇你的出生年月'), findsNothing);
  });

  testWidgets('連不上：請他再按一次，不放行；再按一次成功就回首頁', (tester) async {
    final repository = await pumpApp(tester);
    repository.fail = true;
    await pick(tester, 'year', '1990 年');
    await pick(tester, 'month', '5 月');

    await submitAndConfirm(tester);
    expect(find.text(kAgeGateRecordFailedMessage), findsOneWidget);
    expect(find.text('main-shell'), findsNothing);

    repository.fail = false;
    await submitAndConfirm(tester);
    expect(repository.requests, [AgeGateResult.adult, AgeGateResult.adult]);
    expect(find.text('main-shell'), findsOneWidget);
  });

  testWidgets('成年寫入成功但換 token 失敗：不放行、請再按一次；再按一次換成功就回首頁', (tester) async {
    final repository = await pumpApp(tester);
    repository.refreshFails = true;
    await pick(tester, 'year', '1990 年');
    await pick(tester, 'month', '5 月');

    await submitAndConfirm(tester);
    expect(find.text(kAgeGateRecordFailedMessage), findsOneWidget);
    expect(find.text('main-shell'), findsNothing);

    repository.refreshFails = false;
    await submitAndConfirm(tester);
    expect(repository.requests, [AgeGateResult.adult, AgeGateResult.adult]);
    expect(find.text('main-shell'), findsOneWidget);
  });

  testWidgets('不想填或登錯帳號：「登出或刪除帳號」進得了設定頁', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const ValueKey('age-gate-settings')));
    await tester.pumpAndSettle();

    expect(find.text('settings-screen'), findsOneWidget);
  });
}
