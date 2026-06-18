import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../../../conversation/domain/entities/session_context.dart';
import '../../domain/entities/analysis_models.dart';
import '../../domain/services/screenshot_recognition_helper.dart';

class ScreenshotRecognitionDialogResult {
  final String name;
  final MeetingContext? meetingContext;
  final AcquaintanceDuration? duration;
  final UserGoal? goal;
  final String? analysisContextNote;
  final String importMode;
  final List<RecognizedMessage> messages;

  const ScreenshotRecognitionDialogResult({
    required this.name,
    required this.meetingContext,
    required this.duration,
    required this.goal,
    required this.analysisContextNote,
    required this.importMode,
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
  final String initialImportMode;
  final bool forceShowSessionContextFields;
  final Conversation currentConversation;

  const ScreenshotRecognitionDialog({
    super.key,
    required this.recognized,
    required this.warningMessage,
    required this.initialName,
    required this.initialMeetingContext,
    required this.initialDuration,
    required this.initialGoal,
    required this.initialAnalysisContextNote,
    required this.initialImportMode,
    required this.forceShowSessionContextFields,
    required this.currentConversation,
  });

  @override
  State<ScreenshotRecognitionDialog> createState() =>
      _ScreenshotRecognitionDialogState();
}

class _ScreenshotRecognitionDialogState
    extends State<ScreenshotRecognitionDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _analysisContextNoteController;
  late MeetingContext? _selectedMeeting;
  late AcquaintanceDuration? _selectedDuration;
  late UserGoal? _selectedGoal;
  late String _selectedImportMode;
  late final List<_EditableRecognizedMessage> _editableMessages;
  String? _editValidationMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _analysisContextNoteController =
        TextEditingController(text: widget.initialAnalysisContextNote);
    _selectedMeeting = widget.initialMeetingContext;
    _selectedDuration = widget.initialDuration;
    _selectedGoal = widget.initialGoal;
    _selectedImportMode = widget.initialImportMode;
    _editableMessages =
        (widget.recognized.messages ?? const <RecognizedMessage>[])
            .map(_EditableRecognizedMessage.fromRecognizedMessage)
            .toList();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _analysisContextNoteController.dispose();
    for (final message in _editableMessages) {
      message.dispose();
    }
    super.dispose();
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
    final sanitizedMessages = _sanitizedMessages();
    if (sanitizedMessages.isEmpty) {
      setState(() {
        _editValidationMessage = '至少要保留一則可加入對話的訊息。';
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
        importMode: _selectedImportMode,
        messages: sanitizedMessages,
      ),
    );
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
          onTap: () => _openMessageEditor(index),
          child: _buildBubble(message),
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
                    '判錯邊？左右滑動訊息即可切換。',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.glassTextPrimary,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '左邊是她說、右邊是我說。點訊息可改錯字或刪除。',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.glassTextSecondary,
                height: 1.4,
              ),
            ),
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
        widget.forceShowSessionContextFields ||
            _selectedImportMode ==
                ScreenshotRecognitionHelper.importModeNewConversation;

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
              '共抓到 ${widget.recognized.messageCount} 則訊息，加入對話前先確認一下。',
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
            const SizedBox(height: 16),
            const Text(
              '加入方式',
              style: TextStyle(
                color: AppColors.onBackgroundPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('加入目前對話'),
                  selected: _selectedImportMode ==
                      ScreenshotRecognitionHelper.importModeAppendCurrent,
                  onSelected: (selected) {
                    if (!selected) return;
                    setState(() {
                      _selectedImportMode =
                          ScreenshotRecognitionHelper.importModeAppendCurrent;
                    });
                  },
                  showCheckmark: false,
                  selectedColor: AppColors.ctaStart.withValues(alpha: 0.2),
                  backgroundColor: AppColors.brandInk.withValues(alpha: 0.4),
                  side: BorderSide(
                    color: _selectedImportMode ==
                            ScreenshotRecognitionHelper.importModeAppendCurrent
                        ? AppColors.ctaStart.withValues(alpha: 0.4)
                        : AppColors.onBackgroundPrimary.withValues(alpha: 0.2),
                  ),
                  labelStyle: TextStyle(
                    color: _selectedImportMode ==
                            ScreenshotRecognitionHelper.importModeAppendCurrent
                        ? AppColors.ctaStart
                        : AppColors.onBackgroundPrimary,
                  ),
                ),
                ChoiceChip(
                  label: const Text('另存成新對話'),
                  selected: _selectedImportMode ==
                      ScreenshotRecognitionHelper.importModeNewConversation,
                  onSelected: (selected) {
                    if (!selected) return;
                    setState(() {
                      _selectedImportMode =
                          ScreenshotRecognitionHelper.importModeNewConversation;
                    });
                  },
                  showCheckmark: false,
                  selectedColor: AppColors.ctaStart.withValues(alpha: 0.2),
                  backgroundColor: AppColors.brandInk.withValues(alpha: 0.4),
                  side: BorderSide(
                    color: _selectedImportMode ==
                            ScreenshotRecognitionHelper
                                .importModeNewConversation
                        ? AppColors.ctaStart.withValues(alpha: 0.4)
                        : AppColors.onBackgroundPrimary.withValues(alpha: 0.2),
                  ),
                  labelStyle: TextStyle(
                    color: _selectedImportMode ==
                            ScreenshotRecognitionHelper
                                .importModeNewConversation
                        ? AppColors.ctaStart
                        : AppColors.onBackgroundPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              ScreenshotRecognitionHelper.importModeDescription(
                recognized: widget.recognized,
                currentConversation: widget.currentConversation,
                selectedImportMode: _selectedImportMode,
              ),
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.onBackgroundSecondary,
                height: 1.45,
              ),
            ),
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
                '把 AI 看不到的關係、背景或你的真實狀態補在這裡。只影響這個對話的分析，不會改對象資料。',
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
            '稍後再加入',
            style: TextStyle(color: AppColors.onBackgroundSecondary),
          ),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.ctaStart,
            foregroundColor: Colors.white,
          ),
          child: const Text('確認加入對話'),
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
