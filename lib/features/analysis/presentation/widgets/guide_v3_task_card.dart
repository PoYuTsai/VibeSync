/// v3 任務卡（結果頁與分析紀錄共用）：任務標籤直接給用戶看（設計文件第 5 節）。
/// 兩則以上的卡要分開傳（Eric 2026-10-18）：主按鈕一則一則複製（第 1 則 → 第 2 則），
/// 整組複製放次要位置；點泡泡也能只複製那一則。有空格（「＿」）的卡一定要先填好
/// 才能複製，照樣寫＋標示的卡提醒「有編的細節，請改成你的」。複製哪一則由卡片決定
///（填空、再調之後也是卡片接著複製）；剪貼簿與成效紀錄由呼叫端做，所以結果頁與
/// 紀錄頁可以各自決定要不要記錄。「再調一下」也由呼叫端決定給不給（只有結果頁的
/// 最終結果給）。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
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

/// 卡上顯示的是「再調一下」選定的版本。
const guideV3RefinedLabel = '已再調過';

/// 結果頁的任務卡要不要給「再調一下」入口（只管畫面給不給 onRefine；伺服器、v2 回覆的
/// 再調一下與草稿潤飾都不受影響）。
/// Eric 2026-10-18 停損：主審第 3 輪 APPROVED_WITH_RISK，今天先隱藏入口，明天再決定。
const bool kGuideV3CardRefineEnabled = false;

Color guideV3TaskColor(GuideV3Task task) => switch (task) {
      GuideV3Task.accept => AppColors.info,
      GuideV3Task.resonate => AppColors.coachAccentBright,
      GuideV3Task.tension => AppColors.coachRecommendation,
      GuideV3Task.push => AppColors.ctaStart,
      GuideV3Task.close => AppColors.onBackgroundSecondary,
    };

/// 任務標籤點開的一句用途（Eric 2026-10-18：開場救星、新話題都有推薦理由，v3 補上
/// 「這張卡在做什麼」；固定說明、不花模型費）。鎖住的卡也用同一句。
String guideV3TaskPurpose(GuideV3Task task) => switch (task) {
      GuideV3Task.accept => '先接她剛說的話，讓她知道你有在聽。',
      GuideV3Task.resonate => '站在她的感受這邊，讓她覺得你懂她。',
      GuideV3Task.tension => '用輕鬆的玩笑逗她一下，讓聊天多點火花。',
      GuideV3Task.push => '往見面靠近一步，例如提個想一起做的事，或約好時間。',
      GuideV3Task.close => '讓這輪自然收個尾，不用硬聊下去。',
    };

class GuideV3TaskChip extends StatelessWidget {
  const GuideV3TaskChip({
    super.key,
    required this.task,
    this.onTap,
    this.expanded = false,
  });

  final GuideV3Task task;

  /// 點了展開用途句（Eric 2026-10-18）；null＝只是標籤（正在寫、鎖住的卡）。
  final VoidCallback? onTap;

  /// 用途句開著（VoiceOver 念「已展開」）。
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final color = guideV3TaskColor(task);
    final onTap = this.onTap;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            task.label,
            style: AppTypography.labelMedium.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          // 小 i 告訴他這個標籤點得開。
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(TablerIcons.info_circle, size: 14, color: color),
          ],
        ],
      ),
    );
    if (onTap == null) {
      return Semantics(
        label: '任務：${task.label}',
        child: ExcludeSemantics(child: chip),
      );
    }
    // 標籤本身很小，點擊區撐到 44 高（iOS 建議的最小點擊區）。
    return Semantics(
      button: true,
      expanded: expanded,
      label: '任務：${task.label}',
      hint: expanded ? '點兩下收起說明' : '點兩下看這張卡在做什麼',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.centerLeft,
          child: chip,
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
      borderRadius: BorderRadius.circular(22),
      border: Border.all(
        color: border ?? Colors.white.withValues(alpha: 0.12),
      ),
    );

class GuideV3TaskCard extends StatefulWidget {
  const GuideV3TaskCard({
    super.key,
    required this.card,
    this.editedMessages,
    this.refinedMessages,
    this.onCopy,
    this.onEdit,
    this.onRefine,
    this.footer,
  });

  final GuideV3Card card;

  /// 他填過空格或改過的版本；null＝照伺服器原樣。
  final List<String>? editedMessages;

