import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive_ce.dart' show Box;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:vibesync/features/practice_chat/data/providers/practice_chat_providers.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_session_repository.dart';
import 'package:vibesync/features/practice_chat/data/services/practice_chat_api_service.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_session.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/presentation/screens/settings_screen.dart';
import 'package:vibesync/features/subscription/presentation/subscription_diagnostics_gate.dart';

class _UnusedPracticeSessionBox extends Fake implements Box<PracticeSession> {}

class _MemoryPracticeSessionRepository extends PracticeSessionRepository {
  _MemoryPracticeSessionRepository() : super(_UnusedPracticeSessionBox());

  @override
  List<PracticeSession> recentSessions() => const [];
}

class _NoopPracticeChatApi extends PracticeChatApiService {}

class _DisposablePracticeChatController extends PracticeChatController {
  _DisposablePracticeChatController({
    required this.onDispose,
    required super.api,
    required super.repository,
    required super.sessionId,
    required super.createdAt,
  });

  final VoidCallback onDispose;

  @override
  void dispose() {
    onDispose();
    super.dispose();
  }
}

class _FakeAccountDeletionActions extends AccountDeletionActions {
  _FakeAccountDeletionActions({
    this.deleteError,
    this.clearLocalStorageError,
    this.clearLocalSessionError,
    this.onClearLocalSessionAfterDeletion,
  });

  final Object? deleteError;
  final Object? clearLocalStorageError;
  final Object? clearLocalSessionError;
  final Future<void> Function()? onClearLocalSessionAfterDeletion;
  final confirmations = <String>[];
  var clearLocalStorageCalls = 0;
  var clearLocalSessionCalls = 0;

  @override
  Future<void> deleteAccount({required String confirmation}) async {
    confirmations.add(confirmation);
    final error = deleteError;
    if (error != null) throw error;
  }

  @override
  Future<void> clearLocalStorage() async {
    clearLocalStorageCalls++;
    final error = clearLocalStorageError;
    if (error != null) throw error;
  }

  @override
  Future<void> clearLocalSessionAfterDeletion() async {
    clearLocalSessionCalls++;
    final error = clearLocalSessionError;
    if (error != null) throw error;
    await onClearLocalSessionAfterDeletion?.call();
  }
}

class _FakeAccountLogoutActions extends AccountLogoutActions {
  _FakeAccountLogoutActions({
    this.signOutError,
    this.clearUsageSnapshotError,
    this.authenticated = false,
  });

  final Object? signOutError;
  final Object? clearUsageSnapshotError;
  bool authenticated;
  var signOutCalls = 0;
  var clearUsageSnapshotCalls = 0;
  var clearPracticeRoomStateCalls = 0;

  @override
  bool get isAuthenticated => authenticated;

  @override
  Future<void> signOut() async {
    signOutCalls++;
    final error = signOutError;
    if (error != null) throw error;
    authenticated = false;
  }

  @override
  Future<void> clearUsageSnapshot() async {
    clearUsageSnapshotCalls++;
    final error = clearUsageSnapshotError;
    if (error != null) throw error;
  }

  @override
  Future<void> clearPracticeRoomState() async {
    clearPracticeRoomStateCalls++;
  }
}

