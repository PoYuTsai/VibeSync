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
  final List<Map<String, dynamic>> _messages = [];
  bool _isLoading = false;

  // Session Context (情境收集)
  MeetingContext _meetingContext = MeetingContext.datingApp;
  AcquaintanceDuration _duration = AcquaintanceDuration.justMet;
  UserGoal _goal = UserGoal.dateInvite;

  // 個人化設定
  UserStyle? _userStyle;
  final _userInterestsController = TextEditingController();
  final _targetDescriptionController = TextEditingController();
  bool _showPersonalization = false;

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
    if (text.isNotEmpty) {
      setState(() {
        _messages.add({'isFromMe': false, 'content': text});
        _herMessageController.clear();
      });
    }
  }

  void _addMyMessage() {
    final text = _myMessageController.text.trim();
    if (text.isNotEmpty) {
      setState(() {
        _messages.add({'isFromMe': true, 'content': text});
        _myMessageController.clear();
      });
    }
  }

  void _removeMessage(int index) {
    setState(() {
      _messages.removeAt(index);
    });
  }

  Future<void> _analyze() async {
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請輸入對話對象暱稱')),
      );
      return;
    }

    if (_messages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請至少新增一則對話')),
      );
      return;
    }

    // Check if last message is from her (we need to respond)
    if (_messages.last['isFromMe'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('最後一則應該是對方的訊息，才能給你回覆建議')),
      );
      return;
    }

    final repository = ref.read(conversationRepositoryProvider);
    final messages = repository.createMessagesFromList(_messages);

    setState(() => _isLoading = true);

    try {
      final conversation = await repository.createConversation(
        name: name,
        messages: messages,
      );

      // Update session context
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

      // 刷新對話列表，確保返回首頁時能看到新對話
      ref.invalidate(conversationsProvider);

      if (mounted) {
        context.go('/conversation/${conversation.id}');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
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
          title: Text('新增對話', style: AppTypography.titleLarge),
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
            Text('對話對象暱稱', style: AppTypography.bodyLarge),
            const SizedBox(height: 8),
            GlassmorphicTextField(
              controller: _nameController,
              hintText: '例如：小美',
            ),

            // === 情境收集區塊 ===
            const SizedBox(height: 24),
            Text('認識場景', style: AppTypography.bodyLarge),
            const SizedBox(height: 8),
            GlassmorphicSegmentedButton<MeetingContext>(
              segments: const [
                GlassSegment(value: MeetingContext.datingApp, label: '交友軟體'),
                GlassSegment(value: MeetingContext.inPerson, label: '現實搭訕'),
                GlassSegment(value: MeetingContext.friendIntro, label: '朋友介紹'),
              ],
              selected: _meetingContext,
              onChanged: (v) => setState(() => _meetingContext = v),
            ),

            const SizedBox(height: 16),
            Text('認識多久', style: AppTypography.bodyLarge),
            const SizedBox(height: 8),
            GlassmorphicSegmentedButton<AcquaintanceDuration>(
              segments: const [
                GlassSegment(value: AcquaintanceDuration.justMet, label: '剛認識'),
                GlassSegment(value: AcquaintanceDuration.fewDays, label: '幾天'),
                GlassSegment(value: AcquaintanceDuration.fewWeeks, label: '幾週'),
                GlassSegment(value: AcquaintanceDuration.monthPlus, label: '一個月+'),
              ],
              selected: _duration,
              onChanged: (v) => setState(() => _duration = v),
            ),

            const SizedBox(height: 16),
            Text('你的目標', style: AppTypography.bodyLarge),
            const SizedBox(height: 8),
            GlassmorphicSegmentedButton<UserGoal>(
              segments: const [
                GlassSegment(value: UserGoal.dateInvite, label: '約出來'),
                GlassSegment(value: UserGoal.maintainHeat, label: '維持熱度'),
                GlassSegment(value: UserGoal.justChat, label: '隨意聊'),
              ],
              selected: _goal,
              onChanged: (v) => setState(() => _goal = v),
            ),

            // === 個人化設定區塊（可折疊）===
            const SizedBox(height: 24),
            InkWell(
              onTap: () =>
                  setState(() => _showPersonalization = !_showPersonalization),
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
                    '個人化設定（選填）',
                    style: AppTypography.bodyLarge
                        .copyWith(color: AppColors.textSecondary),
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
                    label: Text(style.label),
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
              TextField(
                controller: _userInterestsController,
                decoration: const InputDecoration(
                  hintText: '例如：咖啡、攝影、露營',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              Text('對方特質', style: AppTypography.bodyMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _targetDescriptionController,
                decoration: const InputDecoration(
                  hintText: '例如：慢熱、喜歡旅行',
                  isDense: true,
                ),
              ),
            ],

            const SizedBox(height: 24),
            Text('對話內容', style: AppTypography.bodyLarge),
            const SizedBox(height: 8),

            // 已新增的訊息列表
            if (_messages.isNotEmpty) ...[
              GlassmorphicContainer(
                borderRadius: 12,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isFromMe = msg['isFromMe'] as bool;
                      return ListTile(
                        dense: true,
                        leading: BubbleAvatar(
                          label: isFromMe ? '我' : '她',
                          isMe: isFromMe,
                          size: 28,
                        ),
                        title: Text(
                          msg['content'] as String,
                          style: AppTypography.bodyMedium,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => _removeMessage(index),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // 新增「她的訊息」
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
                IconButton(
                  icon: const Icon(Icons.add_circle, color: AppColors.warm),
                  onPressed: _addHerMessage,
                ),
              ],
            ),

            const SizedBox(height: 8),

            // 新增「我的訊息」
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
                    hintText: '我回了什麼...',
                    onSubmitted: (_) => _addMyMessage(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: AppColors.primary),
                  onPressed: _addMyMessage,
                ),
              ],
            ),

            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '依序輸入對話，最後一則須為「她」的訊息',
                      style: AppTypography.caption,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            GradientButton(
              text: '開始分析',
              onPressed: _isLoading ? null : _analyze,
              isLoading: _isLoading,
            ),
          ],
        ),
      ),
    ),
    );
  }
}
