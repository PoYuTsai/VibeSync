import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/app/main_shell.dart';
import 'package:vibesync/core/theme/app_colors.dart';
import 'package:vibesync/core/theme/app_typography.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/partner/presentation/screens/partner_list_screen.dart';
import 'package:vibesync/features/analysis_history/domain/entities/analysis_history_event.dart';
import 'package:vibesync/features/follow_up_notification/data/follow_up_opt_in_store.dart';
import 'package:vibesync/features/follow_up_notification/data/providers/follow_up_notification_service.dart';
import 'package:vibesync/features/follow_up_notification/domain/follow_up_opt_in.dart';
import 'package:vibesync/features/report/data/providers/report_providers.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';
import 'package:vibesync/features/user_profile/data/providers/user_profile_providers.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';
import 'package:vibesync/shared/widgets/warm_theme_widgets.dart';

import 'proof_support.dart';

/// 同 onboarding_conversion proof：先載微軟正黑當 AppTC，單靠 loadProofFonts
/// 的 fc-match 路徑在部分環境會整頁豆腐字。絕不寫死單一本機路徑。
Future<void> _loadFonts() async {
  for (final path in const [
    '/mnt/c/Windows/Fonts/msjh.ttc',
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
  ]) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    await (FontLoader('AppTC')
          ..addFont(Future.value(ByteData.view(bytes.buffer))))
        .load();
    break;
  }
  await loadProofFonts();
}

/// Tier 2 批 1：首頁掛了 HomeQuotaStrip，proof 一律用 seeded 免費態
/// （7/30 已用）＋no-op 刷新，額度小條在截圖裡可見且不打網路。
class _SeededSubscriptionNotifier extends SubscriptionNotifier {
  _SeededSubscriptionNotifier(SubscriptionState seed) {
    state = seed;
  }
}

class _NullUserProfileController extends UserProfileController {
  @override
  Future<UserProfile?> build() async => null;
}

class _FakeOptInStore implements FollowUpOptInStore {
  @override
  FollowUpOptIn read() => FollowUpOptIn.unknown;

  @override
  Future<void> write(FollowUpOptIn value) async {}
}

List<Override> _subscriptionOverrides() => [
      subscriptionProvider.overrideWith(
        (_) => _SeededSubscriptionNotifier(
          const SubscriptionState(
            tier: SubscriptionTierHelper.free,
            monthlyMessagesUsed: 7,
            monthlyLimit: 30,
          ),
        ),
      ),
      subscriptionScreenRefreshProvider.overrideWithValue(() async {}),
      // 批 2 起步清單卡的訊號 seed：proof 呈現「一項未完成都沒有勾」態。
      userProfileControllerProvider
          .overrideWith(_NullUserProfileController.new),
      analysisHistoryEventsProvider
          .overrideWithValue(const <AnalysisHistoryEvent>[]),
      followUpOptInStoreProvider.overrideWithValue(_FakeOptInStore()),
    ];

Partner _p(String id, String name) => Partner(
      id: id,
      name: name,
      createdAt: DateTime(2026, 4, 20),
      updatedAt: DateTime(2026, 4, 20),
      ownerUserId: 'u-proof',
    );

PartnerAggregateView _agg({
  int? heat,
  List<String> interests = const [],
  List<String> traits = const [],
  int daysAgo = 5,
}) =>
    PartnerAggregateView(
      unionInterests: interests,
      unionTraits: traits,
      unionNotes: null,
      latestHeat: heat,
      totalRounds: heat == null ? 0 : 3,
      totalMessages: 0,
      lastInteraction: DateTime.now().subtract(Duration(days: daysAgo)),
    );

