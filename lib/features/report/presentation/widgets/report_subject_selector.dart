import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/report_models.dart';

/// 案2：報告頁熱度趨勢的對象選擇器（橫向 chip 列）。
class ReportSubjectSelector extends StatelessWidget {
  final List<AnalysisSubject> subjects;
  final String? selectedConversationId;
  final ValueChanged<String> onSelected;

  const ReportSubjectSelector({
    super.key,
    required this.subjects,
    required this.selectedConversationId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: subjects.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final subject = subjects[index];
          final selected = subject.conversationId == selectedConversationId;
          return GestureDetector(
            onTap: () => onSelected(subject.conversationId),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.ctaStart
                    : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                subject.name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? Colors.white
                      : AppColors.onBackgroundSecondary
                          .withValues(alpha: 0.85),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
