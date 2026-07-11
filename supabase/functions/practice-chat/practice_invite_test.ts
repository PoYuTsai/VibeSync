import { assertEquals } from "jsr:@std/assert@1";
import { practiceInviteLevelFor } from "./practice_invite.ts";

Deno.test("practice invite classifier separates self-disclosure from plans involving her", () => {
  for (
    const line of [
      "明天我也想喝咖啡補血",
      "這週六我想去爬山",
      "週末我去看電影放空，妳呢？",
      "週末看電影放空，妳呢？",
      "明天我去打球，妳呢？",
      "明天我在咖啡廳跟朋友見面。",
      "明天我要去咖啡廳見面。",
      "週六朋友來我家。",
      "妳到家跟我說一聲。",
      "不是要約妳，我明天也會去那間店。",
      "等妳時差歸位，我拿一杯咖啡跟妳交換故事。",
      "調時差辛苦了，妳這趟回來最想先用什麼方式回血？",
    ]
  ) {
    assertEquals(practiceInviteLevelFor(line), "none", line);
  }
  assertEquals(practiceInviteLevelFor("週六一起去爬山吧"), "direct");
  assertEquals(practiceInviteLevelFor("明晚我們去打羽球吧"), "direct");
  assertEquals(practiceInviteLevelFor("下次有空去打羽球吧"), "soft");
});

Deno.test("practice invite classifier recognises generic scheduling language", () => {
  for (
    const line of [
      "週六我帶妳去那間店。",
      "明晚我帶妳出去玩。",
      "週末直接出來，我帶妳去一個地方。",
      "我們週六約在那間店。",
      "週六去陶藝教室玩吧？",
      "明天七點我去接妳。",
      "七點我會去接妳。",
      "明晚我想請妳吃飯。",
      "明天七點樓下見。",
      "明天七點我在妳家樓下等妳。",
      "明天七點在咖啡廳見面。",
      "週六咖啡店見。",
      "明晚七點咖啡店碰面。",
      "週六我訂那間店，妳直接過來。",
      "明晚妳直接過來。",
      "週六來找我。",
      "明晚過來找我。",
      "週末來我家。",
      "明晚到我這邊。",
      "明天七點樓下見喔。",
      "明天七點樓下見啦",
      "明天七點樓下等妳。",
      "明天七點我等妳。",
      "明天七點妳下樓，我到了叫妳。",
      "明天七點碰個面吧。",
      "明晚過來。",
      "妳明晚直接過來。",
      "明晚七點老地方。",
      "七點樓下。",
    ]
  ) {
    assertEquals(practiceInviteLevelFor(line), "direct", line);
  }
  assertEquals(
    practiceInviteLevelFor("下次有空再去那間咖啡店走走。"),
    "soft",
  );
});

Deno.test("practice invite classifier removes cancelled or negated plans", () => {
  for (
    const line of [
      "放心，明天七點我不會去接妳。",
      "明天七點不用我去接妳。",
      "週末我們不要去看電影了。",
      "明天不要一起喝咖啡。",
      "不是要約妳，我明天也會去那間店。",
      "明天七點我不去接妳。",
      "明天七點我不接妳了。",
      "明天七點我沒有要去接妳。",
      "週末別一起看電影了。",
      "週末不要來找我。",
      "週末不用來我家。",
    ]
  ) {
    assertEquals(practiceInviteLevelFor(line), "none", line);
  }
  assertEquals(
    practiceInviteLevelFor("明天不要喝咖啡，週六一起去爬山吧。"),
    "direct",
  );
});
