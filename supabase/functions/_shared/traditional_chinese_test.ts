import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import v2Fixtures from "../analyze-chat/testdata/analyze_replay_fixtures.json" with {
  type: "json",
};
import v3Fixtures from "../analyze-chat/testdata/guide_v3_replay_fixtures.json" with {
  type: "json",
};
import { parseWrittenCardLine } from "../analyze-chat/guide_v3/cards.ts";
import {
  finalizeCard,
  vetCoachText,
} from "../analyze-chat/guide_v3/finalize.ts";
import {
  normalizeOutgoingMessageText,
  normalizeOutgoingScript,
} from "../analyze-chat/outgoing_message_text.ts";
import { validateMomentDraft } from "../practice-chat/moments_validate.ts";
import { toTraditionalChinese } from "./traditional_chinese.ts";

// 2026-08-11：Game hint／NPC 可以摻台語與注音（Eric 拍板「台灣人的諧音梗很屌」）。
// 但「厂」在轉換表裡是「廠」的簡體字，台灣人拿它當注音ㄏ打笑聲會被轉壞
// （厂ㄠ厂ㄠ丂ㄞ → 廠ㄠ廠ㄠ丂ㄞ）。prompt 要求打真注音，但模型偶爾照樣
// 吐漢字版（2026-08-19 真機實錄「甜點單厂厂」）；改在轉換前把當注音用
// 的漢字正規化成真注音——判準是相鄰字：旁邊也是注音/同類漢字才換，
// 孤立的「厂」（工厂）留給 cn2t 轉成「廠」。
Deno.test("注音符號原樣通過繁簡轉換", () => {
  assertEquals(toTraditionalChinese("ㄏㄏ 妳很敢講"), "ㄏㄏ 妳很敢講");
  assertEquals(toTraditionalChinese("我沒那麼遜ㄟ"), "我沒那麼遜ㄟ");
  assertEquals(toTraditionalChinese("歹勢 我剛在忙ㄌ"), "歹勢 我剛在忙ㄌ");
  assertEquals(toTraditionalChinese("母湯 甘安捏"), "母湯 甘安捏");
});

Deno.test("當注音用的漢字笑聲正規化成真注音，真簡體字照樣轉繁", () => {
  assertEquals(toTraditionalChinese("厂厂"), "ㄏㄏ");
  assertEquals(
    toTraditionalChinese("改天研究股票不如研究甜點單厂厂"),
    "改天研究股票不如研究甜點單ㄏㄏ",
  );
  assertEquals(toTraditionalChinese("厂ㄠ厂ㄠ丂ㄞ"), "ㄏㄠㄏㄠㄎㄞ");
  assertEquals(toTraditionalChinese("丂丂"), "ㄎㄎ");
  // 孤立的厂不是笑聲：留給 cn2t 當簡體「廠」轉。
  assertEquals(toTraditionalChinese("这家工厂很大"), "這家工廠很大");
});

// 2026-10-20（Eric「直接修好上線」）：OpenCC 的詞組表把「是只」轉成「是隻」，已經是繁體的「還是只有」
// 「不是只回」會被改成「還是隻有」「不是隻回」（正式環境用真的函式確認過）。「只」不交給轉換器，代價
// 是簡體的量詞「一只猫」轉成「一只貓」。
Deno.test("已經是繁體的「只」不會變成「隻」：回報的兩句，與各種「是只」", () => {
  assertEquals(toTraditionalChinese("還是只有"), "還是只有");
  assertEquals(toTraditionalChinese("不是只回"), "不是只回");
  for (
    const text of [
      "就是只有你",
      "可是只差一點",
      "她是只想聊天",
      "還是只想待在家",
      "你是只有今天有空嗎",
    ]
  ) assertEquals(toTraditionalChinese(text), text);
});

