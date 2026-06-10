// Scoped visual proof — LAYOUT-DENSITY only (warm theme preserved).
//
// Brief (Bruce 2026-06-10): keep the EXACT warm theme — same gradient bg, same
// bokeh, same glass surfaces, same AppColors. Do NOT adopt the v3 dark/calm
// look. Borrow ONLY the one good thing from the v3 comparison: "排版寬度比較剛好、
// 內容更集中". So the ONLY variable between before/after is layout density —
// content width, vertical rhythm, whitespace balance. No new decoration, no new
// copy, no stuffing content to fill space. lib/ is NOT touched.
//
// Run: flutter test test/visual_proof/density_proof_test.dart
// Out (build/visual_proof/):
//   add_partner_before.png / add_partner_after.png
//   new_conversation_collapsed_before.png / ..._after.png
//   new_conversation_expanded_before.png  / ..._after.png
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/theme/app_colors.dart';
import 'package:vibesync/core/theme/app_typography.dart';
import 'package:vibesync/shared/widgets/warm_theme_widgets.dart';

import 'proof_support.dart';

// ---------------------------------------------------------------------------
// Shared warm chrome (identical before & after — proves bg/bokeh/glass intact).
// ---------------------------------------------------------------------------

/// Replica of AddPartnerScreen's private `_AddPartnerBackground`: warm gradient
/// + 3 STATIC brand bubbles. Static so the headless still-frame matches 1:1.
class _AddPartnerWarmBg extends StatelessWidget {
  const _AddPartnerWarmBg({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.backgroundGradientStart,
                  AppColors.backgroundGradientMid,
                  AppColors.backgroundGradientEnd,
                ],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),
        ),
        const Positioned(
          top: -40,
          left: -30,
          child: _Bubble(color: AppColors.primaryLight, size: 170, opacity: 0.55),
        ),
        const Positioned(
          top: 60,
          right: -50,
          child: _Bubble(color: AppColors.ctaStart, size: 150, opacity: 0.5),
        ),
        const Positioned(
          bottom: 120,
          left: 40,
          child: _Bubble(color: AppColors.bokehPink, size: 130, opacity: 0.4),
        ),
        child,
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.color, required this.size, required this.opacity});
  final Color color;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: opacity),
            blurRadius: 60,
            spreadRadius: 25,
          ),
        ],
      ),
    );
  }
}

PreferredSizeWidget _warmAppBar(String title) => AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: const Icon(Icons.arrow_back, color: AppColors.onBackgroundPrimary),
      title: Text(
        title,
        style: const TextStyle(color: AppColors.onBackgroundPrimary),
      ),
      iconTheme: const IconThemeData(color: AppColors.onBackgroundPrimary),
    );

// Shared copy — byte-identical between before & after so layout is the only
// variable. No new strings invented.
const _kAddTitle = '先建立一張對象卡';
const _kAddSubtitle =
    '這張卡代表一個人，之後與同一個人在不同日期、IG、Line 或交友軟體的聊天，都整理在這裡';
const _kAddHint = '例：Alice / Tinder 上的空姐';

// ===========================================================================
// PAGE 1 — Add Partner   (problem: 太空 / 沒重心)
// ===========================================================================

// BEFORE: faithful current tree — top-anchored stretch column, big gaps;
// content piles under the AppBar and the lower ~55% of the screen is dead.
Widget _addPartnerBefore() {
  return _AddPartnerWarmBg(
    child: Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: _warmAppBar('新增對象'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, kToolbarHeight + 16, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(_kAddTitle,
                  style: TextStyle(
                      color: AppColors.onBackgroundPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text(_kAddSubtitle,
                  style: TextStyle(
                      color: AppColors.onBackgroundSecondary,
                      fontSize: 13,
                      height: 1.4)),
              const SizedBox(height: 20),
              const GlassmorphicTextField(hintText: _kAddHint),
              const SizedBox(height: 24),
              GradientButton(text: '建立', onPressed: () {}),
            ],
          ),
        ),
      ),
    ),
  );
}

