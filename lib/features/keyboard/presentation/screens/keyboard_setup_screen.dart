import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/services/funnel_tracker.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/ai_data_sharing_consent.dart';
import '../../../onboarding/data/onboarding_service.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../data/providers/keyboard_context_sync_provider.dart';
import '../../data/services/keyboard_screenshot_setup_coordinator.dart';

typedef OpenKeyboardSettings = Future<bool> Function();

class KeyboardSetupScreen extends ConsumerStatefulWidget {
  const KeyboardSetupScreen({
    super.key,
    this.openSettings = _openIOSSettings,
    this.firstRun = false,
  });

  final OpenKeyboardSettings openSettings;
  final bool firstRun;

  static Future<bool> _openIOSSettings() {
    return launchUrl(
      Uri.parse('app-settings:'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  ConsumerState<KeyboardSetupScreen> createState() =>
      _KeyboardSetupScreenState();
}

class _KeyboardSetupScreenState extends ConsumerState<KeyboardSetupScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final _controller = PageController();
  late final AnimationController _pulse;
  late Future<bool> _hasKeyboardScreenshotConsent;
  late Future<bool> _hasLatestScreenshotDetection;
  int _page = 0;
  bool _openedSettings = false;
  bool _revokingScreenshotConsent = false;
  bool _enablingLatestScreenshotDetection = false;
  bool _nativePrivacyCleanupPending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hasKeyboardScreenshotConsent =
        AiDataSharingConsent.hasKeyboardScreenshotConsent();
    _hasLatestScreenshotDetection =
        ref.read(keyboardScreenshotSetupCoordinatorProvider).hasEnabledSetup();
    unawaited(_restoreNativePrivacyCleanupState());
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.94,
      upperBound: 1.04,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulse.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _openedSettings && _page == 1) {
      _controller.animateToPage(
        2,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _openSettings() async {
    final opened = await widget.openSettings();
    if (!mounted) return;
    if (opened) {
      setState(() => _openedSettings = true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('無法開啟設定，請手動前往「設定 > VibeSync > 鍵盤」。')),
      );
    }
  }

  void _next() {
    if (_page == 3) {
      _finishFirstRun();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finishFirstRun() async {
    if (widget.firstRun) {
      // 走完四頁才算 completed；「略過」不打，否則鍵盤採用漏斗失真。
      unawaited(
        ref.read(funnelTrackerProvider).track('keyboard_setup_completed'),
      );
    }
    // 旗標不分入口：起步清單／設定頁（非 firstRun）走完四頁也要寫，
    // 否則清單的鍵盤項永遠亮不了勾。
    await OnboardingService.markKeyboardCompleted();
    if (!mounted) return;
    if (widget.firstRun) {
      context.go('/');
    } else {
      context.pop();
    }
  }

  Future<void> _skipFirstRun() async {
    await OnboardingService.markKeyboardCompleted();
    if (mounted) context.go('/');
  }

  Future<void> _revokeKeyboardScreenshotConsent() async {
    if (_revokingScreenshotConsent) return;
    setState(() => _revokingScreenshotConsent = true);
    try {
      if (_nativePrivacyCleanupPending) {
        await ref
            .read(keyboardPrivacyPurgeServiceProvider)
            .retryPendingNativeCleanup();
      } else {
        await ref
            .read(keyboardScreenshotPrivacyCoordinatorProvider)
            .revokeScreenshotConsent();
      }
      final hasConsent =
          await AiDataSharingConsent.hasKeyboardScreenshotConsent();
      final hasDetection = await ref
          .read(keyboardScreenshotSetupCoordinatorProvider)
          .hasEnabledSetup();
      if (!mounted) return;
      setState(() {
        _hasKeyboardScreenshotConsent = Future<bool>.value(hasConsent);
        _hasLatestScreenshotDetection = Future<bool>.value(hasDetection);
        _revokingScreenshotConsent = false;
        _nativePrivacyCleanupPending = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已撤回截圖 AI 同意並清除鍵盤脈絡。')),
      );
    } catch (error) {
      final service = ref.read(keyboardPrivacyPurgeServiceProvider);
      var hasConsent = true;
      var nativeCleanupPending = true;
      try {
        hasConsent = await AiDataSharingConsent.hasKeyboardScreenshotConsent();
      } catch (_) {
        // Fail closed and keep the cleanup action visible.
      }
      try {
        nativeCleanupPending =
            await service.pendingNativeCleanupScope() != null;
      } catch (_) {
        // An unreadable retry marker must not make the cleanup action vanish.
      }
      if (!mounted) return;
      setState(() {
        _hasKeyboardScreenshotConsent = Future<bool>.value(hasConsent);
        _hasLatestScreenshotDetection = Future<bool>.value(false);
        _revokingScreenshotConsent = false;
        _nativePrivacyCleanupPending = nativeCleanupPending;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('本機同意已撤回；鍵盤資料清除失敗，請再試一次。')),
      );
    }
  }

  Future<void> _restoreNativePrivacyCleanupState() async {
    final service = ref.read(keyboardPrivacyPurgeServiceProvider);
    try {
      final pendingScope = await service.pendingNativeCleanupScope();
      if (pendingScope == null || !mounted) return;
      setState(() {
        _hasKeyboardScreenshotConsent = Future<bool>.value(false);
        _hasLatestScreenshotDetection = Future<bool>.value(false);
        _nativePrivacyCleanupPending = true;
      });

      await service.retryPendingNativeCleanup();
      final hasConsent =
          await AiDataSharingConsent.hasKeyboardScreenshotConsent();
      final hasDetection = await ref
          .read(keyboardScreenshotSetupCoordinatorProvider)
          .hasEnabledSetup();
      if (!mounted) return;
      setState(() {
        _hasKeyboardScreenshotConsent = Future<bool>.value(hasConsent);
        _hasLatestScreenshotDetection = Future<bool>.value(hasDetection);
        _nativePrivacyCleanupPending = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasKeyboardScreenshotConsent = Future<bool>.value(false);
        _hasLatestScreenshotDetection = Future<bool>.value(false);
        _nativePrivacyCleanupPending = true;
      });
    }
  }

  Future<void> _enableLatestScreenshotDetection() async {
    if (_enablingLatestScreenshotDetection) return;
    setState(() => _enablingLatestScreenshotDetection = true);

    final consented = await AiDataSharingConsent.ensure(
      context,
      featureLabel: 'AI 鍵盤截圖回覆',
      consentKey: AiDataSharingConsent.keyboardScreenshotConsentKey,
      dataDescription: AiDataSharingConsent.keyboardScreenshotDataDescription,
      purposeText: AiDataSharingConsent.keyboardScreenshotPurposeText,
    );
    if (!mounted) return;
    if (!consented) {
      setState(() => _enablingLatestScreenshotDetection = false);
      _showScreenshotSetupFeedback(
        '你尚未同意截圖 AI 資料使用，因此「最近截圖」輔助沒有啟用。',
      );
      return;
    }

    KeyboardScreenshotSetupResult result;
    try {
      result = await ref
          .read(keyboardScreenshotSetupCoordinatorProvider)
          .enableAfterConsent();
    } catch (_) {
      result = KeyboardScreenshotSetupResult.nativeSyncFailed;
    }
    if (!mounted) return;

    final setupCoordinator =
        ref.read(keyboardScreenshotSetupCoordinatorProvider);
    final hasConsent =
        await AiDataSharingConsent.hasKeyboardScreenshotConsent();
    final enabled = await setupCoordinator.hasEnabledSetup();
    if (!mounted) return;
    if (result == KeyboardScreenshotSetupResult.enabled && !enabled) {
      result = KeyboardScreenshotSetupResult.accountChanged;
    }
    setState(() {
      _enablingLatestScreenshotDetection = false;
      _hasKeyboardScreenshotConsent = Future<bool>.value(hasConsent);
      _hasLatestScreenshotDetection = Future<bool>.value(enabled);
    });
    _showScreenshotSetupFeedback(_screenshotSetupMessage(result));
  }

  String _screenshotSetupMessage(KeyboardScreenshotSetupResult result) {
    return switch (result) {
      KeyboardScreenshotSetupResult.enabled =>
        '已啟用「最近截圖」輔助。鍵盤開啟時會自動使用最近 3 分鐘的截圖，並在鍵盤上顯示用了哪一張。',
      KeyboardScreenshotSetupResult.signedOut => '請先登入 VibeSync，再回來啟用「最近截圖」輔助。',
      KeyboardScreenshotSetupResult.consentMissing =>
        '截圖 AI 同意已失效，沒有啟用。請重新操作一次。',
      KeyboardScreenshotSetupResult.accountChanged =>
        '登入帳號在設定途中變更，沒有啟用。請用目前帳號重新操作。',
      KeyboardScreenshotSetupResult.photoDenied =>
        '相片權限已拒絕。請到「iPhone 設定 > VibeSync > 相片」允許取用後再試。',
      KeyboardScreenshotSetupResult.photoRestricted =>
        '這台 iPhone 的相片存取受系統或家長控制限制，目前無法啟用。',
      KeyboardScreenshotSetupResult.photoNotDetermined =>
        'iOS 尚未完成相片授權，沒有啟用。請再試一次。',
      KeyboardScreenshotSetupResult.localStorageFailed =>
        '無法儲存「最近截圖」設定，因此沒有啟用。請再試一次。',
      KeyboardScreenshotSetupResult.nativeSyncFailed =>
        '無法安全同步鍵盤同意，因此沒有啟用。請再試一次。',
    };
  }

  void _showScreenshotSetupFeedback(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _buildLatestScreenshotDetectionSetup() {
    return FutureBuilder<bool>(
      future: _hasLatestScreenshotDetection,
      builder: (context, snapshot) {
        final enabled = snapshot.data == true;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.brandSurface2,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: enabled
                  ? Colors.greenAccent.withValues(alpha: 0.45)
                  : Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    enabled
                        ? Icons.verified_user_outlined
                        : Icons.photo_library_outlined,
                    color: enabled ? Colors.greenAccent : AppColors.brandFlame,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      enabled ? '「最近截圖」輔助已啟用' : '選用：啟用「最近截圖」AI 輔助',
                      style: AppTypography.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                enabled
                    ? '功能啟用後，鍵盤開啟時會在本機尋找最近 3 分鐘的系統截圖並自動分析一張；鍵盤上會顯示這次用的是哪一張。'
                    : '需要獨立的 AI 資料同意與 iOS 相片權限。啟用後，鍵盤開啟時會在本機尋找最近 3 分鐘的系統截圖並自動分析一張；鍵盤上會顯示這次用的是哪一張。',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.onBackgroundSecondary,
                ),
              ),
              if (!enabled) ...[
                const SizedBox(height: 16),
                BrandPrimaryButton(
                  key: const Key('enable_latest_screenshot_detection'),
                  label: '同意並設定相片權限',
                  onPressed: _enablingLatestScreenshotDetection ||
                          _revokingScreenshotConsent
                      ? null
                      : _enableLatestScreenshotDetection,
                  isLoading: _enablingLatestScreenshotDetection,
                  icon: Icons.lock_open_outlined,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildScreenshotConsentRevocation() {
    return FutureBuilder<bool>(
      future: _hasKeyboardScreenshotConsent,
      builder: (context, snapshot) {
        if (snapshot.data != true && !_nativePrivacyCleanupPending) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: TextButton.icon(
            key: const Key('revoke_keyboard_screenshot_consent'),
            onPressed:
                _revokingScreenshotConsent || _enablingLatestScreenshotDetection
                    ? null
                    : _revokeKeyboardScreenshotConsent,
            icon: const Icon(Icons.delete_outline),
            label: Text(
              _revokingScreenshotConsent
                  ? '正在清除鍵盤脈絡…'
                  : _nativePrivacyCleanupPending
                      ? '重試清除鍵盤資料'
                      : '撤回截圖 AI 同意並清除鍵盤脈絡',
            ),
          ),
        );
      },
    );
  }

  void _close() {
    if (widget.firstRun) {
      _skipFirstRun();
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BrandPageBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('VibeSync AI 鍵盤'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _close,
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: PageView(
                  controller: _controller,
                  onPageChanged: (value) => setState(() => _page = value),
                  children: [
                    _SetupPage(
                      icon: Icons.auto_awesome,
                      title: '聊天不用再跳出 App',
                      description: '複製她的訊息，切到 VibeSync 鍵盤，選一種風格，回覆就會插入輸入框。',
                      child: const _StylePreview(),
                    ),
                    _SetupPage(
                      icon: Icons.keyboard_alt_outlined,
                      title: '先啟用 VibeSync 鍵盤',
                      description:
                          '到 iPhone 設定開啟「VibeSync 鍵盤」與「允許完整取用」。iOS 需要由你親自開啟。',
                      child: Column(
                        children: [
                          const _PrivacyNotice(),
                          const SizedBox(height: 20),
                          BrandPrimaryButton(
                            label: '前往 iPhone 設定',
                            onPressed: _openSettings,
                            icon: Icons.open_in_new,
                          ),
                          const SizedBox(height: 12),
                          // 實測 iOS 狀態列的「◀ 返回 App」提示會消失，
                          // 不可靠——明講用 App 切換器回來。
                          Text(
                            '開好後從畫面底部上滑並停頓（App 切換器），切回 VibeSync 繼續。',
                            textAlign: TextAlign.center,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.onBackgroundSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _SetupPage(
                      icon: Icons.language,
                      title: '長按地球，切換鍵盤',
                      description: '在任何聊天 App 點開輸入框，長按左下角 🌐，再選擇「VibeSync 鍵盤」。',
                      child: ScaleTransition(
                        scale: _pulse,
                        child: const _GlobeDemo(),
                      ),
                    ),
                    _SetupPage(
                      icon: Icons.bolt,
                      title: '三步就有好回覆',
                      description:
                          '貼上文字可以直接產生回覆；也可選擇啟用「最近截圖」輔助。VibeSync 只插入文字，最後由你決定是否送出。',
                      child: Column(
                        children: [
                          const _ThreeStepDemo(),
                          const SizedBox(height: 20),
                          _buildLatestScreenshotDetectionSetup(),
                          _buildScreenshotConsentRevocation(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  4,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: index == _page ? 24 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: index == _page
                          ? AppColors.brandFlame
                          : Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: BrandPrimaryButton(
                  label: _page == 3
                      ? '完成'
                      : _page == 1
                          ? '我已完成設定'
                          : '下一步',
                  onPressed: _next,
                ),
              ),
              if (widget.firstRun)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextButton(
                    onPressed: _skipFirstRun,
                    child: const Text('稍後設定'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SetupPage extends StatelessWidget {
  const _SetupPage({
    required this.icon,
    required this.title,
    required this.description,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.brandFlame.withValues(alpha: 0.14),
            ),
            child: Icon(icon, size: 46, color: AppColors.brandFlame),
          ),
          const SizedBox(height: 24),
          Text(title,
              style: AppTypography.headlineMedium, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(
            description,
            style: AppTypography.bodyLarge
                .copyWith(color: AppColors.onBackgroundSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),
          child,
        ],
      ),
    );
  }
}

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.brandSurface2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.45)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.privacy_tip_outlined, color: AppColors.brandFlame),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'VibeSync 只會將你主動點擊「載入」的文字送去產生回覆；「最近截圖」需另行同意，啟用後會在鍵盤開啟時於本機尋找最近 3 分鐘的系統截圖並自動分析一張，上傳前會裁掉截圖裡 VibeSync 鍵盤自己佔的區塊。不會自動讀取其他聊天紀錄。',
              ),
            ),
          ],
        ),
      );
}

class _StylePreview extends StatelessWidget {
  const _StylePreview();
  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: const ['🔄 延展', '💬 共鳴', '😏 調情', '🎭 幽默', '🔮 冷讀']
            .map((text) => Chip(label: Text(text)))
            .toList(),
      );
}

class _GlobeDemo extends StatelessWidget {
  const _GlobeDemo();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: BoxDecoration(
            color: AppColors.brandSurface2,
            borderRadius: BorderRadius.circular(20)),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🌐', style: TextStyle(fontSize: 36)),
            SizedBox(width: 16),
            Icon(Icons.touch_app, color: AppColors.brandFlame, size: 34),
            SizedBox(width: 10),
            Text('長按並選 VibeSync'),
          ],
        ),
      );
}

class _ThreeStepDemo extends StatelessWidget {
  const _ThreeStepDemo();
  @override
  Widget build(BuildContext context) => const Column(
        children: [
          _StepRow(number: '1', text: '複製她的訊息'),
          _StepRow(number: '2', text: '點「載入」'),
          _StepRow(number: '3', text: '選風格，確認後送出'),
        ],
      );
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.number, required this.text});
  final String number;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            CircleAvatar(
                backgroundColor: AppColors.brandFlame, child: Text(number)),
            const SizedBox(width: 14),
            Text(text, style: AppTypography.bodyLarge),
          ],
        ),
      );
}
