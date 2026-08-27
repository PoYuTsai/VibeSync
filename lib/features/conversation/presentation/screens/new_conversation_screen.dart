// lib/features/conversation/presentation/screens/new_conversation_screen.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_feedback_snack_bar.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../../../shared/widgets/warm_theme_widgets.dart';
import '../../../analysis/domain/services/screenshot_session_context_defaults.dart';
import '../../../partner/domain/entities/partner.dart';
import '../../../partner/presentation/providers/partner_providers.dart';
import '../../data/providers/conversation_providers.dart';
import '../../data/providers/conversation_write_controller.dart';
import '../../domain/entities/session_context.dart';

/// 手動輸入頁的版面契約。
///
/// 兩個輸入列合成「單一群組卡片」，Sydney 走底部出血；三個 key 分別對應
/// 群組卡、裙襬裁切容器與角色圖本身。
const String manualInputComposerGroupKey = 'manual_input_composer_group';
const String manualInputSydneySkirtBleedKey = 'manual_input_sydney_skirt_bleed';
const String manualInputSydneyArtKey = 'manual_input_sydney_art';

/// 去背角色素材：只保留頭部、上半身與連續 A-line 百褶裙，素材本身已裁在
/// 裙襬之上，因此任何可見範圍都不會露出裙襬底端、大腿或鞋子。
const String _manualInputSydneyAsset =
    'assets/images/coach/sydney_manual_input_full.png';

/// 素材長寬比（468 / 1151）。等比縮放用，禁止拉伸。
const double _manualInputSydneyAspectRatio = 468 / 1151;

/// 角色可見高度下限；內容太長把 Sydney 擠到畫面外時仍保留這個高度。
const double _manualInputSydneyMinVisibleHeight = 300;

/// 出血倍率：實際繪製高度＝可見高度 × 此值，多出來的部分被 [ClipRect]
/// 裁掉，所以素材自己的下緣永遠不會變成畫面中一條浮空的硬邊。
const double _manualInputSydneyBleedFactor = 1.16;

/// 兩個「＋」按鈕的最小點擊邊長（Apple HIG 44pt）。
const double _manualInputAddButtonHitSize = 44;

String newConversationHintText({
  required bool hasMessages,
  required bool hasIncomingMessage,
  required bool endsWithMyMessage,
}) {
  if (!hasMessages) {
    return '依序輸入對話，至少先加入一則訊息。';
  }

  if (!hasIncomingMessage) {
    return '目前還沒有她的回覆。等她回覆後貼到「她說」，再建立對話分析。';
  }

  if (endsWithMyMessage) {
    return '最後一則可以是我說，系統會以前一則她的回覆作為分析基準。';
  }

  return '最後一則是她說，建立後可直接開始分析。';
}

class NewConversationScreen extends ConsumerStatefulWidget {
  final String? partnerId;

  const NewConversationScreen({
    super.key,
    this.partnerId,
  });

  @override
  ConsumerState<NewConversationScreen> createState() =>
      _NewConversationScreenState();
}

class _NewConversationScreenState extends ConsumerState<NewConversationScreen> {
  final _nameController = TextEditingController();
  final _herMessageController = TextEditingController();
  final _myMessageController = TextEditingController();
  final _analysisContextNoteController = TextEditingController();

  final List<Map<String, dynamic>> _messages = [];

  bool _isLoading = false;
  bool _showAnalysisSettings = false;

  MeetingContext _meetingContext = MeetingContext.datingApp;
  AcquaintanceDuration _duration = AcquaintanceDuration.justMet;
  UserGoal _goal = UserGoal.dateInvite;

  bool get _hasIncomingMessage =>
      _messages.any((message) => message['isFromMe'] == false);

  bool get _endsWithMyMessage =>
      _messages.isNotEmpty && (_messages.last['isFromMe'] as bool);

  String get _conversationHint {
    return newConversationHintText(
      hasMessages: _messages.isNotEmpty,
      hasIncomingMessage: _hasIncomingMessage,
      endsWithMyMessage: _endsWithMyMessage,
    );
  }

