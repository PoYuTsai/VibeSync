// lib/features/learning/data/providers/ebook_providers.dart
//
// 互動電子書的 Riverpod 接線。
//
// 刻意與文章區完全分離：這裡不出現 ArticleReadService，也不讀文章每日額度，
// 因為電子書拍板為「不消耗文章每日三篇免費額度」。
//
// 帳號隔離靠 [ebookProgressOwnerProvider]：owner id 只能來自 Supabase session，
// 不從 route、內容或 UI 傳入；沒有帳號時 fail closed 用空進度，絕不建立共用 key。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/storage_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../domain/models/ebook.dart';
import '../../domain/models/ebook_progress.dart';
import '../repositories/ebook_catalog_repository.dart';
import '../repositories/ebook_progress_repository.dart';

final ebookCatalogRepositoryProvider = Provider<EbookCatalogRepository>((ref) {
  return EbookCatalogRepository();
});

/// 四本書的內容 catalog。解析失敗時是 AsyncError，UI 顯示可讀錯誤而不是假裝空書架。
final ebookCatalogProvider = FutureProvider<EbookCatalog>((ref) {
  return ref.watch(ebookCatalogRepositoryProvider).load();
});

/// 目前登入帳號 id。對齊 `authUserProfileScopeProvider` 的做法：帳號改變時
/// 下游進度自動重建，換帳號不會沿用上一個帳號的 snapshot。
final ebookProgressOwnerProvider = StreamProvider<String?>((ref) async* {
  yield SupabaseService.currentUser?.id;
  yield* SupabaseService.authStateChanges
      .map((authState) => authState.session?.user.id);
});

final ebookProgressRepositoryProvider =
    Provider<EbookProgressRepository>((ref) {
  return EbookProgressRepository(box: StorageService.settingsBox);
});

final ebookProgressControllerProvider =
    AsyncNotifierProvider<EbookProgressController, EbookProgressSnapshot>(
  EbookProgressController.new,
);

class EbookProgressController extends AsyncNotifier<EbookProgressSnapshot> {
  bool _disposed = false;

  /// 目前這份 state 屬於哪個帳號。寫入完成時要比對，否則在帳號切換的競態下
  /// 可能把 A 的 snapshot 發布到已經切成 B 的畫面上。
  String? _currentOwner;

  @override
  Future<EbookProgressSnapshot> build() async {
    _disposed = false;
    ref.onDispose(() => _disposed = true);

    final owner = await ref.watch(ebookProgressOwnerProvider.future);
    final normalized = owner?.trim() ?? '';
    _currentOwner = normalized.isEmpty ? null : normalized;
    if (normalized.isEmpty) {
      // 未登入 fail closed：不建立 anonymous 共用進度。
      return EbookProgressSnapshot.empty;
    }
    return ref.read(ebookProgressRepositoryProvider).load(normalized);
  }

  Future<void> markChapterCompleted({
    required String bookId,
    required String chapterId,
    int? contentVersion,
  }) async {
    final owner = await _ownerOrNull();
    if (owner == null) return;
    _publish(
      owner,
      await ref.read(ebookProgressRepositoryProvider).markChapterCompleted(
            ownerUserId: owner,
            bookId: bookId,
            chapterId: chapterId,
            contentVersion: contentVersion,
          ),
    );
  }

  Future<void> setLastChapter({
    required String bookId,
    required String chapterId,
    int? contentVersion,
  }) async {
    final owner = await _ownerOrNull();
    if (owner == null) return;
    _publish(
      owner,
      await ref.read(ebookProgressRepositoryProvider).setLastChapter(
            ownerUserId: owner,
            bookId: bookId,
            chapterId: chapterId,
            contentVersion: contentVersion,
          ),
    );
  }

  Future<void> recordQuizSubmission({
    required String bookId,
    required String quizId,
    required int quizRevision,
    required List<String> choiceIds,
    required bool solved,
  }) async {
    final owner = await _ownerOrNull();
    if (owner == null) return;
    _publish(
      owner,
      await ref.read(ebookProgressRepositoryProvider).recordQuizSubmission(
            ownerUserId: owner,
            bookId: bookId,
            quizId: quizId,
            quizRevision: quizRevision,
            choiceIds: choiceIds,
            solved: solved,
          ),
    );
  }

  Future<void> setChecklistItem({
    required String bookId,
    required String blockId,
    required String itemId,
    required bool checked,
  }) async {
    final owner = await _ownerOrNull();
    if (owner == null) return;
    _publish(
      owner,
      await ref.read(ebookProgressRepositoryProvider).setChecklistItem(
            ownerUserId: owner,
            bookId: bookId,
            blockId: blockId,
            itemId: itemId,
            checked: checked,
          ),
    );
  }

  Future<String?> _ownerOrNull() async {
    final owner = await ref.read(ebookProgressOwnerProvider.future);
    final normalized = owner?.trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }

  /// Hive 寫入已經完成才會走到這裡。
  ///
  /// 兩道保護：
  ///   - provider 已被 dispose（例如登出 invalidate）就不再更新已死的 state；
  ///     寫入本身不會被取消。
  ///   - 寫入期間帳號換人時丟掉這筆結果，避免 A 的進度被發布到 B 的畫面。
  void _publish(String writeOwner, EbookProgressSnapshot snapshot) {
    if (_disposed) return;
    if (_currentOwner != writeOwner) return;
    state = AsyncData(snapshot);
  }
}

/// 單一本書的進度切片。
///
/// 刻意只讀 [AsyncData]：Riverpod 在重建時會把上一次的值掛在 AsyncLoading 的
/// previousValue 上，若直接用 `.value` 就會在帳號切換的空窗期短暫顯示上一個
/// 帳號的完成度。寧可先顯示空進度。
final ebookBookProgressProvider =
    Provider.family<EbookBookProgress, String>((ref, bookId) {
  final snapshot = ref.watch(ebookProgressControllerProvider);
  if (snapshot is! AsyncData<EbookProgressSnapshot>) {
    return EbookBookProgress.empty;
  }
  return snapshot.value.bookProgress(bookId);
});