class _PartnerHomeProof extends StatelessWidget {
  const _PartnerHomeProof();

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          centerTitle: true,
          elevation: 0,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('VibeSync', style: AppTypography.headlineMedium),
              const SizedBox(width: 6),
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(top: 12),
                decoration: const BoxDecoration(
                  color: AppColors.ctaStart,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings, color: Colors.white),
              onPressed: () {},
            ),
          ],
        ),
        body: const PartnerListScreen(
          bottomPadding: 32.0 + homeFabReservedHeight,
        ),
        floatingActionButton: const HomeFab(),
        bottomNavigationBar: _ProofBottomNav(),
      ),
    );
  }
}

class _ProofBottomNav extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.brandInk.withValues(alpha: 0.94),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: const [
            _ProofTab(icon: Icons.home, label: '首頁', selected: true),
            _ProofTab(icon: Icons.bar_chart_outlined, label: '分析'),
            _ProofTab(icon: Icons.menu_book_outlined, label: '學習'),
          ],
        ),
      ),
    );
  }
}

class _ProofTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;

  const _ProofTab({
    required this.icon,
    required this.label,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 54, minHeight: 44),
      padding: EdgeInsets.symmetric(
        horizontal: selected ? 20 : 14,
        vertical: 11,
      ),
      decoration: selected
          ? BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.ctaStart, AppColors.ctaEnd],
              ),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            )
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color:
                selected ? Colors.white : Colors.white.withValues(alpha: 0.66),
            size: 22,
          ),
          if (selected) ...[
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('prod partner home', (tester) async {
    // 起步清單卡含「設定 AI 鍵盤」項僅 iOS 顯示，proof 以 iOS 呈現全貌。
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final partners = [
      _p('amy', 'Amy'),
      _p('jenny', 'Jenny'),
      _p('joyce', 'Joyce'),
      _p('nina', 'Nina'),
      _p('gigi', 'Gigi'),
      _p('tina', 'Tina'),
    ];

    await pumpAndCapture(
      tester,
      child: ProviderScope(
        overrides: [
          ..._subscriptionOverrides(),
          authConversationScopeProvider.overrideWith(
            (_) => Stream.value('u-proof'),
          ),
          partnerListProvider.overrideWith((_) => partners),
          partnerAggregateProvider('amy').overrideWith((_) => _agg()),
          partnerAggregateProvider('jenny').overrideWith((_) => _agg()),
          partnerAggregateProvider('joyce').overrideWith(
            (_) => _agg(
              heat: 68,
              interests: const ['茄汁牛肉飯'],
              traits: const ['喜歡碎碎念'],
            ),
          ),
          partnerAggregateProvider('nina').overrideWith(
            (_) => _agg(
              heat: 82,
              interests: const ['美食'],
              traits: const ['主動分享', '可愛自嘲'],
            ),
          ),
          partnerAggregateProvider('gigi').overrideWith(
            (_) => _agg(
              heat: 85,
              interests: const ['可愛小物'],
              traits: const ['活潑', 'QQ恐龍'],
            ),
          ),
          partnerAggregateProvider('tina').overrideWith(
            (_) => _agg(
              heat: 85,
              interests: const ['健身'],
              traits: const ['主動分享', '瑜伽'],
              daysAgo: 6,
            ),
          ),
          for (final partner in partners)
            conversationsByPartnerProvider(partner.id)
                .overrideWith((_) => const <Conversation>[]),
        ],
        child: const _PartnerHomeProof(),
      ),
      outPath: outPath('prod_partner_home.png'),
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('prod partner home — empty state with quota strip and entries',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await pumpAndCapture(
      tester,
      child: ProviderScope(
        overrides: [
          ..._subscriptionOverrides(),
          authConversationScopeProvider.overrideWith(
            (_) => Stream.value('u-proof'),
          ),
          partnerListProvider.overrideWith((_) => const <Partner>[]),
        ],
        child: const _PartnerHomeProof(),
      ),
      // 空態有 Sydney PNG，要留真 async 時間 decode，否則截圖是空框。
      rasterDecodeWait: const Duration(milliseconds: 600),
      outPath: outPath('prod_partner_home_empty.png'),
    );
    debugDefaultTargetPlatformOverride = null;
  });
}
