// lib/features/conversation/domain/entities/conversation.dart
import 'package:hive/hive.dart';
import 'message.dart';
import 'session_context.dart';

part 'conversation.g.dart';

@HiveType(typeId: 0)
class Conversation extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String? avatarPath;

  @HiveField(3)
  List<Message> messages;

  @HiveField(4)
  final DateTime createdAt;

  @HiveField(5)
  DateTime updatedAt;

  @HiveField(6)
  int? lastEnthusiasmScore;

  // v1.1 新增：Session 情境
  @HiveField(7)
  SessionContext? sessionContext;

  // v1.1 新增：當前 GAME 階段
  @HiveField(8)
  String? currentGameStage;

  Conversation({
    required this.id,
    required this.name,
    this.avatarPath,
    required this.messages,
    required this.createdAt,
    required this.updatedAt,
    this.lastEnthusiasmScore,
    this.sessionContext,
    this.currentGameStage,
  });

  Message? get lastMessage => messages.isNotEmpty ? messages.last : null;

  List<Message> get theirMessages =>
      messages.where((m) => !m.isFromMe).toList();
}
