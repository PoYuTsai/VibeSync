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
  late final ScrollController _messageScrollController;
  late MeetingContext? _selectedMeeting;
  late AcquaintanceDuration? _selectedDuration;
  late UserGoal? _selectedGoal;
  late String _selectedImportMode;
  late final List<_EditableRecognizedMessage> _editableMessages;
  late bool _showDetailedEditor;
  String? _editValidationMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _analysisContextNoteController =
        TextEditingController(text: widget.initialAnalysisContextNote);
    _messageScrollController = ScrollController();
    _selectedMeeting = widget.initialMeetingContext;
    _selectedDuration = widget.initialDuration;
    _selectedGoal = widget.initialGoal;
    _selectedImportMode = widget.initialImportMode;
    _editableMessages =
        (widget.recognized.messages ?? const <RecognizedMessage>[])
            .map(_EditableRecognizedMessage.fromRecognizedMessage)
            .toList();
    _showDetailedEditor = _shouldExpandEditorByDefault;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _analysisContextNoteController.dispose();
    _messageScrollController.dispose();
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

  Future<void> _confirmRemoveMessage(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.glassWhite,
        title: Text(
          '刪除這則訊息？',
          style: TextStyle(color: AppColors.glassTextPrimary),
        ),
        content: Text(
          '確定要刪除第 ${index + 1} 則訊息嗎？',
          style: TextStyle(color: AppColors.glassTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child:
                Text('取消', style: TextStyle(color: AppColors.unselectedText)),
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
    }
  }

  void _submit() {
    final sanitizedMessages = _sanitizedMessages();
    if (sanitizedMessages.isEmpty) {
      setState(() {
        _editValidationMessage = '至少要保留一則可加入對話的訊息。';
        // 直接帶用戶進能修的地方，預設唯讀預覽下不留無聲死路。
        _showDetailedEditor = true;
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

  void _applySpeakerSelection(int index, bool isFromMe) {
    setState(() {
      _editableMessages[index].isFromMe = isFromMe;
      _editValidationMessage = null;
    });
  }

  void _applyQuotedReplySpeakerSelection(int index, bool isFromMe) {
    setState(() {
      _editableMessages[index].quotedReplyPreviewIsFromMe = isFromMe;
      _editValidationMessage = null;
    });
  }

  void _applySpeakerToKnownSides() {
    setState(() {
      for (final message in _editableMessages) {
        if (message.side == 'left') {
          message.isFromMe = false;
        } else if (message.side == 'right') {
          message.isFromMe = true;
        }
      }
      _editValidationMessage = null;
    });
  }

  bool _hasKnownSideMessages() {
    return _editableMessages.any(
      (message) => message.side == 'left' || message.side == 'right',
    );
  }

  List<int> _contiguousSideIndexes(int index) {
    if (index < 0 || index >= _editableMessages.length) {
      return const <int>[];
    }

    final side = _editableMessages[index].side;
    if (side != 'left' && side != 'right') {
      return <int>[index];
    }

    var start = index;
    while (start > 0 && _editableMessages[start - 1].side == side) {
      start--;
    }

    var end = index;
    while (end + 1 < _editableMessages.length &&
        _editableMessages[end + 1].side == side) {
      end++;
    }

    return List<int>.generate(end - start + 1, (offset) => start + offset);
  }

  bool _shouldShowBatchCard(int index) {
    final groupIndexes = _contiguousSideIndexes(index);
    return groupIndexes.length > 1 && groupIndexes.first == index;
  }

  // 預設唯讀預覽：內容照樣攤開給用戶檢查，但編輯（TextField＋她說/我說
  // chip）是高密度操作，等用戶點「編輯內容」才開啟（Eric 2026-06-13：
  // 預設全展開用很多次仍覺得複雜）。
  bool get _shouldExpandEditorByDefault => false;

  bool get _hasQuotedReplyPreview =>
      ScreenshotRecognitionHelper.hasQuotedReplyPreview(widget.recognized);

  bool get _isCompactHighConfidenceFlow =>
      widget.recognized.importPolicy == 'allow' &&
      widget.recognized.confidence == 'high' &&
      widget.recognized.sideConfidence == 'high' &&
      !_hasQuotedReplyPreview &&
      (widget.warningMessage?.trim().isEmpty ?? true);

  int get _priorityMessageCount =>
      _editableMessages.where((message) => message.side == 'unknown').length;

  String _editorSummaryCopy() {
    if (_priorityMessageCount > 0) {
      return '這次有 $_priorityMessageCount 則訊息的左右方向還不夠穩，建議先檢查這幾列。AI 識別小字可能會有誤，請順便確認文字內容是否正確。';
    }

    if (_isCompactHighConfidenceFlow) {
      return 'AI 識別小字可能會有誤（如「佳評如潮」變成「住評如潮」），建議快速掃一下內容是否正確。';
    }

    if (_hasQuotedReplyPreview) {
      return '這次含回覆引用框，AI 可能把引用卡裡的人名誤當成發話方向。加入前請特別確認每則是「我說」還是「她說」，有問題可直接修改。';
    }

    return 'AI 識別截圖文字可能會有小誤差，建議快速確認內容是否正確，有問題可以直接修改。';
  }

  void _applySpeakerToGroup(int index, bool isFromMe) {
    final groupIndexes = _contiguousSideIndexes(index);
    setState(() {
      for (final groupIndex in groupIndexes) {
        _editableMessages[groupIndex].isFromMe = isFromMe;
      }
      _editValidationMessage = null;
    });
  }

  Color _confidenceColor(RecognizedConversation recognized) {
    if (recognized.importPolicy == 'reject') {
      return AppColors.error;
    }
    switch (recognized.confidence) {
      case 'low':
        return AppColors.warning;
      case 'medium':
        return AppColors.info;
      case 'high':
      default:
        return AppColors.success;
    }
  }

  Color _sideConfidenceColor(RecognizedConversation recognized) {
    switch (recognized.sideConfidence) {
      case 'low':
        return AppColors.warning;
      case 'medium':
        return AppColors.info;
      case 'high':
      default:
        return AppColors.success;
    }
  }

  double _messageEditorHeight(BuildContext context, int messageCount) {
    final screenHeight = MediaQuery.of(context).size.height;
    final estimatedHeight = switch (messageCount) {
      <= 2 => 220.0,
      <= 4 => 300.0,
      <= 6 => 360.0,
      _ => screenHeight * 0.42,
    };

    return estimatedHeight.clamp(220.0, screenHeight * 0.5).toDouble();
  }

  Color _guidanceColor(ScreenshotRecognitionGuidanceTone tone) {
    switch (tone) {
      case ScreenshotRecognitionGuidanceTone.reject:
        return AppColors.error;
      case ScreenshotRecognitionGuidanceTone.caution:
        return AppColors.warning;
      case ScreenshotRecognitionGuidanceTone.review:
        return AppColors.info;
      case ScreenshotRecognitionGuidanceTone.stable:
        return AppColors.success;
    }
  }

  IconData _guidanceIcon(ScreenshotRecognitionGuidanceTone tone) {
    switch (tone) {
      case ScreenshotRecognitionGuidanceTone.reject:
        return Icons.block_rounded;
      case ScreenshotRecognitionGuidanceTone.caution:
        return Icons.call_split_rounded;
      case ScreenshotRecognitionGuidanceTone.review:
        return Icons.fact_check_rounded;
      case ScreenshotRecognitionGuidanceTone.stable:
        return Icons.check_circle_outline_rounded;
    }
  }

  String _sideLabel(String side) {
    switch (side) {
      case 'left':
        return '原本看起來在左邊';
      case 'right':
        return '原本看起來在右邊';
      default:
        return '左右還不夠清楚';
    }
  }

  Widget _buildStatusChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTypography.bodySmall.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeakerChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.primary.withValues(alpha: 0.2),
      backgroundColor: Colors.white,
      side: BorderSide(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.4)
            : AppColors.glassTextPrimary.withValues(alpha: 0.2),
      ),
      labelStyle: TextStyle(
        color: selected ? AppColors.primary : AppColors.glassTextPrimary,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  /// 唯讀預覽：左右對齊氣泡＋她說/我說標籤，攤開 OCR 結果供快速目檢。
  /// 不放任何輸入元件——編輯一律走「編輯內容」功能鍵。
  /// 讀 controller 現值而非原始 OCR 結果，編輯後收合預覽才會同步。
  Widget _buildReadOnlyPreviewList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final message in _editableMessages)
          _buildReadOnlyPreviewRow(message),
      ],
    );
  }

  Widget _buildReadOnlyPreviewRow(_EditableRecognizedMessage message) {
    final isMe = message.isFromMe;
    final quoted = message.quotedReplyController?.text.trim() ?? '';
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: isMe
              ? AppColors.primary.withValues(alpha: 0.14)
              : const Color(0xFFF0EAF5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: message.side == 'unknown'
                ? AppColors.warning.withValues(alpha: 0.6)
                : AppColors.primary.withValues(alpha: 0.12),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              isMe ? '我說' : '她說',
              style: AppTypography.bodySmall.copyWith(
                color: message.side == 'unknown'
                    ? AppColors.warning
                    : AppColors.unselectedText,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (quoted.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                '引用：$quoted',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.glassTextHint,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 2),
            Text(
              message.controller.text,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.glassTextPrimary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditableMessageCard(
    _EditableRecognizedMessage message,
    int index,
  ) {
    final showBatchCard = _shouldShowBatchCard(index);
    final sideGroupLabel = message.side == 'left' ? '左側' : '右側';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0EAF5), // 淡紫色背景，與外層白色區分
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '第 ${index + 1} 則',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.unselectedText,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _editableMessages.length <= 1
                    ? null
                    : () => _confirmRemoveMessage(index),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                ),
                color: _editableMessages.length <= 1
                    ? AppColors.unselectedText
                    : AppColors.error,
                tooltip: '刪除這則訊息',
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildSpeakerChip(
                label: '她說',
                selected: !message.isFromMe,
                onTap: () => _applySpeakerSelection(index, false),
              ),
              _buildSpeakerChip(
                label: '我說',
                selected: message.isFromMe,
                onTap: () => _applySpeakerSelection(index, true),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _sideLabel(message.side),
            style: AppTypography.bodySmall.copyWith(
              color: message.side == 'unknown'
                  ? AppColors.warning
                  : AppColors.unselectedText,
              fontWeight:
                  message.side == 'unknown' ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
          if (showBatchCard) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.14),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '這幾則都是連在一起的 $sideGroupLabel 泡泡。如果整串都被判反，可以一次改掉。',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.glassTextPrimary,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () => _applySpeakerToGroup(index, false),
                        child: const Text('這幾則都改成她說'),
                      ),
                      OutlinedButton(
                        onPressed: () => _applySpeakerToGroup(index, true),
                        child: const Text('這幾則都改成我說'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '如果每則都判對了，這區可以直接略過。',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.unselectedText,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (message.quotedReplyController != null) ...[
            const SizedBox(height: 10),
            Text(
              '引用的上一則',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.glassTextHint,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildSpeakerChip(
                  label: '引用對方',
                  selected: message.quotedReplyPreviewIsFromMe == false,
                  onTap: () => _applyQuotedReplySpeakerSelection(index, false),
                ),
                _buildSpeakerChip(
                  label: '引用我方',
                  selected: message.quotedReplyPreviewIsFromMe == true,
                  onTap: () => _applyQuotedReplySpeakerSelection(index, true),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: message.quotedReplyController,
              minLines: 1,
              maxLines: 3,
              onChanged: (_) {
                if (_editValidationMessage != null) {
                  setState(() {
                    _editValidationMessage = null;
                  });
                }
              },
              decoration: InputDecoration(
                hintText: '可選：補上她這句正在回哪個舊訊息',
                hintStyle: const TextStyle(color: AppColors.unselectedText),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.35),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.glassTextPrimary,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: message.controller,
            minLines: 1,
            maxLines: 4,
            onChanged: (_) {
              if (_editValidationMessage != null) {
                setState(() {
                  _editValidationMessage = null;
                });
              }
            },
            decoration: InputDecoration(
              hintText: '修正這則訊息內容',
              hintStyle: const TextStyle(color: AppColors.unselectedText),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
            style: const TextStyle(color: AppColors.glassTextPrimary),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentMessages = _sanitizedMessages();
    final guidance = ScreenshotRecognitionHelper.guidance(widget.recognized);
    final guidanceColor = _guidanceColor(guidance.tone);
    final showStatusChips = !_isCompactHighConfidenceFlow &&
        (widget.recognized.classification != 'valid_chat' ||
            widget.recognized.confidence != 'high' ||
            widget.recognized.sideConfidence != 'high');
    final shouldShowSessionContextFields =
        widget.forceShowSessionContextFields ||
            _selectedImportMode ==
                ScreenshotRecognitionHelper.importModeNewConversation;

    return AlertDialog(
      backgroundColor: AppColors.glassWhite,
      title: const Text(
        '先確認內容',
        style: TextStyle(color: AppColors.glassTextPrimary),
      ),
      content: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '共抓到 ${widget.recognized.messageCount} 則訊息。請先確認內容和「我說／她說」，再加入對話。',
              style: const TextStyle(color: AppColors.glassTextPrimary),
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
                            color: AppColors.glassTextPrimary,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_isCompactHighConfidenceFlow) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.info.withValues(alpha: 0.18),
                  ),
                ),
                child: Text(
                  '這批截圖方向看起來很穩，但建議快速確認文字內容是否正確（AI 識別小字可能有誤）。',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.glassTextPrimary,
                    height: 1.45,
                  ),
                ),
              ),
            ],
            if (showStatusChips) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (widget.recognized.classification != 'valid_chat')
                    _buildStatusChip(
                      icon: Icons.chat_bubble_outline,
                      label: ScreenshotRecognitionHelper.classificationLabel(
                        widget.recognized.classification,
                      ),
                      color: widget.recognized.importPolicy == 'reject'
                          ? AppColors.error
                          : AppColors.primary,
                    ),
                  if (widget.recognized.confidence != 'high')
                    _buildStatusChip(
                      icon: Icons.auto_awesome,
                      label: ScreenshotRecognitionHelper.confidenceLabel(
                        widget.recognized.confidence,
                      ),
                      color: _confidenceColor(widget.recognized),
                    ),
                  if (widget.recognized.sideConfidence != 'high')
                    _buildStatusChip(
                      icon: Icons.compare_arrows_rounded,
                      label: ScreenshotRecognitionHelper.sideConfidenceLabel(
                        widget.recognized.sideConfidence,
                      ),
                      color: _sideConfidenceColor(widget.recognized),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: guidanceColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: guidanceColor.withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _guidanceIcon(guidance.tone),
                    size: 18,
                    color: guidanceColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          guidance.title,
                          style: AppTypography.bodySmall.copyWith(
                            color: guidanceColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          guidance.body,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.glassTextPrimary,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '加入方式',
              style: TextStyle(
                color: AppColors.glassTextPrimary,
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
                  selectedColor: AppColors.primary.withValues(alpha: 0.2),
                  backgroundColor: Colors.white,
                  side: BorderSide(
                    color: _selectedImportMode ==
                            ScreenshotRecognitionHelper.importModeAppendCurrent
                        ? AppColors.primary.withValues(alpha: 0.4)
                        : AppColors.glassTextPrimary.withValues(alpha: 0.2),
                  ),
                  labelStyle: TextStyle(
                    color: _selectedImportMode ==
                            ScreenshotRecognitionHelper.importModeAppendCurrent
                        ? AppColors.primary
                        : AppColors.glassTextPrimary,
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
                  selectedColor: AppColors.primary.withValues(alpha: 0.2),
                  backgroundColor: Colors.white,
                  side: BorderSide(
                    color: _selectedImportMode ==
                            ScreenshotRecognitionHelper
                                .importModeNewConversation
                        ? AppColors.primary.withValues(alpha: 0.4)
                        : AppColors.glassTextPrimary.withValues(alpha: 0.2),
                  ),
                  labelStyle: TextStyle(
                    color: _selectedImportMode ==
                            ScreenshotRecognitionHelper
                                .importModeNewConversation
                        ? AppColors.primary
                        : AppColors.glassTextPrimary,
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
                color: AppColors.unselectedText,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '手動修正（選填）',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.glassTextPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _showDetailedEditor = !_showDetailedEditor;
                          });
                        },
                        icon: Icon(
                          _showDetailedEditor
                              ? Icons.check_rounded
                              : Icons.edit_note_rounded,
                        ),
                        label: Text(
                          _showDetailedEditor ? '完成編輯' : '編輯內容',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _editorSummaryCopy(),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.unselectedText,
                      height: 1.45,
                    ),
                  ),
                  if (!_showDetailedEditor) ...[
                    const SizedBox(height: 10),
                    _buildReadOnlyPreviewList(),
                    const SizedBox(height: 8),
                    Text(
                      '內容或「她說／我說」有錯？點右上「編輯內容」即可修改。',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.unselectedText,
                        height: 1.4,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    Text(
                      '逐則確認內容 (${currentMessages.length} 則會被加入)',
                      style: const TextStyle(
                        color: AppColors.glassTextPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '請確認文字內容是否正確（AI 識別小字可能有誤），也可以調整她說／我說。',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.unselectedText,
                        height: 1.45,
                      ),
                    ),
                    if (_hasKnownSideMessages()) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _applySpeakerToKnownSides,
                            icon: const Icon(Icons.compare_arrows_rounded),
                            label: const Text('依左／右重新套用'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '這顆按鈕會依畫面左右重新判斷她說或我說。如果目前都判對了，可以直接略過。',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.unselectedText,
                          height: 1.45,
                        ),
                      ),
                    ],
                    if (widget.recognized.uncertainSideCount > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        '這次有 ${widget.recognized.uncertainSideCount} 則左右還不夠清楚，建議先檢查這些列。',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w600,
                          height: 1.45,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Container(
                      width: double.maxFinite,
                      height: _messageEditorHeight(
                        context,
                        _editableMessages.length,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: Colors.white.withValues(alpha: 0.06),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.25),
                          width: 1.2,
                        ),
                      ),
                      child: ScrollbarTheme(
                        data: ScrollbarThemeData(
                          thumbColor: WidgetStatePropertyAll(
                            AppColors.primary.withValues(alpha: 0.4),
                          ),
                          thickness: const WidgetStatePropertyAll(6),
                          radius: const Radius.circular(3),
                        ),
                        child: Scrollbar(
                          controller: _messageScrollController,
                          thumbVisibility: _editableMessages.length > 2,
                          child: ListView.builder(
                            controller: _messageScrollController,
                            padding: const EdgeInsets.all(8),
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            itemCount: _editableMessages.length,
                            itemBuilder: (context, index) =>
                                _buildEditableMessageCard(
                              _editableMessages[index],
                              index,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  // 驗證訊息放在預覽/編輯分支外：預設收合時驗證失敗也看得到
                  // （Codex review P2，2026-06-13）。
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
            const SizedBox(height: 16),
            const Text(
              '對方名字',
              style: TextStyle(
                color: AppColors.glassTextPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: '輸入對方名字',
                hintStyle: const TextStyle(color: AppColors.unselectedText),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(color: AppColors.glassTextPrimary),
            ),
            if (shouldShowSessionContextFields) ...[
              const SizedBox(height: 16),
              const Text(
                '認識場景（選填）',
                style: TextStyle(
                  color: AppColors.glassTextPrimary,
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
                    selectedColor: AppColors.primary.withValues(alpha: 0.2),
                    backgroundColor: Colors.white,
                    side: BorderSide(
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.4)
                          : AppColors.glassTextPrimary.withValues(alpha: 0.2),
                    ),
                    labelStyle: TextStyle(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.glassTextPrimary,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              const Text(
                '認識多久（選填）',
                style: TextStyle(
                  color: AppColors.glassTextPrimary,
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
                    selectedColor: AppColors.primary.withValues(alpha: 0.2),
                    backgroundColor: Colors.white,
                    side: BorderSide(
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.4)
                          : AppColors.glassTextPrimary.withValues(alpha: 0.2),
                    ),
                    labelStyle: TextStyle(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.glassTextPrimary,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              const Text(
                '目前目標',
                style: TextStyle(
                  color: AppColors.glassTextPrimary,
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
                    selectedColor: AppColors.primary.withValues(alpha: 0.2),
                    backgroundColor: Colors.white,
                    side: BorderSide(
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.4)
                          : AppColors.glassTextPrimary.withValues(alpha: 0.2),
                    ),
                    labelStyle: TextStyle(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.glassTextPrimary,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              const Text(
                '補充背景（選填）',
                style: TextStyle(
                  color: AppColors.glassTextPrimary,
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
                  hintStyle: const TextStyle(color: AppColors.unselectedText),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: const TextStyle(color: AppColors.glassTextPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                '把 AI 看不到的關係、背景或你的真實狀態補在這裡。只影響這個對話的分析，不會改對象資料。',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.glassTextSecondary,
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
            style: TextStyle(color: AppColors.unselectedText),
          ),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
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
