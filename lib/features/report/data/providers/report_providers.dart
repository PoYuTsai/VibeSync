// lib/features/report/data/providers/report_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
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
