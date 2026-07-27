import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/report_models.dart';

/// 案2：報告頁熱度趨勢的對象選擇器（橫向 chip 列）。
class ReportSubjectSelector extends StatelessWidget {
  final List<AnalysisSubject> subjects;
  final String? selectedSubjectId;
  final ValueChanged<String> onSelected;

  const ReportSubjectSelector({
    super.key,
    required this.subjects,
    required this.selectedSubjectId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final animationDuration =
        MediaQuery.maybeOf(context)?.disableAnimations == true
            ? Duration.zero
            : const Duration(milliseconds: 220);
    final normalizedNameCounts = <String, int>{};
    for (final subject in subjects) {
      final key = subject.name.trim().toLowerCase();
      normalizedNameCounts[key] = (normalizedNameCounts[key] ?? 0) + 1;
    }
    final duplicateDateCounts = <String, int>{};
    for (final subject in subjects) {
      final nameKey = subject.name.trim().toLowerCase();
      if ((normalizedNameCounts[nameKey] ?? 0) < 2) continue;
      final dateKey =
          '$nameKey|${DateFormat('M/d').format(subject.lastEventAt)}';
      duplicateDateCounts[dateKey] = (duplicateDateCounts[dateKey] ?? 0) + 1;
    }
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: subjects.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final subject = subjects[index];
          final selected = subject.subjectId == selectedSubjectId;
          final normalizedName = subject.name.trim().toLowerCase();
          final hasDuplicateName =
              (normalizedNameCounts[normalizedName] ?? 0) > 1;
          final date = DateFormat('M/d').format(subject.lastEventAt);
          final duplicateDateKey = '$normalizedName|$date';
          var label =
              hasDuplicateName ? '${subject.name} · $date' : subject.name;
          if ((duplicateDateCounts[duplicateDateKey] ?? 0) > 1) {
            final ordinal = subjects.take(index + 1).where((candidate) {
              final candidateName = candidate.name.trim().toLowerCase();
              final candidateDate =
                  DateFormat('M/d').format(candidate.lastEventAt);
              return '$candidateName|$candidateDate' == duplicateDateKey;
            }).length;
            label = '$label #$ordinal';
          }
          return Semantics(
            button: true,
            selected: selected,
            label: '查看 $label 的投入趨勢',
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                onTap: () => onSelected(subject.subjectId),
                borderRadius: BorderRadius.circular(20),
                child: AnimatedContainer(
                  duration: animationDuration,
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.ctaStart.withValues(alpha: 0.16)
                        : Colors.white.withValues(alpha: 0.055),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected
                          ? AppColors.ctaStart.withValues(alpha: 0.62)
                          : Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: animationDuration,
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.ctaStart
                              : AppColors.onBackgroundSecondary
                                  .withValues(alpha: 0.42),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w600,
                          color: selected
                              ? Colors.white
                              : AppColors.onBackgroundSecondary
                                  .withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
