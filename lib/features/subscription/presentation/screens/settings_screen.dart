// lib/features/subscription/presentation/screens/settings_screen.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/warm_theme_widgets.dart';
import '../../data/providers/subscription_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _versionString = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _versionString = '${packageInfo.version} (${packageInfo.buildNumber})';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final subscription = ref.watch(subscriptionProvider);

    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text('設定', style: AppTypography.titleLarge),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildSection(
                  title: '帳戶',
                  children: [
                    _buildTile(
                      context: context,
                      icon: Icons.workspace_premium,
                      title: '訂閱方案',
                      trailing: _getTierDisplayName(subscription.tier),
                      onTap: () => context.push('/paywall'),
                    ),
                    _buildTile(
                      context: context,
                      icon: Icons.analytics,
                      title: '本月用量',
                      trailing:
                          '${subscription.monthlyMessagesUsed}/${subscription.monthlyLimit} 則',
                    ),
                    _buildTile(
                      context: context,
                      icon: Icons.person,
                      title: '帳號',
                      trailing: _getAccountDisplay(),
                    ),
                    if (!kIsWeb) // 只在 App 顯示恢復購買
                      _buildTile(
                        context: context,
                        icon: Icons.restore,
                        title: '恢復購買',
                        onTap: () => _restorePurchases(context, ref),
                      ),
                  ],
                ),
                _buildSection(
                  title: '隱私與安全',
                  children: [
                    _buildTile(
                      context: context,
                      icon: Icons.delete_forever,
                      title: '清除所有對話資料',
                      titleColor: AppColors.error,
                      onTap: () => _confirmDeleteAccount(context, ref),
                    ),
                    _buildTile(
                      context: context,
                      icon: Icons.privacy_tip,
                      title: '隱私權政策',
                      onTap: () => _launchUrl('https://vibesyncai.app/privacy'),
                    ),
                  ],
                ),
                _buildSection(
                  title: '關於',
                  children: [
                    _buildTile(
                      context: context,
                      icon: Icons.info,
                      title: '版本',
                      trailing:
                          _versionString.isNotEmpty ? _versionString : '載入中...',
                    ),
                    _buildTile(
                      context: context,
                      icon: Icons.description,
                      title: '使用條款',
                      onTap: () => _launchUrl('https://vibesyncai.app/terms'),
                    ),
                    _buildTile(
                      context: context,
                      icon: Icons.feedback,
                      title: '意見回饋',
                      onTap: () =>
                          _launchUrl('https://t.me/vibesync_feedback_bot'),
                    ),
                    _buildTile(
                      context: context,
                      icon: Icons.logout,
                      title: '登出',
                      titleColor: AppColors.error,
                      onTap: () => _logout(context, ref),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getTierDisplayName(String tier) {
    switch (tier) {
      case 'starter':
        return 'Starter';
      case 'essential':
        return 'Essential';
      default:
        return 'Free';
    }
  }

  String _getAccountDisplay() {
    final user = SupabaseService.currentUser;
    if (user == null) return '未登入';

    // Check login provider from app_metadata
    final provider = user.appMetadata['provider'] as String?;

    if (provider == 'apple') {
      // Apple user: prefer name, fallback to "Apple 帳號"
      final fullName = user.userMetadata?['full_name'] as String?;
      final name = user.userMetadata?['name'] as String?;
      return fullName ?? name ?? 'Apple 帳號';
    }

    // Google / Email user: show email
    return user.email ?? '未知帳號';
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
          child: Text(
            title,
            style: AppTypography.labelLarge.copyWith(
              color: AppColors.onBackgroundSecondary,
            ),
          ),
        ),
        GlassmorphicContainer(
          padding: EdgeInsets.zero,
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    String? trailing,
    Color? titleColor,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: titleColor ?? AppColors.glassTextHint),
      title: Text(
        title,
        style: AppTypography.bodyLarge.copyWith(
          color: titleColor ?? AppColors.glassTextPrimary,
        ),
      ),
      trailing: trailing != null
          ? Text(
              trailing,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.glassTextHint,
              ),
            )
          : Icon(Icons.chevron_right, color: AppColors.glassTextHint),
      onTap: onTap,
    );
  }

  Future<void> _restorePurchases(BuildContext context, WidgetRef ref) async {
    // 顯示 loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final restored =
          await ref.read(subscriptionProvider.notifier).restorePurchases();

      if (context.mounted) {
        Navigator.pop(context); // 關閉 loading

        if (restored) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('購買已恢復！'),
              backgroundColor: AppColors.success,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('沒有找到可恢復的購買')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // 關閉 loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('恢復失敗: $e')),
        );
      }
    }
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.glassWhite,
        title: Text(
          '確定要登出？',
          style: TextStyle(color: AppColors.glassTextPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child:
                Text('取消', style: TextStyle(color: AppColors.unselectedText)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('登出', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await SupabaseService.signOut();
      ref.invalidate(subscriptionProvider);
      if (context.mounted) {
        context.go('/login');
      }
    }
  }

  Future<void> _confirmDeleteAccount(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final controller = TextEditingController();
    final confirmation = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: AppColors.glassWhite,
          title: Text(
            '刪除帳號',
            style: TextStyle(color: AppColors.glassTextPrimary),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '這會永久刪除你的帳號與雲端資料。若你仍有 App Store 訂閱，仍需到 Apple 的訂閱管理頁另外取消續訂。',
                style: TextStyle(
                  color: AppColors.glassTextPrimary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '請輸入 DELETE 以確認',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.glassTextPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => setDialogState(() {}),
                decoration: InputDecoration(
                  hintText: 'DELETE',
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.45),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                '取消',
                style: TextStyle(color: AppColors.unselectedText),
              ),
            ),
            TextButton(
              onPressed: controller.text.trim().toUpperCase() == 'DELETE'
                  ? () => Navigator.pop(dialogContext, controller.text.trim())
                  : null,
              child: Text(
                '永久刪除',
                style: TextStyle(color: AppColors.error),
              ),
            ),
          ],
        ),
      ),
    );
    controller.dispose();

    if (confirmation == null || !context.mounted) {
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await SupabaseService.deleteAccount(confirmation: confirmation);
      await StorageService.clearAll();
      await SupabaseService.clearLocalSessionAfterDeletion();
      ref.invalidate(subscriptionProvider);

      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        context.go('/login');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('帳號已刪除'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('刪除帳號失敗: $error'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // ignore: unused_element
  void _showDeleteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.glassWhite,
        title: Text(
          '確定要刪除所有對話？',
          style: TextStyle(color: AppColors.glassTextPrimary),
        ),
        content: Text(
          '此操作無法復原。您所有的對話紀錄都會被永久刪除。',
          style: TextStyle(color: AppColors.glassTextPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child:
                Text('取消', style: TextStyle(color: AppColors.unselectedText)),
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

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
