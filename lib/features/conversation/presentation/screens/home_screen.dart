// lib/features/conversation/presentation/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/warm_theme_widgets.dart';
import '../../data/providers/conversation_providers.dart';
import '../widgets/conversation_tile.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(conversationsProvider);

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
        // RWD: 限制最大寬度，大螢幕置中顯示
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: conversations.isEmpty
                ? _buildEmptyState(context)
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    itemCount: conversations.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final conversation = conversations[index];
                      return GlassmorphicContainer(
                        padding: EdgeInsets.zero,
                        child: ConversationTile(
                          conversation: conversation,
                          onTap: () => context.push('/conversation/${conversation.id}'),
                          onDelete: () => _showDeleteDialog(context, ref, conversation),
                        ),
                      );
                    },
                  ),
          ),
        ),
        floatingActionButton: _buildFab(context, ref),
      ),
    );
  }

  Widget _buildFab(BuildContext context, WidgetRef ref) {
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
        onPressed: () => _showNewConversationOptions(context, ref),
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _showNewConversationOptions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
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
            // 手動輸入
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
                '輸入對話內容和情境設定',
                style: TextStyle(color: AppColors.unselectedText, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(context);
                context.push('/new');
              },
            ),
            const SizedBox(height: 8),
            // 截圖開始
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
                '上傳聊天截圖，AI 自動識別對話',
                style: TextStyle(color: AppColors.unselectedText, fontSize: 12),
              ),
              onTap: () async {
                Navigator.pop(context);
                await _createConversationFromScreenshot(context, ref);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _createConversationFromScreenshot(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(conversationRepositoryProvider);

    // 創建一個新對話（名稱稍後由用戶設定或從截圖識別）
    final conversation = await repository.createConversation(
      name: '新對話',
      messages: [],
    );

    ref.invalidate(conversationsProvider);

    if (context.mounted) {
      // 導航到分析頁面，用戶可以上傳截圖
      context.push('/conversation/${conversation.id}');
    }
  }

  Future<void> _showDeleteDialog(
    BuildContext context,
    WidgetRef ref,
    dynamic conversation,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.glassWhite,
        title: Text('刪除對話', style: TextStyle(color: AppColors.glassTextPrimary)),
        content: Text(
          '確定要刪除與「${conversation.name}」的對話嗎？',
          style: TextStyle(color: AppColors.glassTextPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('取消', style: TextStyle(color: AppColors.unselectedText)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.error,
            ),
            child: const Text('刪除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final repository = ref.read(conversationRepositoryProvider);
      await repository.deleteConversation(conversation.id);
      ref.invalidate(conversationsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已刪除「${conversation.name}」')),
        );
      }
    }
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: AppColors.onBackgroundSecondary,
          ),
          const SizedBox(height: 16),
          Text(
            '還沒有對話',
            style: AppTypography.titleLarge.copyWith(
              color: AppColors.onBackgroundPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '點擊右下角 + 手動輸入或上傳截圖',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
