import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../../../conversation/domain/entities/session_context.dart';
import '../../../conversation/presentation/widgets/message_bubble.dart';
import '../../domain/entities/analysis_models.dart';
import '../../domain/services/analysis_fragment_policy.dart';
import '../../domain/services/screenshot_recognition_helper.dart';
import '../../../../shared/widgets/analysis_preview_dialog.dart';
import '../../../../shared/widgets/brand/app_sheet.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../../../core/services/app_haptics.dart';

class ScreenshotRecognitionDialogResult {
  final String name;
  final MeetingContext? meetingContext;
  final AcquaintanceDuration? duration;
  final UserGoal? goal;
  final String? analysisContextNote;
  final List<RecognizedMessage> messages;

  /// 按的是「加入並開始分析」（Eric 2026-10-18）：匯入成功後接著走分析鈕同一個入口。
  final bool startAnalysis;

  /// 按下時確認框上寫的那一行（沒寫就是 null）：分析入口重算一樣才不跳確認框。
  final AnalysisQuotaLine? shownQuotaLine;

  const ScreenshotRecognitionDialogResult({
    required this.name,
    required this.meetingContext,
    required this.duration,
    required this.goal,
    required this.analysisContextNote,
    required this.messages,
    this.startAnalysis = false,
    this.shownQuotaLine,
  });
}

class ScreenshotRecognitionDialog extends StatefulWidget {
  static const analyzeButtonKey = ValueKey('recognition-import-analyze');
  static const quotaLineKey = ValueKey('recognition-import-quota-line');

  final RecognizedConversation recognized;
  final String? warningMessage;
  final String initialName;
  final MeetingContext? initialMeetingContext;
  final AcquaintanceDuration? initialDuration;
  final UserGoal? initialGoal;
  final String initialAnalysisContextNote;
  final Conversation currentConversation;
  final String? expectedPartnerName;

  /// 有給：主鈕換成「加入並開始分析」（Eric 2026-10-18：辨識確認後一鍵接著分析），
  /// 旁邊只有「取消」，沒有只匯入不分析的鈕（Eric 2026-10-19 照 Bruce 拿掉「先存起來」）。
  /// 用目前編輯中的訊息算這次會用幾則（跟分析鈕同一套），寫在主鈕上面；回 null 就不寫
  /// 那一行，按下去照舊跳確認框。沒給：只有今天的「確認本次內容」。
  final AnalysisQuotaLine? Function(List<RecognizedMessage> messages)?
      analyzeQuotaLineFor;

  const ScreenshotRecognitionDialog({
    super.key,
    required this.recognized,
    required this.warningMessage,
    required this.initialName,
    required this.initialMeetingContext,
    required this.initialDuration,
    required this.initialGoal,
    required this.initialAnalysisContextNote,
    required this.currentConversation,
    this.expectedPartnerName,
    this.analyzeQuotaLineFor,
  });

  @override
  State<ScreenshotRecognitionDialog> createState() =>
      _ScreenshotRecognitionDialogState();
}

