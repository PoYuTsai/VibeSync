// lib/features/conversation/presentation/screens/new_conversation_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
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

  @override
  void dispose() {
    _nameController.dispose();
    _herMessageController.dispose();
    _myMessageController.dispose();
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
      );
      await repository.updateConversation(conversation);

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
    return Scaffold(
      appBar: AppBar(
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
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                hintText: '例如：小美',
              ),
            ),

            // === 情境收集區塊 ===
            const SizedBox(height: 24),
            Text('認識場景', style: AppTypography.bodyLarge),
            const SizedBox(height: 8),
            SegmentedButton<MeetingContext>(
              segments: const [
                ButtonSegment(
                    value: MeetingContext.datingApp, label: Text('交友軟體')),
                ButtonSegment(
                    value: MeetingContext.inPerson, label: Text('現實搭訕')),
                ButtonSegment(
                    value: MeetingContext.friendIntro, label: Text('朋友介紹')),
              ],
              selected: {_meetingContext},
              onSelectionChanged: (v) =>
                  setState(() => _meetingContext = v.first),
            ),

            const SizedBox(height: 16),
            Text('認識多久', style: AppTypography.bodyLarge),
            const SizedBox(height: 8),
            SegmentedButton<AcquaintanceDuration>(
              segments: const [
                ButtonSegment(
                    value: AcquaintanceDuration.justMet, label: Text('剛認識')),
                ButtonSegment(
                    value: AcquaintanceDuration.fewDays, label: Text('幾天')),
                ButtonSegment(
                    value: AcquaintanceDuration.fewWeeks, label: Text('幾週')),
                ButtonSegment(
                    value: AcquaintanceDuration.monthPlus,
                    label: Text('一個月+')),
              ],
              selected: {_duration},
              onSelectionChanged: (v) => setState(() => _duration = v.first),
            ),

            const SizedBox(height: 16),
            Text('你的目標', style: AppTypography.bodyLarge),
            const SizedBox(height: 8),
            SegmentedButton<UserGoal>(
              segments: const [
                ButtonSegment(
                    value: UserGoal.dateInvite, label: Text('約出來')),
                ButtonSegment(
                    value: UserGoal.maintainHeat, label: Text('維持熱度')),
                ButtonSegment(value: UserGoal.justChat, label: Text('隨意聊')),
              ],
              selected: {_goal},
              onSelectionChanged: (v) => setState(() => _goal = v.first),
            ),

            const SizedBox(height: 24),
            Text('對話內容', style: AppTypography.bodyLarge),
            const SizedBox(height: 8),

            // 已新增的訊息列表
            if (_messages.isNotEmpty) ...[
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.divider),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    final isFromMe = msg['isFromMe'] as bool;
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: isFromMe ? AppColors.primary : AppColors.warm,
                        child: Text(
                          isFromMe ? '我' : '她',
                          style: const TextStyle(fontSize: 12, color: Colors.white),
                        ),
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
              const SizedBox(height: 12),
            ],

            // 新增「她的訊息」
            Row(
              children: [
                const CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.warm,
                  child: Text('她', style: TextStyle(fontSize: 12, color: Colors.white)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _herMessageController,
                    decoration: const InputDecoration(
                      hintText: '她說了什麼...',
                      isDense: true,
                    ),
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
                const CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.primary,
                  child: Text('我', style: TextStyle(fontSize: 12, color: Colors.white)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _myMessageController,
                    decoration: const InputDecoration(
                      hintText: '我回了什麼...',
                      isDense: true,
                    ),
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
            ElevatedButton(
              onPressed: _isLoading ? null : _analyze,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('開始分析'),
            ),
          ],
        ),
      ),
    );
  }
}
