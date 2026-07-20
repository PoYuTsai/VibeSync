import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { looksLikeGameSoftInvite } from "./game_invite_classifier.ts";

Deno.test("Game invite scanner keeps retractions, reports, and solo plans non-invites", () => {
  const nonInvites = [
    // A later retraction must clear an earlier proposal, including sentences.
    "明天一起喝咖啡。算了。",
    "明天要不要一起吃飯？算了。",
    "改天可以喝咖啡，沒有要約妳啦。",
    "明天一起看電影吧。不去了。",
    "週末一起逛街。不要了。",
    "明天一起吃飯。開玩笑啦。",
    "明天一起吃飯，當我沒講。",
    "明天一起吃飯，我亂講的。",
    "明天一起吃飯，別當真。",
    "明天一起喝咖啡，不是約妳啦。",
    "明天一起喝咖啡，收回。",
    "明天一起吃飯，撤回。",
    "週末一起看電影，不算。",
    "改天要不要喝一杯？別認真。",
    "週末我們去看展，我隨口說的。",
    "明晚一起散步，只是亂講。",
    "下週一起吃飯，說笑的。",
    "明天一起去夜市，鬧你的。",
    "改天一起看電影，逗你的。",
    "週末一起喝咖啡，當作沒聽到。",
    "週末電影？這次先跳過。",
    "有空去書店？先擱著。",
    "下週一起喝茶，暫緩。",
    "明天一起喝咖啡，先不排了。",
    "後天一起看展，先撤掉。",
    "改天去夜市，這回免了。",
    "週六一起唱歌，暫時作廢。",
    "明晚約個晚餐，先別約。",
    "週末一起跑步，先不要排。",
    "有空去水族館？行程先擱置。",
    "後天一起吃早餐，暫且喊停。",
    "週日一起去書店，先延後再說。",
    "改天碰面吧，這回先免了。",
    "下次聚餐，先不要。",
    "明晚咖啡，還是不要好了。",
    "改天喝咖啡，下次再說。",
    "明天一起吃飯，但我沒空。",
    "明天一起吃飯，我沒有空。",
    // Reported or third-party plans never become the user's invitation.
    "我媽問我，明天要不要一起喝咖啡？",
    "朋友問我，欸，明天要不要一起喝咖啡？",
    "朋友問我：嗯，那個，週末一起看電影？",
    "朋友問我。『明天要不要一起喝咖啡？』",
    "朋友說：『明天有空嗎？一起喝咖啡？』",
    "朋友問：『你要不要一起吃飯？』我說可以。",
    "怡君說改天一起吃飯。",
    "咖啡店店員說改天一起吃飯。",
    "公司新來的同事問我明天要不要喝咖啡。",
    "住隔壁的阿姨說下次一起逛街。",
    "剛提過的餐廳，朋友下次會跟我去。",
    "總監要帶我明晚去酒吧。",
    "我跟品妤明晚一起吃飯。",
    "隔壁新來的實習生說改天一起喝咖啡。",
    "公司產品經理問我明天要不要一起看展。",
    "同組工程師說週末一起吃飯。",
    "朋友說她明天沒空週末再一起喝咖啡。",
    "朋友昨天說她明天沒空週末再一起喝咖啡。",
    "陳醫師問我，週末要不要看電影？",
    "Amy 問我：『明晚咖啡？』",
    "阿豪約我週末去看展。",
    "下次朋友跟我去喝。",
    "明天他們一起吃飯吧？",
    "我跟小美一起去看展。",
    "週末老闆帶我去餐廳。",
    "昨天我問妳，明天要不要一起喝咖啡？",
    "昨天我跟妳說週末一起吃飯。",
    "前天我告訴你週末一起看電影。",
    "去年我邀妳週末吃飯。",
    "去年我邀你週末吃飯。",
    "去年我約妳週末吃飯。",
    "去年冬天我約妳週末吃飯。",
    "上週五我邀你明晚看電影。",
    "前年我約妳下週喝咖啡。",
    "幾年前我邀你明天吃飯。",
    "剛剛我約妳週末看展。",
    "先前我提議週末一起逛書店。",
    // An explicit partner subject describes their solo plan unless dyad evidence exists.
    "你週末要不要去逛市集？",
    "那你明天要不要去看電影？",
    "不知道你下週想不想看展？",
    "問一下你明天要不要吃晚餐？",
    "妳明天要不要喝咖啡？",
    "你今晚想不想看電影？",
    "妳下週想不想去看展？",
    "你明晚想不想自己去看電影？",
    "想問妳明晚要不要喝咖啡？",
    "欸你週六要看展嗎？",
    "好奇妳明晚要不要喝咖啡？",
    "想了解你週末想不想看電影？",
    // Schedule, preference, description, and content questions are not proposals.
    "明天你去哪裡吃飯？",
    "週末你會去看電影嗎？",
    "明天咖啡比較有精神。",
    "週末公園人多嗎？",
    "你喜歡週末看電影嗎？",
    "明晚電影幾點開始？",
    "週末電影票價多少？",
    "週末電影好看嗎？",
    "明天咖啡好喝嗎？",
    "明晚酒吧有低消嗎？",
    "明晚酒吧會很多人嗎？",
    "下週音樂祭還有票嗎？",
    "明晚牛排價格多少？",
    "週六電影票多少錢？",
    "明天早餐幾卡？",
    "週五晚餐菜單出了嗎？",
    "週六桌遊規則很難嗎？",
    "週末火鍋人很多吧？",
    "今晚牛排五分熟嗎？",
    "這週末咖啡店休息吧？",
    "昨天那場電影你下週會再看嗎？",
    "明晚電影很貴吧？",
    "明晚電影很爛吧？",
    "明天咖啡店營業嗎？",
    "這週末想吃什麼？",
    "妳平常會去咖啡店嗎？",
    "妳週末常爬山嗎？",
    "你明早喝咖啡嗎？",
    "妳明早要不要喝咖啡？",
    "明早你喝咖啡嗎？",
    "週末去夜市是不是很擠？",
    "明天咖啡妳想喝哪種？",
    "想不想看這篇文章？",
    "改天有空再看看你的想法？",
    "有空再玩這個梗？",
    "要不要玩猜謎遊戲？",
    "我跟你說明天會下雨。",
    "週末別一起去看電影。",
    "暫時別跟妳看展。",
    "週末看電影很舒服。",
    "下週去展覽的人會很多。",
    "今晚喝酒對身體不好。",
    "前陣子我們一起喝咖啡。",
    "上個禮拜我們一起吃飯。",
    "前幾天我們一起看展。",
    "要不要看電影預告？",
    "妳對週末有什麼意見？",
    "下週展覽要預約嗎？",
    "明天要預約餐廳嗎？",
    "週六展覽需要預約嗎？",
    "如果改天一起喝咖啡算邀約嗎？",
    "『週末電影？』這句自然嗎？",
    "我要寫『明天一起吃飯』在筆記裡。",
    "下次約會的意思是什麼？",
    "下週公司聚餐嗎？",
    "明天董事會？",
    "週末家庭聚會嗎？",
    "明天記者會？",
    "下週說明會？",
    "週末法說會？",
    "明天同學會？",
    "品妤下週跟我去吃飯。",
    "佩佩明晚會跟我去酒吧。",
    "佩佩講『改天一起喝咖啡』。",
    "這算是在約妳嗎？",
    "如果說下次一起看展會太直接嗎？",
    "下次聚焦咖啡主題可以嗎？",
    "週末看展超有趣。",
    // Direct negation, separation, chores, and health plans are not dates.
    "今晚不喝酒了。",
    "明天不一起吃飯。",
    "改天不一起喝咖啡。",
    "下次沒有咖啡局。",
    "明天不吃飯。",
    "週末不看電影。",
    "我不跟妳去喝咖啡。",
    "我不陪你去看展。",
    "明天要不要各自吃飯？",
    "週末我們各自看電影吧。",
    "我們分開去逛街。",
    "你週末要不要去看牙醫？",
    "你今晚要不要去睡覺？",
    "你等等要不要去睡？",
    "你下班後要不要去加油？",
    "欸明晚要不要去領藥？",
    "有空一起去領包裹？",
    "週末一起去辦護照？",
    "明晚陪我去超商取貨？",
    "明天跟我去修手機？",
    "週末他去你家吃飯。",
    "後天朋友來我家喝茶。",
    "週末品妤去你家吃飯。",
    "後天怡君來我家喝茶。",
    "週末跑團朋友去你家吃飯。",
    "後天看展同事來我家喝茶。",
    "明天怡君去妳家吃飯。",
    "週末小美來我家喝茶。",
    "改天去山上的路會塞嗎？",
    "改天路況會塞嗎？",
    "她到我工作室喝茶。",
    "朋友上你家看電影。",
    "去超商取貨。",
    "去修手機。",
    "辦護照。",
    "下次聚焦資料。",
    "下次聚合資料。",
    "要不要我幫你找一間咖啡店？",
  ];

  for (const text of nonInvites) {
    assertEquals(looksLikeGameSoftInvite(text), false, text);
  }
});

type R15ClassifierRegressionCase = {
  readonly id: string;
  readonly root: string;
  readonly text: string;
  readonly expected: boolean;
};

