// lib/features/conversation/domain/entities/message.dart
import 'package:hive_ce/hive_ce.dart';

part 'message.g.dart';

@HiveType(typeId: 1)
class Message extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String content;

  @HiveField(2)
  final bool isFromMe;

  @HiveField(3)
  final DateTime timestamp;

  @HiveField(4)
  int? enthusiasmScore;

  @HiveField(5)
  final String? quotedReplyPreview;

  Message({
    required this.id,
    required this.content,
    required this.isFromMe,
    required this.timestamp,
    this.enthusiasmScore,
    this.quotedReplyPreview,
  });

  int get wordCount => content.length;
}
