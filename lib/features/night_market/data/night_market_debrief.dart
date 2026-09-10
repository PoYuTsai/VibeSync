import '../domain/night_market_scenario.dart';

// Chris source audit and approved reading structure: 2026-09-10.
// Each entry is shared across chapters, mindset shortcuts and the full index.
const nightMarketReview = <NightMarketReviewItem>[
  NightMarketReviewItem(
    id: 'approach_anxiety',
    term: '接近焦慮',
    plain: '準備接近陌生人時，可能會擔心被拒絕、打擾她，或不知道下一句怎麼接。緊張也可以開始，不需要先逼自己變得毫不在意。',
    practice: '先吐口氣，把這次的目標縮成「有禮貌地打聲招呼」。結束後只回想一個卡點，下次就練那一件事。',
    source: '第 11 集 15:36–16:08；目前 Sydney 開場字幕。',
    tier: NightMarketReviewTier.mindset,
  ),
  NightMarketReviewItem(
    id: 'certainty',
    term: '確信感',
    plain: '你確定自己想認識她，也覺得主動打招呼是自然的事。這份態度要同時出現在眼神、聲音和動作裡。',
    practice: '先想清楚她哪個細節吸引了你，再說一句真實的開場。留意說話時，有沒有因為急著看她反應而把聲音縮回去。',
    source:
        '達人篇 01 02:40–04:35；達人篇 02 00:27–01:30、02:13–02:49；第 11 集 07:18–07:31、16:19–16:30。',
    tier: NightMarketReviewTier.mindset,
  ),
  NightMarketReviewItem(
    id: 'worthiness',
    term: '配得感',
    plain: '把自己放在平等的位置交流，不需要先得到她的認可，才覺得自己值得被認識。',
    practice: '把「我就是不行」換成一個具體描述，例如「她回答後，我急著換了話題」。描述得出行為，才找得到可以練的地方。',
    source: '第 11 集 15:51–16:08 僅能支持避免把技巧卡點一概歸為自我否定。',
    tier: NightMarketReviewTier.mindset,
    detail: '一次對話沒接上，可以回頭調整說話與回應的方式；不用把這個卡點擴大成對自己的全盤否定。',
  ),
  NightMarketReviewItem(
    id: 'self_amusement',
    term: '自娛自樂感',
    plain: '帶著自己也覺得有意思的心情去聊，享受分享本身。她有好反應當然開心，也不用每說一句就停下來等她認可。',
    practice: '挑一件自己說起來仍有感覺的小事，把好笑、意外或在意的細節說出來。她沒立刻笑，也可以把話自然說完。',
    source: '達人篇 05 00:43–01:25、01:35–02:22、03:15–04:25；第 11 集 16:24–16:30。',
    tier: NightMarketReviewTier.mindset,
  ),
  NightMarketReviewItem(
    id: 'flow',
    term: '流動感',
    plain: '把注意力放在眼前的人和話題，從她剛說的內容，自然聯想到下一句。',
    practice: '聽完一個回答，先接其中一個細節：說自己的聯想、補一段經驗，或再問深一點。一次接住一件事就好。',
    source:
        '達人篇 03 00:15–00:47、01:26–02:46、03:10–03:59；解惑篇 02 15:10–15:44；夜市陶藝對話。',
    tier: NightMarketReviewTier.mindset,
  ),
  NightMarketReviewItem(
    id: 'nonverbal_eye_contact',
    term: '潛溝通＋強眼神溝通',
    plain: '話語之外，眼神、尾音與身體姿態也在傳遞你的態度。強眼神溝通讓想認識她的意圖更清楚。',
    practice: '用同一句開場練三次，依序只注意站姿、尾音、眼神。熟悉後再合在一起，避免一開口就忙著檢查所有動作。',
    source: '第 11 集 07:13–07:31、07:58–08:06。',
    detail: '把重心放穩，身體可以微微後傾；說完一句，尾音落下來。眼神與語氣要傳達同一個意思，也要留意她回望時的狀態。',
    tier: NightMarketReviewTier.key,
  ),
  NightMarketReviewItem(
    id: 'empathy_background',
    term: '同理心陳述＋背景介紹',
    plain: '同理心陳述把她可能有的尷尬、意外或突然感說出來；背景介紹交代你為什麼出現、為什麼過來，解決陌生人之間的信任感問題。',
    practice: '用兩句短話練習：一句接她當下的感受，一句交代真實來意。說完就留空間讓她回應。',
    source:
        '第 11 集 03:38–04:20、07:32–07:49；解惑篇 01 01:21–01:50；達人篇 09 09:48–10:32。',
    tier: NightMarketReviewTier.key,
    detail: '感受只點到當下，不必替她下定論。背景交代到能理解來意就夠了；若一直解釋自己的身分和行程，對話反而很難開始。',
  ),
  NightMarketReviewItem(
    id: 'cold_read',
    term: '冷讀',
    plain: '根據眼前細節說出一個觀察或猜測，邀請她補充自己。猜測可以打開交流，猜錯也可能帶出新資訊。',
    practice: '用「妳看起來……」提出一個有根據的猜測。她修正時，接著聊她補充的內容，別忙著證明自己其實猜得很準。',
    source: '第 11 集 08:10–08:46；夜市 Leah 回覆「也沒有啦，我只是蠻喜歡逛手作的」。',
    tier: NightMarketReviewTier.key,
  ),
  NightMarketReviewItem(
    id: 'hook',
    term: '留白＋鉤子評估',
    plain: '故事說到讓人好奇的位置時，留一點接話空間。她是否追問，可以幫你評估她對這個話題的投入。',
    practice: '找一段有轉折的真實故事，先說到轉折。她問了就把內容接完；沒追問也能自然往下說，不必反覆吊著答案。',
    source: '第 11 集 04:33–05:57、12:59–13:07、13:32–13:58；夜市陶藝故事與 Leah 的「為什麼」。',
    tier: NightMarketReviewTier.key,
  ),
  NightMarketReviewItem(
    id: 'disinterest',
    term: '無興趣指標',
    plain: '你透過注意力和行動，傳出「我也有自己的安排」。這裡指你表現出的興趣變化，不是在判斷她喜不喜歡你。',
    practice: '聊到一個完整段落時，照原本的安排收尾。說完之後就接著行動，留意自己有沒有又急著補話、尋求她的認可。',
    source: '第 11 集 11:07–11:21、11:55–12:22；夜市先回去找朋友的台詞。',
    tier: NightMarketReviewTier.key,
  ),
  NightMarketReviewItem(
    id: 'contact',
    term: '加聯繫方式',
    plain: '把當下的交流延續到之後。前面聊出的共同點與欣賞，讓提出加聯繫方式有自然的理由。',
    practice: '從剛才的一個共同話題接到聯繫，延續原本的眼神與語氣。提出後先聽她怎麼回答，不必急著再解釋一輪。',
    source: '第 11 集 10:39–11:06、11:07–11:40、14:51–15:14；達人篇 09 12:23–13:22。',
    tier: NightMarketReviewTier.key,
  ),
  NightMarketReviewItem(
    id: 'first_minute',
    term: '第一分鐘破防',
    plain: '剛接觸時，先處理陌生感，讓她能自在地進入對話。這就是「第一分鐘破防」在關注的階段。',
    practice: '回想她從哪一句開始願意多說一點。下一次留意這個轉變，讓話題跟著往前走，不再反覆重講開場。',
    source: '解惑篇 01 01:21–01:50、05:02–05:14；解惑篇 07 00:28–00:40。',
    tier: NightMarketReviewTier.more,
    detail: '「第一分鐘」不是固定的六十秒門檻。她可能很快願意聊，也可能需要多一點時間；開始正面回應、分享自己後，就可以往下接。',
  ),
  NightMarketReviewItem(
    id: 'opening',
    term: '打開',
    plain: '先取得對方的注意，讓打招呼變成雙方都參與的對話。',
    practice: '從她看得到的方向靠近，選不擋人流的位置開口。等她注意到你、開始回應，再接著說來意。',
    source: '解惑篇 01 04:48–05:38；達人篇 09 09:13–09:33；第 11 集 01:14–03:15。',
    tier: NightMarketReviewTier.more,
  ),
  NightMarketReviewItem(
    id: 'opener',
    term: '開場白不重要',
    plain: '開場白的作用是開始交流。比起追求一句完美的話，更要知道對方回應後怎麼接下去。',
    practice: '用眼前的一個真實細節開口，再接想認識她的來意。練習把這兩句連起來，而不是只背第一句。',
    source: '第 11 集 01:14–03:15；夜市米色外套開場。',
    tier: NightMarketReviewTier.more,
  ),
  NightMarketReviewItem(
    id: 'gender_intent',
    term: '男女前提',
    plain: '讓她知道你對她有男女之間的興趣，想進一步認識她。後面的交流與邀約，才有清楚的來意。',
    practice: '說出真實吸引你的地方，再聽她怎麼接。隨著了解增加，也聊聊你欣賞她什麼個性，讓興趣有更具體的理由。',
    source: '達人篇 09 11:18–12:19、13:18–13:54；夜市外套與陶藝耐心段落。',
    tier: NightMarketReviewTier.more,
  ),
  NightMarketReviewItem(
    id: 'questions',
    term: '提問是工具',
    plain: '問題用來了解對方、找到可以繼續聊的內容。問完之後怎麼接，決定它會不會變成一段交流。',
    practice: '問完一題，先回應她的一個細節，再分享自己的相關經驗。練習把同一個話題聊深一點。',
    source: '第 11 集 08:20–08:36、09:17–10:01；達人篇 04 09:21–10:13、13:00–13:16。',
    tier: NightMarketReviewTier.more,
  ),
  NightMarketReviewItem(
    id: 'emotion',
    term: '觀察情緒',
    plain: '從笑容、眼神、語氣和接話方式，看她當下是自在、好奇，還是有些拘謹。',
    practice: '回看一段互動，先描述你看到的反應，再說自己的判斷。像「她開始主動追問」是觀察，「她被我吸引」則還需要更多線索。',
    source: '第 11 集 06:05–07:02、12:59–13:07、14:05–14:10；解惑篇 09 03:04–03:31。',
    tier: NightMarketReviewTier.more,
  ),
  NightMarketReviewItem(
    id: 'qualification',
    term: '賦格',
    plain: '根據她實際展現的特質，表達你真正在意、欣賞的地方。讓認同有理由，也讓她知道你怎麼看她。',
    practice: '先找出她做過的一件事，再說這讓你看見什麼特質。讓欣賞落在具體行為上，不只停在「很棒」「很厲害」。',
    source: '第 11 集 10:39–11:06、15:01–15:09；達人篇 09 12:23–13:22；夜市「這點我蠻欣賞的」。',
    tier: NightMarketReviewTier.more,
  ),
  NightMarketReviewItem(
    id: 'disqualification',
    term: '失格',
    plain: '在已有認同、有興趣的互動裡，適時收回一點認同或注意力，表達你也有自己的評估與節奏。',
    practice: '先看彼此是否已有認同與交流，再決定何時收回注意力。保留自己的安排，不必為了製造落差而硬加一句貶低。',
    source: '第 11 集 08:55–09:01、11:55–12:22；夜市欣賞後收回注意力。',
    tier: NightMarketReviewTier.more,
    detail: '失格可以透過話語，也可以透過行動呈現。要連同前面的認同一起看；只有冷淡或離開，並不能說明整段互動的進退。',
    optional: true,
  ),
  NightMarketReviewItem(
    id: 'push_pull',
    term: '推拉',
    plain: '一段互動中靠近與退開的起伏。表達欣賞是靠近，收回注意力是退開，前後放在一起才看得到推拉。',
    practice: '回想整段聊天在哪裡靠近、在哪裡退開。抓整體節奏就好，不用替每一句話安排一個相反動作。',
    source: '第 11 集 12:26–12:42、13:08–13:17；夜市賦格與離場段落。',
    tier: NightMarketReviewTier.more,
    optional: true,
  ),
  NightMarketReviewItem(
    id: 'busy_or_instant_date',
    term: '忙碌收尾／即約',
    plain: '依彼此接下來的安排決定怎麼延續互動：還有事就收尾、留聯繫；當下都有時間，也聊得下去，再考慮附近的小邀約。',
    practice: '先了解她接下來的安排，再提出符合當下時間的小邀約。要是各自還有事，就把這次好好收尾。',
    source: '達人篇 08 05:36–07:19；夜市結尾是「改天咖啡」，不是當下即約。',
    tier: NightMarketReviewTier.more,
    detail: '即約是把互動延續到當下的另一個活動；「改天有空喝咖啡」是在表達之後見面的意願，還沒有約好具體時間。',
    met: false,
  ),
  NightMarketReviewItem(
    id: 'control',
    term: '掌控感／控制力',
    plain: '主動發起互動，也願意處理其中的狀況。從站位、話題到收尾，知道接下來要做什麼，並自然帶出下一步。',
    practice: '回想一個讓聊天卡住的狀況，練習說出下一個具體動作：挪位置、接回話題，或把這段收尾。',
    source: '解惑篇 04 00:06–00:51、04:08–05:36；第 11 集 16:30–17:03。',
    tier: NightMarketReviewTier.mindset,
    detail: '例如站在店門口擋到人流，就先提議挪到旁邊；被打斷時先處理眼前的事，再接回對話。掌控局面也包括看見變化、跟著調整。',
    sceneNote: '從主動開口、延伸陶藝話題，到表達欣賞、收尾和加 IG，留意每一步是怎麼接到下一步的。',
  ),
  NightMarketReviewItem(
    id: 'sexual_hook',
    term: '性上鉤點',
    plain: '指互動從一般社交回應，出現男女吸引情緒的轉折。判斷時要看一組持續的反應。',
    practice: '觀察不同反應是否持續、相互呼應。只有一次微笑或追問時，先保留判斷，繼續交流。',
    source: '第 11 集 06:05–07:02、12:59–13:07、14:05–14:10、15:10–15:25。',
    tier: NightMarketReviewTier.more,
    detail: '留意沒有刻意逗她時的笑、主動想了解你的問題，以及持續停留的眼神。把反應前後連起來，才能區分禮貌應答、對話題好奇與被你吸引。',
    sceneNote: 'Leah 追問「為什麼」「到底是多醜」，表示她對你的故事有好奇。是否已經被你吸引，還要一起看她的眼神、情緒與後續回應。',
  ),
  NightMarketReviewItem(
    id: 'lifestyle_sample',
    term: '生活模式樣本',
    plain: '用一小段真實生活，讓她想像你的日常、興趣與身邊的人。',
    practice: '挑一件最近做過的事，說清楚和誰、在哪裡、哪個片刻最有意思。先分享一小段，看看她想接哪裡。',
    source: '第 11 集 04:33–05:22、09:17–10:01。',
    tier: NightMarketReviewTier.more,
    detail: '選一件說得出具體細節的小事，比羅列經歷更有畫面。朋友與活動自然出現在故事裡就夠了，不必靠誇大經歷來證明自己。',
    sceneNote: '從「陪朋友去陶藝課」到「自己不肯走」，幾句話就讓 Leah 看見了你生活的一小部分，也有了可以追問的地方。',
  ),
  NightMarketReviewItem(
    id: 'personality_sample',
    term: '個性樣本',
    plain: '分享自己怎麼看事情、在意什麼，讓她從故事中認識你的偏好與性格。',
    practice: '在一段經歷後，加上你當時的感受或選擇理由。讓她有機會接「我也會」或分享不同的看法。',
    source: '第 11 集 10:03–10:23；夜市杯口與龜毛台詞。',
    tier: NightMarketReviewTier.more,
    detail: '生活模式樣本描繪你在做什麼；個性樣本讓她看見你為什麼在意、怎麼做選擇。同一件事可以同時帶出這兩層。',
    sceneNote: '你說想做好的東西就會很龜毛，Leah 接著分享把手重做三次。你們從陶藝聊到了做事的態度，找到更具體的共同點。',
  ),
  NightMarketReviewItem(
    id: 'shit_test',
    term: '廢物測試',
    plain: '也叫一致性測試。面對質疑或調侃時，能否保持自己的狀態、把互動接下去，而不一直困在證明自己。',
    practice: '先分辨她是在打趣、認真問問題，還是想結束對話，再決定怎麼接。別因為認得這個名詞，就把每句不如預期的回答都當成測試。',
    source:
        '第 11 集 00:23–00:33；解惑篇 06 00:06–00:14、02:59–03:16、07:03–08:26；第 07 集 08:30–09:17；第 09 集 03:04–03:31。',
    tier: NightMarketReviewTier.more,
    detail: '可以簡答後繼續、略過調侃，或逆轉框架，順著她的話輕鬆接回互動。先看她的語氣與情緒；明確拒絕就照她表達的意思處理。',
    sceneNote: 'Leah 說「也沒有啦，我只是蠻喜歡逛手作的」，是在修正你的猜測。順著手作往下聊就好，不需要把這句話當成挑戰。',
    met: false,
  ),
  NightMarketReviewItem(
    id: 'handshake',
    term: '服從性測試（握手）',
    plain: '提出一個小互動，觀察她當下是否願意配合。握手是這次用來觀察回應的方式。',
    practice: '自然提出握手，觀察她怎麼接。她沒有回應時就收回手，照當下的反應決定繼續聊或道別。',
    source: '第 11 集 16:09–16:13。',
    tier: NightMarketReviewTier.more,
    detail: '回握只代表她願意參與當下這個動作。後面的互動仍要繼續看她的反應，不能從一次配合推定之後也都會接受。',
    sceneNote: '自我介紹後，你和 Leah 握了手。回看時可以留意她接這個動作的方式，再看對話怎麼繼續。',
  ),
];