const R15_GRAMMAR_REGRESSIONS: readonly R15ClassifierRegressionCase[] = [
  // current: 6 reliable frozen-baseline mismatches.
  {
    id: "current-006",
    root: "current shared proposal",
    text: "不如月底的星期五我去接妳，再到港邊餐廳吃晚餐。",
    expected: true,
  },
  {
    id: "current-015",
    root: "current shared proposal",
    text: "我把下個月第一個週末留給妳，要不要跟我到森林步道拍幾張照片？",
    expected: true,
  },
  {
    id: "current-018",
    root: "current shared proposal",
    text: "不如後天傍晚我去接妳，再到獨立書店挑一本書。",
    expected: true,
  },
  {
    id: "current-030",
    root: "current shared proposal",
    text: "不如下個月第一個週末我去接妳，再到森林步道拍幾張照片。",
    expected: true,
  },
  {
    id: "current-054",
    root: "current shared proposal",
    text: "不如這個週末我去接妳，再到植物市集逛逛攤位。",
    expected: true,
  },
  {
    id: "current-060",
    root: "current shared proposal",
    text: "想在下個月第一個週末跟妳去森林步道拍幾張照片，妳覺得呢？",
    expected: true,
  },

  // retraction: 26 reliable frozen-baseline mismatches.
  {
    id: "retraction-005",
    root: "terminal withdrawal",
    text: "下下週日上午我帶妳去小劇場看場小戲，剛剛那個提議不作數。",
    expected: false,
  },
  {
    id: "retraction-006",
    root: "terminal withdrawal",
    text: "這個週末我們一起去老屋茶館吃份甜點，那段邀請請直接忽略。",
    expected: false,
  },
  {
    id: "retraction-009",
    root: "terminal withdrawal",
    text:
      "要不要七月二十五號晚上跟我去音樂展演空間聽一場音樂會，先不要把這件事排進去。",
    expected: false,
  },
  {
    id: "retraction-011",
    root: "terminal withdrawal",
    text: "明晚八點我們一起去老屋茶館吃份甜點，這趟先停掉。",
    expected: false,
  },
  {
    id: "retraction-012",
    root: "terminal withdrawal",
    text: "我想約妳下個月第一個週末到陶藝工坊做一堂陶藝，那個計畫我收回了。",
    expected: false,
  },
  {
    id: "retraction-015",
    root: "terminal withdrawal",
    text: "後天傍晚我帶妳去小劇場看場小戲，只是這次先別成行。",
    expected: false,
  },
  {
    id: "retraction-017",
    root: "terminal withdrawal",
    text: "我想約妳下個禮拜二晚上到陶藝工坊做一堂陶藝，剛剛那個提議不作數。",
    expected: false,
  },
  {
    id: "retraction-021",
    root: "terminal withdrawal",
    text: "這個週末我們一起去老屋茶館吃份甜點，先不要把這件事排進去。",
    expected: false,
  },
  {
    id: "retraction-023",
    root: "terminal withdrawal",
    text: "本月最後一個週六陪我去湖畔公園散散步，這趟先停掉。",
    expected: false,
  },
  {
    id: "retraction-024",
    root: "terminal withdrawal",
    text:
      "要不要七月二十五號晚上跟我去音樂展演空間聽一場音樂會，那個計畫我收回了。",
    expected: false,
  },
  {
    id: "retraction-027",
    root: "terminal withdrawal",
    text: "我想約妳下個月第一個週末到陶藝工坊做一堂陶藝，只是這次先別成行。",
    expected: false,
  },
  {
    id: "retraction-029",
    root: "terminal withdrawal",
    text:
      "要不要下星期六下午跟我去音樂展演空間聽一場音樂會，剛剛那個提議不作數。",
    expected: false,
  },
  {
    id: "retraction-030",
    root: "terminal withdrawal",
    text: "後天傍晚我帶妳去小劇場看場小戲，那段邀請請直接忽略。",
    expected: false,
  },
  {
    id: "retraction-035",
    root: "terminal withdrawal",
    text: "下下週日上午我帶妳去小劇場看場小戲，這趟先停掉。",
    expected: false,
  },
  {
    id: "retraction-036",
    root: "terminal withdrawal",
    text: "這個週末我們一起去老屋茶館吃份甜點，那個計畫我收回了。",
    expected: false,
  },
  {
    id: "retraction-039",
    root: "terminal withdrawal",
    text:
      "要不要七月二十五號晚上跟我去音樂展演空間聽一場音樂會，只是這次先別成行。",
    expected: false,
  },
  {
    id: "retraction-041",
    root: "terminal withdrawal",
    text: "明晚八點我們一起去老屋茶館吃份甜點，剛剛那個提議不作數。",
    expected: false,
  },
  {
    id: "retraction-042",
    root: "terminal withdrawal",
    text: "我想約妳下個月第一個週末到陶藝工坊做一堂陶藝，那段邀請請直接忽略。",
    expected: false,
  },
  {
    id: "retraction-045",
    root: "terminal withdrawal",
    text: "後天傍晚我帶妳去小劇場看場小戲，先不要把這件事排進去。",
    expected: false,
  },
  {
    id: "retraction-047",
    root: "terminal withdrawal",
    text: "我想約妳下個禮拜二晚上到陶藝工坊做一堂陶藝，這趟先停掉。",
    expected: false,
  },
  {
    id: "retraction-051",
    root: "terminal withdrawal",
    text: "這個週末我們一起去老屋茶館吃份甜點，只是這次先別成行。",
    expected: false,
  },
  {
    id: "retraction-053",
    root: "terminal withdrawal",
    text: "本月最後一個週六陪我去湖畔公園散散步，剛剛那個提議不作數。",
    expected: false,
  },
  {
    id: "retraction-054",
    root: "terminal withdrawal",
    text:
      "要不要七月二十五號晚上跟我去音樂展演空間聽一場音樂會，那段邀請請直接忽略。",
    expected: false,
  },
  {
    id: "retraction-057",
    root: "terminal withdrawal",
    text:
      "我想約妳下個月第一個週末到陶藝工坊做一堂陶藝，先不要把這件事排進去。",
    expected: false,
  },
  {
    id: "retraction-059",
    root: "terminal withdrawal",
    text: "要不要下星期六下午跟我去音樂展演空間聽一場音樂會，這趟先停掉。",
    expected: false,
  },
  {
    id: "retraction-060",
    root: "terminal withdrawal",
    text: "後天傍晚我帶妳去小劇場看場小戲，那個計畫我收回了。",
    expected: false,
  },

  // reschedule: 29 reliable frozen-baseline mismatches.
  {
    id: "reschedule-003",
    root: "withdrawal followed by concrete replacement",
    text: "這個週末那場陶藝體驗不成行了，挪去明晚八點吧。",
    expected: true,
  },
  {
    id: "reschedule-004",
    root: "withdrawal followed by concrete replacement",
    text: "下週三晚間先不要去攝影藝廊，另約下個月第一個週末碰面。",
    expected: true,
  },
  {
    id: "reschedule-006",
    root: "withdrawal followed by concrete replacement",
    text: "七月二十五號晚上那趟往後延，時間移到下星期六下午。",
    expected: true,
  },
  {
    id: "reschedule-009",
    root: "withdrawal followed by concrete replacement",
    text: "下個月第一個週末的英式下午茶取消，時間改成下個禮拜二晚上。",
    expected: true,
  },
  {
    id: "reschedule-012",
    root: "withdrawal followed by concrete replacement",
    text: "先把後天傍晚的湖畔野餐拿掉，順延到下下週日上午。",
    expected: true,
  },
  {
    id: "reschedule-014",
    root: "withdrawal followed by concrete replacement",
    text:
      "原訂下個禮拜二晚上的森林健行先撤掉，下週三晚間改成我們去森林步道拍幾張照片。",
    expected: true,
  },
  {
    id: "reschedule-015",
    root: "withdrawal followed by concrete replacement",
    text: "月底的星期五那場黑盒子劇場不成行了，挪去本月最後一個週六吧。",
    expected: true,
  },
  {
    id: "reschedule-016",
    root: "withdrawal followed by concrete replacement",
    text: "明天下班後先不要去海濱步道，另約七月二十五號晚上碰面。",
    expected: true,
  },
  {
    id: "reschedule-018",
    root: "withdrawal followed by concrete replacement",
    text: "這個週末那趟往後延，時間移到明晚八點。",
    expected: true,
  },
  {
    id: "reschedule-021",
    root: "withdrawal followed by concrete replacement",
    text: "七月二十五號晚上的不插電音樂會取消，時間改成下星期六下午。",
    expected: true,
  },
  {
    id: "reschedule-024",
    root: "withdrawal followed by concrete replacement",
    text: "先把下個月第一個週末的英式下午茶拿掉，順延到下個禮拜二晚上。",
    expected: true,
  },
  {
    id: "reschedule-027",
    root: "withdrawal followed by concrete replacement",
    text: "後天傍晚那場湖畔野餐不成行了，挪去下下週日上午吧。",
    expected: true,
  },
  {
    id: "reschedule-028",
    root: "withdrawal followed by concrete replacement",
    text: "本週日中午先不要去手作甜點店，另約這個週末碰面。",
    expected: true,
  },
  {
    id: "reschedule-030",
    root: "withdrawal followed by concrete replacement",
    text: "月底的星期五那趟往後延，時間移到本月最後一個週六。",
    expected: true,
  },
  {
    id: "reschedule-033",
    root: "withdrawal followed by concrete replacement",
    text: "這個週末的陶藝體驗取消，時間改成明晚八點。",
    expected: true,
  },
  {
    id: "reschedule-034",
    root: "withdrawal followed by concrete replacement",
    text: "下週三晚間先延後，改約在下個月第一個週末去攝影藝廊看攝影作品。",
    expected: true,
  },
  {
    id: "reschedule-036",
    root: "withdrawal followed by concrete replacement",
    text: "先把七月二十五號晚上的不插電音樂會拿掉，順延到下星期六下午。",
    expected: true,
  },
  {
    id: "reschedule-039",
    root: "withdrawal followed by concrete replacement",
    text: "下個月第一個週末那場英式下午茶不成行了，挪去下個禮拜二晚上吧。",
    expected: true,
  },
  {
    id: "reschedule-040",
    root: "withdrawal followed by concrete replacement",
    text: "這週四晚上先不要去爵士酒吧，另約月底的星期五碰面。",
    expected: true,
  },
  {
    id: "reschedule-042",
    root: "withdrawal followed by concrete replacement",
    text: "後天傍晚那趟往後延，時間移到下下週日上午。",
    expected: true,
  },
  {
    id: "reschedule-045",
    root: "withdrawal followed by concrete replacement",
    text: "月底的星期五的黑盒子劇場取消，時間改成本月最後一個週六。",
    expected: true,
  },
  {
    id: "reschedule-046",
    root: "withdrawal followed by concrete replacement",
    text: "明天下班後先延後，改約在七月二十五號晚上去海濱步道走一小段路。",
    expected: true,
  },
  {
    id: "reschedule-048",
    root: "withdrawal followed by concrete replacement",
    text: "先把這個週末的陶藝體驗拿掉，順延到明晚八點。",
    expected: true,
  },
  {
    id: "reschedule-051",
    root: "withdrawal followed by concrete replacement",
    text: "七月二十五號晚上那場不插電音樂會不成行了，挪去下星期六下午吧。",
    expected: true,
  },
  {
    id: "reschedule-052",
    root: "withdrawal followed by concrete replacement",
    text: "星期二傍晚先不要去河岸咖啡館，另約後天傍晚碰面。",
    expected: true,
  },
  {
    id: "reschedule-054",
    root: "withdrawal followed by concrete replacement",
    text: "下個月第一個週末那趟往後延，時間移到下個禮拜二晚上。",
    expected: true,
  },
  {
    id: "reschedule-056",
    root: "withdrawal followed by concrete replacement",
    text: "下星期六下午暫緩，等明天下班後我們再約。",
    expected: true,
  },
  {
    id: "reschedule-057",
    root: "withdrawal followed by concrete replacement",
    text: "後天傍晚的湖畔野餐取消，時間改成下下週日上午。",
    expected: true,
  },
  {
    id: "reschedule-060",
    root: "withdrawal followed by concrete replacement",
    text: "先把月底的星期五的黑盒子劇場拿掉，順延到本月最後一個週六。",
    expected: true,
  },

  // double_neg: 27 reliable frozen-baseline mismatches.
  {
    id: "double_neg-002",
    root: "double-negative lead plus affirmative scheduling",
    text: "倒不是不願意陪你去音樂展演空間，只是希望排到本週日中午。",
    expected: true,
  },
  {
    id: "double_neg-003",
    root: "double-negative lead plus affirmative scheduling",
    text: "我並非不肯帶妳去海濱步道，只是要等到下個禮拜二晚上。",
    expected: true,
  },
  {
    id: "double_neg-005",
    root: "double-negative lead plus affirmative scheduling",
    text: "我也不是不打算邀妳聽一場音樂會，只是想挪到明天下班後。",
    expected: true,
  },
  {
    id: "double_neg-006",
    root: "double-negative lead plus affirmative scheduling",
    text: "不是說我不想陪你走一小段路，時間改成下下週日上午比較好。",
    expected: true,
  },
  {
    id: "double_neg-010",
    root: "double-negative lead plus affirmative scheduling",
    text: "不是完全不想帶你去山城夜市，而是想把約會放到七月二十五號晚上。",
    expected: true,
  },
  {
    id: "double_neg-012",
    root: "double-negative lead plus affirmative scheduling",
    text: "也不是不願跟你去海濱步道，我們換成明晚八點。",
    expected: true,
  },
  {
    id: "double_neg-014",
    root: "double-negative lead plus affirmative scheduling",
    text: "倒不是不願意陪你去音樂展演空間，只是希望排到這週四晚上。",
    expected: true,
  },
  {
    id: "double_neg-015",
    root: "double-negative lead plus affirmative scheduling",
    text: "我並非不肯帶妳去海濱步道，只是要等到下星期六下午。",
    expected: true,
  },
  {
    id: "double_neg-017",
    root: "double-negative lead plus affirmative scheduling",
    text: "我也不是不打算邀妳聽一場音樂會，只是想挪到本週日中午。",
    expected: true,
  },
  {
    id: "double_neg-018",
    root: "double-negative lead plus affirmative scheduling",
    text: "不是說我不想陪你走一小段路，時間改成下個禮拜二晚上比較好。",
    expected: true,
  },
  {
    id: "double_neg-022",
    root: "double-negative lead plus affirmative scheduling",
    text: "不是完全不想帶你去山城夜市，而是想把約會放到這個週末。",
    expected: true,
  },
  {
    id: "double_neg-024",
    root: "double-negative lead plus affirmative scheduling",
    text: "也不是不願跟你去海濱步道，我們換成本月最後一個週六。",
    expected: true,
  },
  {
    id: "double_neg-025",
    root: "double-negative lead plus affirmative scheduling",
    text: "我不是不想約妳，而是想把時間改在七月二十五號晚上。",
    expected: true,
  },
  {
    id: "double_neg-026",
    root: "double-negative lead plus affirmative scheduling",
    text: "倒不是不願意陪你去音樂展演空間，只是希望排到星期二傍晚。",
    expected: true,
  },
  {
    id: "double_neg-027",
    root: "double-negative lead plus affirmative scheduling",
    text: "我並非不肯帶妳去海濱步道，只是要等到明晚八點。",
    expected: true,
  },
  {
    id: "double_neg-029",
    root: "double-negative lead plus affirmative scheduling",
    text: "我也不是不打算邀妳聽一場音樂會，只是想挪到這週四晚上。",
    expected: true,
  },
  {
    id: "double_neg-030",
    root: "double-negative lead plus affirmative scheduling",
    text: "不是說我不想陪你走一小段路，時間改成下星期六下午比較好。",
    expected: true,
  },
  {
    id: "double_neg-034",
    root: "double-negative lead plus affirmative scheduling",
    text: "不是完全不想帶你去山城夜市，而是想把約會放到月底的星期五。",
    expected: true,
  },
  {
    id: "double_neg-036",
    root: "double-negative lead plus affirmative scheduling",
    text: "也不是不願跟你去海濱步道，我們換成下下週日上午。",
    expected: true,
  },
  {
    id: "double_neg-038",
    root: "double-negative lead plus affirmative scheduling",
    text: "倒不是不願意陪你去音樂展演空間，只是希望排到下週三晚間。",
    expected: true,
  },
  {
    id: "double_neg-039",
    root: "double-negative lead plus affirmative scheduling",
    text: "我並非不肯帶妳去海濱步道，只是要等到本月最後一個週六。",
    expected: true,
  },
  {
    id: "double_neg-040",
    root: "double-negative lead plus affirmative scheduling",
    text: "並不是沒有想跟你去山城夜市，我想約在七月二十五號晚上。",
    expected: true,
  },
  {
    id: "double_neg-042",
    root: "double-negative content-only tail with explicit no meeting",
    text: "並非不願跟你走一小段路，只是查票價資料，不是在約你。",
    expected: false,
  },
  {
    id: "double_neg-046",
    root: "double-negative content-only tail with explicit no meeting",
    text: "並非不願跟你吃點宵夜，只是查節目手冊，不是在約你。",
    expected: false,
  },
  {
    id: "double_neg-050",
    root: "double-negative content-only tail with explicit no meeting",
    text: "並非不願跟你聽一場音樂會，只是查活動官網，不是在約你。",
    expected: false,
  },
  {
    id: "double_neg-054",
    root: "double-negative content-only tail with explicit no meeting",
    text: "並非不願跟你走一小段路，只是查演員專訪，不是在約你。",
    expected: false,
  },
  {
    id: "double_neg-058",
    root: "double-negative content-only tail with explicit no meeting",
    text: "並非不願跟你吃點宵夜，只是查交通指南，不是在約你。",
    expected: false,
  },

  // past: 35 reliable frozen-baseline mismatches.
  {
    id: "past-001",
    root: "definite historical self narrative",
    text: "三個月前我曾約妳月底的星期五去攝影藝廊。",
    expected: false,
  },
  {
    id: "past-002",
    root: "definite historical self narrative",
    text: "兩個星期以前我有邀你下週一起聽一場音樂會。",
    expected: false,
  },
  {
    id: "past-003",
    root: "definite historical self narrative",
    text: "去年暑假我原先打算陪妳週末去植物市集。",
    expected: false,
  },
  {
    id: "past-004",
    root: "definite historical self narrative",
    text: "前年年底我那時想帶你明晚去爵士酒吧。",
    expected: false,
  },
  {
    id: "past-005",
    root: "definite historical self narrative",
    text: "大前年春天我們談過改天一起散散步。",
    expected: false,
  },
  {
    id: "past-007",
    root: "definite historical self narrative",
    text: "四週之前我本來準備約你後天走一小段路。",
    expected: false,
  },
  {
    id: "past-008",
    root: "definite historical self narrative",
    text: "一年前的冬天我說過月底要陪妳去陶藝工坊。",
    expected: false,
  },
  {
    id: "past-009",
    root: "definite historical self narrative",
    text: "前幾個星期我們曾計畫這週末一起吃晚餐。",
    expected: false,
  },
  {
    id: "past-011",
    root: "definite historical self narrative",
    text: "前年夏天我有邀你下週一起吃份甜點。",
    expected: false,
  },
  {
    id: "past-012",
    root: "definite historical self narrative",
    text: "去年十二月我原先打算陪妳週末去山城夜市。",
    expected: false,
  },
  {
    id: "past-013",
    root: "definite historical self narrative",
    text: "三個月前我那時想帶你明晚去手作甜點店。",
    expected: false,
  },
  {
    id: "past-015",
    root: "definite historical self narrative",
    text: "去年暑假我提議過下次跟妳去獨立書店。",
    expected: false,
  },
  {
    id: "past-016",
    root: "definite historical self narrative",
    text: "前年年底我本來準備約你後天看攝影作品。",
    expected: false,
  },
  {
    id: "past-018",
    root: "definite historical self narrative",
    text: "去年年初我們曾計畫這週末一起逛逛攤位。",
    expected: false,
  },
  {
    id: "past-019",
    root: "definite historical self narrative",
    text: "四週之前我曾約妳這個週末去爵士酒吧。",
    expected: false,
  },
  {
    id: "past-020",
    root: "definite historical self narrative",
    text: "一年前的冬天我有邀你下週一起散散步。",
    expected: false,
  },
  {
    id: "past-023",
    root: "definite historical self narrative",
    text: "前年夏天我們談過改天一起做一堂陶藝。",
    expected: false,
  },
  {
    id: "past-025",
    root: "definite historical self narrative",
    text: "三個月前我本來準備約你後天喝杯手沖。",
    expected: false,
  },
  {
    id: "past-027",
    root: "definite historical self narrative",
    text: "去年暑假我們曾計畫這週末一起吃點宵夜。",
    expected: false,
  },
  {
    id: "past-028",
    root: "definite historical self narrative",
    text: "前年年底我曾約妳後天傍晚去手作甜點店。",
    expected: false,
  },
  {
    id: "past-029",
    root: "definite historical self narrative",
    text: "大前年春天我有邀你下週一起看場小戲。",
    expected: false,
  },
  {
    id: "past-030",
    root: "definite historical self narrative",
    text: "去年年初我原先打算陪妳週末去獨立書店。",
    expected: false,
  },
  {
    id: "past-032",
    root: "definite historical self narrative",
    text: "一年前的冬天我們談過改天一起聽一場音樂會。",
    expected: false,
  },
  {
    id: "past-033",
    root: "definite historical self narrative",
    text: "前幾個星期我提議過下次跟妳去植物市集。",
    expected: false,
  },
  {
    id: "past-034",
    root: "definite historical self narrative",
    text: "上個月初我本來準備約你後天聽現場演出。",
    expected: false,
  },
  {
    id: "past-035",
    root: "definite historical self narrative",
    text: "前年夏天我說過月底要陪妳去湖畔公園。",
    expected: false,
  },
  {
    id: "past-037",
    root: "definite historical self narrative",
    text: "三個月前我曾約妳七月二十五號晚上去海濱步道。",
    expected: false,
  },
  {
    id: "past-038",
    root: "definite historical self narrative",
    text: "兩個星期以前我有邀你下週一起做一堂陶藝。",
    expected: false,
  },
  {
    id: "past-040",
    root: "definite historical self narrative",
    text: "前年年底我那時想帶你明晚去河岸咖啡館。",
    expected: false,
  },
  {
    id: "past-041",
    root: "definite historical self narrative",
    text: "大前年春天我們談過改天一起吃份甜點。",
    expected: false,
  },
  {
    id: "past-043",
    root: "definite historical self narrative",
    text: "四週之前我本來準備約你後天喝下午茶。",
    expected: false,
  },
  {
    id: "past-046",
    root: "historical context escaped by explicit fresh proposal",
    text: "上個月初我曾約過妳，但這次我想在月底的星期五帶妳去攝影藝廊。",
    expected: true,
  },
  {
    id: "past-051",
    root: "historical context escaped by explicit fresh proposal",
    text: "去年暑假我曾約過妳，但這次我想在本月最後一個週六帶妳去森林步道。",
    expected: true,
  },
  {
    id: "past-052",
    root: "historical context escaped by explicit fresh proposal",
    text: "前年年底那趟沒有成行；現在我們改約七月二十五號晚上走一小段路。",
    expected: true,
  },
  {
    id: "past-056",
    root: "historical context escaped by explicit fresh proposal",
    text: "一年前的冬天我曾約過妳，但這次我想在這週四晚上帶妳去老屋茶館。",
    expected: true,
  },

  // completed: 4 reliable frozen-baseline mismatches.
  {
    id: "completed-009",
    root: "completed condition followed by shared outing",
    text: "等週末前的排班處理完了，就跟我去小劇場看場小戲。",
    expected: true,
  },
  {
    id: "completed-019",
    root: "completed condition followed by shared outing",
    text: "對了，等週末前的排班處理完了，就跟我去小劇場看場小戲。",
    expected: true,
  },
  {
    id: "completed-029",
    root: "completed condition followed by shared outing",
    text: "話說，等週末前的排班處理完了，就跟我去小劇場看場小戲。",
    expected: true,
  },
  {
    id: "completed-039",
    root: "completed condition followed by shared outing",
    text: "順便問一下，等週末前的排班處理完了，就跟我去小劇場看場小戲。",
    expected: true,
  },

  // shorthand: 27 reliable frozen-baseline mismatches.
  {
    id: "shorthand-001",
    root: "calendar shorthand proposal",
    text: "這個星期六晚上七點花藝市集？",
    expected: true,
  },
  {
    id: "shorthand-002",
    root: "calendar shorthand proposal",
    text: "下下個禮拜日下午兩點，攝影聯展好嗎？",
    expected: true,
  },
  {
    id: "shorthand-003",
    root: "calendar shorthand proposal",
    text: "黑盒子劇場就排下個月第一個週末中午？",
    expected: true,
  },
  {
    id: "shorthand-007",
    root: "calendar shorthand proposal",
    text: "森林健行，七月二十五號晚上七點可以嗎？",
    expected: true,
  },
  {
    id: "shorthand-008",
    root: "calendar shorthand proposal",
    text: "那週二晚間七點四十五爵士演出吧？",
    expected: true,
  },
  {
    id: "shorthand-010",
    root: "calendar shorthand proposal",
    text: "下週末中午十二點，二手書展好嗎？",
    expected: true,
  },
  {
    id: "shorthand-011",
    root: "calendar shorthand proposal",
    text: "法式甜點就排這禮拜四午後三點？",
    expected: true,
  },
  {
    id: "shorthand-015",
    root: "calendar shorthand proposal",
    text: "湖畔野餐，下個月第一個週末中午可以嗎？",
    expected: true,
  },
  {
    id: "shorthand-016",
    root: "calendar shorthand proposal",
    text: "那星期三傍晚六點半花藝市集吧？",
    expected: true,
  },
  {
    id: "shorthand-018",
    root: "calendar shorthand proposal",
    text: "本月最後一個週六下午，黑盒子劇場好嗎？",
    expected: true,
  },
  {
    id: "shorthand-019",
    root: "calendar shorthand proposal",
    text: "山城夜遊就排七月二十五號晚上七點？",
    expected: true,
  },
  {
    id: "shorthand-022",
    root: "calendar shorthand proposal",
    text: "下週末中午十二點一起去森林健行？",
    expected: true,
  },
  {
    id: "shorthand-023",
    root: "calendar shorthand proposal",
    text: "爵士演出，這禮拜四午後三點可以嗎？",
    expected: true,
  },
  {
    id: "shorthand-025",
    root: "calendar shorthand proposal",
    text: "這個星期六晚上七點二手書展？",
    expected: true,
  },
  {
    id: "shorthand-026",
    root: "calendar shorthand proposal",
    text: "下下個禮拜日下午兩點，法式甜點好嗎？",
    expected: true,
  },
  {
    id: "shorthand-027",
    root: "calendar shorthand proposal",
    text: "英式下午茶就排下個月第一個週末中午？",
    expected: true,
  },
  {
    id: "shorthand-031",
    root: "calendar shorthand proposal",
    text: "花藝市集，七月二十五號晚上七點可以嗎？",
    expected: true,
  },
  {
    id: "shorthand-033",
    root: "calendar shorthand proposal",
    text: "明天傍晚五點半黑盒子劇場？",
    expected: true,
  },
  {
    id: "shorthand-034",
    root: "calendar shorthand proposal",
    text: "下週末中午十二點，山城夜遊好嗎？",
    expected: true,
  },
  {
    id: "shorthand-035",
    root: "calendar shorthand proposal",
    text: "手沖咖啡就排這禮拜四午後三點？",
    expected: true,
  },
  {
    id: "shorthand-037",
    root: "calendar shorthand proposal",
    text: "要不要這個星期六晚上七點去森林健行？",
    expected: true,
  },
  {
    id: "shorthand-039",
    root: "calendar shorthand proposal",
    text: "不插電音樂會，下個月第一個週末中午可以嗎？",
    expected: true,
  },
  {
    id: "shorthand-040",
    root: "calendar shorthand proposal",
    text: "那星期三傍晚六點半二手書展吧？",
    expected: true,
  },
  {
    id: "shorthand-045",
    root: "calendar information query",
    text: "明天傍晚五點半湖畔野餐還有名額嗎？",
    expected: false,
  },
  {
    id: "shorthand-051",
    root: "calendar information query",
    text: "下個月第一個週末中午的陶藝體驗官網有公告嗎？",
    expected: false,
  },
  {
    id: "shorthand-059",
    root: "calendar information query",
    text: "這禮拜四午後三點的海岸散步官網有公告嗎？",
    expected: false,
  },
  {
    id: "shorthand-060",
    root: "calendar information query",
    text: "想問下個星期一晚間九點湖畔野餐還有名額嗎？",
    expected: false,
  },

  // constraint: 18 reliable frozen-baseline mismatches.
  {
    id: "constraint-001",
    root: "degree or pace constraint on active proposal",
    text: "下個禮拜二晚上我們一起去小劇場看場小戲，不用特別穿得太正式。",
    expected: true,
  },
  {
    id: "constraint-002",
    root: "degree or pace constraint on active proposal",
    text: "月底的星期五陪我到植物市集逛逛攤位，不要把行程排得太緊。",
    expected: true,
  },
  {
    id: "constraint-003",
    root: "degree or pace constraint on active proposal",
    text: "我想約妳明天下班後去音樂展演空間聽一場音樂會，別弄到太晚。",
    expected: true,
  },
  {
    id: "constraint-011",
    root: "degree or pace constraint on active proposal",
    text: "下個月第一個週末我們一起去森林步道拍幾張照片，別選得那麼遠。",
    expected: true,
  },
  {
    id: "constraint-013",
    root: "degree or pace constraint on active proposal",
    text: "我想約妳下星期六下午去小劇場看場小戲，不用特別穿得太正式。",
    expected: true,
  },
  {
    id: "constraint-017",
    root: "degree or pace constraint on active proposal",
    text: "月底的星期五陪我到港邊餐廳吃晚餐，別把氣氛搞得太隆重。",
    expected: true,
  },
  {
    id: "constraint-018",
    root: "degree or pace constraint on active proposal",
    text:
      "我想約妳明天下班後去音樂展演空間聽一場音樂會，不用約在那麼晚的時間。",
    expected: true,
  },
  {
    id: "constraint-022",
    root: "degree or pace constraint on active proposal",
    text: "本月最後一個週六陪我到海濱步道走一小段路，不要安排太多行程。",
    expected: true,
  },
  {
    id: "constraint-025",
    root: "degree or pace constraint on active proposal",
    text: "明晚八點我帶妳去小劇場看場小戲，不用特別穿得太正式。",
    expected: true,
  },
  {
    id: "constraint-032",
    root: "degree or pace constraint on active proposal",
    text: "月底的星期五陪我到爵士酒吧聽現場演出，別喝到太醉。",
    expected: true,
  },
  {
    id: "constraint-033",
    root: "degree or pace constraint on active proposal",
    text: "我想約妳明天下班後去山城夜市吃點宵夜，不用玩得太瘋。",
    expected: true,
  },
  {
    id: "constraint-034",
    root: "degree or pace constraint on active proposal",
    text: "下下週日上午一起到海濱步道走一小段路，不要安排太多行程。",
    expected: true,
  },
  {
    id: "constraint-037",
    root: "degree or pace constraint on active proposal",
    text: "本月最後一個週六陪我到小劇場看場小戲，不用特別穿得太正式。",
    expected: true,
  },
  {
    id: "constraint-050",
    root: "terminal cancellation control",
    text: "這個週末我帶妳去森林步道拍幾張照片，整個行程拿掉吧。",
    expected: false,
  },
  {
    id: "constraint-052",
    root: "terminal cancellation control",
    text: "本月最後一個週六陪我到音樂展演空間聽一場音樂會，不要安排這趟了。",
    expected: false,
  },
  {
    id: "constraint-055",
    root: "terminal cancellation control",
    text: "明晚八點我帶妳去老屋茶館吃份甜點，整個行程拿掉吧。",
    expected: false,
  },
  {
    id: "constraint-057",
    root: "terminal cancellation control",
    text: "這週四晚上陪我到海濱步道走一小段路，不要安排這趟了。",
    expected: false,
  },
  {
    id: "constraint-060",
    root: "terminal cancellation control",
    text: "本週日中午我帶妳去攝影藝廊看攝影作品，整個行程拿掉吧。",
    expected: false,
  },
];