// AFTER: SAME warm widgets — the real problem is 蠻空, so add MASS, not just
// rebalance gaps (Bruce is fine with the added structure).
//  · Explanatory text moves into a real glass card → a heavy, deliberate
//    center-of-gravity that fills the void = 重心 + 不空.
//  · Width capped 340 + biased to optical centre (Spacer 3:4) → balanced
//    whitespace, comfortable input/button width.
//  · Field + CTA stay ON the gradient directly under the card (where the warm
//    system designs them to pop), tight 18px rhythm.
Widget _addPartnerAfter() {
  return _AddPartnerWarmBg(
    child: Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: _warmAppBar('新增對象'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, kToolbarHeight + 16, 24, 24),
          child: Column(
            children: [
              const Spacer(flex: 3),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GlassmorphicContainer(
                        borderRadius: 20,
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(_kAddTitle,
                                style: TextStyle(
                                    color: AppColors.glassTextPrimary,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            const Text(_kAddSubtitle,
                                style: TextStyle(
                                    color: AppColors.glassTextSecondary,
                                    fontSize: 13,
                                    height: 1.5)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      const GlassmorphicTextField(hintText: _kAddHint),
                      const SizedBox(height: 18),
                      GradientButton(text: '建立', onPressed: () {}),
                    ],
                  ),
                ),
              ),
              const Spacer(flex: 4),
            ],
          ),
        ),
      ),
    ),
  );
}

// ===========================================================================
// PAGE 2 — New Conversation composer  (problem: 散 / 重心不夠 / 寬度間距不一致)
// ===========================================================================

const _kSeededHer = '哈囉～看你也常爬山，最近有去哪條線嗎？';
const _kSettingsSummary = '交友軟體・剛認識・邀約見面';
const _kSettingsHint = '不確定可以先跳過；AI 會用預設情境分析。';
const _kComposerHint = '最後一則是她說，建立後可直接開始分析。';

Widget _addCircle() => Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: AppColors.glassWhite,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.glassBorder.withValues(alpha: 0.5)),
      ),
      child: const Icon(Icons.add, size: 20, color: AppColors.unselectedText),
    );

Widget _seededList() => GlassmorphicContainer(
      borderRadius: 12,
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: const BubbleAvatar(label: '她', isMe: false, size: 28),
        title: Text(_kSeededHer,
            style: AppTypography.bodyMedium.copyWith(
                color: AppColors.glassTextPrimary, fontWeight: FontWeight.w500)),
        trailing: Icon(Icons.close, size: 18, color: AppColors.glassTextHint),
      ),
    );

Widget _inputRow(String avatar, bool isMe, String hint) => Row(
      children: [
        BubbleAvatar(label: avatar, isMe: isMe, size: 32),
        const SizedBox(width: 8),
        Expanded(child: GlassmorphicTextField(hintText: hint)),
        _addCircle(),
      ],
    );

Widget _hintRow() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_kComposerHint,
                style:
                    AppTypography.caption.copyWith(color: AppColors.textSecondary)),
          ),
        ],
      ),
    );

Widget _seg(List<String> labels, String selected) =>
    GlassmorphicSegmentedButton<String>(
      segments: labels.map((l) => GlassSegment(value: l, label: l)).toList(),
      selected: selected,
      onChanged: (_) {},
    );

