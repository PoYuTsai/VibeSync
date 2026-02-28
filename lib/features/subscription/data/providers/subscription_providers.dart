// lib/features/subscription/data/providers/subscription_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/supabase_service.dart';

/// 訂閱狀態
class SubscriptionState {
  final String tier;
  final int monthlyMessagesUsed;
  final int dailyMessagesUsed;
  final int monthlyLimit;
  final int dailyLimit;
  final bool isLoading;
  final String? error;

  const SubscriptionState({
    this.tier = 'free',
    this.monthlyMessagesUsed = 0,
    this.dailyMessagesUsed = 0,
    this.monthlyLimit = 30,
    this.dailyLimit = 15,
    this.isLoading = false,
    this.error,
  });

  bool get isFreeUser => tier == 'free';
  bool get isStarter => tier == 'starter';
  bool get isEssential => tier == 'essential';
  bool get isPremium => tier == 'starter' || tier == 'essential';

  int get monthlyRemaining => monthlyLimit - monthlyMessagesUsed;
  int get dailyRemaining => dailyLimit - dailyMessagesUsed;

  SubscriptionState copyWith({
    String? tier,
    int? monthlyMessagesUsed,
    int? dailyMessagesUsed,
    int? monthlyLimit,
    int? dailyLimit,
    bool? isLoading,
    String? error,
  }) {
    return SubscriptionState(
      tier: tier ?? this.tier,
      monthlyMessagesUsed: monthlyMessagesUsed ?? this.monthlyMessagesUsed,
      dailyMessagesUsed: dailyMessagesUsed ?? this.dailyMessagesUsed,
      monthlyLimit: monthlyLimit ?? this.monthlyLimit,
      dailyLimit: dailyLimit ?? this.dailyLimit,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// 訂閱 Provider
class SubscriptionNotifier extends StateNotifier<SubscriptionState> {
  SubscriptionNotifier() : super(const SubscriptionState(isLoading: true)) {
    _loadSubscription();
  }

  static const _tierLimits = {
    'free': {'monthly': 30, 'daily': 15},
    'starter': {'monthly': 300, 'daily': 50},
    'essential': {'monthly': 1000, 'daily': 150},
  };

  Future<void> _loadSubscription() async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) {
        state = const SubscriptionState(error: 'Not logged in');
        return;
      }

      final response = await SupabaseService.client
          .from('subscriptions')
          .select()
          .eq('user_id', user.id)
          .single();

      final tier = response['tier'] as String? ?? 'free';
      final limits = _tierLimits[tier] ?? _tierLimits['free']!;

      state = SubscriptionState(
        tier: tier,
        monthlyMessagesUsed: response['monthly_messages_used'] as int? ?? 0,
        dailyMessagesUsed: response['daily_messages_used'] as int? ?? 0,
        monthlyLimit: limits['monthly']!,
        dailyLimit: limits['daily']!,
        isLoading: false,
      );
    } catch (e) {
      state = SubscriptionState(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    await _loadSubscription();
  }
}

final subscriptionProvider =
    StateNotifierProvider<SubscriptionNotifier, SubscriptionState>((ref) {
  return SubscriptionNotifier();
});