Deno.test("各功能常見的輸出裡的「只」照留：對話分析的卡與判讀、教練、練習室的回覆、提示、回顧、動態與溫度理由、開場救星", () => {
  const typical = [
    "還是只有你懂我在說什麼",
    "她不是只回貼圖，還反問你週末要幹嘛",
    "重點不是只有技巧，是你真的想多認識她",
    "你是只想聊天，還是想約出來？",
    "這輪不是只有你在找話題，她也有接",
    "今天還是只想窩在家耍廢",
    "互動還是只停在表面，可以多問一點她的事",
    "我是只有週末有空啦",
  ];
  for (const text of typical) assertEquals(toTraditionalChinese(text), text);
});

Deno.test("走真的呼叫端也一樣：對話分析的整理與定稿、判讀檢查、練習室動態的驗證", () => {
  const card = "還是只有你懂我在說什麼";
  assertEquals(normalizeOutgoingScript(card), card);
  // 傳給她的句子另外把「你」換成「妳」（normalizePartnerPronoun），「只」照留。
  assertEquals(normalizeOutgoingMessageText(card), "還是只有妳懂我在說什麼");
  const finalized = finalizeCard(
    {
      card: 1,
      messages: [card],
      hasInventedDetail: false,
      expectedReaction: "",
    },
    { voice: "預設" },
    "",
  );
  assert(finalized.ok);
  assertEquals(finalized.messages, [card]);
  assertEquals("rawMessages" in finalized, false);
  assertEquals(vetCoachText("她不是只回貼圖，還反問你週末要幹嘛"), {
    ok: true,
    text: "她不是只回貼圖，還反問你週末要幹嘛",
  });
  const moment = "今天還是只想窩在家，煮了一鍋湯配一整晚的劇";
  assertEquals(
    validateMomentDraft({
      raw: JSON.stringify({ text: moment, imageId: null }),
      imageCandidates: [],
    }).body,
    moment,
  );
});

Deno.test("繁體的量詞「隻」照留；簡體照樣轉繁，只有「只」原樣留著（簡體量詞「一只猫」變成「一只貓」是這個修法的代價）", () => {
  for (const text of ["這隻狗好可愛", "養了一隻貓叫布丁", "隻身去旅行"]) {
    assertEquals(toTraditionalChinese(text), text);
  }
  assertEquals(toTraditionalChinese("你只是说说而已吧"), "你只是說說而已吧");
  assertEquals(toTraditionalChinese("只不过有点累"), "只不過有點累");
  assertEquals(toTraditionalChinese("你是只有一个吗"), "你是只有一個嗎");
  // 代價：簡體的量詞「只」不再轉成「隻」。
  assertEquals(toTraditionalChinese("一只猫"), "一只貓");
  assertEquals(toTraditionalChinese("两只手"), "兩只手");
  // 其他轉換照舊：產品用詞、注音笑聲。
  assertEquals(toTraditionalChinese("用户只看信息"), "使用者只看資訊");
  assertEquals(toTraditionalChinese("只是厂厂"), "只是ㄏㄏ");
});

Deno.test("repo 裡錄到的模型輸出（v3 的卡與判讀、v2 原文）：轉完每一個「只」都還在", () => {
  const texts: string[] = [];
  for (const c of v3Fixtures.cases) {
    for (const line of c.writeText.split(/\r?\n/)) {
      const written = parseWrittenCardLine(line);
      if (written) texts.push(...written.messages);
    }
    const tags = JSON.parse(c.readText) as Record<string, unknown>;
    for (const field of ["readForUser", "waitFor"]) {
      const text = tags[field];
      if (typeof text === "string" && text) texts.push(text);
    }
  }
  texts.push(...v2Fixtures.cases.map((c) => c.rawText));
  const zhi = (s: string) => [...s].filter((ch) => ch === "只").length;
  const withZhi = texts.filter((t) => zhi(t) > 0);
  // 確認真的有含「只」的句子，不是空迴圈。
  assert(withZhi.length >= 20, String(withZhi.length));
  for (const text of withZhi) {
    assertEquals(zhi(toTraditionalChinese(text)), zhi(text), text);
  }
});
