/// v3 任務卡（結果頁與分析紀錄共用）：任務標籤直接給用戶看（設計文件第 5 節），
/// 點一則複製一則、整張一起複製；有空格（「＿」）的卡一定要先填好才能複製，
/// 照樣寫＋標示的卡提醒「有編的細節，請改成你的」。複製本身與成效紀錄由呼叫端
/// 做（這裡只給文字），所以結果頁與紀錄頁可以各自決定要不要記錄。
library;

import 'package:flutter/material.dart';

import '../../../../core/services/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/app_sheet.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../domain/entities/guide_v3_result.dart';

/// 照樣寫＋標示的提醒（設計文件第 5 節的字）。
const guideV3InventedNotice = '有編的細節，請改成你的';

Color guideV3TaskColor(GuideV3Task task) => switch (task) {
      GuideV3Task.accept => AppColors.info,
      GuideV3Task.resonate => AppColors.coachAccentBright,
      GuideV3Task.tension => AppColors.coachRecommendation,
      GuideV3Task.push => AppColors.ctaStart,
      GuideV3Task.close => AppColors.onBackgroundSecondary,
    };

class GuideV3TaskChip extends StatelessWidget {
  const GuideV3TaskChip({super.key, required this.task});

  final GuideV3Task task;

  @override
  Widget build(BuildContext context) {
    final color = guideV3TaskColor(task);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        task.label,
        style: AppTypography.labelMedium.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 把「＿」那一段標出來，讓他一眼看到哪裡要填。
Widget _blankAwareText(String text, TextStyle style) {
  if (!guideV3TextHasBlank(text)) return Text(text, style: style);
  final spans = <TextSpan>[];
  final pattern = RegExp('$guideV3BlankMark+');
  var cursor = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, match.start)));
    }
    spans.add(TextSpan(
      text: match.group(0),
      style: style.copyWith(
        color: AppColors.warning,
        fontWeight: FontWeight.w800,
        decoration: TextDecoration.underline,
        decorationColor: AppColors.warning,
      ),
    ));
    cursor = match.end;
  }
  if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
  return Text.rich(TextSpan(style: style, children: spans));
}

BoxDecoration _cardDecoration({Color? border}) => BoxDecoration(
      color: AppColors.brandInk.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: border ?? Colors.white.withValues(alpha: 0.12),
      ),
    );

class GuideV3TaskCard extends StatelessWidget {
  const GuideV3TaskCard({
    super.key,
    required this.card,
    this.editedMessages,
    this.onCopy,
    this.onEdit,
    this.footer,
  });

  final GuideV3Card card;

  /// 他填過空格或改過的版本；null＝照伺服器原樣。
  final List<String>? editedMessages;

  /// 複製（文字、提示）；null＝這個畫面不給複製。
  final void Function(String text, String toast)? onCopy;

  /// 打開填空／改寫；有空格的卡要先經過這裡才能複製。
  final VoidCallback? onEdit;

  /// 卡片下方（例如複製後的成效回報列）。
  final Widget? footer;

  List<String> get _messages => editedMessages ?? card.messages;

  bool get _needsFill => _messages.any(guideV3TextHasBlank);

  @override
  Widget build(BuildContext context) {
    final messages = _messages;
    final edited = editedMessages != null;
    final textStyle = AppTypography.bodyLarge.copyWith(
      color: AppColors.onBackgroundPrimary,
      height: 1.45,
    );
    return Container(
      key: ValueKey('guide-v3-card-${card.slot}'),
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GuideV3TaskChip(task: card.task),
              const Spacer(),
              if (edited)
                Text(
                  '已改成你的',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.onBackgroundSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < messages.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            InkWell(
              key: ValueKey('guide-v3-card-${card.slot}-message-$i'),
              borderRadius: BorderRadius.circular(14),
              onTap: onCopy == null
                  ? null
                  : () {
                      if (guideV3TextHasBlank(messages[i])) {
                        onEdit?.call();
                        return;
                      }
                      AppHaptics.light();
                      onCopy!(
                        messages[i],
                        messages.length == 1 ? '已複製這句' : '已複製第 ${i + 1} 句',
                      );
                    },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: _blankAwareText(messages[i], textStyle),
              ),
            ),
          ],
          if (card.hasInventedDetail && !edited) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  TablerIcons.alert_circle,
                  size: 16,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    guideV3InventedNotice,
                    key: ValueKey('guide-v3-card-${card.slot}-invented'),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.warning,
                    ),
                  ),
                ),
                if (onEdit != null)
                  TextButton(
                    key: ValueKey('guide-v3-card-${card.slot}-edit'),
                    onPressed: onEdit,
                    child: const Text('改成我的'),
                  ),
              ],
            ),
          ],
          if (onCopy != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 38,
              child: _needsFill
                  ? FilledButton.icon(
                      key: ValueKey('guide-v3-card-${card.slot}-fill'),
                      onPressed: onEdit,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.warning,
                        foregroundColor: AppColors.brandInk,
                      ),
                      icon: const Icon(TablerIcons.pencil, size: 16),
                      label: const Text('填好空格再複製'),
                    )
                  : OutlinedButton.icon(
                      key: ValueKey('guide-v3-card-${card.slot}-copy'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.ctaStart,
                        side: BorderSide(
                          color: AppColors.ctaStart.withValues(alpha: 0.55),
                        ),
                      ),
                      onPressed: () {
                        AppHaptics.light();
                        onCopy!(
                          messages.join('\n'),
                          messages.length == 1 ? '已複製這句' : '已複製這組訊息',
                        );
                      },
                      icon: const Icon(TablerIcons.copy, size: 16),
                      label: Text(messages.length == 1 ? '複製這句' : '複製整組'),
                    ),
            ),
          ],
          if (footer != null) footer!,
        ],
      ),
    );
  }
}

