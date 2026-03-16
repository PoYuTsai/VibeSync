import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/conversation.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/entities/message.dart';

/// Service for managing conversation memory and context.
class MemoryService {
  /// Maximum rounds to keep as full messages when building AI context.
  static const int maxRecentRounds = 15;

  /// Minimum older rounds before we create a summary segment.
  static const int minRoundsPerSummary = 5;

  static const Set<String> _stopWords = {
    'the',
    'and',
    'for',
    'with',
    'that',
    'this',
    'have',
    'just',
    'really',
    'about',
    '你們',
    '我們',
    '你我',
    '就是',
    '真的',
    '可以',
    '一下',
    '然後',
    '因為',
    '如果',
    '那個',
    '這個',
    '一個',
    '今天',
    '昨天',
    '明天',
    '哈哈',
    '欸欸',
  };

  /// Prepare AI analysis context.
  String prepareContext(Conversation conversation) {
    final buffer = StringBuffer();

    if (conversation.sessionContext != null) {
      final ctx = conversation.sessionContext!;
      buffer.writeln('Session context:');
      buffer.writeln('Meeting context: ${_enumToLabel(ctx.meetingContext)}');
      buffer.writeln('Duration: ${_enumToLabel(ctx.duration)}');
      buffer.writeln('Goal: ${_enumToLabel(ctx.goal)}');
      buffer.writeln('---');
    }

    if (conversation.summaries?.isNotEmpty ?? false) {
      buffer.writeln('Historical summaries:');
      for (final summary in conversation.summaries!) {
        buffer.writeln(summary.content);
        if (summary.keyTopics.isNotEmpty) {
          buffer.writeln('Topics: ${summary.keyTopics.join(", ")}');
        }
        if (summary.sharedInterests.isNotEmpty) {
          buffer.writeln(
              'Shared interests: ${summary.sharedInterests.join(", ")}');
        }
      }
      buffer.writeln('---');
    }

    final recentMessages = conversation.getRecentMessages(maxRecentRounds);
    if (recentMessages.isNotEmpty) {
      buffer.writeln('Recent messages:');
      for (final msg in recentMessages) {
        buffer.writeln('${msg.isFromMe ? "Me" : "Her"}: ${msg.content}');
      }
    }

    return buffer.toString();
  }

  /// Build a compact summary string for older context that has already been
  /// distilled into historical summary segments.
  String? buildHistoricalSummary(Conversation conversation) {
    final summaries = conversation.summaries
        ?.where((summary) => summary.content.trim().isNotEmpty)
        .toList();
    if (summaries == null || summaries.isEmpty) {
      return null;
    }

    return formatSummarySegments(summaries);
  }

  String formatSummarySegments(Iterable<ConversationSummary> summaries) {
    final nonEmptySummaries =
        summaries.where((summary) => summary.content.trim().isNotEmpty).toList();
    if (nonEmptySummaries.isEmpty) {
      return '';
    }

    final summarizedRounds = summaries.fold<int>(
      0,
      (total, summary) => total + summary.roundsCovered,
    );
    final buffer = StringBuffer()
      ..writeln('Older context summary (covers $summarizedRounds rounds):');

    for (final summary in nonEmptySummaries) {
      buffer.writeln('- ${summary.content}');
      if (summary.keyTopics.isNotEmpty) {
        buffer.writeln('  Topics: ${summary.keyTopics.join(", ")}');
      }
      if (summary.sharedInterests.isNotEmpty) {
        buffer.writeln(
          '  Shared interests: ${summary.sharedInterests.join(", ")}',
        );
      }
      if (summary.relationshipStage.trim().isNotEmpty) {
        buffer.writeln('  Stage: ${summary.relationshipStage}');
      }
    }

    return buffer.toString().trim();
  }

