// lib/features/conversation/presentation/widgets/new_conversation_sheet.dart
//
// Shared bottom sheet for creating new conversations. Pure move from
// `lib/app/main_shell.dart` (`_NewConversationSheet`) — no behavior change.
// Title string「新增對話」intentionally stays untouched here; Phase 4 Task 15
// owns the global「對話」→「對象」copy sweep including this title.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../data/providers/conversation_write_controller.dart';

class NewConversationSheet extends ConsumerWidget {
  final String? partnerId;

  const NewConversationSheet({super.key, this.partnerId});

  String get _manualEntryLocation {
    final id = partnerId;
    if (id == null) return '/new';
    return Uri(
      path: '/new',
      queryParameters: {'partnerId': id},
    ).toString();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.glassWhite,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '新增對話',
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.glassTextPrimary,
            ),
          ),
          const SizedBox(height: 20),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.edit_note, color: AppColors.primary),
            ),
            title: Text(
              '手動輸入',
              style: TextStyle(color: AppColors.glassTextPrimary),
            ),
            subtitle: Text(
              '輸入聊天內容並開始分析',
              style: TextStyle(color: AppColors.unselectedText, fontSize: 12),
            ),
            onTap: () {
              final router = GoRouter.of(context);
              Navigator.pop(context);
              router.push(_manualEntryLocation);
            },
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.ctaStart.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.photo_camera, color: AppColors.ctaStart),
            ),
            title: Text(
              '截圖開始',
              style: TextStyle(color: AppColors.glassTextPrimary),
            ),
            subtitle: Text(
              '從相簿選擇聊天截圖，AI 先幫你辨識再建立對話',
              style: TextStyle(color: AppColors.unselectedText, fontSize: 12),
            ),
            onTap: () async {
              final router = GoRouter.of(context);
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(context);
              try {
                final conversation = await ref
                    .read(conversationWriteControllerProvider.notifier)
                    .create(
                      name: '新對話',
                      messages: [],
                      partnerId: partnerId,
                    );
                router.push('/conversation/${conversation.id}');
              } catch (_) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('建立對話失敗，請再試一次')),
                );
              }
            },
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.bokehYellow.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.auto_awesome, color: AppColors.bokehYellow),
            ),
            title: Text(
              '開場救星',
              style: TextStyle(color: AppColors.glassTextPrimary),
            ),
            subtitle: Text(
              '交友軟體不知道怎麼開場？AI 幫你生成開場白',
              style: TextStyle(color: AppColors.unselectedText, fontSize: 12),
            ),
            onTap: () {
              Navigator.pop(context);
              context.push('/opener');
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
