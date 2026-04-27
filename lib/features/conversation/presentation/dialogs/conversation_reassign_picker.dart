import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../partner/presentation/widgets/partner_picker_sheet.dart';
import '../../data/providers/conversation_write_controller.dart';
import '../../domain/entities/conversation.dart';

/// Modal sheet that lets the user move a single Conversation to another
/// Partner. Reuses [PartnerPickerSheet] for the list / filter UI.
///
/// Save path: `ConversationWriteController.save(c, previousPartnerId:)` —
/// Phase 1's narrow contract handles the dual-side (`previousPartnerId`
/// + new `partnerId`) invalidation.
///
/// Failure handling: the in-memory `conversation.partnerId` is mutated
/// optimistically before save and rolled back on throw, so the visible
/// state never lies about which Partner owns the conversation.
Future<void> showConversationReassignPicker(
  BuildContext context, {
  required Conversation conversation,
  required WidgetRef ref,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).cardColor,
    builder: (sheetCtx) => SafeArea(
      child: PartnerPickerSheet(
        excludeId: conversation.partnerId,
        onSelected: (target) async {
          final previousPartnerId = conversation.partnerId;
          conversation.partnerId = target.id;
          try {
            await ref
                .read(conversationWriteControllerProvider.notifier)
                .save(conversation, previousPartnerId: previousPartnerId);
            if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
          } catch (_) {
            conversation.partnerId = previousPartnerId;
            if (!sheetCtx.mounted) return;
            ScaffoldMessenger.of(sheetCtx).showSnackBar(
              const SnackBar(content: Text('移動失敗，請稍後再試')),
            );
          }
        },
      ),
    ),
  );
}
