import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../core/config/environment.dart';
import '../../../../core/services/revenuecat_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/services/usage_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/services/link_launch_service.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../../conversation/data/providers/conversation_providers.dart';
import '../../../practice_chat/data/providers/practice_chat_providers.dart';
import '../../data/providers/subscription_providers.dart';
import '../../domain/services/subscription_tier_helper.dart';
import '../subscription_diagnostics_gate.dart';

@visibleForTesting
String formatSettingsRenewalDate(DateTime? dateTime, {DateTime? now}) {
  if (dateTime == null) return '--';

  final local = dateTime.toLocal();
  final localNow = (now ?? DateTime.now()).toLocal();
  final sameLocalDay = local.year == localNow.year &&
      local.month == localNow.month &&
      local.day == localNow.day;
  if (sameLocalDay) {
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '今天 $hour:$minute';
  }

  return '${local.year}/${local.month}/${local.day}';
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({
    super.key,
    this.accountDeletionActions = const DefaultAccountDeletionActions(),
    this.accountLogoutActions = const DefaultAccountLogoutActions(),
  });

  final AccountDeletionActions accountDeletionActions;
  final AccountLogoutActions accountLogoutActions;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

@visibleForTesting
abstract class AccountDeletionActions {
  const AccountDeletionActions();

  Future<void> deleteAccount({required String confirmation});

  Future<void> clearLocalStorage();

  Future<void> clearLocalSessionAfterDeletion();
}

class DefaultAccountDeletionActions extends AccountDeletionActions {
  const DefaultAccountDeletionActions();

  @override
  Future<void> deleteAccount({required String confirmation}) {
    return SupabaseService.deleteAccount(confirmation: confirmation);
  }

  @override
  Future<void> clearLocalStorage() {
    return StorageService.clearAll();
  }

  @override
  Future<void> clearLocalSessionAfterDeletion() {
    return SupabaseService.clearLocalSessionAfterDeletion();
  }
}

@visibleForTesting
abstract class AccountLogoutActions {
  const AccountLogoutActions();

  bool get isAuthenticated;

  Future<void> signOut();

  Future<void> clearUsageSnapshot();

  Future<void> clearPracticeRoomState();
}

class DefaultAccountLogoutActions extends AccountLogoutActions {
  const DefaultAccountLogoutActions();

  @override
  bool get isAuthenticated => SupabaseService.isAuthenticated;

  @override
  Future<void> signOut() {
    return SupabaseService.signOut();
  }

  @override
  Future<void> clearUsageSnapshot() {
    return UsageService.clearSnapshot();
  }

  @override
  Future<void> clearPracticeRoomState() {
    return StorageService.clearPracticeRoomState();
  }
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const _manageSubscriptionsUrl =
      'https://apps.apple.com/account/subscriptions';
  static const _supportEmail = 'vibesyncaiapp@gmail.com';

  String _versionString = '';
  bool _isRefreshingSubscription = true;
  bool _isRefreshingPendingDowngrade = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_refreshSubscriptionOnEntry());
    });
  }

  Future<void> _loadVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _versionString = '${packageInfo.version} (${packageInfo.buildNumber})';
    });
  }

  Future<void> _refreshSubscriptionOnEntry() async {
    setState(() {
      _isRefreshingSubscription = true;
    });
    try {
      await ref.read(subscriptionScreenRefreshProvider)();
    } catch (error) {
      debugPrint('Settings subscription refresh error: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingSubscription = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final subscription = ref.watch(subscriptionProvider);

    return BrandScaffold(
      title: '設定',
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => context.pop(),
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
                    trailing:
                        '${_tierLabel(subscription.tier)}${_billingPeriodLabel(subscription)}',
                    onTap: () {
                      context.push('/paywall');
                    },
                  ),
                  if (subscription.renewsAt != null && !subscription.isFreeUser)
                    _buildTile(
                      icon: Icons.event,
                      title: '下次續約',
                      trailing: _isRefreshingSubscription
                          ? '確認中...'
                          : _formatDate(subscription.renewsAt),
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
                  if (SubscriptionDiagnosticsGate.isVisible)
                    _buildTile(
                      icon: Icons.bug_report_outlined,
                      title: '複製訂閱診斷',
                      onTap: _copySubscriptionDiagnostics,
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
                    title: 'App 版本',
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
                      _openSupportEmail();
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
    );
  }

  Widget _buildUsageSummaryCard(SubscriptionState subscription) {
    return BrandSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '目前方案與額度',
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.onBackgroundPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '目前方案：${_tierLabel(subscription.tier)}${_billingPeriodLabel(subscription)}',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.7),
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
        color: AppColors.brandInk.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.onBackgroundPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingDowngradeCard(SubscriptionState subscription) {
    return BrandSurfaceCard(
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
                    color: AppColors.onBackgroundPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '將於 ${_formatDate(subscription.pendingDowngradeEffectiveAt)} 生效。'
                  '在那之前目前額度仍會維持，今天不會再次扣款。',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.onBackgroundSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    TextButton(
                      onPressed: () {
                        _openManageSubscriptions();
                      },
                      child: Text(
                        '取消降級 / 管理訂閱',
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.ctaStart,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _isRefreshingPendingDowngrade
                          ? null
                          : _refreshAfterExternalDowngradeCancel,
                      child: Text(
                        _isRefreshingPendingDowngrade
                            ? '同步中...'
                            : '我已取消降級，更新狀態',
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.onBackgroundPrimary,
                        ),
                      ),
                    ),
                  ],
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
        BrandSurfaceCard(
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
      leading: Icon(icon,
          color: titleColor ??
              AppColors.onBackgroundSecondary.withValues(alpha: 0.7)),
      title: Text(
        title,
        style: AppTypography.bodyLarge.copyWith(
          color: titleColor ?? AppColors.onBackgroundPrimary,
        ),
      ),
      trailing: trailing != null
          ? Text(
              trailing,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.onBackgroundSecondary.withValues(alpha: 0.7),
              ),
            )
          : Icon(Icons.chevron_right,
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.7)),
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
    return formatSettingsRenewalDate(dateTime);
  }

  String _billingPeriodLabel(SubscriptionState subscription) {
    if (subscription.isFreeUser) return '';
    final productId = subscription.activeProductId ?? '';
    if (productId.contains('quarterly')) return '（季繳）';
    if (productId.contains('monthly')) return '（月繳）';
    return '';
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

  void _invalidateAccountScopedProviders(WidgetRef ref) {
    ref.invalidate(subscriptionProvider);
    ref.invalidate(conversationsProvider);
    ref.invalidate(usageDataProvider);
    ref.invalidate(practiceChatControllerProvider);
    ref.invalidate(recentPracticeSessionsProvider);
  }

  Future<void> _clearLocalLogoutState() async {
    Object? cleanupError;

    try {
      await widget.accountLogoutActions.clearUsageSnapshot();
    } catch (error) {
      cleanupError = error;
    }

    try {
      await widget.accountLogoutActions.clearPracticeRoomState();
    } catch (error) {
      cleanupError ??= error;
    }

    if (cleanupError == null) return;
    if (cleanupError is Exception) throw cleanupError;
    throw Exception(cleanupError.toString());
  }

  Future<void> _restorePurchases(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: AppColors.brandSurface2,
            title: Text(
              '恢復購買',
              style: TextStyle(color: AppColors.onBackgroundPrimary),
            ),
            content: Text(
              '如果這個 Apple ID 已經有訂閱，但 App 尚未更新狀態，可以在這裡重新同步。',
              style: TextStyle(color: AppColors.onBackgroundSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(
                  '取消',
                  style: TextStyle(color: AppColors.onBackgroundSecondary),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(
                  '恢復購買',
                  style: TextStyle(color: AppColors.ctaStart),
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
        backgroundColor: AppColors.brandSurface2,
        title: Text(
          '確認登出',
          style: TextStyle(color: AppColors.onBackgroundPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              '取消',
              style: TextStyle(color: AppColors.onBackgroundSecondary),
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
      await widget.accountLogoutActions.signOut();
      await _clearLocalLogoutState();
    } catch (error) {
      if (!context.mounted) return;

      if (!widget.accountLogoutActions.isAuthenticated) {
        try {
          await _clearLocalLogoutState();
        } catch (cleanupError) {
          debugPrint('Logout local cleanup after sign-out: $cleanupError');
        }
        if (!context.mounted) return;
        _invalidateAccountScopedProviders(ref);
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

    _invalidateAccountScopedProviders(ref);
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
          backgroundColor: AppColors.brandSurface2,
          title: Text(
            '刪除帳號',
            style: TextStyle(color: AppColors.onBackgroundPrimary),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '這會刪除你的帳號與本機資料。如果你仍有 App Store 訂閱，請另外到 Apple 訂閱管理中取消自動續訂。',
                style: TextStyle(
                  color: AppColors.onBackgroundPrimary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '輸入 DELETE 以確認',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.onBackgroundPrimary,
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
                  color: AppColors.onBackgroundPrimary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
                decoration: InputDecoration(
                  hintText: 'DELETE',
                  hintStyle: AppTypography.bodyLarge.copyWith(
                    color:
                        AppColors.onBackgroundSecondary.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                  filled: true,
                  fillColor: AppColors.brandInk.withValues(alpha: 0.38),
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
                style: TextStyle(color: AppColors.onBackgroundSecondary),
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
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final router = GoRouter.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await widget.accountDeletionActions.deleteAccount(
        confirmation: confirmation,
      );
    } catch (error) {
      _dismissBlockingDialog(rootNavigator);
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(_mapDeleteError(error)),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // 遠端帳號已刪除：本機清理各自 best-effort，失敗只影響文案，
    // 絕不把「帳號已刪除」回報成刪除失敗。
    var localCleanupSucceeded = true;
    try {
      await widget.accountDeletionActions.clearLocalStorage();
    } catch (error) {
      localCleanupSucceeded = false;
      debugPrint('Delete-account local storage cleanup failed: $error');
    }
    try {
      await widget.accountDeletionActions.clearLocalSessionAfterDeletion();
    } catch (error) {
      localCleanupSucceeded = false;
      debugPrint('Delete-account session clear failed: $error');
    }
    _invalidateAccountScopedProviders(ref);

    _dismissBlockingDialog(rootNavigator);
    router.go('/login');
    messenger.showSnackBar(
      localCleanupSucceeded
          ? const SnackBar(
              content: Text('帳號已刪除。'),
              backgroundColor: AppColors.success,
            )
          : const SnackBar(
              content: Text('帳號已刪除，但本機清理未完成，請重新開啟 App。'),
            ),
    );
  }

  void _dismissBlockingDialog(NavigatorState rootNavigator) {
    if (rootNavigator.mounted && rootNavigator.canPop()) {
      rootNavigator.pop();
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

  Future<void> _copySubscriptionDiagnostics() async {
    final subscription = ref.read(subscriptionProvider);
    final usage = UsageService().getLocalUsage();
    final user = SupabaseService.currentUser;
    final revenueCat = await RevenueCatService.buildDebugSnapshot();

    final payload = <String, Object?>{
      'generatedAt': DateTime.now().toIso8601String(),
      'app': {
        'version': _versionString.isNotEmpty ? _versionString : 'unknown',
        'gitSha': AppConfig.gitSha,
        'environment': AppConfig.environmentName,
      },
      'supabase': {
        'userId': user?.id,
        'email': user?.email,
        'provider': user?.appMetadata['provider'],
      },
      'subscriptionState': {
        'tier': subscription.tier,
        'monthlyUsed': subscription.monthlyMessagesUsed,
        'monthlyLimit': subscription.monthlyLimit,
        'dailyUsed': subscription.dailyMessagesUsed,
        'dailyLimit': subscription.dailyLimit,
        'renewsAt': subscription.renewsAt?.toIso8601String(),
        'activeProductId': subscription.activeProductId,
      },
      'usageSnapshot': {
        'tier': usage.tier,
        'monthlyUsed': usage.monthlyUsed,
        'monthlyLimit': usage.monthlyLimit,
        'dailyUsed': usage.dailyUsed,
        'dailyLimit': usage.dailyLimit,
      },
      'revenueCat': revenueCat,
    };

    final text = const JsonEncoder.withIndent('  ').convert(payload);
    await Clipboard.setData(ClipboardData(text: text));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('訂閱診斷已複製')),
    );
  }

  Future<void> _openSupportEmail() async {
    final subscription = ref.read(subscriptionProvider);
    final body = [
      '請簡單描述你遇到的問題：',
      '',
      '問題類型：帳號 / 付款 / 額度 / OCR / AI 回覆 / 其他',
      '帳號：${_accountLabel()}',
      '目前方案：${_tierLabel(subscription.tier)}${_billingPeriodLabel(subscription)}',
      'App 版本：${_versionString.isNotEmpty ? _versionString : '未知'}',
      '',
      '問題描述：',
    ].join('\n');
    final uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      queryParameters: {
        'subject': 'VibeSync 客服與支援',
        'body': body,
      },
    );
    await _launchUrl(uri.toString());
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

  Future<void> _refreshAfterExternalDowngradeCancel() async {
    if (_isRefreshingPendingDowngrade) return;

    setState(() => _isRefreshingPendingDowngrade = true);
    try {
      final didClear = await ref
          .read(subscriptionProvider.notifier)
          .clearPendingDowngradeMetadata();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            didClear ? '已重新同步訂閱狀態。' : 'App Store 仍顯示降級排程，請確認取消後稍後再試。',
          ),
          backgroundColor: didClear ? AppColors.success : null,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('同步失敗，請稍後再試。')),
      );
    } finally {
      if (mounted) {
        setState(() => _isRefreshingPendingDowngrade = false);
      }
    }
  }
}