  /// 「再調一下」選定的版本（模型寫的字：編的細節提醒照留，空格一樣要先填）；
  /// 他之後自己改過就以 [editedMessages] 為準。
  final List<String>? refinedMessages;

  /// 複製（文字、提示）；null＝這個畫面不給複製。
  final void Function(String text, String toast)? onCopy;

  /// 打開填空／改寫（呼叫端負責存），回傳他按「複製」時的每一則；關掉回 null。
  /// 有空格的卡要先經過這裡才能複製；拿到結果卡片就複製第 1 則。
  final Future<List<String>?> Function()? onEdit;

  /// 打開「再調一下」（呼叫端負責存），回傳選定的版本；沒選回 null。卡片拿到就照
  /// 複製規則走（還有「＿」就先填）。null＝這個畫面或這張卡不給再調。
  final Future<List<String>?> Function()? onRefine;

  /// 卡片下方（例如複製後的成效回報列）。
  final Widget? footer;

  @override
  State<GuideV3TaskCard> createState() => _GuideV3TaskCardState();
}

class _GuideV3TaskCardState extends State<GuideV3TaskCard> {
  /// 兩則以上的卡：主按鈕下一個要複製第幾則（從 0 起）。
  int _next = 0;

  /// [_next] 算的是哪一份字；卡上的字換了（改過、再調過）就從第 1 則重新開始。
  List<String>? _progressOf;

  /// 任務標籤點開的用途句（Eric 2026-10-18）。
  bool _purposeOpen = false;

  List<String> get _messages =>
      widget.editedMessages ?? widget.refinedMessages ?? widget.card.messages;

  bool get _needsFill => _messages.any(guideV3TextHasBlank);

  @override
  void didUpdateWidget(covariant GuideV3TaskCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final progressOf = _progressOf;
    if (progressOf != null && !listEquals(progressOf, _messages)) {
      _next = 0;
      _progressOf = null;
    }
  }

  /// 複製其中一則；主按鈕接著指到下一則（最後一則之後回到第 1 則）。
  void _copyAt(List<String> messages, int index) {
    final onCopy = widget.onCopy;
    if (onCopy == null || index < 0 || index >= messages.length) return;
    AppHaptics.light();
    final single = messages.length == 1;
    onCopy(messages[index], single ? '已複製這句' : '已複製第 ${index + 1} 則');
    setState(() {
      _progressOf = List.unmodifiable(messages);
      _next = single ? 0 : (index + 1) % messages.length;
    });
  }

  /// 先填空／改寫，好了就從第 1 則開始複製（一張卡的幾則是一起傳的）。
  Future<void> _editThenCopy() async {
    final saved = await widget.onEdit?.call();
    if (saved == null || saved.isEmpty || !mounted) return;
    if (saved.any(guideV3TextHasBlank)) return;
    _copyAt(saved, 0);
  }

