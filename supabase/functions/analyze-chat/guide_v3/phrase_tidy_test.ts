// 「這題」「不怪」「滿→蠻」交給程式（phrase_tidy.ts，Bruce 2026-10-20 PR #97 再處理、先看例子）：
// 每一條的例子、受保護的字、拿掉後沒字就照原文、她沒問就不動、「滿」不動的詞。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  DEGREE_MAN_NEXT,
  HER_QUIZ_WORDS,
  MAN_COMPOUND_BEFORE,
  NO_PHRASE_TIDY_CHANGES,
  NOT_QUIZ_WORDS,
  type PhraseTidyContext,
  phraseTidyContext,
  QUIZ_FILLERS,
  QUIZ_MARKERS,
  tidyCard,
  tidyMessage,
  WORRY_WORDS,
} from "./phrase_tidy.ts";

/// 她問是不是最好看（沒有擔心的字、沒在講題目）。
const ASKS_BEST = phraseTidyContext({
  herLatest: ["欸 你覺得我今天是不是最好看的那個😏"],
  herMessages: ["今天部門聚餐", "欸 你覺得我今天是不是最好看的那個😏"],
});
/// 她剪了頭髮、問會不會很怪。
const ASKS_WEIRD = phraseTidyContext({
  herLatest: ["剪得比想像中短 有點後悔😂", "怎麼樣 會很怪嗎"],
  herMessages: [
    "有啊 跑去剪頭髮",
    "剪得比想像中短 有點後悔😂",
    "怎麼樣 會很怪嗎",
  ],
});
const tidy = (message: string, context: PhraseTidyContext = ASKS_BEST) =>
  tidyMessage(message, context).text;

Deno.test("Eric 2026-10-20 的三個例子：「是你啊 這題不用想」→「是你啊」、「不怪啊 很好看」→「很好看」、「滿適合」→「蠻適合」", () => {
  assertEquals(tidy("是你啊 這題不用想"), "是你啊");
  assertEquals(tidy("不怪啊 很好看", ASKS_WEIRD), "很好看");
  assertEquals(tidy("滿適合"), "蠻適合");
});

Deno.test("常數：考題字、她在講題目的字、題材不算；擔心的字是怪、醜、胖；滿的白名單與連成詞的字", () => {
  assertEquals(QUIZ_MARKERS, [
    "這題",
    "這一題",
    "這道題",
    "送分題",
    "這個答案",
  ]);
  assertEquals(NOT_QUIZ_WORDS, ["這題材"]);
  assert(HER_QUIZ_WORDS.includes("題目"));
  assertEquals(QUIZ_FILLERS.length, 12);
  for (const filler of ["這題不用想", "這題我不用想", "這個答案很穩"]) {
    assert(QUIZ_FILLERS.includes(filler), filler);
  }
  assertEquals(WORRY_WORDS.map((w) => w.her), ["怪", "醜", "胖"]);
  for (
    const word of ["適合", "好看", "可愛", "喜歡", "加分", "有勇氣", "有精神"]
  ) assert(DEGREE_MAN_NEXT.includes(word), word);
  // 主審第 1 輪 P2：白名單只收兩個字以上的詞。
  assert(DEGREE_MAN_NEXT.every((w) => [...w].length >= 2));
  for (const c of "充裝圓美不客期繳很太好超") {
    assert(MAN_COMPOUND_BEFORE.includes(c), c);
  }
});

Deno.test("這題：Bruce 點名的例子——考題那一小段拿掉，其他照原樣", () => {
  assertEquals(tidy("是你啊 這題不用想"), "是你啊");
  assertEquals(tidy("最好看的就是你 這題沒有懸念"), "最好看的就是你");
  assertEquals(
    tidy("有啦有啦 今天你最好看 這個答案很穩"),
    "有啦有啦 今天你最好看",
  );
  assertEquals(tidy("這題我不用想 是你"), "是你");
  assertEquals(
    tidy("最好看的當然是你 這種送分題我秒答"),
    "最好看的當然是你",
  );
  assertEquals(tidy("這道題我直接答 是你"), "是你");
  assertEquals(tidy("這一題不用想 是你"), "是你");
  assertEquals(
    tidyMessage("是你啊 這題不用想", ASKS_BEST).changes,
    { quiz: 1, quizRewrite: 0, worry: 0, degree: 0, messages: 1 },
  );
});

