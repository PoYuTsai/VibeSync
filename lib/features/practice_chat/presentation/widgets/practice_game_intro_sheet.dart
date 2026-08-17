import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/app_sheet.dart';

/// Game 教學卡收合後的去向：開始攻略＝原地關閉；查看方案＝呼叫端導付費牆；
/// 去圖鑑翻牌＝呼叫端導角色圖鑑（鎖定＋已訂閱：他有每日翻牌額度）。
enum PracticeGameIntroResult { start, viewPlans, goDraw }

/// Game 模式一次性教學卡（Eric 拍板：client 靜態文案教原始術語，附 glossary
/// 對照接回 App 內提示的白話用語；server 端可見詞轉譯規則不變）。
/// 樣式沿用 showPracticeProfileSheet：深色底、圓角、isScrollControlled。
///
/// 2026-08-10 拍板改兩頁：第一頁觀念（這是什麼／四變數／工具與卡點）、
/// 第二頁機制（七步併五階段圖＋計分規則）。CTA 第一頁固定「下一頁」，
/// 收合分流（開始攻略／知道了／去圖鑑翻牌）只在第二頁。
///
/// [locked]＝當前角色非 SR、還進不了 Game（2026-08-08 拍板：點鎖定分頁也開
/// 教學卡，不分 N/R/SR 都要認識玩法）。鎖定時底部 CTA 分流：Free「知道了」
/// （升級導流交給鈎子卡）、已訂閱「去圖鑑翻牌」。
Future<PracticeGameIntroResult?> showPracticeGameIntroSheet(
  BuildContext context, {
  required bool showUpgradeHook,
  bool locked = false,
}) {
  return showAppSheet<PracticeGameIntroResult>(
    context: context,
    backgroundColor: AppColors.brandInk,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _PracticeGameIntroSheet(
      showUpgradeHook: showUpgradeHook,
      locked: locked,
    ),
  );
}

class _PracticeGameIntroSheet extends StatefulWidget {
  const _PracticeGameIntroSheet({
    required this.showUpgradeHook,
    required this.locked,
  });

  final bool showUpgradeHook;
  final bool locked;

  @override
  State<_PracticeGameIntroSheet> createState() =>
      _PracticeGameIntroSheetState();
}

