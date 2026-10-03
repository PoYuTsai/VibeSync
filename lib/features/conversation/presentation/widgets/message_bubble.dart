// lib/features/conversation/presentation/widgets/message_bubble.dart
import 'package:flutter/material.dart';

import '../../../../core/services/app_haptics.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/message.dart';
import '../../../../shared/widgets/brand/app_sheet.dart';

/// 分析片段裡的一則訊息（2026-10-02 A 案「LINE 熟悉感」）。
///
/// 說話者只靠左右與底色分辨：她＝白泡泡靠左、我＝蜜桃泡泡靠右，不再在
/// 每顆寫「她說／我說」（改由 Semantics 念給 VoiceOver）。同一人連發時只有
/// 第一顆帶尾巴角與頭像，間距由片段卡控制。
///
/// 引用小卡只顯示截圖裡的原文。舊的「引用我剛剛說的／引用對方剛剛說的」
/// 標題靠 `quotedReplyPreviewIsFromMe` 判斷，但它記的是引用卡在截圖哪一側
/// （`blocktype_fold.ts`），群組裡回覆第三人時會說錯人，所以拿掉；引用
/// 作者等辨識把 `quotedName` 送到 App 再顯示。
class MessageBubble extends StatelessWidget {
  final Message message;
  final VoidCallback? onSwapSide;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;

  /// 同一人連發的第一則：帶尾巴角，對方那側再掛頭像。
  final bool isGroupStart;

  /// 對方頭像上的字（對象名字的第一個字）；null＝不留頭像欄。
  final String? partnerInitial;

  const MessageBubble({
    super.key,
    required this.message,
    this.onSwapSide,
    this.onDelete,
    this.onEdit,
    this.isGroupStart = true,
    this.partnerInitial,
  });

  static const _radius = Radius.circular(18);

  // 尾巴角 5：每組第一顆貼向說話者那側（DESIGN.md §4 聊天泡泡尾巴）。
  static const _tailRadius = Radius.circular(5);
  static const _avatarSize = 30.0;
  static const _avatarGap = 8.0;

  @override
  Widget build(BuildContext context) {
    final hasActions = onSwapSide != null || onDelete != null || onEdit != null;
    final isMe = message.isFromMe;
    final quote = message.quotedReplyPreview?.trim();
    final hasQuote = quote != null && quote.isNotEmpty;
    final initial = isMe ? null : partnerInitial;

    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.7,
      ),
      // 有引用時內距縮成 6 讓小卡貼近泡泡邊緣，內文再補 6，左緣仍對齊 12。
      padding: hasQuote
          ? const EdgeInsets.fromLTRB(6, 6, 6, 8)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isMe ? AppColors.transcriptBubbleMine : Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: !isMe && isGroupStart ? _tailRadius : _radius,
          topRight: isMe && isGroupStart ? _tailRadius : _radius,
          bottomLeft: _radius,
          bottomRight: _radius,
        ),
        // 不描邊，只用一道中性微陰影把泡泡托離底板。
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      // 泡泡寬度跟著內文或引用較寬的那個走，引用小卡再撐滿泡泡；有引用
      // 不會再整排撐到最寬，內文也一律靠左。
      child: IntrinsicWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (quote != null && quote.isNotEmpty)
              _QuoteCard(text: quote, isMe: isMe),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: hasQuote ? 6 : 0),
              child: Text(
                message.content,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.glassTextPrimary,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // VoiceOver 一次念完一則：說話者、引用、回覆分開標明，避免把引用那句
    // 聽成說話者自己說的（PR #86 審查 P2-3）。
    final speaker = isMe ? '我說' : '她說';
    final semanticsLabel = hasQuote
        ? '$speaker\n引用：$quote\n回覆：${message.content}'
        : '$speaker\n${message.content}';

    return MergeSemantics(
      child: GestureDetector(
        // opaque：整個 bubble（含 padding 與兩側空白）都接收 long-press。
        // 預設 deferToChild 只認 Text 渲染區，user 必須按到「字」才觸發
        // — Bruce/Eric 2026-05-23 dogfood 點出這個跟視覺直覺落差。
        behavior: HitTestBehavior.opaque,
        onLongPress: hasActions
            ? () {
                AppHaptics.light();
                _showActionMenu(context);
              }
            : null,
        // 標籤包在手勢裡面：子層文字不再各自念，長按動作仍併進同一個節點。
        child: Semantics(
          label: semanticsLabel,
          excludeSemantics: true,
          child: Align(
            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: initial == null
                  ? bubble
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isGroupStart)
                          _PartnerAvatar(initial: initial)
                        else
                          const SizedBox(width: _avatarSize),
                        const SizedBox(width: _avatarGap),
                        Flexible(child: bubble),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  void _showActionMenu(BuildContext context) {
    showAppSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppColors.glassWhite,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.glassBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              // Preview of the message
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  message.content,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.glassTextSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (onEdit != null)
                ListTile(
                  leading: Icon(Icons.edit_outlined, color: AppColors.primary),
                  title: Text(
                    '編輯文字',
                    style: TextStyle(color: AppColors.glassTextPrimary),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    onEdit!();
                  },
                ),
              if (onSwapSide != null)
                ListTile(
                  leading: Icon(Icons.swap_horiz, color: AppColors.primary),
                  title: Text(
                    message.isFromMe ? '改成她說' : '改成我說',
                    style: TextStyle(color: AppColors.glassTextPrimary),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    onSwapSide!();
                  },
                ),
              if (onDelete != null)
                ListTile(
                  leading: Icon(Icons.delete_outline, color: AppColors.error),
                  title: Text(
                    '刪除這則訊息',
                    style: TextStyle(color: AppColors.error),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    onDelete!();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// 對方頭像：每組第一顆泡泡旁的霧玫瑰圓章，上面是對象名字的第一個字。
/// 只是視覺錨點，語意由泡泡的整則標籤負責。
class _PartnerAvatar extends StatelessWidget {
  const _PartnerAvatar({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: MessageBubble._avatarSize,
      height: MessageBubble._avatarSize,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.partnerRoseStart, AppColors.partnerRoseEnd],
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: AppTypography.titleMedium.copyWith(
            // 白字在霧玫瑰上只有 2.8:1；深墨 6.7:1（DESIGN.md §8）。
            color: AppColors.brandInk,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// 泡泡內的引用小卡：說話側色條＋最多兩行原文（Telegram／WhatsApp 的
/// 引用讀法）。
class _QuoteCard extends StatelessWidget {
  const _QuoteCard({required this.text, required this.isMe});

  final String text;
  final bool isMe;

  // 微圓角 6＝外圓角 18 的 1/3（DESIGN.md §4 登記）；用 18 會變成 pill。
  static const _radius = BorderRadius.all(Radius.circular(6));

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color:
            isMe ? Colors.white.withValues(alpha: 0.55) : AppColors.glassWhite,
        borderRadius: _radius,
        border: Border(
          left: BorderSide(
            color: isMe ? AppColors.ctaEnd : AppColors.primary,
            width: 3,
          ),
        ),
      ),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.bodySmall.copyWith(
          color: AppColors.glassTextSecondary,
        ),
      ),
    );
  }
}