const R15_ACTOR_AND_PURPOSE_REGRESSIONS:
  readonly R15ClassifierRegressionCase[] = [
    // explicit_dyad_owner_or_activity_not_composed: hasExplicitSharedOwner/OUTING_ACTION_PATTERN are closed vocabularies; temporal adjuncts can also be misread by hasThirdPartyPlan: 20 reliable frozen-baseline mismatches.
    {
      id: "actor-001",
      root:
        "explicit_dyad_owner_or_activity_not_composed: hasExplicitSharedOwner/OUTING_ACTION_PATTERN are closed vocabularies; temporal adjuncts can also be misread by hasThirdPartyPlan",
      text: "週三晚上要不要一起去聽現場爵士？",
      expected: true,
    },
    {
      id: "actor-002",
      root:
        "explicit_dyad_owner_or_activity_not_composed: hasExplicitSharedOwner/OUTING_ACTION_PATTERN are closed vocabularies; temporal adjuncts can also be misread by hasThirdPartyPlan",
      text: "有空跟我去苗圃看春天剛開的花？",
      expected: true,
    },
    {
      id: "actor-003",
      root:
        "explicit_dyad_owner_or_activity_not_composed: hasExplicitSharedOwner/OUTING_ACTION_PATTERN are closed vocabularies; temporal adjuncts can also be misread by hasThirdPartyPlan",
      text: "下週二我帶妳去試那家無菜單料理。",
      expected: true,
    },
    {
      id: "actor-004",
      root:
        "explicit_dyad_owner_or_activity_not_composed: hasExplicitSharedOwner/OUTING_ACTION_PATTERN are closed vocabularies; temporal adjuncts can also be misread by hasThirdPartyPlan",
      text: "今晚想不想跟我到操場慢跑幾圈？",
      expected: true,
    },
    {
      id: "actor-005",
      root:
        "explicit_dyad_owner_or_activity_not_composed: hasExplicitSharedOwner/OUTING_ACTION_PATTERN are closed vocabularies; temporal adjuncts can also be misread by hasThirdPartyPlan",
      text: "不然明晚一起去吃那間深夜粥店？",
      expected: true,
    },
    {
      id: "actor-006",
      root:
        "explicit_dyad_owner_or_activity_not_composed: hasExplicitSharedOwner/OUTING_ACTION_PATTERN are closed vocabularies; temporal adjuncts can also be misread by hasThirdPartyPlan",
      text: "乾脆週末跟我去逛二手唱片行。",
      expected: true,
    },
    {
      id: "actor-007",
      root:
        "explicit_dyad_owner_or_activity_not_composed: hasExplicitSharedOwner/OUTING_ACTION_PATTERN are closed vocabularies; temporal adjuncts can also be misread by hasThirdPartyPlan",
      text: "月底找你一起去參加香氛工作坊。",
      expected: true,
    },
    {
      id: "actor-008",
      root:
        "explicit_dyad_owner_or_activity_not_composed: hasExplicitSharedOwner/OUTING_ACTION_PATTERN are closed vocabularies; temporal adjuncts can also be misread by hasThirdPartyPlan",
      text: "妳明天下課後要不要和我去吃豆花？",
      expected: true,
    },
    {
      id: "actor-009",
      root:
        "explicit_dyad_owner_or_activity_not_composed: hasExplicitSharedOwner/OUTING_ACTION_PATTERN are closed vocabularies; temporal adjuncts can also be misread by hasThirdPartyPlan",
      text: "我準備週五載你到港邊看船。",
      expected: true,
    },
    {
      id: "actor-010",
      root:
        "explicit_dyad_owner_or_activity_not_composed: hasExplicitSharedOwner/OUTING_ACTION_PATTERN are closed vocabularies; temporal adjuncts can also be misread by hasThirdPartyPlan",
      text: "下週末我想跟妳去走一段淡蘭古道。",
      expected: true,
    },
    {
      id: "actor-011",
      root:
        "explicit_dyad_owner_or_activity_not_composed: hasExplicitSharedOwner/OUTING_ACTION_PATTERN are closed vocabularies; temporal adjuncts can also be misread by hasThirdPartyPlan",
      text: "下個月初我們到三峽逛老街。",
      expected: true,
    },
    {
      id: "actor-012",
      root:
        "explicit_dyad_owner_or_activity_not_composed: hasExplicitSharedOwner/OUTING_ACTION_PATTERN are closed vocabularies; temporal adjuncts can also be misread by hasThirdPartyPlan",
      text: "週日午後跟我去看陶作聯展，順便吃冰。",
      expected: true,
    },
    {
      id: "actor-013",
      root:
        "explicit_dyad_owner_or_activity_not_composed: hasExplicitSharedOwner/OUTING_ACTION_PATTERN are closed vocabularies; temporal adjuncts can also be misread by hasThirdPartyPlan",
      text: "今天晚一點陪我去唱兩首歌？",
      expected: true,
    },
    {
      id: "actor-014",
      root:
        "explicit_dyad_owner_or_activity_not_composed: hasExplicitSharedOwner/OUTING_ACTION_PATTERN are closed vocabularies; temporal adjuncts can also be misread by hasThirdPartyPlan",
      text: "明天八點來我工作室，我煮宵夜給妳吃。",
      expected: true,
    },
    {
      id: "actor-015",
      root:
        "explicit_dyad_owner_or_activity_not_composed: hasExplicitSharedOwner/OUTING_ACTION_PATTERN are closed vocabularies; temporal adjuncts can also be misread by hasThirdPartyPlan",
      text: "我有空時想陪妳去逛布市。",
      expected: true,
    },
    {
      id: "actor-016",
      root:
        "explicit_dyad_owner_or_activity_not_composed: hasExplicitSharedOwner/OUTING_ACTION_PATTERN are closed vocabularies; temporal adjuncts can also be misread by hasThirdPartyPlan",
      text: "明晚妳陪我到紀州庵聽詩歌朗讀。",
      expected: true,
    },
    {
      id: "actor-017",
      root:
        "explicit_dyad_owner_or_activity_not_composed: hasExplicitSharedOwner/OUTING_ACTION_PATTERN are closed vocabularies; temporal adjuncts can also be misread by hasThirdPartyPlan",
      text: "週四我接你下班，去看城市夜景。",
      expected: true,
    },
    {
      id: "actor-018",
      root:
        "explicit_dyad_owner_or_activity_not_composed: hasExplicitSharedOwner/OUTING_ACTION_PATTERN are closed vocabularies; temporal adjuncts can also be misread by hasThirdPartyPlan",
      text: "下週我們到鄰居阿姨家學包水餃。",
      expected: true,
    },
    {
      id: "actor-019",
      root:
        "explicit_dyad_owner_or_activity_not_composed: hasExplicitSharedOwner/OUTING_ACTION_PATTERN are closed vocabularies; temporal adjuncts can also be misread by hasThirdPartyPlan",
      text: "有空一起去找那位木工老師做托盤吧。",
      expected: true,
    },
    {
      id: "actor-020",
      root:
        "explicit_dyad_owner_or_activity_not_composed: hasExplicitSharedOwner/OUTING_ACTION_PATTERN are closed vocabularies; temporal adjuncts can also be misread by hasThirdPartyPlan",
      text: "晚點跟我去鄰居家看看那隻新領養的狗。",
      expected: true,
    },

    // physical_meeting_suppressed_by_content_guard: isContentOnly runs before explicit in-person owner/location evidence: 5 reliable frozen-baseline mismatches.
    {
      id: "actor-021",
      root:
        "physical_meeting_suppressed_by_content_guard: isContentOnly runs before explicit in-person owner/location evidence",
      text: "後天我們去妳家看演唱會回放。",
      expected: true,
    },
    {
      id: "actor-022",
      root:
        "physical_meeting_suppressed_by_content_guard: isContentOnly runs before explicit in-person owner/location evidence",
      text: "下班後來我家一起看紀錄片預告。",
      expected: true,
    },
    {
      id: "actor-023",
      root:
        "physical_meeting_suppressed_by_content_guard: isContentOnly runs before explicit in-person owner/location evidence",
      text: "月底我想帶妳去工作室看一場攝影直播。",
      expected: true,
    },
    {
      id: "actor-024",
      root:
        "physical_meeting_suppressed_by_content_guard: isContentOnly runs before explicit in-person owner/location evidence",
      text: "明天下午我帶你去看咖啡沖煮示範。",
      expected: true,
    },
    {
      id: "actor-025",
      root:
        "physical_meeting_suppressed_by_content_guard: isContentOnly runs before explicit in-person owner/location evidence",
      text: "月底我帶妳去看陶藝老師現場示範。",
      expected: true,
    },

    // reported_speech_scope_lost: completed-condition stripping can erase the reporter; contextual reporters are missed; freshTail mistakes object 我 inside reported speech for new user ownership: 19 reliable frozen-baseline mismatches.
    {
      id: "actor-026",
      root:
        "reported_speech_scope_lost: completed-condition stripping can erase the reporter; contextual reporters are missed; freshTail mistakes object 我 inside reported speech for new user ownership",
      text: "同事提過下班後一起喝一杯。",
      expected: false,
    },
    {
      id: "actor-027",
      root:
        "reported_speech_scope_lost: completed-condition stripping can erase the reporter; contextual reporters are missed; freshTail mistakes object 我 inside reported speech for new user ownership",
      text: "她在群組裡說下星期一起去桌遊店。",
      expected: false,
    },
    {
      id: "actor-028",
      root:
        "reported_speech_scope_lost: completed-condition stripping can erase the reporter; contextual reporters are missed; freshTail mistakes object 我 inside reported speech for new user ownership",
      text: "她原本跟我說明天下班後喝杯茶。",
      expected: false,
    },
    {
      id: "actor-029",
      root:
        "reported_speech_scope_lost: completed-condition stripping can erase the reporter; contextual reporters are missed; freshTail mistakes object 我 inside reported speech for new user ownership",
      text: "我只是引用她的話：明天一起去喝咖啡。",
      expected: false,
    },
    {
      id: "actor-030",
      root:
        "reported_speech_scope_lost: completed-condition stripping can erase the reporter; contextual reporters are missed; freshTail mistakes object 我 inside reported speech for new user ownership",
      text: "以下是朋友的原句：週末來我家吃飯吧。",
      expected: false,
    },
    {
      id: "actor-031",
      root:
        "reported_speech_scope_lost: completed-condition stripping can erase the reporter; contextual reporters are missed; freshTail mistakes object 我 inside reported speech for new user ownership",
      text: "聊天紀錄裡她說後天一起去海邊。",
      expected: false,
    },
    {
      id: "actor-032",
      root:
        "reported_speech_scope_lost: completed-condition stripping can erase the reporter; contextual reporters are missed; freshTail mistakes object 我 inside reported speech for new user ownership",
      text: "截圖中的男生問明晚要不要喝酒。",
      expected: false,
    },
    {
      id: "actor-033",
      root:
        "reported_speech_scope_lost: completed-condition stripping can erase the reporter; contextual reporters are missed; freshTail mistakes object 我 inside reported speech for new user ownership",
      text: "這是阿美的訊息：改天一起逛書店。",
      expected: false,
    },
    {
      id: "actor-034",
      root:
        "reported_speech_scope_lost: completed-condition stripping can erase the reporter; contextual reporters are missed; freshTail mistakes object 我 inside reported speech for new user ownership",
      text: "我在重述同事的邀請，星期五一起吃晚餐。",
      expected: false,
    },
    {
      id: "actor-035",
      root:
        "reported_speech_scope_lost: completed-condition stripping can erase the reporter; contextual reporters are missed; freshTail mistakes object 我 inside reported speech for new user ownership",
      text: "小說角色對她說下次一起看日出。",
      expected: false,
    },
    {
      id: "actor-036",
      root:
        "reported_speech_scope_lost: completed-condition stripping can erase the reporter; contextual reporters are missed; freshTail mistakes object 我 inside reported speech for new user ownership",
      text: "範例對話中男方說明天一起吃飯。",
      expected: false,
    },
    {
      id: "actor-037",
      root:
        "reported_speech_scope_lost: completed-condition stripping can erase the reporter; contextual reporters are missed; freshTail mistakes object 我 inside reported speech for new user ownership",
      text: "我想傳給她的草稿是：週末一起去看展吧。",
      expected: false,
    },
    {
      id: "actor-038",
      root:
        "reported_speech_scope_lost: completed-condition stripping can erase the reporter; contextual reporters are missed; freshTail mistakes object 我 inside reported speech for new user ownership",
      text: "教練示範的句子是下週一起吃晚餐嗎。",
      expected: false,
    },
    {
      id: "actor-039",
      root:
        "reported_speech_scope_lost: completed-condition stripping can erase the reporter; contextual reporters are missed; freshTail mistakes object 我 inside reported speech for new user ownership",
      text: "筆記抄著她說的話，明晚一起散步。",
      expected: false,
    },
    {
      id: "actor-040",
      root:
        "reported_speech_scope_lost: completed-condition stripping can erase the reporter; contextual reporters are missed; freshTail mistakes object 我 inside reported speech for new user ownership",
      text: "錄音裡阿德說後天一起去逛街。",
      expected: false,
    },
    {
      id: "actor-041",
      root:
        "reported_speech_scope_lost: completed-condition stripping can erase the reporter; contextual reporters are missed; freshTail mistakes object 我 inside reported speech for new user ownership",
      text: "節目主持人提議觀眾週末一起野餐。",
      expected: false,
    },
    {
      id: "actor-042",
      root:
        "reported_speech_scope_lost: completed-condition stripping can erase the reporter; contextual reporters are missed; freshTail mistakes object 我 inside reported speech for new user ownership",
      text: "教練說隊長後天會陪我跑步。",
      expected: false,
    },
    {
      id: "actor-043",
      root:
        "reported_speech_scope_lost: completed-condition stripping can erase the reporter; contextual reporters are missed; freshTail mistakes object 我 inside reported speech for new user ownership",
      text: "她傳明天一起喝咖啡，是在暗示什麼？",
      expected: false,
    },
    {
      id: "actor-044",
      root:
        "reported_speech_scope_lost: completed-condition stripping can erase the reporter; contextual reporters are missed; freshTail mistakes object 我 inside reported speech for new user ownership",
      text: "主管說下班一起吃飯，我需要答應嗎？",
      expected: false,
    },

    // meta_envelope_allowlist_gap: isWholeMessageMetaInviteWording relies on a narrow prefix/quality vocabulary and later invite-looking text reactivates the message: 25 reliable frozen-baseline mismatches.
    {
      id: "actor-045",
      root:
        "meta_envelope_allowlist_gap: isWholeMessageMetaInviteWording relies on a narrow prefix/quality vocabulary and later invite-looking text reactivates the message",
      text: "請幫我把明天一起喝茶改得自然一點。",
      expected: false,
    },
    {
      id: "actor-046",
      root:
        "meta_envelope_allowlist_gap: isWholeMessageMetaInviteWording relies on a narrow prefix/quality vocabulary and later invite-looking text reactivates the message",
      text: "我在草稿寫週末一起看展，這句好嗎？",
      expected: false,
    },
    {
      id: "actor-047",
      root:
        "meta_envelope_allowlist_gap: isWholeMessageMetaInviteWording relies on a narrow prefix/quality vocabulary and later invite-looking text reactivates the message",
      text: "約會文案想放下週一起吃飯。",
      expected: false,
    },
    {
      id: "actor-048",
      root:
        "meta_envelope_allowlist_gap: isWholeMessageMetaInviteWording relies on a narrow prefix/quality vocabulary and later invite-looking text reactivates the message",
      text: "回覆模板可以寫改天陪妳逛街嗎？",
      expected: false,
    },
    {
      id: "actor-049",
      root:
        "meta_envelope_allowlist_gap: isWholeMessageMetaInviteWording relies on a narrow prefix/quality vocabulary and later invite-looking text reactivates the message",
      text: "幫我校對後天一起去海邊這段邀請。",
      expected: false,
    },
    {
      id: "actor-050",
      root:
        "meta_envelope_allowlist_gap: isWholeMessageMetaInviteWording relies on a narrow prefix/quality vocabulary and later invite-looking text reactivates the message",
      text: "範例句可以用週五一起喝咖啡嗎？",
      expected: false,
    },
    {
      id: "actor-051",
      root:
        "meta_envelope_allowlist_gap: isWholeMessageMetaInviteWording relies on a narrow prefix/quality vocabulary and later invite-looking text reactivates the message",
      text: "備忘錄記著月底一起吃火鍋。",
      expected: false,
    },
    {
      id: "actor-052",
      root:
        "meta_envelope_allowlist_gap: isWholeMessageMetaInviteWording relies on a narrow prefix/quality vocabulary and later invite-looking text reactivates the message",
      text: "請替週末一起去聽音樂會打分。",
      expected: false,
    },
    {
      id: "actor-053",
      root:
        "meta_envelope_allowlist_gap: isWholeMessageMetaInviteWording relies on a narrow prefix/quality vocabulary and later invite-looking text reactivates the message",
      text: "下週陪妳看展這個說法會太油嗎？",
      expected: false,
    },
    {
      id: "actor-054",
      root:
        "meta_envelope_allowlist_gap: isWholeMessageMetaInviteWording relies on a narrow prefix/quality vocabulary and later invite-looking text reactivates the message",
      text: "後天一起去市集怎麼說比較好？",
      expected: false,
    },
    {
      id: "actor-055",
      root:
        "meta_envelope_allowlist_gap: isWholeMessageMetaInviteWording relies on a narrow prefix/quality vocabulary and later invite-looking text reactivates the message",
      text: "可以說週末帶妳去看展嗎？",
      expected: false,
    },
    {
      id: "actor-056",
      root:
        "meta_envelope_allowlist_gap: isWholeMessageMetaInviteWording relies on a narrow prefix/quality vocabulary and later invite-looking text reactivates the message",
      text: "建議回她改天一起吃甜點嗎？",
      expected: false,
    },
    {
      id: "actor-057",
      root:
        "meta_envelope_allowlist_gap: isWholeMessageMetaInviteWording relies on a narrow prefix/quality vocabulary and later invite-looking text reactivates the message",
      text: "替我潤飾下班後一起散步。",
      expected: false,
    },
    {
      id: "actor-058",
      root:
        "meta_envelope_allowlist_gap: isWholeMessageMetaInviteWording relies on a narrow prefix/quality vocabulary and later invite-looking text reactivates the message",
      text: "請評估月底一起泡湯這個邀法。",
      expected: false,
    },
    {
      id: "actor-059",
      root:
        "meta_envelope_allowlist_gap: isWholeMessageMetaInviteWording relies on a narrow prefix/quality vocabulary and later invite-looking text reactivates the message",
      text: "這段話是測試資料：明天一起看展。",
      expected: false,
    },
    {
      id: "actor-060",
      root:
        "meta_envelope_allowlist_gap: isWholeMessageMetaInviteWording relies on a narrow prefix/quality vocabulary and later invite-looking text reactivates the message",
      text: "系統範例輸入為週末陪妳去海邊。",
      expected: false,
    },
    {
      id: "actor-061",
      root:
        "meta_envelope_allowlist_gap: isWholeMessageMetaInviteWording relies on a narrow prefix/quality vocabulary and later invite-looking text reactivates the message",
      text: "投影片上的例句是明晚一起散步。",
      expected: false,
    },
    {
      id: "actor-062",
      root:
        "meta_envelope_allowlist_gap: isWholeMessageMetaInviteWording relies on a narrow prefix/quality vocabulary and later invite-looking text reactivates the message",
      text: "先記錄一句月底一起吃燒肉。",
      expected: false,
    },
    {
      id: "actor-063",
      root:
        "meta_envelope_allowlist_gap: isWholeMessageMetaInviteWording relies on a narrow prefix/quality vocabulary and later invite-looking text reactivates the message",
      text: "收藏的文案是有空帶妳去喝咖啡。",
      expected: false,
    },
    {
      id: "actor-064",
      root:
        "meta_envelope_allowlist_gap: isWholeMessageMetaInviteWording relies on a narrow prefix/quality vocabulary and later invite-looking text reactivates the message",
      text: "這是角色扮演台詞：後天一起逛夜市。",
      expected: false,
    },
    {
      id: "actor-065",
      root:
        "meta_envelope_allowlist_gap: isWholeMessageMetaInviteWording relies on a narrow prefix/quality vocabulary and later invite-looking text reactivates the message",
      text: "測試機器人是否能辨識明天一起喝茶。",
      expected: false,
    },
    {
      id: "actor-066",
      root:
        "meta_envelope_allowlist_gap: isWholeMessageMetaInviteWording relies on a narrow prefix/quality vocabulary and later invite-looking text reactivates the message",
      text: "不要真的約她，我只想改寫週六一起看展。",
      expected: false,
    },
    {
      id: "actor-067",
      root:
        "meta_envelope_allowlist_gap: isWholeMessageMetaInviteWording relies on a narrow prefix/quality vocabulary and later invite-looking text reactivates the message",
      text: "我沒有要邀妳，只是在寫改天一起吃飯的文案。",
      expected: false,
    },
    {
      id: "actor-068",
      root:
        "meta_envelope_allowlist_gap: isWholeMessageMetaInviteWording relies on a narrow prefix/quality vocabulary and later invite-looking text reactivates the message",
      text: "先別執行，草稿內容是下週陪你散步。",
      expected: false,
    },
    {
      id: "actor-069",
      root:
        "meta_envelope_allowlist_gap: isWholeMessageMetaInviteWording relies on a narrow prefix/quality vocabulary and later invite-looking text reactivates the message",
      text: "純粹做語氣練習：明晚我帶妳去看夜景。",
      expected: false,
    },

    // partner_with_third_party_misattributed_to_user: calendar/question fallback sees an activity without requiring the user to be a participant: 2 reliable frozen-baseline mismatches.
    {
      id: "actor-070",
      root:
        "partner_with_third_party_misattributed_to_user: calendar/question fallback sees an activity without requiring the user to be a participant",
      text: "明天妳跟阿凱去看展吧。",
      expected: false,
    },
    {
      id: "actor-071",
      root:
        "partner_with_third_party_misattributed_to_user: calendar/question fallback sees an activity without requiring the user to be a participant",
      text: "月底妳和小安去聽演唱會？",
      expected: false,
    },

    // administrative_purpose_allowlist_gap: 帶/載你 forms ownership before unmatched admin purpose is rejected: 2 reliable frozen-baseline mismatches.
    {
      id: "actor-072",
      root:
        "administrative_purpose_allowlist_gap: 帶/載你 forms ownership before unmatched admin purpose is rejected",
      text: "月底我載你去監理站驗機車。",
      expected: false,
    },
    {
      id: "actor-073",
      root:
        "administrative_purpose_allowlist_gap: 帶/載你 forms ownership before unmatched admin purpose is rejected",
      text: "週五我帶你去銀行辦轉帳。",
      expected: false,
    },

    // ordered_fresh_invite_not_reactivated: report future tokens, discourse connectors, double-negative continuations, and replacement targets are closed enumerations: 6 reliable frozen-baseline mismatches.
    {
      id: "actor-074",
      root:
        "ordered_fresh_invite_not_reactivated: report future tokens, discourse connectors, double-negative continuations, and replacement targets are closed enumerations",
      text: "同事說他想看展；至於我們，下星期一起去聽演唱會吧。",
      expected: true,
    },
    {
      id: "actor-075",
      root:
        "ordered_fresh_invite_not_reactivated: report future tokens, discourse connectors, double-negative continuations, and replacement targets are closed enumerations",
      text: "我自己去看電影的計畫取消；明晚改跟妳去聽音樂。",
      expected: true,
    },
    {
      id: "actor-076",
      root:
        "ordered_fresh_invite_not_reactivated: report future tokens, discourse connectors, double-negative continuations, and replacement targets are closed enumerations",
      text: "我媽說週末有事；不然我們下週一起去看海。",
      expected: true,
    },
    {
      id: "actor-077",
      root:
        "ordered_fresh_invite_not_reactivated: report future tokens, discourse connectors, double-negative continuations, and replacement targets are closed enumerations",
      text: "不是不願意帶你去海邊，只是改成星期六早上。",
      expected: true,
    },
    {
      id: "actor-078",
      root:
        "ordered_fresh_invite_not_reactivated: report future tokens, discourse connectors, double-negative continuations, and replacement targets are closed enumerations",
      text: "沒有不肯陪你逛書店，只是要挪到後天。",
      expected: true,
    },
    {
      id: "actor-079",
      root:
        "ordered_fresh_invite_not_reactivated: report future tokens, discourse connectors, double-negative continuations, and replacement targets are closed enumerations",
      text: "先把原本的咖啡局取消掉，改到星期日碰面。",
      expected: true,
    },

    // past_or_habit_scope_gap: past-self, habitual-past, and past-partner-report grammars do not cover these natural forms: 4 reliable frozen-baseline mismatches.
    {
      id: "actor-080",
      root:
        "past_or_habit_scope_gap: past-self, habitual-past, and past-partner-report grammars do not cover these natural forms",
      text: "前一個季度我跟你去海邊散步。",
      expected: false,
    },
    {
      id: "actor-081",
      root:
        "past_or_habit_scope_gap: past-self, habitual-past, and past-partner-report grammars do not cover these natural forms",
      text: "咱們過去總會一起看球賽。",
      expected: false,
    },
    {
      id: "actor-082",
      root:
        "past_or_habit_scope_gap: past-self, habitual-past, and past-partner-report grammars do not cover these natural forms",
      text: "去年妳問過我週末要不要爬山。",
      expected: false,
    },
    {
      id: "actor-083",
      root:
        "past_or_habit_scope_gap: past-self, habitual-past, and past-partner-report grammars do not cover these natural forms",
      text: "我曾打算和妳喝茶，只是最後沒去。",
      expected: false,
    },

    // terminal_retraction_variant_gap: terminal cancellation grammar misses generic 那句話作廢 and 我只是隨口說的: 2 reliable frozen-baseline mismatches.
    {
      id: "actor-084",
      root:
        "terminal_retraction_variant_gap: terminal cancellation grammar misses generic 那句話作廢 and 我只是隨口說的",
      text: "月底我約妳看展，那句話作廢。",
      expected: false,
    },
    {
      id: "actor-085",
      root:
        "terminal_retraction_variant_gap: terminal cancellation grammar misses generic 那句話作廢 and 我只是隨口說的",
      text: "有空一起吃飯，我只是隨口說的。",
      expected: false,
    },
  ];

