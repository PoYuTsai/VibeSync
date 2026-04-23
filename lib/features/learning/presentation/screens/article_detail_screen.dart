// lib/features/learning/presentation/screens/article_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/warm_theme_widgets.dart';
import '../../../subscription/data/providers/subscription_providers.dart';
import '../../data/articles_data.dart';
import '../../data/providers/learning_providers.dart';

class ArticleDetailScreen extends ConsumerStatefulWidget {
  final String articleId;

  const ArticleDetailScreen({super.key, required this.articleId});

  @override
  ConsumerState<ArticleDetailScreen> createState() =>
      _ArticleDetailScreenState();
}

class _ArticleDetailScreenState extends ConsumerState<ArticleDetailScreen> {
  bool _readGateChecked = false;

  Article? _findArticle() {
    try {
      return articles.firstWhere((a) => a.id == widget.articleId);
    } catch (_) {
      return null;
    }
  }

  void _scheduleReadGate(SubscriptionState subscription) {
    if (_readGateChecked || subscription.isLoading) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyReadGate());
  }

  void _applyReadGate() {
    if (!mounted || _readGateChecked) return;

    final subscription = ref.read(subscriptionProvider);
    if (subscription.isLoading) return;

    final article = _findArticle();
    if (article == null) {
      setState(() => _readGateChecked = true);
      return;
    }

    if (!subscription.isFreeUser) {
      setState(() => _readGateChecked = true);
      return;
    }

    final readService = ref.read(articleReadServiceProvider);
    if (!readService.canReadArticle(widget.articleId)) {
      setState(() => _readGateChecked = true);
      context.go('/paywall');
      return;
    }

    readService.recordReadArticle(widget.articleId);
    ref.invalidate(articleReadServiceProvider);
    setState(() => _readGateChecked = true);
  }

  @override
  Widget build(BuildContext context) {
    final article = _findArticle();
    if (article == null) {
      return const Scaffold(body: Center(child: Text('Article not found')));
    }
    final subscription = ref.watch(subscriptionProvider);
    _scheduleReadGate(subscription);

    if (subscription.isLoading ||
        (subscription.isFreeUser && !_readGateChecked)) {
      return const GradientBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            article.title,
            style: AppTypography.titleMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Source + read time
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.ctaStart.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      article.category,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.ctaStart,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    article.readTime,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.onBackgroundSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Article content in glass container
              GlassmorphicContainer(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _parseContent(article.content),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: GradientButton(
                  text: '學完了？來實戰練習',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _parseContent(String content) {
    final lines = content.split('\n');
    final widgets = <Widget>[];

    for (final line in lines) {
      final trimmed = line.trimLeft();

      if (trimmed.isEmpty) {
        widgets.add(const SizedBox(height: 8));
        continue;
      }

      if (trimmed.startsWith('### ')) {
        // H3 subheading
        final text = trimmed.substring(4);
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 6),
          child: Text(
            text,
            style: AppTypography.titleSmall.copyWith(
              color: AppColors.glassTextPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ));
      } else if (trimmed.startsWith('## ')) {
        // H2 heading
        final text = trimmed.substring(3);
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text(
            text,
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.glassTextPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ));
      } else if (trimmed.startsWith('- ')) {
        // Bullet point
        final text = trimmed.substring(2);
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.glassTextSecondary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _buildRichText(text)),
            ],
          ),
        ));
      } else {
        // Regular text
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: _buildRichText(trimmed),
        ));
      }
    }

    return widgets;
  }

  /// Parse bold (**text**) and check/cross markers into rich text.
  Widget _buildRichText(String text) {
    final spans = <InlineSpan>[];
    final boldPattern = RegExp(r'\*\*(.+?)\*\*');
    int lastEnd = 0;

    for (final match in boldPattern.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      spans.add(TextSpan(
        text: match.group(1),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ));
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    // Default style
    var baseStyle = AppTypography.bodyMedium.copyWith(
      color: AppColors.glassTextPrimary,
      height: 1.6,
    );

    // Check/cross prefix colouring
    Widget? leadingIcon;
    if (text.startsWith('\u2705 ') || text.startsWith('\u2705')) {
      leadingIcon =
          const Icon(Icons.check_circle, color: AppColors.success, size: 16);
    } else if (text.startsWith('\u274C ') || text.startsWith('\u274C')) {
      leadingIcon = const Icon(Icons.cancel, color: AppColors.error, size: 16);
    }

    final richText = RichText(
      text: TextSpan(style: baseStyle, children: spans),
    );

    if (leadingIcon != null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: leadingIcon,
          ),
          const SizedBox(width: 6),
          Expanded(child: richText),
        ],
      );
    }

    return richText;
  }
}
