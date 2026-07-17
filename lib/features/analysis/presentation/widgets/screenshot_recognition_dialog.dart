import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../../../conversation/domain/entities/session_context.dart';
import '../../domain/entities/analysis_models.dart';
import '../../domain/services/analysis_fragment_policy.dart';
import '../../domain/services/screenshot_recognition_helper.dart';

class ScreenshotRecognitionDialogResult {
  final String name;
  final MeetingContext? meetingContext;
  final AcquaintanceDuration? duration;
  final UserGoal? goal;
  final String? analysisContextNote;
  final List<RecognizedMessage> messages;

  const ScreenshotRecognitionDialogResult({
    required this.name,
    required this.meetingContext,
    required this.duration,
    required this.goal,
    required this.analysisContextNote,
    required this.messages,
  });
}

class ScreenshotRecognitionDialog extends StatefulWidget {
  final RecognizedConversation recognized;
  final String? warningMessage;
  final String initialName;
  final MeetingContext? initialMeetingContext;
  final AcquaintanceDuration? initialDuration;
  final UserGoal? initialGoal;
  final String initialAnalysisContextNote;
  final bool forceShowSessionContextFields;
  final Conversation currentConversation;
  final String? expectedPartnerName;

  const ScreenshotRecognitionDialog({
    super.key,
    required this.recognized,
    required this.warningMessage,
    required this.initialName,
    required this.initialMeetingContext,
    required this.initialDuration,
    required this.initialGoal,
    required this.initialAnalysisContextNote,
    required this.forceShowSessionContextFields,
    required this.currentConversation,
    this.expectedPartnerName,
  });

  @override
  State<ScreenshotRecognitionDialog> createState() =>
      _ScreenshotRecognitionDialogState();
}