const R15_CONTRACT_REGRESSIONS: readonly R15ClassifierRegressionCase[] = [
  {
    id: "contract-content-denial",
    root: "explicit denial after content-only discussion",
    text: "我只是想先閱讀松菸文創園區的語音導覽腳本，沒有在約妳。",
    expected: false,
  },
  {
    id: "contract-colloquial-outing",
    root: "colloquial shared outing without a named venue",
    text: "週末出來走走吧。",
    expected: true,
  },
  {
    id: "contract-topic-followup",
    root: "activity topic followed by a concrete partner invitation",
    text: "這場攝影展看起來不錯，週六妳要一起嗎？",
    expected: true,
  },
  {
    id: "contract-reported-assistant",
    root:
      "assistant's reported invitation must not become the user's invitation",
    text: "攝影課助教阿哲問我後天要不要一起去松菸文創園區晃一下。",
    expected: false,
  },
  {
    id: "contract-retraction-not-proposed",
    root: "contract-root completion for a terminal withdrawal",
    text: "明晚我們一起去看展，不過請當作我沒提出。",
    expected: false,
  },
  {
    id: "contract-retraction-void",
    root: "contract-root completion for a terminal withdrawal",
    text: "週末一起吃飯，不過那句邀請作廢。",
    expected: false,
  },
  {
    id: "contract-research-station-escort",
    root: "explicit partner escort to a research venue",
    text: "明天下午我帶妳去森林植物研究站拍幾張照片，妳看如何？",
    expected: true,
  },
];