Deno.test("這題：答案就在那一段裡不拿掉；「這題我選你」這種只拿掉考題字（我選你），其他的整則照原文", () => {
  assertEquals(tidy("這題我選你"), "我選你");
  assertEquals(tidy("最好看這題我選你"), "最好看我選你");
  assertEquals(
    tidy("這題我直接投你一票 整桌沒人比得過"),
    "我直接投你一票 整桌沒人比得過",
  );
  assertEquals(tidy("欸這題我就選你"), "欸我就選你");
  assertEquals(
    tidyMessage("這題我選你", ASKS_BEST).changes,
    { quiz: 0, quizRewrite: 1, worry: 0, degree: 0, messages: 1 },
  );
  // 有「你」、或「選、答……」後面接著答案，但不是「這題我選／投」：整則照原文。
  for (
    const kept of [
      "這題我答你 最好看的是你",
      "你啊 你這題問得這麼有自信 答案本來就是你",
      "這題我答山上 海邊太曬",
      "這題是送分題 是你",
    ]
  ) assertEquals(tidy(kept), kept);
  // 整段剛好是考題空話的才拿掉（QUIZ_FILLERS）。
  assertEquals(tidy("這題要選的話 我選你"), "我選你");
  assertEquals(tidy("這題我答得很快：是 而且你還敢問"), "是 而且你還敢問");
  assertEquals(tidy("是啊 你最好看 這題沒有第二個答案"), "是啊 你最好看");
  assertEquals(tidy("欸這題我不用想 就是你"), "就是你");
  assertEquals(tidy("這題送分欸 當然是你"), "當然是你");
});

Deno.test("主審第 1 輪 P2：有考題字、但不是整段空話的，不確定答案在不在裡面，整則照原文", () => {
  for (
    const kept of [
      // 主審的反例：答案在那一段裡，原本被整段拿掉。
      "這題當然第一名啊 晚點給我看影片",
      "這題海邊勝出 晚點看天氣",
      // 之前跑過的卡：前面帶話題、暗示答案、接在而且後面，都照原文。
      "最好看這題我直接說 你笑起來很有感染力",
      "這題沒有別人能選吧 當然是你",
      "是你 而且這個答案我不用想太久",
      "這題還要問嗎？ 是你",
    ]
  ) {
    assertEquals(tidyMessage(kept, ASKS_BEST), {
      text: kept,
      changes: NO_PHRASE_TIDY_CHANGES,
    }, kept);
  }
});

Deno.test("這題：拿掉那一段的語氣標點一起走；拿掉的是最後一段，前面接續用的逗號、空白也拿掉，問號驚嘆號留著", () => {
  assertEquals(tidy("當然是你，這題不用想"), "當然是你");
  assertEquals(tidy("當然是你！ 這題不用想～"), "當然是你！");
  assertEquals(tidy("這題不用想～ 是你"), "是你");
  assertEquals(tidy("是你啊 這題不用想～ 你最好看"), "是你啊 你最好看");
  assertEquals(tidy("是你 這題不用想 這個答案很穩"), "是你");
  // 表情在那一段裡，跟著那一段走。
  assertEquals(tidy("當然是你 這題根本不用想😏"), "當然是你");
});

Deno.test("這題：她自己在講真的題目（她的訊息有這題、題目），整條不做；題材不是考題", () => {
  const exam = phraseTidyContext({
    herLatest: ["這題怎麼解啦"],
    herMessages: ["明天考試", "這題怎麼解啦"],
  });
  assertEquals(exam.herQuizWords, true);
  assertEquals(tidy("這題不用想 先通分", exam), "這題不用想 先通分");
  assertEquals(tidy("這題不用想 先通分"), "先通分");
  assertEquals(
    phraseTidyContext({ herLatest: [], herMessages: ["題目好難"] })
      .herQuizWords,
    true,
  );
  // 她以前講過也算（整段對話她的訊息）；題材不算。
  assertEquals(
    phraseTidyContext({
      herLatest: ["你覺得呢"],
      herMessages: ["這題材的電影我很愛", "你覺得呢"],
    }).herQuizWords,
    false,
  );
  assertEquals(tidy("這題材我喜歡 是你"), "這題材我喜歡 是你");
});