/// 免費方案看不到的卡：只給任務標籤與升級入口（伺服器本來就沒寫這張）。
class GuideV3LockedCard extends StatelessWidget {
  const GuideV3LockedCard({super.key, required this.planned, this.onUpgrade});

  final GuideV3PlannedCard planned;
  final VoidCallback? onUpgrade;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('guide-v3-locked-${planned.slot}'),
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(
        border: AppColors.ctaStart.withValues(alpha: 0.30),
      ),
      child: Row(
        children: [
          GuideV3TaskChip(task: planned.task),
          const SizedBox(width: 10),
          const Icon(
            TablerIcons.lock,
            size: 16,
            color: AppColors.onBackgroundSecondary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '升級後才看得到這張',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.onBackgroundSecondary,
              ),
            ),
          ),
          if (onUpgrade != null)
            TextButton(
              key: ValueKey('guide-v3-locked-${planned.slot}-upgrade'),
              onPressed: onUpgrade,
              child: const Text('看方案'),
            ),
        ],
      ),
    );
  }
}

/// 還在寫的卡（串流中，排好但還沒送到）。
class GuideV3PendingCard extends StatelessWidget {
  const GuideV3PendingCard({super.key, required this.planned});

  final GuideV3PlannedCard planned;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('guide-v3-pending-${planned.slot}'),
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          GuideV3TaskChip(task: planned.task),
          const SizedBox(width: 10),
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            '正在寫這張…',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 填空／改成自己的說法。回傳改好的每一則；他關掉就回 null。空格（「＿」）
/// 還在或有一則清空時不能按複製。
Future<List<String>?> showGuideV3EditSheet(
  BuildContext context, {
  required List<String> messages,
}) {
  return showAppSheet<List<String>>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => GuideV3EditSheet(messages: messages),
  );
}

class GuideV3EditSheet extends StatefulWidget {
  const GuideV3EditSheet({super.key, required this.messages});

  final List<String> messages;

  @override
  State<GuideV3EditSheet> createState() => _GuideV3EditSheetState();
}

class _GuideV3EditSheetState extends State<GuideV3EditSheet> {
  late final List<TextEditingController> _controllers = [
    for (final message in widget.messages) TextEditingController(text: message),
  ];
  late final bool _hadBlank = widget.messages.any(guideV3TextHasBlank);

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _ready => _controllers.every(
        (c) => c.text.trim().isNotEmpty && !guideV3TextHasBlank(c.text),
      );

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final blanksLeft = _controllers.any((c) => guideV3TextHasBlank(c.text));
    return FractionallySizedBox(
      heightFactor: 0.8,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BrandPageBackground(
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottomInset),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _hadBlank ? '把＿＿換成你的' : '改成你的說法',
                    style: AppTypography.titleLarge.copyWith(
                      color: AppColors.onBackgroundPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _hadBlank ? '空格填好才能複製，其他字也可以順手改。' : '改成你真的會說、真的發生過的。',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.onBackgroundSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        for (var i = 0; i < _controllers.length; i++) ...[
                          if (i > 0) const SizedBox(height: 10),
                          TextField(
                            key: ValueKey('guide-v3-edit-field-$i'),
                            controller: _controllers[i],
                            minLines: 1,
                            maxLines: 5,
                            onChanged: (_) => setState(() {}),
                            style: AppTypography.bodyLarge.copyWith(
                              color: AppColors.onBackgroundPrimary,
                            ),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor:
                                  AppColors.brandInk.withValues(alpha: 0.45),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (blanksLeft) ...[
                    Text(
                      '還有＿＿沒填',
                      key: const ValueKey('guide-v3-edit-blanks-left'),
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.warning,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    height: 46,
                    child: FilledButton.icon(
                      key: const ValueKey('guide-v3-edit-copy'),
                      onPressed: _ready
                          ? () => Navigator.of(context).pop(
                                [for (final c in _controllers) c.text.trim()],
                              )
                          : null,
                      icon: const Icon(TablerIcons.copy, size: 18),
                      label: const Text('複製'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
