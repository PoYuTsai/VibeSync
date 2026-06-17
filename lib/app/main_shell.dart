// lib/app/main_shell.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../shared/widgets/warm_theme_widgets.dart';
import '../features/partner/presentation/screens/partner_list_screen.dart';
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

class _MainShellState extends State<MainShell> {
  late int _currentIndex = _normalizeTabIndex(widget.initialTabIndex);

  @override
  void didUpdateWidget(covariant MainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextIndex = _normalizeTabIndex(widget.initialTabIndex);
    final routeTabChanged = oldWidget.routeTab != widget.routeTab;
    if (routeTabChanged && _currentIndex != nextIndex) {
      setState(() => _currentIndex = nextIndex);
    }
  }

  int _normalizeTabIndex(int index) => index.clamp(0, 2);

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('VibeSync', style: AppTypography.headlineMedium),
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
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () => context.push('/settings'),
            ),
          ],
        ),
        body: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.only(
            bottom: _currentIndex == 0 ? homeFabReservedHeight : 0,
          ),
          child: IndexedStack(
            index: _currentIndex,
            children: const [
              PartnerListScreen(),
              MyReportScreen(),
              LearningScreen(),
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
      padding: const EdgeInsets.only(top: 10, bottom: 8),
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
    final iconColor =
        isSelected ? Colors.white : Colors.white.withValues(alpha: 0.66);

    return Semantics(
      selected: isSelected,
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _selectTab(index),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minWidth: 54, minHeight: 44),
            padding: EdgeInsets.symmetric(
              horizontal: isSelected ? 20 : 14,
              vertical: 11,
            ),
            decoration: isSelected
                ? BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.ctaStart, AppColors.ctaEnd],
                    ),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.ctaStart.withValues(alpha: 0.28),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  )
                : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isSelected ? activeIcon : icon,
                  color: iconColor,
                  size: 22,
                ),
                if (isSelected) ...[
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: AppTypography.bodySmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _selectTab(int index) {
    final nextIndex = _normalizeTabIndex(index);
    if (_currentIndex != nextIndex) {
      setState(() => _currentIndex = nextIndex);
    }
    context.go('/?tab=${MainShell.tabRouteFromIndex(nextIndex)}');
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
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.ctaStart, AppColors.ctaEnd],
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.ctaStart.withValues(alpha: 0.32),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: FloatingActionButton(
        onPressed: () => context.push('/partner/new'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        tooltip: '新增對象',
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
