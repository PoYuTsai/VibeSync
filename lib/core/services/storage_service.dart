// lib/core/services/storage_service.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import '../../features/conversation/domain/entities/conversation.dart';
import '../../features/conversation/domain/entities/conversation_summary.dart';
import '../../features/conversation/domain/entities/message.dart';
import '../../features/conversation/domain/entities/session_context.dart';
import '../constants/app_constants.dart';

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
    Hive.registerAdapter(ConversationSummaryAdapter()); // v2.0: Memory feature

    // Get or create encryption key
    final encryptionKey = await _getEncryptionKey();

    // Open encrypted boxes
    await Hive.openBox<Conversation>(
      AppConstants.conversationsBox,
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

  static Box<Conversation> get conversationsBox =>
      Hive.box<Conversation>(AppConstants.conversationsBox);

  static Box get settingsBox => Hive.box(AppConstants.settingsBox);

  static Box get usageBox => Hive.box(AppConstants.usageBox);

  /// Clear all stored data (conversations, settings, usage)
  static Future<void> clearAll() async {
    await conversationsBox.clear();
    await settingsBox.clear();
    await usageBox.clear();
  }

  /// Clear only conversation data
  static Future<void> clearConversations() async {
    await conversationsBox.clear();
  }
}
