import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/core/constants/app_constants.dart';
import 'package:vibesync/core/services/storage_service.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation_summary.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/conversation/domain/entities/session_context.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
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
  });

  tearDown(() async {
    await Hive.deleteBoxFromDisk(AppConstants.conversationsBox);
    await Hive.deleteBoxFromDisk(AppConstants.partnersBox);
    await Hive.deleteBoxFromDisk('user_profile');
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
}
