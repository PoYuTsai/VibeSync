import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/shared/widgets/local_avatar.dart';

const fallback = Icon(Icons.person_outline, key: ValueKey('avatar-fallback'));

Future<void> pumpAvatar(WidgetTester t, String? path) async {
  await t.runAsync(() async {
    await t.pumpWidget(MaterialApp(
        home: SizedBox(
            width: 48,
            height: 48,
            child: LocalAvatar(path: path, fallback: fallback))));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await t.pump();
  });
  await t.pumpAndSettle();
}

/// [pumpAvatar] 之後一直等到讀檔結果出來、畫出圖片為止（最多約 5 秒）。
/// LocalAvatar 讀頭像是真的檔案 I/O：全套測試跑到一半、機器忙的時候，固定的 80 ms 偶爾不夠，
/// 圖片還沒出來就斷言會失敗。
Future<void> waitForImage(WidgetTester t) async {
  await t.runAsync(() async {
    for (var i = 0; i < 250 && find.byType(Image).evaluate().isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await t.pump();
    }
  });
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
      'local avatar renders real local bytes then clears old image on path change',
      (t) async {
    final directory = Directory.systemTemp.createTempSync('v3-avatar');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/avatar.png');
    await t.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.purple, BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(4, 4);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
      picture.dispose();
    });
    await pumpAvatar(t, file.path);
    await waitForImage(t);
    expect(find.byType(Image), findsOneWidget);
    expect(t.widget<Image>(find.byType(Image)).image, isA<MemoryImage>());
    expect(find.byKey(const ValueKey('avatar-fallback')), findsNothing);
    await pumpAvatar(t, '${directory.path}/missing.png');
    expect(find.byType(Image), findsNothing);
    expect(find.byKey(const ValueKey('avatar-fallback')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('missing, corrupt and remote avatar paths fall back safely',
      (t) async {
    final directory = Directory.systemTemp.createTempSync('v3-avatar-broken');
    addTearDown(() => directory.deleteSync(recursive: true));
    final bad = File('${directory.path}/bad.png')
      ..writeAsStringSync('not an image');
    for (final path in [
      null,
      '',
      bad.path,
      'https://example.invalid/avatar.png'
    ]) {
      await pumpAvatar(t, path);
      expect(find.byKey(const ValueKey('avatar-fallback')), findsOneWidget);
      expect(t.takeException(), isNull);
    }
  });
}
