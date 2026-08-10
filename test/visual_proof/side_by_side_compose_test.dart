// 把 before/ 與 after/ 目錄下同名整頁 PNG 拼成單張左右對照圖，
// 給 Eric 一眼比整頁氣質差（沒有 PIL/ImageMagick，用 Flutter 自己合成）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'proof_support.dart';

const _pairs = [
  'analysis_records_sheet',
];

void main() {
  setUpAll(loadProofFonts);

  testWidgets('compose full-page before/after side by side', (tester) async {
    // 本機對照工具：before/after PNG 是先前 SLOP_STAGE 跑出的機器本地產物，
    // CI 全新 runner 上不存在——缺圖就 skip，不能讓 distribution gate 紅。
    final missing = _pairs
        .where((name) =>
            !File(outPath('before/$name.png')).existsSync() ||
            !File(outPath('after/$name.png')).existsSync())
        .toList();
    if (missing.isNotEmpty) {
      markTestSkipped('缺 before/after 產物（$missing），本機工具跳過');
      return;
    }
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