function assertR15ClassifierCases(
  cases: readonly R15ClassifierRegressionCase[],
): void {
  for (const testCase of cases) {
    assertEquals(
      looksLikeGameSoftInvite(testCase.text),
      testCase.expected,
      `${testCase.id} [${testCase.root}]: ${testCase.text}`,
    );
  }
}

Deno.test("R15 game invite scanner locks 172 reliable grammar audit mismatches", () => {
  assertEquals(R15_GRAMMAR_REGRESSIONS.length, 172);
  assertR15ClassifierCases(R15_GRAMMAR_REGRESSIONS);
});

Deno.test("R15 game invite scanner locks 85 reliable actor and purpose audit mismatches", () => {
  assertEquals(R15_ACTOR_AND_PURPOSE_REGRESSIONS.length, 85);
  assertR15ClassifierCases(R15_ACTOR_AND_PURPOSE_REGRESSIONS);
});

Deno.test("R15 game invite scanner locks generation-contract reproductions", () => {
  assertEquals(R15_CONTRACT_REGRESSIONS.length, 7);
  assertR15ClassifierCases(R15_CONTRACT_REGRESSIONS);
});

Deno.test("R15 guard repairs preserve 60 fresh current dyad invitations", () => {
  const escapedGuardEnvelopes = [
    {
      root: "meta wording guard",
      prefix: "草稿內容我已經刪掉；至於我們，",
    },
    {
      root: "reported-speech guard",
      prefix: "助教轉述的那句話已經結束；換我問妳，",
    },
    {
      root: "historical-scope guard",
      prefix: "去年那次沒有成行；但這一次，",
    },
    {
      root: "content-only guard",
      prefix: "語音導覽腳本已經讀完；現在，",
    },
    {
      root: "administrative-purpose guard",
      prefix: "銀行的事情也辦完了；接著，",
    },
  ] as const;
  const freshDyadInvites = [
    "明晚我們一起去看展吧。",
    "週六妳要跟我去逛書店嗎？",
    "後天下午我帶妳去植物園拍照。",
    "月底我們一起到河岸咖啡館喝杯咖啡。",
    "下週日下午陪我去花市走走。",
    "今晚想不想跟我去聽現場音樂？",
    "下個月第一個週末我載妳去海邊看夕陽。",
    "這週四晚上咱們一起去看小劇場。",
    "明天下班後跟我去吃豆花好嗎？",
    "星期日早上我們一起去森林步道散步。",
    "七月二十五號晚上我陪妳去陶藝工坊。",
    "本月最後一個週六一起到港邊餐廳吃晚餐吧。",
  ] as const;

  let count = 0;
  for (const envelope of escapedGuardEnvelopes) {
    for (const invite of freshDyadInvites) {
      const text = `${envelope.prefix}${invite}`;
      assertEquals(
        looksLikeGameSoftInvite(text),
        true,
        `${envelope.root}: ${text}`,
      );
      count += 1;
    }
  }
  assertEquals(count, 60);
});

Deno.test("Game invite scanner recognizes replacements, escorts, and concise proposals", () => {
  const invites = [
    // A replacement after a cancellation is a new proposal.
    "上週取消的約明晚再約一杯？",
    "週末一起吃飯，算了，還是下週一起看電影。",
    "原本的咖啡取消，改成我們一起吃火鍋。",
    "原訂行程取消，改成我們一起吃飯。",
    "先取消咖啡，改成我們一起喝茶。",
    "不看電影了，改成我們一起逛街。",
    "咖啡作罷，改成我們一起吃甜點。",
    "吃飯取消，改成我們一起聚聚。",
    "明晚咖啡不要了，改去吃火鍋。",
    "不去酒吧了，換下週一起喝茶。",
    "明天不約了，之後有空再一起散步。",
    // Explicit dyad and escort ownership remain visible with generic destinations.
    "週末我帶妳去公園。",
    "下班後我陪妳去書店。",
    "我想帶妳去河濱。",
    "明晚我接妳去餐廳。",
    "週末我載你去海邊。",
    "有空我陪你去那間店。",
    "帶我去妳喜歡的店吧。",
    // Future callbacks may elide the noun established by prior context.
    "之前沒吃到那家，改天跟你去吃。",
    "上次沒吃成，下次跟你去吃。",
    "之前沒喝到，改天和妳去喝。",
    "昨天沒看成，週末跟你去看。",
    "剛才沒玩到，明天和你去玩。",
    "吃完這家，下次一起換一間。",
    // Subjectless modal and concise noun proposals are invitations.
    "週末要不要去逛市集？",
    "明晚咖啡？",
    "明早咖啡？",
    "明早見？",
    "明早碰面？",
    "週末電影？",
    "明天晚餐？",
    "後天展覽？",
    "這週末火鍋？",
    "下週酒吧？",
    "週六桌遊？",
    "今晚牛排？",
    "明晚拉麵",
    "週末壽司",
    "後天下午水族館",
    "週六博物館",
    "明晚演唱會？",
    "改天火鍋？",
    "週六七點牛排？",
    "週六八點電影？",
    "週日十一點早午餐？",
    "明天義大利麵？",
    "今晚居酒屋？",
    "週末餐酒館？",
    "明天披薩？",
    "下週冰店？",
    "明晚漢堡？",
    "明天咖哩？",
    "後天蛋糕？",
    "週六酒館？",
    "明晚貓咖？",
    "下週動物園？",
    "週末植物園？",
    "明天海生館？",
    "今晚夜景？",
    "改天吃義大利麵？",
    // The partner subject is safe when the utterance explicitly includes the dyad.
    "你週末要不要一起去逛市集？",
    "妳明天想不想跟我喝咖啡？",
    "你今晚要不要我陪你去看電影？",
    "你明天來我家吃晚餐？",
    "明天到我這裡。",
    "有空到我這兒？",
    "改天上我家？",
    "明天去你家吃火鍋。",
    "明晚到那間店吃燒肉。",
    "改天見。",
    "我想約你喝茶。",
    "我想邀妳週末看電影。",
    "我其實想邀你週六吃燒肉。",
    "我真的想跟妳去逛書店。",
    "我超想和你一起看展。",
    "我蠻想找你明晚去散步。",
    "我滿想跟你去聽演唱會。",
    "我倒是想約妳改天喝一杯。",
    "我超想約你週末喝咖啡。",
    "我有點想邀妳明晚看展。",
    "我其實想約妳下週吃晚餐。",
    "坦白講我想約你改天喝一杯。",
    "莫名想跟你一起去散步。",
    "老實講我想帶妳週末去海邊。",
    "我蠻想跟你下次吃火鍋。",
    "我好想跟你去散步。",
    "我真想和妳吃燒肉。",
    "突然好想跟你去散步。",
    "真的好想和妳吃宵夜。",
    "好想約你週末吃火鍋。",
    "我看明天去吃飯吧。",
    "下班後不然去喝一杯。",
    "不然去喝一杯吧。",
    "乾脆去看電影吧。",
    "要不要改天看個展？",
    "今晚來不來喝茶？",
    "話說妳明晚想不想一起喝咖啡？",
    "哈哈要不要一起喝咖啡？",
    "這樣要不要一起吃飯？",
    "認真說要不要一起去夜市？",
    "話說我們明天一起喝咖啡吧。",
    "是說改天要不要一起看展？",
    "欸嘿週末一起吃飯？",
    "或許改天一起喝咖啡。",
    "那就下次一起吃飯。",
    "Kevin說他不去；我想約妳明天吃飯。",
    "朋友說『週末一起看展』但我想跟你去喝咖啡。",
    "朋友說『明天一起喝咖啡』我改天約妳吃飯。",
    "同事問我『週末看電影』我明晚帶妳去夜市。",
    "朋友說：『明天一起喝咖啡。』我改天約妳去吃飯。",
    "同事問我：『週末看電影？』我想改天跟妳看展。",
    "阿明問我：『週末電影？』我改天跟妳去看展。",
    "zoe問我『要不要看展』，不過我明晚陪妳去看電影。",
    "amy說『明天咖啡』而我想和你週六吃火鍋。",
    "同事提到『週末電影』我則想找妳去看展。",
    "怡君說『她明天要上班』我則想跟你週末喝茶。",
    "昨天沒喝成下次跟你去喝。",
    "好想跟你一起喝咖啡。",
    "我想找你改天喝咖啡。",
    "朋友說：『明天她要看電影。』不過我想跟你改天喝咖啡。",
    "上週我問妳要不要看電影。不過我現在想約妳明天看展。",
    "昨天聊得很開心我想約妳明天吃飯。",
    "那天聊到夜市下次一起逛？",
    "前天妳說想散步今晚一起走走？",
    "我上週說改天一起看展，但現在想跟妳週末去散步。",
    "我之前約過她，這次想約你喝咖啡。",
    "上次沒有位子，週六我們再約一頓。",
    "另外我想約妳週六吃飯。",
    "晚點一起去兜風？",
    "明晚過來喝一杯。",
    "明晚見？",
    "明天一起吃飯，別約太晚。",
    "明天一起喝咖啡，不要太早。",
    "明天一起吃飯，先不要排太晚。",
    "明天一起吃飯，先不要排太滿。",
    "明天一起吃飯，別跟妳朋友說。",
    "週末可能去你家吃飯。",
    "明天應該去妳家。",
    "明晚直接去妳家。",
    "後天乾脆去你家。",
    "朋友沒空，但我週末去妳家。",
    "改天去山上兜風。",
    "下次再聚。",
    "下次聚餐。",
    "明天一起吃飯，不要遲到。",
    "打算約妳明晚吃飯。",
    "準備邀你週末看展。",
    "忍不住想約妳改天喝咖啡。",
    "真心想邀你下週吃晚餐。",
    "明天約會？",
    "週六19:30火鍋？",
    "7/24晚餐？",
    "7月24日晚上七點火鍋？",
    "有空來我工作室？",
    "改天到我住的地方喝茶？",
    "不是不想約妳，是想跟妳去看展。",
  ];

  for (const text of invites) {
    assertEquals(looksLikeGameSoftInvite(text), true, text);
  }
});

