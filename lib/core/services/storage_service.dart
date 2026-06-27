import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/coach_chat/domain/entities/coach_chat_result.dart';
import '../../features/coach_follow_up/domain/entities/coach_follow_up_result.dart';
import '../../features/coaching_memory/domain/entities/coaching_outcome_event.dart';
import '../../features/conversation/domain/entities/conversation.dart';
import '../../features/conversation/domain/entities/conversation_summary.dart';
import '../../features/conversation/domain/entities/message.dart';
import '../../features/conversation/domain/entities/session_context.dart';
import '../../features/practice_chat/data/repositories/practice_draw_draft_store.dart';
import '../../features/practice_chat/domain/entities/practice_message.dart';
import '../../features/practice_chat/domain/entities/practice_session.dart';
import '../../features/partner/data/repositories/partner_repository.dart';
import '../../features/partner/data/services/partner_migration_service.dart';
import '../../features/partner/domain/entities/partner.dart';
import '../../features/user_profile/domain/entities/partner_data_quality_state.dart';
import '../../features/user_profile/domain/entities/partner_style_override.dart';
import '../../features/user_profile/domain/entities/user_profile.dart';
import '../constants/app_constants.dart';
import 'conversation_box_backup.dart';

class StorageService {
  static const _encryptionKeyName = 'vibesync_encryption_key';
  static final _secureStorage = const FlutterSecureStorage();

  static Future<void> initialize() async {
    await Hive.initFlutter();

    // Register adapters
    Hive.registerAdapter(ConversationAdapter());
    Hive.registerAdapter(MessageAdapter());
    Hive.registerAdapter(SessionContextAdapter());
    Hive.registerAdapter(MeetingContextAdapter());
    Hive.registerAdapter(AcquaintanceDurationAdapter());
    Hive.registerAdapter(UserGoalAdapter());
    Hive.registerAdapter(UserStyleAdapter());
    Hive.registerAdapter(ConversationSummaryAdapter()); // v2.0: Memory feature
    Hive.registerAdapter(PartnerAdapter()); // A1: Partner Entity Refactor
    Hive.registerAdapter(UserProfileAdapter()); // typeId=9, Spec 1 About Me
    Hive.registerAdapter(InteractionStyleAdapter()); // typeId=10
    Hive.registerAdapter(PracticeGoalAdapter()); // typeId=11
    Hive.registerAdapter(TopicSeedAdapter()); // typeId=12
    Hive.registerAdapter(PartnerStyleOverrideAdapter()); // typeId=13, Spec 2
    Hive.registerAdapter(PartnerDataQualityStateAdapter()); // typeId=14, Spec 3
    Hive.registerAdapter(NamePairAdapter()); // typeId=15, Spec 3
    Hive.registerAdapter(CoachFollowUpResultAdapter()); // typeId=16, Spec 5
    Hive.registerAdapter(CoachChatResultAdapter()); // typeId=17, Spec 6A
    Hive.registerAdapter(CoachingOutcomeEventAdapter()); // typeId=18
    Hive.registerAdapter(CoachingOutcomeSourceAdapter()); // typeId=19
    Hive.registerAdapter(CoachingUserActionAdapter()); // typeId=20
    Hive.registerAdapter(CoachingOutcomeSignalAdapter()); // typeId=21
    Hive.registerAdapter(PracticeMessageAdapter()); // typeId=22, AI 實戰練習室
    Hive.registerAdapter(PracticeSessionAdapter()); // typeId=23, AI 實戰練習室

    // Get or create encryption key
    final encryptionKey = await _getEncryptionKey();

    // Open encrypted boxes
    await Hive.openBox<Conversation>(
      AppConstants.conversationsBox,
      encryptionCipher: HiveAesCipher(encryptionKey),
    );

    await Hive.openBox<Partner>(
      AppConstants.partnersBox,
      encryptionCipher: HiveAesCipher(encryptionKey),
    );

    await Hive.openBox<UserProfile>(
      'user_profile',
      encryptionCipher: HiveAesCipher(encryptionKey),
    );

    await Hive.openBox<PartnerStyleOverride>(
      'partner_style_overrides',
      encryptionCipher: HiveAesCipher(encryptionKey),
    );

    await Hive.openBox<PartnerDataQualityState>(
      'partner_data_quality_states',
      encryptionCipher: HiveAesCipher(encryptionKey),
    );

    await Hive.openBox<CoachFollowUpResult>(
      'coach_follow_up_results',
      encryptionCipher: HiveAesCipher(encryptionKey),
    );

    await Hive.openBox<CoachChatResult>(
      'coach_chat_results',
      encryptionCipher: HiveAesCipher(encryptionKey),
    );

    await Hive.openBox<CoachingOutcomeEvent>(
      AppConstants.coachingOutcomeEventsBox,
      encryptionCipher: HiveAesCipher(encryptionKey),
    );

    await Hive.openBox<PracticeSession>(
      'practice_sessions',
      encryptionCipher: HiveAesCipher(encryptionKey),
    );

    await Hive.openBox(
      AppConstants.settingsBox,
      encryptionCipher: HiveAesCipher(encryptionKey),
    );

    await Hive.openBox(
      AppConstants.usageBox,
      encryptionCipher: HiveAesCipher(encryptionKey),
    );

    // Partner Entity Refactor A1 — Migration runs once on first boot
    // after Partner box is open. Subsequent boots short-circuit on the
    // perf flag inside runIfNeeded.
    final prefs = await SharedPreferences.getInstance();
    final migration = PartnerMigrationService(
      conversationBox: conversationsBox,
      partnerRepo: PartnerRepository(box: partnersBox),
      prefs: prefs,
      backupConversationBox: _backupConversationBox,
    );
    await migration.runIfNeeded();
  }

