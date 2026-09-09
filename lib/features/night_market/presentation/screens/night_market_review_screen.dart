import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/reveal_pill.dart';
import '../../domain/night_market_scenario.dart';
import 'night_market_review_player.dart';

/// The completed demonstration has one shared knowledge source and native
/// routes, so returning from a detail keeps the caller's reading position.
class NightMarketReviewScreen extends StatelessWidget {
  const NightMarketReviewScreen({
    super.key,
    required this.scenario,
    required this.onRestart,
    required this.onExit,
  });

  final NightMarketScenario scenario;
  final VoidCallback onRestart;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final homeRoute = ModalRoute.of(context)!;
    final navigator = Navigator.of(context);
    void openChapter(NightMarketReviewChapter chapter) {
      // A related chapter starts from the overview, rather than growing an
      // unbounded chapter -> knowledge -> chapter navigation stack.
      navigator.pushAndRemoveUntil<void>(
        MaterialPageRoute(
          builder: (_) => _ChapterScreen(
            scenario: scenario,
            chapter: chapter,
            onChapter: openChapter,
          ),
        ),
        (route) => identical(route, homeRoute),
      );
    }

    void openKnowledge(NightMarketReviewItem item) =>
        _openKnowledge(context, scenario, item, openChapter);

    final mindsets = scenario.review
        .where((item) => item.tier == NightMarketReviewTier.mindset);
    return _ReadingPage(
      title: '復盤',
      leading: IconButton(
        tooltip: '回練習室',
        onPressed: onExit,
        icon: const Icon(Icons.close),
      ),
      children: [
        const _Heading('把剛才的互動看懂'),
        const _Paragraph('從走過去到收尾，回看每一步為什麼這樣接。'
            '也留意貫穿全程的潛溝通：態度、眼神與肢體。'),
        const SizedBox(height: 16),
        for (final (index, chapter) in scenario.reviewChapters.indexed)
          _NavigationRow(
            key: ValueKey('chapter-${chapter.id}'),
            number: '${index + 1}'.padLeft(2, '0'),
            title: chapter.title,
            subtitle:
                '${chapter.timeLabel} · ${chapter.explanations.map((e) => e.title.split('｜').first).join(' · ')}',
            onTap: () => openChapter(chapter),
          ),
        const SizedBox(height: 28),
        const _Heading('貫穿全程的狀態', small: true),
        const _Paragraph('從你最有感覺、或最容易卡住的地方開始看。'),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final item in mindsets)
              OutlinedButton(
                onPressed: () => openKnowledge(item),
                child: Text(item.term),
              ),
          ],
        ),
        const SizedBox(height: 16),
        // Eric: reuse the existing opener disclosure, including its centered
        // trigger, animation, full-width body and left-aligned content.
        RevealPill(
          label: '所有知識點（${scenario.review.length}）',
          children: [
            for (final group in _knowledgeGroups) ...[
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: _Heading(group.$1, small: true),
              ),
              for (final id in group.$2)
                _NavigationRow(
                  title: scenario.reviewById(id).term,
                  subtitle: id == 'shit_test' ? '延伸情境 · 本次未明確示範' : null,
                  onTap: () => openKnowledge(scenario.reviewById(id)),
                ),
            ],
          ],
        ),
        const SizedBox(height: 28),
        _Heading(scenario.takeaway, small: true),
        const SizedBox(height: 8),
        FilledButton(onPressed: onRestart, child: const Text('再練一次')),
        OutlinedButton(onPressed: onExit, child: const Text('回練習室')),
      ],
    );
  }
}

