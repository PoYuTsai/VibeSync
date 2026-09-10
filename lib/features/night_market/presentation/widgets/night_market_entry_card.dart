import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../data/night_market_story.dart';
import '../screens/night_market_review_screen.dart';

class NightMarketEntryCard extends StatelessWidget {
  const NightMarketEntryCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _videoCard(context),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            key: const ValueKey('night-market-review-entry'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primaryLight,
            ),
            onPressed: () => _openReview(context),
            icon: const Icon(Icons.menu_book_outlined, size: 18),
            label: const Text('查看復盤'),
          ),
        ),
      ],
    );
  }

  void _openReview(BuildContext context) {
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (reviewContext) => NightMarketReviewScreen(
        scenario: buildNightMarketScenario(),
        onExit: () => Navigator.of(reviewContext).pop(),
        onRestart: () {
          Navigator.of(reviewContext).pop();
          context.push('/practice-night-market');
        },
      ),
    ));
  }

  Widget _videoCard(BuildContext context) {
    return PressableScale(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('night-market-entry-card'),
          onTap: () => context.push('/practice-night-market'),
          child: SizedBox(
            height: 132,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/images/night_market/cover.jpg',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const ColoredBox(
                    color: AppColors.brandSurface2,
                    child: Icon(Icons.local_activity_outlined,
                        color: AppColors.ctaStart, size: 44),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87],
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Icon(Icons.local_activity_outlined,
                          color: AppColors.ctaStart, size: 32),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('簡易搭訕流程詳解',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800)),
                            SizedBox(height: 4),
                            Text('夜市實戰版：從注意到她到加聯繫方式',
                                style: TextStyle(
                                    color: Colors.white70, height: 1.35)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          color: AppColors.ctaStart),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
