// lib/features/conversation/domain/entities/conversation.dart
import 'package:hive_ce/hive_ce.dart';
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

  /// Serialized raw analysis response for restoring the latest analysis UI
  @HiveField(12)
  String? lastAnalysisSnapshotJson;

  /// Message count included in the latest persisted analysis
  @HiveField(13)
  int? lastAnalyzedMessageCount;

  /// Local owner used to isolate conversations between signed-in accounts
  @HiveField(14)
  String? ownerUserId;

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
    this.lastAnalysisSnapshotJson,
    this.lastAnalyzedMessageCount,
    this.ownerUserId,
  });

  Message? get lastMessage => messages.isNotEmpty ? messages.last : null;

  List<Message> get theirMessages =>
      messages.where((m) => !m.isFromMe).toList();

  /// Get recent N rounds of messages (for AI context)
  List<Message> getRecentMessages(int rounds) {
    if (rounds <= 0 || messages.isEmpty) {
      return const [];
    }

    final totalIncomingMessages =
        messages.where((message) => !message.isFromMe).length;
    if (totalIncomingMessages <= rounds) {
      return messages;
    }

    final roundsToSkip = totalIncomingMessages - rounds;
    var incomingSeen = 0;

    for (var i = 0; i < messages.length; i++) {
      if (!messages[i].isFromMe) {
        incomingSeen++;
        if (incomingSeen == roundsToSkip) {
          return messages.sublist(i + 1);
        }
      }
    }

    return messages;
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
