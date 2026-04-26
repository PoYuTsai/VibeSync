import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/core/constants/app_constants.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_repository.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation_summary.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/conversation/domain/entities/session_context.dart';

Conversation _convo({
  required String id,
  String? partnerId,
  String? ownerUserId = 'u-1',
  DateTime? updatedAt,
}) {
  final t = updatedAt ?? DateTime(2026, 4, 26, 10, 0);
  return Conversation(
    id: id,
    name: 'c-$id',
    messages: const [],
    createdAt: t,
    updatedAt: t,
    ownerUserId: ownerUserId,
    partnerId: partnerId,
  );
}

void main() {
  late Box<Conversation> convoBox;
  late ConversationRepository repo;

  setUpAll(() {
    Hive.init('./.dart_tool/test_hive_conv_repo_partner');
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ConversationAdapter());
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
  });

  tearDownAll(() async {
    await Hive.close();
  });

  setUp(() async {
    // listByPartner reads from StorageService.conversationsBox (the canonical
    // app-wide box name); open it here for the test scope.
    convoBox = await Hive.openBox<Conversation>(AppConstants.conversationsBox);
    repo = ConversationRepository();
  });

  tearDown(() async {
    await convoBox.deleteFromDisk();
  });

  group('ConversationRepository.listByPartner', () {
    test('returns only conversations with matching partnerId', () async {
      await convoBox.put('c1', _convo(id: 'c1', partnerId: 'p-X'));
      await convoBox.put('c2', _convo(id: 'c2', partnerId: 'p-Y'));
      await convoBox.put('c3', _convo(id: 'c3', partnerId: 'p-X'));

      final result = repo.listByPartner('p-X');

      expect(result.map((c) => c.id).toSet(), {'c1', 'c3'});
    });

    test('returns empty list when no conversation has partnerId', () async {
      await convoBox.put('c1', _convo(id: 'c1', partnerId: 'p-Y'));
      expect(repo.listByPartner('p-X'), isEmpty);
    });

    test('orphans (partnerId = null) are excluded', () async {
      await convoBox.put('c1', _convo(id: 'c1', partnerId: null));
      await convoBox.put('c2', _convo(id: 'c2', partnerId: 'p-X'));
      expect(repo.listByPartner('p-X').map((c) => c.id), ['c2']);
    });

    test('result sorted by updatedAt descending', () async {
      await convoBox.put('c-old',
          _convo(id: 'c-old', partnerId: 'p-X', updatedAt: DateTime(2026, 1, 1)));
      await convoBox.put('c-new',
          _convo(id: 'c-new', partnerId: 'p-X', updatedAt: DateTime(2026, 5, 1)));
      await convoBox.put('c-mid',
          _convo(id: 'c-mid', partnerId: 'p-X', updatedAt: DateTime(2026, 3, 1)));

      final result = repo.listByPartner('p-X');

      expect(result.map((c) => c.id).toList(), ['c-new', 'c-mid', 'c-old']);
    });
  });
}