Deno.test("不怪：只是在否認她擔心的字那一小段拿掉（Bruce 的例子與同樣的說法；醜、胖、奇怪同樣）", () => {
  assertEquals(tidy("不怪啊 很好看", ASKS_WEIRD), "很好看");
  assertEquals(tidy("一點都不怪 很適合你", ASKS_WEIRD), "很適合你");
  assertEquals(tidy("哪裡怪 我覺得好看欸", ASKS_WEIRD), "我覺得好看欸");
  for (
    const deny of [
      "不會怪啊",
      "完全不怪",
      "沒有很怪啦",
      "完全不會怪",
      "怎麼會怪",
      "才不怪咧",
      "不怪不怪",
      "一點都不奇怪",
      "不怪啊😂",
    ]
  ) assertEquals(tidy(`${deny} 很適合你`, ASKS_WEIRD), "很適合你", deny);
  assertEquals(tidy("剪得很好欸 一點都不怪", ASKS_WEIRD), "剪得很好欸");
  const fat = phraseTidyContext({
    herLatest: ["我是不是變胖了"],
    herMessages: ["我是不是變胖了"],
  });
  assertEquals(fat.herWorries, ["胖"]);
  assertEquals(tidy("哪有胖 你這樣剛好", fat), "你這樣剛好");
  assertEquals(tidy("沒那麼胖啦 很可愛", fat), "很可愛");
  const ugly = phraseTidyContext({
    herLatest: ["我這樣會不會很醜"],
    herMessages: ["我這樣會不會很醜"],
  });
  assertEquals(tidy("一點也不醜 很有氣質", ugly), "很有氣質");
  assertEquals(
    tidyMessage("不怪啊 很好看", ASKS_WEIRD).changes,
    { quiz: 0, quizRewrite: 0, worry: 1, degree: 0, messages: 1 },
  );
});

Deno.test("不怪：她最新這一輪沒提到那個字就不動（別的擔心、難怪、怪我都不算）；多了別的字的「不怪你」不動", () => {
  assertEquals(ASKS_BEST.herWorries, []);
  assertEquals(tidy("不怪啊 很好看"), "不怪啊 很好看");
  // 她擔心的是胖，卡否認的是怪：不動。
  const fat = phraseTidyContext({
    herLatest: ["我是不是變胖了"],
    herMessages: ["我是不是變胖了"],
  });
  assertEquals(tidy("不怪啊 很好看", fat), "不怪啊 很好看");
  // 只看她最新這一輪：前面講過不算。
  assertEquals(
    phraseTidyContext({
      herLatest: ["今天好累"],
      herMessages: ["會很怪嗎", "今天好累"],
    }).herWorries,
    [],
  );
  for (
    const notWorry of ["難怪你會累", "都怪我啦", "別見怪喔", "小怪獸好可愛"]
  ) {
    assertEquals(
      phraseTidyContext({ herLatest: [notWorry], herMessages: [notWorry] })
        .herWorries,
      [],
      notWorry,
    );
  }
  for (
    const kept of ["不怪你啊 很好看", "不會怪你 慢慢來", "有點怪 但很可愛"]
  ) assertEquals(tidy(kept, ASKS_WEIRD), kept);
});

