import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/brand/brand_feedback_snack_bar.dart';
import '../../../conversation/data/providers/conversation_write_controller.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../../../conversation/presentation/dialogs/delete_conversation_confirm_dialog.dart';

Future<void> confirmDeleteConversation(
  BuildContext context,
  WidgetRef ref,
  Conversation conversation,
) async {
  final dateLabel = DateFormat('MM/dd').format(conversation.updatedAt);
  final messenger = ScaffoldMessenger.of(context);
  final controller = ref.read(conversationWriteControllerProvider.notifier);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => DeleteConversationConfirmDialog(
      dateLabel: dateLabel,
      messageCount: conversation.messages.length,
    ),
  );
  if (confirmed != true) return;

  try {
    await controller.delete(conversation);
    if (!context.mounted) return;
    messenger.showSnackBar(
      buildBrandFeedbackSnackBar(
        title: '已刪除這段互動紀錄',
        icon: Icons.delete_outline_rounded,
      ),
    );
  } catch (error, stackTrace) {
    debugPrint(
      'Conversation record delete failed: $error\n$stackTrace',
    );
    if (!context.mounted) return;
    messenger.showSnackBar(
      buildBrandFeedbackSnackBar(
        title: '刪除失敗，請稍後再試',
        icon: Icons.error_outline_rounded,
        accentColor: AppColors.error,
      ),
    );
  }
}
