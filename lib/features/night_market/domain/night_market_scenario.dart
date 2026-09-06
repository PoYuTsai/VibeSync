/// Typed contract for the finite Night Market video scenario.
///
/// Concrete beats live in a separate data file so presentation code does not
/// hard-code remote URLs or bind itself to one script revision.
enum NightMarketRunVariant {
  busy,
  available,
}

enum NightMarketSpeaker {
  npc,
  coach,
  user,
  vendor,
}

/// A timed caption rendered while [videoAsset] is playing.
class NightMarketCaption {
  const NightMarketCaption({
    required this.start,
    required this.end,
    required this.speaker,
    required this.text,
  }) : assert(end > start);

  final Duration start;
  final Duration end;
  final NightMarketSpeaker speaker;
  final String text;
}

/// One finite, non-interactive video beat. Choices become available only after
/// the player reports completion; [nextId] handles automatic continuation.
class NightMarketBeat {
  const NightMarketBeat({
    required this.id,
    required this.videoAsset,
    this.posterAsset,
    this.captions = const <NightMarketCaption>[],
    this.hint,
    this.choices = const <NightMarketChoice>[],
    this.nextId,
    this.ending = false,
    this.textOnly = false,
    this.voiceoverAsset,
    this.sfxAsset,
  });

  final String id;
  final String videoAsset;
  final String? posterAsset;
  final List<NightMarketCaption> captions;
  final String? hint;
  final List<NightMarketChoice> choices;
  final String? nextId;
  final bool ending;
  final bool textOnly;
  final String? voiceoverAsset;
  final String? sfxAsset;

  bool get waitsForChoice => choices.isNotEmpty;
}

/// A user choice that may play one spoken line before advancing to [nextId].
class NightMarketChoice {
  const NightMarketChoice({
    required this.id,
    required this.label,
    this.spokenText,
    this.audioAsset,
    required this.nextId,
    this.feedbackTag,
  });

  final String id;
  final String label;
  final String? spokenText;
  final String? audioAsset;
  final String nextId;
  final String? feedbackTag;
}

/// Bundle-level scenario manifest. Asset paths must point to app-bundled files.
class NightMarketScenario {
  const NightMarketScenario({
    required this.id,
    required this.initialBeatId,
    required this.beats,
    this.title = '台灣夜市練習',
  });

  final String id;
  final String title;
  final String initialBeatId;
  final List<NightMarketBeat> beats;

  NightMarketBeat? beatById(String id) {
    for (final beat in beats) {
      if (beat.id == id) return beat;
    }
    return null;
  }
}

/// Presentation state kept independent from Practice chat/session/quota state.
class NightMarketFlowState {
  const NightMarketFlowState({
    required this.beatId,
    this.variant = NightMarketRunVariant.available,
    this.videoCompleted = false,
    this.isPlaying = false,
    this.isMuted = false,
    this.hintVisible = true,
    this.selectedChoiceIds = const <String>[],
    this.keyRetry = 0,
  });

  final String beatId;
  final NightMarketRunVariant variant;
  final bool videoCompleted;
  final bool isPlaying;
  final bool isMuted;
  final bool hintVisible;
  final List<String> selectedChoiceIds;
  final int keyRetry;

  NightMarketFlowState copyWith({
    String? beatId,
    NightMarketRunVariant? variant,
    bool? videoCompleted,
    bool? isPlaying,
    bool? isMuted,
    bool? hintVisible,
    List<String>? selectedChoiceIds,
    int? keyRetry,
  }) {
    return NightMarketFlowState(
      beatId: beatId ?? this.beatId,
      variant: variant ?? this.variant,
      videoCompleted: videoCompleted ?? this.videoCompleted,
      isPlaying: isPlaying ?? this.isPlaying,
      isMuted: isMuted ?? this.isMuted,
      hintVisible: hintVisible ?? this.hintVisible,
      selectedChoiceIds: selectedChoiceIds ?? this.selectedChoiceIds,
      keyRetry: keyRetry ?? this.keyRetry,
    );
  }
}