Deno.test("主審第 1 輪 P2：她要用問句問自己會不會很怪、很醜、很胖才算；怕你怪她、說別人怪怪的都不算，卡照原文", () => {
  // 主審的反例：她是怕你怪她（取消約會），「不怪啊」是在回答她，不能拿掉。
  const blame = phraseTidyContext({
    herLatest: ["臨時取消約會很抱歉", "會怪嗎"],
    herMessages: ["臨時取消約會很抱歉", "會怪嗎"],
  });
  assertEquals(blame.herWorries, []);
  assertEquals(tidy("不怪啊 你先休息", blame), "不怪啊 你先休息");
  for (
    const notAsking of [
      "我同事怪怪的",
      "怪我囉",
      "會不會很怪我",
      "我同事是不是很怪",
      "他會不會很胖",
      "這張會不會很醜",
      "我變胖了",
      "會不會怪怪的",
    ]
  ) {
    assertEquals(
      phraseTidyContext({ herLatest: [notAsking], herMessages: [notAsking] })
        .herWorries,
      [],
      notAsking,
    );
  }
  // 問自己、有很／太／變的問句才算（可以先說我、這樣、看起來，後面可以有語助詞、表情、問號）。
  for (
    const [asking, worry] of [
      ["會很怪嗎", "怪"],
      ["會不會很怪", "怪"],
      ["是不是很怪", "怪"],
      ["很怪嗎？", "怪"],
      ["看起來很怪", "怪"],
      ["我這樣會不會很奇怪😂", "怪"],
      ["欸 我剪這樣會太怪嗎", "怪"],
      ["我是不是變胖了", "胖"],
      ["會不會太胖啊", "胖"],
      ["我穿這樣會很醜嗎", "醜"],
      ["人家看起來是不是很醜", "醜"],
    ]
  ) {
    assertEquals(
      phraseTidyContext({ herLatest: [asking], herMessages: [asking] })
        .herWorries,
      [worry],
      asking,
    );
  }
  // 引用前綴是被引用的那句、照片貼圖是描述、引號裡是別人的話，都不算她問的。
  assertEquals(
    phraseTidyContext({
      herLatest: [
        "（引用：「會很怪嗎」）哪有",
        "[照片：會不會很怪的帽子]",
        "他說「會很怪嗎」",
      ],
      herMessages: [],
    }).herWorries,
    [],
  );
});

Deno.test("滿→蠻：程度的「滿」後面接白名單的字才換（Bruce：蠻適合的、蠻好看的才對）", () => {
  assertEquals(tidy("滿適合的"), "蠻適合的");
  assertEquals(tidy("滿有勇氣的"), "蠻有勇氣的");
  assertEquals(tidy("還滿好看的"), "還蠻好看的");
  assertEquals(tidy("位子滿舒服的"), "位子蠻舒服的");
  assertEquals(tidy("空氣瀏海那個還滿加分的"), "空氣瀏海那個還蠻加分的");
  assertEquals(tidy("我滿喜歡 也滿期待的"), "我蠻喜歡 也蠻期待的");
  assertEquals(
    tidyMessage("我滿喜歡 也滿期待的", ASKS_BEST).changes,
    { quiz: 0, quizRewrite: 0, worry: 0, degree: 2, messages: 1 },
  );
});

Deno.test("滿→蠻 不動的：滿意、滿足、充滿、滿分……（後面不在白名單，或前面的字跟滿連成詞）", () => {
  for (
    const word of [
      "滿意",
      "滿足",
      "充滿",
      "滿分",
      "滿了",
      "滿滿",
      "裝滿",
      "滿月",
      "圓滿",
      "美滿",
      "不滿",
      "滿臉",
      "滿身",
      "滿桌",
      "滿地",
      "滿屋",
      "滿載",
      "滿額",
      "滿座",
      "客滿",
      "期滿",
      "滿週年",
    ]
  ) {
    const message = `今天${word}的`;
    assertEquals(tidy(message), message, word);
  }
  // 前面的字跟滿連成詞，後面就算是白名單的字也不換。
  for (
    const kept of [
      "充滿期待",
      "期滿會自動續約",
      "她對主管不滿想離職",
      "裝滿好料",
      "主管請客加滿桌肉",
      "吃完還滿意就好",
      "滿不在乎",
    ]
  ) assertEquals(tidy(kept), kept);
});

Deno.test("主審第 1 輪 P2：「滿」後面一個字的、前面是很太好超的，不確定是不是「很」的意思，都照原文", () => {
  for (
    const kept of [
      // 主審的反例：「會」是下一個詞的開頭、「繳滿」是繳完。
      "行程很滿會累",
      "月底之前要繳滿會費",
      // 前面是很、太、好、超：滿是形容詞（很滿＝很擠）。
      "這週很滿適合下週再約",
      "今天很滿好的明天聊",
      "時間太滿有點累",
      "排得超滿想休息",
      // 一個字的不收：滿會、滿想、滿多、滿好（之前跑過的卡沒有這些用法）。
      "滿會打扮的",
      "滿想去的",
      "滿多人的",
      "滿好的",
    ]
  ) assertEquals(tidy(kept), kept);
  // 之前跑過的卡的用法照常換。
  assertEquals(tidy("而且敢剪這麼短 滿有勇氣的"), "而且敢剪這麼短 蠻有勇氣的");
  assertEquals(tidy("還滿有氣質的"), "還蠻有氣質的");
  assertEquals(tidy("看起來滿有精神的"), "看起來蠻有精神的");
  assertEquals(tidy("玩得滿開心的"), "玩得蠻開心的");
});