const nightMarketReviewChapters = <NightMarketReviewChapter>[
  NightMarketReviewChapter(
    id: 'approach',
    title: '帶著確信，走過去',
    timeLabel: '00:00–00:24',
    clips: [
      NightMarketReviewClip(
          beatId: 's1_notice',
          start: Duration(microseconds: 0),
          end: Duration(microseconds: 13250000)),
      NightMarketReviewClip(
          beatId: 's2_opening_to_craft',
          start: Duration(microseconds: 0),
          end: Duration(microseconds: 11150000)),
    ],
    dialogue: ['Sydney：先吐口氣，三二一，走過去。', '你：覺得妳這件米色外套蠻好看的，很適合妳。'],
    explanations: [
      NightMarketReviewExplanation(
          knowledgeId: 'certainty',
          title: '確信感｜讓意圖和行動站在一起',
          text: '你注意到她，也有想認識她的理由。帶著這份確定去開口，眼神、聲音與姿態就能傳達同一個意思。',
          detail:
              'Sydney 的倒數停在行動之前。真的開口後，你的注意力已轉向 Leah；回看時可以留意，這個轉換有沒有讓眼神與聲音跟上想認識她的意圖。'),
      NightMarketReviewExplanation(
          knowledgeId: 'opening',
          title: '打開｜先取得注意，再進入對話',
          text: '從她看得到的方向打招呼。她開始回應了，就順著當下往下聊，讓開場成為對話的起點。',
          detail:
              '米色外套是雙方眼前都看得到的細節，她不需要先理解一長段背景就能回應。她說謝謝之後，這個開場已經完成任務，可以接著交代來意。'),
    ],
    practice: '下次先想清楚：她身上哪個細節讓你想認識？帶著這個念頭開口。',
    knowledgeIds: [
      'approach_anxiety',
      'certainty',
      'worthiness',
      'opening',
      'opener',
      'gender_intent',
      'nonverbal_eye_contact'
    ],
  ),
  NightMarketReviewChapter(
    id: 'trust',
    title: '接住感受，建立信任',
    timeLabel: '00:24–00:36',
    clips: [
      NightMarketReviewClip(
          beatId: 's2_opening_to_craft',
          start: Duration(microseconds: 11150000),
          end: Duration(microseconds: 23171000)),
    ],
    dialogue: ['你：有點突然。', '你：我跟朋友來買東西，剛在那邊等她。看到妳，想過來打個招呼。'],
    explanations: [
      NightMarketReviewExplanation(
          knowledgeId: 'empathy_background',
          title: '同理心陳述｜把她當下的感受說出來',
          text: '突然被陌生人打招呼，她可能有些意外、尷尬。一句「有點突然」，讓她知道你有感覺到她的處境。',
          detail: '「有點突然」說的是當下的情境，沒有替她下「妳很尷尬」的定論。說完接背景介紹，再把空間留給她回應。'),
      NightMarketReviewExplanation(
          knowledgeId: 'empathy_background',
          title: '背景介紹｜讓她知道你為什麼在這裡',
          text: '交代自己和朋友來逛、剛才在等人，讓你的出現有前因後果。她比較能理解你的來意，信任感才有地方開始。',
          detail:
              '「和朋友來買東西」「剛才在等她」補上你出現在附近的原因；「看到妳，想過來打招呼」再交代為什麼走過來。背景與來意一起說清楚，就能接自我介紹。'),
    ],
    practice: '留意她的反應，用一句話說出當下的感受，再簡單交代自己的背景。',
    knowledgeIds: [
      'empathy_background',
      'first_minute',
      'handshake',
      'nonverbal_eye_contact'
    ],
  ),
  NightMarketReviewChapter(
    id: 'interest',
    title: '從觀察，聊進她的興趣',
    timeLabel: '00:36–01:05',
    clips: [
      NightMarketReviewClip(
          beatId: 's2_opening_to_craft',
          start: Duration(microseconds: 23171000),
          end: Duration(microseconds: 52041667)),
    ],
    dialogue: ['你：妳看起來蠻會挑這種小東西的。', 'Leah：也沒有啦，我只是蠻喜歡逛手作的。'],
    explanations: [
      NightMarketReviewExplanation(
          knowledgeId: 'cold_read',
          title: '冷讀｜她的修正，也是認識她的線索',
          text: '你從她挑東西的樣子提出觀察。她把話題修正成手作，你就沿著她真正有興趣的方向繼續。',
          detail:
              'Leah 說「也沒有啦」之後，馬上補了「喜歡逛手作」。值得接的是她主動給的新資訊；若留在原本的猜測上爭對錯，反而會錯過手作這條話題。'),
      NightMarketReviewExplanation(
          knowledgeId: 'questions',
          title: '提問是工具｜問完之後，讓話題長下去',
          text: '「妳是喜歡逛，還是自己也會做？」讓手作延伸到陶藝，也替你分享自己的經驗留下位置。',
          detail: '「喜歡逛，還是自己也會做」沿著她剛提供的資訊往下問。她答陶藝後，你也有相關經驗能分享，因此不必再換一題蒐集資料。'),
    ],
    practice: '她說完一件事，先接那件事。讓一個問題帶出一段交流。',
    knowledgeIds: ['cold_read', 'questions', 'flow'],
  ),
  NightMarketReviewChapter(
    id: 'share',
    title: '分享生活，也露出個性',
    timeLabel: '01:05–01:38',
    clips: [
      NightMarketReviewClip(
          beatId: 's3_lifehook_to_end',
          start: Duration(microseconds: 0),
          end: Duration(microseconds: 32521000)),
    ],
    dialogue: ['你：原本只是陪朋友，結果最後是我不肯走。', 'Leah：為什麼？'],
    explanations: [
      NightMarketReviewExplanation(
          knowledgeId: 'hook',
          title: '留白＋鉤子評估｜留一點她想追問的空間',
          text: '先說到「最後反而是我不肯走」，她接著問為什麼。她想知道了，你再把杯子的故事接下去。',
          detail:
              '「陪朋友」和「自己不肯走」之間有個還沒說明的轉折。她問為什麼時，你再補上做杯子的經過，讓追問得到實際內容，而不是再丟一個謎題。'),
      NightMarketReviewExplanation(
          knowledgeId: 'personality_sample',
          title: '個性樣本｜故事裡，讓她看見你在意什麼',
          text: '從「想做好的東西就會很龜毛」，到她說把手重做三次，你們聊出了做事的態度和共同點。',
          detail:
              '她說把手重做三次，把共同點從「都做過陶藝」往前推了一步：你們都會在想做好時變得講究。這也替後面欣賞她的耐心留下了具體依據。'),
    ],
    practice: '分享一小段真實經驗，也說說你當時的感受或在意的事。',
    knowledgeIds: [
      'hook',
      'lifestyle_sample',
      'personality_sample',
      'self_amusement',
      'emotion',
      'sexual_hook'
    ],
  ),
  NightMarketReviewChapter(
    id: 'qualify',
    title: '有根據地欣賞，適時退開',
    timeLabel: '01:38–01:52',
    clips: [
      NightMarketReviewClip(
          beatId: 's3_lifehook_to_end',
          start: Duration(microseconds: 32521000),
          end: Duration(microseconds: 46296000)),
    ],
    dialogue: ['你：不過妳那個把手願意重做三次，蠻有耐心的。', '你：這點我蠻欣賞的。好，那妳先忙吧，我也回去找我朋友。'],
    explanations: [
      NightMarketReviewExplanation(
          knowledgeId: 'qualification',
          title: '賦格｜先看見，再說出欣賞',
          text: '她分享了重做把手的經歷，你因此欣賞她的耐心。這個肯定有根據，也讓繼續認識她有了理由。',
          detail: '開場注意的是外套，現在欣賞的已經是她聊出來的做事態度。這個轉變讓 Leah 知道，你在交流過程中真的多認識了她一點。'),
      NightMarketReviewExplanation(
          knowledgeId: 'disqualification',
          title: '失格／無興趣指標｜在有興趣的互動裡，退開一點',
          text: '說完欣賞，再回去找自己的朋友。前面的認同與後面的退開，讓這段互動有進有退。',
          detail:
              '「妳先忙，我回去找朋友」接在欣賞之後，語氣與行動才形成前後的變化。這裡看的是收回注意力，不需要再另外加一句否定她的話。'),
    ],
    practice: '留意自己究竟欣賞她哪一點，再把那個理由說清楚。',
    knowledgeIds: [
      'qualification',
      'disqualification',
      'push_pull',
      'disinterest',
      'control'
    ],
  ),
  NightMarketReviewChapter(
    id: 'close',
    title: '留下聯繫，也留下下一次',
    timeLabel: '01:52–02:13',
    clips: [
      NightMarketReviewClip(
          beatId: 's3_lifehook_to_end',
          start: Duration(microseconds: 46296000),
          end: Duration(microseconds: 67875000)),
    ],
    dialogue: ['你：加個朋友吧，妳有 IG 嗎？', '你：改天有空，約個咖啡。'],
    explanations: [
      NightMarketReviewExplanation(
          knowledgeId: 'contact',
          title: '加聯繫方式｜讓下一步接在這段互動後面',
          text: '你們已經有共同話題，也表達了欣賞。這時提出加 IG，延續原本的眼神與語氣，把聯繫接起來。',
          detail: '加 IG 前，你們已經聊過共同興趣，也說清楚欣賞的理由。提出聯繫時延續同一段對話，拿出手機之後也留時間讓她回應。'),
      NightMarketReviewExplanation(
          knowledgeId: 'control',
          title: '掌控感／控制力｜把互動的下一步帶出來',
          text: '何時收尾、何時提聯繫，都由你自然往前帶。這次是改天咖啡；當下即約，是另一種時間安排。',
          detail:
              '「改天咖啡」替之後見面留下方向，Sydney 的「走吧」則把當下這次互動收住。這裡還沒有確定下次的時間與地點，可以等之後聯繫再談。'),
    ],
    practice: '收尾前想一想：你們剛才聊出的共同點，可以怎麼接到下一次見面？',
    knowledgeIds: ['contact', 'busy_or_instant_date', 'control'],
  ),
];
