// lib/features/learning/data/providers/chat_quiz_providers.dart
//
// 聊天測驗的 Riverpod 接線。
//
// 刻意與電子書完全分離：這裡不讀 `ebookProgressControllerProvider`，也不寫
// `learning_progress_v1:`。測驗進度有自己的 key（見 Task 3），兩邊唯一共用的是
// 權限階梯型別 [EbookAccess] 與內容 catalog（深連要對照書與章是否真的存在）。
//
// 第 1 期完全不打網路：沒有 Edge Function、沒有 quota、沒有計費。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/storage_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../domain/models/chat_quiz.dart';
import '../../domain/models/chat_quiz_progress.dart';
import '../repositories/chat_quiz_catalog_repository.dart';
import '../repositories/chat_quiz_progress_repository.dart';

final chatQuizCatalogRepositoryProvider =
    Provider<ChatQuizCatalogRepository>((ref) {
  return ChatQuizCatalogRepository();
});

/// 測驗內容 catalog。
///
/// 解析失敗時是 AsyncError 而不是空 catalog：空的看起來像「還沒有題目」，
/// 錯誤才會讓學習頁那一塊顯示可讀錯誤並被測試抓到。學習頁其他區塊（文章、
/// 電子書）不得因此一起壞掉——降級處理在 `chat_quiz_section.dart`。
final chatQuizCatalogProvider = FutureProvider<ChatQuizCatalog>((ref) {
  return ref.watch(chatQuizCatalogRepositoryProvider).load();
});

/// 目前登入帳號 id。
///
/// 刻意不共用電子書那顆 owner provider：兩個功能各自成立，共用會讓其中一邊的
/// override（測試或未來的帳號邏輯）默默影響另一邊。多一條 auth 訂閱很便宜。
final chatQuizProgressOwnerProvider = StreamProvider<String?>((ref) async* {
  yield SupabaseService.currentUser?.id;
  yield* SupabaseService.authStateChanges
      .map((authState) => authState.session?.user.id);
});

final chatQuizProgressRepositoryProvider =
    Provider<ChatQuizProgressRepository>((ref) {
  return ChatQuizProgressRepository(box: StorageService.settingsBox);
});

final chatQuizProgressControllerProvider =
    AsyncNotifierProvider<ChatQuizProgressController, ChatQuizProgress>(
  ChatQuizProgressController.new,
);

class ChatQuizProgressController extends AsyncNotifier<ChatQuizProgress> {
  bool _disposed = false;

  /// 目前這份 state 屬於哪個帳號。寫入完成時要比對，否則在帳號切換的競態下
  /// 可能把 A 的進度發布到已經切成 B 的畫面上。
  String? _currentOwner;

  @override
  Future<ChatQuizProgress> build() async {
    _disposed = false;
    ref.onDispose(() => _disposed = true);

    final owner = await ref.watch(chatQuizProgressOwnerProvider.future);
    final normalized = owner?.trim() ?? '';
    _currentOwner = normalized.isEmpty ? null : normalized;
    if (normalized.isEmpty) {
      // 未登入 fail closed：不建立 anonymous 共用進度。
      return ChatQuizProgress.empty;
    }
    return ref.read(chatQuizProgressRepositoryProvider).load(normalized);
  }

  Future<void> recordAnswer({
    required String questionId,
    required String choiceId,
    required int revision,
  }) async {
    final owner = await _ownerOrNull();
    if (owner == null) return;
    _publish(
      owner,
      await ref.read(chatQuizProgressRepositoryProvider).recordAnswer(
            ownerUserId: owner,
            questionId: questionId,
            choiceId: choiceId,
            revision: revision,
          ),
    );
  }

  Future<void> recordLevelResult({
    required String levelId,
    required int correctCount,
    required int questionCount,
    required bool passed,
  }) async {
    final owner = await _ownerOrNull();
    if (owner == null) return;
    _publish(
      owner,
      await ref.read(chatQuizProgressRepositoryProvider).recordLevelResult(
            ownerUserId: owner,
            levelId: levelId,
            correctCount: correctCount,
            questionCount: questionCount,
            passed: passed,
          ),
    );
  }

  Future<void> clearAnswers(List<String> questionIds) async {
    final owner = await _ownerOrNull();
    if (owner == null) return;
    _publish(
      owner,
      await ref.read(chatQuizProgressRepositoryProvider).clearAnswers(
            ownerUserId: owner,
            questionIds: questionIds,
          ),
    );
  }

  Future<String?> _ownerOrNull() async {
    final owner = await ref.read(chatQuizProgressOwnerProvider.future);
    final normalized = owner?.trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }

  /// Hive 寫入已經完成才會走到這裡。provider 已被 dispose、或寫入期間帳號
  /// 換人時丟掉這筆結果；寫入本身不會被取消。
  void _publish(String writeOwner, ChatQuizProgress progress) {
    if (_disposed) return;
    if (_currentOwner != writeOwner) return;
    state = AsyncData(progress);
  }
}

/// 目前可用的測驗進度。
///
/// 刻意只讀 [AsyncData]：Riverpod 重建時會把上一次的值掛在 AsyncLoading 的
/// previousValue 上，直接用 `.value` 會在帳號切換的空窗期短暫顯示上一個帳號
/// 的成績。寧可先顯示空進度。
final chatQuizProgressProvider = Provider<ChatQuizProgress>((ref) {
  final snapshot = ref.watch(chatQuizProgressControllerProvider);
  if (snapshot is! AsyncData<ChatQuizProgress>) return ChatQuizProgress.empty;
  return snapshot.value;
});