class _ScreenshotRecognitionDialogState
    extends State<ScreenshotRecognitionDialog>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _nameController;
  late final List<_EditableRecognizedMessage> _editableMessages;
  String? _editValidationMessage;

  /// 擋下送出的那行紅字：捲到確認格時，放得下就連它一起帶進視口。
  final _editValidationKey = GlobalKey();
  bool _warningExpanded = false;

  /// 同對象確認格的定位錨與一次性閃光 token（沒勾就按「確認本次內容」時
  /// 自動捲到格子並閃一下——按鈕不再 disabled 裝死，2026-08-09 Eric 真機回報
  /// 「根本不知道要勾」）。block 是整張提醒卡（閃光；捲的時候盡量不捲出卡頂），
  /// checkbox 是卡裡確認格那一列（一定要捲進視口）。
  final _samePartnerBlockKey = GlobalKey();
  final _samePartnerCheckboxKey = GlobalKey();
  int _samePartnerFlashRequest = 0;
  bool _confirmedSamePartner = false;

  /// 已經帶著結果關掉：連點時第二下不再 pop，不然會連底下的分析頁一起關掉。
  bool _submitted = false;

  /// 這次畫面上寫的那一行（build 時算）；按「加入並開始分析」時原樣帶回去比對。
  AnalysisQuotaLine? _shownQuotaLine;

  static const _swipeTutorialEntryDelay = Duration(milliseconds: 650);

  /// 滑動教學第一則移開的距離：要讓露出的那條看得到「⇄ 改成我說」整段字。
  static const _swipeTutorialReveal = 96.0;

  // 滑動教學：每次 dialog 進場後延遲播放 2 輪（2.6 秒/輪），第一則跟真的
  // 滑一樣露出「改成我說／改成她說」那條，播完歸位。問號按鈕可手動重播；
  // 左右對應由對話板上常駐的「← 她說／我說 →」圖例負責。
  late final AnimationController _swipeTutorialController;
  late final Animation<double> _swipeTutorialShift;
  late final Animation<double> _swipeTutorialRightHintOpacity;
  late final Animation<double> _swipeTutorialLeftHintOpacity;
  Timer? _swipeTutorialAutoPlayTimer;
  bool _swipeTutorialAutoPlayScheduled = false;
  bool _swipeTutorialAutoPlaySuppressed = false;

  /// 「全是她說」那一格（Bruce 2026-10-21 示意稿）：打開時有「我說」才
  /// 出現，出現後這次一直留著——它在訊息上面，消失會讓整串訊息往上跳。
  late final bool _showAllHersSlot;

  /// 按「全是她說」前每則的說話者，給「復原」用；之後手動把某則換邊就作廢。
  Map<_EditableRecognizedMessage, bool>? _allHersUndo;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _editableMessages =
        (widget.recognized.messages ?? const <RecognizedMessage>[])
            .map(_EditableRecognizedMessage.fromRecognizedMessage)
            .toList();
    _showAllHersSlot = _editableMessages.any((message) => message.isFromMe);

    // 節奏對標分析頁 SwipeHintNudge：一輪 2.6 秒、播 2 輪就停（2026-08-14
    // Eric 真機回報：常駐循環的方向徽章會擋住第一則訊息內容，跟「讀訊息核對
    // 左右」的主任務打架；2 輪夠搶注意力，播完歸位，問號可重播）。
    _swipeTutorialController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    // 右去右回、短暫停頓、左去左回各一趟，首尾都是 0。兩側各留一小段
    // 定點時間，讓露出的那條與位移可以被看清楚。
    _swipeTutorialShift = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: _swipeTutorialReveal)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 18,
      ),
      TweenSequenceItem(
        tween: ConstantTween(_swipeTutorialReveal),
        weight: 7,
      ),
      TweenSequenceItem(
        tween: Tween(begin: _swipeTutorialReveal, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 18,
      ),
      TweenSequenceItem(
        tween: ConstantTween(0.0),
        weight: 7,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: -_swipeTutorialReveal)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 18,
      ),
      TweenSequenceItem(
        tween: ConstantTween(-_swipeTutorialReveal),
        weight: 7,
      ),
      TweenSequenceItem(
        tween: Tween(begin: -_swipeTutorialReveal, end: 0.0)
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
      return;
    }

    _swipeTutorialController
      ..value = 0
      ..repeat(count: 2);
  }

  /// 使用者動手（滑、點泡泡、按「全是她說」）就停：取消自動播放、位移歸零。
  void _stopSwipeTutorial() {
    _swipeTutorialAutoPlaySuppressed = true;
    _swipeTutorialAutoPlayTimer?.cancel();
    _swipeTutorialAutoPlayTimer = null;
    if (_swipeTutorialController.isAnimating ||
        _swipeTutorialController.value != 0) {
      _swipeTutorialController
        ..stop()
        ..value = 0;
    }
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
    _allHersUndo?.remove(removed);
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
            onPressed:
                AppHaptics.onPress(() => Navigator.of(context).pop(true)),
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

  void _submit({bool startAnalysis = false}) {
    if (_submitted) return;
    if (_requiresSamePartnerConfirmation && !_confirmedSamePartner) {
      setState(() {
        _editValidationMessage = '請先勾選上方的確認格：這些截圖都是目前這位對象；如果是另一人，請取消後到正確對象再匯入。';
        _samePartnerFlashRequest++;
      });
      // 捲到確認格再閃：訊息可能在視口外，光有紅字使用者還是找不到。
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _revealSamePartnerConfirmation());
      return;
    }

    final sanitizedMessages = _sanitizedMessages();
    if (sanitizedMessages.isEmpty) {
      setState(() {
        _editValidationMessage = '至少要保留一則可加入片段的訊息。';
      });
      return;
    }

    _submitted = true;
    Navigator.of(context).pop(
      ScreenshotRecognitionDialogResult(
        name: _nameController.text.trim(),
        meetingContext: widget.initialMeetingContext,
        duration: widget.initialDuration,
        goal: widget.initialGoal,
        analysisContextNote: widget.initialAnalysisContextNote.trim().isEmpty
            ? null
            : widget.initialAnalysisContextNote.trim(),
        messages: sanitizedMessages,
        startAnalysis: startAnalysis,
        shownQuotaLine: startAnalysis ? _shownQuotaLine : null,
      ),
    );
  }

  /// 捲到確認格時上下多留的距離：紅字不貼著底部動作列。
  static const _revealMargin = 8.0;

  /// 沒勾就送出：確認格那一列（圈＋兩行說明）一定捲進視口，下面那行紅字跟它一起
  /// 放得下就連紅字；在這個前提下只捲必要的距離，能不把提醒卡頂端捲出去就不捲。
  /// 不拿整張卡當目標：展開詳情後卡片可能比視口還高，對齊整張卡會把卡底的確認格
  /// 推出畫面（320 寬、1.4 倍字只剩 7% 看得到）。
  void _revealSamePartnerConfirmation() {
    final rowContext = _samePartnerCheckboxKey.currentContext;
    final row = rowContext?.findRenderObject();
    final card = _samePartnerBlockKey.currentContext?.findRenderObject();
    if (rowContext == null || row is! RenderBox || card == null) return;
    final viewport = RenderAbstractViewport.maybeOf(row);
    final position = Scrollable.maybeOf(rowContext)?.position;
    if (viewport == null || position == null) return;

    // 一定要看得到的一段（以確認格那一列為座標）：放得下就連紅字一起。
    var mustSee = Offset.zero & row.size;
    final guidance = _editValidationKey.currentContext?.findRenderObject();
    if (guidance is RenderBox) {
      final withGuidance = mustSee.expandToInclude(
        MatrixUtils.transformRect(
          guidance.getTransformTo(row),
          Offset.zero & guidance.size,
        ),
      );
      if (withGuidance.height + _revealMargin * 2 <=
          position.viewportDimension) {
        mustSee = withGuidance;
      }
    }
    mustSee = mustSee.inflate(_revealMargin);

    // 能停的捲動位置：最小是紅字貼底、最大是確認格貼頂。比卡頂貼頂更往下捲就會把
    // 卡頂的摘要捲出去，所以上限先收到卡頂貼頂那一格（放不下時照樣以確認格為準）。
    final lowest = viewport.getOffsetToReveal(row, 1, rect: mustSee).offset;
    final highest = viewport.getOffsetToReveal(row, 0, rect: mustSee).offset;
    final cardTop = viewport.getOffsetToReveal(card, 0).offset - _revealMargin;
    final to = lowest > highest
        ? highest // 視口連確認格都放不下：至少讓它的頂端進來。
        : position.pixels.clamp(lowest, cardTop.clamp(lowest, highest));
    position.animateTo(
      to.clamp(position.minScrollExtent, position.maxScrollExtent),
      duration: AppMotion.scroll,
      curve: AppMotion.easeOut,
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
      final message = _editableMessages[index];
      // 「全是她說」之後又手動換了邊：跟按之前對不上了，復原作廢。
      if (message.isFromMe != isFromMe) _allHersUndo = null;
      message.isFromMe = isFromMe;
      _editValidationMessage = null;
    });
  }

  bool _hasAnyFromMeMessage() =>
      _editableMessages.any((message) => message.isFromMe);

  /// 單側截圖常常整段都是她連發：一次全改成她說，記下原本的邊給「復原」。
  void _markAllAsHers() {
    _stopSwipeTutorial();
    setState(() {
      _allHersUndo = {
        for (final message in _editableMessages) message: message.isFromMe,
      };
      for (final message in _editableMessages) {
        message.isFromMe = false;
      }
      _editValidationMessage = null;
    });
  }

  void _undoMarkAllAsHers() {
    final undo = _allHersUndo;
    if (undo == null) return;
    setState(() {
      for (final message in _editableMessages) {
        message.isFromMe = undo[message] ?? message.isFromMe;
      }
      _allHersUndo = null;
      _editValidationMessage = null;
    });
  }

  /// 單則進階編輯：改錯字 / 刪除 / 唯讀檢視引用。一次只編一則。
  Future<void> _openMessageEditor(int index) async {
    final message = _editableMessages[index];
    final quoted = message.quotedReplyController?.text.trim() ?? '';

    await showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.brandSurface2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                    borderRadius: BorderRadius.circular(18),
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
                    onPressed: AppHaptics.onPress(() => Navigator.of(sheetContext).pop()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.ctaStart,
                      foregroundColor: AppColors.onCta,
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

  /// 對方頭像上的字：跟分析片段卡同一套（對象名字的第一個字；預設名稱不畫）。
  String? get _partnerInitial {
    final name = ScreenshotRecognitionHelper.resolveKnownContactName(
      currentConversation: widget.currentConversation,
      expectedPartnerName: widget.expectedPartnerName,
    );
    if (name == null ||
        ScreenshotRecognitionHelper.isPlaceholderConversationName(name)) {
      return null;
    }
    return name.characters.first.toUpperCase();
  }

  bool _isGroupStart(int index) =>
      index == 0 ||
      _editableMessages[index].isFromMe !=
          _editableMessages[index - 1].isFromMe;

  /// 滑動校正器：左泡她說、右泡我說，左右滑動切換，點泡泡開單則編輯。
  /// 間距跟分析片段卡一樣：同一人連發貼緊，換人多留 8。
  Widget _buildSwipeCorrector() {
    final partnerInitial = _partnerInitial;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < _editableMessages.length; index++) ...[
          if (index > 0)
            AnimatedContainer(
              duration: AppMotion.state,
              curve: AppMotion.easeOut,
              height: _isGroupStart(index) ? 8 : 0,
            ),
          _buildSwipeRow(
            _editableMessages[index],
            index,
            isGroupStart: _isGroupStart(index),
            partnerInitial: partnerInitial,
          ),
        ],
      ],
    );
  }

  Widget _buildSwipeRow(
    _EditableRecognizedMessage message,
    int index, {
    required bool isGroupStart,
    required String? partnerInitial,
  }) {
    final row = AnimatedAlign(
      duration: AppMotion.state,
      curve: AppMotion.easeOut,
      alignment:
          message.isFromMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: MergeSemantics(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              AppHaptics.tap();
              _stopSwipeTutorial();
              unawaited(_openMessageEditor(index));
            },
            // 泡泡跟分析片段同一份（2026-10-21 改版），不再每顆寫「她說／我說」：
            // 靠左右與底色分辨，整則標籤念給 VoiceOver。
            child: Semantics(
              label: _bubbleSemanticsLabel(message),
              excludeSemantics: true,
              child: MessageBubbleBody(
                isMe: message.isFromMe,
                content: message.controller.text,
                quote: message.quotedReplyController?.text,
                isGroupStart: isGroupStart,
                partnerInitial: partnerInitial,
              ),
            ),
          ),
        ),
      ),
    );

    return Dismissible(
      key: ObjectKey(message),
      direction: DismissDirection.horizontal,
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.25,
        DismissDirection.endToStart: 0.25,
      },
      background: _buildSwipeLane(toMe: true),
      secondaryBackground: _buildSwipeLane(toMe: false),
      onUpdate: (details) {
        if (details.progress > 0) {
          _stopSwipeTutorial();
        }
      },
      confirmDismiss: (direction) async {
        // 絕對方向映射，與目前側別無關：右滑一律我說、左滑一律她說。
        _stopSwipeTutorial();
        final toMe = direction == DismissDirection.startToEnd;
        // 只在真的換側時震；往同側重滑不震。
        if (message.isFromMe != toMe) AppHaptics.light();
        _setMessageSide(index, toMe);
        // 永遠回 false → 不真的移除，泡泡彈回後由 AnimatedAlign 滑到正確側。
        return false;
      },
      child: index == 0 ? _buildTutorialRow(row) : row,
    );
  }

  String _bubbleSemanticsLabel(_EditableRecognizedMessage message) {
    final speaker = message.isFromMe ? '我說' : '她說';
    final quote = message.quotedReplyController?.text.trim() ?? '';
    final content = message.controller.text;
    return quote.isEmpty
        ? '$speaker\n$content'
        : '$speaker\n引用：$quote\n回覆：$content';
  }

  /// 第一則包滑動教學：整排跟真的滑一樣位移，讓出來的那一段露出滑過門檻後的
  /// 結果（右滑「改成我說」、左滑「改成她說」），不再蓋徽章擋住訊息字
  /// （2026-10-21 改版）。播完位移歸零。
  Widget _buildTutorialRow(Widget row) {
    return AnimatedBuilder(
      animation: _swipeTutorialShift,
      builder: (context, child) {
        final shift = _swipeTutorialShift.value;
        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: ClipRect(
                    clipper: _TutorialRevealClipper(shift),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        FadeTransition(
                          key: const ValueKey(
                            'ocr-swipe-tutorial-right-hint',
                          ),
                          opacity: _swipeTutorialRightHintOpacity,
                          child: _buildSwipeLane(toMe: true),
                        ),
                        FadeTransition(
                          key: const ValueKey(
                            'ocr-swipe-tutorial-left-hint',
                          ),
                          opacity: _swipeTutorialLeftHintOpacity,
                          child: _buildSwipeLane(toMe: false),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Transform.translate(
              key: const ValueKey('ocr-swipe-tutorial-shift'),
              offset: Offset(shift, 0),
              child: child,
            ),
          ],
        );
      },
      child: row,
    );
  }

  /// 滑動時露出的那條，預告放開後的樣子：改成我說＝蜜桃（我方泡泡色）、
  /// 改成她說＝白（她的泡泡色）。真的滑和滑動教學共用。
  Widget _buildSwipeLane({required bool toMe}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Container(
        alignment: toMe ? Alignment.centerLeft : Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: toMe ? AppColors.transcriptBubbleMine : Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.swap_horiz_rounded,
              size: 16,
              color: AppColors.glassTextPrimary,
            ),
            const SizedBox(width: 6),
            Text(
              toMe ? '改成我說' : '改成她說',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.glassTextPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 「全是她說」按鈕和按完的那一格的最低高度：一般字級兩種狀態都是這個高，換狀態
  /// 時下面的訊息不會跳；大字小螢幕上「已全部改成她說」排成兩行時，那一格跟著長高，
  /// 不把第二行裁掉（320 寬、1.4 倍字原本裁掉 14）。
  static const _allHersSlotHeight = 44.0;

  /// 那一格裡按鈕的字：15／w600，不帶顏色與字型，讓按鈕的前景色照常套上。
  static final _slotLabelStyle = TextStyle(
    fontSize: AppTypography.titleSmall.fontSize,
    fontWeight: FontWeight.w600,
  );

  /// 「全是她說」放在說明正下方（2026-10-21 改版；原本在所有訊息最後，常常
  /// 手動改完才看到）。按下後同一格改成「已全部改成她說・復原」；手動一則則
  /// 滑到全是她說時一樣顯示，但沒有一次改動可以復原，就不放「復原」。
  Widget _buildAllHersSlot() {
    final undo = _allHersUndo;
    if (undo == null && _hasAnyFromMeMessage()) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _allHersSlotHeight),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: OutlinedButton.icon(
            key: const ValueKey('ocr-mark-all-hers'),
            onPressed: _markAllAsHers,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              backgroundColor: Colors.white,
              side: BorderSide(
                color: AppColors.primary.withValues(alpha: 0.24),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.swap_horiz_rounded, size: 18),
            // 字級跟主鈕同檔；字型與顏色沿用按鈕自己的（跟 BrandSecondaryButton
            // 同一種寫法），不在 ButtonStyle 整顆換掉預設字樣式。
            label: Text('全是她說', style: _slotLabelStyle),
          ),
        ),
      );
    }
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('ocr-mark-all-hers-done'),
        constraints: const BoxConstraints(minHeight: _allHersSlotHeight),
        padding: const EdgeInsets.only(left: 16, right: 4),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.check_rounded,
              size: 18,
              color: AppColors.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              // 排成兩行時上下各留 4，字不貼著底色的邊；一行時比 44 矮，不撐高。
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '已全部改成她說',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.glassTextPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            if (undo != null)
              TextButton.icon(
                key: const ValueKey('ocr-mark-all-hers-undo'),
                onPressed: _undoMarkAllAsHers,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryDark,
                  minimumSize:
                      const Size(_allHersSlotHeight, _allHersSlotHeight),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                icon: const Icon(Icons.undo_rounded, size: 16),
                label: Text('復原', style: _slotLabelStyle),
              ),
          ],
        ),
      ),
    );
  }

  /// 常駐的左右圖例：白「← 她說」、蜜桃「我說 →」，跟泡泡同色，箭頭就是滑的
  /// 方向（取代教學播完才出現的靜態圖例，2026-10-21 改版）。
  Widget _buildDirectionLegend() {
    return Semantics(
      key: const ValueKey('ocr-swipe-direction-legend'),
      container: true,
      label: '左滑改成她說，右滑改成我說。',
      child: ExcludeSemantics(
        child: Row(
          children: [
            _buildLegendPill(toMe: false),
            const Spacer(),
            _buildLegendPill(toMe: true),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendPill({required bool toMe}) {
    final arrow = Icon(
      toMe ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded,
      size: 14,
      color: AppColors.glassTextSecondary,
    );
    final label = Text(
      toMe ? '我說' : '她說',
      style: AppTypography.bodySmall.copyWith(
        color: AppColors.glassTextSecondary,
        fontWeight: FontWeight.w600,
      ),
    );
    return Container(
      padding: EdgeInsets.fromLTRB(toMe ? 12 : 8, 4, toMe ? 8 : 12, 4),
      decoration: BoxDecoration(
        color: toMe ? AppColors.transcriptBubbleMine : Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!toMe) ...[arrow, const SizedBox(width: 4)],
          label,
          if (toMe) ...[const SizedBox(width: 4), arrow],
        ],
      ),
    );
  }

  /// 對話板跟分析片段卡同一套（A 案「LINE 熟悉感」淡紫板＋白／蜜桃泡泡，
  /// 2026-10-21 改版）：匯入前在這裡看到的，就是匯入後分析頁上的樣子。
  Widget _buildMessageEditWorkspace() {
    final hasMessages = _editableMessages.isNotEmpty;
    return Container(
      key: const ValueKey('ocr-message-edit-workspace'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      // 滑動時泡泡滑出板外的部分裁掉，不蓋到外面的深色底。
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.transcriptBoard,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '判錯邊？滑動訊息切換說話者。',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.glassTextPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '點訊息可改字或刪除。',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.glassTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey('ocr-swipe-tutorial-replay'),
                onPressed: _playSwipeTutorial,
                tooltip: '重播滑動教學',
                padding: EdgeInsets.zero,
                alignment: Alignment.centerRight,
                constraints: const BoxConstraints.tightFor(
                  width: 48,
                  height: 48,
                ),
                icon: const Icon(
                  Icons.help_outline_rounded,
                  size: 20,
                  color: AppColors.glassTextSecondary,
                ),
              ),
            ],
          ),
          if (_showAllHersSlot && hasMessages) ...[
            const SizedBox(height: 12),
            _buildAllHersSlot(),
          ],
          if (hasMessages) ...[
            const SizedBox(height: 12),
            Divider(
              height: 1,
              thickness: 1,
              color: AppColors.glassTextPrimary.withValues(alpha: 0.10),
            ),
            const SizedBox(height: 12),
            _buildDirectionLegend(),
            const SizedBox(height: 12),
            _buildSwipeCorrector(),
          ],
        ],
      ),
    );
  }

  String _warningSummary(String warning) {
    final normalized = warning.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.contains('目前對象') && normalized.contains('不同')) {
      return '辨識到的名字和目前對象不同，請先確認是不是同一人。';
    }
    if (normalized.contains('同一位對象') ||
        normalized.contains('混到另一人') ||
        normalized.contains('歸在目前對象')) {
      return '這批截圖可能混到不同對象，請先確認都是同一人。';
    }
    if (widget.recognized.importPolicy == 'reject') {
      switch (widget.recognized.classification) {
        case 'group_chat':
          return '這張是群組聊天，目前只支援一對一聊天截圖。';
        case 'gallery_album':
          return '這張是相簿或選圖畫面，請改傳聊天視窗。';
        case 'call_log_screen':
          return '這張是通話紀錄，請改傳聊天視窗。';
        case 'system_ui':
          return '這張是系統或通知畫面，請改傳聊天視窗。';
        case 'sensitive_content':
          return '這張含不適合辨識的內容，請改傳聊天截圖。';
        case 'social_feed':
          return '這張是社群貼文或留言，請改傳一對一聊天截圖。';
        case 'unsupported':
        default:
          return '這張不是可分析的聊天截圖，請改傳完整聊天視窗。';
      }
    }
    if (normalized.contains('引用')) {
      return '這批訊息含引用內容，請確認對象與「我說／她說」。';
    }
    if (widget.recognized.uncertainSideCount > 0) {
      return '有 ${widget.recognized.uncertainSideCount} 則說話者方向不確定，請確認「我說／她說」。';
    }
    if (widget.recognized.sideConfidence == 'low' ||
        widget.recognized.sideConfidence == 'medium' ||
        normalized.contains('左右') ||
        normalized.contains('補判')) {
      return '說話者方向可能有誤，請確認「我說／她說」。';
    }
    if (widget.recognized.confidence == 'low' ||
        widget.recognized.importPolicy == 'confirm' ||
        normalized.contains('信心') ||
        normalized.contains('不太確定')) {
      return '這次辨識信心較低，請先快速確認內容。';
    }
    return '辨識內容有需要留意的地方，請先確認再繼續。';
  }

  /// 辨識提醒卡（2026-10-21 改版）：中性深色卡＋琥珀圖示，不再整片紅；要確認
  /// 同一人時，確認格收在這張卡裡，不必捲到所有訊息下面才找得到。
  Widget _buildRecognitionCard({
    required String? warning,
    required bool needsSamePartnerConfirmation,
  }) {
    Widget card(double flash) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.055),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Color.lerp(
              Colors.white.withValues(alpha: 0.09),
              AppColors.ctaStart.withValues(alpha: 0.85),
              flash,
            )!,
            width: 1 + 0.4 * flash,
          ),
          // 沒勾就按送出時單發一次的橘框光（DESIGN.md §7「OCR 確認格單發閃光」），
          // 平時是黑底上的中性卡，不發光。
          boxShadow: flash == 0
              ? null
              : [
                  BoxShadow(
                    color: AppColors.ctaStart.withValues(alpha: 0.45 * flash),
                    blurRadius: 18 * flash,
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (warning != null) _buildWarningContent(warning),
            if (warning != null && needsSamePartnerConfirmation)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            if (needsSamePartnerConfirmation) _buildSamePartnerConfirmation(),
          ],
        ),
      );
    }

    if (!needsSamePartnerConfirmation) return card(0);
    // 2026-08-09 顯眼化（Eric 真機回報「根本不知道要勾」）：沒勾就按送出時
    // 捲到卡裡的確認格（_revealSamePartnerConfirmation），整張卡單發一次閃光，
    // 提示「卡在這格」。
    return _AttentionFlash(
      key: _samePartnerBlockKey,
      flashRequest: _samePartnerFlashRequest,
      builder: (context, flash) => card(flash),
    );
  }

  Widget _buildWarningContent(String warning) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 18,
              color: AppColors.warning,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _warningSummary(warning),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.onBackgroundPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('recognition-warning-info-button'),
              tooltip: _warningExpanded ? '收起辨識提醒詳情' : '查看辨識提醒詳情',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              alignment: Alignment.centerRight,
              constraints: const BoxConstraints.tightFor(width: 48, height: 48),
              onPressed: () => setState(
                () => _warningExpanded = !_warningExpanded,
              ),
              icon: Icon(
                _warningExpanded
                    ? Icons.info_rounded
                    : Icons.info_outline_rounded,
                color: AppColors.onBackgroundSecondary.withValues(alpha: 0.62),
                size: 20,
              ),
            ),
          ],
        ),
        if (_warningExpanded) ...[
          const SizedBox(height: 8),
          Divider(
            height: 1,
            thickness: 1,
            color: Colors.white.withValues(alpha: 0.08),
          ),
          const SizedBox(height: 8),
          Text(
            warning,
            key: const ValueKey('recognition-warning-details'),
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.78),
              height: 1.45,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSamePartnerConfirmation() {
    final confirmed = _confirmedSamePartner;
    final partnerName = widget.expectedPartnerName?.trim();
    return MergeSemantics(
      // 沒勾就送出時一定捲進視口的是這一列（圈＋說明），不是整張提醒卡。
      key: _samePartnerCheckboxKey,
      child: Semantics(
        checked: confirmed,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              setState(() {
                _confirmedSamePartner = !_confirmedSamePartner;
                _editValidationMessage = null;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 勾了用品牌橘：跟主鈕同一個「可以送出了」，不再多一個綠色。
                  AnimatedContainer(
                    duration: AppMotion.state,
                    curve: AppMotion.easeOut,
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: confirmed ? AppColors.ctaStart : Colors.transparent,
                      border: Border.all(
                        color: confirmed
                            ? AppColors.ctaStart
                            : Colors.white.withValues(alpha: 0.45),
                        width: 2,
                      ),
                    ),
                    child: confirmed
                        ? const Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: AppColors.onCta,
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          partnerName != null && partnerName.isNotEmpty
                              ? '我確認這些是「$partnerName」的聊天'
                              : '我確認這些截圖都是目前這位對象',
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.onBackgroundPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          confirmed
                              ? '如果是另一人，請取消並回到正確對象再匯入。'
                              : '要先勾這格才能開始分析；如果是另一人，請取消並回到正確對象再匯入。',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.onBackgroundSecondary
                                .withValues(alpha: 0.78),
                            height: 1.4,
                          ),
                        ),
                      ],
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

  @override
  Widget build(BuildContext context) {
    final willReplaceCurrentBatch = _canReplaceCurrentDraft &&
        widget.currentConversation.messages.isNotEmpty;
    // 改了文字、左右或刪掉一則都會重畫，那一行照目前要匯入的訊息重算。
    _shownQuotaLine = widget.analyzeQuotaLineFor?.call(_sanitizedMessages());
    final warning = widget.warningMessage?.trim();
    final hasWarning = warning != null && warning.isNotEmpty;
    final needsSamePartnerConfirmation = _requiresSamePartnerConfirmation;
    // 卡片與板子上的橘色只留給主要動作；說明類圖示一律中性色。
    final noteIconColor =
        AppColors.onBackgroundSecondary.withValues(alpha: 0.62);

    // 滿版底部 sheet 呈現（2026-08-14 對標夥伴示意稿）：拖把手＋大標＋
    // 底部固定動作列。仍走 showDialog 管線，僅換內部版型。
    return Dialog(
      insetPadding: EdgeInsets.zero,
      alignment: Alignment.bottomCenter,
      backgroundColor: Colors.transparent,
      child: Container(
        height: MediaQuery.sizeOf(context).height * 0.94,
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: const BoxDecoration(
          color: AppColors.brandSurface2,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.24),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            // 拖把手下面留一段，捲上去的內容不會貼著它被裁掉。
            const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '先確認內容',
                      style: AppTypography.headlineMedium.copyWith(
                        color: AppColors.onBackgroundPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '共抓到 ${widget.recognized.messageCount} 則訊息，確認後會作為這次完整片段。',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.onBackgroundSecondary
                            .withValues(alpha: 0.78),
                        height: 1.4,
                      ),
                    ),
                    if (hasWarning || needsSamePartnerConfirmation) ...[
                      const SizedBox(height: 16),
                      _buildRecognitionCard(
                        warning: hasWarning ? warning : null,
                        needsSamePartnerConfirmation:
                            needsSamePartnerConfirmation,
                      ),
                    ],
                    // 擋下送出的原因寫在提醒卡正下方：沒勾確認格時捲到卡裡的確認格，
                    // 這行放得下就一起帶進視口。
                    if (_editValidationMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _editValidationMessage!,
                        key: _editValidationKey,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.error,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    // 滑動校正器：只留一句能幫使用者完成動作的提示，不放系統狀態說明。
                    _buildMessageEditWorkspace(),
                    if (willReplaceCurrentBatch) ...[
                      const SizedBox(height: 16),
                      BrandInfoNote(
                        text:
                            '確認後會以這批 ${_editableMessages.length} 則訊息整批取代目前內容，不會接在原訊息下面。',
                        icon: Icons.info_outline_rounded,
                        iconColor: noteIconColor,
                      ),
                    ] else if (!_canReplaceCurrentDraft) ...[
                      const SizedBox(height: 16),
                      BrandInfoNote(
                        text: '原片段已完成分析；這批內容會自動另存成新的分析片段，不會改動舊紀錄。',
                        icon: Icons.info_outline_rounded,
                        iconColor: noteIconColor,
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
                          hintStyle: const TextStyle(
                            color: AppColors.onBackgroundSecondary,
                          ),
                          filled: true,
                          fillColor: AppColors.brandInk.withValues(alpha: 0.4),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        style: const TextStyle(
                          color: AppColors.onBackgroundPrimary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // 底部動作列：深一階的底＋細線，捲動的內容在這裡有明確收邊。
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.brandSurface,
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: widget.analyzeQuotaLineFor == null
                      ? _buildConfirmOnlyActions()
                      : _buildImportAndAnalyzeActions(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 底部動作列：量排不排得下和畫出來用同一組數字。
  static const _actionGap = 12.0;
  static const _cancelMinSize = Size(88, 52);

  /// 主鈕留白跟 App 主題同值（畫面不變）；寫在按鈕上，量字和畫鈕才是同一個數。
  static const _primaryPadding =
      EdgeInsets.symmetric(horizontal: 24, vertical: 16);
  static const _analyzeLabel = '加入並開始分析';
  static final _quotaLineStyle = AppTypography.bodySmall.copyWith(
    color: AppColors.onBackgroundSecondary,
    fontWeight: FontWeight.w600,
  );
  static final _primaryLabelStyle = AppTypography.titleSmall.copyWith(
    color: AppColors.onCta,
    fontWeight: FontWeight.w800,
  );

  /// 不提供一鍵分析時（例如會另開新片段）：今天的「取消／確認本次內容」。
  Widget _buildConfirmOnlyActions() {
    return Row(
      children: [
        _buildCancelAction(),
        const SizedBox(width: _actionGap),
        Expanded(
          child: _buildPrimaryAction(label: '確認本次內容', onPressed: _submit),
        ),
      ],
    );
  }

  /// 一鍵分析（Eric 2026-10-18）：主鈕加入並開始分析，上面寫這次會用幾則。旁邊只留
  /// 「取消」，跟「確認本次內容」同一排（Eric 2026-10-19 照 Bruce 拿掉「先存起來」）。
  /// 一般情況按一下就匯入並開始分析，後面一關都不跳；不想現在分析就按「取消」，辨識
  /// 結果留在分析頁，可從「繼續確認本次內容」再開。只有後面真的跳出最後一則提示或
  /// 確認框而在那裡取消，或額度不夠，匯入的內容才留著、不送；額度不夠但她的訊息有
  /// 自傷字眼例外（Eric 2026-10-18），照常送出，伺服器只回關心訊息與專線、不扣。
  ///
  /// 「取消」旁邊放不下那一行或主鈕的字（各一行）就改上下排，三樣各占整排（主審 r1
  /// P3：320 寬、1.4 倍字會變成「加入並開始分／析」、「則」單獨一行）。照實際的寬度、
  /// 字型和字級縮放量，放得下就維持同一排。
  Widget _buildImportAndAnalyzeActions() {
    final quotaLine = _shownQuotaLine;
    return LayoutBuilder(
      builder: (context, constraints) {
        // 「取消」兩個字在 App 字級上限 1.4 倍也比最小寬 88 窄，旁邊剩的就是這麼寬。
        final besideCancel =
            constraints.maxWidth - _cancelMinSize.width - _actionGap;
        final fitsBesideCancel = (quotaLine == null ||
                _fitsOneLine(
                  context,
                  quotaLine.text,
                  DefaultTextStyle.of(context).style.merge(_quotaLineStyle),
                  besideCancel,
                )) &&
            _fitsOneLine(
              context,
              _analyzeLabel,
              _primaryLabelStyleIn(context),
              besideCancel - _primaryPadding.horizontal,
            );
        final lineAndButton = <Widget>[
          if (quotaLine != null) ...[
            Text(
              quotaLine.text,
              key: ScreenshotRecognitionDialog.quotaLineKey,
              textAlign: TextAlign.center,
              style: _quotaLineStyle,
            ),
            const SizedBox(height: 8),
          ],
          _buildPrimaryAction(
            key: ScreenshotRecognitionDialog.analyzeButtonKey,
            label: _analyzeLabel,
            onPressed: () => _submit(startAnalysis: true),
          ),
        ];
        if (!fitsBesideCancel) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...lineAndButton,
              const SizedBox(height: 8),
              _buildCancelAction(),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildCancelAction(),
            const SizedBox(width: _actionGap),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: lineAndButton,
              ),
            ),
          ],
        );
      },
    );
  }

  /// 主鈕上的字實際用的樣式：ElevatedButton 的字以按鈕主題（沒有就是 labelLarge）
  /// 為底，再疊我們給的。
  TextStyle _primaryLabelStyleIn(BuildContext context) {
    final base = ElevatedButtonTheme.of(context)
            .style
            ?.textStyle
            ?.resolve(const <WidgetState>{}) ??
        Theme.of(context).textTheme.labelLarge ??
        const TextStyle();
    return base.merge(_primaryLabelStyle);
  }

  /// 這段字在 [maxWidth] 內排不排得下一行：跟 Text 一樣套字級縮放、粗體設定和語系。
  bool _fitsOneLine(
    BuildContext context,
    String text,
    TextStyle style,
    double maxWidth,
  ) {
    if (maxWidth <= 0) return false;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: MediaQuery.boldTextOf(context)
            ? style.merge(const TextStyle(fontWeight: FontWeight.bold))
            : style,
      ),
      textDirection: Directionality.of(context),
      locale: Localizations.maybeLocaleOf(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout(maxWidth: maxWidth);
    final fits = !painter.didExceedMaxLines;
    painter.dispose();
    return fits;
  }

  Widget _buildCancelAction() {
    return TextButton(
      onPressed: () {
        // 跟送出共用一次性旗標：同一格裡又按確認又按取消，也只關一次。
        if (_submitted) return;
        _submitted = true;
        Navigator.of(context).pop();
      },
      style: TextButton.styleFrom(
        minimumSize: _cancelMinSize,
      ),
      child: const Text(
        '取消',
        style: TextStyle(color: AppColors.onBackgroundSecondary),
      ),
    );
  }

  /// 底部主鈕（橘底深墨字）。沒勾同對象確認不再 disabled 裝死：一律可按，
  /// _submit 內擋下並捲到確認格＋閃光＋紅字說明。
  ///
  /// 底色跟品牌主鈕（BrandPrimaryButton）同一套橘漸層＋黑色柔陰影；圓角維持
  /// 18，按鈕本身透明，字和留白不變（量排不排得下照舊用同一組數字）。
  Widget _buildPrimaryAction({
    Key? key,
    required String label,
    required VoidCallback onPressed,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.ctaStart, AppColors.ctaEnd],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.20),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        key: key,
        onPressed: AppHaptics.onPress(onPressed),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          foregroundColor: AppColors.onCta,
          minimumSize: const Size.fromHeight(52),
          padding: _primaryPadding,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Text(
          label,
          style: _primaryLabelStyle,
        ),
      ),
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

/// 同對象確認格的一次性提醒閃光。
///
/// [flashRequest] 變動時單發 forward→reverse（約 640ms 即收斂，不 repeat，
/// pumpAndSettle 安全）。遵守 [MediaQuery.disableAnimations] 與 [TickerMode]：
/// 關閉動畫時不閃，只靠靜態高亮（builder 收到的 flash 恆 0）。
/// 動的是 decoration 色彩/陰影（非文字、非透明度），符合殘影禁令。
class _AttentionFlash extends StatefulWidget {
  const _AttentionFlash({
    super.key,
    required this.flashRequest,
    required this.builder,
  });

  final int flashRequest;
  final Widget Function(BuildContext context, double flash) builder;

  @override
  State<_AttentionFlash> createState() => _AttentionFlashState();
}

class _AttentionFlashState extends State<_AttentionFlash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.state,
  );

  @override
  void didUpdateWidget(covariant _AttentionFlash oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.flashRequest == oldWidget.flashRequest) return;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion || !TickerMode.valuesOf(context).enabled) return;
    _controller.forward(from: 0).then((_) {
      if (mounted) _controller.reverse();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => widget.builder(context, _controller.value),
    );
  }
}

/// 滑動教學只露出位移讓出來的那一段：跟 Dismissible 露出背景同一個道理，
/// 右移露出左邊那條、左移露出右邊那條。
class _TutorialRevealClipper extends CustomClipper<Rect> {
  const _TutorialRevealClipper(this.shift);

  final double shift;

  @override
  Rect getClip(Size size) => shift >= 0
      ? Rect.fromLTWH(0, 0, shift, size.height)
      : Rect.fromLTWH(size.width + shift, 0, -shift, size.height);

  @override
  bool shouldReclip(_TutorialRevealClipper oldClipper) =>
      oldClipper.shift != shift;
}
