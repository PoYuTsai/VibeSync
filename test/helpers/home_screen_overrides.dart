// test/helpers/home_screen_overrides.dart
//
// Tier 2 批 1／批 2 後，PartnerListScreen 頂部掛了 HomeQuotaStrip 與
// GettingStartedChecklist。任何 pump 這個 screen 的測試都要 seed 這批
// 訊號 provider 保持封閉（不碰 Supabase／Hive／網路）。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibesync/features/analysis_history/domain/entities/analysis_history_event.dart';
import 'package:vibesync/features/follow_up_notification/data/follow_up_opt_in_store.dart';
import 'package:vibesync/features/follow_up_notification/data/providers/follow_up_notification_service.dart';
import 'package:vibesync/features/follow_up_notification/domain/follow_up_opt_in.dart';
import 'package:vibesync/features/report/data/providers/report_providers.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/user_profile/data/providers/user_profile_providers.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';

class SeededSubscriptionNotifier extends SubscriptionNotifier {
  SeededSubscriptionNotifier(SubscriptionState seed) {
    state = seed;
  }
}

class NullUserProfileController extends UserProfileController {
  @override
  Future<UserProfile?> build() async => null;
}

class FakeFollowUpOptInStore extends FollowUpOptInStore {
  FakeFollowUpOptInStore([this.state = FollowUpOptIn.unknown]);
  FollowUpOptIn state;

  @override
  FollowUpOptIn read() => state;

  @override
  Future<void> write(FollowUpOptIn value) async {
    state = value;
  }
}

/// 首頁（PartnerListScreen）測試用的標準訊號 seed。
List<Override> homeScreenSignalOverrides({
  SubscriptionState subscription = const SubscriptionState(),
}) =>
    [
      subscriptionProvider
          .overrideWith((_) => SeededSubscriptionNotifier(subscription)),
      subscriptionScreenRefreshProvider.overrideWithValue(() async {}),
      userProfileControllerProvider.overrideWith(NullUserProfileController.new),
      analysisHistoryEventsProvider
          .overrideWithValue(const <AnalysisHistoryEvent>[]),
      followUpOptInStoreProvider.overrideWithValue(FakeFollowUpOptInStore()),
    ];
