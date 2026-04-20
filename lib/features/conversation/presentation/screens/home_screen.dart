// lib/features/conversation/presentation/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/warm_theme_widgets.dart';
import '../../data/providers/conversation_providers.dart';
import '../widgets/conversation_tile.dart';

/// Body-only content for use inside MainShell (no Scaffold/AppBar/FAB).
class HomeContent extends ConsumerWidget {
  final VoidCallback? onNewConversation;

  const HomeContent({super.key, this.onNewConversation});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(conversationsProvider);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: conversations.isEmpty
            ? _buildEmptyState(context)
            : ListView.separated(
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 16,
                ),
                itemCount: conversations.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final conversation = conversations[index];
                  return GlassmorphicContainer(
                    padding: EdgeInsets.zero,
                    child: ConversationTile(
                      conversation: conversation,
                      onTap: () =>
                          context.push('/conversation/${conversation.id}'),
                      onDelete: () =>
                          _showDeleteDialog(context, ref, conversation),
                    ),
                  );
                },
              ),
      ),
    );
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
        title: Text(
          '刪除對話',
          style: TextStyle(color: AppColors.glassTextPrimary),
        ),
        content: Text(
          '確定要刪除「${conversation.name}」這個對話嗎？',
          style: TextStyle(color: AppColors.glassTextPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              '取消',
              style: TextStyle(color: AppColors.unselectedText),
            ),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Text(
            '三步開始',
            style: AppTypography.headlineMedium.copyWith(
              color: AppColors.onBackgroundPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'AI 教練幫你拆解每一句話',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundSecondary,
            ),
          ),
          const SizedBox(height: 28),

          // Step 1
          _buildGuideStep(
            number: '1',
            icon: Icons.photo_camera_outlined,
            title: '截圖她的訊息',
            subtitle: '從相簿選一張聊天截圖',
          ),
          const SizedBox(height: 12),

          // Step 2
          _buildGuideStep(
            number: '2',
            icon: Icons.psychology_outlined,
            title: 'AI 幫你分析',
            subtitle: '熱度、階段、心理全拆解',
          ),
          const SizedBox(height: 12),

          // Step 3
          _buildGuideStep(
            number: '3',
            icon: Icons.chat_outlined,
            title: '教你怎麼回',
            subtitle: '五種風格，複製就能用',
          ),
          const SizedBox(height: 32),

          // CTA Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.ctaStart, AppColors.ctaEnd],
                ),
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.ctaStart.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(26),
                  onTap: () {
                    if (onNewConversation != null) {
                      onNewConversation!();
                    } else {
                      context.push('/new');
                    }
                  },
                  child: Center(
                    child: Text(
                      '立即開始',
                      style: AppTypography.titleMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildGuideStep({
    required String number,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return GlassmorphicContainer(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Number circle
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.ctaStart, AppColors.ctaEnd],
              ),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: AppTypography.titleMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Icon
          Icon(icon, color: AppColors.glassTextHint, size: 28),
          const SizedBox(width: 14),
          // Text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.glassTextPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.glassTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Full standalone HomeScreen (kept for backward compatibility).
/// The main app now uses MainShell which embeds HomeContent directly.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        body: const HomeContent(),
      ),
    );
  }
}
