// lib/features/conversation/domain/entities/conversation.dart
import 'package:hive/hive.dart';
import 'conversation_summary.dart';
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

  // v2.0 新增：對話記憶
  /// Current round number (1 round = 1 exchange between user and them)
  @HiveField(9)
  int currentRound;

  /// Historical summaries of older messages
  @HiveField(10)
  List<ConversationSummary>? summaries;

  /// Last reply type chosen by user (for choice tracking)
  @HiveField(11)
  String? lastUserChoice;

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
    this.currentRound = 0,
    this.summaries,
    this.lastUserChoice,
  });

  Message? get lastMessage => messages.isNotEmpty ? messages.last : null;

  List<Message> get theirMessages =>
      messages.where((m) => !m.isFromMe).toList();

  /// Get recent N rounds of messages (for AI context)
  /// Each round is approximately 2 messages (user + them)
  List<Message> getRecentMessages(int rounds) {
    final messageCount = rounds * 2;
    if (messages.length <= messageCount) return messages;
    return messages.sublist(messages.length - messageCount);
  }

  /// Whether this conversation needs summarization
  /// Triggered when over 15 rounds and no existing summary
  bool get needsSummary => currentRound > 15 && (summaries?.isEmpty ?? true);

  /// Increment round count when a new exchange is completed
  void incrementRound() {
    currentRound++;
  }

  /// Add a summary to history
  void addSummary(ConversationSummary summary) {
    summaries ??= [];
    summaries!.add(summary);
  }
}