Deno.test("Game invite scanner preserves ordered invite transformations", () => {
  const proposals = [
    "明天一起喝咖啡",
    "週末要不要一起看展",
    "改天一起吃飯",
    "明晚約妳吃晚餐",
  ];
  const retractions = [
    "收回",
    "撤回",
    "不算",
    "別認真",
    "我隨口說的",
    "只是亂講",
    "說笑的",
    "鬧你的",
    "逗你的",
    "當作沒聽到",
    "先擱著",
    "暫緩",
    "先撤掉",
    "這回免了",
    "暫時作廢",
    "先別約",
    "先不要排",
    "行程先擱置",
    "暫且喊停",
    "先延後再說",
    "這回先免了",
    "先不要",
    "還是不要好了",
  ];
  for (const proposal of proposals) {
    assertEquals(looksLikeGameSoftInvite(`${proposal}。`), true, proposal);
    for (const retraction of retractions) {
      const text = `${proposal}，${retraction}。`;
      assertEquals(looksLikeGameSoftInvite(text), false, text);
    }
  }

  const replacements = [
    "改去吃火鍋",
    "改喝下午茶",
    "換下週一起看電影",
    "之後有空再一起散步",
  ];
  for (const replacement of replacements) {
    const text = `明晚咖啡不要了，${replacement}。`;
    assertEquals(looksLikeGameSoftInvite(text), true, text);
  }
});

Deno.test("Game invite scanner treats discourse prefixes as syntax, not actors", () => {
  const prefixes = [
    "最近",
    "週末的話",
    "順便問",
    "反正",
    "既然這樣",
    "有機會的話",
    "哪天方便的話",
    "有空的時候",
    "聽起來不錯",
    "問個問題",
  ];
  for (const prefix of prefixes) {
    const text = `${prefix}要不要一起喝咖啡？`;
    assertEquals(looksLikeGameSoftInvite(text), true, text);
  }

  const selfIntents = [
    "我其實想約妳明晚吃飯",
    "我真的想跟你週末看展",
    "我超想和妳一起散步",
    "我蠻想找你改天喝茶",
    "我滿想帶妳下週去海邊",
    "我倒是想邀你週六看電影",
    "我現在想約妳吃晚餐",
    "另外我想跟你去逛書店",
  ];
  for (const text of selfIntents) {
    assertEquals(looksLikeGameSoftInvite(text), true, text);
  }
});

Deno.test("Game invite scanner keeps reporter ownership while accepting fresh tails", () => {
  const actors = [
    "朋友",
    "咖啡店店員",
    "公司新來的同事",
    "怡君",
    "Amy",
  ];
  for (const actor of actors) {
    const quoted = `${actor}說「明天一起喝咖啡」`;
    const asked = `${actor}問我明天要不要一起看展`;
    assertEquals(looksLikeGameSoftInvite(quoted), false, quoted);
    assertEquals(looksLikeGameSoftInvite(asked), false, asked);
    const freshTail = `${quoted}，但我想約妳週末吃飯`;
    assertEquals(looksLikeGameSoftInvite(freshTail), true, freshTail);
  }

  const pastSelf = [
    "昨天我問妳明天要不要喝咖啡",
    "前天我告訴你週末一起看電影",
    "上週我約妳週末吃飯",
    "去年我邀你下週看展",
  ];
  for (const text of pastSelf) {
    assertEquals(looksLikeGameSoftInvite(text), false, text);
  }
});

Deno.test("Game invite scanner distinguishes shorthand from information", () => {
  const nouns = [
    "咖啡",
    "義大利麵",
    "居酒屋",
    "餐酒館",
    "披薩",
    "漢堡",
    "咖哩",
    "蛋糕",
    "貓咖",
    "動物園",
    "植物園",
    "海生館",
    "夜景",
  ];
  for (const noun of nouns) {
    const shorthand = `週六七點${noun}？`;
    assertEquals(looksLikeGameSoftInvite(shorthand), true, shorthand);
    for (const predicate of ["好吃嗎", "多少錢", "需要預約嗎", "人很多嗎"]) {
      const info = `週六七點${noun}${predicate}？`;
      assertEquals(looksLikeGameSoftInvite(info), false, info);
    }
  }

  for (
    const text of [
      "下週要預約餐廳嗎",
      "下次約會的意思是什麼",
      "明天大約七點嗎",
      "合約明天到期嗎",
      "週末工作嗎",
      "明天看牙醫嗎",
    ]
  ) {
    assertEquals(looksLikeGameSoftInvite(text), false, text);
  }
});

Deno.test("Game invite scanner closes adversarial grammar boundaries", () => {
  const nonInvites = [
    "不是不想約妳，是想跟妳聊展覽。",
    "沒有要約妳，只是想和妳討論咖啡。",
    "不是邀妳，只是想跟妳分享電影。",
    "早先我提議週末一起逛書店。",
    "稍早我提議週末一起逛書店。",
    "當時我提議週末一起逛書店。",
    "那時我提議週末一起逛書店。",
    "先前我想約妳週末吃飯。",
    "之前我打算約妳週末吃飯。",
    "當時我約妳週末吃飯。",
    "那時我邀你下週看展。",
    "先前我說週末看展，現在想跟妳聊電影。",
    "明天一起喝咖啡，先別排。",
    "明天一起喝咖啡，暫且不排。",
    "明天一起喝咖啡，先延後。",
    "明天一起喝咖啡，延後再說。",
    "明天一起喝咖啡，先放著。",
    "明天一起喝咖啡，先緩緩。",
    "明天一起喝咖啡，先暫停。",
    "明天一起喝咖啡，這次先免了。",
    "明天一起喝咖啡，先不要排了吧。",
    "明天一起喝咖啡，行程暫時擱置。",
    "明天一起喝咖啡，暫且延後再說。",
    "明天一起喝咖啡，別喝咖啡了。",
    "明天一起看展，不看展了。",
    "明天一起吃飯，不吃飯了。",
    "明晚咖啡不要了，改看狀況。",
    "明晚咖啡不要了，改天再說。",
    "明晚咖啡不要了，改期再說。",
    "明晚咖啡不要了，改成取消。",
    "明晚咖啡不要了，改成她去。",
    "明晚咖啡不要了，改週六有事。",
    "週末一起去辦簽證？",
    "週末一起去換駕照？",
    "週末一起去剪頭髮？",
    "週末一起去搬家？",
    "週末一起去看房？",
    "週末一起去驗車？",
    "週末一起去買手機？",
    "週末一起去投票？",
    "週末一起去打疫苗？",
    "週末一起去做體檢？",
    "明天來福去妳家吃飯。",
    "週末看護去你家喝茶。",
    "後天阿來到我家看電影。",
    "明晚王見明去妳家吃飯。",
    "週末跑者來我家喝咖啡。",
    "如果我說下次一起看展，會太直接嗎？",
    "要是說下次一起看展會太直接嗎？",
    "說下次一起看展會太直接嗎？",
    "下次一起看展這句會太直接嗎？",
    "我這樣約妳看展會太直接嗎？",
    "如果說下次一起看展合適嗎？",
    "下次邀約文案怎麼寫？",
    "下次一起看展會太直接嗎？",
    "要是說改天吃飯會太刻意嗎？",
    "下次節約用水。",
    "下次違約怎麼處理？",
    "下次契約再更新。",
    "下次條約討論。",
    "下次簡約設計。",
    "下次凝聚共識。",
    "下次聚變研究。",
    "改天去山上路況如何？",
    "改天去海邊交通方便嗎？",
    "改天山上好停車嗎？",
    "改天那間店有停車位嗎？",
    "改天去展覽怎麼走？",
    "改天去公園哪條路？",
    "明早早會？",
    "明早聚會？",
    "明早同業公會？",
  ];
  for (const text of nonInvites) {
    assertEquals(looksLikeGameSoftInvite(text), false, text);
  }

  const invites = [
    "並不是不想約妳，而是想跟妳去看展。",
    "不是不想約妳只是想跟妳去喝咖啡。",
    "只是想跟妳去看展。",
    "只是想跟妳去喝咖啡。",
    "先前我提議看電影，但現在想約妳週末看展。",
    "當時我約妳喝咖啡，不過現在想跟妳週末看展。",
    "先前我提議週末看展現在想約妳明晚吃飯。",
    "先前我提議週末看展而我現在想約妳明晚吃飯。",
    "先前我提議週末看展現在我想約妳明晚吃飯。",
    "明天一起吃飯，先不排太滿。",
    "明天一起吃飯，先別約太早。",
    "明天一起吃飯，先別約太晚。",
    "明天一起吃飯，先延後再說細節。",
    "明天一起吃飯，不要好高騖遠。",
    "明天一起吃飯，不要好奇太多。",
    "明天一起吃飯，還是不要好遠的店。",
    "明天一起吃飯，不要好幾點才來。",
    "明天一起喝咖啡，別喝太多。",
    "明天一起喝咖啡，不要喝太多。",
    "明天一起吃飯，別吃太辣。",
    "明晚咖啡不要了，改週六。",
    "明晚咖啡不要了，改到週六。",
    "明晚咖啡不要了，改成週六。",
    "明晚咖啡不要了，換週六。",
    "明晚咖啡不要了，延到週六。",
    "明晚咖啡不要了，延後到週六。",
    "明晚咖啡不要了，改明早。",
    "明晚咖啡不要了，改七點。",
    "明晚咖啡不要了，改週六七點。",
    "週末一起跑步，先不要排，改成早上。",
    "明晚咖啡取消，週六吧。",
    "週末先一起去辦護照再一起喝咖啡？",
    "週末先一起去辦護照然後一起喝咖啡？",
    "週末先一起去辦護照接著一起喝咖啡？",
    "明晚陪我去超商取貨再一起吃飯？",
    "明天跟我去修手機然後一起看電影？",
    "週末一起喝咖啡再去辦護照。",
    "明晚一起吃飯然後去超商取貨。",
    "明晚先取貨再一起喝咖啡。",
    "明晚一起喝咖啡順便取貨。",
    "明天雨停去妳家吃飯。",
    "週末忙完去你家喝茶。",
    "明晚收工去妳家吃飯。",
    "後天課後去你家看電影。",
    "明天方便的話去妳家喝茶。",
    "週末可以的話來我家吃飯。",
    "明晚沒事去妳家看電影。",
    "明天開完會去妳家吃飯。",
    "明天電影看完去你家喝茶。",
    "明晚順路來我家喝茶。",
    "後天終於去你家看電影。",
    "週末臨時去你家吃飯。",
    "如果說下次一起看展，可以嗎？",
    "我知道有點直接，但想約妳看展。",
    "如果我約妳下次看展，妳會答應嗎？",
    "改天路會塞也一起去山上？",
    "山上的路難走但我們一起去。",
    "明早音樂會？",
    "明早舞會？",
  ];
  for (const text of invites) {
    assertEquals(looksLikeGameSoftInvite(text), true, text);
  }
});

Deno.test("R12 game invite scanner locks R11 grammar regressions", () => {
  const nonInvites = [
    // Explicit retractions must clear the earlier proposal.
    "明晚一起去酒吧，我收回這個提議。",
    "下班後一起散步，這個邀請作廢。",
    "週六我們一起唱歌，先擱一擱。",
    "改天一起去泡湯，暫時取消行程。",
    "明晚一起吃拉麵，先別安排。",
    "後天我們去海邊兜風，先暫停一下。",
    "下次一起去野餐，當我沒提過。",
    "明早一起喝茶，剛剛那句不算數。",
    "週日下午一起看展，取消這個安排。",
    "週五一起吃晚餐，延後再決定。",
    "明晚碰個面吧，先緩一下。",
    "明天一起喝下午茶，先擱置這個行程。",
    "改天我帶妳去河濱，別當一回事。",
    "週日一起去美術館，我只是說著玩的。",
    // A double negative about content is not an invitation.
    "我不是不願意跟你喝咖啡，是想知道哪家好喝。",
    "並不是不願陪你看電影，只是想討論劇情。",
    // Past and reported proposals do not belong to the current user turn.
    "上個禮拜六我曾邀妳吃晚餐。",
    "那時我們打算週末一起吃飯。",
    "朋友的姊姊說明早一起喝咖啡。",
    // Draft, rewrite, and example frames describe wording rather than an outing.
    "要怎麼自然地說週末一起看展？",
    "請幫我改寫改天一起吃飯。",
    "我在草稿裡寫明天一起喝咖啡。",
    "筆記內容是下週一起逛夜市。",
    "範例可以用週六一起吃燒肉嗎？",
    "約會文案寫下週吃飯可以嗎？",
    "這句要不要改成改天一起喝茶？",
    "我只是舉例：明天一起吃飯。",
    // Directly negating the partner's participation is not a dyadic proposal.
    "後天別陪我逛夜市。",
  ];
  for (const text of nonInvites) {
    assertEquals(looksLikeGameSoftInvite(text), false, text);
  }

  const invites = [
    // Cancelling one slot and supplying another is a fresh proposal.
    "明晚咖啡先取消，改到週日中午。",
    "週五晚餐不要了，換到下週二晚上。",
    "下週一的飯局取消，延後到週三七點。",
    "明晚約會先撤回，改在週六下午。",
    "今天晚餐先不約，順延到明天晚上。",
    "週末咖啡暫停，延至下週日。",
    "明早見面取消，改約後天下午三點。",
    "週日看展先取消，那就改成下週六。",
    "明晚散步先不去了，換週末早上。",
    "下週咖啡局先喊停，改為週五晚餐。",
    "週末碰面先延後，改至下週三晚上。",
    "週日一起爬山先取消，延到下個週末。",
    "明晚一起吃飯先撤掉，另約週六晚上。",
    "今天的咖啡先作罷，改排後天下午。",
    "明天下午的展先不要，改在週五晚上看電影。",
    "今晚不碰面了，後天我們再見。",
    "週末散步取消，下週日早上吧。",
    "下班後的酒吧取消，改約週末吃晚餐。",
    "週日午餐先擱著，改到下週三中午。",
    // A double negative followed by affirmative intent remains an invitation.
    "我不是不想跟妳吃飯，是想改到週日晚上。",
    "我沒有不想約妳，只是明天太趕，改週五好嗎？",
    "我並不是不想和妳看展，只是想挑週末。",
    "並非不願陪妳去看電影，我想改成週六。",
    "我不是不打算約你，是打算下週去看展。",
    "不是不想一起喝茶，只是想約晚一點。",
    "並不是不想邀妳喝咖啡，而是想約週日下午。",
    "不是不想帶你去海邊，是想等週末。",
    // A past setup may still be followed by a fresh current proposal.
    "本來我想約你明天吃飯，這次我們改週五吧。",
    // Degree and pace constraints modify an active outing; they do not cancel it.
    "週末一起吃火鍋，不要吃那麼辣。",
    "明晚一起喝酒，別喝那麼多。",
    "週日一起散步，不要走太快。",
    "下班後一起小酌，別喝過頭。",
    "明晚一起吃拉麵，別吃太撐。",
    "週日一起去公園，不要跑太快。",
    // Time plus activity noun shorthand is itself a concise proposal.
    "本週六早上十點早午餐？",
    "下週四晚上九點酒吧？",
    "下週日早上十一點動物園？",
  ];
  for (const text of invites) {
    assertEquals(looksLikeGameSoftInvite(text), true, text);
  }
});

