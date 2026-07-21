// Phase E Task 6 — 純記憶體 CoachChatRepository 測試替身。
//
// 對象頁 CoachFollowUpSection 變薄後直接掛 CoachSurface，任何 pump 到
// PartnerDetailScreen / CoachFollowUpSection 的 widget 測試都會經
// coachChatControllerProvider / coachChatHistoryProvider 讀 repository；
// 預設實作打 Hive box（測試環境未初始化必炸），一律用本替身 override。
import 'package:vibesync/features/coach_chat/domain/entities/coach_chat_result.dart';
import 'package:vibesync/features/coach_chat/domain/entities/unified_coach_result.dart';
import 'package:vibesync/features/coach_chat/domain/repositories/coach_chat_repository.dart';

class MemoryCoachChatRepository implements CoachChatRepository {
  final Map<String, UnifiedCoachResult> _store = {};

  /// 佐證「絕無 auto-send」：任何送出成功都會落卡經過 putUnified。
  int putUnifiedCalls = 0;

  void seedUnified(UnifiedCoachResult result) => _store[result.id] = result;

  @override
  List<UnifiedCoachResult> listByScope(String scopeType, String scopeId) {
    return _store.values
        .where((r) => r.scopeType == scopeType && r.scopeId == scopeId)
        .toList()
      ..sort((a, b) => b.generatedAt.compareTo(a.generatedAt));
  }

  @override
  UnifiedCoachResult? latestForScope(String scopeType, String scopeId) {
    final list = listByScope(scopeType, scopeId);
    return list.isEmpty ? null : list.first;
  }

  @override
  Future<void> putUnified(UnifiedCoachResult result) async {
    putUnifiedCalls++;
    _store[result.id] = result;
  }

  @override
  Future<void> deleteScope(String scopeType, String scopeId) async {
    _store.removeWhere(
      (_, r) => r.scopeType == scopeType && r.scopeId == scopeId,
    );
  }

  // Phase E 之後 UI 一律走 unified scope 路徑；legacy facade 被呼叫代表
  // 走錯路，直接炸出來當回歸守門。
  @override
  List<CoachChatResult> listByConversation(String conversationId) =>
      throw UnimplementedError('Phase E must use listByScope');

  @override
  CoachChatResult? latestForConversation(String conversationId) =>
      throw UnimplementedError('Phase E must use latestForScope');

  @override
  Future<void> put(CoachChatResult result) =>
      throw UnimplementedError('Phase E must use putUnified');

  @override
  Future<void> deleteConversation(String conversationId) =>
      throw UnimplementedError('Phase E must use deleteScope');

  @override
  Future<void> clearAll() async => _store.clear();
}