class _ScreenshotRecognitionDialogState
    extends State<ScreenshotRecognitionDialog>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _nameController;
  late final TextEditingController _analysisContextNoteController;
  late MeetingContext? _selectedMeeting;
  late AcquaintanceDuration? _selectedDuration;
  late UserGoal? _selectedGoal;
  late final List<_EditableRecognizedMessage> _editableMessages;
  String? _editValidationMessage;
  bool _confirmedSamePartner = false;

  static const _swipeTutorialEntryDelay = Duration(milliseconds: 350);

  // 滑動教學：每次 dialog 進場後延遲播放一次（零 repeat），
  // 播完停在原位。問號按鈕可手動重播。
  late final AnimationController _swipeTutorialController;
  late final Animation<double> _swipeTutorialShift;
  late final Animation<double> _swipeTutorialRightHintOpacity;
  late final Animation<double> _swipeTutorialLeftHintOpacity;
  Timer? _swipeTutorialAutoPlayTimer;
  bool _swipeTutorialAutoPlayScheduled = false;
  bool _swipeTutorialAutoPlaySuppressed = false;
  bool _showStaticSwipeTutorialLegend = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _analysisContextNoteController =
        TextEditingController(text: widget.initialAnalysisContextNote);
    _selectedMeeting = widget.initialMeetingContext;
    _selectedDuration = widget.initialDuration;
    _selectedGoal = widget.initialGoal;
    _editableMessages =
        (widget.recognized.messages ?? const <RecognizedMessage>[])
            .map(_EditableRecognizedMessage.fromRecognizedMessage)
            .toList();

    _swipeTutorialController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    // 右去右回、短暫停頓、左去左回各一趟，首尾都是 0。兩側各留一小段
    // 定點時間，讓方向文案與位移可以被看清楚。
    _swipeTutorialShift = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 28.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 18,
      ),
      TweenSequenceItem(
        tween: ConstantTween(28.0),
        weight: 7,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 28.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 18,
      ),
      TweenSequenceItem(
        tween: ConstantTween(0.0),
        weight: 7,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: -28.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 18,
      ),
      TweenSequenceItem(
        tween: ConstantTween(-28.0),
        weight: 7,
      ),
      TweenSequenceItem(
        tween: Tween(begin: -28.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 18,
      ),
      TweenSequenceItem(
        tween: ConstantTween(0.0),
        weight: 7,
      ),
    ]).animate(_swipeTutorialController);
    _swipeTutorialRightHintOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 6),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 38),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 6),
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 50),
    ]).animate(_swipeTutorialController);
    _swipeTutorialLeftHintOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 6),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 38),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 6),
    ]).animate(_swipeTutorialController);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_reduceMotion) {
      _swipeTutorialAutoPlayTimer?.cancel();
      _swipeTutorialAutoPlayTimer = null;
      if (_swipeTutorialController.isAnimating ||
          _swipeTutorialController.value != 0) {
        _swipeTutorialController
          ..stop()
          ..value = 0;
      }
    }

    if (_swipeTutorialAutoPlayScheduled) return;
    _swipeTutorialAutoPlayScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scheduleSwipeTutorialAutoPlay();
    });
  }

  @override
  void dispose() {
    _swipeTutorialAutoPlayTimer?.cancel();
    _swipeTutorialController.dispose();
    _nameController.dispose();
    _analysisContextNoteController.dispose();
    for (final message in _editableMessages) {
      message.dispose();
    }
    super.dispose();
  }

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  void _scheduleSwipeTutorialAutoPlay() {
    if (_editableMessages.isEmpty || _reduceMotion) return;
    if (!mounted || _reduceMotion || _swipeTutorialAutoPlaySuppressed) {
      return;
    }

    _swipeTutorialAutoPlayTimer?.cancel();
    _swipeTutorialAutoPlayTimer = Timer(_swipeTutorialEntryDelay, () {
      _swipeTutorialAutoPlayTimer = null;
      if (!mounted ||
          _editableMessages.isEmpty ||
          _reduceMotion ||
          _swipeTutorialAutoPlaySuppressed) {
        return;
      }
      _playSwipeTutorial();
    });
  }

  void _playSwipeTutorial() {
    // A manual replay or the actual auto-play both consume any outstanding
    // scheduling path, including an in-flight SharedPreferences read.
    _swipeTutorialAutoPlaySuppressed = true;
    _swipeTutorialAutoPlayTimer?.cancel();
    _swipeTutorialAutoPlayTimer = null;
    if (_editableMessages.isEmpty) return;

    if (_reduceMotion) {
      _swipeTutorialController
        ..stop()
        ..value = 0;
      if (!_showStaticSwipeTutorialLegend) {
        setState(() {
          _showStaticSwipeTutorialLegend = true;
        });
      }
      return;
    }

    if (_showStaticSwipeTutorialLegend) {
      setState(() {
        _showStaticSwipeTutorialLegend = false;
      });
    }
    _swipeTutorialController.forward(from: 0);
  }

  void _cancelSwipeTutorialForInteraction() {
    _swipeTutorialAutoPlaySuppressed = true;
    _swipeTutorialAutoPlayTimer?.cancel();
    _swipeTutorialAutoPlayTimer = null;
    if (_swipeTutorialController.isAnimating ||
        _swipeTutorialController.value != 0) {
      _swipeTutorialController
        ..stop()
        ..value = 0;
    }
    if (_showStaticSwipeTutorialLegend) {
      setState(() {
        _showStaticSwipeTutorialLegend = false;
      });
    }
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  List<RecognizedMessage> _sanitizedMessages() {
    return _editableMessages
        .map(
          (message) => message.toRecognizedMessage(),
        )
        .where((message) => message.content.trim().isNotEmpty)
        .toList();
  }

  void _removeMessage(int index) {
    final removed = _editableMessages.removeAt(index);
    removed.dispose();
    setState(() {
      _editValidationMessage = null;
    });
  }

  /// 二次確認後刪除該則。回傳是否真的刪除（給編輯 sheet 用來決定要不要收起）。
  Future<bool> _confirmRemoveMessage(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.brandSurface2,
        title: Text(
          '刪除這則訊息？',
          style: TextStyle(color: AppColors.onBackgroundPrimary),
        ),
        content: Text(
          '確定要刪除第 ${index + 1} 則訊息嗎？',
          style: TextStyle(color: AppColors.onBackgroundSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('取消',
                style: TextStyle(color: AppColors.onBackgroundSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _removeMessage(index);
      return true;
    }
    return false;
  }

  void _submit() {
    if (_requiresSamePartnerConfirmation && !_confirmedSamePartner) {
      setState(() {
        _editValidationMessage = '請先確認這些截圖都是目前這位對象；如果是另一人，請取消後到正確對象再匯入。';
      });
      return;
    }

    final sanitizedMessages = _sanitizedMessages();
    if (sanitizedMessages.isEmpty) {
      setState(() {
        _editValidationMessage = '至少要保留一則可加入片段的訊息。';
      });
      return;
    }

    Navigator.of(context).pop(
      ScreenshotRecognitionDialogResult(
        name: _nameController.text.trim(),
        meetingContext: _selectedMeeting,
        duration: _selectedDuration,
        goal: _selectedGoal,
        analysisContextNote: _analysisContextNoteController.text.trim().isEmpty
            ? null
            : _analysisContextNoteController.text.trim(),
        messages: sanitizedMessages,
      ),
    );
  }

  bool get _requiresSamePartnerConfirmation =>
      ScreenshotRecognitionHelper.requiresSamePartnerConfirmation(
        recognized: widget.recognized,
        currentConversation: widget.currentConversation,
        expectedPartnerName: widget.expectedPartnerName,
      );

  bool get _canReplaceCurrentDraft =>
      AnalysisFragmentPolicy.canAppendInput(widget.currentConversation);

  bool get _isPartnerBound {
    final partnerId = widget.currentConversation.partnerId?.trim();
    return partnerId != null && partnerId.isNotEmpty;
  }

  // 滑動絕對方向映射：右滑 = 我說、左滑 = 她說。
  void _setMessageSide(int index, bool isFromMe) {
    setState(() {
      _editableMessages[index].isFromMe = isFromMe;
      _editValidationMessage = null;
    });
  }

  bool _hasAnyFromMeMessage() =>
      _editableMessages.any((message) => message.isFromMe);

  void _markAllAsOtherPerson() {
    _cancelSwipeTutorialForInteraction();
    setState(() {
      for (final message in _editableMessages) {
        message.isFromMe = false;
      }
      _editValidationMessage = null;
    });
  }

  /// 單則進階編輯：改錯字 / 刪除 / 唯讀檢視引用。一次只編一則。
  Future<void> _openMessageEditor(int index) async {
    final message = _editableMessages[index];
    final quoted = message.quotedReplyController?.text.trim() ?? '';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.brandSurface2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '編輯這則訊息',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.onBackgroundPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                message.isFromMe ? '目前標記為「我說」' : '目前標記為「她說」',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.onBackgroundSecondary,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: message.controller,
                minLines: 1,
                maxLines: 5,
                autofocus: false,
                onChanged: (_) {
                  if (_editValidationMessage != null) {
                    setState(() {
                      _editValidationMessage = null;
                    });
                  }
                },
                decoration: InputDecoration(
                  hintText: '修正這則訊息內容',
                  hintStyle:
                      const TextStyle(color: AppColors.onBackgroundSecondary),
                  filled: true,
                  fillColor: AppColors.brandInk.withValues(alpha: 0.4),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: const TextStyle(color: AppColors.onBackgroundPrimary),
              ),
              if (quoted.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '引用上一則（唯讀）',
                  style: AppTypography.bodySmall.copyWith(
                    color:
                        AppColors.onBackgroundSecondary.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  quoted,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.onBackgroundSecondary,
                    fontStyle: FontStyle.italic,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      final removed = await _confirmRemoveMessage(index);
                      if (removed && sheetContext.mounted) {
                        Navigator.of(sheetContext).pop();
                      }
                    },
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: AppColors.error,
                    ),
                    label: const Text(
                      '刪除這則訊息',
                      style: TextStyle(color: AppColors.error),
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.ctaStart,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('完成'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    // sheet 內改了文字 / 側別後，回到確認頁同步泡泡顯示。
    if (mounted) {
      setState(() {});
    }
  }

  /// 滑動校正器：左泡她說、右泡我說，左右滑動切換，點泡泡開單則編輯。
  Widget _buildSwipeCorrector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < _editableMessages.length; index++)
          _buildSwipeRow(_editableMessages[index], index),
      ],
    );
  }

  Widget _buildSwipeRow(_EditableRecognizedMessage message, int index) {
    return Dismissible(
      key: ObjectKey(message),
      direction: DismissDirection.horizontal,
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.25,
        DismissDirection.endToStart: 0.25,
      },
      background: _buildSwipeHint(toMe: true),
      secondaryBackground: _buildSwipeHint(toMe: false),
      onUpdate: (details) {
        if (details.progress > 0) {
          _cancelSwipeTutorialForInteraction();
        }
      },
      confirmDismiss: (direction) async {
        // 絕對方向映射，與目前側別無關：右滑一律我說、左滑一律她說。
        _setMessageSide(index, direction == DismissDirection.startToEnd);
        // 永遠回 false → 不真的移除，泡泡彈回後由 AnimatedAlign 滑到正確側。
        return false;
      },
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        alignment:
            message.isFromMe ? Alignment.centerRight : Alignment.centerLeft,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _cancelSwipeTutorialForInteraction();
            unawaited(_openMessageEditor(index));
          },
          child: index == 0
              ? _buildTutorialBubble(message)
              : _buildBubble(message),
        ),
      ),
    );
  }

  /// 第一則泡泡包滑動教學動畫：水平位移跟著 [_swipeTutorialShift]，右／左
  /// 兩個 phase 各自顯示明確文案；播完位移歸零、提示全透明。
  Widget _buildTutorialBubble(_EditableRecognizedMessage message) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedBuilder(
          animation: _swipeTutorialShift,
          builder: (context, child) => Transform.translate(
            key: const ValueKey('ocr-swipe-tutorial-shift'),
            offset: Offset(_swipeTutorialShift.value, 0),
            child: child,
          ),
          child: _buildBubble(message),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: OverflowBox(
                alignment: Alignment.center,
                maxWidth: double.infinity,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    FadeTransition(
                      key: const ValueKey(
                        'ocr-swipe-tutorial-right-hint',
                      ),
                      opacity: _swipeTutorialRightHintOpacity,
                      child: _buildTutorialPhaseBadge(
                        icon: Icons.arrow_forward_rounded,
                        label: '右滑 → 我說',
                        color: AppColors.ctaStart,
                      ),
                    ),
                    FadeTransition(
                      key: const ValueKey(
                        'ocr-swipe-tutorial-left-hint',
                      ),
                      opacity: _swipeTutorialLeftHintOpacity,
                      child: _buildTutorialPhaseBadge(
                        icon: Icons.arrow_back_rounded,
                        label: '左滑 → 她說',
                        color: AppColors.info,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTutorialPhaseBadge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.42)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStaticSwipeTutorialLegend() {
    return Semantics(
      key: const ValueKey('ocr-swipe-tutorial-static-legend'),
      container: true,
      liveRegion: true,
      label: '滑動教學：右滑改成我說，左滑改成她說。',
      child: ExcludeSemantics(
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildTutorialPhaseBadge(
              icon: Icons.arrow_forward_rounded,
              label: '右滑 → 我說',
              color: AppColors.ctaStart,
            ),
            _buildTutorialPhaseBadge(
              icon: Icons.arrow_back_rounded,
              label: '左滑 → 她說',
              color: AppColors.info,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBubble(_EditableRecognizedMessage message) {
    final isMe = message.isFromMe;
    final quoted = message.quotedReplyController?.text.trim() ?? '';
    final fillColor = isMe
        ? AppColors.ctaStart.withValues(alpha: 0.14)
        : AppColors.primaryLight.withValues(alpha: 0.18);
    final borderColor = isMe
        ? AppColors.ctaEnd.withValues(alpha: 0.46)
        : AppColors.primaryLight.withValues(alpha: 0.52);
    final labelColor = isMe ? AppColors.ctaEnd : AppColors.primaryDark;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      constraints: const BoxConstraints(maxWidth: 280),
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(
            isMe ? '我說' : '她說',
            style: AppTypography.bodySmall.copyWith(
              color: labelColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (quoted.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.58),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.glassBorder.withValues(alpha: 0.90),
                ),
              ),
              child: Text(
                '引用：$quoted',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.glassTextSecondary,
                  fontStyle: FontStyle.italic,
                  height: 1.35,
                ),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            message.controller.text,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.glassTextPrimary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwipeHint({required bool toMe}) {
    final color = toMe ? AppColors.ctaStart : AppColors.info;
    return Container(
      alignment: toMe ? Alignment.centerLeft : Alignment.centerRight,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.swap_horiz_rounded, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            toMe ? '改成我說' : '改成她說',
            style: AppTypography.bodySmall.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageEditWorkspace() {
    return Container(
      key: const ValueKey('ocr-message-edit-workspace'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.ctaStart.withValues(alpha: 0.24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: AppColors.glassTextPrimary),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.swap_horiz_rounded,
                  size: 18,
                  color: AppColors.ctaStart,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '判錯邊？滑動訊息切換說話者。',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.glassTextPrimary,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('ocr-swipe-tutorial-replay'),
                  onPressed: _playSwipeTutorial,
                  tooltip: '重播滑動教學',
                  constraints: const BoxConstraints.tightFor(
                    width: 48,
                    height: 48,
                  ),
                  icon: const Icon(
                    Icons.help_outline_rounded,
                    size: 20,
                    color: AppColors.ctaStart,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '右滑＝我說，左滑＝她說；點訊息可改字或刪除。',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.glassTextSecondary,
                height: 1.4,
              ),
            ),
            if (_showStaticSwipeTutorialLegend) ...[
              const SizedBox(height: 10),
              _buildStaticSwipeTutorialLegend(),
            ],
            const SizedBox(height: 12),
            _buildSwipeCorrector(),
            if (_hasAnyFromMeMessage()) ...[
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _markAllAsOtherPerson,
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: const Text('全部都是對方說的'),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '單側截圖常常整段都是對方連發。如果 AI 把某幾則誤判成你說的，'
                '點這裡一次全部改回對方。',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.glassTextSecondary,
                  height: 1.45,
                ),
              ),
            ],
            if (_editValidationMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _editValidationMessage!,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shouldShowSessionContextFields =
        widget.forceShowSessionContextFields || !_canReplaceCurrentDraft;
    final willReplaceCurrentBatch = _canReplaceCurrentDraft &&
        widget.currentConversation.messages.isNotEmpty;

    return AlertDialog(
      backgroundColor: AppColors.brandSurface2,
      title: const Text(
        '先確認內容',
        style: TextStyle(color: AppColors.onBackgroundPrimary),
      ),
      content: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '共抓到 ${widget.recognized.messageCount} 則訊息，確認後會作為這次完整片段。',
              style: const TextStyle(color: AppColors.onBackgroundPrimary),
            ),
            if (widget.warningMessage != null &&
                widget.warningMessage!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 18,
                        color: AppColors.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.warningMessage!,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.onBackgroundPrimary,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            // 滑動校正器：只留一句能幫使用者完成動作的提示，不放系統狀態說明。
            _buildMessageEditWorkspace(),
            if (willReplaceCurrentBatch) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.ctaStart.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.ctaStart.withValues(alpha: 0.24),
                  ),
                ),
                child: Text(
                  '確認後會以這批 ${_editableMessages.length} 則訊息整批取代目前內容，不會接在原訊息下面。',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.onBackgroundPrimary,
                    height: 1.45,
                  ),
                ),
              ),
            ] else if (!_canReplaceCurrentDraft) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.ctaStart.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.ctaStart.withValues(alpha: 0.24),
                  ),
                ),
                child: Text(
                  '原片段已完成分析；這批內容會自動另存成新的分析片段，不會改動舊紀錄。',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.onBackgroundPrimary,
                    height: 1.45,
                  ),
                ),
              ),
            ],
            if (_requiresSamePartnerConfirmation) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.24),
                  ),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _confirmedSamePartner,
                    onChanged: (value) {
                      setState(() {
                        _confirmedSamePartner = value ?? false;
                        _editValidationMessage = null;
                      });
                    },
                    title: Text(
                      widget.expectedPartnerName?.trim().isNotEmpty == true
                          ? '我確認這些是「${widget.expectedPartnerName!.trim()}」的聊天'
                          : '我確認這些截圖都是目前這位對象',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.onBackgroundPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      '如果是另一人，請取消並回到正確對象再匯入。',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.onBackgroundSecondary,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            if (!_isPartnerBound) ...[
              const SizedBox(height: 16),
              const Text(
                '對方名字',
                style: TextStyle(
                  color: AppColors.onBackgroundPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  hintText: '輸入對方名字',
                  hintStyle:
                      const TextStyle(color: AppColors.onBackgroundSecondary),
                  filled: true,
                  fillColor: AppColors.brandInk.withValues(alpha: 0.4),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: const TextStyle(color: AppColors.onBackgroundPrimary),
              ),
            ],
            if (shouldShowSessionContextFields) ...[
              const SizedBox(height: 16),
              const Text(
                '認識場景（選填）',
                style: TextStyle(
                  color: AppColors.onBackgroundPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    MeetingContext.visibleAnalysisOptions.map((meetingContext) {
                  final isSelected = _selectedMeeting == meetingContext;
                  return ChoiceChip(
                    label: Text(meetingContext.label),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedMeeting = selected ? meetingContext : null;
                      });
                    },
                    selectedColor: AppColors.ctaStart.withValues(alpha: 0.2),
                    backgroundColor: AppColors.brandInk.withValues(alpha: 0.4),
                    side: BorderSide(
                      color: isSelected
                          ? AppColors.ctaStart.withValues(alpha: 0.4)
                          : AppColors.onBackgroundPrimary
                              .withValues(alpha: 0.2),
                    ),
                    labelStyle: TextStyle(
                      color: isSelected
                          ? AppColors.ctaStart
                          : AppColors.onBackgroundPrimary,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              const Text(
                '認識多久（選填）',
                style: TextStyle(
                  color: AppColors.onBackgroundPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: AcquaintanceDuration.values.map((duration) {
                  final isSelected = _selectedDuration == duration;
                  return ChoiceChip(
                    label: Text(duration.label),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedDuration = selected ? duration : null;
                      });
                    },
                    selectedColor: AppColors.ctaStart.withValues(alpha: 0.2),
                    backgroundColor: AppColors.brandInk.withValues(alpha: 0.4),
                    side: BorderSide(
                      color: isSelected
                          ? AppColors.ctaStart.withValues(alpha: 0.4)
                          : AppColors.onBackgroundPrimary
                              .withValues(alpha: 0.2),
                    ),
                    labelStyle: TextStyle(
                      color: isSelected
                          ? AppColors.ctaStart
                          : AppColors.onBackgroundPrimary,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              const Text(
                '目前目標',
                style: TextStyle(
                  color: AppColors.onBackgroundPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: UserGoal.values.map((goal) {
                  final isSelected = _selectedGoal == goal;
                  return ChoiceChip(
                    label: Text(goal.label),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedGoal = selected ? goal : null;
                      });
                    },
                    selectedColor: AppColors.ctaStart.withValues(alpha: 0.2),
                    backgroundColor: AppColors.brandInk.withValues(alpha: 0.4),
                    side: BorderSide(
                      color: isSelected
                          ? AppColors.ctaStart.withValues(alpha: 0.4)
                          : AppColors.onBackgroundPrimary
                              .withValues(alpha: 0.2),
                    ),
                    labelStyle: TextStyle(
                      color: isSelected
                          ? AppColors.ctaStart
                          : AppColors.onBackgroundPrimary,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              const Text(
                '補充背景（選填）',
                style: TextStyle(
                  color: AppColors.onBackgroundPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _analysisContextNoteController,
                maxLength: 300,
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.done,
                onEditingComplete: _dismissKeyboard,
                onTapOutside: (_) => _dismissKeyboard(),
                decoration: InputDecoration(
                  hintText: '沒有可以留空',
                  hintStyle:
                      const TextStyle(color: AppColors.onBackgroundSecondary),
                  filled: true,
                  fillColor: AppColors.brandInk.withValues(alpha: 0.4),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: const TextStyle(color: AppColors.onBackgroundPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                '把 AI 看不到的關係、背景或你的真實狀態補在這裡。只影響這個片段的分析，不會改對象資料。',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.onBackgroundSecondary,
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            '取消',
            style: TextStyle(color: AppColors.onBackgroundSecondary),
          ),
        ),
        ElevatedButton(
          onPressed: _requiresSamePartnerConfirmation && !_confirmedSamePartner
              ? null
              : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.ctaStart,
            foregroundColor: Colors.white,
          ),
          child: const Text('確認本次內容'),
        ),
      ],
    );
  }
}

class _EditableRecognizedMessage {
  final String side;
  bool isFromMe;
  bool? quotedReplyPreviewIsFromMe;
  final TextEditingController controller;
  final TextEditingController? quotedReplyController;

  _EditableRecognizedMessage({
    required this.side,
    required this.isFromMe,
    required this.quotedReplyPreviewIsFromMe,
    required this.controller,
    required this.quotedReplyController,
  });

  factory _EditableRecognizedMessage.fromRecognizedMessage(
    RecognizedMessage message,
  ) {
    return _EditableRecognizedMessage(
      side: message.side,
      isFromMe: message.isFromMe,
      quotedReplyPreviewIsFromMe: message.quotedReplyPreviewIsFromMe,
      controller: TextEditingController(text: message.content),
      quotedReplyController:
          (message.quotedReplyPreview?.trim().isNotEmpty ?? false)
              ? TextEditingController(text: message.quotedReplyPreview)
              : null,
    );
  }

  RecognizedMessage toRecognizedMessage() {
    return RecognizedMessage(
      side: side,
      isFromMe: isFromMe,
      content: controller.text.trim(),
      quotedReplyPreviewIsFromMe:
          quotedReplyController == null ? null : quotedReplyPreviewIsFromMe,
      quotedReplyPreview: quotedReplyController?.text.trim().isEmpty ?? true
          ? null
          : quotedReplyController!.text.trim(),
    );
  }

  void dispose() {
    controller.dispose();
    quotedReplyController?.dispose();
  }
}
