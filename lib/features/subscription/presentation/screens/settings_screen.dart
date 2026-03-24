import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../core/services/storage_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/services/link_launch_service.dart';
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
    if (!mounted) {
      return;
    }

    setState(() {
      _versionString = '${packageInfo.version} (${packageInfo.buildNumber})';
    });
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
                  title: '帳號與方案',
                  children: [
                    _buildTile(
                      context: context,
                      icon: Icons.workspace_premium,
                      title: '目前方案',
                      trailing: _getTierDisplayName(subscription.tier),
                      onTap: () => context.push('/paywall'),
                    ),
                    _buildTile(
                      context: context,
                      icon: Icons.analytics,
                      title: '本月已分析',
                      trailing:
                          '${subscription.monthlyMessagesUsed}/${subscription.monthlyLimit}',
                    ),
                    _buildTile(
                      context: context,
                      icon: Icons.person,
                      title: '帳號',
                      trailing: _getAccountDisplay(),
                    ),
                    if (!kIsWeb)
                      _buildTile(
                        context: context,
                        icon: Icons.restore,
                        title: '恢復購買',
                        onTap: () => _restorePurchases(context, ref),
                      ),
                  ],
                ),
                _buildSection(
                  title: '安全與隱私',
                  children: [
                    _buildTile(
                      context: context,
                      icon: Icons.delete_forever,
                      title: '刪除帳號',
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
                  title: '其他',
                  children: [
                    _buildTile(
                      context: context,
                      icon: Icons.info,
                      title: '版本',
                      trailing:
                          _versionString.isNotEmpty ? _versionString : '讀取中...',
                    ),
                    _buildTile(
                      context: context,
                      icon: Icons.description,
                      title: '服務條款',
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
    if (user == null) {
      return '未登入';
    }

    final provider = user.appMetadata['provider'] as String?;

    if (provider == 'apple') {
      final fullName = user.userMetadata?['full_name'] as String?;
      final name = user.userMetadata?['name'] as String?;
      return fullName ?? name ?? 'Apple 帳號';
    }

    return user.email ?? '未提供 email';
  }

  bool _containsAny(String source, List<String> patterns) {
    return patterns.any(source.contains);
  }

  String _mapRestorePurchasesError(Object error) {
    final normalized = error.toString().toLowerCase();

    if (_containsAny(normalized, [
      'network',
      'timeout',
      'socket',
      'failed host lookup',
      'connection',
    ])) {
      return '網路不太穩，請稍後再試一次。';
    }

    if (_containsAny(normalized, [
      'not logged in',
      'unauthorized',
      'auth',
      'jwt',
      'session',
    ])) {
      return '登入狀態已失效，請重新登入後再試。';
    }

    if (_containsAny(normalized, [
      'not initialized',
      'configured',
      'configuration',
      'platform',
    ])) {
      return '購買服務還在準備中，請稍後再試。';
    }

    return '目前無法恢復購買，請稍後再試一次。';
  }

  String _mapDeleteAccountError(Object error) {
    final normalized = error.toString().toLowerCase();

    if (_containsAny(normalized, [
      'confirmation',
      'mismatch',
    ])) {
      return '確認資訊不正確，請重新輸入 DELETE 再試一次。';
    }

    if (_containsAny(normalized, [
      'network',
      'timeout',
      'socket',
      'failed host lookup',
      'connection',
    ])) {
      return '網路不太穩，請稍後再試一次。';
    }

    if (_containsAny(normalized, [
      'not logged in',
      'unauthorized',
      'auth',
      'jwt',
      'session',
    ])) {
      return '登入狀態已失效，請重新登入後再試。';
    }

    return '現在還不能刪除帳號，請稍後再試一次。';
  }

  String _mapLogoutError(Object error) {
    final normalized = error.toString().toLowerCase();

    if (_containsAny(normalized, [
      'network',
      'timeout',
      'socket',
      'failed host lookup',
      'connection',
    ])) {
      return '目前無法順利登出，請檢查網路後再試一次。';
    }

    return '登出時出了點問題，請再試一次。';
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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final restored =
          await ref.read(subscriptionProvider.notifier).restorePurchases();

      if (!context.mounted) {
        return;
      }

      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(restored ? '恢復購買成功' : '目前沒有可恢復的購買'),
          backgroundColor: restored ? AppColors.success : null,
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_mapRestorePurchasesError(error))),
      );
    }
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.glassWhite,
        title: Text(
          '確認登出',
          style: TextStyle(color: AppColors.glassTextPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              '取消',
              style: TextStyle(color: AppColors.unselectedText),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              '登出',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);

    try {
      await SupabaseService.signOut();
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      if (!SupabaseService.isAuthenticated) {
        ref.invalidate(subscriptionProvider);
        context.go('/login');
        messenger.showSnackBar(
          const SnackBar(content: Text('你已登出。若畫面還有異常，重新開啟 App 即可。')),
        );
        return;
      }

      messenger.showSnackBar(
        SnackBar(content: Text(_mapLogoutError(error))),
      );
      return;
    }

    ref.invalidate(subscriptionProvider);

    if (context.mounted) {
      context.go('/login');
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

    final messenger = ScaffoldMessenger.of(context);

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

      if (!context.mounted) {
        return;
      }

      Navigator.of(context, rootNavigator: true).pop();
      context.go('/login');
      messenger.showSnackBar(
        const SnackBar(
          content: Text('帳號已刪除'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      Navigator.of(context, rootNavigator: true).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(_mapDeleteAccountError(error)),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _launchUrl(String url) async {
    final launched = await LinkLaunchService.open(url);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('目前無法開啟連結，請稍後再試。')),
      );
    }
  }
}
