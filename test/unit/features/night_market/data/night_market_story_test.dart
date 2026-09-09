import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/night_market/data/night_market_story.dart';
import 'package:vibesync/features/night_market/domain/night_market_scenario.dart';

void main() {
  group('buildNightMarketScenario', () {
    final scenario = buildNightMarketScenario();

    test('graph is closed and every stop point leads to the main line', () {
      expect(scenario.beatById(scenario.initialBeatId), isNotNull);
      for (final beat in scenario.beats) {
        for (final choice in beat.choices) {
          expect(scenario.beatById(choice.nextId), isNotNull,
              reason: '${beat.id}/${choice.id} -> ${choice.nextId}');
        }
        // Every stop point has exactly one main-line choice and one coached one.
        if (!beat.ending) {
          expect(beat.choices.where((c) => c.coachCard == null), hasLength(1),
              reason: beat.id);
          expect(beat.choices.where((c) => c.coachCard != null), hasLength(1),
              reason: beat.id);
          expect(beat.hint, isNotNull, reason: beat.id);
        }
      }
      expect(scenario.beats.where((b) => b.ending), hasLength(1));
      expect(scenario.beats.where((b) => !b.ending), hasLength(2));
    });

    test('captions are ordered and inside each segment', () {
      // ffprobe durations of the bundled natural v3 media; see conform record.
      const durations = <String, Duration>{
        's1_notice': Duration(milliseconds: 13250),
        's2_opening_to_craft': Duration(microseconds: 52041667),
        's3_lifehook_to_end': Duration(milliseconds: 67875),
      };
      for (final beat in scenario.beats) {
        var last = Duration.zero;
        for (final caption in beat.captions) {
          expect(caption.end, greaterThan(caption.start), reason: beat.id);
          expect(caption.start, greaterThanOrEqualTo(last), reason: beat.id);
          expect(caption.end, lessThanOrEqualTo(durations[beat.id]!),
              reason: beat.id);
          last = caption.end;
        }
      }
    });

    test('review retains the terms and distinguishes demonstrated situations',
        () {
      final byTier = <NightMarketReviewTier, int>{};
      for (final item in scenario.review) {
        byTier.update(item.tier, (n) => n + 1, ifAbsent: () => 1);
      }
      expect(scenario.review, hasLength(27));
      expect(byTier[NightMarketReviewTier.mindset], 6);
      expect(scenario.review.first.term, '接近焦慮');
      expect(scenario.review.first.tier, NightMarketReviewTier.mindset);
      expect(byTier[NightMarketReviewTier.key], 6);
      expect(scenario.review.where((i) => !i.met).map((i) => i.term),
          ['忙碌收尾／即約', '廢物測試']);
      expect(scenario.takeaway, contains('強眼神溝通'));
    });

    test(
        'chapters partition the existing media and resolve every knowledge link',
        () {
      const durationUs = {
        's1_notice': 13250000,
        's2_opening_to_craft': 52041667,
        's3_lifehook_to_end': 67875000,
      };
      final ids = scenario.review.map((item) => item.id).toSet();
      expect(ids, hasLength(scenario.review.length));
      expect(scenario.reviewChapters, hasLength(6));
      final covered = <String>{};
      final lastEnd = <String, int>{};
      for (final chapter in scenario.reviewChapters) {
        for (final clip in chapter.clips) {
          expect(scenario.beatById(clip.beatId), isNotNull);
          expect(clip.start.inMicroseconds, lastEnd[clip.beatId] ?? 0);
          expect(clip.end, greaterThan(clip.start));
          expect(clip.end.inMicroseconds,
              lessThanOrEqualTo(durationUs[clip.beatId]!));
          lastEnd[clip.beatId] = clip.end.inMicroseconds;
        }
        for (final id in chapter.knowledgeIds) {
          expect(ids, contains(id));
          covered.add(id);
        }
        for (final explanation in chapter.explanations) {
          expect(chapter.knowledgeIds, contains(explanation.knowledgeId));
        }
      }
      expect(lastEnd, durationUs);
      // The unshown test has a full-index entry, rather than a fabricated scene.
      expect(ids.difference(covered), {'shit_test'});
      for (final item in scenario.review) {
        expect(item.practice, isNotEmpty, reason: item.id);
        expect(item.source, isNotEmpty, reason: item.id);
      }
    });
  });
}
