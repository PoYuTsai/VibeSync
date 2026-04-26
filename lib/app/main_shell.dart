// lib/app/main_shell.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../shared/widgets/warm_theme_widgets.dart';
import '../features/conversation/data/providers/conversation_write_controller.dart';
import '../features/conversation/presentation/screens/home_screen.dart';
import '../features/report/presentation/screens/my_report_screen.dart';
import '../features/learning/presentation/screens/learning_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text('VibeSync', style: AppTypography.headlineMedium),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () => context.push('/settings'),
            ),
          ],
        ),
        body: Builder(
          builder: (shellContext) => IndexedStack(
            index: _currentIndex,
            children: [
              HomeContent(
                onNewConversation: () => _showNewConversationOptions(shellContext),
              ),
              const MyReportScreen(),
              const LearningScreen(),
            ],
          ),
        ),
        floatingActionButton: _currentIndex == 0
            ? _HomeFab()
            : null,
        bottomNavigationBar: _buildBottomNav(),
      ),
    );
  }

  void _showNewConversationOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _NewConversationSheet(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundGradientStart.withValues(alpha: 0.95),
        border: Border(
          top: BorderSide(
            color: AppColors.glassBorder.withValues(alpha: 0.2),
          ),
        ),
      ),
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildTab(0, Icons.home_outlined, Icons.home, '首頁'),
            _buildTab(
                1, Icons.bar_chart_outlined, Icons.bar_chart, '報告'),
            _buildTab(
                2, Icons.menu_book_outlined, Icons.menu_book, '學習'),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(
      int index, IconData icon, IconData activeIcon, String label) {
    final isSelected = _currentIndex == index;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _currentIndex = index),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(
            horizontal: isSelected ? 24 : 20,
            vertical: 12,
          ),
          decoration: isSelected
              ? BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.ctaStart, AppColors.ctaEnd],
                  ),
                  borderRadius: BorderRadius.circular(24),
                )
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSelected ? activeIcon : icon,
                color: isSelected
                    ? Colors.white
                    : AppColors.onBackgroundSecondary,
                size: 22,
              ),
              if (isSelected) ...[
                const SizedBox(width: 8),
                Text(
                  label,
                  style: AppTypography.bodySmall.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// FAB extracted so it can access WidgetRef via Consumer
class _HomeFab extends ConsumerWidget {
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
            color: AppColors.ctaStart.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: FloatingActionButton(
        onPressed: () => showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (ctx) => _NewConversationSheet(),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

}

/// Shared bottom sheet for creating new conversations.
class _NewConversationSheet extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.glassWhite,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '新增對話',
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.glassTextPrimary,
            ),
          ),
          const SizedBox(height: 20),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.edit_note, color: AppColors.primary),
            ),
            title: Text(
              '手動輸入',
              style: TextStyle(color: AppColors.glassTextPrimary),
            ),
            subtitle: Text(
              '輸入聊天內容並開始分析',
              style: TextStyle(color: AppColors.unselectedText, fontSize: 12),
            ),
            onTap: () {
              Navigator.pop(context);
              context.push('/new');
            },
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.ctaStart.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.photo_camera, color: AppColors.ctaStart),
            ),
            title: Text(
              '截圖開始',
              style: TextStyle(color: AppColors.glassTextPrimary),
            ),
            subtitle: Text(
              '從相簿選擇聊天截圖，AI 先幫你辨識再建立對話',
              style: TextStyle(color: AppColors.unselectedText, fontSize: 12),
            ),
            onTap: () async {
              Navigator.pop(context);
              final conversation = await ref
                  .read(conversationWriteControllerProvider.notifier)
                  .create(name: '新對話', messages: []);
              if (context.mounted) {
                context.push('/conversation/${conversation.id}');
              }
            },
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.bokehYellow.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.auto_awesome, color: AppColors.bokehYellow),
            ),
            title: Text(
              '開場救星',
              style: TextStyle(color: AppColors.glassTextPrimary),
            ),
            subtitle: Text(
              '交友軟體不知道怎麼開場？AI 幫你生成開場白',
              style: TextStyle(color: AppColors.unselectedText, fontSize: 12),
            ),
            onTap: () {
              Navigator.pop(context);
              context.push('/opener');
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
