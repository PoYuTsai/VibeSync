// run_benchmark.ts 核心比對邏輯單元測試
// 跑法：deno test tools/ocr-golden/run_benchmark_test.ts

import {
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  alignMessages,
  levenshtein,
  normalizeText,
  similarity,
} from "./run_benchmark.ts";

Deno.test("normalizeText：全形轉半形、去空白、轉小寫", () => {
  assertEquals(normalizeText("Ｈｅｌｌｏ　ｗｏｒｌｄ！"), "helloworld!");
  assertEquals(normalizeText("你 好  嗎"), "你好嗎");
});

Deno.test("levenshtein：基本距離", () => {
  assertEquals(levenshtein("abc", "abc"), 0);
  assertEquals(levenshtein("abc", "abd"), 1);
  assertEquals(levenshtein("", "abc"), 3);
  assertEquals(levenshtein("在嗎", "再嗎"), 1); // 錯字被修正會產生距離
});

Deno.test("similarity：相同文字 = 1，差一字的短句仍高相似", () => {
  assertEquals(similarity("哈囉你好嗎", "哈囉你好嗎"), 1);
  const s = similarity("今天天氣真的很好耶", "今天天氣真的很好捏");
  if (s < 0.8) throw new Error(`預期 ≥0.8，得到 ${s}`);
});

Deno.test("alignMessages：順序保持的一對一對齊", () => {
  const expected = [
    { side: "left" as const, text: "今天吃什麼" },
    { side: "right" as const, text: "想吃拉麵" },
    { side: "left" as const, text: "好啊走" },
  ];
  const actual = [
    { side: "left", content: "今天吃什麼" },
    { side: "right", content: "想吃拉麵" },
    { side: "left", content: "好啊走" },
  ];
  assertEquals(alignMessages(expected, actual), [[0, 0], [1, 1], [2, 2]]);
});

Deno.test("alignMessages：漏抓（actual 缺一則）不錯位", () => {
  const expected = [
    { side: "left" as const, text: "第一句話內容" },
    { side: "right" as const, text: "第二句話內容" },
    { side: "left" as const, text: "第三句話內容" },
  ];
  const actual = [
    { side: "left", content: "第一句話內容" },
    { side: "left", content: "第三句話內容" },
  ];
  // 第二句漏抓；第三句必須對到 actual[1]，不能硬塞給第二句
  assertEquals(alignMessages(expected, actual), [[0, 0], [2, 1]]);
});

Deno.test("alignMessages：幻覺訊息（actual 多一則）被排除", () => {
  const expected = [
    { side: "left" as const, text: "真實訊息一號" },
    { side: "right" as const, text: "真實訊息二號" },
  ];
  const actual = [
    { side: "left", content: "真實訊息一號" },
    { side: "left", content: "憑空多出來的內容" },
    { side: "right", content: "真實訊息二號" },
  ];
  assertEquals(alignMessages(expected, actual), [[0, 0], [1, 2]]);
});

Deno.test("alignMessages：輕微 OCR 誤差（≥0.8 相似）仍可對齊", () => {
  const expected = [
    { side: "left" as const, text: "明天下午三點老地方見面喔" },
  ];
  const actual = [
    { side: "left", content: "明天下午三點老地方見面唷" },
  ];
  assertEquals(alignMessages(expected, actual), [[0, 0]]);
});

Deno.test("alignMessages：完全不同的短訊息不對齊", () => {
  const expected = [{ side: "left" as const, text: "晚安" }];
  const actual = [{ side: "left", content: "早安你好" }];
  assertEquals(alignMessages(expected, actual), []);
});
