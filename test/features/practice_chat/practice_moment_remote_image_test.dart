// 生成配圖（PR-5）client 端的解析契約：
// URL 縱深防禦、fromJson 容錯、imageSource 優先序、tile 渲染與降級。
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/config/environment.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_moment_image.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_moment_post.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_moment_tile.dart';

/// 與 AppConfig.supabaseUrl 同 host 的合法生成圖 URL。
final String validUrl =
    '${AppConfig.supabaseUrl}/storage/v1/object/public/practice-moment-images/2026-08-25/practice_girl_001_0.jpeg';

Map<String, dynamic> rawPost({String? imageId, String? imageUrl}) => {
      'profileId': 'practice_girl_001',
      'postDate': '2026-08-25',
      'slot': 0,
      'dayPart': 'evening',
      'postedAt': '2026-08-25T12:00:00.000Z',
      'body': '傍晚的天色好到讓人想多走一站再回家',
      if (imageId != null) 'imageId': imageId,
      if (imageUrl != null) 'imageUrl': imageUrl,
    };

void main() {
  group('resolveMomentImageUrl 縱深防禦', () {
    test('同 host 的 https URL 放行', () {
      expect(resolveMomentImageUrl(validUrl), validUrl);
    });

    test('非本 app Supabase host 一律拒絕', () {
      expect(
        resolveMomentImageUrl(
          'https://evil.example.com/storage/v1/object/public/x.jpeg',
        ),
        isNull,
      );
    });

    test('http（非 https）拒絕', () {
      expect(
        resolveMomentImageUrl(validUrl.replaceFirst('https://', 'http://')),
        isNull,
      );
    });

    test('null／空白／垃圾字串一律 null', () {
      expect(resolveMomentImageUrl(null), isNull);
      expect(resolveMomentImageUrl('  '), isNull);
      expect(resolveMomentImageUrl('not a url'), isNull);
    });
  });

  group('PracticeMomentPost.imageSource 優先序', () {
    test('合法 imageUrl → MomentRemoteImage（優先於 imageId）', () {
      final post = PracticeMomentPost.fromJson(
        rawPost(imageId: 'moment_coffee_cup', imageUrl: validUrl),
      );
      expect(post, isNotNull);
      final source = post!.imageSource;
      expect(source, isA<MomentRemoteImage>());
      expect((source! as MomentRemoteImage).url, validUrl);
    });

    test('imageUrl 不合法 → 退回 imageId 的 catalog 解析', () {
      final post = PracticeMomentPost.fromJson(
        rawPost(
          imageId: 'moment_coffee_cup',
          imageUrl: 'https://evil.example.com/x.jpeg',
        ),
      );
      expect(post!.imageSource, isA<MomentSceneImage>());
    });

    test('兩者皆無 → 純文字', () {
      final post = PracticeMomentPost.fromJson(rawPost());
      expect(post!.imageSource, isNull);
    });

    test('舊 server 回應（無 imageUrl 鍵）完全相容', () {
      final post = PracticeMomentPost.fromJson(
        rawPost(imageId: 'moment_coffee_cup'),
      );
      expect(post!.imageUrl, isNull);
      expect(post.imageSource, isA<MomentSceneImage>());
    });
  });

  group('PracticeMomentTile 渲染', () {
    Widget wrap(PracticeMomentPost post) => MaterialApp(
          home: Scaffold(
            body: PracticeMomentTile(
              post: post,
              profile: null,
              now: DateTime.utc(2026, 8, 25, 13),
            ),
          ),
        );

    testWidgets('remote 圖貼文渲染 CachedNetworkImage', (tester) async {
      final post = PracticeMomentPost.fromJson(rawPost(imageUrl: validUrl))!;
      await tester.pumpWidget(wrap(post));
      expect(find.byType(CachedNetworkImage), findsOneWidget);
    });

    testWidgets('純文字貼文零圖片 widget', (tester) async {
      final post = PracticeMomentPost.fromJson(rawPost())!;
      await tester.pumpWidget(wrap(post));
      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(find.text(post.body), findsOneWidget);
    });
  });
}
