import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/services/app_haptics.dart';
import '../../../../shared/widgets/brand/brand_dialog.dart';
import '../../domain/errors/analysis_exceptions.dart';

/// App Store 上的 VibeSync 頁面。正式版的提示不提 TestFlight（送審前盤點 2026-10-30）。
const appStoreUpdateUrl = 'https://apps.apple.com/tw/app/vibesync/id6760161877';

/// 開商店頁的動作。測試換成假的，不真的開 App Store。
typedef AppStoreLauncher = Future<bool> Function(Uri uri);

Future<bool> launchAppStore(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

final appStoreLauncherProvider = Provider<AppStoreLauncher>(
  (ref) => launchAppStore,
);

/// 開不了商店就算了：畫面上的說明文字已經告訴使用者去哪裡更新。
Future<bool> openAppStoreForUpdate(AppStoreLauncher launchStore) async {
  try {
    return await launchStore(Uri.parse(appStoreUpdateUrl));
  } catch (_) {
    return false;
  }
}

/// 最低 App 版本閘門擋下對話分析時的更新提示（Eric 2026-10-18）。只有「前往
/// 更新」與「關閉」，沒有重試：舊版本重送只會再被擋一次。
Future<void> showAppUpdateRequiredDialog(
  BuildContext context, {
  required AppStoreLauncher launchStore,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AppUpdateRequiredDialog(launchStore: launchStore),
  );
}

class AppUpdateRequiredDialog extends StatelessWidget {
  const AppUpdateRequiredDialog({super.key, required this.launchStore});

  final AppStoreLauncher launchStore;

  @override
  Widget build(BuildContext context) {
    return BrandAlertDialog(
      title: const Text('請更新 VibeSync'),
      content: const Text(AppUpdateRequiredException.userMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('關閉'),
        ),
        ElevatedButton(
          onPressed: AppHaptics.onPress(() {
            Navigator.of(context).pop();
            unawaited(openAppStoreForUpdate(launchStore));
          }),
          child: const Text('前往更新'),
        ),
      ],
    );
  }
}