  /// 再調選定的版本不直接當成已傳：還有「＿」就先填，填好才複製第 1 則。
  Future<void> _refineThenCopy() async {
    final adopted = await widget.onRefine?.call();
    if (adopted == null || adopted.isEmpty || !mounted) return;
    if (adopted.any(guideV3TextHasBlank)) {
      await _editThenCopy();
      return;
    }
    _copyAt(adopted, 0);
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final onCopy = widget.onCopy;
    final onEdit = widget.onEdit;
    final messages = _messages;
    final edited = widget.editedMessages != null;
    final refined = !edited && widget.refinedMessages != null;
    final needsFill = _needsFill;
    final multi = messages.length > 1;
    final next = _next < messages.length ? _next : 0;
    final copyLabel = multi ? '複製第 ${next + 1} 則' : '複製這句';
    final textStyle = AppTypography.bodyLarge.copyWith(
      color: AppColors.onBackgroundPrimary,
      height: 1.45,
    );
    return Container(
      key: ValueKey('guide-v3-card-${card.slot}'),
      // 標籤的點擊區是 44 高：上緣少留 10、標籤下面不再另外空一行，標籤和泡泡
      // 的位置跟以前一樣。
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GuideV3TaskChip(
                key: ValueKey('guide-v3-task-chip-${card.slot}'),
                task: card.task,
                expanded: _purposeOpen,
                onTap: () => setState(() => _purposeOpen = !_purposeOpen),
              ),
              const Spacer(),
              if (edited || refined)
                Text(
                  edited ? '已改成你的' : guideV3RefinedLabel,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.onBackgroundSecondary,
                  ),
                ),
            ],
          ),
          if (_purposeOpen)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                guideV3TaskPurpose(card.task),
                key: ValueKey('guide-v3-card-${card.slot}-purpose'),
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.onBackgroundSecondary,
                  height: 1.4,
                ),
              ),
            ),
          for (var i = 0; i < messages.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            // VoiceOver：點泡泡會複製（有空格先填），要唸得出來（Eric 2026-10-18）。
            Semantics(
              container: true,
              button: onCopy != null,
              hint: onCopy == null
                  ? null
                  : needsFill
                      ? '點兩下先填空格'
                      : multi
                          ? '點兩下只複製這一則'
                          : '點兩下複製這句',
              child: InkWell(
                key: ValueKey('guide-v3-card-${card.slot}-message-$i'),
                borderRadius: BorderRadius.circular(18),
                onTap: onCopy == null
                    ? null
                    : () {
                        // 整張卡有空格就先填：一張卡的幾則是一起傳的，不能先
                        // 拿走沒空格的那幾則（主審第 1 輪 P2-2）。
                        if (needsFill) {
                          unawaited(_editThenCopy());
                          return;
                        }
                        _copyAt(messages, i);
                      },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: _blankAwareText(messages[i], textStyle),
                ),
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
                    onPressed: () => unawaited(_editThenCopy()),
                    // 主題紫在深色卡上只有約 3.2:1，換淺紫（約 6:1）；點擊區 44。
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primaryLight,
                      minimumSize: const Size(44, 44),
                    ),
                    child: const Text('改成我的'),
                  ),
              ],
            ),
          ],
          if (onCopy != null) ...[
            const SizedBox(height: 10),
            // 44：iOS 建議的最小點擊高度（原本 38）。VoiceOver 唸按鈕時帶上任務，
            // 一頁好幾顆「複製這句」才分得出是哪張卡。
            SizedBox(
              width: double.infinity,
              height: 44,
              child: needsFill
                  ? FilledButton.icon(
                      key: ValueKey('guide-v3-card-${card.slot}-fill'),
                      onPressed: onEdit == null
                          ? null
                          : () => unawaited(_editThenCopy()),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.warning,
                        foregroundColor: AppColors.brandInk,
                      ),
                      icon: const Icon(TablerIcons.pencil, size: 16),
                      label: Text(
                        '填好空格再複製',
                        semanticsLabel: '填好空格再複製（${card.task.label}）',
                      ),
                    )
                  : OutlinedButton.icon(
                      key: ValueKey('guide-v3-card-${card.slot}-copy'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.ctaStart,
                        side: BorderSide(
                          color: AppColors.ctaStart.withValues(alpha: 0.55),
                        ),
                      ),
                      onPressed: () => _copyAt(messages, multi ? next : 0),
                      icon: const Icon(TablerIcons.copy, size: 16),
                      label: Text(
                        copyLabel,
                        semanticsLabel: '$copyLabel（${card.task.label}）',
                      ),
                    ),
            ),
            // 兩則以上：提醒分開傳；整組複製放次要（貼到 LINE 會變成同一則）。
            if (multi)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '分 ${messages.length} 則傳',
                        key: ValueKey('guide-v3-card-${card.slot}-split-hint'),
                        style: AppTypography.caption.copyWith(
                          color: AppColors.onBackgroundSecondary,
                        ),
                      ),
                    ),
                    if (!needsFill)
                      TextButton(
                        key: ValueKey('guide-v3-card-${card.slot}-copy-all'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(44, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          foregroundColor: AppColors.onBackgroundSecondary,
                        ),
                        onPressed: () {
                          AppHaptics.light();
                          onCopy(messages.join('\n'), '已複製這組訊息');
                        },
                        child: Text('複製整組', style: AppTypography.labelMedium),
                      ),
                  ],
                ),
              ),
          ],
          // 整張卡一起調（幾則照舊是幾則）；跟 v2 的「再調一下」同一個樣子。
          if (widget.onRefine != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SizedBox(
                width: double.infinity,
                height: 44,
                child: TextButton.icon(
                  key: ValueKey('guide-v3-card-${card.slot}-refine'),
                  onPressed: () => unawaited(_refineThenCopy()),
                  icon: const Icon(Icons.tune_rounded, size: 16),
                  label: Text('再調一下', style: AppTypography.labelMedium),
                ),
              ),
            ),
          if (widget.footer != null) widget.footer!,
        ],
      ),
    );
  }
}

