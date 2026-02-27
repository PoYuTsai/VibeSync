// lib/features/analysis/data/providers/analysis_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../conversation/domain/entities/message.dart';
import '../../../conversation/domain/entities/session_context.dart';
import '../../domain/entities/analysis_models.dart';
import '../services/analysis_service.dart';

/// Provider for AnalysisService
final analysisServiceProvider = Provider<AnalysisService>((ref) {
  return AnalysisService();
});

/// State for analysis operation
sealed class AnalysisState {}

class AnalysisInitial extends AnalysisState {}

class AnalysisLoading extends AnalysisState {}

class AnalysisSuccess extends AnalysisState {
  final AnalysisResult result;
  AnalysisSuccess(this.result);
}

class AnalysisError extends AnalysisState {
  final String message;
  final bool isDailyLimit;
  final bool isMonthlyLimit;

  AnalysisError(
    this.message, {
    this.isDailyLimit = false,
    this.isMonthlyLimit = false,
  });
}

/// Notifier for managing analysis state
class AnalysisNotifier extends StateNotifier<AnalysisState> {
  final AnalysisService _service;

  AnalysisNotifier(this._service) : super(AnalysisInitial());

  Future<void> analyze(
    List<Message> messages, {
    SessionContext? sessionContext,
  }) async {
    state = AnalysisLoading();

    try {
      final result = await _service.analyzeConversation(
        messages,
        sessionContext: sessionContext,
      );
      state = AnalysisSuccess(result);
    } on DailyLimitExceededException catch (e) {
      state = AnalysisError(
        '今日額度已用完 (${e.used}/${e.dailyLimit})',
        isDailyLimit: true,
      );
    } on MonthlyLimitExceededException catch (e) {
      state = AnalysisError(
        '本月額度已用完 (${e.used}/${e.monthlyLimit})',
        isMonthlyLimit: true,
      );
    } on AnalysisException catch (e) {
      state = AnalysisError(e.message);
    }
  }

  void reset() {
    state = AnalysisInitial();
  }
}

/// Provider for analysis state management
final analysisNotifierProvider =
    StateNotifierProvider<AnalysisNotifier, AnalysisState>((ref) {
  final service = ref.watch(analysisServiceProvider);
  return AnalysisNotifier(service);
});