void main() {
  late GoRouter testRouter;
  late AccountDeletionActions accountDeletionActions;
  late AccountLogoutActions accountLogoutActions;
  Widget? settingsOverlay;

  setUp(() {
    accountDeletionActions = const DefaultAccountDeletionActions();
    accountLogoutActions = const DefaultAccountLogoutActions();
    settingsOverlay = null;
    PackageInfo.setMockInitialValues(
      appName: 'VibeSync',
      packageName: 'com.poyutsai.vibesync',
      version: '1.0.0',
      buildNumber: '165',
      buildSignature: '',
    );

    testRouter = GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(
          path: '/settings',
          builder: (context, state) {
            final screen = SettingsScreen(
              accountDeletionActions: accountDeletionActions,
              accountLogoutActions: accountLogoutActions,
            );
            final overlay = settingsOverlay;
            if (overlay == null) return screen;
            return Stack(children: [screen, overlay]);
          },
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => const Scaffold(
            body: Center(child: Text('Login')),
          ),
        ),
        GoRoute(
          path: '/paywall',
          builder: (context, state) => const Scaffold(
            body: Center(child: Text('Paywall')),
          ),
        ),
      ],
    );
  });

  Future<void> pumpSettings(
    WidgetTester tester, {
    Future<void> Function()? refreshUsage,
    AccountDeletionActions? deletionActions,
    AccountLogoutActions? logoutActions,
    List<Override> extraOverrides = const [],
    Widget? overlay,
  }) async {
    if (deletionActions != null) {
      accountDeletionActions = deletionActions;
    }
    if (logoutActions != null) {
      accountLogoutActions = logoutActions;
    }
    settingsOverlay = overlay;

    await tester.binding.setSurfaceSize(const Size(430, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          subscriptionScreenRefreshProvider.overrideWithValue(
            refreshUsage ?? () async {},
          ),
          ...extraOverrides,
        ],
        child: MaterialApp.router(routerConfig: testRouter),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('formatSettingsRenewalDate', () {
    test('shows time instead of a bare date when renewal is today', () {
      final now = DateTime(2026, 6, 7, 12, 43);
      final renewsAt = DateTime(2026, 6, 7, 14, 5);

      expect(
        formatSettingsRenewalDate(renewsAt, now: now),
        '今天 14:05',
      );
    });

    test('shows date for future renewal days', () {
      final now = DateTime(2026, 6, 7, 12, 43);
      final renewsAt = DateTime(2026, 6, 8, 14, 5);

      expect(
        formatSettingsRenewalDate(renewsAt, now: now),
        '2026/6/8',
      );
    });
  });

  group('SettingsScreen', () {
    testWidgets('refreshes subscription usage snapshot on entry',
        (tester) async {
      var refreshCalls = 0;
      await pumpSettings(tester, refreshUsage: () async {
        refreshCalls++;
      });

      expect(refreshCalls, 1);
    });

    testWidgets('shows settings title and quota summary', (tester) async {
      await pumpSettings(tester);

      expect(find.text('設定'), findsOneWidget);
      expect(find.text('目前方案與額度'), findsOneWidget);
      expect(find.text('目前方案：Free'), findsOneWidget);
      expect(find.text('本月剩餘'), findsNWidgets(2));
      expect(find.text('今日剩餘'), findsNWidgets(2));
      expect(find.text('30/30'), findsNWidgets(2));
      expect(find.text('15/15'), findsNWidgets(2));
    });

    testWidgets('shows clear plan and account rows', (tester) async {
      await pumpSettings(tester);

      expect(find.text('方案與帳號'), findsOneWidget);
      expect(find.text('目前方案'), findsOneWidget);
      expect(find.text('本月已使用'), findsOneWidget);
      expect(find.text('0/30'), findsOneWidget);
      expect(find.text('帳號'), findsOneWidget);
      expect(find.text('尚未登入'), findsOneWidget);
      expect(find.text('管理訂閱'), findsOneWidget);
      expect(find.text('恢復購買'), findsOneWidget);
    });

    testWidgets('diagnostics row hidden when gate is off (release build)',
        (tester) async {
      SubscriptionDiagnosticsGate.debugVisibleOverride = false;
      addTearDown(() {
        SubscriptionDiagnosticsGate.debugVisibleOverride = null;
      });

      await pumpSettings(tester);

      expect(find.text('複製訂閱診斷'), findsNothing);
    });

    testWidgets('diagnostics row visible when gate is on (debug build)',
        (tester) async {
      SubscriptionDiagnosticsGate.debugVisibleOverride = true;
      addTearDown(() {
        SubscriptionDiagnosticsGate.debugVisibleOverride = null;
      });

      await pumpSettings(tester);

      expect(find.text('複製訂閱診斷'), findsOneWidget);
    });

    testWidgets('shows privacy and support rows with launch copy',
        (tester) async {
      await pumpSettings(tester);

      expect(find.text('隱私與資料'), findsOneWidget);
      expect(find.text('刪除帳號'), findsOneWidget);
      expect(find.text('隱私政策'), findsOneWidget);
      expect(find.text('其他'), findsOneWidget);
      expect(find.text('App 版本'), findsOneWidget);
      expect(find.text('1.0.0 (165)'), findsOneWidget);
      expect(find.text('服務條款'), findsOneWidget);
      expect(find.text('客服與支援'), findsOneWidget);
      expect(find.text('登出'), findsOneWidget);
    });

    testWidgets('opens paywall when tapping current plan row', (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.text('目前方案'));
      await tester.pumpAndSettle();

      expect(find.text('Paywall'), findsOneWidget);
    });

    testWidgets('logout success clears practice room state before login',
        (tester) async {
      final actions = _FakeAccountLogoutActions(authenticated: true);

      await pumpSettings(tester, logoutActions: actions);

      await tester.ensureVisible(find.byIcon(Icons.logout));
      await tester.tap(find.byIcon(Icons.logout));
      await tester.pump();
      await tester.tap(find.byType(TextButton).last);
      await tester.pumpAndSettle();

      expect(actions.signOutCalls, 1);
      expect(actions.clearUsageSnapshotCalls, 1);
      expect(actions.clearPracticeRoomStateCalls, 1);
      expect(find.text('Login'), findsOneWidget);
    });

    testWidgets('logout failure while still authenticated keeps practice state',
        (tester) async {
      final actions = _FakeAccountLogoutActions(
        signOutError: Exception('network down'),
        authenticated: true,
      );

      await pumpSettings(tester, logoutActions: actions);

      await tester.ensureVisible(find.byIcon(Icons.logout));
      await tester.tap(find.byIcon(Icons.logout));
      await tester.pump();
      await tester.tap(find.byType(TextButton).last);
      await tester.pumpAndSettle();

      expect(actions.signOutCalls, 1);
      expect(actions.clearUsageSnapshotCalls, 0);
      expect(actions.clearPracticeRoomStateCalls, 0);
      expect(find.text('Login'), findsNothing);
    });

    testWidgets('logout auth-gone fallback still clears practice state',
        (tester) async {
      final actions = _FakeAccountLogoutActions(
        signOutError: Exception('cleanup failed after auth signout'),
        authenticated: false,
      );

      await pumpSettings(tester, logoutActions: actions);

      await tester.ensureVisible(find.byIcon(Icons.logout));
      await tester.tap(find.byIcon(Icons.logout));
      await tester.pump();
      await tester.tap(find.byType(TextButton).last);
      await tester.pumpAndSettle();

      expect(actions.signOutCalls, 1);
      expect(actions.clearUsageSnapshotCalls, 1);
      expect(actions.clearPracticeRoomStateCalls, 1);
      expect(find.text('Login'), findsOneWidget);
    });

    testWidgets(
        'logout auth-gone fallback runs practice cleanup if usage fails',
        (tester) async {
      final actions = _FakeAccountLogoutActions(
        signOutError: Exception('cleanup failed after auth signout'),
        clearUsageSnapshotError: Exception('usage cleanup failed'),
        authenticated: false,
      );

      await pumpSettings(tester, logoutActions: actions);

      await tester.ensureVisible(find.byIcon(Icons.logout));
      await tester.tap(find.byIcon(Icons.logout));
      await tester.pump();
      await tester.tap(find.byType(TextButton).last);
      await tester.pumpAndSettle();

      expect(actions.signOutCalls, 1);
      expect(actions.clearUsageSnapshotCalls, 1);
      expect(actions.clearPracticeRoomStateCalls, 1);
      expect(find.text('Login'), findsOneWidget);
    });

    testWidgets('delete account dialog requires explicit DELETE confirmation',
        (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.text('刪除帳號'));
      await tester.pump();

      expect(find.text('刪除帳號'), findsNWidgets(2));
      expect(find.textContaining('Apple 訂閱管理'), findsOneWidget);
      expect(find.text('輸入 DELETE 以確認'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('刪除'), findsOneWidget);

      final deleteButton =
          tester.widget<TextButton>(find.widgetWithText(TextButton, '刪除'));
      expect(deleteButton.onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pump();

      final enabledDeleteButton =
          tester.widget<TextButton>(find.widgetWithText(TextButton, '刪除'));
      expect(enabledDeleteButton.onPressed, isNotNull);
    });

    testWidgets(
        'delete account success closes progress overlay after auth redirect',
        (tester) async {
      final clearSessionCompleter = Completer<void>();
      final actions = _FakeAccountDeletionActions(
        onClearLocalSessionAfterDeletion: () {
          testRouter.go('/login');
          return clearSessionCompleter.future;
        },
      );

      await pumpSettings(tester, deletionActions: actions);

      await tester.ensureVisible(find.byIcon(Icons.delete_forever));
      await tester.tap(find.byIcon(Icons.delete_forever));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pump();
      await tester.tap(find.byType(TextButton).last);
      await tester.pump();
      await tester.pump();

      expect(actions.confirmations, ['DELETE']);
      expect(actions.clearLocalStorageCalls, 1);
      expect(actions.clearLocalSessionCalls, 1);
      expect(find.text('Login'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      clearSessionCompleter.complete();
      await tester.pumpAndSettle();

      expect(find.text('Login'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('delete account failure keeps local cleanup untouched',
        (tester) async {
      final actions = _FakeAccountDeletionActions(
        deleteError: Exception('remote delete failed'),
      );

      await pumpSettings(tester, deletionActions: actions);

      await tester.ensureVisible(find.byIcon(Icons.delete_forever));
      await tester.tap(find.byIcon(Icons.delete_forever));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pump();
      await tester.tap(find.byType(TextButton).last);
      await tester.pumpAndSettle();

      expect(actions.confirmations, ['DELETE']);
      expect(actions.clearLocalStorageCalls, 0);
      expect(actions.clearLocalSessionCalls, 0);
      expect(find.text('Login'), findsNothing);
    });

    testWidgets(
        'delete account local cleanup failure still finishes deletion '
        'with split copy and best-effort session clear', (tester) async {
      final actions = _FakeAccountDeletionActions(
        clearLocalStorageError: Exception('local clear failed'),
      );

      await pumpSettings(tester, deletionActions: actions);

      await tester.ensureVisible(find.byIcon(Icons.delete_forever));
      await tester.tap(find.byIcon(Icons.delete_forever));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pump();
      await tester.tap(find.byType(TextButton).last);
      await tester.pumpAndSettle();

      expect(actions.confirmations, ['DELETE']);
      expect(actions.clearLocalStorageCalls, 1);
      expect(actions.clearLocalSessionCalls, 1);
      expect(find.text('Login'), findsOneWidget);
      expect(
        find.text('帳號已刪除，但本機清理未完成，請重新開啟 App。'),
        findsOneWidget,
      );
      expect(find.text('帳號已刪除。'), findsNothing);
    });

    testWidgets(
        'delete account session clear failure still finishes deletion '
        'with split copy', (tester) async {
      final actions = _FakeAccountDeletionActions(
        clearLocalSessionError: Exception('session clear failed'),
      );

      await pumpSettings(tester, deletionActions: actions);

      await tester.ensureVisible(find.byIcon(Icons.delete_forever));
      await tester.tap(find.byIcon(Icons.delete_forever));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pump();
      await tester.tap(find.byType(TextButton).last);
      await tester.pumpAndSettle();

      expect(actions.confirmations, ['DELETE']);
      expect(actions.clearLocalStorageCalls, 1);
      expect(actions.clearLocalSessionCalls, 1);
      expect(find.text('Login'), findsOneWidget);
      expect(
        find.text('帳號已刪除，但本機清理未完成，請重新開啟 App。'),
        findsOneWidget,
      );
    });

    testWidgets('delete account invalidates live practice room state',
        (tester) async {
      final actions = _FakeAccountDeletionActions();
      final repo = _MemoryPracticeSessionRepository();
      final api = _NoopPracticeChatApi();
      var createdControllers = 0;
      var disposedControllers = 0;

      PracticeChatController makeController() {
        createdControllers++;
        return _DisposablePracticeChatController(
          onDispose: () => disposedControllers++,
          api: api,
          repository: repo,
          sessionId: 'practice-$createdControllers',
          createdAt: DateTime(2026, 6, 28, 10),
        );
      }

      await pumpSettings(
        tester,
        deletionActions: actions,
        extraOverrides: [
          practiceChatControllerProvider.overrideWith(
            (ref) => makeController(),
          ),
        ],
        overlay: Consumer(
          builder: (context, ref, child) {
            ref.watch(practiceChatControllerProvider);
            return const SizedBox.shrink();
          },
        ),
      );
      expect(createdControllers, 1);

      await tester.ensureVisible(find.byIcon(Icons.delete_forever));
      await tester.tap(find.byIcon(Icons.delete_forever));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pump();
      await tester.tap(find.byType(TextButton).last);
      await tester.pumpAndSettle();

      expect(actions.clearLocalStorageCalls, 1);
      expect(disposedControllers, greaterThanOrEqualTo(1));
      expect(createdControllers, greaterThanOrEqualTo(2));
    });
  });
}
