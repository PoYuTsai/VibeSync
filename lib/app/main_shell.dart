// lib/app/main_shell.dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/services/app_haptics.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_motion.dart';
import '../core/theme/app_typography.dart';
import '../shared/widgets/brand/brand_kit.dart';
import '../shared/widgets/pressable_scale.dart';
import '../features/partner/presentation/providers/partner_providers.dart';
import '../features/partner/presentation/screens/partner_list_screen.dart';
import '../features/partner/presentation/widgets/home_coach_presence.dart';
import '../features/report/presentation/screens/my_report_screen.dart';
import '../features/learning/presentation/screens/learning_screen.dart';

const double homeFabReservedHeight = 74;

class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    this.initialTabIndex = 0,
    this.routeTab,
  });

  final int initialTabIndex;
  final String? routeTab;

  static int tabIndexFromRoute(String? tab) {
    switch (tab) {
      case 'report':
      case 'reports':
        return 1;
      case 'learn':
      case 'learning':
        return 2;
      case 'home':
      default:
        return 0;
    }
  }

  static String tabRouteFromIndex(int index) {
    switch (index) {
      case 1:
        return 'report';
      case 2:
        return 'learning';
      case 0:
      default:
        return 'home';
    }
  }

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell>
    with SingleTickerProviderStateMixin {
  final Random _coachRandom = Random();
  late int _currentIndex = _normalizeTabIndex(widget.initialTabIndex);
  late HomeCoachPose _coachPose =
      HomeCoachPose.values[_coachRandom.nextInt(HomeCoachPose.values.length)];

  /// fade-through：Phase A（0→0.3＝90ms）舊頁淡出、換 index，
  /// Phase B（0.3→1＝210ms）新頁淡入＋scale 0.92→1。value 1＝靜止完整顯示。
  late final AnimationController _tabTransition = AnimationController(
    vsync: this,
    duration: AppMotion.tabTransition,
    value: 1,
  )..addListener(_onTabTransitionTick);
  int? _pendingIndex;

  /// 動畫中再切時 Phase A 從當下 opacity 出發，不閃白。
  double _fadeFrom = 1.0;

  static const double _swapPoint = 0.3;

  void _onTabTransitionTick() {
    final pending = _pendingIndex;
    if (pending == null || _tabTransition.value < _swapPoint) return;
    setState(() {
      _updateCurrentTab(pending);
      _pendingIndex = null;
    });
  }

  double get _tabOpacity {
    final t = _tabTransition.value;
    if (_pendingIndex != null) {
      final out = (t / _swapPoint).clamp(0.0, 1.0);
      return _fadeFrom * (1 - Curves.easeOut.transform(out));
    }
    final inn = ((t - _swapPoint) / (1 - _swapPoint)).clamp(0.0, 1.0);
    return AppMotion.easeOut.transform(inn);
  }

  double get _tabScale {
    if (_pendingIndex != null) return 1.0;
    final inn = ((_tabTransition.value - _swapPoint) / (1 - _swapPoint))
        .clamp(0.0, 1.0);
    return 0.92 + 0.08 * AppMotion.easeOut.transform(inn);
  }

  @override
  void dispose() {
    _tabTransition.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextIndex = _normalizeTabIndex(widget.initialTabIndex);
    final routeTabChanged = oldWidget.routeTab != widget.routeTab;
    // fade-through 進行中且目標一致時交給動畫換 index，避免 context.go 觸發的
    // rebuild 把轉場打斷成硬切。
    if (routeTabChanged &&
        _currentIndex != nextIndex &&
        _pendingIndex != nextIndex) {
      setState(() {
        _pendingIndex = null;
        _tabTransition.value = 1;
        _updateCurrentTab(nextIndex);
      });
    }
  }

  int _normalizeTabIndex(int index) => index.clamp(0, 2);

  @override
  Widget build(BuildContext context) {
    return BrandPageBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          titleSpacing: 16,
          title: Row(
            children: [
              Text(
                'VibeSync',
                style: AppTypography.headlineMedium.copyWith(
                  color: AppColors.onBackgroundPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(top: 12),
                decoration: const BoxDecoration(
                  color: AppColors.ctaStart,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          actions: [
            // 夥伴稿：齒輪帶一圈深灰底，跟 wordmark 分層、也把點擊區畫出來。
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: const Icon(Icons.settings_rounded, size: 20),
                tooltip: '設定',
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  foregroundColor: AppColors.onBackgroundPrimary,
                  shape: const CircleBorder(),
                ),
                onPressed: AppHaptics.onPress(() => context.push('/settings')),
              ),
            ),
          ],
        ),
        body: AnimatedBuilder(
          animation: _tabTransition,
          builder: (context, child) {
            final animating =
                _tabTransition.isAnimating || _pendingIndex != null;
            return Opacity(
              opacity: animating ? _tabOpacity : 1.0,
              child: Transform.scale(
                scale: animating ? _tabScale : 1.0,
                child: child,
              ),
            );
          },
          // IndexedStack 不會替隱藏 child 關 ticker，各 child 包 TickerMode
          // 讓背景 tab 的環境動畫真正停下（品牌元件內已有對應閘門）。
          child: IndexedStack(
            index: _currentIndex,
            children: [
              TickerMode(
                enabled: _currentIndex == 0,
                child: PartnerListScreen(
                  bottomPadding: 32,
                  coachPose: _coachPose,
                ),
              ),
              TickerMode(
                enabled: _currentIndex == 1,
                child: const MyReportScreen(),
              ),
              TickerMode(
                enabled: _currentIndex == 2,
                child: const LearningScreen(),
              ),
            ],
          ),
        ),
        floatingActionButton: _currentIndex == 0 ? const HomeFab() : null,
        bottomNavigationBar: _buildBottomNav(),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.brandInk.withValues(alpha: 0.94),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 28,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildTab(0, Icons.home_outlined, Icons.home, '首頁'),
            _buildTab(1, Icons.bar_chart_outlined, Icons.bar_chart, '報告'),
            _buildTab(2, Icons.menu_book_outlined, Icons.menu_book, '學習'),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(
    int index,
    IconData icon,
    IconData activeIcon,
    String label,
  ) {
    final isSelected = _currentIndex == index;
    final color =
        isSelected ? AppColors.ctaStart : Colors.white.withValues(alpha: 0.62);

    return Semantics(
      selected: isSelected,
      button: true,
      label: label,
      child: PressableScale(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _selectTab(index),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 72, minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isSelected ? activeIcon : icon,
                    color: color,
                    size: 22,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: AppTypography.labelMedium.copyWith(
                      color: color,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _selectTab(int index) {
    final nextIndex = _normalizeTabIndex(index);
    if (_currentIndex != nextIndex || _pendingIndex != null) {
      final reduceMotion =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (reduceMotion) {
        setState(() {
          _pendingIndex = null;
          _tabTransition.value = 1;
          _updateCurrentTab(nextIndex);
        });
      } else if (_pendingIndex != null) {
        // Phase A 進行中再點：換目標即可，淡出照走、換到最新 index。
        _pendingIndex = nextIndex;
      } else {
        _fadeFrom = _tabOpacity;
        _pendingIndex = nextIndex;
        _tabTransition.forward(from: 0);
      }
    }
    context.go('/?tab=${MainShell.tabRouteFromIndex(nextIndex)}');
  }

  void _updateCurrentTab(int nextIndex) {
    if (nextIndex == 0) {
      _changeCoachPose();
    }
    _currentIndex = nextIndex;
  }

  void _changeCoachPose() {
    // 稀有彩蛋降頻：冷啟動隨機一次後，回首頁只有 20% 機率換姿勢，
    // 免得 100+ 次/天的切 tab 把新鮮感磨光。
    if (_coachRandom.nextDouble() >= 0.2) return;
    _coachPose = _coachPose.differentPose(_coachRandom);
  }
}

/// FAB extracted so it can access WidgetRef via Consumer.
///
/// Public so it can be widget-tested in isolation without spinning up the
/// full `MainShell` (which mounts Hive-backed tabs eagerly via IndexedStack).
/// Tooltip 「新增對象」 follows ADR-15: home FAB is Partner-level — a tap
/// opens the new-Partner flow, NOT a new-Conversation sheet.
class HomeFab extends ConsumerWidget {
  const HomeFab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 空態不浮這顆：那一頁已經有整寬「建立對象卡，開始分析」CTA，再疊一顆 +
    // 只會蓋住文案（夥伴稿 2／3 也都沒有 FAB）。有對象後才需要這個捷徑。
    if (ref.watch(partnerListProvider).isEmpty) return const SizedBox.shrink();
    return PressableScale(
      hapticOnDown: true,
      child: FloatingActionButton(
        onPressed: () => context.push('/partner/new'),
        backgroundColor: AppColors.ctaStart,
        foregroundColor: AppColors.onCta,
        elevation: 0,
        tooltip: '新增對象',
        child: const Icon(Icons.add),
      ),
    );
  }
}
