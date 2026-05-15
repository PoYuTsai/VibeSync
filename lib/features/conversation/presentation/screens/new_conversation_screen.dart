// lib/features/conversation/presentation/screens/new_conversation_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/warm_theme_widgets.dart';
import '../../../opener/data/services/opener_result_cache_service.dart';
import '../../data/providers/conversation_providers.dart';
import '../../data/providers/conversation_write_controller.dart';
import '../../domain/entities/session_context.dart';

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
  final _targetDescriptionController = TextEditingController();
  final _openerResultCacheService = OpenerResultCacheService();

  final List<Map<String, dynamic>> _messages = [];

  bool _isLoading = false;
  bool _showPersonalization = false;
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

  String get _primaryButtonText {
    if (_hasIncomingMessage) return '建立對話';
    if (_hasOpenerSeed) return '先儲存開場草稿';
    return '先儲存對話';
  }

  String get _conversationHint {
    if (_messages.isEmpty) {
      return '依序輸入對話，至少先加入一則訊息。';
    }

    if (_hasOpenerSeed && !_hasIncomingMessage) {
      return '已先帶入你準備送出的開場白。送出後，等她回覆再貼到「她說」；也可以先儲存成草稿。';
    }

    if (!_hasIncomingMessage) {
      return '目前還沒有她的回覆，可以先把你已傳出的訊息存成對話；等她回覆後再分析。';
    }

    if (_endsWithMyMessage) {
      return '最後一則可以是我說，系統會以前一則她的回覆作為分析基準。';
    }

    return '最後一則是她說，建立後可直接開始分析。';
  }

  @override
  void initState() {
    super.initState();
    if (widget.seedFromLatestOpener) {
      _seedFromLatestOpener();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _herMessageController.dispose();
    _myMessageController.dispose();
    _targetDescriptionController.dispose();
    super.dispose();
  }

  void _seedFromLatestOpener() {
    try {
      final result = _openerResultCacheService.loadLatestForScope(
          partnerId: widget.partnerId);
      if (result == null) return;
      final openerText = result.bestOpenerText;
      if (openerText == null) return;

      _messages.add({
        'isFromMe': true,
        'content': openerText,
      });
      _hasOpenerSeed = true;
      _openerSeedText = openerText;
      _openerSeedLabel = _openerLabel(result.bestOpenerType);
      _openerSeedReason = result.recommendedReason?.trim();
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

    final repository = ref.read(conversationRepositoryProvider);
    final messages = repository.createMessagesFromList(_messages);
    final shouldShowDraftNotice = !_hasIncomingMessage;

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
        targetDescription: _targetDescriptionController.text.trim().isEmpty
            ? null
            : _targetDescriptionController.text.trim(),
      );
      await controller.save(conversation);

      if (!mounted) return;

      final messenger = ScaffoldMessenger.of(context);
      // pushReplacement (NOT go): swap THIS screen with /conversation/{id}
      // while keeping the underlying PartnerDetail (or wherever the user
      // came from) in the stack. go() would reset the entire stack and
      // strand back-navigation on home. (Bruce TF feedback 2026-04-28).
      context.pushReplacement('/conversation/${conversation.id}');
      if (shouldShowDraftNotice) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('已先存成對話草稿；等她回覆後再開始分析。'),
          ),
        );
      }
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

  List<Widget> _buildSessionContextSettings() {
    return [
      Text('認識情境', style: AppTypography.bodyLarge),
      const SizedBox(height: 8),
      GlassmorphicSegmentedButton<MeetingContext>(
        segments: MeetingContext.values
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
    ];
  }

  List<Widget> _buildPartnerScopedAnalysisSettings() {
    return [
      const SizedBox(height: 24),
      InkWell(
        onTap: () => setState(
          () => _showAnalysisSettings = !_showAnalysisSettings,
        ),
        child: Row(
          children: [
            Icon(
              _showAnalysisSettings ? Icons.expand_less : Icons.expand_more,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '這次分析設定（可不改）',
                style: AppTypography.bodyLarge.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 6),
      Text(
        '只影響這次分析，不會改對象資料。',
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

  List<Widget> _buildLegacyPersonalizationBlock() {
    return [
      const SizedBox(height: 24),
      InkWell(
        onTap: () =>
            setState(() => _showPersonalization = !_showPersonalization),
        child: Row(
          children: [
            Icon(
              _showPersonalization ? Icons.expand_less : Icons.expand_more,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              '個人化資訊（選填）',
              style: AppTypography.bodyLarge.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
      if (_showPersonalization) ...[
        const SizedBox(height: 16),
        Text('對方特質', style: AppTypography.bodyMedium),
        const SizedBox(height: 8),
        GlassmorphicTextField(
          controller: _targetDescriptionController,
          hintText: '例如：活潑、慢熱、喜歡戶外活動',
          isDense: true,
        ),
        const SizedBox(height: 8),
        Text(
          '這些對方資訊可到對象卡的「對方特質」齒輪設定一次。',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
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
                      '這則已放進「我說」。送出後，把她的回覆貼到「她說」，就能接著分析或問教練。名字不確定也能先存成「開場草稿」。',
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
                ..._buildSessionContextSettings(),
                ..._buildLegacyPersonalizationBlock(),
                const SizedBox(height: 24),
                ..._buildConversationContentInput(),
              ] else ...[
                ..._buildConversationContentInput(),
                ..._buildPartnerScopedAnalysisSettings(),
              ],
              const SizedBox(height: 32),
              GradientButton(
                text: _primaryButtonText,
                onPressed: _isLoading ? null : _createConversation,
                isLoading: _isLoading,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
