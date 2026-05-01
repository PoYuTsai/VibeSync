import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/glassmorphic_container.dart';
import '../../../partner/presentation/providers/partner_providers.dart';

/// Edit screen for per-partner style overrides — Spec 2 Phase 6.
///
/// Phase progression:
///  - Task 14 (this commit): scaffold + dynamic title + section headers
///    only. Section bodies are placeholders; PopScope is wired but no-op.
///  - Tasks 15-17: fill in chip / textfield bodies + reset links.
///  - Task 18: PopScope auto-save + 重設整個對象風格 action.
class PartnerStyleEditScreen extends ConsumerWidget {
  const PartnerStyleEditScreen({super.key, required this.partnerId});

  final String partnerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partner = ref.watch(partnerByIdProvider(partnerId));
    final title =
        partner == null ? '我的風格' : '我的風格 · ${partner.name}';

    return PopScope(
      // Auto-save plumbing lands in Task 18 — keeping the wrapper here so
      // the future change touches behavior only, not the widget tree shape.
      canPop: true,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(
            color: AppColors.onBackgroundPrimary,
          ),
          title: Text(
            title,
            style: const TextStyle(color: AppColors.onBackgroundPrimary),
          ),
        ),
        body: Stack(
          children: [
            const Positioned.fill(child: _EditScreenBackground()),
            SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, kToolbarHeight, 16, 32),
                children: const [
                  _SectionPlaceholder(title: '互動風格'),
                  SizedBox(height: 16),
                  _SectionPlaceholder(title: '練習目標'),
                  SizedBox(height: 16),
                  _SectionPlaceholder(title: '備註'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionPlaceholder extends StatelessWidget {
  const _SectionPlaceholder({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return GlassmorphicContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.glassTextPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '即將上線',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.glassTextSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _EditScreenBackground extends StatelessWidget {
  const _EditScreenBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.partnerDetailBgTop,
            AppColors.partnerDetailBgBottom,
          ],
        ),
      ),
    );
  }
}
