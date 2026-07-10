import {
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { latestAssistantShowsHostility } from "./conversation_signals.ts";

Deno.test("hostility signal accepts direct exit boundaries", () => {
  for (
    const text of [
      "不要再傳了",
      "可以不要再聯絡我嗎？",
      "我不想跟你聊了",
      "你再這樣我就封鎖你",
      "請停止聯絡我",
      "請不要再跟我聯絡",
      "我希望你不要再聯絡我",
      "我覺得我們不要再聯絡比較好",
      "我不想再收到你的訊息",
      "我不想再跟你有任何聯絡",
      "請勿再聯絡我",
      "不要再聯\u200b絡我",
      "我不想跟你聊\ufe0f了",
      "先這樣\n不要再聯絡我",
      "先說清楚：不要再聯絡我",
      "請停止跟我聯絡",
      "我們不要再聯絡了",
      "不要再密了",
      "別再回我了",
      "到此為止，不要聯絡了",
      "別再傳 Line 給我",
    ]
  ) {
    assertEquals(latestAssistantShowsHostility(text), true, text);
  }
});

Deno.test("hostility signal does not treat a bare question as her exit declaration", () => {
  for (
    const text of [
      "不想聊了？",
      "你不想聊了嗎？",
      "前任跟我說，不要再傳了。",
      "她問我，可以不要再聯絡我嗎？",
      "她說：不要再聯絡我",
      "她問我：可以不要再聯絡我嗎？",
      "前任跟我說：不要再傳了",
      "下次別再來。這家店很雷。",
      "不是不想聊，只是今天有點累。",
    ]
  ) {
    assertFalse(latestAssistantShowsHostility(text), text);
  }
});

Deno.test("hostility signal keeps direct-speaker colon boundaries", () => {
  for (const text of ["我說：不要再聯絡我", "先說清楚：不要再聯絡我"]) {
    assertEquals(latestAssistantShowsHostility(text), true, text);
  }
});
