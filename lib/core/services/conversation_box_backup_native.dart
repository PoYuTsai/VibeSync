import 'dart:io' show File;

import 'package:hive_ce/hive_ce.dart';

import '../../features/conversation/domain/entities/conversation.dart';

Future<void> backupConversationBoxFile(Box<Conversation> box) async {
  final source = box.path;
  if (source == null) {
    return;
  }

  final backup = File('$source.partner_migration_backup');
  await File(source).copy(backup.path);
}
