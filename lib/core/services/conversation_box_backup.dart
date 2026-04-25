import 'package:hive_ce/hive_ce.dart';

import '../../features/conversation/domain/entities/conversation.dart';
import 'conversation_box_backup_web.dart'
    if (dart.library.io) 'conversation_box_backup_native.dart'
    as conversation_box_backup;

Future<void> backupConversationBoxFile(Box<Conversation> box) {
  return conversation_box_backup.backupConversationBoxFile(box);
}
