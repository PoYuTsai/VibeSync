// test/unit/app/ebook_routes_test.dart
//
// 路由回歸：電子書路由已註冊，而既有的 /article/:id 與 Coach 深連路由沒有被改動。
//
// 為什麼讀原始檔而不是實例化 GoRouter：`lib/app/routes.dart` 的 top-level
// `router` 在初始化時就會訂閱 `SupabaseService.authStateChanges`，而那在未
// 初始化 Supabase 的測試環境會直接拋 StateError，沒有注入 seam 可以繞開。
// 這個測試守的是「路由字串有沒有被改掉或刪掉」，不是 GoRouter 的行為。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/coach/coach_action_type.dart';
import 'package:vibesync/features/analysis/domain/coach/learning_link_resolver.dart';
import 'package:vibesync/features/learning/data/articles_data.dart';
import 'package:vibesync/features/learning/presentation/screens/ebook_detail_screen.dart';

void main() {
  late String routesSource;

  setUpAll(() {
    routesSource = File('lib/app/routes.dart').readAsStringSync();
  });

  test('電子書路由已註冊', () {
    expect(routesSource.contains("path: '/learning/books/:bookId'"), isTrue);
    expect(
      routesSource.contains(
        "path: '/learning/books/:bookId/chapters/:chapterId'",
      ),
      isTrue,
    );
    expect(routesSource.contains('EbookDetailScreen'), isTrue);
    expect(routesSource.contains('EbookReaderScreen'), isTrue);
  });

  test('既有文章路由沒有被改動', () {
    expect(routesSource.contains("path: '/article/:id'"), isTrue);
    expect(routesSource.contains('ArticleDetailScreen'), isTrue);
  });

  test('route helper 產生的路徑與註冊的樣板一致', () {
    expect(
      ebookDetailRoute('ebook-1-bottleneck'),
      '/learning/books/ebook-1-bottleneck',
    );
    expect(
      ebookChapterRoute('ebook-1-bottleneck', 'ebook-1-chapter-2'),
      '/learning/books/ebook-1-bottleneck/chapters/ebook-1-chapter-2',
    );
  });

  test('交叉指涉的定位點走 query，且 route 真的有讀它', () {
    expect(
      ebookChapterRoute(
        'ebook-2-conversation',
        'ebook-2-chapter-5',
        entryId: 'ebook-2-c5-lib-e11',
      ),
      '/learning/books/ebook-2-conversation/chapters/ebook-2-chapter-5'
      '?entry=ebook-2-c5-lib-e11',
    );
    // 空定位點不留一個沒有值的 query。
    expect(
      ebookChapterRoute('ebook-1-bottleneck', 'ebook-1-chapter-2', entryId: ''),
      '/learning/books/ebook-1-bottleneck/chapters/ebook-1-chapter-2',
    );
    // helper 產了 query 但 route 沒接，等於按鈕永遠落在章首。
    expect(routesSource.contains("queryParameters['entry']"), isTrue);
  });

  test('電子書沒有佔用 numeric article id space', () {
    // 電子書 id 一律是 `ebook-` 前綴，且不可與任何 article id 相同。
    final articleIds = articles.map((article) => article.id).toSet();
    for (final bookId in const [
      'ebook-1-bottleneck',
      'ebook-2-conversation',
      'ebook-3-rescue',
      'ebook-4-meeting',
    ]) {
      expect(articleIds.contains(bookId), isFalse);
      expect(bookId.startsWith('ebook-'), isTrue);
    }
  });

  test('Coach learning link 仍然全部指向存在的 article id', () {
    final articleIds = articles.map((article) => article.id).toSet();
    for (final type in CoachActionType.values) {
      final id = LearningLinkResolver.resolve(type);
      if (id == null) continue;
      expect(
        articleIds.contains(id),
        isTrue,
        reason: 'CoachActionType.$type 指向不存在的 article id $id',
      );
    }
  });
}
