// Scoped visual proof — Opener (開場救星) result state.
// Run: flutter test test/visual_proof/opener_proof_test.dart
// Out: build/visual_proof/opener_before.png, opener_after.png
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'proof_support.dart';
import 'proof_themes.dart';

Widget _eyebrow(ProofTheme t, String s) => Text(
      s,
      style: TextStyle(
          color: t.accent, fontSize: 13, fontWeight: FontWeight.w600),
    );

Widget _segmented(ProofTheme t) => t.card(
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: t.accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.accent.withValues(alpha: 0.5)),
              ),
              child: Center(
                child: Text('截圖自介',
                    style: TextStyle(
                        color: t.accent, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text('手動輸入', style: TextStyle(color: t.onCardSecondary)),
            ),
          ),
        ],
      ),
    );

Widget _openerCard(ProofTheme t, String label, String content,
        {bool recommended = false}) =>
    SizedBox(
      width: 280,
      height: 188,
      child: t.card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(label,
                    style: TextStyle(
                        color: t.onCardPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                if (recommended)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: t.accent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('教練建議',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Text(content,
                  style: TextStyle(
                      color: t.onCardPrimary, fontSize: 14, height: 1.6),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.copy, size: 16, color: t.onCardHint),
                  const SizedBox(width: 4),
                  Text('複製', style: TextStyle(color: t.onCardHint, fontSize: 14)),
                ],
              ),
            ),
          ],
        ),
      ),
    );

Widget _nextStepRow(ProofTheme t, IconData icon, String title, String desc) =>
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: t.accent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: t.onCardPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(desc,
                  style: TextStyle(
                      color: t.onCardSecondary, fontSize: 13, height: 1.4)),
            ],
          ),
        ),
      ],
    );

Widget buildOpenerScreen(ProofTheme t) {
  return t.background(
    Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Icon(Icons.arrow_back_ios, color: t.appBarTitleColor, size: 20),
        title: Text('開場救星',
            style: TextStyle(
                color: t.appBarTitleColor,
                fontSize: 22,
                fontWeight: FontWeight.w600)),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _eyebrow(t, '開場救星'),
              const SizedBox(height: 4),
              Text('為 小雨 想開場',
                  style: TextStyle(
                      color: t.onBgPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              _segmented(t),
              const SizedBox(height: 24),
              Row(
                children: [
                  Text('開場白建議',
                      style: TextStyle(
                          color: t.onBgPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  Text(' ・5 種風格',
                      style: TextStyle(color: t.onBgSecondary, fontSize: 13)),
                  const Spacer(),
                  Text('← 左右滑動',
                      style: TextStyle(color: t.onBgSecondary, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 200,
                child: ShaderMask(
                  shaderCallback: (rect) => const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Colors.white, Colors.white, Colors.transparent],
                    stops: [0.0, 0.86, 1.0],
                  ).createShader(rect),
                  blendMode: BlendMode.dstIn,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(right: 28),
                    children: [
                      _openerCard(
                        t,
                        '直球風格',
                        '看妳照片裡在象山拍的夜景，構圖很有想法。我也常帶相機上去，下次可以交流拍夜景的點。',
                        recommended: true,
                      ),
                      const SizedBox(width: 12),
                      _openerCard(
                        t,
                        '幽默風格',
                        '我認真說，妳簡介寫「拒絕已讀不回」這點我完全同意，所以我先回妳——現在換妳了。',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              t.cardLow(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lightbulb_outline, size: 18, color: t.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '為什麼這樣說：她的自介強調生活感和真實互動，直球但具體的稱讚最容易接得住。',
                        style: TextStyle(
                            color: t.onCardSecondary,
                            fontSize: 13,
                            height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              t.cardLow(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.route_outlined, size: 18, color: t.accent),
                        const SizedBox(width: 8),
                        Text('下一步怎麼接？',
                            style: TextStyle(
                                color: t.onCardPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '開場救星只是「先鋒」：先複製一則去送出，等她真的回覆後，再建立新對話分析後續。',
                      style: TextStyle(
                          color: t.onCardSecondary, fontSize: 13, height: 1.45),
                    ),
                    const SizedBox(height: 14),
                    _nextStepRow(t, Icons.content_copy_outlined,
                        '1. 複製開場，去交友軟體送出', '你可以直接用，也可以照自己的語氣微調。'),
                    const SizedBox(height: 12),
                    _nextStepRow(t, Icons.chat_bubble_outline,
                        '2. 她回覆後，回來開新對話', '把你送出的那句，加上她的回覆一起貼上。'),
                    const SizedBox(height: 16),
                    t.cta('她回覆了，開始分析對話'),
                  ],
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(loadProofFonts);

  testWidgets('opener before (warm)', (tester) async {
    await pumpAndCapture(tester,
        child: buildOpenerScreen(warmTheme),
        outPath: outPath('opener_before.png'),
        size: const Size(390, 1180));
  });

  testWidgets('opener after (calm)', (tester) async {
    await pumpAndCapture(tester,
        child: buildOpenerScreen(calmTheme),
        outPath: outPath('opener_after.png'),
        size: const Size(390, 1180));
  });
}
