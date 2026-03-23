import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../conversation/domain/entities/session_context.dart';
import '../../domain/entities/analysis_models.dart';
import '../../domain/services/screenshot_recognition_helper.dart';

class ScreenshotRecognitionDialogResult {
  final String name;
  final MeetingContext? meetingContext;
  final AcquaintanceDuration? duration;
  final String importMode;
  final List<RecognizedMessage> messages;

  const ScreenshotRecognitionDialogResult({
    required this.name,
    required this.meetingContext,
    required this.duration,
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
  final String initialImportMode;
  final bool forceShowSessionContextFields;

  const ScreenshotRecognitionDialog({
    super.key,
    required this.recognized,
    required this.warningMessage,
    required this.initialName,
    required this.initialMeetingContext,
    required this.initialDuration,
    required this.initialImportMode,
    required this.forceShowSessionContextFields,
  });

  @override
  State<ScreenshotRecognitionDialog> createState() =>
      _ScreenshotRecognitionDialogState();
}

class _ScreenshotRecognitionDialogState
    extends State<ScreenshotRecognitionDialog> {
  late final TextEditingController _nameController;
  late MeetingContext? _selectedMeeting;
  late AcquaintanceDuration? _selectedDuration;
  late String _selectedImportMode;
  late final List<_EditableRecognizedMessage> _editableMessages;
  String? _editValidationMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _selectedMeeting = widget.initialMeetingContext;
    _selectedDuration = widget.initialDuration;
    _selectedImportMode = widget.initialImportMode;
    _editableMessages =
        (widget.recognized.messages ?? const <RecognizedMessage>[])
            .map(_EditableRecognizedMessage.fromRecognizedMessage)
            .toList();
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final message in _editableMessages) {
      message.dispose();
    }
    super.dispose();
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

  void _submit() {
    final sanitizedMessages = _sanitizedMessages();
    if (sanitizedMessages.isEmpty) {
      setState(() {
        _editValidationMessage = '至少要保留一則可匯入的訊息。';
      });
      return;
    }

    Navigator.of(context).pop(
      ScreenshotRecognitionDialogResult(
        name: _nameController.text.trim(),
        meetingContext: _selectedMeeting,
        duration: _selectedDuration,
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

  String _sideLabel(String side) {
    switch (side) {
      case 'left':
        return '原判斷：左側';
      case 'right':
        return '原判斷：右側';
      default:
        return '原判斷：方向待確認';
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
      selectedColor: AppColors.primary.withValues(alpha: 0.3),
      labelStyle: TextStyle(
        color: selected ? AppColors.primary : AppColors.glassTextPrimary,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildEditableMessageCard(
    _EditableRecognizedMessage message,
    int index,
  ) {
    final batchIndexes = _contiguousSideIndexes(index);
    final showBatchCard = _shouldShowBatchCard(index);
    final sideGroupLabel = message.side == 'left' ? '左側' : '右側';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
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
                    : () => _removeMessage(index),
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
                    '這組連續 $sideGroupLabel 泡泡共有 ${batchIndexes.length} 則，可一起校正。',
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
                        child: const Text('這組改成她說'),
                      ),
                      OutlinedButton(
                        onPressed: () => _applySpeakerToGroup(index, true),
                        child: const Text('這組改成我說'),
                      ),
                    ],
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
    final shouldShowSessionContextFields =
        widget.forceShowSessionContextFields ||
            _selectedImportMode ==
                ScreenshotRecognitionHelper.importModeNewConversation;

    return AlertDialog(
      backgroundColor: AppColors.glassWhite,
      title: const Text(
        '識別成功',
        style: TextStyle(color: AppColors.glassTextPrimary),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '識別到 ${widget.recognized.messageCount} 則訊息，可在下方修正後再匯入。',
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
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildStatusChip(
                  icon: Icons.chat_bubble_outline,
                  label: ScreenshotRecognitionHelper.classificationLabel(
                    widget.recognized.classification,
                  ),
                  color: widget.recognized.importPolicy == 'reject'
                      ? AppColors.error
                      : AppColors.primary,
                ),
                _buildStatusChip(
                  icon: Icons.auto_awesome,
                  label: ScreenshotRecognitionHelper.confidenceLabel(
                    widget.recognized.confidence,
                  ),
                  color: _confidenceColor(widget.recognized),
                ),
                _buildStatusChip(
                  icon: Icons.compare_arrows_rounded,
                  label: ScreenshotRecognitionHelper.sideConfidenceLabel(
                    widget.recognized.sideConfidence,
                  ),
                  color: _sideConfidenceColor(widget.recognized),
                ),
              ],
            ),
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
                ScreenshotRecognitionHelper.actionGuidance(widget.recognized),
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.glassTextPrimary,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '匯入方式',
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
                  selectedColor: AppColors.primary.withValues(alpha: 0.3),
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
                  selectedColor: AppColors.primary.withValues(alpha: 0.3),
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
              _selectedImportMode ==
                      ScreenshotRecognitionHelper.importModeAppendCurrent
                  ? '會把這批訊息接到目前對話尾端，適合剛截到最新續聊。'
                  : '會建立新的對話，不會污染目前這段聊天紀錄。',
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
                  Text(
                    '編修識別內容 (${currentMessages.length} 則會被匯入)',
                    style: TextStyle(
                      color: AppColors.glassTextPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '可直接修正錯字、切換左右方，或刪掉誤辨識訊息。這一步不會重新呼叫 OCR。',
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
                          label: const Text('依左 / 右重新套用'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '先依原本的左 / 右泡泡方向快速套用，再逐則微調會更快。',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.unselectedText,
                        height: 1.45,
                      ),
                    ),
                  ],
                  if (widget.recognized.uncertainSideCount > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      '這次有 ${widget.recognized.uncertainSideCount} 則訊息的左右方向不夠確定，建議優先檢查這些列。',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.warning,
                        fontWeight: FontWeight.w600,
                        height: 1.45,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  ..._editableMessages.asMap().entries.map(
                        (entry) => _buildEditableMessageCard(
                          entry.value,
                          entry.key,
                        ),
                      ),
                  if (_editValidationMessage != null)
                    Text(
                      _editValidationMessage!,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
                children: MeetingContext.values.map((meetingContext) {
                  final isSelected = _selectedMeeting == meetingContext;
                  return ChoiceChip(
                    label: Text(meetingContext.label),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedMeeting = selected ? meetingContext : null;
                      });
                    },
                    selectedColor: AppColors.primary.withValues(alpha: 0.3),
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
                    selectedColor: AppColors.primary.withValues(alpha: 0.3),
                    labelStyle: TextStyle(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.glassTextPrimary,
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            '稍後再匯入',
            style: TextStyle(color: AppColors.unselectedText),
          ),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
          ),
          child: const Text('確認匯入'),
        ),
      ],
    );
  }
}

class _EditableRecognizedMessage {
  final String side;
  bool isFromMe;
  final TextEditingController controller;
  final TextEditingController? quotedReplyController;

  _EditableRecognizedMessage({
    required this.side,
    required this.isFromMe,
    required this.controller,
    required this.quotedReplyController,
  });

  factory _EditableRecognizedMessage.fromRecognizedMessage(
    RecognizedMessage message,
  ) {
    return _EditableRecognizedMessage(
      side: message.side,
      isFromMe: message.isFromMe,
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
