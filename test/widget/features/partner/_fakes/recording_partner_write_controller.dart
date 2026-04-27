// test/widget/features/partner/_fakes/recording_partner_write_controller.dart
//
// Hermetic test double for PartnerWriteController. Captures merge() args
// so widget tests can assert PR-B's merge / reassign UX without Hive or
// real provider invalidation.
//
// Mirrors PR-A's RecordingConversationWriteController pattern. Phase 4
// cleanup may unify the two fakes once delete() / update() ship.
import 'package:vibesync/features/partner/data/providers/partner_write_controller.dart';

class RecordingPartnerWriteController extends PartnerWriteController {
  bool mergeCalled = false;
  String? fromId;
  String? toId;
  Object? throwOnMerge;

  @override
  Future<void> merge({
    required String fromId,
    required String toId,
  }) async {
    mergeCalled = true;
    this.fromId = fromId;
    this.toId = toId;
    if (throwOnMerge != null) throw throwOnMerge!;
  }
}
