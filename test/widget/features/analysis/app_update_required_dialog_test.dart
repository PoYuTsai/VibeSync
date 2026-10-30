// 最低 App 版本閘門的更新視窗（Eric 2026-10-18）：只有「前往更新」與「關閉」，
// 點外面關不掉、沒有重試；前往更新經由可注入的 launcher 開 App Store 頁。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/presentation/widgets/app_update_required_dialog.dart';

const _gateMessage = '這個版本已經停止支援，請到 App Store 更新到最新版。';

Future<List<Uri>> _pumpAndOpen(
  WidgetTester tester, {
  AppStoreLauncher? launchStore,
}) async {
  final launched = <Uri>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showAppUpdateRequiredDialog(
                context,
                launchStore: launchStore ??
                    (uri) async {
                      launched.add(uri);
                      return true;
                    },
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return launched;
}

void main() {
  testWidgets('標題、說明照定稿；沒有重試，點外面關不掉', (tester) async {
    await _pumpAndOpen(tester);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('請更新 VibeSync'), findsOneWidget);
    expect(find.text(_gateMessage), findsOneWidget);
    expect(find.text('前往更新'), findsOneWidget);
    expect(find.text('關閉'), findsOneWidget);
    expect(find.textContaining('重試'), findsNothing);
    expect(find.textContaining('重新分析'), findsNothing);

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('前往更新：用 launcher 開 App Store 頁並關掉視窗', (tester) async {
    final launched = await _pumpAndOpen(tester);

    await tester.tap(find.text('前往更新'));
    await tester.pumpAndSettle();

    expect(launched, [Uri.parse(appStoreUpdateUrl)]);
    expect(
      appStoreUpdateUrl,
      'https://apps.apple.com/tw/app/vibesync/id6760161877',
    );
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('關閉：只關視窗，不開商店', (tester) async {
    final launched = await _pumpAndOpen(tester);

    await tester.tap(find.text('關閉'));
    await tester.pumpAndSettle();

    expect(launched, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('商店開不了也不丟例外', (tester) async {
    await _pumpAndOpen(
      tester,
      launchStore: (_) async => throw StateError('no handler'),
    );

    await tester.tap(find.text('前往更新'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      await openAppStoreForUpdate((_) async => throw StateError('no handler')),
      isFalse,
    );
  });
}
