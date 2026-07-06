import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/storage_service.dart';
import '../../domain/repositories/analysis_history_repository.dart';
import '../repositories/analysis_history_repository_impl.dart';

final analysisHistoryRepositoryProvider =
    Provider<AnalysisHistoryRepository>((ref) {
  return AnalysisHistoryRepositoryImpl(
    StorageService.analysisHistoryEventsBox,
  );
});
