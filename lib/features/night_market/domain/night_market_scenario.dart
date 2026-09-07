/// Typed contract for the finite Night Market video scenario.
///
/// Concrete beats live in a separate data file so presentation code does not
/// bind itself to one script revision.
enum NightMarketSpeaker { npc, coach, user }

/// A timed caption; hidden by default, shown only when the player turns
/// captions on.
class NightMarketCaption {
  const NightMarketCaption({
    required this.start,
    required this.end,
    required this.speaker,
    required this.text,
  });

  final Duration start;
  final Duration end;
  final NightMarketSpeaker speaker;
  final String text;
}

/// A choice at a stop point. Every choice continues to [nextId]; a non-main
/// choice first shows [coachCard] (術語｜白話) before continuing.
class NightMarketChoice {
  const NightMarketChoice({
    required this.id,
    required this.label,
    required this.nextId,
    this.coachCard,
  });

  final String id;
  final String label;
  final String nextId;
  final String? coachCard;
}

/// One finite video segment. Playback stops at its last frame; [choices] then
/// appear, or the review page when [ending].
class NightMarketBeat {
  const NightMarketBeat({
    required this.id,
    required this.videoAsset,
    this.captions = const <NightMarketCaption>[],
    this.hint,
    this.choices = const <NightMarketChoice>[],
    this.ending = false,
  });

  final String id;
  final String videoAsset;
  final List<NightMarketCaption> captions;
  final String? hint;
  final List<NightMarketChoice> choices;
  final bool ending;
}

enum NightMarketReviewTier { mindset, key, more }

/// One review-page card: `term｜plain`. [met] false renders greyed as
/// 「這次沒遇到」; [optional] appends 「不是必要」.
class NightMarketReviewItem {
  const NightMarketReviewItem({
    required this.term,
    required this.plain,
    this.tier = NightMarketReviewTier.key,
    this.met = true,
    this.optional = false,
  });

  final String term;
  final String plain;
  final NightMarketReviewTier tier;
  final bool met;
  final bool optional;
}

/// Bundle-level scenario manifest. Asset paths must point to app-bundled files.
class NightMarketScenario {
  const NightMarketScenario({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.coverAsset,
    required this.initialBeatId,
    required this.beats,
    required this.review,
    required this.takeaway,
  });

  final String id;
  final String title;
  final String subtitle;
  final String coverAsset;
  final String initialBeatId;
  final List<NightMarketBeat> beats;
  final List<NightMarketReviewItem> review;
  final String takeaway;

  NightMarketBeat? beatById(String id) {
    for (final beat in beats) {
      if (beat.id == id) return beat;
    }
    return null;
  }
}
