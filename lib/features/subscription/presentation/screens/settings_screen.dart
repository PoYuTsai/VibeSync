// lib/features/subscription/presentation/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text('設定', style: AppTypography.titleLarge),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        children: [
          _buildSection(
            title: '帳戶',
            children: [
              _buildTile(
                icon: Icons.workspace_premium,
                title: '訂閱方案',
                trailing: 'Free',
                onTap: () {
                  context.push('/paywall');
                },
              ),
              _buildTile(
                icon: Icons.analytics,
                title: '本月用量',
                trailing: '0/30 則',
              ),
              _buildTile(
                icon: Icons.person,
                title: '帳號',
                trailing: '未登入',
                onTap: () {
                  // TODO: Open login screen
                },
              ),
            ],
          ),
          _buildSection(
            title: '隱私與安全',
            children: [
              _buildTile(
                icon: Icons.delete_forever,
                title: '清除所有對話資料',
                titleColor: AppColors.error,
                onTap: () => _showDeleteDialog(context),
              ),
              _buildTile(
                icon: Icons.download,
                title: '匯出我的資料',
                onTap: () {
                  // TODO: Export data as JSON
                  _showComingSoonSnackBar(context, '匯出功能即將推出');
                },
              ),
              _buildTile(
                icon: Icons.privacy_tip,
                title: '隱私權政策',
                onTap: () {
                  // TODO: Open privacy policy URL
                  _showComingSoonSnackBar(context, '隱私權政策連結');
                },
              ),
            ],
          ),
          _buildSection(
            title: '關於',
            children: [
              _buildTile(
                icon: Icons.info,
                title: '版本',
                trailing: '1.0.0',
              ),
              _buildTile(
                icon: Icons.description,
                title: '使用條款',
                onTap: () {
                  // TODO: Open terms URL
                  _showComingSoonSnackBar(context, '使用條款連結');
                },
              ),
              _buildTile(
                icon: Icons.feedback,
                title: '意見回饋',
                onTap: () {
                  // TODO: Open feedback form
                  _showComingSoonSnackBar(context, '意見回饋功能');
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            title,
            style: AppTypography.labelLarge.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        ...children,
      ],
    );
  }

  Widget _buildTile({
    required IconData icon,
    required String title,
    String? trailing,
    Color? titleColor,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: titleColor ?? AppColors.textSecondary),
      title: Text(
        title,
        style: AppTypography.bodyLarge.copyWith(color: titleColor),
      ),
      trailing: trailing != null
          ? Text(
              trailing,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            )
          : const Icon(Icons.chevron_right, color: AppColors.textSecondary),
      onTap: onTap,
    );
  }

  void _showDeleteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('確定要刪除所有對話？'),
        content: const Text('此操作無法復原。您所有的對話紀錄都會被永久刪除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await StorageService.clearAll();
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('所有對話資料已清除'),
                    backgroundColor: AppColors.success,
                  ),
                );
              }
            },
            child: Text(
              '刪除',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  void _showComingSoonSnackBar(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature 即將推出'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
