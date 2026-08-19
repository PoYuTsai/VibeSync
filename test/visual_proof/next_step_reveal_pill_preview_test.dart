// 2026-08-19「下一步怎麼接？」對標膠囊的預覽：開場白頁深底上，
// 收合（懸浮深墨膠囊）＋展開（淡紫容器＋收起列）兩態。
// 用的是真 RevealPill 共用元件，非替身。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/theme/app_colors.dart';
import 'package:vibesync/core/theme/app_typography.dart';
import 'package:vibesync/shared/widgets/reveal_pill.dart';

import 'proof_support.dart';

Future<void> _loadDefaultFamilyFont() async {
  final tc = File([
    '/usr/share/fonts/opentype/noto/NotoSansCJKtc-Regular.otf',
    '/mnt/c/Windows/Fonts/NotoSansTC-VF.ttf',
  ].firstWhere((p) => File(p).existsSync())).readAsBytesSync();
  await (FontLoader('Roboto')
        ..addFont(Future.value(ByteData.view(tc.buffer))))
      .load();
}

Widget _stepRow(IconData icon, String title, String description) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 18,
            color: AppColors.coachAccentBright.withValues(alpha: 0.90),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.onBackgroundPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: AppTypography.caption.copyWith(
                    color:
                        AppColors.onBackgroundSecondary.withValues(alpha: 0.70),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

List<Widget> _nextStepChildren() => [
      _stepRow(Icons.content_copy_outlined, '1. 複製開場，去交友軟體送出',
          '你可以直接用，也可以照自己的語氣微調。'),
      _stepRow(Icons.chat_bubble_outline, '2. 她回覆後，回來開新對話',
          '把你送出的那句，加上她的回覆一起貼上。'),
      _stepRow(Icons.psychology_alt_outlined, '3. 分析後再問教練怎麼接',
          '只有真實互動進入分析後，才會接上對象記憶。'),
    ];

void main() {
  setUpAll(() async {
    await loadProofFonts();
    await _loadDefaultFamilyFont();
  });

  Future<void> withRealShadows(Future<void> Function() run) async {
    debugDisableShadows = false;
    try {
      await run();
    } finally {
      debugDisableShadows = true;
    }
  }

  testWidgets('下一步怎麼接 膠囊兩態預覽', (tester) async {
    await withRealShadows(() => pumpAndCapture(
          tester,
          outPath: outPath('next_step_reveal_pill.png'),
          child: Material(
            type: MaterialType.transparency,
            child: ColoredBox(
              color: AppColors.brandInk,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '收合態（開場白頁深底）',
                      style: AppTypography.bodySmall.copyWith(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    RevealPill(
                      label: '下一步怎麼接？',
                      children: _nextStepChildren(),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      '展開態',
                      style: AppTypography.bodySmall.copyWith(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    RevealPill(
                      key: const ValueKey('expanded-pill'),
                      label: '下一步怎麼接？（展開示範）',
                      children: _nextStepChildren(),
                    ),
                  ],
                ),
              ),
            ),
          ),
          beforeCapture: (tester) async {
            await tester.tap(find.text('下一步怎麼接？（展開示範）'));
            // AnimatedSize 要先起跑一幀再走完，單次 pump 會拍到半展開。
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));
            await tester.pump(const Duration(milliseconds: 400));
          },
        ));
  });
}