/// The real settings block — identical between before & after. Only the OUTER
/// column width/rhythm changes; the settings widget itself is untouched.
List<Widget> _settingsBlock(bool expanded) => [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(expanded ? Icons.expand_less : Icons.expand_more,
              color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('這次分析設定（可不改）',
                    style: AppTypography.bodyLarge.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(_kSettingsSummary,
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Text(_kSettingsHint,
          style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
      if (expanded) ...[
        const SizedBox(height: 16),
        Text('認識情境', style: AppTypography.bodyLarge),
        const SizedBox(height: 8),
        _seg(['交友軟體', '現實認識', '朋友介紹', '其他'], '交友軟體'),
        const SizedBox(height: 16),
        Text('認識多久', style: AppTypography.bodyLarge),
        const SizedBox(height: 8),
        _seg(['剛認識', '幾天', '幾週', '一個月以上'], '剛認識'),
        const SizedBox(height: 16),
        Text('目前目標', style: AppTypography.bodyLarge),
        const SizedBox(height: 8),
        _seg(['邀約見面', '維持熱度', '自然聊天'], '邀約見面'),
        const SizedBox(height: 16),
        Text('補充背景（選填）', style: AppTypography.bodyLarge),
        const SizedBox(height: 8),
        const GlassmorphicTextField(hintText: '沒有可以留空', isDense: true),
        const SizedBox(height: 8),
        Text('把 AI 看不到的關係、背景或你的真實狀態補在這裡。只影響這個對話的分析，不會改對象資料。',
            style: AppTypography.bodySmall
                .copyWith(color: AppColors.textSecondary)),
      ],
    ];

/// Low-alpha frosted tray: gives a section visual MASS so the page stops
/// feeling 空, while the fill stays faint (7%) enough that the opaque glassWhite
/// fields/segments inside still pop. Same warm tokens (glassWhite/glassBorder),
/// no new brand color.
Widget _frostTray(List<Widget> children) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.glassWhite.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border:
            Border.all(color: AppColors.glassBorder.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );

List<Widget> _composerInner() => [
      Text('對話內容', style: AppTypography.bodyLarge),
      const SizedBox(height: 10),
      _seededList(),
      const SizedBox(height: 10),
      _inputRow('她', false, '她說了什麼...'),
      const SizedBox(height: 10),
      _inputRow('我', true, '我說了什麼...'),
      const SizedBox(height: 10),
      _hintRow(),
    ];

// BEFORE: faithful current — loose edge-to-edge stacking, mixed gaps, settings
// header + input rows float bare on the gradient → 散 & 空.
Widget _convoBefore(bool expanded) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('對話對象', style: AppTypography.bodyLarge),
        const SizedBox(height: 8),
        const GlassmorphicTextField(hintText: '例如：小安'),
        const SizedBox(height: 24),
        ..._settingsBlock(expanded),
        const SizedBox(height: 24),
        Text('對話內容', style: AppTypography.bodyLarge),
        const SizedBox(height: 8),
        _seededList(),
        const SizedBox(height: 12),
        _inputRow('她', false, '她說了什麼...'),
        const SizedBox(height: 8),
        _inputRow('我', true, '我說了什麼...'),
        const SizedBox(height: 12),
        _hintRow(),
        const SizedBox(height: 32),
        GradientButton(text: '建立對話', onPressed: () {}),
      ],
    );

// AFTER: same warm widgets — settings & composer each sit in a matching frosted
// tray (consistent width/rhythm → 一致；real mass → 不空), capped 340 + centred.
Widget _convoAfter(bool expanded) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('對話對象', style: AppTypography.bodyLarge),
            const SizedBox(height: 8),
            const GlassmorphicTextField(hintText: '例如：小安'),
            const SizedBox(height: 16),
            _frostTray(_settingsBlock(expanded)),
            const SizedBox(height: 16),
            _frostTray(_composerInner()),
            const SizedBox(height: 20),
            GradientButton(text: '建立對話', onPressed: () {}),
          ],
        ),
      ),
    );

Widget _newConversation({required bool dense, required bool expanded}) {
  return GradientBackground(
    child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: _warmAppBar('手動輸入'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: dense ? _convoAfter(expanded) : _convoBefore(expanded),
      ),
    ),
  );
}

// Side-by-side BEFORE | AFTER in one capture, so each comparison is a single
// openable/screenshot-able image (Eric 2026-06-10).
Widget _panel(String label, Color labelColor, Widget phone, double phoneH) {
  return SizedBox(
    width: 390,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 34,
          color: const Color(0xFF0E0B14),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                  color: labelColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2)),
        ),
        SizedBox(height: phoneH, child: phone),
      ],
    ),
  );
}

Widget _compare(Widget before, Widget after, double phoneH) {
  return ColoredBox(
    color: const Color(0xFF0E0B14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panel('BEFORE', const Color(0xFFB9AEC8), before, phoneH),
        const SizedBox(width: 3),
        _panel('AFTER', const Color(0xFFFFB59A), after, phoneH),
      ],
    ),
  );
}

void main() {
  setUpAll(loadProofFonts);

  testWidgets('add_partner compare', (tester) async {
    await pumpAndCapture(tester,
        child: _compare(_addPartnerBefore(), _addPartnerAfter(), 844),
        outPath: outPath('add_partner_compare.png'),
        size: const Size(783, 878));
  });

  testWidgets('new_conversation collapsed compare', (tester) async {
    await pumpAndCapture(tester,
        child: _compare(
            _newConversation(dense: false, expanded: false),
            _newConversation(dense: true, expanded: false),
            880),
        outPath: outPath('new_conversation_collapsed_compare.png'),
        size: const Size(783, 914));
  });

  testWidgets('new_conversation expanded compare', (tester) async {
    await pumpAndCapture(tester,
        child: _compare(
            _newConversation(dense: false, expanded: true),
            _newConversation(dense: true, expanded: true),
            1320),
        outPath: outPath('new_conversation_expanded_compare.png'),
        size: const Size(783, 1354));
  });
}
