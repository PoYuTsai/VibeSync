import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// Game 教學卡收合後的去向：開始攻略＝原地關閉；查看方案＝呼叫端導付費牆；
/// 去圖鑑翻牌＝呼叫端導角色圖鑑（鎖定＋已訂閱：他有每日翻牌額度）。
enum PracticeGameIntroResult { start, viewPlans, goDraw }

/// Game 模式一次性教學卡（Eric 拍板：client 靜態文案教原始術語，附 glossary
/// 對照接回 App 內提示的白話用語；server 端可見詞轉譯規則不變）。
/// 樣式沿用 showPracticeProfileSheet：深色底、圓角、isScrollControlled。
///
/// [locked]＝當前角色非 SR、還進不了 Game（2026-08-08 拍板：點鎖定分頁也開
/// 教學卡，不分 N/R/SR 都要認識玩法）。鎖定時底部 CTA 分流：Free「知道了」
/// （升級導流交給鈎子卡）、已訂閱「去圖鑑翻牌」。
Future<PracticeGameIntroResult?> showPracticeGameIntroSheet(
  BuildContext context, {
  required bool showUpgradeHook,
  bool locked = false,
}) {
  return showModalBottomSheet<PracticeGameIntroResult>(
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

class _PracticeGameIntroSheet extends StatelessWidget {
  const _PracticeGameIntroSheet({
    required this.showUpgradeHook,
    required this.locked,
  });

  final bool showUpgradeHook;
  final bool locked;

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
            Flexible(
              child: SingleChildScrollView(
                key: const ValueKey('practice-game-intro-sheet'),
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _IntroSectionCard(
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
                    const SizedBox(height: 12),
                    const _IntroSectionCard(
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
                    const SizedBox(height: 12),
                    const _IntroSectionCard(
                      icon: Icons.route_outlined,
                      title: '七步節奏（遊戲內五階段）',
                      children: [
                        _IntroBody('開場 → 展示 → 測試 → 張力 → 收尾'),
                        _IntroBullet(
                          lead: '1. 開場',
                          text: '讓她願意回。狀態＋感受，留一半。',
                        ),
                        _IntroBullet(
                          lead: '2. 展示',
                          text: '讓價值以背景資訊自然洩漏，等她來挖。',
                        ),
                        _IntroBullet(
                          lead: '3. 測試',
                          text: '互相篩選。丟出你的標準，也穩穩接住她的小測試。',
                        ),
                        _IntroBullet(
                          lead: '4. 張力',
                          text: '推拉、反差、角色感，拉出情緒波動。',
                        ),
                        _IntroBullet(
                          lead: '5. 收尾',
                          text: '釋放可得性——「我標準很多，但你剛好符合」，'
                              '再低壓邀約。',
                        ),
                        _IntroFootnote(
                          '心法：先練兩端。開不了場一切歸零，收不了尾一切白費；'
                          '中間再逐步加厚。',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const _IntroSectionCard(
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
                    if (showUpgradeHook) ...[
                      const SizedBox(height: 12),
                      const _IntroUpgradeHook(),
                    ],
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('practice-game-intro-cta'),
                  onPressed: () => Navigator.of(context).pop(
                    !locked
                        ? PracticeGameIntroResult.start
                        : showUpgradeHook
                            ? null
                            : PracticeGameIntroResult.goDraw,
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.ctaStart,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    !locked
                        ? '開始攻略'
                        : showUpgradeHook
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

/// 訂閱鈎子：只對 Free 顯示。事實對齊 server（free 每日翻牌 0、續同一位
/// 付費限定）——文案不承諾 SR 機率、不寫死各檔翻牌數字，避免額度調整後漂移。
class _IntroUpgradeHook extends StatelessWidget {
  const _IntroUpgradeHook();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('practice-game-intro-upsell'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.ctaStart.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
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
                '想每天都有新對象可攻略？',
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.ctaStart,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '訂閱後每天都能翻牌認識新對象，遇到 SR 的機會更多；'
            '也能和同一位連續多局，把五階段從開場一路練到收尾。',
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.brandSurface2.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
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
