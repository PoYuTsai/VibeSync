import 'package:vibesync/features/coaching_memory/data/services/coaching_outcome_uploader.dart';
import 'package:vibesync/features/coaching_memory/domain/entities/coaching_outcome_event.dart';

/// Test double for [CoachingOutcomeUploader] that records upload calls instead
/// of hitting the network. Keeps recorder tests off Supabase / subscription.
class RecordingCoachingOutcomeUploader extends CoachingOutcomeUploader {
  RecordingCoachingOutcomeUploader() : super();

  final List<CoachingOutcomeEvent> uploaded = <CoachingOutcomeEvent>[];

  int get uploadCount => uploaded.length;

  @override
  Future<void> upload(CoachingOutcomeEvent event) async {
    uploaded.add(event);
  }
}