  @override
  void initState() {
    super.initState();
    _analysisContextNoteController.addListener(_refreshAnalysisSettingsSummary);
  }

  @override
  void dispose() {
    _analysisContextNoteController
        .removeListener(_refreshAnalysisSettingsSummary);
    _nameController.dispose();
    _herMessageController.dispose();
    _myMessageController.dispose();
    _analysisContextNoteController.dispose();
    super.dispose();
  }

  void _refreshAnalysisSettingsSummary() {
    if (mounted) {
      setState(() {});
    }
  }

  void _addHerMessage() {
    final text = _herMessageController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({
        'isFromMe': false,
        'content': text,
      });
      _herMessageController.clear();
    });
  }

  void _addMyMessage() {
    final text = _myMessageController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({
        'isFromMe': true,
        'content': text,
      });
      _myMessageController.clear();
    });
  }

  void _removeMessage(int index) {
    setState(() {
      _messages.removeAt(index);
    });
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  /// 對象卡查詢失敗不擋建立流程——退回產品預設即可。
  Partner? _partnerForDefaults() {
    final partnerId = widget.partnerId;
    if (partnerId == null) return null;
    try {
      return ref.read(partnerRepositoryProvider).getById(partnerId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _createConversation() async {
    // When entered from PartnerDetail (partnerId != null), the Partner
    // already owns the relationship identity — the「對話對象」name field
    // is hidden in the UI. Default to a calm placeholder name so the
    // AnalysisScreen header still has something to show. Aligns with the
    // 截圖開始 path (`new_conversation_sheet.dart` → `name: '新對話'`).
    // (Bruce TF feedback 2026-04-28).
    final typedName = _nameController.text.trim();
    final name =
        widget.partnerId != null && typedName.isEmpty ? '新對話' : typedName;

    if (widget.partnerId == null && name.isEmpty) {
      showBrandFeedbackSnackBar(
        context,
        title: '請先輸入對方名稱。',
        icon: Icons.info_outline_rounded,
      );
      return;
    }

    if (_messages.isEmpty) {
      showBrandFeedbackSnackBar(
        context,
        title: '請先加入至少一則訊息。',
        icon: Icons.info_outline_rounded,
      );
      return;
    }

    if (!_hasIncomingMessage) {
      showBrandFeedbackSnackBar(
        context,
        title: '請先加入她的回覆，再建立對話。',
        icon: Icons.info_outline_rounded,
      );
      return;
    }

    final repository = ref.read(conversationRepositoryProvider);
    final messages = repository.createMessagesFromList(_messages);

    setState(() => _isLoading = true);

    try {
      final controller = ref.read(conversationWriteControllerProvider.notifier);
      final conversation = await controller.create(
        name: name,
        messages: messages,
        partnerId: widget.partnerId,
      );

      // Spec 1: userStyle / userInterests removed from manual input UI.
      // Schema fields kept for backward compatibility with existing Hive
      // records (design §13 forbids silent migration). New rows write null.
      //
      // 2026-08-14 Eric 拍板：對象卡建立的片段，設定 UI 拆除、蓋章改用
      // 對象卡預設（原本蓋 UI 出廠預設，會把卡上填好的設定擋在外面）。
      // 文字分析 payload 直接讀 conversation.sessionContext，所以這裡仍要
      // 蓋章、不能留 null。孤兒對話（無對象卡）保留 UI、照舊蓋 UI 值。
      if (widget.partnerId != null) {
        final partner = _partnerForDefaults();
        final defaults = ScreenshotSessionContextDefaults.resolve(
          conversation: null,
          partner: partner,
        );
        conversation.sessionContext = defaults;
      } else {
        conversation.sessionContext = SessionContext(
          meetingContext: _meetingContext,
          duration: _duration,
          goal: _goal,
          userStyle: null,
          userInterests: null,
          targetDescription: null,
          analysisContextNote:
              _analysisContextNoteController.text.trim().isEmpty
                  ? null
                  : _analysisContextNoteController.text.trim(),
        );
      }
      await controller.save(conversation);

      if (!mounted) return;

      // pushReplacement (NOT go): swap THIS screen with /conversation/{id}
      // while keeping the underlying PartnerDetail (or wherever the user
      // came from) in the stack. go() would reset the entire stack and
      // strand back-navigation on home. (Bruce TF feedback 2026-04-28).
      context.pushReplacement('/conversation/${conversation.id}');
    } catch (_) {
      if (!mounted) return;
      showBrandFeedbackSnackBar(
        context,
        title: '建立對話失敗，請再試一次',
        icon: Icons.error_outline_rounded,
        accentColor: AppColors.error,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Layout-density fold (Bruce/Eric 2026-06-10, proof:
  /// test/visual_proof/density_proof_test.dart): the tray gives a section
  /// visual MASS so the page stops feeling 空. 2026-06-17 暗紫橘統一: switched
  /// from the light warm-glass fill to a dark brand surface so the inner dark
  /// BrandKit fields/segments sit on the same surface system as 關於我.
  Widget _frostTray(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.brandSurface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  /// Dark-brand input field (replaces the light GlassmorphicTextField).
  Widget _brandField({
    required TextEditingController controller,
    required String hintText,
    bool isDense = false,
    int? maxLength,
    int maxLines = 1,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
    TapRegionCallback? onTapOutside,
  }) {
    return TextField(
      controller: controller,
      maxLength: maxLength,
      maxLines: maxLines,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      onTapOutside: onTapOutside,
      cursorColor: AppColors.ctaStart,
      style: AppTypography.bodyMedium.copyWith(color: Colors.white),
      decoration: brandInputDecoration(hintText: hintText).copyWith(
        isDense: isDense,
      ),
    );
  }

  /// 橘色圓形「＋」。視覺直徑 38，但整個 44×44 都吃得到點擊
  /// （[HitTestBehavior.opaque]），符合 Apple HIG 最小觸控尺寸。
  /// 觸覺回饋沿用 [AppHaptics.onPress]。
  Widget _buildAddButton({
    required VoidCallback onPressed,
    required String semanticLabel,
  }) {
    final handlePress = AppHaptics.onPress(onPressed);
    return Semantics(
      button: true,
      label: semanticLabel,
      onTap: handlePress,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: handlePress,
          child: const SizedBox(
            width: _manualInputAddButtonHitSize,
            height: _manualInputAddButtonHitSize,
            child: Center(
              child: SizedBox(
                width: 38,
                height: 38,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.ctaStart, AppColors.ctaEnd],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.add,
                    size: 21,
                    color: AppColors.onCta,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _meetingContextLabel(MeetingContext context) {
    switch (context) {
      case MeetingContext.datingApp:
        return '交友軟體';
      case MeetingContext.inPerson:
        return '現實認識';
      case MeetingContext.friendIntro:
        return '朋友介紹';
      case MeetingContext.other:
        return '其他';
      case MeetingContext.committedPartner:
        return '已是伴侶';
    }
  }

  String _durationLabel(AcquaintanceDuration duration) {
    switch (duration) {
      case AcquaintanceDuration.justMet:
        return '剛認識';
      case AcquaintanceDuration.fewDays:
        return '幾天';
      case AcquaintanceDuration.fewWeeks:
        return '幾週';
      case AcquaintanceDuration.monthPlus:
        return '一個月以上';
    }
  }

  String _goalLabel(UserGoal goal) {
    switch (goal) {
      case UserGoal.dateInvite:
        return '邀約見面';
      case UserGoal.maintainHeat:
        return '維持熱度';
      case UserGoal.justChat:
        return '自然聊天';
    }
  }

  String _analysisSettingsSummary() {
    final parts = [
      _meetingContextLabel(_meetingContext),
      _durationLabel(_duration),
      _goalLabel(_goal),
    ];
    if (_analysisContextNoteController.text.trim().isNotEmpty) {
      parts.insert(0, '已補充背景');
    }
    return parts.join('・');
  }

  List<Widget> _buildAnalysisSettingsSection() {
    return [
      InkWell(
        onTap: () {
          AppHaptics.tap();
          setState(() => _showAnalysisSettings = !_showAnalysisSettings);
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              _showAnalysisSettings ? Icons.expand_less : Icons.expand_more,
              color: AppColors.onBackgroundSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '這次分析設定（可不改）',
                    style: AppTypography.bodyLarge.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _analysisSettingsSummary(),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.onBackgroundSecondary
                          .withValues(alpha: 0.78),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 6),
      Text(
        '不確定可以先跳過；AI 會用預設情境分析。',
        style: AppTypography.bodySmall.copyWith(
          color: AppColors.onBackgroundSecondary.withValues(alpha: 0.70),
        ),
      ),
      if (_showAnalysisSettings) ...[
        const SizedBox(height: 16),
        ..._buildSessionContextSettings(),
      ],
    ];
  }

  List<Widget> _buildSessionContextSettings() {
    return [
      _settingLabel('認識情境'),
      const SizedBox(height: 8),
      BrandSegmentedButton<MeetingContext>(
        segments: MeetingContext.visibleAnalysisOptions
            .map(
              (value) => BrandSegment(
                value: value,
                label: _meetingContextLabel(value),
              ),
            )
            .toList(),
        selected: _meetingContext,
        onChanged: (value) => setState(() => _meetingContext = value),
      ),
      const SizedBox(height: 16),
      _settingLabel('認識多久'),
      const SizedBox(height: 8),
      BrandSegmentedButton<AcquaintanceDuration>(
        segments: AcquaintanceDuration.values
            .map(
              (value) => BrandSegment(
                value: value,
                label: _durationLabel(value),
              ),
            )
            .toList(),
        selected: _duration,
        onChanged: (value) => setState(() => _duration = value),
      ),
      const SizedBox(height: 16),
      _settingLabel('目前目標'),
      const SizedBox(height: 8),
      BrandSegmentedButton<UserGoal>(
        segments: UserGoal.values
            .map(
              (value) => BrandSegment(
                value: value,
                label: _goalLabel(value),
              ),
            )
            .toList(),
        selected: _goal,
        onChanged: (value) => setState(() => _goal = value),
      ),
      const SizedBox(height: 16),
      _settingLabel('補充背景（選填）'),
      const SizedBox(height: 8),
      _brandField(
        controller: _analysisContextNoteController,
        hintText: '沒有可以留空',
        isDense: true,
        maxLength: 300,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _dismissKeyboard(),
        onTapOutside: (_) => _dismissKeyboard(),
      ),
      const SizedBox(height: 8),
      Text(
        '把 AI 看不到的關係、背景或你的真實狀態補在這裡。只影響這個對話的分析，不會改對象資料。',
        style: AppTypography.bodySmall.copyWith(
          color: AppColors.onBackgroundSecondary.withValues(alpha: 0.70),
        ),
      ),
    ];
  }

  /// White section label used on the dark trays (replaces bare bodyLarge,
  /// which read as muted on the old light glass).
  Widget _settingLabel(String text) {
    return Text(
      text,
      style: AppTypography.bodyLarge.copyWith(
        color: Colors.white,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  /// 「對話內容」區塊：白色區塊標題 → 單一群組卡 → 卡外的提示列。
  ///
  /// 正式版設計把「她說／我說」兩列收進同一張圓角深紫卡片（[ClipRect] 化的
  /// [Container]，key = [manualInputComposerGroupKey]），中間只用一條低對比
  /// 細分隔線，欄位本身不再各自帶邊框——卡片就是那個容器。已加入的訊息列表
  /// 也放在同一張卡的最上方，維持「一個群組」的閱讀單位。
  List<Widget> _buildConversationContentInput() {
    return [
      _settingLabel('對話內容'),
      const SizedBox(height: 10),
      _conversationComposerGroup(),
      const SizedBox(height: 10),
      _composerHintRow(),
    ];
  }

  Widget _conversationComposerGroup() {
    return Container(
      key: const ValueKey(manualInputComposerGroupKey),
      decoration: BoxDecoration(
        color: AppColors.brandSurface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_messages.isNotEmpty) ...[
            _composerMessageList(),
            _composerDivider(),
          ],
          _composerRow(
            isMe: false,
            controller: _herMessageController,
            hintText: '她說了什麼…',
            onAdd: _addHerMessage,
          ),
          _composerDivider(),
          _composerRow(
            isMe: true,
            controller: _myMessageController,
            hintText: '我說了什麼…',
            onAdd: _addMyMessage,
          ),
        ],
      ),
    );
  }

  /// 低對比細分隔線：只負責分開兩列，不製造第二層卡片邊框。
  Widget _composerDivider() {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 16,
      endIndent: 16,
      color: Colors.white.withValues(alpha: 0.07),
    );
  }

  /// 單一輸入列：頭像 → 無邊框輸入框 → 橘色「＋」。
  Widget _composerRow({
    required bool isMe,
    required TextEditingController controller,
    required String hintText,
    required VoidCallback onAdd,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 17, 14, 17),
      child: Row(
        children: [
          BubbleAvatar(
            label: isMe ? '我' : '她',
            isMe: isMe,
            size: 40,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: TextField(
              controller: controller,
              cursorColor: AppColors.ctaStart,
              style: AppTypography.bodyMedium.copyWith(color: Colors.white),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onAdd(),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: AppTypography.bodyMedium.copyWith(
                  color:
                      AppColors.onBackgroundSecondary.withValues(alpha: 0.45),
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildAddButton(
            onPressed: onAdd,
            semanticLabel: isMe ? '加入我說' : '加入她說',
          ),
        ],
      ),
    );
  }

  /// 已加入的訊息：留在群組卡內，維持一個閱讀單位。刪除鍵不變。
  Widget _composerMessageList() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 220),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: _messages.length,
        itemBuilder: (context, index) {
          final msg = _messages[index];
          final isFromMe = msg['isFromMe'] as bool;
          return ListTile(
            dense: true,
            textColor: Colors.white,
            iconColor: AppColors.onBackgroundSecondary,
            leading: BubbleAvatar(
              label: isFromMe ? '我' : '她',
              isMe: isFromMe,
              size: 28,
            ),
            title: Text(
              msg['content'] as String,
              style: AppTypography.bodyMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
            trailing: IconButton(
              icon: Icon(
                Icons.close,
                size: 18,
                color: AppColors.onBackgroundSecondary.withValues(alpha: 0.70),
              ),
              onPressed: AppHaptics.onPress(() => _removeMessage(index)),
            ),
          );
        },
      ),
    );
  }

  /// 卡片下方的提示列：info outline + 目前狀態文案。
  Widget _composerHintRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: AppColors.onBackgroundSecondary.withValues(alpha: 0.70),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _conversationHint,
              style: AppTypography.caption.copyWith(
                color: AppColors.onBackgroundSecondary.withValues(alpha: 0.70),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 頁面底部的 Sydney 陪伴視覺。
  ///
  /// 出血規則：素材等比繪製成 `可見高度 × [_manualInputSydneyBleedFactor]`，
  /// 靠上對齊後由 [ClipRect] 把多出來的下緣裁掉，因此畫面上看到的永遠是
  /// 「裙子被螢幕底部切掉」，不是素材自己的邊。素材本身已裁在裙襬之上，
  /// 兩層保險加起來保證不會露出裙襬底端、大腿、膝蓋、小腿、腳踝或鞋子。
  ///
  /// [constraints] 來自 [SliverFillRemaining]：高度是捲動視窗剩下的空間，
  /// 所以內容短時 Sydney 會自動長到螢幕底部，內容長時退回
  /// [_manualInputSydneyMinVisibleHeight] 並跟著捲動。全程等比，不拉長身體
  /// 比例。
  Widget _buildSydneyCompanion(BoxConstraints constraints) {
    final incomingHeight = constraints.hasBoundedHeight
        ? constraints.maxHeight
        : constraints.minHeight;
    final availableHeight = math.max(
      incomingHeight,
      _manualInputSydneyMinVisibleHeight,
    );
    // 寬度保險：先算出等比縮放可用的最大高度，再反推可見裁切高度。
    // 高窄螢幕上即使留有垂直空間，也不會為了填滿而左右裁圖；
    // 影像區塊改為貼底對齊，仍保留固定比例的裙襬出血。
    final maxHeightByWidth = constraints.maxWidth.isFinite
        ? constraints.maxWidth / _manualInputSydneyAspectRatio
        : double.infinity;
    final artHeight = math.min(
      availableHeight * _manualInputSydneyBleedFactor,
      maxHeightByWidth,
    );
    final visibleHeight = math.min(
      availableHeight,
      artHeight / _manualInputSydneyBleedFactor,
    );

    return SizedBox(
      height: availableHeight,
      width: double.infinity,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ClipRect(
          key: const ValueKey(manualInputSydneySkirtBleedKey),
          child: SizedBox(
            height: visibleHeight,
            width: double.infinity,
            child: OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: 0,
              maxHeight: artHeight,
              child: Image.asset(
                _manualInputSydneyAsset,
                key: const ValueKey(manualInputSydneyArtKey),
                height: artHeight,
                fit: BoxFit.contain,
                alignment: Alignment.topCenter,
                // 百褶裙的細直紋在縮放時最容易產生摩爾紋／水波感，
                // 交給 mipmap 取樣而不是最近鄰。
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BrandPageBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(
            color: AppColors.onBackgroundPrimary,
          ),
          title: Text(
            '手動輸入',
            style: AppTypography.titleLarge.copyWith(
              color: AppColors.onBackgroundPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverPadding(
              // 底部不留 padding：Sydney 是出血視覺，要一路接到螢幕底部。
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              sliver: SliverToBoxAdapter(
                // Layout-density fold (Bruce/Eric 2026-06-10, proof:
                // test/visual_proof/density_proof_test.dart): content capped
                // at 340 and centred, so 欄位寬度／節奏一致。16px section
                // rhythm, 20px before the CTA.
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 「對話對象」 input — only shown for legacy /
                        // orphan-conversation entries (partnerId == null).
                        // When entered from PartnerDetail (partnerId set) the
                        // Partner already owns the relationship identity, so
                        // re-typing the name here is redundant double-input.
                        // (Bruce TF feedback 2026-04-28.)
                        if (widget.partnerId == null) ...[
                          _settingLabel('對話對象'),
                          const SizedBox(height: 8),
                          _brandField(
                            controller: _nameController,
                            hintText: '例如：小安',
                          ),
                          const SizedBox(height: 16),
                        ],
                        // 對象卡進來的片段不再放「這次分析設定」（2026-08-14
                        // Eric 拍板：卡建立時已填，這裡重複）；孤兒對話沒有卡
                        // 可繼承，保留設定入口。
                        if (widget.partnerId == null) ...[
                          _frostTray(_buildAnalysisSettingsSection()),
                          const SizedBox(height: 16),
                        ],
                        ..._buildConversationContentInput(),
                        // CTA 排在 Sydney 之前：底部出血的角色不能壓在可操作
                        // 元件上面，也不能把按鈕推到看不到的地方。
                        if (_hasIncomingMessage) ...[
                          const SizedBox(height: 20),
                          BrandPrimaryButton(
                            label: '建立對話',
                            onPressed: _isLoading ? null : _createConversation,
                            isLoading: _isLoading,
                          ),
                        ],
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // 夥伴示意稿（2026-08-14 起，2026-08-26 換成去背正式素材）：
            // Sydney 永遠排在提示文字之後，不覆蓋任何文字或輸入卡。
            SliverFillRemaining(
              hasScrollBody: false,
              // SliverFillRemaining 會先問 child 的 intrinsic height，而
              // LayoutBuilder 不支援 intrinsics；外面這層固定高度的 SizedBox
              // 直接回報下限值，攔住那次詢問，再由 sliver 把它撐成
              // max(剩餘視窗高度, 下限)，LayoutBuilder 才拿得到最終高度。
              child: SizedBox(
                height: _manualInputSydneyMinVisibleHeight,
                child: LayoutBuilder(
                  builder: (context, constraints) =>
                      _buildSydneyCompanion(constraints),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
