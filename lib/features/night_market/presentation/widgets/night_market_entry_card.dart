import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/pressable_scale.dart';

class NightMarketEntryCard extends StatelessWidget {
  const NightMarketEntryCard({super.key});

  @override
  Widget build(BuildContext context) {
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
                  'assets/images/night_market/sydney.jpg',
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
                            Text('和 Sydney 逛夜市',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800)),
                            SizedBox(height: 4),
                            Text('一起逛攤位，練習開口與接話。約 4 分鐘',
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