/// 「這輪付費方案還有 3 張：帶張力 ×2、推進」：任務照第一次出現的順序，同一種
/// 兩張以上寫 ×N。
String guideV3LockedSummary(List<GuideV3PlannedCard> locked) {
  final counts = <GuideV3Task, int>{};
  for (final card in locked) {
    counts[card.task] = (counts[card.task] ?? 0) + 1;
  }
  final parts = [
    for (final entry in counts.entries)
      entry.value > 1 ? '${entry.key.label} ×${entry.value}' : entry.key.label,
  ];
  return '這輪付費方案還有 ${locked.length} 張：${parts.join('、')}';
}

/// 免費方案看不到的卡合成一塊（Eric 2026-10-18：5 張排卡時原本會疊出 3 顆一樣的
/// 「看方案」）：一行說付費方案這輪還有幾張、各是什麼任務，每種任務一句用途，只放
/// 一顆按鈕。伺服器本來就沒寫這幾張，這裡只有排卡的任務標籤；說法不承諾升級後看到
/// 同樣的卡，所以結果頁和分析紀錄共用。什麼時候出現由 [GuideV3ResultSection] 決定。
class GuideV3LockedBlock extends StatelessWidget {
  const GuideV3LockedBlock({super.key, required this.locked, this.onUpgrade});

  /// 鎖住的排卡（照順序）。
  final List<GuideV3PlannedCard> locked;
  final VoidCallback? onUpgrade;

  @override
  Widget build(BuildContext context) {
    final tasks = <GuideV3Task>{for (final card in locked) card.task};
    final onUpgrade = this.onUpgrade;
    return Container(
      key: const ValueKey('guide-v3-locked-block'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
      decoration: _cardDecoration(
        border: AppColors.ctaStart.withValues(alpha: 0.30),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  TablerIcons.lock,
                  size: 16,
                  color: AppColors.onBackgroundSecondary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  guideV3LockedSummary(locked),
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.onBackgroundPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final task in tasks) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GuideV3TaskChip(task: task),
                const SizedBox(width: 8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      guideV3TaskPurpose(task),
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.onBackgroundSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (onUpgrade != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const ValueKey('guide-v3-locked-upgrade'),
                onPressed: onUpgrade,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.ctaStart,
                  minimumSize: const Size(44, 44),
                ),
                iconAlignment: IconAlignment.end,
                icon: const Icon(TablerIcons.chevron_right, size: 16),
                label: const Text('看方案'),
              ),
            )
          else
            const SizedBox(height: 10),
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

/// 填空框帶回來的字有沒有改（Eric 2026-10-18：沒改就不算「已改成你的」，編的細節
/// 提醒照留）。填空框回傳的是去掉頭尾空白的字，比之前一樣先去掉。
bool guideV3EditChanged(List<String> before, List<String> after) =>
    !listEquals([for (final message in before) message.trim()], after);

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

  /// 第一個有空格的那一則；沒有空格就是 null。
  int? _firstBlankField;

  @override
  void initState() {
    super.initState();
    // 先選好第一個空格：打字就直接換掉＿＿，不用自己點到底線再刪（Eric 2026-10-18）。
    final blank = RegExp('$guideV3BlankMark+');
    for (var i = 0; i < _controllers.length; i++) {
      final match = blank.firstMatch(_controllers[i].text);
      if (match == null) continue;
      _controllers[i].selection = TextSelection(
        baseOffset: match.start,
        extentOffset: match.end,
      );
      _firstBlankField = i;
      break;
    }
  }

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
                            autofocus: i == _firstBlankField,
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
                                borderRadius: BorderRadius.circular(18),
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
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.ctaStart,
                        foregroundColor: AppColors.onCta,
                      ),
                      onPressed: _ready
                          ? () => Navigator.of(context).pop(
                                [for (final c in _controllers) c.text.trim()],
                              )
                          : null,
                      icon: const Icon(TablerIcons.copy, size: 18),
                      // 兩則以上照卡片的規則從第 1 則開始傳。
                      label: Text(
                        _controllers.length > 1 ? '複製第 1 則' : '複製',
                      ),
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
