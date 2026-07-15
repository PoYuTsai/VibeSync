import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vibesync/shared/widgets/image_picker_widget.dart';

void main() {
  testWidgets('多選模式把剩餘張數交給相簿 selector', (tester) async {
    bool? receivedAllowMultiple;
    int? receivedLimit;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImagePickerWidget(
            maxImages: 3,
            allowMultiSelect: true,
            fileSelector: ({required allowMultiple, required limit}) async {
              receivedAllowMultiple = allowMultiple;
              receivedLimit = limit;
              return const <XFile>[];
            },
            onImagesChanged: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('多選'));
    await tester.pump();

    expect(receivedAllowMultiple, isTrue);
    expect(receivedLimit, 3);
  });

  testWidgets('預設模式維持單張選圖', (tester) async {
    bool? receivedAllowMultiple;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImagePickerWidget(
            fileSelector: ({required allowMultiple, required limit}) async {
              receivedAllowMultiple = allowMultiple;
              return const <XFile>[];
            },
            onImagesChanged: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('選圖'));
    await tester.pump();

    expect(receivedAllowMultiple, isFalse);
  });
}
