// lib/features/learning/data/providers/ebook_providers.dart
//
// 互動電子書的 Riverpod 接線。
//
// 刻意與文章區完全分離：這裡不出現 ArticleReadService，也不讀文章每日額度，
// 因為電子書拍板為「不消耗文章每日三篇免費額度」。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/ebook.dart';
import '../repositories/ebook_catalog_repository.dart';

final ebookCatalogRepositoryProvider = Provider<EbookCatalogRepository>((ref) {
  return EbookCatalogRepository();
});

/// 四本書的內容 catalog。解析失敗時是 AsyncError，UI 顯示可讀錯誤而不是假裝空書架。
final ebookCatalogProvider = FutureProvider<EbookCatalog>((ref) {
  return ref.watch(ebookCatalogRepositoryProvider).load();
});
