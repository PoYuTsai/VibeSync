// lib/features/conversation/presentation/screens/new_conversation_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/warm_theme_widgets.dart';
import '../../data/providers/conversation_providers.dart';
import '../../domain/entities/session_context.dart';

class NewConversationScreen extends ConsumerStatefulWidget {
  const NewConversationScreen({super.key});

  @override
  ConsumerState<NewConversationScreen> createState() =>
      _NewConversationScreenState();
}

class _NewConversationScreenState extends ConsumerState<NewConversationScreen> {
  final _nameController = TextEditingController();
  final _herMessageController = TextEditingController();
  final _myMessageController = TextEditingController();
  final _userInterestsController = TextEditingController();
  final _targetDescriptionController = TextEditingController();

  final List<Map<String, dynamic>> _messages = [];

  bool _isLoading = false;
  bool _showPersonalization = false;

  MeetingContext _meetingContext = MeetingContext.datingApp;
  AcquaintanceDuration _duration = AcquaintanceDuration.justMet;
  UserGoal _goal = UserGoal.dateInvite;
  UserStyle? _userStyle;

  bool get _hasIncomingMessage =>
      _messages.any((message) => message['isFromMe'] == false);

  bool get _endsWithMyMessage =>
      _messages.isNotEmpty && (_messages.last['isFromMe'] as bool);

  String get _primaryButtonText => _hasIncomingMessage ? '建立對話' : '先儲存對話';

  String get _conversationHint {
    if (_messages.isEmpty) {
      return '依序輸入對話，至少先加入一則訊息。';
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
  void dispose() {
    _nameController.dispose();
    _herMessageController.dispose();
    _myMessageController.dispose();
    _userInterestsController.dispose();
    _targetDescriptionController.dispose();
    super.dispose();
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

  Future<void> _createConversation() async {
    final name = _nameController.text.trim();

    if (name.isEmpty) {
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
      final conversation = await repository.createConversation(
        name: name,
        messages: messages,
      );

      conversation.sessionContext = SessionContext(
        meetingContext: _meetingContext,
        duration: _duration,
        goal: _goal,
        userStyle: _userStyle,
        userInterests: _userInterestsController.text.trim().isEmpty
            ? null
            : _userInterestsController.text.trim(),
        targetDescription: _targetDescriptionController.text.trim().isEmpty
            ? null
            : _targetDescriptionController.text.trim(),
      );
      await repository.updateConversation(conversation);

      ref.invalidate(conversationsProvider);

      if (!mounted) return;

      final messenger = ScaffoldMessenger.of(context);
      context.go('/conversation/${conversation.id}');
      if (shouldShowDraftNotice) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('已先存成對話草稿；等她回覆後再開始分析。'),
          ),
        );
      }
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

  String _userStyleLabel(UserStyle style) {
    switch (style) {
      case UserStyle.humorous:
        return '幽默';
      case UserStyle.steady:
        return '穩重';
      case UserStyle.direct:
        return '直接';
      case UserStyle.gentle:
        return '溫柔';
      case UserStyle.playful:
        return '俏皮';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text('手動輸入', style: AppTypography.titleLarge),
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
              Text('對話對象', style: AppTypography.bodyLarge),
              const SizedBox(height: 8),
              GlassmorphicTextField(
                controller: _nameController,
                hintText: '例如：小安',
              ),
              const SizedBox(height: 24),
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
              const SizedBox(height: 24),
              InkWell(
                onTap: () => setState(
                    () => _showPersonalization = !_showPersonalization),
                child: Row(
                  children: [
                    Icon(
                      _showPersonalization
                          ? Icons.expand_less
                          : Icons.expand_more,
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
                Text('你的風格', style: AppTypography.bodyMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: UserStyle.values.map((style) {
                    final isSelected = _userStyle == style;
                    return ChoiceChip(
                      label: Text(_userStyleLabel(style)),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() => _userStyle = selected ? style : null);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Text('你的興趣', style: AppTypography.bodyMedium),
                const SizedBox(height: 8),
                GlassmorphicTextField(
                  controller: _userInterestsController,
                  hintText: '例如：健身、旅行、攝影、咖啡',
                  isDense: true,
                ),
                const SizedBox(height: 16),
                Text('對方特質', style: AppTypography.bodyMedium),
                const SizedBox(height: 8),
                GlassmorphicTextField(
                  controller: _targetDescriptionController,
                  hintText: '例如：活潑、慢熱、喜歡戶外活動',
                  isDense: true,
                ),
              ],
              const SizedBox(height: 24),
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
