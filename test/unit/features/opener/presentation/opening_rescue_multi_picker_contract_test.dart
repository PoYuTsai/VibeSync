import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('開場救星啟用最多三張的相簿多選模式', () {
    final source = File(
      'lib/features/opener/presentation/screens/opening_rescue_screen.dart',
    ).readAsStringSync();

    expect(source, contains('ImagePickerWidget('));
    expect(source, contains('maxImages: 3,'));
    expect(source, contains('allowMultiSelect: true,'));
  });

  test('開場救星關掉共用元件的聊天截圖提示（自介頁沒有 LINE 回覆框）', () {
    final source = File(
      'lib/features/opener/presentation/screens/opening_rescue_screen.dart',
    ).readAsStringSync();
    final pickerStart = source.indexOf('ImagePickerWidget(');
    expect(pickerStart, greaterThan(-1));
    final pickerBlock = source.substring(pickerStart, pickerStart + 800);
    expect(pickerBlock, contains('showHelperText: false,'));

    // 那三句提示只該留在聊天截圖流程，開場救星共用同一個元件。
    final picker = File(
      'lib/shared/widgets/image_picker_widget.dart',
    ).readAsStringSync();
    expect(picker, contains('LINE 回覆框'));
    expect(picker, contains('showHelperText'));
  });
}
