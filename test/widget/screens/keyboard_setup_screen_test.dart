import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vibesync/core/services/keyboard_privacy_purge_service.dart';
import 'package:vibesync/features/keyboard/data/providers/keyboard_context_sync_provider.dart';
import 'package:vibesync/features/keyboard/data/services/keyboard_context_bridge.dart';
import 'package:vibesync/features/keyboard/data/services/keyboard_screenshot_setup_coordinator.dart';
import 'package:vibesync/features/keyboard/domain/entities/keyboard_context_snapshot.dart';
import 'package:vibesync/features/keyboard/presentation/screens/keyboard_setup_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/features/onboarding/data/onboarding_service.dart';
import 'package:vibesync/shared/widgets/ai_data_sharing_consent.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await OnboardingService.load();
  });

  tearDown(() {
    AiDataSharingConsent.debugUserIdOverride = null;
  });

  testWidgets('teaches settings permission before globe and quick reply',
      (tester) async {
    var settingsOpened = 0;
    final router = GoRouter(
      initialLocation: '/keyboard',
      routes: [
        GoRoute(
          path: '/keyboard',
          builder: (_, __) => KeyboardSetupScreen(
            openSettings: () async {
              settingsOpened++;
              return true;
            },
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    expect(find.text('聊天不用再跳出 App'), findsOneWidget);
    expect(find.text('🔄 延展'), findsOneWidget);

    await tester.tap(find.text('下一步'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('先啟用 VibeSync 鍵盤'), findsOneWidget);
    // 隱私說明改成點擊才展開（2026-08-06），不再常駐佔版面。
    expect(find.textContaining('只送出你按下「載入」的文字'), findsNothing);
    final privacyInfoButton = find.text('資料使用說明');
    await tester.ensureVisible(privacyInfoButton);
    await tester.pump();
    await tester.tap(privacyInfoButton);
    await tester.pump();
    expect(find.textContaining('只送出你按下「載入」的文字'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pump();

    // 圖文路徑導引（2026-08-03）：文字路徑「設定 > VibeSync > 鍵盤」使用者
    // 實測會迷路，補一段圖文導引標出完整巢狀路徑跟最終畫面長怎樣。
    expect(find.text('一般'), findsOneWidget);
    expect(find.text('鍵盤（Keyboards）'), findsOneWidget);
    // AppBar 標題也是「VibeSync AI 鍵盤」，路徑麵包屑那顆是第二個。
    expect(find.text('VibeSync AI 鍵盤'), findsNWidgets(2));
    expect(find.text('允許完整取用'), findsOneWidget);

    final openSettingsButton = find.text('前往 iPhone 設定');
    await tester.ensureVisible(openSettingsButton);
    await tester.pump();
    await tester.tap(openSettingsButton);
    await tester.pump();
    expect(settingsOpened, 1);

    await tester.tap(find.text('我已完成設定'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('長按地球，切換鍵盤'), findsOneWidget);

    await tester.tap(find.text('下一步'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('三步就有好回覆'), findsOneWidget);
    expect(find.text('選風格，確認後送出'), findsOneWidget);
  });

  testWidgets(
    'cold restart after opening Settings resumes past the Full Access page '
    'instead of resetting to page 1',
    (tester) async {
      // 去 iPhone 設定常把整個 app 記憶體回收掉，process 重開時 initState
      // 重跑、_page/_openedSettings 這些純記憶體狀態全部歸零——2026-08-06
      // 真機影片重現。SharedPreferences mock 在同一個 test 內是靜態記憶體，
      // 跨 pumpWidget 仍保留，正好模擬「持久旗標活過 process 重啟」。
      final router = GoRouter(
        initialLocation: '/keyboard',
        routes: [
          GoRoute(
            path: '/keyboard',
            builder: (_, __) => KeyboardSetupScreen(
              openSettings: () async => true,
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );

      await tester.tap(find.text('下一步'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('先啟用 VibeSync 鍵盤'), findsOneWidget);

      final openSettingsButton = find.text('前往 iPhone 設定');
      await tester.ensureVisible(openSettingsButton);
      await tester.pump();
      await tester.tap(openSettingsButton);
      await tester.pump();

      // 模擬 process 被系統整個回收：不是切回背景再 resume，而是重新蓋一棵
      // 全新的 widget tree，舊 state 徹底作廢，只有 SharedPreferences 存活。
      final freshRouter = GoRouter(
        initialLocation: '/keyboard',
        routes: [
          GoRoute(
            path: '/keyboard',
            builder: (_, __) => KeyboardSetupScreen(
              openSettings: () async => true,
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: freshRouter)),
      );
      // 讓 SharedPreferences 讀取＋post-frame callback＋PageView jump 這串
      // async chain 走完；pulse 動畫無限循環，不能用 pumpAndSettle。
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('聊天不用再跳出 App'), findsNothing);
      expect(find.text('先啟用 VibeSync 鍵盤'), findsNothing);
      expect(find.text('長按地球，切換鍵盤'), findsOneWidget);
    },
  );

  testWidgets('first-run setup can be postponed and is persisted',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const SizedBox.shrink()),
        GoRoute(
          path: '/keyboard',
          builder: (_, __) => const KeyboardSetupScreen(firstRun: true),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    router.push('/keyboard');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('稍後設定'), findsOneWidget);
    await tester.tap(find.text('稍後設定'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(OnboardingService.isKeyboardCompletedSync, isTrue);
  });

  testWidgets('non-first-run walkthrough also marks keyboard completed',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const SizedBox.shrink()),
        GoRoute(
          path: '/keyboard',
          builder: (_, __) => KeyboardSetupScreen(
            openSettings: () async => true,
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    router.push('/keyboard');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(OnboardingService.isKeyboardCompletedSync, isFalse);
    // 非 firstRun 沒有「稍後設定」。
    expect(find.text('稍後設定'), findsNothing);

    // 走完四頁按「完成」——起步清單入口（非 firstRun）也必須寫旗標（勾勾 bug 回歸鎖）。
    await tester.tap(find.text('下一步'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('我已完成設定'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('下一步'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('完成'));
    // pop 轉場收完、setup screen dispose 後 pulse 動畫停止，可安全 settle。
    await tester.pumpAndSettle();

    expect(OnboardingService.isKeyboardCompletedSync, isTrue);
    // 非 firstRun 完成後 pop 回前一頁。
    expect(find.text('三步就有好回覆'), findsNothing);
  });

  testWidgets('revoking screenshot consent purges native keyboard context',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      '${AiDataSharingConsent.keyboardScreenshotConsentKey}::owner-1': true,
      '${AiDataSharingConsent.keyboardScreenshotConsentAcceptedAtKey}::owner-1':
          DateTime.utc(2026, 7, 27).toIso8601String(),
    });
    AiDataSharingConsent.debugUserIdOverride = () => 'owner-1';
    expect(await AiDataSharingConsent.hasKeyboardScreenshotConsent(), isTrue);
    final bridge = _RecordingKeyboardContextBridge();
    final router = GoRouter(
      initialLocation: '/keyboard',
      routes: [
        GoRoute(
          path: '/keyboard',
          builder: (_, __) => const KeyboardSetupScreen(),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyboardContextBridgeProvider.overrideWithValue(bridge),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    for (var step = 0; step < 3; step++) {
      final label = step == 1 ? '我已完成設定' : '下一步';
      await tester.tap(find.text(label));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('三步就有好回覆'), findsOneWidget);
    expect(find.text('撤回截圖 AI 同意並清除鍵盤脈絡'), findsOneWidget);

    await tester.ensureVisible(find.text('撤回截圖 AI 同意並清除鍵盤脈絡'));
    await tester.pump();
    await tester.tap(find.text('撤回截圖 AI 同意並清除鍵盤脈絡'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(bridge.purgeScopes, [KeyboardContextPurgeScope.consentRevoked]);
    expect(await AiDataSharingConsent.hasKeyboardScreenshotConsent(), isFalse);
  });

  testWidgets(
      'relaunch retries persisted native cleanup and keeps retry action visible',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      KeyboardScreenshotPrivacyKeys.nativeCleanupPendingScope:
          KeyboardContextPurgeScope.accountDeletion.wireName,
    });
    AiDataSharingConsent.debugUserIdOverride = () => 'owner-1';
    final channel = _RecordingPrivacyPurgeChannel(
      error: StateError('native channel unavailable'),
    );
    final service = KeyboardPrivacyPurgeService(channel: channel);
    final router = GoRouter(
      initialLocation: '/keyboard',
      routes: [
        GoRoute(
          path: '/keyboard',
          builder: (_, __) => const KeyboardSetupScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyboardPrivacyPurgeServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(channel.scopes, [KeyboardContextPurgeScope.accountDeletion]);

    for (var page = 0; page < 3; page++) {
      await tester.drag(
        find.byType(PageView),
        const Offset(-500, 0),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    expect(
      find.byKey(const Key('revoke_keyboard_screenshot_consent')),
      findsOneWidget,
    );
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(
        KeyboardScreenshotPrivacyKeys.nativeCleanupPendingScope,
      ),
      KeyboardContextPurgeScope.accountDeletion.wireName,
    );
  });

  testWidgets(
      'latest screenshot CTA obtains disclosure consent before native setup',
      (tester) async {
    AiDataSharingConsent.debugUserIdOverride = () => 'owner-1';
    final setup = _RecordingScreenshotSetup(
      KeyboardScreenshotSetupResult.enabled,
    );
    final router = GoRouter(
      initialLocation: '/keyboard',
      routes: [
        GoRoute(
          path: '/keyboard',
          builder: (_, __) => const KeyboardSetupScreen(),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyboardScreenshotSetupCoordinatorProvider.overrideWithValue(setup),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();

    for (var step = 0; step < 3; step++) {
      final label = step == 1 ? '我已完成設定' : '下一步';
      await tester.tap(find.text(label));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
    final enableButton =
        find.byKey(const Key('enable_latest_screenshot_detection'));
    await tester.ensureVisible(enableButton);
    await tester.pump();
    await tester.tap(enableButton);
    await tester.pump();

    expect(find.text('第三方 AI 資料使用同意'), findsOneWidget);
    expect(find.textContaining('不會自動讀取其他聊天紀錄'), findsOneWidget);
    expect(setup.calls, 0);

    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.ensureVisible(find.text('我同意並送出'));
    await tester.tap(find.text('我同意並送出'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(setup.calls, 1);
    expect(find.text('「最近截圖」輔助已啟用'), findsOneWidget);
    expect(
      find.textContaining('自動使用最近 3 分鐘的截圖'),
      findsOneWidget,
    );
    expect(
      find.textContaining('顯示用了哪一張'),
      findsOneWidget,
      reason: 'Dropping the per-upload tap must not drop the visibility of '
          'which capture was used.',
    );
  });

  testWidgets('denied Photos permission leaves screenshot setup disabled',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      '${AiDataSharingConsent.keyboardScreenshotConsentKey}::owner-1': true,
      '${AiDataSharingConsent.keyboardScreenshotConsentAcceptedAtKey}::owner-1':
          DateTime.utc(2026, 7, 27).toIso8601String(),
    });
    AiDataSharingConsent.debugUserIdOverride = () => 'owner-1';
    final setup = _RecordingScreenshotSetup(
      KeyboardScreenshotSetupResult.photoDenied,
    );
    final router = GoRouter(
      initialLocation: '/keyboard',
      routes: [
        GoRoute(
          path: '/keyboard',
          builder: (_, __) => const KeyboardSetupScreen(),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyboardScreenshotSetupCoordinatorProvider.overrideWithValue(setup),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();

    for (var step = 0; step < 3; step++) {
      final label = step == 1 ? '我已完成設定' : '下一步';
      await tester.tap(find.text(label));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
    final enableButton =
        find.byKey(const Key('enable_latest_screenshot_detection'));
    await tester.ensureVisible(enableButton);
    await tester.tap(enableButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(setup.calls, 1);
    expect(find.textContaining('相片權限已拒絕'), findsOneWidget);
    expect(enableButton, findsOneWidget);
    expect(
      await AiDataSharingConsent.hasKeyboardLatestScreenshotDetectionEnabled(),
      isFalse,
    );
  });

  testWidgets('account change re-reads owner-bound consent instead of true',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      '${AiDataSharingConsent.keyboardScreenshotConsentKey}::owner-1': true,
      '${AiDataSharingConsent.keyboardScreenshotConsentAcceptedAtKey}::owner-1':
          DateTime.utc(2026, 7, 27).toIso8601String(),
    });
    var owner = 'owner-1';
    AiDataSharingConsent.debugUserIdOverride = () => owner;
    final setup = _RecordingScreenshotSetup(
      KeyboardScreenshotSetupResult.accountChanged,
      onEnable: () => owner = 'owner-2',
    );
    final router = GoRouter(
      initialLocation: '/keyboard',
      routes: [
        GoRoute(
          path: '/keyboard',
          builder: (_, __) => const KeyboardSetupScreen(),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyboardScreenshotSetupCoordinatorProvider.overrideWithValue(setup),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();

    for (var step = 0; step < 3; step++) {
      final label = step == 1 ? '我已完成設定' : '下一步';
      await tester.tap(find.text(label));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
    final enableButton =
        find.byKey(const Key('enable_latest_screenshot_detection'));
    await tester.ensureVisible(enableButton);
    await tester.tap(enableButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(setup.calls, 1);
    expect(find.textContaining('登入帳號在設定途中變更'), findsOneWidget);
    expect(
      find.byKey(const Key('revoke_keyboard_screenshot_consent')),
      findsNothing,
    );
    expect(enableButton, findsOneWidget);
  });
}

class _RecordingKeyboardContextBridge implements KeyboardContextBridge {
  final purgeScopes = <KeyboardContextPurgeScope>[];

  @override
  Future<KeyboardContextPublishResult> publish(
    KeyboardContextSnapshot snapshot,
  ) async {
    return KeyboardContextPublishResult(storedRevision: snapshot.revision);
  }

  @override
  Future<void> purge(KeyboardContextPurgeScope scope) async {
    purgeScopes.add(scope);
  }
}

class _RecordingPrivacyPurgeChannel implements KeyboardPrivacyPurgeChannel {
  _RecordingPrivacyPurgeChannel({this.error});

  final Object? error;
  final scopes = <KeyboardContextPurgeScope>[];

  @override
  Future<void> invokePurge(KeyboardContextPurgeScope scope) async {
    scopes.add(scope);
    final invocationError = error;
    if (invocationError != null) throw invocationError;
  }
}

class _RecordingScreenshotSetup implements KeyboardScreenshotSetupEnabling {
  _RecordingScreenshotSetup(
    this.result, {
    this.onEnable,
  });

  final KeyboardScreenshotSetupResult result;
  final void Function()? onEnable;
  int calls = 0;

  @override
  Future<KeyboardScreenshotSetupResult> enableAfterConsent() async {
    calls++;
    onEnable?.call();
    return result;
  }

  @override
  Future<bool> hasEnabledSetup() async =>
      calls > 0 && result == KeyboardScreenshotSetupResult.enabled;
}
