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
}
