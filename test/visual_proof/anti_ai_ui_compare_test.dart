// 把 anti_ai_ui/before 與 after 同名整頁 PNG 拼成左右對照圖，給 Eric 肉眼 gate。
// 本機工具：缺圖就 skip，CI 不受影響。
import 'dart:io';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'proof_support.dart';

const _pairs = [
  'home_populated',
  'home_empty',
  'add_partner',
  'learning_hero',
  'collection',
  'practice_opening',
];

void main() {
  setUpAll(loadProofFonts);

  testWidgets('compose anti-ai-ui before/after side by side', (tester) async {
    for (final name in _pairs) {
      final beforeFile = File(outPath('anti_ai_ui/before/$name.png'));
      final afterFile = File(outPath('anti_ai_ui/after/$name.png'));
      if (!beforeFile.existsSync() || !afterFile.existsSync()) {
        markTestSkipped('缺 $name 的 before/after 產物，本機工具跳過');
        continue;
      }
      final beforeBytes = beforeFile.readAsBytesSync();
      final afterBytes = afterFile.readAsBytesSync();
      await pumpAndCapture(
        tester,
        size: const Size(820, 950),
        rasterDecodeWait: const Duration(milliseconds: 500),
        child: Material(
          color: const Color(0xFF150C24),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _Side(
                          label: '改前（HEAD）',
                          color: const Color(0xFFFFB48C),
                          bytes: beforeBytes,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _Side(
                          label: '改後（本輪）',
                          color: const Color(0xFF8CFFB4),
                          bytes: afterBytes,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        outPath: outPath('anti_ai_ui/compare_$name.png'),
      );
    }
  });
}

class _Side extends StatelessWidget {
  const _Side({
    required this.label,
    required this.color,
    required this.bytes,
  });

  final String label;
  final Color color;
  final List<int> bytes;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: Image.memory(
              Uint8List.fromList(bytes),
              fit: BoxFit.contain,
            ),
          ),
        ),
      ],
    );
  }
}
