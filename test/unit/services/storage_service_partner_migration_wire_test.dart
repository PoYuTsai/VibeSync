import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation_summary.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/conversation/domain/entities/session_context.dart';
import 'package:vibesync/features/partner/data/repositories/partner_repository.dart';
import 'package:vibesync/features/partner/data/services/partner_migration_service.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';

/// Mirrors what StorageService.initialize() does end-to-end, but uses a
/// raw Hive.init() temp dir + SharedPreferences mock to skip the platform
/// secure-storage step. The point is to prove the wiring does not throw
/// on cold boot with a non-empty conversations box, and that the
/// migration converges in-process exactly like the unit tests claim.
void main() {
  setUpAll(() {
    Hive.init('./.dart_tool/test_hive_partner_wire');
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ConversationAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(MessageAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ConversationSummaryAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(MeetingContextAdapter());
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(AcquaintanceDurationAdapter());
    if (!Hive.isAdapterRegistered(5)) Hive.registerAdapter(UserGoalAdapter());
    if (!Hive.isAdapterRegistered(6)) Hive.registerAdapter(SessionContextAdapter());
    if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(UserStyleAdapter());
    if (!Hive.isAdapterRegistered(8)) Hive.registerAdapter(PartnerAdapter());
  });

  tearDownAll(() async {
    await Hive.close();
  });

  test(
      'cold boot with 1 legacy conversation + nil-backup hook → migration '
      'converges, no throw',
      () async {
    SharedPreferences.setMockInitialValues({});
    final ts = DateTime.now().microsecondsSinceEpoch;
    final convoBox = await Hive.openBox<Conversation>('wire_conv_$ts');
    final partnerBox = await Hive.openBox<Partner>('wire_partner_$ts');
    addTearDown(() async {
      await convoBox.deleteFromDisk();
      await partnerBox.deleteFromDisk();
    });

    final now = DateTime(2026, 4, 25);
    await convoBox.put(
      'c-1',
      Conversation(
        id: 'c-1',
        name: '糖糖',
        messages: const [],
        createdAt: now,
        updatedAt: now,
        ownerUserId: 'user-1',
      ),
    );

    final svc = PartnerMigrationService(
      conversationBox: convoBox,
      partnerRepo: PartnerRepository(box: partnerBox),
      prefs: await SharedPreferences.getInstance(),
      // Wiring uses File.copy on native; in this harness we skip backup
      // by passing a no-op so we don't depend on a real file path.
      backupConversationBox: () async {},
    );
    await svc.runIfNeeded();

    expect(partnerBox.length, 1);
    expect(convoBox.get('c-1')!.partnerId, isNotNull);
  });
}