class _PracticeGameIntroSheetState extends State<_PracticeGameIntroSheet> {
  final _pageController = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.86,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.sports_esports_outlined,
                  size: 20,
                  color: AppColors.ctaStart,
                ),
                const SizedBox(width: 8),
                Text(
                  'Game 攻略指南',
                  style: AppTypography.titleMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            Expanded(
              child: PageView(
                key: const ValueKey('practice-game-intro-sheet'),
                controller: _pageController,
                onPageChanged: (page) => setState(() => _page = page),
                children: [
                  const _IntroConceptPage(),
                  _IntroMechanicsPage(showUpgradeHook: widget.showUpgradeHook),
                ],
              ),
            ),
            const SizedBox(height: 6),
            _PageDots(page: _page),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: _page == 0
                    ? FilledButton(
                        key: const ValueKey('practice-game-intro-next'),
                        onPressed: () => _pageController.animateToPage(
                          1,
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.ctaStart,
                          foregroundColor: AppColors.onCta,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('下一頁：節奏與計分'),
                      )
                    : FilledButton(
                        key: const ValueKey('practice-game-intro-cta'),
                        onPressed: () => Navigator.of(context).pop(
                          !widget.locked
                              ? PracticeGameIntroResult.start
                              : widget.showUpgradeHook
                                  ? null
                                  : PracticeGameIntroResult.goDraw,
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.ctaStart,
                          foregroundColor: AppColors.onCta,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Text(
                          !widget.locked
                              ? '開始攻略'
                              : widget.showUpgradeHook
                                  ? '知道了'
                                  : '去圖鑑翻牌',
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 第一頁：觀念——這遊戲在練什麼。
class _IntroConceptPage extends StatelessWidget {
  const _IntroConceptPage();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          _IntroSectionCard(
            icon: Icons.flag_outlined,
            title: '這是什麼',
            children: [
              _IntroBody(
                'Game 是 SR 限定的攻略型練習。目標只有一個：'
                '照七步節奏，把關係推進到可約的窗口。',
              ),
              _IntroBody(
                '她的反應比其他模式更真實直接——你做對，她更快投入；'
                '太急、太油、框架崩，她冷得也更快。',
              ),
            ],
          ),
          SizedBox(height: 12),
          _IntroSectionCard(
            icon: Icons.tune,
            title: '四個核心變數',
            children: [
              _IntroBody(
                '所有技巧都在調節四個變數。複盤時別背話術，問自己：'
                '這句話在動哪個變數？',
              ),
              _IntroBullet(
                lead: '價值（Value）',
                text: '她覺得你值不值得聊。用生活片段側面展示（DHV），'
                    '不要自誇——被問出來的價值才可信。',
              ),
              _IntroBullet(
                lead: '框架（Frame）',
                text: '你穩不穩、有沒有主見。被測試時不自證、不慌、'
                    '不過度道歉。',
              ),
              _IntroBullet(
                lead: '情緒（Emotion）',
                text: '沒波動就沒心跳。用「狀態＋感受」和推拉製造起伏，'
                    '別查戶口。',
              ),
              _IntroBullet(
                lead: '投資（Investment）',
                text: '讓她主動問、主動延伸。說話留一半，讓她追問——'
                    '她投入越多，越會說服自己「我是真的想聊」。',
              ),
              _IntroFootnote(
                '＊App 內提示會用白話版：框架→「節奏與主見」、'
                '推拉→「輕鬆張力」、DHV→「生活樣本」、'
                '篩選→「互相合適度」。',
              ),
            ],
          ),
          SizedBox(height: 12),
          _IntroSectionCard(
            icon: Icons.handyman_outlined,
            title: '工具與常見卡點',
            children: [
              _IntroBullet(
                lead: '溫度計＋熟悉度',
                text: '即時看每句話的效果。',
              ),
              _IntroBullet(
                lead: '提示（每局 5 次）',
                text: '告訴你現在第幾步、該動哪個變數、下一句怎麼說。',
              ),
              _IntroBullet(
                lead: '結束拆盤',
                text: '指出關鍵轉折、沒動到的變數、下次第一句怎麼改。',
              ),
              _IntroBody(
                '常見卡點：查戶口冷場、工具人感、太油（越級升溫）、'
                '框架掉了（被測試時自證）、節奏熄火（好感給太滿）。',
              ),
              _IntroFootnote(
                '邊界：所有推進都要低壓、可退。她說不，就是不。',
              ),
            ],
          ),
          SizedBox(height: 4),
        ],
      ),
    );
  }
}

/// 第二頁：機制——遊戲怎麼推進、怎麼判分。
/// 階段圖對齊 server 實作（game_fsm basePhaseFor）：正常節奏 P1→P2→P4→P5
/// 由熟悉度/升溫門檻推進，P3 測試是她起防備時的條件插入，不排隊。
/// 圖上刻意不標門檻數字——client 靜態文案不寫死 server 可調參數。
class _IntroMechanicsPage extends StatelessWidget {
  const _IntroMechanicsPage({required this.showUpgradeHook});

  final bool showUpgradeHook;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _IntroSectionCard(
            icon: Icons.route_outlined,
            title: '七步節奏（遊戲內五階段）',
            children: [
              _IntroBody(
                '七步合併成五階段。正常節奏走四階，'
                '熟悉度與升溫夠了才進下一階；每句話重算，掉分會退回去。',
              ),
              _PhaseDiagram(),
              _IntroFootnote(
                '＊P3 不排隊：她起防備的當下就是測試——'
                '接住了才回到原節奏。',
              ),
            ],
          ),
          const SizedBox(height: 12),
          const _IntroSectionCard(
            icon: Icons.swap_vert,
            title: '分數怎麼算',
            children: [
              _ScoreRow(text: '接住她的情緒或前文', chip: _ScoreChip.plus),
              _ScoreRow(text: '接住她的小測試', chip: _ScoreChip.plus),
              _ScoreRow(text: '沒接住、答非所問', chip: _ScoreChip.minorMinus),
              _ScoreRow(text: '防禦、自證、查戶口', chip: _ScoreChip.midMinus),
              _ScoreRow(text: '太急太油、越級升溫', chip: _ScoreChip.majorMinus),
              _IntroFootnote(
                'Game 的加減分幅度接近其他模式的兩倍——進步和翻車都更快；'
                '框架崩或讓她不舒服時，扣分放大得最兇。',
              ),
            ],
          ),
          if (showUpgradeHook) ...[
            const SizedBox(height: 12),
            const _IntroUpgradeHook(),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

/// 七步併五階段圖：正常節奏四列（進度條漸長），虛線下方是條件插入的 P3。
class _PhaseDiagram extends StatelessWidget {
  const _PhaseDiagram();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: const [
        _PhaseRow(
          code: 'P1',
          name: '開場',
          steps: '破冰＋資訊交換',
          barFraction: 0.24,
        ),
        SizedBox(height: 8),
        _PhaseRow(
          code: 'P2',
          name: '展示',
          steps: '側面價值',
          barFraction: 0.44,
        ),
        SizedBox(height: 8),
        _PhaseRow(
          code: 'P4',
          name: '張力',
          steps: '推拉／角色感',
          barFraction: 0.66,
        ),
        SizedBox(height: 8),
        _PhaseRow(
          code: 'P5',
          name: '收尾',
          steps: '可得性＋邀約',
          barFraction: 0.88,
        ),
        SizedBox(height: 12),
        _DashedDivider(),
        SizedBox(height: 8),
        _PhaseRow(
          code: 'P3',
          name: '測試',
          steps: '篩選／小測試·她起防備時',
          barFraction: null,
          emphasized: true,
        ),
      ],
    );
  }
}

class _PhaseRow extends StatelessWidget {
  const _PhaseRow({
    required this.code,
    required this.name,
    required this.steps,
    required this.barFraction,
    this.emphasized = false,
  });

  final String code;
  final String name;
  final String steps;

  /// 進度條相對長度；null＝不畫（條件插入的 P3）。
  final double? barFraction;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final fraction = barFraction;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                code,
                style: AppTypography.caption.copyWith(
                  color: AppColors.onBackgroundSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              name,
              style: AppTypography.bodySmall.copyWith(
                color: emphasized ? AppColors.ctaStart : Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                steps,
                textAlign: TextAlign.end,
                style: AppTypography.caption.copyWith(
                  color: AppColors.onBackgroundSecondary,
                ),
              ),
            ),
          ],
        ),
        if (fraction != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: fraction,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppColors.ctaStart,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dashWidth = 5.0;
        const gap = 4.0;
        final count =
            (constraints.maxWidth / (dashWidth + gap)).floor().clamp(1, 200);
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < count; i++)
              Container(
                width: dashWidth,
                height: 1,
                color: AppColors.onBackgroundSecondary.withValues(alpha: 0.35),
              ),
          ],
        );
      },
    );
  }
}

