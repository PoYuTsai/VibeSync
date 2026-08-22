/// data 端 adapter：以既有 MemoryService 實作 application 的
/// ConversationMemoryPort（摘要生成／格式化／近幾輪裁切規則全在
/// MemoryService）。
library;

import '../../../conversation/data/services/memory_service.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../../../conversation/domain/entities/conversation_summary.dart';
import '../../../conversation/domain/entities/message.dart';
import '../../application/ports/conversation_memory_port.dart';

class ConversationMemoryAdapter implements ConversationMemoryPort {
  ConversationMemoryAdapter({MemoryService? memoryService})
      : _memoryService = memoryService ?? MemoryService();

  final MemoryService _memoryService;

  @override
  String? persistedHistoricalSummary(Conversation conversation) =>
      _memoryService.buildHistoricalSummary(conversation);

  @override
  Future<String> formatEphemeralSummary(
    Conversation conversation,
    int olderRounds,
  ) async {
    final ephemeralSummary = await _memoryService.generateSummary(
      conversation,
      0,
      olderRounds,
    );
    return _memoryService.formatSummarySegments(
      <ConversationSummary>[ephemeralSummary],
    );
  }

  @override
  List<Message> clipToRecentRounds(List<Message> messages, int maxRounds) =>
      _memoryService.clipToRecentRounds(messages, maxRounds);

  @override
  int get maxRecentRounds => MemoryService.maxRecentRounds;

  @override
  int get minRoundsPerSummary => MemoryService.minRoundsPerSummary;
}