Deno.test("受保護的字不動：引號裡、網址、顏文字裡的「這題」「不怪」「滿」都照原樣", () => {
  assertEquals(tidy("她說「滿好看的」 我笑了"), "她說「滿好看的」 我笑了");
  assertEquals(
    tidy("「這題不用想」是她的口頭禪 我很愛"),
    "「這題不用想」是她的口頭禪 我很愛",
  );
  assertEquals(
    tidy("「不怪啊」 很好看", ASKS_WEIRD),
    "「不怪啊」 很好看",
  );
  assertEquals(
    tidy("看 https://a.com/滿好看 是你"),
    "看 https://a.com/滿好看 是你",
  );
  // 引號外的照常改。
  assertEquals(tidy("她說「好」 滿適合的"), "她說「好」 蠻適合的");
  assertEquals(tidy("是你 (・ω・) 這題不用想"), "是你 (・ω・)");
});

Deno.test("拿掉之後沒有字（只剩語助詞、表情、標點）就整則照原文：則數不變、不會變成空的", () => {
  for (
    const [message, context] of [
      ["這題不用想", ASKS_BEST],
      ["欸 這題不用想", ASKS_BEST],
      ["哈哈 這題不用想😂", ASKS_BEST],
      ["不怪啊", ASKS_WEIRD],
      ["不怪啊 😂", ASKS_WEIRD],
      ["不怪啊 這題不用想", ASKS_WEIRD],
    ] as const
  ) {
    assertEquals(tidyMessage(message, context), {
      text: message,
      changes: NO_PHRASE_TIDY_CHANGES,
    }, message);
  }
  assertEquals(tidyMessage("", ASKS_WEIRD).text, "");
});

Deno.test("主審第 1 輪 P2：拿掉後只剩顏文字、整個表情（數字鍵帽、國旗）、XD 這類、網址，都算沒有字，整則照原文", () => {
  for (
    const [message, context] of [
      // 主審的反例。
      ["不怪啊 (・ω・)", ASKS_WEIRD],
      ["不怪啊 1️⃣", ASKS_WEIRD],
      ["不怪啊 #️⃣ 🇹🇼", ASKS_WEIRD],
      ["不怪啊 XD", ASKS_WEIRD],
      ["這題不用想 (｡•̀ᴗ-)✧", ASKS_BEST],
      ["這題不用想 QQ orz", ASKS_BEST],
      ["這題不用想 https://example.com/a", ASKS_BEST],
    ] as const
  ) {
    assertEquals(tidyMessage(message, context), {
      text: message,
      changes: NO_PHRASE_TIDY_CHANGES,
    }, message);
  }
  // 顏文字、表情旁邊還有字就照常拿掉，顏文字與表情照原樣留著。
  assertEquals(
    tidy("不怪啊 (・ω・) 很好看", ASKS_WEIRD),
    "(・ω・) 很好看",
  );
  assertEquals(tidy("這題不用想 1️⃣號是你"), "1️⃣號是你");
  assertEquals(tidy("不怪啊 ok啦", ASKS_WEIRD), "ok啦");
});

Deno.test("一整張卡：每一則各自改、則數不變；次數加總；沒有要改的原樣回、次數都是 0", () => {
  const out = tidyCard(
    ["不會怪啊 滿適合的", "這題不用想 而且看起來比較有精神", "後悔什麼啦"],
    ASKS_WEIRD,
  );
  assertEquals(out.messages, [
    "蠻適合的",
    "而且看起來比較有精神",
    "後悔什麼啦",
  ]);
  assertEquals(out.changes, {
    quiz: 1,
    quizRewrite: 0,
    worry: 1,
    degree: 1,
    messages: 2,
  });
  assertEquals(tidyCard(["好看啊", "等你回來"], ASKS_BEST), {
    messages: ["好看啊", "等你回來"],
    changes: NO_PHRASE_TIDY_CHANGES,
  });
  // 只有考題那一則：那一則照原文，卡還是兩則。
  assertEquals(
    tidyCard(["這題我不用想", "是你"], ASKS_BEST).messages,
    ["這題我不用想", "是你"],
  );
});
