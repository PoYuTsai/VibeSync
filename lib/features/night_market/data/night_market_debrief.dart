import '../domain/night_market_scenario.dart';

// Chris source audit and approved reading structure: 2026-09-10.
// Each entry is shared across chapters, mindset shortcuts and the full index.
const nightMarketReview = <NightMarketReviewItem>[
  NightMarketReviewItem(
    id: 'approach_anxiety',
    term: '接近焦慮',
    plain:
        '緊張也可以開始。先吐口氣，把目標縮成「有禮貌地打聲招呼」，不用先想收號。看她是否願意停下來聊；她忙或不想聊就道別。不去也可以，不必責怪自己。 這次可以回想：你是卡在走過去、第一句，還是她回應之後不知道怎麼接？把卡點找出來，下次就有一件具體的事可以練。',
    practice: '先回想自己卡在哪裡：走過去、第一句，還是她回應之後？下次只挑其中一件事練。',
    source: '第 11 集 15:36–16:08；目前 Sydney 開場字幕。',
    tier: NightMarketReviewTier.mindset,
  ),
  NightMarketReviewItem(
    id: 'certainty',
    term: '確信感',
    plain:
        '你是真的想認識她，也相信走過去打聲招呼是一件自然的事。心裡有這份確定，開口、眼神和動作就能放在一起，不會一邊說想認識，一邊又急著退回去。',
    practice: '開口前想一想，你是被她哪個細節吸引？帶著這個真實的理由去打招呼。',
    source:
        '達人篇 01 02:40–04:35；達人篇 02 00:27–01:30、02:13–02:49；第 11 集 07:18–07:31、16:19–16:30。',
    tier: NightMarketReviewTier.mindset,
  ),
  NightMarketReviewItem(
    id: 'worthiness',
    term: '配得感',
    plain: '不用證明自己配得上，也不用反覆解釋。',
    practice: '復盤時回到具體行為：哪一句沒接上、哪一刻退縮了？把它當成能練習的細節。',
    source: '第 11 集 15:51–16:08 僅能支持避免把技巧卡點一概歸為自我否定。',
    tier: NightMarketReviewTier.mindset,
    detail: '這是原有復盤的提醒。第 11 集沒有單獨定義配得感；其中可對照的是，不要把技巧上的卡點一概歸成「她不喜歡我」。',
  ),
  NightMarketReviewItem(
    id: 'self_amusement',
    term: '自娛自樂感',
    plain:
        '帶著自己也覺得有意思的心情去聊。像說起做歪的杯子，你自己也能覺得好笑、享受這段分享，不必等她先笑，才覺得自己表現得好。沒有特別的笑點，也可以自在地聊。',
    practice: '挑一段自己說起來也有感覺的小事。先享受分享，再留意她怎麼接，不必一直等她給好反應。',
    source: '達人篇 05 00:43–01:25、01:35–02:22、03:15–04:25；第 11 集 16:24–16:30。',
    tier: NightMarketReviewTier.mindset,
  ),
  NightMarketReviewItem(
    id: 'flow',
    term: '流動感',
    plain:
        '把注意力放回她和眼前的話題。她聊陶藝，你想到自己做杯子的糗事；她說把手重做三次，你再聊那份耐心。像平常聊天一樣，讓一句話自然帶出下一句。',
    practice: '聽她剛說了什麼，再接一個真實聯想。像從陶藝接到自己的杯子，不必急著找全新的題目。',
    source:
        '達人篇 03 00:15–00:47、01:26–02:46、03:10–03:59；解惑篇 02 15:10–15:44；夜市陶藝對話。',
    tier: NightMarketReviewTier.mindset,
  ),
  NightMarketReviewItem(
    id: 'nonverbal_eye_contact',
    term: '潛溝通＋強眼神溝通',
    plain: '先把自己放穩：身體微微後傾，重心向下，說完一句，尾音落下來。和她保持強眼神溝通，讓眼神、聲音和姿態一起傳達你的確信感。',
    practice: '回看片段時，分別留意站姿、尾音與眼神，再把這三件事放回同一句話裡練。',
    source: '第 11 集 07:13–07:31、07:58–08:06。',
    tier: NightMarketReviewTier.key,
  ),
  NightMarketReviewItem(
    id: 'empathy_background',
    term: '同理心陳述＋背景介紹',
    plain:
        '「有點突然。」先把她可能有的尷尬、意外說出來。再說「我跟朋友來買東西，剛在那邊等她」，讓她知道你為什麼會出現在這裡。前一句接住感受，後一句交代背景、建立信任感。',
    practice: '留意她的反應，用一句話說出當下的感受，再簡單交代自己為什麼在這裡、為什麼過來。',
    source:
        '第 11 集 03:38–04:20、07:32–07:49；解惑篇 01 01:21–01:50；達人篇 09 09:48–10:32。',
    tier: NightMarketReviewTier.key,
    detail: '同理心陳述處理她的尷尬、意外或突然感；背景介紹則讓陌生人的出現有來由，解決信任感問題。兩者各有作用，說完之後就接著聊。',
  ),
  NightMarketReviewItem(
    id: 'cold_read',
    term: '冷讀',
    plain:
        '從眼前的細節說一個觀察或猜測，給她接話的空間。她把「不喜歡跟大家買一樣的」修正成「喜歡逛手作」，你就沿著手作往下聊，讓猜測變成認識她的起點。',
    practice: '她修正你的猜測時，先接住她補充的資訊。你想認識的是她，不是證明自己猜得準。',
    source: '第 11 集 08:10–08:46；夜市 Leah 回覆「也沒有啦，我只是蠻喜歡逛手作的」。',
    tier: NightMarketReviewTier.key,
  ),
  NightMarketReviewItem(
    id: 'hook',
    term: '留白＋鉤子評估',
    plain:
        '「原本只是陪朋友，結果最後是我不肯走。」說到這裡，留一點空間，看看她會不會問「為什麼」。她追問了，就把故事接下去；有留白，也有實在的分享，才有東西讓她繼續認識你。',
    practice: '留到她可以接話的地方。她追問就把故事接完；沒有追問，也能自然分享，不必一直吊著答案。',
    source: '第 11 集 04:33–05:57、12:59–13:07、13:32–13:58；夜市陶藝故事與 Leah 的「為什麼」。',
    tier: NightMarketReviewTier.key,
  ),
  NightMarketReviewItem(
    id: 'disinterest',
    term: '無興趣指標',
    plain: '聊得正好時，你先說「那妳先忙吧，我也回去找朋友」，把注意力收回自己的行程。前面表達興趣，這裡退開一下，讓她感覺你也有自己的節奏。',
    practice: '知道自己接下來要做什麼，聊到一個完整段落就可以收尾。這裡看的是你傳出的注意力變化。',
    source: '第 11 集 11:07–11:21、11:55–12:22；夜市先回去找朋友的台詞。',
    tier: NightMarketReviewTier.key,
  ),
  NightMarketReviewItem(
    id: 'contact',
    term: '收號',
    plain:
        '前面已聊出彼此的興趣，也說了欣賞她哪一點，這時再提「加個朋友吧，妳有 IG 嗎？」就有來由。延續原本的眼神和語氣，把聯繫當成這段互動的下一步。',
    practice: '從共同話題或欣賞她的理由接到聯繫。提出來後，留空間聽她怎麼回答。',
    source: '第 11 集 10:39–11:06、11:07–11:40、14:51–15:14；達人篇 09 12:23–13:22。',
    tier: NightMarketReviewTier.key,
  ),
  NightMarketReviewItem(
    id: 'first_minute',
    term: '第一分鐘破防',
    plain:
        '前六十秒先讓她放下戒心，之後才談吸引。 剛認識時，先透過同理心陳述和背景介紹處理陌生感，讓她比較自在地進入對話。她開始回應了，就接著聊，不必反覆重講開場。',
    practice: '她開始正面回應、願意聊自己，就往下接。看她的反應，不必計時或反覆重說來意。',
    source: '解惑篇 01 01:21–01:50、05:02–05:14；解惑篇 07 00:28–00:40。',
    tier: NightMarketReviewTier.more,
    detail: '「第一分鐘」說的是剛接觸時的陌生感。Chris 也說打開可能只要幾秒，也可能一分鐘；不用把六十秒當成固定門檻。',
  ),
  NightMarketReviewItem(
    id: 'opening',
    term: '打開',
    plain: '先讓她看見你、注意到你，再展開對話。她開始正面回應、提供自己的資訊，就往下聊，不用反覆重講開場白。',
    practice: '從她看得到的方向打招呼，留意站位與人流。取得注意之後，接著進入你們的對話。',
    source: '解惑篇 01 04:48–05:38；達人篇 09 09:13–09:33；第 11 集 01:14–03:15。',
    tier: NightMarketReviewTier.more,
  ),
  NightMarketReviewItem(
    id: 'opener',
    term: '開場白不重要',
    plain: '開場先替你打開對話。你這次從米色外套切入，接著就讓她知道你想認識她，把話題帶到你們兩個身上。',
    practice: '用眼前真實的細節開口，再交代想認識她的意思。重點是開場之後能接著聊。',
    source: '第 11 集 01:14–03:15；夜市米色外套開場。',
    tier: NightMarketReviewTier.more,
  ),
  NightMarketReviewItem(
    id: 'gender_intent',
    term: '男女前提',
    plain: '從外套切入之後，也讓她知道你是被她吸引、想認識她。後面的分享與邀約，就有男女之間的意思；再慢慢聊到你欣賞她什麼樣的個性。',
    practice: '讓想認識她的意圖清楚地傳出去，再透過交流看看彼此有哪些共同點。',
    source: '達人篇 09 11:18–12:19、13:18–13:54；夜市外套與陶藝耐心段落。',
    tier: NightMarketReviewTier.more,
  ),
  NightMarketReviewItem(
    id: 'questions',
    term: '提問是工具',
    plain: '你是真的想知道她喜歡什麼，問完也接著說自己的經驗。像從「會不會自己做手作」，聊到你們各自的陶藝故事，問題就把話題打開了。',
    practice: '問完先聽，再接她的回答、分享自己的經驗，讓問題帶出一段交流。',
    source: '第 11 集 08:20–08:36、09:17–10:01；達人篇 04 09:21–10:13、13:00–13:16。',
    tier: NightMarketReviewTier.more,
  ),
  NightMarketReviewItem(
    id: 'emotion',
    term: '觀察情緒',
    plain: '看她的反應裡有什麼情緒：是禮貌笑一下，還是聽著你說話就忍不住笑、主動問下去？把笑容、眼神和她怎麼接話放在一起看，再判斷互動走到哪裡。',
    practice: '把笑容、眼神與她接話的方式一起看。單次微笑或追問，都不足以替整段互動下結論。',
    source: '第 11 集 06:05–07:02、12:59–13:07、14:05–14:10；解惑篇 09 03:04–03:31。',
    tier: NightMarketReviewTier.more,
  ),
  NightMarketReviewItem(
    id: 'qualification',
    term: '賦格',
    plain:
        '她說杯子的把手重做了三次，你因此欣賞她的耐心和做事態度。先看見她展現的特質，再說出你欣賞什麼，這個肯定就有根據，也讓後面的邀約有來由。',
    practice: '先找出她已經展現的特質，再說自己欣賞的理由。像重做把手三次，讓耐心變得具體。',
    source: '第 11 集 10:39–11:06、15:01–15:09；達人篇 09 12:23–13:22；夜市「這點我蠻欣賞的」。',
    tier: NightMarketReviewTier.more,
  ),
  NightMarketReviewItem(
    id: 'disqualification',
    term: '失格',
    plain:
        '在有認同、有興趣的互動裡，適時收回一點認同或注意力，讓她感覺你也有自己的評估與節奏。夜市裡，剛說完「這點我蠻欣賞的」，你就先回去找朋友，是這一段可以看的細節。',
    practice: '把前後放在一起看：這裡先表達欣賞，再收回注意力、回到自己的安排。',
    source: '第 11 集 08:55–09:01、11:55–12:22；夜市欣賞後收回注意力。',
    tier: NightMarketReviewTier.more,
    detail: 'Chris 也示範過再次問名字等行為上的失格。這次夜市可對照的是先表達欣賞，再收回注意力，沒有再次問名字。',
    optional: true,
  ),
  NightMarketReviewItem(
    id: 'push_pull',
    term: '推拉',
    plain:
        '剛說「這點我蠻欣賞的」是靠近，接著說各自去找朋友是退開。前面的肯定、後面的收回，放在同一段互動裡，就有進有退。看整個互動的起伏，不用每句都硬湊一進一退。',
    practice: '回看片尾肯定與退開的順序，感受整段起伏，不用替每一句都安排一個相反動作。',
    source: '第 11 集 12:26–12:42、13:08–13:17；夜市賦格與離場段落。',
    tier: NightMarketReviewTier.more,
    optional: true,
  ),
  NightMarketReviewItem(
    id: 'busy_or_instant_date',
    term: '忙碌收尾／即約',
    plain: '先知道她接下來的安排，再決定下一步。各自還有事，就收短、留聯繫；當下都還有時間，也聊得下去，再提附近的小邀約。',
    practice: '先知道彼此接下來的安排。改天見面與現在一起去，是兩種不同的邀約。',
    source: '達人篇 08 05:36–07:19；夜市結尾是「改天咖啡」，不是當下即約。',
    tier: NightMarketReviewTier.more,
    detail: '這次有「改天咖啡」，沒有當場轉去喝咖啡。即約是當下兩人都有時間，再把互動延續到附近的活動。',
    met: false,
  ),
  NightMarketReviewItem(
    id: 'control',
    term: '掌控感／控制力',
    plain:
        '這場互動是你開始的，你也把節奏接起來：留意站位、接住回應，遇到打斷時知道怎麼處理，再決定何時換話題、收尾或提下一步。片尾先回去找朋友，再提加 IG，就是由你自然地把互動往前帶。',
    practice: '從站位、話題到收尾，留意哪個地方需要你接起來。遇到狀況，先處理，再把對話接下去。',
    source: '解惑篇 04 00:06–00:51、04:08–05:36；第 11 集 16:30–17:03。',
    tier: NightMarketReviewTier.mindset,
    detail:
        'Chris 稱為控制力：掌控整個局面、主導社交動態。因為互動是自己發起的，要承擔其中的狀況；他舉了避開店門口人流、換到適合聊天的位置，以及自己決定收尾後再提出聯繫。',
    sceneNote: '夜市有主動開口、延伸陶藝、表達欣賞、先收尾再收 IG；沒有示範遭店門人流打斷後換位。',
  ),
  NightMarketReviewItem(
    id: 'sexual_hook',
    term: '性上鉤點',
    plain:
        '當她開始被你吸引，互動裡會出現男女之間的情緒。留意她是否自發地笑、主動追問、持續看著你；把這些變化連起來，分辨禮貌應答和被吸引時的反應。',
    practice: '留意反應是否持續、有沒有前後變化。這段的主動追問能提供線索，仍要連同眼神與情緒一起判讀。',
    source: '第 11 集 06:05–07:02、12:59–13:07、14:05–14:10、15:10–15:25。',
    tier: NightMarketReviewTier.more,
    detail:
        'Chris 用來描述女生已出現男女吸引的情緒。他在片中觀察沒有笑話仍持續笑、主動問年齡、注視他的眼神，並區分社交性微笑與情緒被調動的笑。',
    sceneNote: '夜市可用她追問「為什麼」「到底是多醜」來講投入線索；不要只憑一個問句宣稱已確定跨過性上鉤點。',
  ),
  NightMarketReviewItem(
    id: 'lifestyle_sample',
    term: '生活模式樣本',
    plain:
        '分享一小段你真的在過的生活，她才有畫面可以認識你。像原本陪朋友去陶藝課，最後自己不肯走，幾句話就讓她看到你的朋友、興趣和日常，也留下想再問一點的空間。',
    practice: '分享真實生活的一小部分：和誰去、做了什麼、哪個細節有意思，讓她有畫面可以接話。',
    source: '第 11 集 04:33–05:22、09:17–10:01。',
    tier: NightMarketReviewTier.more,
    detail:
        '讓她看到自己生活的一小部分，激發她對你的想像與了解慾望；Chris 舉上海到成都、朋友做量化投資，並強調不用誇張吹捧朋友來證明自己。',
    sceneNote: '夜市已有陶藝生活片段。',
  ),
  NightMarketReviewItem(
    id: 'personality_sample',
    term: '個性樣本',
    plain:
        '故事也會讓她看見你是什麼樣的人。「平常很多事情都隨便，想做好的東西就會很龜毛」，把你的在意和性格說出來；她接著說「我也是」，你們就有了更具體的共同點。',
    practice: '說經歷時，也說你在意什麼、怎麼想。對方才有機會從故事認識你的個性。',
    source: '第 11 集 10:03–10:23；夜市杯口與龜毛台詞。',
    tier: NightMarketReviewTier.more,
    detail: 'Chris 把「一聽數字就頭疼」說成展現個性樣本。重點是讓對方從具體表達認識自己的偏好與個性。',
    sceneNote: '夜市已有明確個性分享。',
  ),
  NightMarketReviewItem(
    id: 'shit_test',
    term: '廢物測試',
    plain:
        '互動中遇到質疑或調侃，先聽懂她在表達什麼，再決定怎麼接。Chris 講的重點是：回應之後仍能維持自己的狀態，把話題接下去，別一直困在證明自己。',
    practice: '先聽語氣與情緒，再選擇簡答後繼續、略過調侃，或順著她的話轉回互動。若她明確拒絕，就按她表達的意思處理。',
    source:
        '第 11 集 00:23–00:33；解惑篇 06 00:06–00:14、02:59–03:16、07:03–08:26；第 07 集 08:30–09:17；第 09 集 03:04–03:31。',
    tier: NightMarketReviewTier.more,
    detail:
        '解惑篇 06 也稱一致性測試；Chris 關注的是對方提出質疑、挑戰時，你是否卡住、反覆自證，或仍能穩定地回應並推進互動。解惑篇 07 列簡答後繼續、直接忽略、逆轉框架；第 09 集提醒看話語背後的情緒。',
    sceneNote: 'Leah 的「也沒有啦」是在修正冷讀；目前沒有充分依據把它標成一次已通過的廢物測試。明確拒絕仍按她表達的意思處理。',
    met: false,
  ),
  NightMarketReviewItem(
    id: 'handshake',
    term: '服從性測試（握手）',
    plain: '自我介紹後伸出手，看看她是否願意回應這個小互動。Chris 把片中的握手稱為服從性測試；復盤可以看她這一次怎麼接，再決定後面的節奏。',
    practice: '留意她是否回應這次握手，以及回應時的狀態。這只能說明當下這個互動，後面仍要繼續觀察。',
    source: '第 11 集 16:09–16:13。',
    tier: NightMarketReviewTier.more,
    detail: '在這一集可直接對照的行為是握手：提出一個小互動，看她是否回應。這一集沒有完整展開後續升級方法。',
    sceneNote: '夜市握手可以對照；回握的資訊只對應當下這個互動。',
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
          text: '你注意到她，也有想認識她的理由。帶著這份確定去開口，眼神、聲音與姿態就能傳達同一個意思。'),
      NightMarketReviewExplanation(
          knowledgeId: 'opening',
          title: '打開｜先取得注意，再進入對話',
          text: '從她看得到的方向打招呼。她開始回應了，就順著當下往下聊，讓開場成為對話的起點。'),
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
          text: '突然被陌生人打招呼，她可能有些意外、尷尬。一句「有點突然」，讓她知道你有感覺到她的處境。'),
      NightMarketReviewExplanation(
          knowledgeId: 'empathy_background',
          title: '背景介紹｜讓她知道你為什麼在這裡',
          text: '交代自己和朋友來逛、剛才在等人，讓你的出現有前因後果。她比較能理解你的來意，信任感才有地方開始。'),
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
          text: '你從她挑東西的樣子提出觀察。她把話題修正成手作，你就沿著她真正有興趣的方向繼續。'),
      NightMarketReviewExplanation(
          knowledgeId: 'questions',
          title: '提問是工具｜問完之後，讓話題長下去',
          text: '「妳是喜歡逛，還是自己也會做？」讓手作延伸到陶藝，也替你分享自己的經驗留下位置。'),
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
          text: '先說到「最後反而是我不肯走」，她接著問為什麼。她想知道了，你再把杯子的故事接下去。'),
      NightMarketReviewExplanation(
          knowledgeId: 'personality_sample',
          title: '個性樣本｜故事裡，讓她看見你在意什麼',
          text: '從「想做好的東西就會很龜毛」，到她說把手重做三次，你們聊出了做事的態度和共同點。'),
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
          text: '她分享了重做把手的經歷，你因此欣賞她的耐心。這個肯定有根據，也讓繼續認識她有了理由。'),
      NightMarketReviewExplanation(
          knowledgeId: 'disqualification',
          title: '失格／無興趣指標｜在有興趣的互動裡，退開一點',
          text: '說完欣賞，再回去找自己的朋友。前面的認同與後面的退開，讓這段互動有進有退。'),
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
          title: '收號｜讓下一步接在這段互動後面',
          text: '你們已經有共同話題，也表達了欣賞。這時提出加 IG，延續原本的眼神與語氣，把聯繫接起來。'),
      NightMarketReviewExplanation(
          knowledgeId: 'control',
          title: '掌控感／控制力｜把互動的下一步帶出來',
          text: '何時收尾、何時提聯繫，都由你自然往前帶。這次是改天咖啡；當下即約，是另一種時間安排。'),
    ],
    practice: '收尾前想一想：你們剛才聊出的共同點，可以怎麼接到下一次見面？',
    knowledgeIds: ['contact', 'busy_or_instant_date', 'control'],
  ),
];