  /// Keep only the most recent incoming-message rounds from an arbitrary
  /// message slice. This matches how summaries are generated and avoids the old
  /// "2 messages = 1 round" assumption.
  List<Message> clipToRecentRounds(List<Message> messages, int roundLimit) {
    if (roundLimit <= 0 || messages.isEmpty) {
      return const <Message>[];
    }

    final totalIncomingMessages =
        messages.where((message) => !message.isFromMe).length;
    if (totalIncomingMessages <= roundLimit) {
      return messages;
    }

    final roundsToSkip = totalIncomingMessages - roundLimit;
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

  /// Infer which reply type user chose from the next incoming message.
  String? inferUserChoice(
    Message theirReply,
    Map<String, String> previousSuggestions,
  ) {
    final content = theirReply.content.toLowerCase();

    String? bestMatch;
    var bestScore = 0;

    for (final entry in previousSuggestions.entries) {
      final keywords = _extractKeywords(entry.value);
      var score = 0;

      for (final keyword in keywords) {
        if (content.contains(keyword.toLowerCase())) {
          score++;
        }
      }

      if (score > bestScore) {
        bestScore = score;
        bestMatch = entry.key;
      }
    }

    return bestScore >= 2 ? bestMatch : null;
  }

  /// Generate a heuristic summary for older messages.
  Future<ConversationSummary> generateSummary(
    Conversation conversation,
    int fromRound,
    int toRound,
  ) async {
    final safeFromRound = fromRound.clamp(0, toRound);
    final safeToRound = toRound.clamp(safeFromRound, conversation.currentRound);
    final segmentMessages = _messagesForRoundRange(
      conversation,
      safeFromRound,
      safeToRound,
    );
    final keyTopics = _extractTopicsFromSegment(segmentMessages);
    final sharedInterests = _extractSharedInterests(segmentMessages);

    return ConversationSummary(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      roundsCovered: safeToRound - safeFromRound,
      content: _buildSummaryContent(
        segmentMessages,
        safeFromRound,
        safeToRound,
        keyTopics,
        sharedInterests,
      ),
      keyTopics: keyTopics,
      sharedInterests: sharedInterests,
      relationshipStage: _guessRelationshipStageForRoundCount(safeToRound),
      createdAt: DateTime.now(),
    );
  }

  List<Message> messagesForRoundRange(
    Conversation conversation,
    int fromRound,
    int toRound,
  ) {
    return _messagesForRoundRange(conversation, fromRound, toRound);
  }

  List<String> extractTopicsFromMessages(
    Conversation conversation,
    int fromRound,
    int toRound,
  ) {
    return _extractTopicsFromMessages(conversation, fromRound, toRound);
  }

  List<Message> _messagesForRoundRange(
    Conversation conversation,
    int fromRound,
    int toRound,
  ) {
    if (toRound <= fromRound || conversation.messages.isEmpty) {
      return const [];
    }

    final startIndex = _indexAfterIncomingRound(
      conversation.messages,
      fromRound,
    );
    final endIndex = _indexAfterIncomingRound(
      conversation.messages,
      toRound,
    );

    if (startIndex < 0 || endIndex <= startIndex) {
      return const [];
    }

    return conversation.messages.sublist(startIndex, endIndex);
  }

  int _indexAfterIncomingRound(List<Message> messages, int roundCount) {
    if (roundCount <= 0) {
      return 0;
    }

    var incomingSeen = 0;
    for (var i = 0; i < messages.length; i++) {
      if (!messages[i].isFromMe) {
        incomingSeen++;
        if (incomingSeen == roundCount) {
          return i + 1;
        }
      }
    }

    return -1;
  }

  String _buildSummaryContent(
    List<Message> messages,
    int fromRound,
    int toRound,
    List<String> keyTopics,
    List<String> sharedInterests,
  ) {
    final displayFromRound = fromRound + 1;

    if (messages.isEmpty) {
      return 'Rounds $displayFromRound-$toRound had no usable messages to summarize.';
    }

    final myMessages = messages.where((message) => message.isFromMe).toList();
    final theirMessages =
        messages.where((message) => !message.isFromMe).toList();
    final questionCount =
        messages.where((message) => message.content.contains('?')).length;

    final parts = <String>[
      'Rounds $displayFromRound-$toRound covered ${messages.length} messages.',
      _describeBalance(myMessages.length, theirMessages.length),
    ];

    if (keyTopics.isNotEmpty) {
      parts.add('Main topics: ${keyTopics.join(", ")}.');
    }

    if (sharedInterests.isNotEmpty) {
      parts.add('Possible shared interests: ${sharedInterests.join(", ")}.');
    }

    if (questionCount > 0) {
      parts.add('Questions asked in this segment: $questionCount.');
    }

    return parts.join(' ');
  }

  String _describeBalance(int myCount, int theirCount) {
    if (myCount == 0 && theirCount == 0) {
      return 'No clear participation balance was detected.';
    }

    if (myCount == theirCount) {
      return 'The exchange stayed balanced between both sides.';
    }

    final moreActiveSide = myCount > theirCount ? 'The user' : 'The other side';
    final difference = (myCount - theirCount).abs();
    return '$moreActiveSide sent $difference more messages in this segment.';
  }

  /// Extract meaningful keywords from text.
  List<String> _extractKeywords(String text) {
    final cleaned = text.replaceAll(RegExp(r'[^\w\u4e00-\u9fff]'), ' ');

    return cleaned
        .split(RegExp(r'\s+'))
        .map((word) => word.trim())
        .where((word) => word.length > 1)
        .toSet()
        .toList();
  }

  List<String> _extractTopicsFromMessages(
    Conversation conversation,
    int fromRound,
    int toRound,
  ) {
    return _extractTopicsFromSegment(
      _messagesForRoundRange(conversation, fromRound, toRound),
    );
  }

  List<String> _extractTopicsFromSegment(List<Message> messages) {
    final wordCount = <String, int>{};

    for (final message in messages) {
      final keywords = _extractKeywords(message.content);
      for (final keyword in keywords) {
        final normalized = keyword.toLowerCase();
        if (normalized.length < 2 || _stopWords.contains(normalized)) {
          continue;
        }
        wordCount[normalized] = (wordCount[normalized] ?? 0) + 1;
      }
    }

    final sorted = wordCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted.take(5).map((entry) => entry.key).toList();
  }

  List<String> _extractSharedInterests(List<Message> messages) {
    final myKeywords = <String, int>{};
    final theirKeywords = <String, int>{};

    for (final message in messages) {
      final bucket = message.isFromMe ? myKeywords : theirKeywords;
      for (final keyword in _extractKeywords(message.content)) {
        final normalized = keyword.toLowerCase();
        if (normalized.length < 2 || _stopWords.contains(normalized)) {
          continue;
        }
        bucket[normalized] = (bucket[normalized] ?? 0) + 1;
      }
    }

    final shared = myKeywords.keys
        .where((keyword) => theirKeywords.containsKey(keyword))
        .toList()
      ..sort(
        (a, b) => (theirKeywords[b]! + myKeywords[b]!).compareTo(
          theirKeywords[a]! + myKeywords[a]!,
        ),
      );

    return shared.take(3).toList();
  }

  String _guessRelationshipStageForRoundCount(int roundCount) {
    if (roundCount < 5) {
      return 'initial';
    }
    if (roundCount < 15) {
      return 'getting_to_know';
    }
    if (roundCount < 30) {
      return 'rapport';
    }
    return 'established';
  }

  String _enumToLabel(dynamic value) {
    if (value == null) return 'unknown';
    return value.toString().split('.').last;
  }
}

final memoryServiceProvider = Provider<MemoryService>((ref) {
  return MemoryService();
});
