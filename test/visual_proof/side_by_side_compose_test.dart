// 把 before/ 與 after/ 目錄下同名整頁 PNG 拼成單張左右對照圖，
// 給 Eric 一眼比整頁氣質差（沒有 PIL/ImageMagick，用 Flutter 自己合成）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'proof_support.dart';

const _pairs = [
  'about_me_profile',
  'brand_kit_gallery',
  'partner_mindmap',
  'prod_partner_home',
];

void main() {
  setUpAll(loadProofFonts);

  testWidgets('compose full-page before/after side by side', (tester) async {
    for (final name in _pairs) {
      final beforeBytes =
          File(outPath('before/$name.png')).readAsBytesSync();
      final afterBytes = File(outPath('after/$name.png')).readAsBytesSync();
      await pumpAndCapture(
        tester,
        size: const Size(820, 950),
        rasterDecodeWait: const Duration(milliseconds: 500),
        child: Material(
          color: const Color(0xFF150C24),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      const Text('改前',
                          style: TextStyle(
                              color: Color(0xFFFFB48C),
                              fontSize: 20,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Expanded(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Image.memory(beforeBytes,
                              fit: BoxFit.contain),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    children: [
                      const Text('改後',
                          style: TextStyle(
                              color: Color(0xFF8CFFB4),
                              fontSize: 20,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Expanded(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Image.memory(afterBytes,
                              fit: BoxFit.contain),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        outPath: outPath('compare_full_$name.png'),
      );
    }
  });
}
