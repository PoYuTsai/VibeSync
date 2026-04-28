// test/widget/features/partner/_fakes/recording_partner_write_controller.dart
//
// Hermetic test double for PartnerWriteController. Captures write-side args
// so widget tests can assert merge / rename UX without Hive or real provider
// invalidation.
import 'package:vibesync/features/partner/data/providers/partner_write_controller.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';

class RecordingPartnerWriteController extends PartnerWriteController {
  bool mergeCalled = false;
  String? fromId;
  String? toId;
  Object? throwOnMerge;

  bool updateNameCalled = false;
  Partner? updatedPartner;
  String? updatedName;
  Object? throwOnUpdateName;

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

  @override
  Future<void> updateName(Partner partner, String newName) async {
    updateNameCalled = true;
    updatedPartner = partner;
    updatedName = newName;
    if (throwOnUpdateName != null) throw throwOnUpdateName!;
  }
}
