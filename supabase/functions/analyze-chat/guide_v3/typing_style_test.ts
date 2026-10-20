// 口吻與斷句交給程式（typing_style.ts，Bruce 2026-10-20 改法 3）：從他的訊息看習慣、照習慣統一每一則。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  addressFor,
  DEFAULT_ADDRESS,
  detectTypingHabits,
  HIS_HABIT_MIN_MESSAGES,
  HIS_HABIT_MIN_SHARE,
  NO_TYPING_CHANGES,
  NOT_PRONOUN_WORDS,
  styleCard,
  styleMessage,
  type TypingHabits,
} from "./typing_style.ts";

const habits = (over: Partial<TypingHabits> = {}): TypingHabits => ({
  address: null,
  usesCommas: false,
  endsWithPeriod: false,
  messages: 0,
  ...over,
});
const text = (message: string, h: TypingHabits = habits()) =>
  styleMessage(message, h).text;

Deno.test("Bruce 的例子：他打「妳」、用空白斷句 →「好，那妳先忙／忙完有空再說，不急」變「好 那妳先忙／忙完有空再說 不急」（程式轉換，不重新生成）", () => {
  const his = detectTypingHabits(["好 那妳先忙", "妳到了沒"]);
  assertEquals(his.address, "妳");
  assertEquals(his.usesCommas, false);
  const out = styleCard(["好，那妳先忙", "忙完有空再說，不急"], his);
  assertEquals(out.messages, ["好 那妳先忙", "忙完有空再說 不急"]);
  assertEquals(out.changes, {
    address: 0,
    commas: 2,
    innerPeriods: 0,
    finalPeriods: 0,
    messages: 2,
  });
});

Deno.test("常數：沒有稱呼習慣用「你」；明顯的習慣＝至少 2 則、至少三分之一；不是稱呼的詞有迷你", () => {
  assertEquals(DEFAULT_ADDRESS, "你");
  assertEquals(HIS_HABIT_MIN_MESSAGES, 2);
  assertEquals(HIS_HABIT_MIN_SHARE, 1 / 3);
  assert(NOT_PRONOUN_WORDS.includes("迷你"));
});

Deno.test("看習慣只看他的訊息：稱呼取多數，一樣多或沒打過是沒有；引號裡、迷你、照片貼圖、引用前綴都不算", () => {
  assertEquals(
    detectTypingHabits(["妳在幹嘛", "你吃了嗎", "妳呢"]).address,
    "妳",
  );
  assertEquals(detectTypingHabits(["你在幹嘛", "妳吃了嗎"]).address, null);
  assertEquals(detectTypingHabits(["下班了沒", "好"]).address, null);
  assertEquals(detectTypingHabits([]).address, null);
  // 引號裡的「你」可能是她的話；迷你不是稱呼；照片、貼圖不算；引用前綴是別人的句子。
  assertEquals(
    detectTypingHabits([
      "她說「你很煩」",
      "迷你版的",
      "[照片：妳的貼圖]",
      "（引用：「你到了嗎」）到了",
    ]).address,
    null,
  );
  assertEquals(detectTypingHabits([]).messages, 0);
  assertEquals(
    detectTypingHabits(["好", "[貼圖：小熊]", "😂", "  "]).messages,
    1,
  );
});

Deno.test("看習慣：明顯用逗號斷句才算（至少 2 則、至少佔他有斷句的訊息三分之一）；句尾句號同樣門檻、比的是他全部的訊息", () => {
  assertEquals(
    detectTypingHabits(["好，我等等過去", "嗯，晚點說", "下班了沒"]).usesCommas,
    true,
  );
  // 只有一則用逗號：不算。
  assertEquals(
    detectTypingHabits(["好，我等等過去", "下班了沒"]).usesCommas,
    false,
  );
  // 兩則用逗號、但他有斷句的訊息大多用空白（2/7 不到三分之一）：不算。
  assertEquals(
    detectTypingHabits([
      "好，等等",
      "嗯，晚點",
      "好 等等",
      "嗯 晚點",
      "我到了 你呢",
      "走吧 出門",
      "吃了 很飽",
    ]).usesCommas,
    false,
  );
  // 1,000 不是斷句的逗號。
  assertEquals(
    detectTypingHabits(["要 1,000 元", "大概 2,000 吧"]).usesCommas,
    false,
  );
  assertEquals(
    detectTypingHabits(["好。", "我到了。", "嗯"]).endsWithPeriod,
    true,
  );
  assertEquals(
    detectTypingHabits(["好。", "我到了", "嗯", "走吧", "出門"]).endsWithPeriod,
    false,
  );
  // 。。。 是刪節號，不算句尾句號。
  assertEquals(
    detectTypingHabits(["好吧。。。", "嗯。。。"]).endsWithPeriod,
    false,
  );
});

