import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/warm_theme_widgets.dart';
import '../../../subscription/data/providers/subscription_providers.dart';
import '../../../../core/services/usage_service.dart';
import '../../data/services/opener_service.dart';

class OpeningRescueScreen extends ConsumerStatefulWidget {
  const OpeningRescueScreen({super.key});

  @override
  ConsumerState<OpeningRescueScreen> createState() =>
      _OpeningRescueScreenState();
}

class _OpeningRescueScreenState extends ConsumerState<OpeningRescueScreen> {
  int _selectedTab = 0;
  List<Uint8List> _images = [];

  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _interestsController = TextEditingController();
  String? _meetingContext;

  bool _isGenerating = false;
  OpenerResult? _result;
  String? _error;
  final _scrollController = ScrollController();

  static const _meetingOptions = ['交友軟體', 'IG', '現實認識', '其他'];

  static const _openerTypeLabels = {
    'extend': '🔄 延展',
    'resonate': '💬 共鳴',
    'tease': '😏 調情',
    'humor': '🎭 幽默',
    'coldRead': '🔮 冷讀',
  };

  int get _estimatedCost => 3 + (_images.length * 2);

  UsageData _currentUsageSnapshot() {
    final subscription = ref.read(subscriptionProvider);
    final localUsage = ref.read(usageDataProvider);

    if (subscription.isLoading) {
      return localUsage;
    }

    return UsageData(
      monthlyUsed: subscription.monthlyMessagesUsed,
      monthlyLimit: subscription.monthlyLimit,
      dailyUsed: subscription.dailyMessagesUsed,
      dailyLimit: subscription.dailyLimit,
      dailyResetAt: localUsage.dailyResetAt,
      tier: subscription.tier,
    );
  }

