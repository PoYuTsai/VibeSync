import '../domain/night_market_scenario.dart';
import 'night_market_debrief.dart';

const _s1Captions = <NightMarketCaption>[
  NightMarketCaption(
    start: Duration(milliseconds: 3500),
    end: Duration(milliseconds: 5183),
    speaker: NightMarketSpeaker.coach,
    text: '等我一下，我看一下這個。',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 5231),
    end: Duration(milliseconds: 9048),
    speaker: NightMarketSpeaker.coach,
    text: '想認識她？',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 9096),
    end: Duration(milliseconds: 13230),
    speaker: NightMarketSpeaker.coach,
    text: '先吐口氣，三二一，走過去。',
  ),
];

const _s2Captions = <NightMarketCaption>[
  NightMarketCaption(
    start: Duration(milliseconds: 4868),
    end: Duration(milliseconds: 5186),
    speaker: NightMarketSpeaker.user,
    text: '嗨。',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 5230),
    end: Duration(milliseconds: 9337),
    speaker: NightMarketSpeaker.user,
    text: '剛剛看到妳，覺得妳這件米色外套蠻好看的，很適合妳。',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 10360),
    end: Duration(milliseconds: 11067),
    speaker: NightMarketSpeaker.npc,
    text: '喔，謝謝。',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 11150),
    end: Duration(milliseconds: 12012),
    speaker: NightMarketSpeaker.user,
    text: '有點突然。',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 12056),
    end: Duration(milliseconds: 20492),
    speaker: NightMarketSpeaker.user,
    text: '我跟朋友來買東西，剛在那邊等她。看到妳，想過來打個招呼。你好，我叫 Chris。',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 20721),
    end: Duration(milliseconds: 21882),
    speaker: NightMarketSpeaker.npc,
    text: '我叫 Leah。',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 22058),
    end: Duration(milliseconds: 22831),
    speaker: NightMarketSpeaker.user,
    text: 'Leah。',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 23171),
    end: Duration(milliseconds: 24634),
    speaker: NightMarketSpeaker.user,
    text: '妳今天自己來逛？',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 25130),
    end: Duration(milliseconds: 27711),
    speaker: NightMarketSpeaker.npc,
    text: '跟朋友，她還在那邊買吃的。',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 28007),
    end: Duration(milliseconds: 29952),
    speaker: NightMarketSpeaker.user,
    text: '那我們現在都在等人。',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 30594),
    end: Duration(milliseconds: 34976),
    speaker: NightMarketSpeaker.user,
    text: '妳看起來蠻會挑這種小東西的，應該不太喜歡跟大家買一樣的。',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 35187),
    end: Duration(milliseconds: 38706),
    speaker: NightMarketSpeaker.npc,
    text: '也沒有啦，我只是蠻喜歡逛手作的。',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 38991),
    end: Duration(milliseconds: 41496),
    speaker: NightMarketSpeaker.user,
    text: '妳是喜歡逛，還是自己也會做？',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 42322),
    end: Duration(milliseconds: 45301),
    speaker: NightMarketSpeaker.npc,
    text: '我有去上陶藝課，但做得不怎麼樣。',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 46235),
    end: Duration(milliseconds: 47668),
    speaker: NightMarketSpeaker.user,
    text: '妳還真的自己下去做。',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 48288),
    end: Duration(milliseconds: 51500),
    speaker: NightMarketSpeaker.npc,
    text: '朋友找我去的，後來覺得蠻好玩。',
  ),
];

