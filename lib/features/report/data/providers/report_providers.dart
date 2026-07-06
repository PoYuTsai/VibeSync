// lib/features/report/data/providers/report_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../analysis_history/data/providers/analysis_history_providers.dart';
import '../../../analysis_history/domain/entities/analysis_history_event.dart';
import '../../../conversation/data/providers/conversation_providers.dart';
import '../services/report_data_service.dart';
import '../../domain/entities/report_models.dart';

final reportDataServiceProvider = Provider<ReportDataService>((ref) {
  return ReportDataService();
});

final reportDataProvider = Provider<ReportData>((ref) {
  final conversations = ref.watch(conversationsProvider);
  final service = ref.watch(reportDataServiceProvider);
  return service.generateReport(conversations);
});

/// 案2：歷史事件快照。autoDispose——離開報告頁釋放，重進重讀 box（Hive
/// box 非 reactive，靠頁面生命週期刷新）。
final analysisHistoryEventsProvider =
    Provider.autoDispose<List<AnalysisHistoryEvent>>((ref) {
  return ref.watch(analysisHistoryRepositoryProvider).listRecent();
});

final analysisSubjectsProvider =
    Provider.autoDispose<List<AnalysisSubject>>((ref) {
  return ref.watch(reportDataServiceProvider).analysisSubjects(
        ref.watch(analysisHistoryEventsProvider),
      );
});

final subjectHeatTrendProvider = Provider.autoDispose
    .family<List<HeatTrendPoint>, String>((ref, conversationId) {
  return ref.watch(reportDataServiceProvider).subjectTrendPoints(
        ref.watch(analysisHistoryEventsProvider),
        conversationId,
      );
});

final practiceTemperatureTrendProvider =
    Provider.autoDispose<List<HeatTrendPoint>>((ref) {
  return ref.watch(reportDataServiceProvider).practiceTemperaturePoints(
        ref.watch(analysisHistoryEventsProvider),
      );
});

/// 案2：對象選擇器選中的 conversationId；null＝預設（清單第一個）。
final selectedReportSubjectProvider =
    StateProvider.autoDispose<String?>((ref) => null);