  Future<bool> _canStartGeneration(int cost) async {
    if (_currentUsageSnapshot().canAfford(cost)) {
      return true;
    }

    try {
      await ref.read(subscriptionScreenRefreshProvider)();
    } catch (_) {
      // If refresh is temporarily unavailable, let the Edge Function make the
      // authoritative quota decision instead of blocking a fresh free user.
      return true;
    }

    if (_currentUsageSnapshot().canAfford(cost)) {
      return true;
    }

    if (mounted) {
      context.push('/paywall');
    }
    return false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _interestsController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    // Validate input
    final hasImages = _images.isNotEmpty;
    final hasManualInput = _nameController.text.trim().isNotEmpty ||
        _bioController.text.trim().isNotEmpty ||
        _interestsController.text.trim().isNotEmpty;

    if (!hasImages && !hasManualInput) {
      setState(() => _error = '請上傳截圖或輸入對方資料');
      return;
    }

    final cost = _estimatedCost;
    if (!await _canStartGeneration(cost)) {
      return;
    }
    if (!mounted) return;

    // 收鍵盤
    FocusScope.of(context).unfocus();

    setState(() {
      _isGenerating = true;
      _error = null;
      _result = null;
    });

    try {
      final service = OpenerService();
      final result = await service.generateOpeners(
        images: _images.isNotEmpty ? _images : null,
        name: _nameController.text,
        bio: _bioController.text,
        interests: _interestsController.text,
        meetingContext: _meetingContext,
      );
      if (mounted) {
        setState(() {
          _result = result;
          _isGenerating = false;
        });

        try {
          await ref.read(subscriptionScreenRefreshProvider)();
        } catch (_) {
          // The opener result already succeeded; usage UI can catch up on the
          // next subscription refresh if this best-effort sync fails.
        }
        if (!mounted) return;

        // 滾到結果區域
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } on OpenerQuotaExceededException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _isGenerating = false;
        });
        context.push('/paywall');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _isGenerating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final subscription = ref.watch(subscriptionProvider);

    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
            onPressed: () => context.pop(),
          ),
          title: Text('開場救星', style: AppTypography.headlineMedium),
        ),
        body: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text(
                '開場救星',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.bokehCoral,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'AI 幫你打造完美開場',
                style: AppTypography.headlineLarge.copyWith(
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),

              // Tab switcher
              GlassmorphicSegmentedButton<int>(
                segments: const [
                  GlassSegment(value: 0, label: '截圖自介'),
                  GlassSegment(value: 1, label: '手動輸入'),
                ],
                selected: _selectedTab,
                onChanged: (val) => setState(() => _selectedTab = val),
              ),
              const SizedBox(height: 20),

              // Tab content
              if (_selectedTab == 0) _buildScreenshotTab(),
              if (_selectedTab == 1) _buildManualTab(),

              const SizedBox(height: 16),

              // Cost indicator
              Center(
                child: Text(
                  '將使用 $_estimatedCost 則額度',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.onBackgroundSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Generate button
              GradientButton(
                text: '生成開場白',
                isLoading: _isGenerating,
                onPressed: _isGenerating ? null : _generate,
              ),
              const SizedBox(height: 16),

              // Loading state
              if (_isGenerating)
                Center(
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      const CircularProgressIndicator(
                        valueColor:
                            AlwaysStoppedAnimation<Color>(AppColors.bokehCoral),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'AI 正在分析...',
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.onBackgroundSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

              // Error
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Center(
                    child: Text(
                      _error!,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),

              // Results
              if (_result != null) ...[
                const SizedBox(height: 24),
                _buildResults(subscription),
              ],

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScreenshotTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '上傳對方的交友軟體自介截圖',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.onBackgroundSecondary,
          ),
        ),
        const SizedBox(height: 12),
        ImagePickerWidget(
          maxImages: 3,
          onImagesChanged: (images) => setState(() => _images = images),
          externalImages: _images,
        ),
      ],
    );
  }

  Widget _buildManualTab() {
    return GlassmorphicContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '對方名字',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.glassTextSecondary,
            ),
          ),
          const SizedBox(height: 6),
          GlassmorphicTextField(
            controller: _nameController,
            hintText: '輸入對方名字（選填）',
            isDense: true,
          ),
          const SizedBox(height: 16),
          Text(
            'Bio / 自我介紹',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.glassTextSecondary,
            ),
          ),
          const SizedBox(height: 6),
          _buildMultilineField(
            controller: _bioController,
            hintText: '貼上對方的自介內容',
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          Text(
            '興趣',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.glassTextSecondary,
            ),
          ),
          const SizedBox(height: 6),
          GlassmorphicTextField(
            controller: _interestsController,
            hintText: '對方的興趣標籤（選填）',
            isDense: true,
          ),
          const SizedBox(height: 16),
          Text(
            '認識場景',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.glassTextSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _meetingOptions.map((option) {
              final isSelected = _meetingContext == option;
              return ChoiceChip(
                label: Text(option),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _meetingContext = selected ? option : null;
                  });
                },
                selectedColor: AppColors.ctaStart.withValues(alpha: 0.2),
                backgroundColor: AppColors.glassWhite,
                labelStyle: AppTypography.bodySmall.copyWith(
                  color: isSelected
                      ? AppColors.ctaStart
                      : AppColors.glassTextSecondary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
                side: BorderSide(
                  color:
                      isSelected ? AppColors.ctaStart : AppColors.glassBorder,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildMultilineField({
    required TextEditingController controller,
    required String hintText,
    int maxLines = 3,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.glassWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder, width: 1.5),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: AppTypography.bodyMedium.copyWith(
          color: AppColors.glassTextPrimary,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: AppTypography.bodyMedium.copyWith(
            color: AppColors.glassTextHint,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          filled: true,
          fillColor: Colors.transparent,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildResults(SubscriptionState subscription) {
    final result = _result!;
    final isFree = subscription.isFreeUser;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Profile analysis card
        if (result.profileAnalysis != null) ...[
          GlassmorphicContainer(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '對方特質分析',
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.glassTextPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                ..._buildProfileAnalysisItems(result.profileAnalysis!),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        // Opener cards header
        Row(
          children: [
            Text(
              '開場白建議',
              style: AppTypography.titleMedium.copyWith(
                color: Colors.white,
              ),
            ),
            Text(
              ' ・5 種風格',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.onBackgroundSecondary,
              ),
            ),
            const Spacer(),
            Text(
              '← 左右滑動',
              style: AppTypography.caption.copyWith(
                color: AppColors.onBackgroundSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Horizontal scroll opener cards
        SizedBox(
          height: 220,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: result.openers.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final entry = result.openers.entries.elementAt(index);
              final type = entry.key;
              final content = entry.value;
              final isRecommended = type == result.recommendedPick;
              final isLocked = isFree && type != 'extend';

              return _buildOpenerCard(
                type: type,
                content: content,
                isRecommended: isRecommended,
                isLocked: isLocked,
              );
            },
          ),
        ),

        // Recommended reason
        if (result.recommendedReason != null) ...[
          const SizedBox(height: 12),
          GlassmorphicContainer(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Text('💡', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'AI 推薦理由：${result.recommendedReason}',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.glassTextSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 16),

        // Regenerate button
        Center(
          child: OutlinedButton.icon(
            onPressed: _isGenerating ? null : _generate,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('重新生成'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.onBackgroundSecondary,
              side: BorderSide(
                color: AppColors.onBackgroundSecondary.withValues(alpha: 0.5),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildProfileAnalysisItems(Map<String, dynamic> analysis) {
    final items = <Widget>[];
    final labelMap = {
      'style': '風格',
      'personality': '切入判斷',
      'talkingPoints': '話題切入點',
      'vibe': '氛圍',
      'interests': '興趣',
    };

    for (final entry in analysis.entries) {
      final label = labelMap[entry.key] ?? entry.key;
      final value = entry.value;
      if (value == null) continue;

      items.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 80,
              child: Text(
                label,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.glassTextHint,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value is List ? value.join('、') : value.toString(),
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.glassTextPrimary,
                ),
              ),
            ),
          ],
        ),
      ));
    }

    return items;
  }

  Widget _buildOpenerCard({
    required String type,
    required String content,
    bool isRecommended = false,
    bool isLocked = false,
  }) {
    final label = _openerTypeLabels[type] ?? type;

    return SizedBox(
      width: 280,
      child: GlassmorphicContainer(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Text(
                  label,
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.glassTextPrimary,
                  ),
                ),
                const Spacer(),
                if (isRecommended)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.ctaStart, AppColors.ctaEnd],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'AI 推薦',
                      style: AppTypography.caption.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Content or locked state
            Expanded(
              child: isLocked
                  ? _buildLockedContent()
                  : Text(
                      content,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.glassTextPrimary,
                        height: 1.6,
                      ),
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),

            const SizedBox(height: 8),

            // Copy button or upgrade button
            if (isLocked)
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => context.push('/paywall'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.ctaStart,
                  ),
                  child: const Text('升級解鎖'),
                ),
              )
            else
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: content));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('已複製「$label」開場白'),
                        duration: const Duration(seconds: 2),
                        backgroundColor: AppColors.backgroundGradientMid
                            .withValues(alpha: 0.9),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('複製'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.glassTextHint,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLockedContent() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.lock_outline,
            size: 32,
            color: AppColors.glassTextHint.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 8),
          Text(
            '升級解鎖此風格',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.glassTextHint,
            ),
          ),
        ],
      ),
    );
  }
}