const _knowledgeGroups = <(String, List<String>)>[
  (
    '心態與狀態',
    [
      'approach_anxiety',
      'certainty',
      'worthiness',
      'self_amusement',
      'flow',
      'control',
    ]
  ),
  (
    '接近與開場',
    [
      'nonverbal_eye_contact',
      'opening',
      'opener',
      'gender_intent',
    ]
  ),
  ('陌生感與信任', ['empathy_background', 'first_minute', 'handshake']),
  (
    '話題與吸引',
    [
      'cold_read',
      'questions',
      'hook',
      'lifestyle_sample',
      'personality_sample',
      'emotion',
      'sexual_hook',
    ]
  ),
  (
    '進退與收尾',
    [
      'qualification',
      'disqualification',
      'push_pull',
      'disinterest',
      'contact',
      'busy_or_instant_date',
    ]
  ),
  ('遇到狀況時', ['shit_test']),
];

void _openKnowledge(
  BuildContext context,
  NightMarketScenario scenario,
  NightMarketReviewItem item,
  ValueChanged<NightMarketReviewChapter> onChapter, {
  String? originChapterId,
}) {
  Navigator.of(context).push<void>(MaterialPageRoute(
    builder: (_) => _KnowledgeScreen(
      scenario: scenario,
      item: item,
      onChapter: onChapter,
      originChapterId: originChapterId,
    ),
  ));
}

class _ChapterScreen extends StatelessWidget {
  const _ChapterScreen({
    required this.scenario,
    required this.chapter,
    required this.onChapter,
  });

  final NightMarketScenario scenario;
  final NightMarketReviewChapter chapter;
  final ValueChanged<NightMarketReviewChapter> onChapter;

