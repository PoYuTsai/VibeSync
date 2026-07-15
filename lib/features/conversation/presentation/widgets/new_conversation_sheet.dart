// lib/features/conversation/presentation/widgets/new_conversation_sheet.dart
//
// Shared bottom sheet for creating new conversations. Pure move from
// `lib/app/main_shell.dart` (`_NewConversationSheet`) — no behavior change.
//
// Partner-bound entry creates an independent analysis fragment. The global
// entry keeps the broader "new conversation" wording.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_feedback_snack_bar.dart';
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

  String get _openerLocation {
    final id = partnerId;
    if (id == null || id.isEmpty) return '/opener';
    return Uri(
      path: '/opener',
      queryParameters: {'partnerId': id},
    ).toString();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPartner = partnerId != null && partnerId!.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.glassWhite,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              hasPartner ? '分析新片段' : '新增對話',
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.glassTextPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hasPartner ? '只放這次想讓 AI 看的內容，不會接到舊紀錄' : '建立一段新的互動紀錄',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.unselectedText,
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
                hasPartner ? '貼上這次要分析的一段聊天' : '貼上或輸入一段聊天',
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
                hasPartner ? '選這次要分析的聊天截圖，會建立獨立片段' : '選聊天截圖，AI 辨識後會建立互動紀錄',
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
                    buildBrandFeedbackSnackBar(
                      title: '建立對話失敗，請再試一次',
                      icon: Icons.error_outline_rounded,
                      accentColor: AppColors.error,
                    ),
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
                context.push(_openerLocation);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