Deno.test("R12 game invite scanner locks R11 actor and purpose regressions", () => {
  const actors = [
    "咖啡師阿哲",
    "電影社社長",
    "桌遊團團長",
    "夜市攤販阿凱",
    "海邊救生員",
    "美術館導覽員",
    "跑團領隊阿傑",
    "登山社副社長",
    "酒吧調酒師",
    "餐廳外場小林",
    "展覽策展人小周",
    "書店老闆娘",
    "健身房櫃檯人員",
  ];

  for (const actor of actors) {
    const reportedSpeech = [
      `${actor}說明天一起喝咖啡吧。`,
      `${actor}問我週末要不要一起看展？`,
      `${actor}跟我講下週可以一起吃晚餐。`,
    ];
    const thirdPartyPlans = [
      `明晚${actor}陪我去酒吧。`,
      `下週${actor}跟我看展。`,
    ];
    for (const text of [...reportedSpeech, ...thirdPartyPlans]) {
      assertEquals(looksLikeGameSoftInvite(text), false, text);
    }
  }

  const nonInvites = [
    // Solo and third-party errands must not inherit dyadic ownership.
    "去完醫院後我自己散步。",
    "先買菜再去鄰居家做菜。",
    // Watching or listening to related content is not the corresponding outing.
    "明天一起看電影幕後花絮。",
    "下週我們看展覽介紹影片。",
    "今晚一起聽演唱會錄音檔。",
    "改天一起看桌遊教學影片。",
    "明天一起看那間書店的評論。",
    "週末一起看美術館官方網站。",
    "明晚一起看夜景照片集。",
    "下次一起看密室逃脫攻略。",
    "週日一起看市集宣傳海報。",
    "週末一起看球賽精華剪輯。",
    "下班後一起看拉麵店評價。",
    // Route and parking questions ask for information, not a meeting.
    "明天到展覽會場搭捷運方便嗎？",
    "去海邊應該走哪一條路？",
    "明天去那間店要從哪個出口？",
    "週末去夜市應該在哪站下車？",
    "明天去展覽要搭哪班公車？",
    "後天去書店附近能停機車嗎？",
    "週末去市集坐哪一路公車？",
  ];
  for (const text of nonInvites) {
    assertEquals(looksLikeGameSoftInvite(text), false, text);
  }

  const invites = [
    // Completed-context transitions can introduce a fresh current proposal.
    "電影看完我們去逛夜市。",
    "工作收尾後我找你喝茶。",
    // Incidental 到 and 預約 tokens must not be mistaken for actor/report frames.
    "合約到期後一起吃飯吧。",
    "預約完成後我們喝咖啡。",
    // A directive addressed to the partner can still propose a shared outing.
    "等妳忙完去喝杯茶吧。",
    "你下課後過來看電影吧。",
    "等妳下班去吃拉麵吧。",
  ];
  for (const text of invites) {
    assertEquals(looksLikeGameSoftInvite(text), true, text);
  }
});

Deno.test("R12 game invite scanner keeps cancellation replacements in the FSM phase", () => {
  const replacements = [
    "後天去海邊取消了，但改去書店逛逛。",
    "今晚碰面取消了，但改成明天下午。",
    "週末一起小酌取消了，但改成下星期。",
  ];
  for (const text of replacements) {
    assertEquals(looksLikeGameSoftInvite(text), true, text);
  }
});

Deno.test("R12 game invite scanner keeps structural fixes narrowly scoped", () => {
  const nonInvites = [
    // A replacement time alone cannot revive a solo or unrelated statement.
    "明晚咖啡豆不要了，改到週日中午再買。",
    "今天不碰面了，後天我自己再去。",
    "週末散步取消，下週日早上我要加班。",
    // Double negatives without affirmative outing intent remain non-invites.
    "我不是不想跟妳吃飯，是今天真的沒空。",
    "不是不想一起喝茶，只是想問你哪家茶好喝。",
    // Time shorthand must yield to explicit information questions.
    "本週六早上十點早午餐要訂位嗎？",
    "下週四晚上九點酒吧在哪裡？",
    "下週日早上十一點動物園交通方便嗎？",
    // Completed-context and directive grammar must preserve solo ownership.
    "工作收尾後我自己喝茶。",
    "電影看完我自己去逛夜市。",
    "合約到期後我自己吃飯。",
    "預約完成後我再回覆你。",
    "等妳忙完我去喝杯茶。",
    "你下課後自己去看電影吧。",
    // A contrast tail needs an actual replacement proposal.
    "後天去海邊取消了，但書店今天休息。",
    "今晚碰面取消了，但明天下午我要加班。",
    "週末一起小酌取消了，但下星期再聯絡。",
    // Reporter ownership remains false when the report itself is retracted.
    "咖啡師阿哲說明天一起喝咖啡吧，但他後來取消了。",
  ];
  for (const text of nonInvites) {
    assertEquals(looksLikeGameSoftInvite(text), false, text);
  }

  const invites = [
    // Constraints and affirmative double-negative replacements remain proposals.
    "明晚一起吃飯，先別安排太晚。",
    "我不是不願意跟你喝咖啡，是想改到週日。",
    // A fresh user-owned tail overrides earlier report or past context.
    "咖啡師阿哲說明天一起喝咖啡吧，但我想約妳週末看展。",
    "上個禮拜六我曾邀妳吃晚餐，這次我們改週五吧。",
    "朋友的姊姊說明早一起喝咖啡，但我想約妳後天喝茶。",
    // A completed meta frame may be followed by a real current proposal.
    "請幫我改寫這份文案，寫完後我們週末一起看展。",
    "我在草稿裡寫完了，明天一起喝咖啡吧。",
    "我只是舉例說明，接著我真的想約妳明天吃飯。",
    // Actor and negation guards must not hide explicit user/dyad ownership.
    "後天陪我逛夜市。",
    "我是美術館導覽員，週末一起看展吧。",
    "週末我們一起去找咖啡師阿哲。",
    // Content and route exclusions must preserve the actual activities.
    "明天一起看電影。",
    "下週我們一起看展。",
    "今晚一起去聽演唱會。",
    "改天一起玩桌遊。",
    "週末一起去美術館。",
    "明天我們一起去展覽會場，搭捷運吧。",
    "週末一起去夜市，在哪站下車再說。",
    // Sequence and directive forms remain invites with explicit shared ownership.
    "去完醫院後我們一起散步。",
    "先買菜再去你家一起做菜。",
    "等妳忙完我們去喝杯茶吧。",
    "你下課後過來一起看電影吧。",
  ];
  for (const text of invites) {
    assertEquals(looksLikeGameSoftInvite(text), true, text);
  }
});

Deno.test("R13 game invite scanner locks R12 release grammar mismatches", () => {
  const nonInvites = [
    // The complete utterance retracts its own proposal.
    "下週二我們一起去吃早午餐，先取消這一趟。",
    "下週二我們一起去吃早午餐，剛才的邀請請忽略。",
    "下週二我們一起去吃早午餐，這次行程不成立。",
    "下週二我們一起去吃早午餐，我決定撤銷剛才的安排。",
    "下週二我們一起去吃早午餐，先把這個約拿掉。",
    "下週二我們一起去吃早午餐，那句約妳的話作廢。",
    "週三晚上陪我去河邊散步，那句約妳的話作廢。",
    "這個星期日跟我去看攝影展，那句約妳的話作廢。",
    "月底一起去聽現場演出，那句約妳的話作廢。",
    "明天下午我帶妳去逛花市，先取消這一趟。",
    "明天下午我帶妳去逛花市，剛才的邀請請忽略。",
    "明天下午我帶妳去逛花市，這次行程不成立。",
    "明天下午我帶妳去逛花市，我決定撤銷剛才的安排。",
    "明天下午我帶妳去逛花市，先把這個約拿掉。",
    "明天下午我帶妳去逛花市，那句約妳的話作廢。",
    "下回一起去吃港式點心，那句約妳的話作廢。",
  ];

  const pastNarratives: Array<[string, string[]]> = [
    [
      "前一陣子的某天",
      [
        "我有邀你去看一場電影。",
        "我提過和你一起逛夜市。",
        "我原先打算陪妳去看展。",
      ],
    ],
    [
      "上上個週末",
      [
        "我曾經約妳去吃火鍋。",
        "我有邀你去看一場電影。",
        "我當時想找妳喝下午茶。",
        "我提過和你一起逛夜市。",
        "我原先打算陪妳去看展。",
        "我那時想帶你去海邊。",
      ],
    ],
    [
      "幾個月前",
      [
        "我有邀你去看一場電影。",
        "我提過和你一起逛夜市。",
        "我原先打算陪妳去看展。",
      ],
    ],
    [
      "上星期三下午",
      [
        "我曾經約妳去吃火鍋。",
        "我有邀你去看一場電影。",
        "我當時想找妳喝下午茶。",
        "我提過和你一起逛夜市。",
        "我原先打算陪妳去看展。",
        "我那時想帶你去海邊。",
      ],
    ],
  ];
  for (const [pastSource, narratives] of pastNarratives) {
    for (const narrative of narratives) {
      nonInvites.push(`${pastSource}${narrative}`);
    }
  }

  nonInvites.push(
    "這只是文案範本：明晚一起吃壽司吧。",
    "這只是文案範本：後天我帶妳去吃甜點。",
  );

  for (const text of nonInvites) {
    assertEquals(looksLikeGameSoftInvite(text), false, text);
  }

  const invites = [
    "星期二的晚餐先取消，另訂後天中午。",
    "本週四的咖啡先不約，另訂後天中午。",
    "明天下午的散步先作罷，另訂後天中午。",
    "原本週日的展覽先撤掉，另訂後天中午。",
    "今晚的見面先暫停，另訂後天中午。",
    "月底那頓飯先延後，改約下星期一晚上。",
    "月底那頓飯先延後，換成週六早上吧。",
    "月底那頓飯先延後，另訂後天中午。",
    "月底那頓飯先延後，順延到下個星期三。",
    "月底那頓飯先延後，改排這週日午後。",
    "月底那頓飯先延後，延至下週五七點。",
    "月底那頓飯先延後，那就改明晚吧。",
    "不是不打算找你喝咖啡，只是想改約下週六。",
    "不是不打算找你喝咖啡，而是想等到週日晚上。",
    "不是不打算找你喝咖啡，我想換成明晚七點。",
  ];

  const activeProposals = [
    "下週一起去吃燒肉",
    "明晚我們去唱歌",
    "週六陪我去爬山",
    "後天一起喝手沖咖啡",
    "這週日一起騎腳踏車",
    "下班後跟我吃宵夜",
    "週五晚上一起逛夜市",
  ];
  for (const proposal of activeProposals) {
    for (const constraint of ["不用弄得那麼正式。", "不用走得那麼急。"]) {
      invites.push(`${proposal}，${constraint}`);
    }
  }

  for (const noun of ["下午茶", "攝影展", "港式飲茶", "河濱公園"]) {
    invites.push(`下個週六早上九點${noun}？`);
    invites.push(`月底週日十一點${noun}？`);
  }

  for (const text of invites) {
    assertEquals(looksLikeGameSoftInvite(text), true, text);
  }
});

Deno.test("R13 game invite scanner locks R12 release actor and purpose mismatches", () => {
  const reporters = [
    "甜點師小琪",
    "攝影社副社長阿豪",
    "跑步教練小安",
    "餐酒館店長阿凱",
    "陶藝老師小美",
    "書店店員小傑",
    "健身房經理阿倫",
    "咖啡店服務生小雨",
    "桌遊店老闆阿雄",
    "登山隊領隊小陳",
    "水族館導覽員阿良",
    "電影社組長小周",
    "餐廳主管阿信",
  ];
  for (const reporter of reporters) {
    const text = `${reporter}傳訊息說明晚一起喝茶。`;
    assertEquals(looksLikeGameSoftInvite(text), false, text);
  }

  const invites = [
    "晚餐吃完後我找妳去河濱走走。",
    "咖啡喝完後一起去逛美術館。",
    "今晚我們一起去同事家看電影。",
    "週末我們一起去主管家喝茶。",
    "明晚我們一起去教練家吃宵夜。",
    "等妳看完展陪我去吃甜點吧。",
  ];
  for (const text of invites) {
    assertEquals(looksLikeGameSoftInvite(text), true, text);
  }
});

Deno.test("R13 game invite scanner locks R12 release integration mismatches", () => {
  const nonInvites = [
    "烘豆課講師阿倫傳話說明晚我們去河濱散步。",
    "影展志工小穎傳話說明晚我們去河濱散步。",
    "明晚我們一起看夜市攤位地圖，再聊聊內容。",
    "明晚我們一起看市集直播回放，再聊聊內容。",
    "後天去河濱入口從哪個捷運出口走？",
    "下週二晚上影展志工小穎陪我去河濱公園。",
    "週日早上我跟影展志工小穎一起去河濱公園。",
  ];
  for (const text of nonInvites) {
    assertEquals(looksLikeGameSoftInvite(text), false, text);
  }

  const invites = [
    "剛把手邊的事情忙完，不過後天下午我們一起聽一場爵士演出吧。",
    "去年我原本想邀妳一起喝咖啡，但這次我們改成本週六下午去吃晚餐。",
    "去年我原本想邀妳一起看攝影展，但這次我們改成下週二晚上去吃晚餐。",
    "去年我原本想邀妳一起吃壽司，但這次我們改成週日早上去吃晚餐。",
    "去年我原本想邀妳一起逛書店，但這次我們改成明晚去吃晚餐。",
    "去年我原本想邀妳一起走河濱，但這次我們改成後天下午去吃晚餐。",
    "去年我原本想邀妳一起看老電影，但這次我們改成這週末去吃晚餐。",
    "去年我原本想邀妳一起玩桌遊，但這次我們改成本週六下午去吃晚餐。",
    "去年我原本想邀妳一起吃拉麵，但這次我們改成下週二晚上去吃晚餐。",
    "去年我原本想邀妳一起逛市集，但這次我們改成週日早上去吃晚餐。",
    "去年我原本想邀妳一起看夜景，但這次我們改成明晚去吃晚餐。",
  ];
  for (const text of invites) {
    assertEquals(looksLikeGameSoftInvite(text), true, text);
  }
});

Deno.test("R13 game invite scanner keeps release fixes narrowly scoped", () => {
  const nonInvites = [
    // Quoting a proposal inside a retraction does not create a new proposal.
    "請幫我把「明晚一起吃飯」這句邀約撤回。",
    "我傳訊息說要撤回「週末一起看展」那句話。",
    // Completed past events and abandoned past intent remain narrative context.
    "前一陣子的某天我和她一起看過電影。",
    "上上個週末我們一起吃過火鍋。",
    "幾個月前我陪她去逛過夜市。",
    "去年我原本想邀妳喝咖啡，但後來沒有成行。",
    // Reschedule words require a concrete replacement proposal.
    "月底那頓飯先延後，改天再說。",
    "星期二的晚餐先取消，另訂哪一天再說。",
    // Expanded time shorthand must still yield to information predicates.
    "下個週六早上九點下午茶要訂位嗎？",
    "下個週六早上九點攝影展在哪裡？",
    "月底週日十一點港式飲茶要排隊嗎？",
    "月底週日十一點河濱公園怎麼去？",
    // 傳訊息說 is a report frame even without a catalogued professional role.
    "朋友傳訊息說週末要不要一起看展。",
    "主管傳訊息說後天下午一起喝咖啡。",
    // Content, navigation, and third-party ownership remain non-invites.
    "明晚一起研究夜市攤位地圖。",
    "後天河濱入口從哪個捷運出口走？",
    "下週二晚上影展志工小穎自己去河濱公園。",
    // A completed-context prefix must not erase explicit solo ownership.
    "剛把手邊事情忙完，我自己去吃飯。",
    // 不用了 is a retraction, unlike a degree constraint using 不用.
    "明晚一起吃飯，不用了，改天再說。",
  ];
  for (const text of nonInvites) {
    assertEquals(looksLikeGameSoftInvite(text), false, text);
  }

  const invites = [
    // 另訂 and 月底 reschedules remain active with a concrete replacement.
    "星期二的晚餐先取消，另訂後天中午一起吃。",
    "月底那頓飯先延後，改約下星期一晚上一起吃。",
    "月底的咖啡取消，另訂週六早上。",
    // Explicit dyad ownership survives a third party's home or participation.
    "後天我們一起去朋友家做菜。",
    "今晚陪我去同學家看球賽。",
    "下週二晚上我和妳一起陪影展志工小穎去河濱公園。",
    // Actual outings survive content and navigation vocabulary in a later clause.
    "明晚我們一起去夜市看攤位。",
    "明晚我們一起去市集逛逛。",
    "後天我們一起去河濱入口，從二號出口走吧。",
    // Past, report, and meta context may be followed by a fresh user proposal.
    "去年我原本想邀妳喝咖啡，但這次我們改成本週六下午吃晚餐。",
    "主管傳訊息說後天下午一起喝咖啡，但我想約妳週六看展。",
    "剛才撤回的是文案，但我現在想約妳明晚吃飯。",
    // Completed-context and degree constraints preserve a current shared outing.
    "剛把手邊事情忙完，我們一起去吃飯吧。",
    "明晚一起吃飯，不用穿得那麼正式。",
  ];
  for (const text of invites) {
    assertEquals(looksLikeGameSoftInvite(text), true, text);
  }
});