  static Future<List<int>> _getEncryptionKey() async {
    final existingKey = await _secureStorage.read(key: _encryptionKeyName);

    if (existingKey != null) {
      return existingKey.codeUnits;
    }

    final newKey = Hive.generateSecureKey();
    await _secureStorage.write(
      key: _encryptionKeyName,
      value: String.fromCharCodes(newKey),
    );
    return newKey;
  }

  /// One-shot backup of the conversations Hive file used by the Partner
  /// migration (A1). Mobile-only; on Web `box.path` is unsupported and
  /// the backup is short-circuited so init does not crash.
  ///
  /// Throwing here intentionally aborts `runIfNeeded` (see
  /// `PartnerMigrationService._ensureBackup`) so the migration loop
  /// does not start without a backup. The next boot retries.
  static Future<void> _backupConversationBox() async {
    if (kIsWeb) {
      return; // Hive on Web has no real path; A1 is mobile-only.
    }
    await backupConversationBoxFile(conversationsBox);
  }

  static Box<Conversation> get conversationsBox =>
      Hive.box<Conversation>(AppConstants.conversationsBox);

  static Box<Partner> get partnersBox =>
      Hive.box<Partner>(AppConstants.partnersBox);

  static Box<UserProfile> get userProfileBox =>
      Hive.box<UserProfile>('user_profile');

  static Box<PartnerStyleOverride> get partnerStyleOverridesBox =>
      Hive.box<PartnerStyleOverride>('partner_style_overrides');

  static Box<PartnerDataQualityState> get partnerDataQualityStatesBox =>
      Hive.box<PartnerDataQualityState>('partner_data_quality_states');

  static Box<CoachFollowUpResult> get coachFollowUpResultsBox =>
      Hive.box<CoachFollowUpResult>('coach_follow_up_results');

  static Box<CoachChatResult> get coachChatResultsBox =>
      Hive.box<CoachChatResult>('coach_chat_results');

  static Box<CoachingOutcomeEvent> get coachingOutcomeEventsBox =>
      Hive.box<CoachingOutcomeEvent>(AppConstants.coachingOutcomeEventsBox);

  static Box<PracticeSession> get practiceSessionsBox =>
      Hive.box<PracticeSession>('practice_sessions');

  static Box get settingsBox => Hive.box(AppConstants.settingsBox);

  static Box get usageBox => Hive.box(AppConstants.usageBox);

  /// Clear practice-room state without touching unrelated settings.
  static Future<void> clearPracticeRoomState() async {
    await practiceSessionsBox.clear();
    await settingsBox.delete(HivePracticeDrawDraftStore.storageKey);
  }

  /// Clear all stored data (conversations, partners, user profile,
  /// partner style overrides, partner data quality states, coach follow-up /
  /// coach chat results, practice sessions, settings, usage).
  static Future<void> clearAll() async {
    await conversationsBox.clear();
    await partnersBox.clear();
    await userProfileBox.clear();
    await partnerStyleOverridesBox.clear();
    await partnerDataQualityStatesBox.clear();
    await coachFollowUpResultsBox.clear();
    await coachChatResultsBox.clear();
    await coachingOutcomeEventsBox.clear();
    await clearPracticeRoomState();
    await settingsBox.clear();
    await usageBox.clear();
  }

  /// Clear only conversation data
  static Future<void> clearConversations() async {
    await conversationsBox.clear();
  }
}
