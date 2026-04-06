import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../core/services/revenuecat_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/services/usage_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/services/link_launch_service.dart';
import '../../../../shared/widgets/warm_theme_widgets.dart';
import '../../../conversation/data/providers/conversation_providers.dart';
import '../../data/providers/subscription_providers.dart';
import '../../domain/services/subscription_tier_helper.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const _manageSubscriptionsUrl =
      'https://apps.apple.com/account/subscriptions';

  String _versionString = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (!mounted) return;
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
                _buildUsageSummaryCard(subscription),
                if (subscription.hasPendingDowngrade) ...[
                  const SizedBox(height: 16),
                  _buildPendingDowngradeCard(subscription),
                ],
                _buildSection(
                  title: '方案與帳號',
                  children: [
                    _buildTile(
                      icon: Icons.workspace_premium,
                      title: '目前方案',
                      trailing: _tierLabel(subscription.tier),
                      onTap: () {
                        context.push('/paywall');
                      },
                    ),
                    _buildTile(
                      icon: Icons.today,
                      title: '今日剩餘',
                      trailing:
                          '${subscription.dailyRemaining}/${subscription.dailyLimit}',
                    ),
                    _buildTile(
                      icon: Icons.calendar_month,
                      title: '本月剩餘',
                      trailing:
                          '${subscription.monthlyRemaining}/${subscription.monthlyLimit}',
                    ),
                    _buildTile(
                      icon: Icons.analytics,
                      title: '本月已使用',
                      trailing:
                          '${subscription.monthlyMessagesUsed}/${subscription.monthlyLimit}',
                    ),
                    _buildTile(
                      icon: Icons.person,
                      title: '帳號',
                      trailing: _accountLabel(),
                    ),
                    if (!kIsWeb)
                      _buildTile(
                        icon: Icons.subscriptions_outlined,
                        title: '管理訂閱',
                        onTap: () {
                          _openManageSubscriptions();
                        },
                      ),
                    if (!kIsWeb)
                      _buildTile(
                        icon: Icons.restore,
                        title: '恢復購買',
                        onTap: () {
                          _restorePurchases(context, ref);
                        },
                      ),
                  ],
                ),
                _buildSection(
                  title: '隱私與資料',
                  children: [
                    _buildTile(
                      icon: Icons.delete_forever,
                      title: '刪除帳號',
                      titleColor: AppColors.error,
                      onTap: () {
                        _confirmDeleteAccount(context, ref);
                      },
                    ),
                    _buildTile(
                      icon: Icons.privacy_tip,
                      title: '隱私政策',
                      onTap: () {
                        _launchUrl('https://vibesyncai.app/privacy');
                      },
                    ),
                  ],
                ),
                _buildSection(
                  title: '其他',
                  children: [
                    _buildTile(
                      icon: Icons.info,
                      title: '版本',
                      trailing:
                          _versionString.isNotEmpty ? _versionString : '載入中...',
                    ),
                    _buildTile(
                      icon: Icons.description,
                      title: '服務條款',
                      onTap: () {
                        _launchUrl('https://vibesyncai.app/terms');
                      },
                    ),
                    _buildTile(
                      icon: Icons.feedback,
                      title: '客服與支援',
                      onTap: () {
                        _launchUrl('https://t.me/vibesync_feedback_bot');
                      },
                    ),
                    _buildTile(
                      icon: Icons.logout,
                      title: '登出',
                      titleColor: AppColors.error,
                      onTap: () {
                        _logout(context, ref);
                      },
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

  Widget _buildUsageSummaryCard(SubscriptionState subscription) {
    return GlassmorphicContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '目前方案與額度',
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.glassTextPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '目前方案：${_tierLabel(subscription.tier)}',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.glassTextHint,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildUsagePill(
                  label: '本月剩餘',
                  value:
                      '${subscription.monthlyRemaining}/${subscription.monthlyLimit}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildUsagePill(
                  label: '今日剩餘',
                  value:
                      '${subscription.dailyRemaining}/${subscription.dailyLimit}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUsagePill({
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: AppColors.glassTextHint,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.glassTextPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingDowngradeCard(SubscriptionState subscription) {
    return GlassmorphicContainer(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.event_repeat, color: AppColors.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '已排程降級到 ${_tierLabel(subscription.pendingDowngradeToTier)}',
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.glassTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '將於 ${_formatDate(subscription.pendingDowngradeEffectiveAt)} 生效。'
                  '在那之前目前額度仍會維持，今天不會再次扣款。',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.glassTextSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    _openManageSubscriptions();
                  },
                  child: Text(
                    '取消降級 / 管理訂閱',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
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

  String _tierLabel(String? tier) {
    switch (tier) {
      case SubscriptionTierHelper.starter:
        return 'Starter';
      case SubscriptionTierHelper.essential:
        return 'Essential';
      default:
        return 'Free';
    }
  }

  String _formatDate(DateTime? dateTime) {
    if (dateTime == null) return '下次續訂';
    final local = dateTime.toLocal();
    return '${local.month}/${local.day}';
  }

  String _accountLabel() {
    final user = SupabaseService.currentUser;
    if (user == null) return '尚未登入';

    final provider = user.appMetadata['provider'] as String?;
    if (provider == 'apple') {
      final fullName = user.userMetadata?['full_name'] as String?;
      final name = user.userMetadata?['name'] as String?;
      return fullName ?? name ?? 'Apple 帳號';
    }

    return user.email ?? '未提供 Email';
  }

  bool _containsAny(String source, List<String> patterns) {
    return patterns.any(source.contains);
  }

  String _mapRestoreError(Object error) {
    final normalized = error.toString().toLowerCase();
    if (_containsAny(
        normalized, ['network', 'timeout', 'socket', 'connection'])) {
      return '恢復購買時發生網路錯誤。';
    }
    if (_containsAny(normalized, ['not logged in', 'unauthorized', 'auth'])) {
      return '登入狀態已失效，請重新登入。';
    }
    return '恢復購買失敗，請稍後再試。';
  }

  String _mapDeleteError(Object error) {
    final normalized = error.toString().toLowerCase();
    if (_containsAny(normalized, ['confirmation', 'mismatch'])) {
      return '確認文字與 DELETE 不一致。';
    }
    if (_containsAny(
        normalized, ['network', 'timeout', 'socket', 'connection'])) {
      return '刪除帳號時發生網路錯誤。';
    }
    if (_containsAny(normalized, ['not logged in', 'unauthorized', 'auth'])) {
      return '登入狀態已失效，請重新登入。';
    }
    return '刪除帳號失敗，請稍後再試。';
  }

  String _mapLogoutError(Object error) {
    final normalized = error.toString().toLowerCase();
    if (_containsAny(
        normalized, ['network', 'timeout', 'socket', 'connection'])) {
      return '登出時發生網路錯誤。';
    }
    return '登出失敗，請稍後再試。';
  }

  Future<void> _restorePurchases(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: AppColors.glassWhite,
            title: Text(
              '恢復購買',
              style: TextStyle(color: AppColors.glassTextPrimary),
            ),
            content: Text(
              '如果這個 Apple ID 已經有訂閱，但 App 尚未更新狀態，可以在這裡重新同步。',
              style: TextStyle(color: AppColors.glassTextSecondary),
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
                  '恢復購買',
                  style: TextStyle(color: AppColors.primary),
                ),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final restored =
          await ref.read(subscriptionProvider.notifier).restorePurchases();
      if (!context.mounted) return;

      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            restored ? '訂閱狀態已更新。' : '這個 Apple ID 目前沒有可恢復的有效訂閱。',
          ),
          backgroundColor: restored ? AppColors.success : null,
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_mapRestoreError(error))),
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
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await SupabaseService.signOut();
      await UsageService.clearSnapshot();
    } catch (error) {
      if (!context.mounted) return;

      if (!SupabaseService.isAuthenticated) {
        await UsageService.clearSnapshot();
        ref.invalidate(subscriptionProvider);
        ref.invalidate(conversationsProvider);
        ref.invalidate(usageDataProvider);
        context.go('/login');
        messenger.showSnackBar(
          const SnackBar(
            content: Text('已完成登出，但本機清理時發生小問題，請重新開啟 App。'),
          ),
        );
        return;
      }

      messenger.showSnackBar(SnackBar(content: Text(_mapLogoutError(error))));
      return;
    }

    ref.invalidate(subscriptionProvider);
    ref.invalidate(conversationsProvider);
    ref.invalidate(usageDataProvider);
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
                '這會刪除你的帳號與本機資料。如果你仍有 App Store 訂閱，請另外到 Apple 訂閱管理中取消自動續訂。',
                style: TextStyle(
                  color: AppColors.glassTextPrimary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '輸入 DELETE 以確認',
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
                style: AppTypography.bodyLarge.copyWith(
                  color: AppColors.glassTextPrimary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
                decoration: InputDecoration(
                  hintText: 'DELETE',
                  hintStyle: AppTypography.bodyLarge.copyWith(
                    color: AppColors.glassTextHint,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
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
              style: TextButton.styleFrom(
                foregroundColor: AppColors.error,
                disabledForegroundColor:
                    AppColors.error.withValues(alpha: 0.35),
              ),
              child: const Text('刪除'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (confirmation == null || !context.mounted) return;

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
      ref.invalidate(conversationsProvider);
      ref.invalidate(usageDataProvider);
      if (!context.mounted) return;

      Navigator.of(context, rootNavigator: true).pop();
      context.go('/login');
      messenger.showSnackBar(
        const SnackBar(
          content: Text('帳號已刪除。'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(_mapDeleteError(error)),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _launchUrl(String url) async {
    final launched = await LinkLaunchService.open(url);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('目前無法開啟連結。')),
      );
    }
  }

  Future<void> _openManageSubscriptions() async {
    final openedNative =
        await RevenueCatService.showNativeManageSubscriptions();
    if (openedNative) {
      return;
    }

    final managementUrl =
        await RevenueCatService.getManagementUrl() ?? _manageSubscriptionsUrl;
    final launched = await LinkLaunchService.open(managementUrl);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('目前無法開啟 App Store 訂閱管理。'),
        ),
      );
    }
  }
}
