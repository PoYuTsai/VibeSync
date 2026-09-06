import '../domain/night_market_scenario.dart';

const _videoRoot = 'assets/videos/night_market';
const _voiceRoot = 'assets/audio/night_market';
const _sfxRoot = 'assets/audio/night_market';

String _video(String id) => '$_videoRoot/$id.mp4';
String _voice(String id) => '$_voiceRoot/$id.mp3';
String _sfx(String id) => '$_sfxRoot/$id.wav';

NightMarketCaption _caption(
  NightMarketSpeaker speaker,
  String text,
  num endSeconds, {
  num startSeconds = 0,
}) {
  return NightMarketCaption(
    start: Duration(milliseconds: (startSeconds * 1000).round()),
    end: Duration(milliseconds: (endSeconds * 1000).round()),
    speaker: speaker,
    text: text,
  );
}

NightMarketChoice _choice({
  required String id,
  required String label,
  required String spokenText,
  required String nextId,
  required String feedbackTag,
}) {
  return NightMarketChoice(
    id: id,
    label: label,
    spokenText: spokenText,
    audioAsset: spokenText.trim().isEmpty ? null : _voice(id),
    nextId: nextId,
    feedbackTag: feedbackTag,
  );
}

/// Builds the finite, asset-backed night-market story.
///
/// The run variant is chosen by the caller before playback. It controls the
/// time situation after the tea is called; it is never inferred from a user
/// choice or from a perceived NPC reaction.
NightMarketScenario buildNightMarketScenario({
  NightMarketRunVariant variant = NightMarketRunVariant.available,
}) {
  final postCallId =
      variant == NightMarketRunVariant.available ? 'available' : 'busy';

  return NightMarketScenario(
    id: 'night_market_v1',
    initialBeatId: 'establish',
    beats: <NightMarketBeat>[
      NightMarketBeat(
        id: 'establish',
        videoAsset: _video('establish'),
        posterAsset: 'assets/images/night_market/sydney.jpg',
        captions: <NightMarketCaption>[
          _caption(NightMarketSpeaker.coach, '你剛剛不是說只吃一攤？', 2),
          _caption(NightMarketSpeaker.coach, '好啦，先逛一圈。', 5, startSeconds: 2),
          _caption(NightMarketSpeaker.coach, '前面有一家手作攤。', 8, startSeconds: 5),
        ],
        nextId: 'hesitate',
      ),
      NightMarketBeat(
        id: 'hesitate',
        videoAsset: _video('hesitate'),
        posterAsset: 'assets/images/night_market/sydney.jpg',
        hint: 'Sydney｜先吐口氣。穩穩走到她看得到的位置，不用急著想下一句。',
        sfxAsset: _sfx('hesitate-heartbeat'),
        captions: <NightMarketCaption>[
          _caption(NightMarketSpeaker.coach, '有想認識她？先吐口氣。', 6.38,
              startSeconds: 3.76),
          _caption(NightMarketSpeaker.coach, '三、二、一。', 8.24,
              startSeconds: 6.38),
          _caption(NightMarketSpeaker.coach, '從她看得到的地方過去，', 10,
              startSeconds: 8.24),
          _caption(NightMarketSpeaker.coach, '我在這裡。', 10.92, startSeconds: 10),
        ],
        choices: <NightMarketChoice>[
          _choice(
            id: 'approach',
            label: '走到她看得到的側前方',
            spokenText: '',
            nextId: 'opening',
            feedbackTag: 'clear_approach',
          ),
          _choice(
            id: 'keepwalking',
            label: '先繼續逛夜市',
            spokenText: '',
            nextId: 'pause_ending',
            feedbackTag: 'respectful_pause',
          ),
        ],
      ),
      NightMarketBeat(
        id: 'opening',
        videoAsset: _video('opening'),
        posterAsset: 'assets/images/night_market/leah.jpg',
        hint: 'Sydney｜她已經聽見了。簡短介紹自己，留一點空間讓她接。',
        captions: <NightMarketCaption>[
          _caption(NightMarketSpeaker.user, '妳這件米色外套搭得很好看，', 7.28,
              startSeconds: 4.86),
          _caption(NightMarketSpeaker.user, '剛剛經過就注意到了。', 8.88,
              startSeconds: 7.28),
          _caption(NightMarketSpeaker.user, '我想來跟妳打個招呼。', 11.64,
              startSeconds: 8.88),
          _caption(NightMarketSpeaker.npc, '嗨。', 13.8, startSeconds: 13.22),
        ],
        choices: <NightMarketChoice>[
          _choice(
            id: 'introduce',
            label: '我叫阿澤，剛下班來逛逛。',
            spokenText: '我叫阿澤，剛下班來逛逛。',
            nextId: 'concern',
            feedbackTag: 'clear_introduction',
          ),
          _choice(
            id: 'pressure_wait',
            label: '等一下，妳先不要走。',
            spokenText: '等一下，妳先不要走。',
            nextId: 'decline',
            feedbackTag: 'pressure_repair',
          ),
        ],
      ),
      NightMarketBeat(
        id: 'concern',
        videoAsset: _video('concern'),
        posterAsset: 'assets/images/night_market/leah.jpg',
        hint: 'Sydney｜這是來意的疑慮。先回答她，不必急著證明自己。',
        captions: <NightMarketCaption>[
          _caption(NightMarketSpeaker.npc, '你不是在賣東西吧？', 5.68,
              startSeconds: 2.52),
          _caption(NightMarketSpeaker.npc, '剛剛好多人在發傳單。', 7.72,
              startSeconds: 5.68),
        ],
        choices: <NightMarketChoice>[
          _choice(
            id: 'answer_intent',
            label: '不是，我沒有東西要賣；就是想跟妳聊兩句。',
            spokenText: '不是，我沒有東西要賣；就是想跟妳聊兩句。',
            nextId: 'work',
            feedbackTag: 'meaningful_callback',
          ),
          _choice(
            id: 'challenge_sales',
            label: '妳看我像推銷員嗎？',
            spokenText: '妳看我像推銷員嗎？',
            nextId: 'decline',
            feedbackTag: 'defensive_reply',
          ),
        ],
      ),
      NightMarketBeat(
        id: 'work',
        videoAsset: _video('work'),
        posterAsset: 'assets/images/night_market/leah.jpg',
        hint: 'Sydney｜她在問你。給她一小段真實的自己，再把話題交回去。',
        captions: <NightMarketCaption>[
          _caption(NightMarketSpeaker.npc, '喔，原來是這樣。', 3.88,
              startSeconds: 2.14),
          _caption(NightMarketSpeaker.npc, '我叫 Leah。你是做什麼的？', 6.44,
              startSeconds: 4.42),
        ],
        choices: <NightMarketChoice>[
          _choice(
            id: 'share_product_design',
            label: '我做產品設計，把亂的東西整理成好用的流程。妳呢？',
            spokenText: '我做產品設計，把亂的東西整理成好用的流程。妳呢？',
            nextId: 'craft',
            feedbackTag: 'meaningful_callback',
          ),
          _choice(
            id: 'ask_demographics',
            label: '就上班啊。妳幾歲？',
            spokenText: '就上班啊。妳幾歲？',
            nextId: 'decline',
            feedbackTag: 'missed_question',
          ),
        ],
      ),
      NightMarketBeat(
        id: 'craft',
        videoAsset: _video('craft'),
        posterAsset: 'assets/images/night_market/leah.jpg',
        captions: <NightMarketCaption>[
          _caption(NightMarketSpeaker.npc, '我做職能治療。下班有時去做陶杯。', 5.34,
              startSeconds: 0.94),
          _caption(NightMarketSpeaker.user, '我第一次拉坯，杯子歪得很有個性。', 9.4,
              startSeconds: 6.2),
          _caption(NightMarketSpeaker.npc, '那是杯子還是花盆？', 12, startSeconds: 10.5),
          _caption(NightMarketSpeaker.user, '介於兩者，老師說很有個人風格。', 16.2,
              startSeconds: 13.32),
        ],
        choices: <NightMarketChoice>[
          _choice(
            id: 'share_pen_holder',
            label: '現在拿來放筆了，放在桌上剛剛好。',
            spokenText: '現在拿來放筆了，放在桌上剛剛好。',
            nextId: 'tease',
            feedbackTag: 'meaningful_callback',
          ),
          _choice(
            id: 'share_pen_holder_light',
            label: '老師人很好，至少我做出了一個筆筒。',
            spokenText: '老師人很好，至少我做出了一個筆筒。',
            nextId: 'tease',
            feedbackTag: 'shared_humor',
          ),
        ],
      ),
      NightMarketBeat(
        id: 'tease',
        videoAsset: _video('tease'),
        posterAsset: 'assets/images/night_market/leah.jpg',
        hint: 'Sydney｜她笑著接了杯子的梗。用你自在的方式回答，不用反擊。',
        captions: <NightMarketCaption>[
          _caption(NightMarketSpeaker.npc, '至少還用得上。', 4.84, startSeconds: 2.86),
          _caption(NightMarketSpeaker.npc, '你很常這樣跟女生打招呼嗎？', 8.22,
              startSeconds: 5.58),
        ],
        choices: <NightMarketChoice>[
          _choice(
            id: 'first_today',
            label: '今天第一個。',
            spokenText: '今天第一個。',
            nextId: 'call',
            feedbackTag: 'consistent_humor',
          ),
          _choice(
            id: 'hungry_vendor',
            label: '我比較常跟老闆搭話，因為我肚子餓。',
            spokenText: '我比較常跟老闆搭話，因為我肚子餓。',
            nextId: 'call',
            feedbackTag: 'shared_humor',
          ),
        ],
      ),
      NightMarketBeat(
        id: 'call',
        videoAsset: _video('call'),
        posterAsset: 'assets/images/night_market/leah.jpg',
        captions: <NightMarketCaption>[
          _caption(NightMarketSpeaker.npc, '至少你有先說來意。', 2.14),
          _caption(NightMarketSpeaker.vendor, '十七號，無糖烏龍！', 5,
              startSeconds: 2.92),
          _caption(NightMarketSpeaker.npc, '我的茶好了，等我一下。', 7.44,
              startSeconds: 5.52),
        ],
        nextId: postCallId,
      ),
      NightMarketBeat(
        id: 'available',
        videoAsset: _video('available'),
        posterAsset: 'assets/images/night_market/leah-cup.jpg',
        hint: 'Sydney｜她說還有時間，也接續了話題。邀請可以具體、小一點。',
        captions: <NightMarketCaption>[
          _caption(NightMarketSpeaker.npc, '我朋友還要二十分鐘才來，', 6.48,
              startSeconds: 4.44),
          _caption(NightMarketSpeaker.npc, '還能逛一下。', 7.76, startSeconds: 6.48),
          _caption(NightMarketSpeaker.npc, '旁邊那家是在賣陶杯嗎？', 9.94,
              startSeconds: 7.76),
        ],
        choices: <NightMarketChoice>[
          _choice(
            id: 'invite_craft_stall',
            label: '要不要去旁邊逛兩分鐘手作攤？',
            spokenText: '要不要去旁邊逛兩分鐘手作攤？',
            nextId: 'date',
            feedbackTag: 'meaningful_callback',
          ),
          _choice(
            id: 'leave_available',
            label: '那我們先各自逛，今晚玩得開心。',
            spokenText: '那我們先各自逛，今晚玩得開心。',
            nextId: 'decline',
            feedbackTag: 'respectful_exit',
          ),
        ],
      ),
      NightMarketBeat(
        id: 'date',
        videoAsset: _video('date'),
        posterAsset: 'assets/images/night_market/leah-cup.jpg',
        captions: <NightMarketCaption>[
          _caption(NightMarketSpeaker.npc, '好啊，去看一下。', 7.8, startSeconds: 6.4),
          _caption(NightMarketSpeaker.user, '這杯子比我的直很多。', 10.4,
              startSeconds: 8.22),
          _caption(NightMarketSpeaker.npc, '拉坯要慢一點，急了就會歪。', 13.56,
              startSeconds: 10.4),
          _caption(NightMarketSpeaker.user, '那今天先欣賞就好。', 15.2,
              startSeconds: 13.56),
          _caption(NightMarketSpeaker.npc, '先不要把它碰倒。', 16.6,
              startSeconds: 15.2),
        ],
        nextId: 'decline',
      ),
      NightMarketBeat(
        id: 'busy',
        videoAsset: _video('busy'),
        posterAsset: 'assets/images/night_market/leah-cup.jpg',
        hint: 'Sydney｜她有在接話，但朋友在等。先尊重時間，再決定怎麼收尾。',
        captions: <NightMarketCaption>[
          _caption(NightMarketSpeaker.npc, '朋友在前面等我了。', 5, startSeconds: 2.86),
          _caption(NightMarketSpeaker.npc, '不過剛剛那個杯子的故事蠻好笑的。', 7.74,
              startSeconds: 5),
        ],
        choices: <NightMarketChoice>[
          _choice(
            id: 'offer_contact',
            label: '妳願意的話我留我的，改天喝無糖烏龍；不用現在回。',
            spokenText: '妳願意的話我留我的，改天喝無糖烏龍；不用現在回。',
            nextId: 'contact',
            feedbackTag: 'meaningful_callback',
          ),
          _choice(
            id: 'respect_busy_bye',
            label: '了解，祝妳今晚逛得開心，再見。',
            spokenText: '了解，祝妳今晚逛得開心，再見。',
            nextId: 'decline',
            feedbackTag: 'respectful_exit',
          ),
        ],
      ),
      NightMarketBeat(
        id: 'contact',
        videoAsset: _video('contact'),
        posterAsset: 'assets/images/night_market/leah-cup.jpg',
        captions: <NightMarketCaption>[
          _caption(NightMarketSpeaker.npc, '好啊，我掃你。', 2.2, startSeconds: 0.66),
          _caption(NightMarketSpeaker.npc, '下次可以看看那個很有個性的杯子。', 5.2,
              startSeconds: 2.76),
          _caption(NightMarketSpeaker.npc, '我要先走了，掰掰。', 7.48,
              startSeconds: 6.06),
        ],
        nextId: 'coach',
      ),
      NightMarketBeat(
        id: 'decline',
        videoAsset: _video('decline'),
        posterAsset: 'assets/images/night_market/leah-close.jpg',
        captions: <NightMarketCaption>[
          _caption(NightMarketSpeaker.npc, '謝謝，我先走了。', 2.36),
          _caption(NightMarketSpeaker.npc, '祝你們逛得開心。', 4.22,
              startSeconds: 2.36),
        ],
        nextId: 'coach',
      ),
      NightMarketBeat(
        id: 'coach',
        videoAsset: _video('coach'),
        posterAsset: 'assets/images/night_market/sydney.jpg',
        sfxAsset: _sfx('ui-cue'),
        captions: <NightMarketCaption>[
          _caption(NightMarketSpeaker.coach, '剛剛哪一句，讓你最想急著解釋？', 4.04,
              startSeconds: 0.82),
          _caption(NightMarketSpeaker.coach, '先接住對方說的，再選你真的想說的。', 9.32,
              startSeconds: 5.28),
          _caption(NightMarketSpeaker.coach, '這個比背台詞重要。', 11.4,
              startSeconds: 9.8),
        ],
        ending: true,
        choices: <NightMarketChoice>[
          _choice(
            id: 'retry_earliest',
            label: '再練一次開場',
            spokenText: '',
            nextId: 'opening',
            feedbackTag: 'keypoint_retry',
          ),
          _choice(
            id: 'retry_callback',
            label: '再練一次話題延伸',
            spokenText: '',
            nextId: 'craft',
            feedbackTag: 'keypoint_retry',
          ),
        ],
      ),
      const NightMarketBeat(
        id: 'pause_ending',
        videoAsset: 'assets/videos/night_market/coach.mp4',
        textOnly: true,
        ending: true,
      ),
    ],
  );
}