const _s3Captions = <NightMarketCaption>[
  NightMarketCaption(
    start: Duration(milliseconds: 0),
    end: Duration(milliseconds: 4447),
    speaker: NightMarketSpeaker.user,
    text: '我之前也去過一次。原本只是陪朋友，結果最後是我不肯走。',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 5175),
    end: Duration(milliseconds: 5859),
    speaker: NightMarketSpeaker.npc,
    text: '為什麼？',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 6840),
    end: Duration(milliseconds: 15854),
    speaker: NightMarketSpeaker.user,
    text: '我那時候做一個杯子，杯口怎麼弄都弄不平。我平常很多事情都隨便，但自己想做好的東西，就會突然很龜毛。',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 16937),
    end: Duration(milliseconds: 20473),
    speaker: NightMarketSpeaker.npc,
    text: '我也是，我那個把手重做了三次。',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 20482),
    end: Duration(milliseconds: 22628),
    speaker: NightMarketSpeaker.user,
    text: '那妳有把它拿回家用嗎？',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 23245),
    end: Duration(milliseconds: 24641),
    speaker: NightMarketSpeaker.npc,
    text: '有啊，不然很浪費欸～',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 24686),
    end: Duration(milliseconds: 28881),
    speaker: NightMarketSpeaker.user,
    text: '我那個也還留著，但我朋友每次看到都要講一下。',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 29813),
    end: Duration(milliseconds: 30917),
    speaker: NightMarketSpeaker.npc,
    text: '到底是多醜？',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 31837),
    end: Duration(milliseconds: 32476),
    speaker: NightMarketSpeaker.user,
    text: '下次給妳看。',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 32521),
    end: Duration(milliseconds: 36983),
    speaker: NightMarketSpeaker.user,
    text: '不過妳那個把手願意重做三次，蠻有耐心的。',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 38210),
    end: Duration(milliseconds: 40124),
    speaker: NightMarketSpeaker.npc,
    text: '我就是不喜歡做一半。',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 40769),
    end: Duration(milliseconds: 41469),
    speaker: NightMarketSpeaker.user,
    text: '這點我蠻欣賞的。',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 41513),
    end: Duration(milliseconds: 45040),
    speaker: NightMarketSpeaker.user,
    text: '好，那妳先忙吧，我也回去找我朋友。',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 45366),
    end: Duration(milliseconds: 46175),
    speaker: NightMarketSpeaker.npc,
    text: '好啊。',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 46296),
    end: Duration(milliseconds: 48069),
    speaker: NightMarketSpeaker.user,
    text: '加個朋友吧，妳有 IG 嗎？',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 48116),
    end: Duration(milliseconds: 49937),
    speaker: NightMarketSpeaker.npc,
    text: '有啊，我掃你。',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 53487),
    end: Duration(milliseconds: 53684),
    speaker: NightMarketSpeaker.npc,
    text: '有了。',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 53729),
    end: Duration(milliseconds: 56411),
    speaker: NightMarketSpeaker.user,
    text: '改天有空，約個咖啡。',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 56799),
    end: Duration(milliseconds: 57605),
    speaker: NightMarketSpeaker.npc,
    text: '好啊。',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 57952),
    end: Duration(milliseconds: 58483),
    speaker: NightMarketSpeaker.user,
    text: '那先這樣，掰。',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 58530),
    end: Duration(milliseconds: 59576),
    speaker: NightMarketSpeaker.npc,
    text: '掰。',
  ),
  NightMarketCaption(
    start: Duration(milliseconds: 62520),
    end: Duration(milliseconds: 63357),
    speaker: NightMarketSpeaker.coach,
    text: '走吧。',
  ),
];

/// Builds the night-market story (v2 script, natural v3 media, 2026-09-09).
/// Caption timing follows docs/learning/night-market-research/natural-v3-conform.md.
///
/// Three bundled segments, two stop points. Every choice continues on the
/// main line; a non-main choice first shows a coach card. Copy source:
/// Opening 11「簡易搭訕流程詳解」, see docs/learning/night-market-research/.
NightMarketScenario buildNightMarketScenario() {
  return const NightMarketScenario(
    id: 'night_market_v2',
    title: '簡易搭訕流程詳解',
    subtitle: '夜市實戰版：從注意到她到收號，約 2 分鐘、2 個選擇',
    coverAsset: 'assets/images/night_market/cover.jpg',
    initialBeatId: 's1_notice',
    beats: <NightMarketBeat>[
      NightMarketBeat(
        id: 's1_notice',
        videoAsset: 'assets/videos/night_market/s1_notice.mp4',
        captions: _s1Captions,
        hint: '確信感｜決定要就走，決定不去就放下，不站著糾結。',
        choices: <NightMarketChoice>[
          NightMarketChoice(
            id: 'approach',
            label: '走到她看得到的側前方',
            nextId: 's2_opening_to_craft',
          ),
          NightMarketChoice(
            id: 'wait_for_her',
            label: '等她逛到我旁邊再說',
            nextId: 's2_opening_to_craft',
            coachCard: '等時機｜等時機就是猶豫，她不會走過來。要就現在走，不要就放下，兩個都比站著好。',
          ),
        ],
      ),
      NightMarketBeat(
        id: 's2_opening_to_craft',
        videoAsset: 'assets/videos/night_market/s2_opening_to_craft.mp4',
        captions: _s2Captions,
        hint: '提問是工具｜接她的話，再給她一小段你自己，不要連著問。',
        choices: <NightMarketChoice>[
          NightMarketChoice(
            id: 'extend',
            label: '「我之前也去過一次，結果最後是我不肯走。」',
            nextId: 's3_lifehook_to_end',
          ),
          NightMarketChoice(
            id: 'interrogate',
            label: '「妳平常在哪上班？住這附近嗎？」',
            nextId: 's3_lifehook_to_end',
            coachCard: '查戶口｜這樣她只會覺得被查戶口，對話會斷。接她的話，再給她一小段你自己。',
          ),
        ],
      ),
      NightMarketBeat(
        id: 's3_lifehook_to_end',
        videoAsset: 'assets/videos/night_market/s3_lifehook_to_end.mp4',
        captions: _s3Captions,
        ending: true,
      ),
    ],
    review: nightMarketReview,
    reviewChapters: nightMarketReviewChapters,
    takeaway: '下次只記這個：強眼神溝通。',
  );
}
