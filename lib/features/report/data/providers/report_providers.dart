// lib/features/report/data/providers/report_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../analysis_history/data/providers/analysis_history_providers.dart';
import '../../../analysis_history/domain/entities/analysis_history_event.dart';
import '../../../conversation/data/providers/conversation_providers.dart';
import '../../../partner/presentation/providers/partner_providers.dart';
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

final _analysisHistoryChangesProvider = StreamProvider.autoDispose<void>((ref) {
  return ref.watch(analysisHistoryRepositoryProvider).watchChanges();
});

/// 歷史事件快照。初次進頁直接讀取，Hive 每次 append / clear 後也會重讀，
/// 因此報告保持開啟時仍能收到最新分析。
final analysisHistoryEventsProvider =
    Provider.autoDispose<List<AnalysisHistoryEvent>>((ref) {
  ref.watch(_analysisHistoryChangesProvider);
  return ref.watch(analysisHistoryRepositoryProvider).listRecent();
});

final analysisSubjectsProvider =
    Provider.autoDispose<List<AnalysisSubject>>((ref) {
  return ref.watch(reportDataServiceProvider).analysisSubjects(
        ref.watch(analysisHistoryEventsProvider),
        ref.watch(conversationsProvider),
        ref.watch(partnerListProvider),
      );
});

final subjectHeatTrendProvider =
    Provider.autoDispose.family<List<HeatTrendPoint>, String>((ref, subjectId) {
  return ref.watch(reportDataServiceProvider).subjectTrendPoints(
        ref.watch(analysisHistoryEventsProvider),
        subjectId,
        ref.watch(conversationsProvider),
      );
});

final practiceTemperatureTrendProvider =
    Provider.autoDispose<List<HeatTrendPoint>>((ref) {
  return ref.watch(reportDataServiceProvider).practiceTemperaturePoints(
        ref.watch(analysisHistoryEventsProvider),
      );
});

/// 對象選擇器選中的 canonical subjectId（partnerId 優先）；null＝預設。
final selectedReportSubjectProvider =
    StateProvider.autoDispose<String?>((ref) => null);