  @override
  Widget build(BuildContext context) {
    final index = scenario.reviewChapters.indexOf(chapter);
    final primaryIds = chapter.explanations.map((e) => e.knowledgeId).toSet();
    return _ReadingPage(
      title: '片段解析 ${index + 1}／${scenario.reviewChapters.length}',
      children: [
        _Heading(chapter.title),
        _Paragraph(chapter.timeLabel, muted: true),
        OutlinedButton.icon(
          icon: const Icon(Icons.play_circle_outline),
          label: const Text('回看這段'),
          onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(
            builder: (_) => NightMarketReviewPlayer(
              scenario: scenario,
              chapter: chapter,
            ),
          )),
        ),
        const SizedBox(height: 16),
        _Surface(children: [
          const _Heading('剛才的對話', small: true),
          for (final line in chapter.dialogue) _Paragraph(line),
        ]),
        const SizedBox(height: 20),
        for (final explanation in chapter.explanations) ...[
          _Heading(explanation.title, small: true),
          _Paragraph(explanation.text),
          const SizedBox(height: 12),
        ],
        RevealPill(
          label: '看完整解析',
          children: [
            for (final id in primaryIds) ...[
              _Heading(scenario.reviewById(id).term, small: true),
              _Paragraph(scenario.reviewById(id).plain),
              if (scenario.reviewById(id).detail case final detail?)
                _Paragraph(detail),
              _NavigationRow(
                title: '繼續看「${scenario.reviewById(id).term}」',
                onTap: () => _openKnowledge(
                  context,
                  scenario,
                  scenario.reviewById(id),
                  onChapter,
                  originChapterId: chapter.id,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
        const SizedBox(height: 24),
        const _Heading('下次怎麼用', small: true),
        _Paragraph(chapter.practice),
        const SizedBox(height: 16),
        const _Heading('這段的知識點', small: true),
        for (final id in chapter.knowledgeIds)
          _NavigationRow(
            title: scenario.reviewById(id).term,
            onTap: () => _openKnowledge(
              context,
              scenario,
              scenario.reviewById(id),
              onChapter,
              originChapterId: chapter.id,
            ),
          ),
        const SizedBox(height: 24),
        if (index + 1 < scenario.reviewChapters.length)
          FilledButton(
            onPressed: () => onChapter(scenario.reviewChapters[index + 1]),
            child: const Text('下一段解析'),
          )
        else
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('回復盤總覽'),
          ),
      ],
    );
  }
}

class _KnowledgeScreen extends StatelessWidget {
  const _KnowledgeScreen({
    required this.scenario,
    required this.item,
    required this.onChapter,
    required this.originChapterId,
  });

  final NightMarketScenario scenario;
  final NightMarketReviewItem item;
  final ValueChanged<NightMarketReviewChapter> onChapter;
  final String? originChapterId;

  @override
  Widget build(BuildContext context) {
    final chapters = scenario.reviewChapters
        .where((chapter) => chapter.knowledgeIds.contains(item.id));
    return _ReadingPage(
      title: '知識詳解',
      children: [
        _Heading(item.term),
        if (!item.met)
          _Paragraph(
            item.id == 'busy_or_instant_date'
                ? '本次是改天咖啡，沒有示範當下即約。'
                : '延伸情境 · 本次主線未明確示範',
            muted: true,
          ),
        if (item.optional) const _Paragraph('可運用的細節，不必每次刻意安排。', muted: true),
        _Paragraph(item.plain),
        RevealPill(
          label: '下一步怎麼做',
          children: [
            if (item.detail case final detail?) ...[
              const _Heading('再看細節', small: true),
              _Paragraph(detail),
            ],
            const _Heading('下次可以這樣練', small: true),
            _Paragraph(item.practice),
            if (item.sceneNote case final scene?) ...[
              const _Heading('對照這次互動', small: true),
              _Paragraph(scene),
            ],
            const SizedBox(height: 8),
            const _Heading('課程來源', small: true),
            _Paragraph(item.source, muted: true),
          ],
        ),
        if (chapters.isNotEmpty) ...[
          const SizedBox(height: 28),
          const _Heading('放回互動裡看', small: true),
          for (final chapter in chapters)
            _NavigationRow(
              title: chapter.title,
              subtitle: chapter.timeLabel,
              onTap: () {
                if (chapter.id == originChapterId) {
                  Navigator.of(context).pop();
                } else {
                  onChapter(chapter);
                }
              },
            ),
        ],
      ],
    );
  }
}

class _ReadingPage extends StatelessWidget {
  const _ReadingPage(
      {required this.title, required this.children, this.leading});

  final String title;
  final List<Widget> children;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => Theme(
      data: Theme.of(context).copyWith(
        outlinedButtonTheme: OutlinedButtonThemeData(
          style:
              OutlinedButton.styleFrom(foregroundColor: AppColors.primaryLight),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.ctaStart,
            foregroundColor: AppColors.brandInk,
          ),
        ),
      ),
      child: Scaffold(
        backgroundColor: AppColors.brandInk,
        appBar: AppBar(
          title: Text(title),
          backgroundColor: AppColors.brandInk,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          leading: leading,
        ),
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ));
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.small = false});
  final String text;
  final bool small;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Semantics(
          header: true,
          child: Text(text,
              style: (small
                      ? AppTypography.titleLarge
                      : AppTypography.headlineMedium)
                  .copyWith(
                color: Colors.white,
                height: 1.4,
                fontWeight: FontWeight.w700,
              )),
        ),
      );
}

class _Paragraph extends StatelessWidget {
  const _Paragraph(this.text, {this.muted = false});
  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text,
            textAlign: TextAlign.start,
            style: AppTypography.bodyLarge.copyWith(
              color: muted ? Colors.white60 : Colors.white70,
              fontSize: muted ? 14 : 15,
              height: 1.6,
            )),
      );
}

class _Surface extends StatelessWidget {
  const _Surface({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        decoration: BoxDecoration(
          color: AppColors.brandSurface2,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );
}

class _NavigationRow extends StatelessWidget {
  const _NavigationRow({
    super.key,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.number,
  });
  final String title;
  final String? subtitle;
  final String? number;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
              child: Row(
                children: [
                  if (number != null) ...[
                    Text(number!,
                        style: const TextStyle(
                            color: AppColors.ctaStart,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                height: 1.45)),
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(subtitle!,
                              style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12,
                                  height: 1.4)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right, color: Colors.white54),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
        ],
      );
}