enum _ScoreChip { plus, minorMinus, midMinus, majorMinus }

class _ScoreRow extends StatelessWidget {
  const _ScoreRow({required this.text, required this.chip});

  final String text;
  final _ScoreChip chip;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (chip) {
      _ScoreChip.plus => ('加分', AppColors.success),
      _ScoreChip.minorMinus => ('小扣', AppColors.warning),
      _ScoreChip.midMinus => ('中扣', AppColors.error),
      _ScoreChip.majorMinus => ('重扣', AppColors.error),
    };
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundPrimary,
              height: 1.55,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: AppTypography.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.page});

  final int page;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 2; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: i == page ? 16 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == page
                  ? AppColors.ctaStart
                  : AppColors.onBackgroundSecondary.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ],
    );
  }
}

/// 訂閱鈎子：只對 Free 顯示。主承諾＝訂閱送一次 SR 限定翻牌（2026-08-08 拍板，
/// 機制已上線才講——批 1 曾刻意保留舊話術避免空頭支票）；其餘事實對齊 server
/// （free 每日翻牌 0）——不承諾 SR 機率、不寫死各檔翻牌數字，避免額度調整後漂移。
class _IntroUpgradeHook extends StatelessWidget {
  const _IntroUpgradeHook();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('practice-game-intro-upsell'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.ctaStart.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.ctaStart.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: AppColors.ctaStart),
              const SizedBox(width: 6),
              Text(
                '訂閱直接解鎖 Game',
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.ctaStart,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '訂閱就送一次 SR 限定翻牌，馬上開一位 SR 對象進 Game；'
            '之後每天還能翻牌認識新對象、和同一位連續多局，'
            '把五階段從開場一路練到收尾。',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const ValueKey('practice-game-intro-upsell-cta'),
              onPressed: () => Navigator.of(context)
                  .pop(PracticeGameIntroResult.viewPlans),
              child: Text(
                '查看方案',
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.ctaStart,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IntroSectionCard extends StatelessWidget {
  const _IntroSectionCard({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.brandSurface2.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.onBackgroundSecondary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.ctaStart),
              const SizedBox(width: 6),
              Text(
                title,
                style: AppTypography.labelMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final (index, child) in children.indexed) ...[
            if (index > 0) const SizedBox(height: 6),
            child,
          ],
        ],
      ),
    );
  }
}

class _IntroBody extends StatelessWidget {
  const _IntroBody(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTypography.bodySmall.copyWith(
        color: AppColors.onBackgroundSecondary,
        height: 1.55,
      ),
    );
  }
}

class _IntroBullet extends StatelessWidget {
  const _IntroBullet({required this.lead, required this.text});

  final String lead;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '・$lead：',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundPrimary,
              fontWeight: FontWeight.w700,
              height: 1.55,
            ),
          ),
          TextSpan(
            text: text,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundSecondary,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

class _IntroFootnote extends StatelessWidget {
  const _IntroFootnote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTypography.caption.copyWith(
        color: AppColors.onBackgroundSecondary.withValues(alpha: 0.75),
        height: 1.5,
      ),
    );
  }
}