Deno.test("稱呼：照他的習慣換整組；沒有習慣就用「你」；你們、妳們跟著換；引號裡與迷你不動", () => {
  const her = habits({ address: "妳" });
  assertEquals(addressFor(her), "妳");
  assertEquals(addressFor(habits()), "你");
  assertEquals(text("你今天好嗎", her), "妳今天好嗎");
  assertEquals(text("妳今天好嗎"), "你今天好嗎");
  assertEquals(text("你們先走 妳們等等", her), "妳們先走 妳們等等");
  assertEquals(text("她說「你很煩」 我笑了", her), "她說「你很煩」 我笑了");
  assertEquals(text("迷你的你 好可愛", her), "迷你的妳 好可愛");
  assertEquals(text('『你看』 “你好” "你在"', her), '『你看』 “你好” "你在"');
});

Deno.test("斷句：句子中間的逗號換成一個空白、一則中間的句號換成空白、句尾句號拿掉；空白連在一起的併成一個、頭尾修掉", () => {
  assertEquals(text("好，那你先忙"), "好 那你先忙");
  assertEquals(text("好, 那你先忙"), "好 那你先忙");
  assertEquals(text("好。我等你"), "好 我等你");
  assertEquals(text("好，我等你。"), "好 我等你");
  assertEquals(text("我到了."), "我到了");
  assertEquals(text("好，， 那你先忙，"), "好 那你先忙");
});

Deno.test("斷句不動的：頓號、問號、驚嘆號、～、…、表情、1,000、3.5、網址、刪節號、英文、引號裡", () => {
  assertEquals(text("嗯、好，我知道了！"), "嗯、好 我知道了！");
  assertEquals(text("真的嗎？好啊～"), "真的嗎？好啊～");
  assertEquals(text("好…那再說"), "好…那再說");
  assertEquals(text("好啊😂，等你"), "好啊😂 等你");
  assertEquals(text("1,000 元，3.5 小時。"), "1,000 元 3.5 小時");
  assertEquals(
    text("看 https://a.com/x,y 吧，好。"),
    "看 https://a.com/x,y 吧 好",
  );
  assertEquals(text("好吧。。。"), "好吧。。。");
  assertEquals(text("OK, see you."), "OK, see you.");
  assertEquals(
    text("他說「好，那你先忙。」，我笑了"),
    "他說「好，那你先忙。」 我笑了",
  );
  // 整則只有一個句號：換完會變空的，照原文（則數不能少）。
  assertEquals(styleMessage("。", habits()), {
    text: "。",
    changes: NO_TYPING_CHANGES,
  });
});

Deno.test("他明顯用逗號：逗號與一則中間的句號照留，稱呼照樣統一；他明顯在句尾打句號：句尾句號照留", () => {
  const commas = habits({ usesCommas: true, address: "妳" });
  assertEquals(
    text("好，你先忙。我等等過去。", commas),
    "好，妳先忙。我等等過去",
  );
  const periods = habits({ endsWithPeriod: true });
  assertEquals(text("好，我等你。", periods), "好 我等你。");
  const both = habits({ usesCommas: true, endsWithPeriod: true });
  assertEquals(text("好，我等你。", both), "好，我等你。");
  assertEquals(styleMessage("好，我等你。", both).changes, NO_TYPING_CHANGES);
});

Deno.test("一整組：同一份習慣套到每張卡的每一則，則數不變；混用你妳的一組統一成同一個；次數加總", () => {
  const cards = [
    ["改五版還嫌，客戶是把妳當印表機喔", "先抱一個，今天辛苦了"],
    [
      "剛到家又要想明天一早的事，這主管也太會排",
      "先給你一個抱抱，今晚什麼都不用想",
    ],
  ];
  const his = detectTypingHabits(["下班了沒"]);
  const out = cards.map((c) => styleCard(c, his));
  assertEquals(out.map((o) => o.messages), [
    ["改五版還嫌 客戶是把你當印表機喔", "先抱一個 今天辛苦了"],
    [
      "剛到家又要想明天一早的事 這主管也太會排",
      "先給你一個抱抱 今晚什麼都不用想",
    ],
  ]);
  assertEquals(out.map((o) => o.messages.length), [2, 2]);
  assertEquals(out[0].changes, {
    address: 1,
    commas: 2,
    innerPeriods: 0,
    finalPeriods: 0,
    messages: 2,
  });
  // 沒有要改的就原樣回、次數都是 0。
  assertEquals(styleCard(["好 等你"], his), {
    messages: ["好 等你"],
    changes: NO_TYPING_CHANGES,
  });
});

Deno.test("主審第 1 輪 P2：整理空白只整理引號外的，引號裡的空白照原樣", () => {
  assertEquals(text("好，「代碼 A  B」照貼"), "好 「代碼 A  B」照貼");
  assertEquals(text("「 好  啊 」，"), "「 好  啊 」");
  assertEquals(text("好，，  那  「 A  B 」"), "好 那 「 A  B 」");
});
