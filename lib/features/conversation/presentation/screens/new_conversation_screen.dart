// lib/features/conversation/presentation/screens/new_conversation_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/warm_theme_widgets.dart';
import '../../../opener/data/services/opener_result_cache_service.dart';
import '../../../subscription/data/providers/subscription_providers.dart';
import '../../data/providers/conversation_providers.dart';
import '../../data/providers/conversation_write_controller.dart';
import '../../domain/entities/session_context.dart';

String newConversationHintText({
  required bool hasMessages,
  required bool hasOpenerSeed,
  required bool hasIncomingMessage,
  required bool endsWithMyMessage,
}) {
  if (!hasMessages) {
    return '依序輸入對話，至少先加入一則訊息。';
  }

  if (hasOpenerSeed && !hasIncomingMessage) {
    return '先把這句傳給對方；收到回覆後，貼到「她說」再建立對話分析。';
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
  final bool seedFromLatestOpener;

  const NewConversationScreen({
    super.key,
    this.partnerId,
    this.seedFromLatestOpener = false,
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
  final _openerResultCacheService = OpenerResultCacheService();

  final List<Map<String, dynamic>> _messages = [];

  bool _isLoading = false;
  bool _showAnalysisSettings = false;
  bool _hasOpenerSeed = false;
  String? _openerSeedText;
  String? _openerSeedLabel;
  String? _openerSeedReason;

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
      hasOpenerSeed: _hasOpenerSeed,
      hasIncomingMessage: _hasIncomingMessage,
      endsWithMyMessage: _endsWithMyMessage,
    );
  }

  @override
  void initState() {
    super.initState();
    _analysisContextNoteController.addListener(_refreshAnalysisSettingsSummary);
    if (widget.seedFromLatestOpener) {
      _seedFromLatestOpener();
    }
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

  void _seedFromLatestOpener() {
    try {
      final result = _openerResultCacheService.loadLatestForScope(
          partnerId: widget.partnerId);
      if (result == null) return;
      final subscription = ref.read(subscriptionProvider);
      final visibleResult = result.visibleForAccess(
        isFreeUser: !subscription.isPremium,
      );
      final openerType = visibleResult.bestOpenerType;
      final openerText = visibleResult.bestOpenerText;
      if (openerText == null) return;

      _messages.add({
        'isFromMe': true,
        'content': openerText,
      });
      _hasOpenerSeed = true;
      _openerSeedText = openerText;
      _openerSeedLabel = _openerLabel(openerType);
      _openerSeedReason = openerType == visibleResult.recommendedPick
          ? visibleResult.recommendedReason?.trim()
          : null;
    } catch (_) {
      _hasOpenerSeed = false;
      _openerSeedText = null;
      _openerSeedLabel = null;
      _openerSeedReason = null;
    }
  }

  String _openerLabel(String? type) {
    switch (type) {
      case 'extend':
        return '延展';
      case 'resonate':
        return '共鳴';
      case 'tease':
        return '調情';
      case 'humor':
        return '幽默';
      case 'coldRead':
        return '冷讀';
      default:
        return 'AI 推薦';
    }
  }

  void _clearOpenerSeed() {
    final seed = _openerSeedText;
    setState(() {
      if (seed != null) {
        _messages.removeWhere(
          (message) =>
              message['isFromMe'] == true && message['content'] == seed,
        );
      }
      _hasOpenerSeed = false;
      _openerSeedText = null;
      _openerSeedLabel = null;
      _openerSeedReason = null;
    });
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
      final removed = _messages.removeAt(index);
      if (removed['isFromMe'] == true &&
          removed['content'] == _openerSeedText) {
        _hasOpenerSeed = false;
        _openerSeedText = null;
        _openerSeedLabel = null;
        _openerSeedReason = null;
      }
    });
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _createConversation() async {
    // When entered from PartnerDetail (partnerId != null), the Partner
    // already owns the relationship identity — the「對話對象」name field
    // is hidden in the UI. Default to a calm placeholder name so the
    // AnalysisScreen header still has something to show. Aligns with the
    // 截圖開始 path (`new_conversation_sheet.dart` → `name: '新對話'`).
    // (Bruce TF feedback 2026-04-28).
    final typedName = _nameController.text.trim();
    final name = widget.partnerId != null
        ? (typedName.isEmpty ? '新對話' : typedName)
        : (typedName.isEmpty && _hasOpenerSeed ? '開場草稿' : typedName);

    if (widget.partnerId == null && name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先輸入對方名稱。')),
      );
      return;
    }

    if (_messages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先加入至少一則訊息。')),
      );
      return;
    }

    if (!_hasIncomingMessage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先加入她的回覆，再建立對話。')),
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
      conversation.sessionContext = SessionContext(
        meetingContext: _meetingContext,
        duration: _duration,
        goal: _goal,
        userStyle: null,
        userInterests: null,
        targetDescription: null,
        analysisContextNote: _analysisContextNoteController.text.trim().isEmpty
            ? null
            : _analysisContextNoteController.text.trim(),
      );
      await controller.save(conversation);

      if (!mounted) return;

      // pushReplacement (NOT go): swap THIS screen with /conversation/{id}
      // while keeping the underlying PartnerDetail (or wherever the user
      // came from) in the stack. go() would reset the entire stack and
      // strand back-navigation on home. (Bruce TF feedback 2026-04-28).
      context.pushReplacement('/conversation/${conversation.id}');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('建立對話失敗，請再試一次')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildAddButton(VoidCallback onPressed) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.glassWhite,
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.glassBorder.withValues(alpha: 0.5),
          ),
        ),
        child: Icon(
          Icons.add,
          size: 20,
          color: AppColors.unselectedText,
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

  List<Widget> _buildAnalysisSettingsSection({bool includeTopSpacing = false}) {
    return [
      if (includeTopSpacing) const SizedBox(height: 24),
      InkWell(
        onTap: () => setState(
          () => _showAnalysisSettings = !_showAnalysisSettings,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              _showAnalysisSettings ? Icons.expand_less : Icons.expand_more,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '這次分析設定（可不改）',
                    style: AppTypography.bodyLarge.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _analysisSettingsSummary(),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
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
          color: AppColors.textSecondary,
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
      Text('認識情境', style: AppTypography.bodyLarge),
      const SizedBox(height: 8),
      GlassmorphicSegmentedButton<MeetingContext>(
        segments: MeetingContext.visibleAnalysisOptions
            .map(
              (value) => GlassSegment(
                value: value,
                label: _meetingContextLabel(value),
              ),
            )
            .toList(),
        selected: _meetingContext,
        onChanged: (value) => setState(() => _meetingContext = value),
      ),
      const SizedBox(height: 16),
      Text('認識多久', style: AppTypography.bodyLarge),
      const SizedBox(height: 8),
      GlassmorphicSegmentedButton<AcquaintanceDuration>(
        segments: AcquaintanceDuration.values
            .map(
              (value) => GlassSegment(
                value: value,
                label: _durationLabel(value),
              ),
            )
            .toList(),
        selected: _duration,
        onChanged: (value) => setState(() => _duration = value),
      ),
      const SizedBox(height: 16),
      Text('目前目標', style: AppTypography.bodyLarge),
      const SizedBox(height: 8),
      GlassmorphicSegmentedButton<UserGoal>(
        segments: UserGoal.values
            .map(
              (value) => GlassSegment(
                value: value,
                label: _goalLabel(value),
              ),
            )
            .toList(),
        selected: _goal,
        onChanged: (value) => setState(() => _goal = value),
      ),
      const SizedBox(height: 16),
      Text('補充背景（選填）', style: AppTypography.bodyLarge),
      const SizedBox(height: 8),
      GlassmorphicTextField(
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
          color: AppColors.textSecondary,
        ),
      ),
    ];
  }

  List<Widget> _buildConversationContentInput() {
    return [
      Text('對話內容', style: AppTypography.bodyLarge),
      const SizedBox(height: 8),
      if (_messages.isNotEmpty) ...[
        GlassmorphicContainer(
          borderRadius: 12,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isFromMe = msg['isFromMe'] as bool;
                return ListTile(
                  dense: true,
                  textColor: AppColors.glassTextPrimary,
                  iconColor: AppColors.glassTextHint,
                  leading: BubbleAvatar(
                    label: isFromMe ? '我' : '她',
                    isMe: isFromMe,
                    size: 28,
                  ),
                  title: Text(
                    msg['content'] as String,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.glassTextPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  trailing: IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 18,
                      color: AppColors.glassTextHint,
                    ),
                    onPressed: () => _removeMessage(index),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
      Row(
        children: [
          const BubbleAvatar(
            label: '她',
            isMe: false,
            size: 32,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GlassmorphicTextField(
              controller: _herMessageController,
              hintText: '她說了什麼...',
              onSubmitted: (_) => _addHerMessage(),
            ),
          ),
          _buildAddButton(_addHerMessage),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          const BubbleAvatar(
            label: '我',
            isMe: true,
            size: 32,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GlassmorphicTextField(
              controller: _myMessageController,
              hintText: '我說了什麼...',
              onSubmitted: (_) => _addMyMessage(),
            ),
          ),
          _buildAddButton(_addMyMessage),
        ],
      ),
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              size: 18,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _conversationHint,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _buildOpenerSeedNotice() {
    final reason = _openerSeedReason;
    return GlassmorphicContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.auto_awesome,
                color: AppColors.ctaStart,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '已帶入剛剛的開場白',
                      style: AppTypography.bodyLarge.copyWith(
                        color: AppColors.glassTextPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '這則已放進「我說」。先傳給對方；等她回覆後回到這裡，把回覆貼進「她說」。',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.glassTextSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (reason != null && reason.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'AI 選擇：${_openerSeedLabel ?? '推薦'}，$reason',
              style: AppTypography.caption.copyWith(
                color: AppColors.glassTextHint,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _clearOpenerSeed,
              icon: const Icon(Icons.close, size: 16),
              label: const Text('不帶入'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.glassTextSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            _hasOpenerSeed ? '接續開場' : '手動輸入',
            style: AppTypography.titleLarge,
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_hasOpenerSeed) ...[
                _buildOpenerSeedNotice(),
                const SizedBox(height: 24),
              ],
              // 「對話對象」 input — only shown for legacy / orphan-conversation
              // entries (partnerId == null). When entered from PartnerDetail
              // (partnerId set) the Partner already owns the relationship
              // identity, so re-typing the name here is redundant double-input.
              // (Bruce TF feedback 2026-04-28.)
              if (widget.partnerId == null) ...[
                Text('對話對象', style: AppTypography.bodyLarge),
                const SizedBox(height: 8),
                GlassmorphicTextField(
                  controller: _nameController,
                  hintText: '例如：小安',
                ),
                const SizedBox(height: 24),
              ],
              if (widget.partnerId == null) ...[
                ..._buildAnalysisSettingsSection(),
                const SizedBox(height: 24),
                ..._buildConversationContentInput(),
              ] else ...[
                ..._buildConversationContentInput(),
                ..._buildAnalysisSettingsSection(includeTopSpacing: true),
              ],
              if (_hasIncomingMessage) ...[
                const SizedBox(height: 32),
                GradientButton(
                  text: '建立對話',
                  onPressed: _isLoading ? null : _createConversation,
                  isLoading: _isLoading,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