Deno.test("R14 game invite scanner locks R13 release grammar mismatches", () => {
  const nonInvites: string[] = [];
  const retractedProposals = [
    "下星期一晚上我們去吃泰國菜",
    "這週六我陪妳去看音樂劇",
    "後天下午一起到海邊看夕陽",
    "月中我帶你去逛創意市集",
  ];
  const retractionTails = [
    "先把這次邀約取消掉。",
    "請當作我沒有提出。",
    "這項安排現在撤銷。",
    "我收回方才的邀約。",
    "這趟計畫就不成立了。",
    "請忽略剛才約你的內容。",
  ];
  for (const proposal of retractedProposals) {
    for (const retraction of retractionTails) {
      nonInvites.push(`${proposal}，${retraction}`);
    }
  }

  nonInvites.push(
    "上個季度我提議過和你一起喝茶。",
    "前前個星期天我有約妳吃過晚餐。",
    "前前個星期天我曾邀你去逛過書店。",
    "前前個星期天我當時打算找妳看電影。",
    "前前個星期天我提議過和你一起喝茶。",
    "前前個星期天我原本想陪妳去海邊。",
    "前前個星期天我那時候想帶你看展。",
    "半年前我提議過和你一起喝茶。",
    "前一個月我提議過和你一起喝茶。",
    "請替我校對這段邀約：明天下午我載妳去海邊。",
  );

  for (const text of nonInvites) {
    assertEquals(looksLikeGameSoftInvite(text), false, text);
  }

  const invites = [
    "週三的午餐先喊停，那就挪到月底吧。",
    "明早的咖啡暫時取消，那就挪到月底吧。",
    "本月底的散步先不排，那就挪到月底吧。",
  ];
  const replacementTails = [
    "另訂下週二中午。",
    "改排後天傍晚。",
    "換到這星期六下午。",
    "順延至下週四八點。",
    "另約星期日早上。",
    "改在明晚碰面。",
    "延到下個週一。",
    "那就挪到月底吧。",
  ];
  for (
    const cancelled of [
      "下星期日晚餐先撤銷",
      "週五下午茶先往後延",
    ]
  ) {
    for (const replacement of replacementTails) {
      invites.push(`${cancelled}，${replacement}`);
    }
  }

  const doubleNegativeFrames: Array<[string, string[]]> = [
    [
      "我並不是不打算邀妳吃飯",
      [
        "而是希望排在週六晚上。",
        "只是打算晚一週再去。",
        "而是要等妳休假那天。",
      ],
    ],
    [
      "不是不願意找你看展",
      [
        "而是希望排在週六晚上。",
        "只是打算晚一週再去。",
        "而是要等妳休假那天。",
      ],
    ],
    [
      "我沒有不想帶妳去看夜景",
      [
        "而是希望排在週六晚上。",
        "只是打算晚一週再去。",
        "而是要等妳休假那天。",
      ],
    ],
    [
      "並非不肯陪你喝下午茶",
      [
        "只是想改成下星期四。",
        "而是希望排在週六晚上。",
        "我想換到後天午後。",
        "只是打算晚一週再去。",
        "而是要等妳休假那天。",
      ],
    ],
    [
      "我不是不想和妳逛花市",
      [
        "只是想改成下星期四。",
        "而是希望排在週六晚上。",
        "我想換到後天午後。",
        "只是打算晚一週再去。",
        "而是要等妳休假那天。",
      ],
    ],
    [
      "不是不願約你去聽音樂",
      [
        "而是希望排在週六晚上。",
        "只是打算晚一週再去。",
        "而是要等妳休假那天。",
      ],
    ],
  ];
  for (const [frame, tails] of doubleNegativeFrames) {
    for (const tail of tails) {
      invites.push(`${frame}，${tail}`);
    }
  }

  invites.push(
    "下星期一起吃韓國烤肉，別約得那麼匆忙。",
    "明天下班後我們去打保齡球，別約得那麼匆忙。",
  );
  const allConstraintTails = [
    "不用排到那麼晚。",
    "別弄得太隆重。",
    "不必走得這麼趕。",
    "不要安排得過於正式。",
    "不用待到太遲。",
    "別約得那麼匆忙。",
  ];
  for (
    const proposal of [
      "週日陪我去走步道",
      "晚上跟我去吃甜品",
      "週四一起逛花市",
    ]
  ) {
    for (const constraint of allConstraintTails) {
      invites.push(`${proposal}，${constraint}`);
    }
  }
  invites.push(
    "後天一起喝氣泡酒，別約得那麼匆忙。",
    "這星期六一起騎單車，別約得那麼匆忙。",
    "月底我們去看夜景，別約得那麼匆忙。",
  );

  invites.push(
    "這星期二晚上六點半河岸音樂會？",
    "下個星期四中午一點河岸音樂會？",
    "本週日早上八點河岸音樂會？",
    "下下週六下午三點當代藝術展？",
    "下下週六下午三點英式下午茶？",
    "下下週六下午三點河岸音樂會？",
    "後天晚上九點河岸音樂會？",
    "下週一傍晚五點河岸音樂會？",
    "月初週五七點當代藝術展？",
    "月初週五七點英式下午茶？",
    "月初週五七點河岸音樂會？",
    "月底星期六十點當代藝術展？",
    "月底星期六十點英式下午茶？",
    "月底星期六十點河岸音樂會？",
  );

  for (const text of invites) {
    assertEquals(looksLikeGameSoftInvite(text), true, text);
  }
});

Deno.test("R14 game invite scanner locks R13 release actor and purpose mismatches", () => {
  const invites = [
    "順帶一提，等你喝完咖啡跟我去看展吧。",
    "順帶一提，忙完這份工作後我們去海邊。",
    "順帶一提，喝完這杯茶後我們去逛書店。",
  ];

  const sharedDestinations = [
    "主管家",
    "教練家",
    "同事的店",
    "老師家",
    "學長家",
    "秘書家",
    "隊長住處",
    "店員家",
    "經理的餐廳",
    "室友家",
    "領隊住處",
  ];
  for (const destination of sharedDestinations) {
    invites.push(`順帶一提，下個星期我們一起去${destination}吃晚餐吧。`);
  }

  const peopleToVisit = [
    "插畫師小禾",
    "瑜伽教練阿青",
    "劇場經理小喬",
    "車隊領隊阿峰",
    "書店主管小寧",
    "甜品店員阿康",
    "展場志工小筑",
    "餐廳助理阿任",
    "樂團團長小晴",
    "泳隊副隊長阿修",
    "咖啡館外場小恩",
    "博物館導覽員阿東",
    "跑團班長小蓉",
    "旅館服務生阿嘉",
    "花藝師小凡",
  ];
  for (const person of peopleToVisit) {
    invites.push(`順帶一提，後天下午我帶妳去找${person}喝咖啡。`);
  }

  invites.push(
    "順帶一提，下禮拜一起去聽演唱會。",
    "順帶一提，禮拜六我們一起去保齡球館，交通晚點查。",
    "順帶一提，禮拜六我們一起去音樂廳，交通晚點查。",
    "順帶一提，禮拜六我們一起去攝影棚，交通晚點查。",
  );

  for (const text of invites) {
    assertEquals(looksLikeGameSoftInvite(text), true, text);
  }

  const nonInvites = [
    "順帶一提，等你看完電影自己去吃蛋糕吧。",
    "順帶一提，等妳吃完晚餐自己回家喝茶吧。",
    "順帶一提，看完這場展後我自己吃甜點。",
    "順帶一提，吃完這頓飯後我一個人去散步。",
    "順帶一提，妳看完電影自己在家吃宵夜吧。",
  ];
  for (const text of nonInvites) {
    assertEquals(looksLikeGameSoftInvite(text), false, text);
  }
});

Deno.test("R14 game invite scanner locks R13 release integration mismatches", () => {
  const invites = [
    "剛把會議記錄整理好；說真的，本週日中午我們一起去北美館看當代藝術，妳覺得呢？",
    "剛把會議記錄整理好；說真的，明天下午我們一起逛假日花市，妳覺得呢？",
    "剛把會議記錄整理好；說真的，本週日中午我們一起玩兩局桌上遊戲，妳覺得呢？",
    "剛把會議記錄整理好；說真的，明天下午我們一起去象山走步道，妳覺得呢？",
    "剛把會議記錄整理好；說真的，這週六傍晚我們一起聽小型不插電演出，妳覺得呢？",
    "剛把會議記錄整理好；說真的，本週日中午我們一起去海岸拍夕陽，妳覺得呢？",
    "週日逛花市先喊停；另訂下週三下午逛美術館。",
    "明晚的紀錄片先不看了；改成後天下午看攝影展。",
    "週末走步道先取消；換成下個週末去河濱騎車。",
    "本週五聚會先作罷；改成下週二一起吃印度菜。",
    "下星期三晚上我們一起去吃甜點再散步，但不要吃得太飽。",
    "我不是不願意約妳，只是想移到本週日中午。",
  ];
  for (const text of invites) {
    assertEquals(looksLikeGameSoftInvite(text), true, text);
  }

  const nonInvites = [
    "下星期三晚上我們一起去看舞台劇，我收回剛才的邀請。",
    "後天早上我們一起去看舞台劇，剛才是在說笑。",
    "後天早上我們一起去看舞台劇，先放一邊吧。",
    "下星期三晚上我們一起去看舞台劇，等以後再說吧。",
    "今晚我們一起看展覽語音導覽，只是整理資料。",
    "今晚我們一起看海邊即時影像，只是整理資料。",
    "今晚我們一起看書店電子報，只是整理資料。",
    "今晚我們一起看市集攤商名單，只是整理資料。",
    "今晚我們一起看電影演員訪談，只是整理資料。",
    "今晚我們一起看音樂會節目單，只是整理資料。",
    "今晚我們一起看博物館藏品清單，只是整理資料。",
    "今晚我們一起看夜景縮時攝影，只是整理資料。",
    "今晚我們一起看咖啡沖煮示範，只是整理資料。",
    "明天到陶藝教室最近的捷運站是哪個？",
    "後天早上我準備跟烘焙坊師傅阿凱一起逛茶樓。",
    "下星期三晚上我準備跟劇場外場人員一起逛美術館。",
    "備忘錄內容是下星期一起吃飯。",
    "請替這句打分：今晚一起看電影。",
    "把例句換成明晚一起逛書店。",
    "筆記上記著週日一起看夕陽。",
    "回覆模板可以放下週一起喝咖啡嗎？",
    "文案範本寫改天一起玩桌遊即可。",
  ];
  for (const text of nonInvites) {
    assertEquals(looksLikeGameSoftInvite(text), false, text);
  }
});

Deno.test("R14 game invite scanner keeps release repairs narrowly scoped", () => {
  const nonInvites = [
    // A proposal quoted as the target of a retraction must not restart itself.
    "我撤回的是「明晚一起吃飯」這句邀約。",
    "請忽略我剛才傳的「週末一起看展」。",
    "「後天一起去海邊」這項安排現在撤銷。",
    "我收回方才約你喝咖啡的內容。",
    "那句約妳吃晚餐的話作廢。",
    // Past and meta context without a fresh tail remain non-invites.
    "半年前我曾邀妳喝咖啡。",
    "上個季度我原本想陪你看展。",
    "請替我校對這段邀約：週末一起吃飯。",
    "這是邀約範本：後天一起看電影。",
    // Content tails are not promoted to their related real-world outings.
    "明晚一起看音樂廳座位圖，再聊聊內容。",
    "週末一起看展覽導覽影片，再做筆記。",
    "今晚一起看市集攤商名單，只是整理資料。",
    "後天一起看海邊即時影像，再討論畫面。",
    // Self plus a third party does not establish ownership by the addressed dyad.
    "下週我自己跟主管去他家吃飯。",
    "後天我一個人陪同事去看展。",
    "週末妳自己跟教練去喝咖啡。",
    "明晚我自己跟店員去吃宵夜。",
    // Completed-condition syntax must preserve an explicitly solo tail.
    "忙完這份工作後我自己去海邊。",
    "喝完這杯茶後我一個人逛書店。",
    "等你喝完咖啡自己去看展吧。",
    "會議結束後她跟同事去吃飯。",
    // Calendar plus venue shorthand remains subordinate to information predicates.
    "下禮拜音樂廳交通方便嗎？",
    "禮拜六保齡球館幾點開？",
    "月初攝影棚有空檔嗎？",
    "下下週河岸音樂會票價多少？",
    // These endings cancel the proposal rather than constrain its details.
    "週日一起走步道，不用了。",
    "明晚一起吃飯，不要安排了。",
    "後天一起喝酒，先取消。",
    "週末一起看展，等以後再說吧。",
  ];
  for (const text of nonInvites) {
    assertEquals(looksLikeGameSoftInvite(text), false, text);
  }

  const invites = [
    // A fresh current proposal can escape an earlier past or meta frame.
    "半年前我曾邀妳喝咖啡，但這次我們改約週六。",
    "上個季度我原本想陪你看展，現在則想約妳明晚看電影。",
    "文案已校對完，現在週末一起吃飯吧。",
    "這只是範本；至於我們，後天一起看電影吧。",
    // A real outing survives related content or navigation in a later clause.
    "明晚我們一起去音樂廳，座位圖晚點看。",
    "週末我們一起去看展，導覽影片回家再看。",
    "今晚一起去市集，攤商名單路上看。",
    "後天我們去海邊，到了再看即時影像。",
    // Explicit dyad ownership survives a third-party home or participant.
    "下週我們一起去主管家吃飯。",
    "後天我陪妳去同事家看展。",
    "週末妳跟我一起去教練家喝咖啡。",
    "明晚我們一起去找店員吃宵夜。",
    // Completed-condition syntax remains active with a shared tail.
    "忙完這份工作後我們去海邊。",
    "喝完這杯茶後一起逛書店吧。",
    "等你喝完咖啡跟我去看展吧。",
    "會議結束後我們一起吃飯。",
    // Generic calendar forms are valid when paired with an explicit dyad and venue.
    "下禮拜我們一起去音樂廳。",
    "禮拜六我們一起去保齡球館。",
    "月初我們一起去攝影棚。",
    "下下週我們一起去河岸音樂會。",
    // These endings constrain an active proposal rather than cancelling it.
    "週日一起走步道，不用走得太趕。",
    "明晚一起吃飯，不要安排得太正式。",
    "後天一起喝酒，別待到太晚。",
    "週末一起看展，別約得那麼匆忙。",
  ];
  for (const text of invites) {
    assertEquals(looksLikeGameSoftInvite(text), true, text);
  }
});
