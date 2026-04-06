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
          title: Text('Settings', style: AppTypography.titleLarge),
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
                  title: 'Plan and account',
                  children: [
                    _buildTile(
                      icon: Icons.workspace_premium,
                      title: 'Current plan',
                      trailing: _tierLabel(subscription.tier),
                      onTap: () {
                        context.push('/paywall');
                      },
                    ),
                    _buildTile(
                      icon: Icons.today,
                      title: 'Daily left',
                      trailing:
                          '${subscription.dailyRemaining}/${subscription.dailyLimit}',
                    ),
                    _buildTile(
                      icon: Icons.calendar_month,
                      title: 'Monthly left',
                      trailing:
                          '${subscription.monthlyRemaining}/${subscription.monthlyLimit}',
                    ),
                    _buildTile(
                      icon: Icons.analytics,
                      title: 'Monthly used',
                      trailing:
                          '${subscription.monthlyMessagesUsed}/${subscription.monthlyLimit}',
                    ),
                    _buildTile(
                      icon: Icons.person,
                      title: 'Account',
                      trailing: _accountLabel(),
                    ),
                    if (!kIsWeb)
                      _buildTile(
                        icon: Icons.subscriptions_outlined,
                        title: 'Manage App Store subscription',
                        onTap: () {
                          _openManageSubscriptions();
                        },
                      ),
                    if (!kIsWeb)
                      _buildTile(
                        icon: Icons.restore,
                        title: 'Restore purchases',
                        onTap: () {
                          _restorePurchases(context, ref);
                        },
                      ),
                  ],
                ),
                _buildSection(
                  title: 'Privacy and data',
                  children: [
                    _buildTile(
                      icon: Icons.delete_forever,
                      title: 'Delete account',
                      titleColor: AppColors.error,
                      onTap: () {
                        _confirmDeleteAccount(context, ref);
                      },
                    ),
                    _buildTile(
                      icon: Icons.privacy_tip,
                      title: 'Privacy policy',
                      onTap: () {
                        _launchUrl('https://vibesyncai.app/privacy');
                      },
                    ),
                  ],
                ),
                _buildSection(
                  title: 'More',
                  children: [
                    _buildTile(
                      icon: Icons.info,
                      title: 'Version',
                      trailing: _versionString.isNotEmpty
                          ? _versionString
                          : 'Loading...',
                    ),
                    _buildTile(
                      icon: Icons.description,
                      title: 'Terms',
                      onTap: () {
                        _launchUrl('https://vibesyncai.app/terms');
                      },
                    ),
                    _buildTile(
                      icon: Icons.feedback,
                      title: 'Support',
                      onTap: () {
                        _launchUrl('https://t.me/vibesync_feedback_bot');
                      },
                    ),
                    _buildTile(
                      icon: Icons.logout,
                      title: 'Sign out',
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
            'Current plan and quota',
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.glassTextPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Active plan: ${_tierLabel(subscription.tier)}',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.glassTextHint,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildUsagePill(
                  label: 'Monthly left',
                  value:
                      '${subscription.monthlyRemaining}/${subscription.monthlyLimit}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildUsagePill(
                  label: 'Daily left',
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
                  'Scheduled downgrade to ${_tierLabel(subscription.pendingDowngradeToTier)}',
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.glassTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'This will take effect on ${_formatDate(subscription.pendingDowngradeEffectiveAt)}. '
                  'Until then your current quota stays active.',
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
                    'Cancel or manage in App Store',
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
    if (dateTime == null) return 'next renewal';
    final local = dateTime.toLocal();
    return '${local.month}/${local.day}';
  }

  String _accountLabel() {
    final user = SupabaseService.currentUser;
    if (user == null) return 'Not signed in';

    final provider = user.appMetadata['provider'] as String?;
    if (provider == 'apple') {
      final fullName = user.userMetadata?['full_name'] as String?;
      final name = user.userMetadata?['name'] as String?;
      return fullName ?? name ?? 'Apple account';
    }

    return user.email ?? 'No email';
  }

  bool _containsAny(String source, List<String> patterns) {
    return patterns.any(source.contains);
  }

  String _mapRestoreError(Object error) {
    final normalized = error.toString().toLowerCase();
    if (_containsAny(
        normalized, ['network', 'timeout', 'socket', 'connection'])) {
      return 'Network error while restoring purchases.';
    }
    if (_containsAny(normalized, ['not logged in', 'unauthorized', 'auth'])) {
      return 'Session expired. Please sign in again.';
    }
    return 'Restore failed. Please try again.';
  }

  String _mapDeleteError(Object error) {
    final normalized = error.toString().toLowerCase();
    if (_containsAny(normalized, ['confirmation', 'mismatch'])) {
      return 'Confirmation text did not match DELETE.';
    }
    if (_containsAny(
        normalized, ['network', 'timeout', 'socket', 'connection'])) {
      return 'Network error while deleting the account.';
    }
    if (_containsAny(normalized, ['not logged in', 'unauthorized', 'auth'])) {
      return 'Session expired. Please sign in again.';
    }
    return 'Delete account failed. Please try again.';
  }

  String _mapLogoutError(Object error) {
    final normalized = error.toString().toLowerCase();
    if (_containsAny(
        normalized, ['network', 'timeout', 'socket', 'connection'])) {
      return 'Network error while signing out.';
    }
    return 'Sign out failed. Please try again.';
  }

  Future<void> _restorePurchases(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: AppColors.glassWhite,
            title: Text(
              'Restore purchases',
              style: TextStyle(color: AppColors.glassTextPrimary),
            ),
            content: Text(
              'Use this if this Apple ID already has a subscription and the app has not refreshed yet.',
              style: TextStyle(color: AppColors.glassTextSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: AppColors.unselectedText),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(
                  'Restore',
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
            restored
                ? 'Subscription status refreshed.'
                : 'No active subscription was found for this Apple ID.',
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
          'Confirm sign out',
          style: TextStyle(color: AppColors.glassTextPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.unselectedText),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Sign out',
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
            content: Text(
                'Signed out, but local cleanup had a minor issue. Please reopen the app.'),
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
            'Delete account',
            style: TextStyle(color: AppColors.glassTextPrimary),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This removes your account and local data. If you still have an App Store subscription, cancel auto-renew separately in Apple subscription management.',
                style: TextStyle(
                  color: AppColors.glassTextPrimary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Type DELETE to confirm',
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
                'Cancel',
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
              child: const Text('Delete'),
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
          content: Text('Account deleted.'),
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
        const SnackBar(content: Text('Could not open the link right now.')),
      );
    }
  }

  Future<void> _openManageSubscriptions() async {
    final managementUrl =
        await RevenueCatService.getManagementUrl() ?? _manageSubscriptionsUrl;
    final launched = await LinkLaunchService.open(managementUrl);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open App Store subscription management.'),
        ),
      );
    }
  }
}
