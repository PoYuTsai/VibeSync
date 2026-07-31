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

import '../../domain/models/chat_quiz.dart';
import '../repositories/chat_quiz_catalog_repository.dart';

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
