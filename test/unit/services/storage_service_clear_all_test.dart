import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/core/constants/app_constants.dart';
import 'package:vibesync/core/services/storage_service.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation_summary.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/conversation/domain/entities/session_context.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_data_quality_state.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_style_override.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';

void main() {
  setUpAll(() {
    Hive.init('./.dart_tool/test_hive_storage_clear_all');
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ConversationAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(MessageAdapter());
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(ConversationSummaryAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(MeetingContextAdapter());
    }
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(AcquaintanceDurationAdapter());
    }
    if (!Hive.isAdapterRegistered(5)) Hive.registerAdapter(UserGoalAdapter());
    if (!Hive.isAdapterRegistered(6)) {
      Hive.registerAdapter(SessionContextAdapter());
    }
    if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(UserStyleAdapter());
    if (!Hive.isAdapterRegistered(8)) Hive.registerAdapter(PartnerAdapter());
    if (!Hive.isAdapterRegistered(9)) {
      Hive.registerAdapter(UserProfileAdapter());
    }
    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(InteractionStyleAdapter());
    }
    if (!Hive.isAdapterRegistered(11)) {
      Hive.registerAdapter(PracticeGoalAdapter());
    }
    if (!Hive.isAdapterRegistered(12)) Hive.registerAdapter(TopicSeedAdapter());
    if (!Hive.isAdapterRegistered(13)) {
      Hive.registerAdapter(PartnerStyleOverrideAdapter());
    }
    if (!Hive.isAdapterRegistered(14)) {
      Hive.registerAdapter(PartnerDataQualityStateAdapter());
    }
    if (!Hive.isAdapterRegistered(15)) {
      Hive.registerAdapter(NamePairAdapter());
    }
  });

  tearDown(() async {
    await Hive.deleteBoxFromDisk(AppConstants.conversationsBox);
    await Hive.deleteBoxFromDisk(AppConstants.partnersBox);
    await Hive.deleteBoxFromDisk('user_profile');
    await Hive.deleteBoxFromDisk('partner_style_overrides');
    await Hive.deleteBoxFromDisk('partner_data_quality_states');
    await Hive.deleteBoxFromDisk(AppConstants.settingsBox);
    await Hive.deleteBoxFromDisk(AppConstants.usageBox);
  });

  tearDownAll(() async {
    await Hive.close();
  });

  test('clearAll clears the About Me user_profile box too', () async {
    await Hive.openBox<Conversation>(AppConstants.conversationsBox);
    await Hive.openBox<Partner>(AppConstants.partnersBox);
    await Hive.openBox<UserProfile>('user_profile');
    await Hive.openBox<PartnerStyleOverride>('partner_style_overrides');
    await Hive.openBox<PartnerDataQualityState>(
      'partner_data_quality_states',
    );
    await Hive.openBox(AppConstants.settingsBox);
    await Hive.openBox(AppConstants.usageBox);

    final now = DateTime.utc(2026, 4, 30);
    await StorageService.userProfileBox.put(
      'profile:user-a',
      UserProfile.create(
        interactionStyle: InteractionStyle.gentle,
        notes: 'private About Me memo',
        updatedAt: now,
      ),
    );
    await StorageService.settingsBox.put('seen_onboarding', true);
    await StorageService.usageBox.put('monthly_count', 3);

    await StorageService.clearAll();

    expect(StorageService.userProfileBox.isEmpty, isTrue);
    expect(StorageService.settingsBox.isEmpty, isTrue);
    expect(StorageService.usageBox.isEmpty, isTrue);
  });

  test('clearAll also clears the partner_style_overrides box (Spec 2)',
      () async {
    await Hive.openBox<Conversation>(AppConstants.conversationsBox);
    await Hive.openBox<Partner>(AppConstants.partnersBox);
    await Hive.openBox<UserProfile>('user_profile');
    await Hive.openBox<PartnerStyleOverride>('partner_style_overrides');
    await Hive.openBox<PartnerDataQualityState>(
      'partner_data_quality_states',
    );
    await Hive.openBox(AppConstants.settingsBox);
    await Hive.openBox(AppConstants.usageBox);

    await StorageService.partnerStyleOverridesBox.put(
      'p1',
      PartnerStyleOverride.create(
        partnerId: 'p1',
        interactionStyle: InteractionStyle.steady,
        updatedAt: DateTime.utc(2026, 5, 1),
      ),
    );
    expect(StorageService.partnerStyleOverridesBox.isNotEmpty, isTrue);

    await StorageService.clearAll();

    expect(StorageService.partnerStyleOverridesBox.isEmpty, isTrue);
  });

  test('clearAll() purges partner_data_quality_states box', () async {
    await Hive.openBox<Conversation>(AppConstants.conversationsBox);
    await Hive.openBox<Partner>(AppConstants.partnersBox);
    await Hive.openBox<UserProfile>('user_profile');
    await Hive.openBox<PartnerStyleOverride>('partner_style_overrides');
    await Hive.openBox<PartnerDataQualityState>(
      'partner_data_quality_states',
    );
    await Hive.openBox(AppConstants.settingsBox);
    await Hive.openBox(AppConstants.usageBox);

    await StorageService.partnerDataQualityStatesBox.put(
      'p1',
      PartnerDataQualityState.empty(
        'p1',
        updatedAt: DateTime.utc(2026, 5, 1),
      ),
    );
    expect(StorageService.partnerDataQualityStatesBox.isNotEmpty, isTrue);

    await StorageService.clearAll();

    expect(StorageService.partnerDataQualityStatesBox.isEmpty, isTrue);
  });
}
