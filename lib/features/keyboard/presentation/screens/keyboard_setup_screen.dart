import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/services/funnel_tracker.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/ai_data_sharing_consent.dart';
import '../../../onboarding/data/onboarding_service.dart';
import '../../../../shared/widgets/brand/brand_dialog.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../data/keyboard_setup_resume_marker.dart';
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
  // 冷啟動復原：去 iPhone 設定這一步常把整個 app 記憶體回收掉（不是單純
  // 背景），process 重開後 _page/_openedSettings 這些純記憶體狀態全部歸零，
  // 使用者退回第 1 頁要重點一輪——2026-08-06 真機影片重現。落一份持久旗標，
  // 下次啟動看到就直接跳回「允許完整取用」後的那一頁；app 層的
  // KeyboardOnboardingScheduler 也讀同一旗標把本頁自動推回來。
  static const _awaitingFullAccessReturnKey = KeyboardSetupResumeMarker.key;
  // 「允許完整取用」切完回來要落的那一頁＝相片權限（截圖輔助）頁。
  // 2026-08-09 頁序調整：截圖輔助提前到完整取用後，地球頁移到最後。
  static const _kPostFullAccessPage = 2;
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
    unawaited(_resumeAfterColdRestartIfAwaitingFullAccess());
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

  Future<void> _resumeAfterColdRestartIfAwaitingFullAccess() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_awaitingFullAccessReturnKey) != true) return;
    await prefs.remove(_awaitingFullAccessReturnKey);
    if (!mounted) return;
    _jumpToPostFullAccessPage();
  }

  /// 舊版單發 postFrame 遇到 PageView 還沒 attach 就靜默放棄，使用者落在
  /// 第 1 頁（2026-08-07 真機重測命中）——改成逐幀重試直到 attach，
  /// 上限守門避免異常狀態下空轉。
  void _jumpToPostFullAccessPage([int attemptsLeft = 30]) {
    if (!mounted || attemptsLeft <= 0) return;
    if (_controller.hasClients) {
      _controller.jumpToPage(_kPostFullAccessPage);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _jumpToPostFullAccessPage(attemptsLeft - 1),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _openedSettings && _page == 1) {
      unawaited(
        SharedPreferences.getInstance()
            .then((p) => p.remove(_awaitingFullAccessReturnKey)),
      );
      _controller.animateToPage(
        _kPostFullAccessPage,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _openSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_awaitingFullAccessReturnKey, true);
    final opened = await widget.openSettings();
    if (!mounted) return;
    if (opened) {
      setState(() => _openedSettings = true);
    } else {
      await prefs.remove(_awaitingFullAccessReturnKey);
      if (!mounted) return;
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
    await _clearAwaitingFullAccessReturn();
    if (!mounted) return;
    if (widget.firstRun) {
      context.go('/');
    } else {
      context.pop();
    }
  }

  Future<void> _skipFirstRun() async {
    await OnboardingService.markKeyboardCompleted();
    await _clearAwaitingFullAccessReturn();
    if (mounted) context.go('/');
  }

  Future<void> _clearAwaitingFullAccessReturn() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_awaitingFullAccessReturnKey);
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
        '已啟用「最近截圖」輔助。鍵盤開著時新拍的截圖會自動分析，並在鍵盤上顯示用了哪一張；開鍵盤前 3 分鐘內的截圖可在鍵盤上手動送出分析。',
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
                // 真實行為（2026-08-09 對過 iOS 端）：鍵盤開著時「新拍」的
                // 截圖才會自動分析（一次一張）；開鍵盤前 3 分鐘內的舊截圖
                // 只能在鍵盤上手動送出。別再寫成「自動找最近 3 分鐘的截圖」。
                enabled
                    ? '鍵盤開著時，新拍的截圖會自動分析並直接給回覆；鍵盤上會顯示這次用的是哪一張，按 ✕ 可收起。開鍵盤前 3 分鐘內的截圖則可在鍵盤上手動送出分析。'
                    : '需要獨立的 AI 資料同意與 iOS 相片權限。啟用後，鍵盤開著時新拍的截圖會自動分析並直接給回覆；鍵盤上會顯示這次用的是哪一張，按 ✕ 可收起。',
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
      unawaited(_clearAwaitingFullAccessReturn());
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
                      // 版位順序（2026-08-09）：CTA →「允許完整取用」開關
                      // 預覽（關鍵視覺，要在不捲動下看得到）→ 重啟預告 →
                      // 隱私鈕。重啟預告雖降到第三位，仍在同一頁內。
                      child: Column(
                        children: [
                          BrandPrimaryButton(
                            label: '前往 iPhone 設定',
                            onPressed: _openSettings,
                            icon: Icons.open_in_new,
                          ),
                          const SizedBox(height: 14),
                          const _FullAccessPathGuide(),
                          const SizedBox(height: 14),
                          // 實測 iOS 狀態列的「◀ 返回 App」提示會消失，
                          // 不可靠——明講用 App 切換器回來。另外切「允許完整
                          // 取用」時 iOS 必定強制重啟 App（權限開關的系統行為，
                          // 擋不掉），要先預告，不然看起來像閃退。
                          Text(
                            '開好後從畫面底部上滑並停頓（App 切換器），切回 VibeSync 繼續。'
                            '切「允許完整取用」時 iOS 會重啟 VibeSync 一次——'
                            '這是正常的安全機制，回來會自動接回這裡。',
                            textAlign: TextAlign.center,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.onBackgroundSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const _PrivacyNoticeButton(),
                        ],
                      ),
                    ),
                    // 頁序（2026-08-09）：截圖輔助（相片權限）提前到完整取用
                    // 之後——冷啟動／熱切回的 jump 目標（_kPostFullAccessPage）
                    // 現在落在這頁；地球頁移到最後收尾。
                    _SetupPage(
                      icon: Icons.bolt,
                      title: '截圖就有好回覆',
                      description:
                          '鍵盤開著時截一張圖，AI 會自動分析並直接給你回覆；也可以貼上文字產生。VibeSync 只插入文字，最後由你決定是否送出。',
                      child: Column(
                        children: [
                          _buildLatestScreenshotDetectionSetup(),
                          _buildScreenshotConsentRevocation(),
                          const SizedBox(height: 20),
                          // 三步示範講的是「貼文字」備援路徑，不是截圖流程；
                          // 標明白，避免又跟上面的截圖說明打架。
                          Text(
                            '不想截圖？貼文字也行：',
                            style: AppTypography.labelLarge.copyWith(
                              color: AppColors.onBackgroundSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const _ThreeStepDemo(),
                        ],
                      ),
                    ),
                    _SetupPage(
                      icon: Icons.language,
                      title: '長按地球，切換鍵盤',
                      description: '在任何聊天 App 點開輸入框，長按左下角 🌐，再選擇「VibeSync 鍵盤」。',
                      child: Column(
                        children: [
                          ScaleTransition(
                            scale: _pulse,
                            child: const _GlobeDemo(),
                          ),
                          const SizedBox(height: 20),
                          // 剛切完「允許完整取用」後 iOS 會重新註冊 extension，
                          // 這段空窗清單裡沒有 VibeSync——系統行為，不是我們能救的。
                          Text(
                            '剛開好設定的一兩分鐘內，清單裡可能還沒有 VibeSync——這是 iOS 正在註冊新鍵盤，把聊天 App 關掉重開就會立刻出現。',
                            textAlign: TextAlign.center,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.onBackgroundSecondary,
                            ),
                          ),
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
    // 頭部收窄（2026-08-09）：96px 大圓＋寬間距把每頁關鍵內容（完整取用
    // 開關預覽、截圖同意卡）壓到摺線下，實機要捲才看得到——縮成 64px
    // 並收緊間距，讓頁面主體早點開始。
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.brandFlame.withValues(alpha: 0.14),
            ),
            child: Icon(icon, size: 34, color: AppColors.brandFlame),
          ),
          const SizedBox(height: 16),
          Text(title,
              style: AppTypography.headlineMedium, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text(
            description,
            style: AppTypography.bodyLarge
                .copyWith(color: AppColors.onBackgroundSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

/// 文字太長會把「前往 iPhone 設定」擠到摺線下方（2026-08-06 dogfood
/// 回饋）；改成點擊才展開的資訊鈕，預設只佔一行。
class _PrivacyNoticeButton extends StatelessWidget {
  const _PrivacyNoticeButton();

  static const _detail =
      'VibeSync 只送出你按下「載入」的文字。「最近截圖」需另行同意：啟用後鍵盤開啟期間，新拍的系統截圖會在本機讀取並上傳分析一張，自動裁掉鍵盤佔用區塊，不讀取其他聊天紀錄；開鍵盤前 3 分鐘內的截圖只在你手動選擇時才分析。隨時可按 ✕ 收起結果或撤回同意。';

  void _showDetail(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => BrandAlertDialog(
        title: const Text('資料使用說明'),
        content: const Text(_detail),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
        onPressed: () => _showDetail(context),
        icon: const Icon(
          Icons.privacy_tip_outlined,
          color: AppColors.brandFlame,
          size: 18,
        ),
        label: Text(
          '資料使用說明',
          style: AppTypography.bodySmall
              .copyWith(color: AppColors.onBackgroundSecondary),
        ),
      );
}

/// 圖文路徑導引（2026-08-03）：純文字「到 iPhone 設定開啟...」實測會讓
/// 使用者迷路——iOS 沒有公開 API 能直接跳到「一般 > 鍵盤 > 鍵盤 >
/// VibeSync AI 鍵盤」這一層，「前往 iPhone 設定」只能開到 App 自己的設定
/// 頁，中間要使用者自己走三層。這裡把完整巢狀路徑畫成麵包屑，並用淺色
/// 卡片模擬最終畫面長怎樣，讓使用者到了 iOS 設定裡能認得出「找到了」。
class _FullAccessPathGuide extends StatelessWidget {
  const _FullAccessPathGuide();

  static const _steps = [
    (label: '設定 App', icon: Icons.settings),
    (label: '一般', icon: Icons.tune),
    (label: '鍵盤', icon: Icons.keyboard_outlined),
    (label: '鍵盤（Keyboards）', icon: Icons.list_alt),
    (label: 'VibeSync AI 鍵盤', icon: Icons.smart_toy_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.brandSurface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '找不到「允許完整取用」？照這條路徑走：',
            style: AppTypography.labelLarge
                .copyWith(color: AppColors.onBackgroundSecondary),
          ),
          const SizedBox(height: 12),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var i = 0; i < _steps.length; i++) ...[
                _PathChip(
                  label: _steps[i].label,
                  icon: _steps[i].icon,
                ),
                if (i != _steps.length - 1)
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color:
                        AppColors.onBackgroundSecondary.withValues(alpha: 0.6),
                  ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          const _FullAccessTogglePreview(),
        ],
      ),
    );
  }
}

class _PathChip extends StatelessWidget {
  const _PathChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.brandFlame),
          const SizedBox(width: 6),
          Text(label, style: AppTypography.labelMedium),
        ],
      ),
    );
  }
}

/// 模擬使用者最終會看到的那個畫面（淺色，仿 iOS 設定介面），讓使用者
/// 到了那一層能立刻認出「就是這個」，並提示要撥到右邊（開）。
class _FullAccessTogglePreview extends StatelessWidget {
  const _FullAccessTogglePreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.keyboard_alt_outlined, color: Colors.black87),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              '允許完整取用',
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            width: 44,
            height: 26,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Colors.greenAccent.shade400,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Align(
              alignment: Alignment.centerRight,
              child: CircleAvatar(radius: 11, backgroundColor: Colors.white),
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.arrow_back, size: 16, color: Colors.black45),
          const SizedBox(width: 2),
          Text(
            '撥到這邊',
            style: AppTypography.caption.copyWith(color: Colors.black45),
          ),
        ],
      ),
    );
  }
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
