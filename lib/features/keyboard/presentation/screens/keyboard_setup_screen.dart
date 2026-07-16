import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../onboarding/data/onboarding_service.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';

typedef OpenKeyboardSettings = Future<bool> Function();

class KeyboardSetupScreen extends StatefulWidget {
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
  State<KeyboardSetupScreen> createState() => _KeyboardSetupScreenState();
}

class _KeyboardSetupScreenState extends State<KeyboardSetupScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final _controller = PageController();
  late final AnimationController _pulse;
  int _page = 0;
  bool _openedSettings = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      await OnboardingService.markKeyboardCompleted();
    }
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
                    const _SetupPage(
                      icon: Icons.bolt,
                      title: '三步就有好回覆',
                      description:
                          '複製對方訊息 → 點「載入」→ 選延展、共鳴、調情、幽默或冷讀。VibeSync 只插入文字，最後由你決定是否送出。',
                      child: _ThreeStepDemo(),
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
              child: Text('VibeSync 只會將你主動點擊「載入」的文字送去產生回覆，不會自動讀取或蒐集其他輸入內容。'),
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
