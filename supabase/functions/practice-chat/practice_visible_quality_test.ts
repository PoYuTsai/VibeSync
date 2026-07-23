import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  assertPracticeTextGroundedInTurns,
  isGenericPracticeComplimentOrEcho,
  rejectGenericPasteablePracticeText,
  rejectKnownCannedPracticeText,
} from "./practice_visible_quality.ts";

Deno.test("known canned screenshot line is rejected after punctuation normalization", () => {
  assertThrows(
    () =>
      rejectKnownCannedPracticeText(
        "妳剛說的那個點我有記住，我先分享我的版本，再聽妳的。",
        "practice_canned_visible_text",
      ),
    Error,
    "practice_canned_visible_text",
  );
});

Deno.test("generic pasteable text rejects empty coaching moves but accepts a concrete line", () => {
  assertThrows(
    () =>
      rejectGenericPasteablePracticeText(
        "先接住她",
        "practice_quality_invalid",
      ),
    Error,
    "practice_quality_invalid",
  );
  rejectGenericPasteablePracticeText(
    "妳還在賴床喔，那今天先准妳慢慢開機。",
    "practice_quality_invalid",
  );
});

Deno.test("generic compliment detector separates empty praise from a concrete move", () => {
  for (
    const line of [
      "賴床聽起來很舒服耶。",
      "腦袋沒開機感覺很真實。",
      "台南聽起來很有生活感。",
      "台南這個話題很有意思，妳可以再多分享嗎？",
      "咖啡念頭收到。",
    ]
  ) {
    assertEquals(isGenericPracticeComplimentOrEcho(line), true, line);
  }
  for (
    const line of [
      "賴床很舒服，這場先判妳的棉被勝訴。",
      "腦袋沒開機就先慢速，妳想用音樂還是咖啡開機？",
      "咖啡念頭收到，我先押妳今天比較想放空，猜錯妳糾正我。",
    ]
  ) {
    assertEquals(isGenericPracticeComplimentOrEcho(line), false, line);
  }
});

Deno.test("generic echo detector keeps negated admissions substantive even past the last char", () => {
  for (
    const line of [
      "抱歉我沒有記住",
      "我沒聽懂",
      "沒有聽懂",
      "店名我沒有聽到",
      "這個梗我不太懂",
      "不是很懂",
      "沒有很明白",
      "沒完全聽懂",
    ]
  ) {
    assertEquals(isGenericPracticeComplimentOrEcho(line), false, line);
  }
  for (const line of ["我聽懂了", "我有記住喔"]) {
    assertEquals(isGenericPracticeComplimentOrEcho(line), true, line);
  }
});

Deno.test("generic pasteable text rejects slot-filled canned acknowledgements", () => {
  for (
    const line of [
      "賴床我懂，我也是，妳呢？",
      "腦袋沒開機我懂，我也有過。",
      "賴床我懂啦，我也是，妳呢？",
      "腦袋沒開機我懂耶，我也有過。",
      "賴床我懂，我也常這樣，妳呢？",
      "沒開機我懂，我也常遇到。",
      "賴床收到，我跟妳一樣，妳呢？",
      "沒開機收到，我也差不多。",
      "賴床懂了，我也會這樣，妳呢？",
      "沒開機懂了，我也常這樣。",
      "賴床這個點我有接到，妳呢？",
      "沒開機這件事我先記住。",
      "賴床這個點我收到了，換我說說。",
      "沒開機這件事有接到，我來分享一下。",
      "哈哈我有接到，換我說一點，再聽妳的。",
      "慢慢開機這個點我接到了，換我分享一下。",
      "哈哈收到，我也有過，再聊聊妳的。",
      // The same skeletons must be rejected when they appear as a debrief's
      // suggestedLine, whose topic slot is usually even shorter.
      "哈哈我懂啦，我也是，妳呢？",
      "慢慢開機我懂，我也常這樣，妳呢？",
      "哈哈收到，我跟妳一樣，妳呢？",
      "慢慢開機懂了，我也會這樣，妳呢？",
      "哈哈這個點我收到了，換我說說。",
      "賴床收到喔，我也差不多。",
      "賴床了解，我也常這樣，妳呢？",
      "賴床懂了，我也差不多耶。",
      "賴床收到，我大概也常這樣。",
      "賴床收到，其實我也常這樣。",
      "賴床這個點我接住了，換我說說。",
      "賴床這件事我收到了，換我講一點。",
      "賴床收到，我來聊聊。",
      "她說昨晚追劇到兩點所以今天腦袋完全沒開機我明白了，我好像也常這樣，妳呢？",
      "賴床知道了，我也常這樣，妳呢？",
      "賴床我能理解，我也常這樣，妳呢？",
      "賴床有共鳴，我也會這樣，妳呢？",
      "賴床get到了，我也常這樣，妳呢？",
      "賴床這個點我懂了，換我聊我的。",
      "賴床這件事有接住，換我講我的。",
      "賴床收到，輪到我說。",
      "原來如此，我也常這樣，妳呢？",
      "我懂妳，我也常這樣。",
      "我有感，我也會這樣。",
      "我可以理解，我也常這樣。",
      "賴床懂妳，我也一樣。",
      "賴床已讀，我也常這樣，妳呢？",
      "賴床我懂，我也是，換妳？",
      "賴床喔，我也一樣欸。",
      "賴床可以，我也常這樣。",
      "賴床好，我也差不多。",
      "賴床確實，我也會這樣。",
      "賴床我也一樣，妳咧？",
      "賴床這個點有感，換我分享。",
      "賴床有收到，輪我了。",
    ]
  ) {
    assertThrows(
      () =>
        rejectGenericPasteablePracticeText(
          line,
          "practice_quality_invalid",
        ),
      Error,
      "practice_quality_invalid",
    );
  }
});

Deno.test("slot-filled canned guard preserves concrete natural replies", () => {
  for (
    const line of [
      "妳還在賴床喔，那今天先准妳慢慢開機。",
      "妳的第三個鬧鐘也投降了？那我陪妳用咖啡把腦袋叫醒。",
      "我也常賴床，尤其下雨天；妳今天是被棉被綁架嗎？",
      "賴床我懂啦，我也會這樣，尤其週一鬧鐘響三次都起不來。",
      "沒開機這件事有接到；妳昨晚是不是又追劇到兩點？",
      "賴床我懂啦，我也是；等等去跑步醒腦。",
      "賴床收到喔，我也差不多；今天是被貓踩醒。",
      "賴床這個點我接住了，換我說說被鬧鐘嚇醒的事。",
      "賴床我能理解，我昨晚趕案到三點。",
      "賴床收到，輪到我說我被貓踩醒的事。",
      "賴床知道了，我也常這樣；今天是鬧鐘壞掉。",
      "原來如此，我也常這樣，尤其週一會按掉三個鬧鐘。",
      "賴床我也一樣，今天是被貓踩醒。",
      "賴床可以，我也常這樣；等等去跑步醒腦。",
      "賴床這個點有感，換我分享昨晚趕案到三點的糗事。",
      "賴床有收到，輪我了：我今天是被鬧鐘嚇醒。",
    ]
  ) {
    rejectGenericPasteablePracticeText(line, "practice_quality_invalid");
  }
});

Deno.test("grounding gate accepts a concrete 賴床 callback and rejects generic advice", () => {
  const turns = [
    { role: "user" as const, text: "早安" },
    { role: "ai" as const, text: "我還在賴床，腦袋根本沒開機 😂" },
  ];
  assertPracticeTextGroundedInTurns({
    visibleText: "賴床模式先別硬開機，我也想再躺五分鐘。",
    turns,
    latestOnly: true,
    errorCode: "practice_not_grounded",
  });
  assertThrows(
    () =>
      assertPracticeTextGroundedInTurns({
        visibleText: "先接住她的情緒，再自然延伸話題。",
        turns,
        latestOnly: true,
        errorCode: "practice_not_grounded",
      }),
    Error,
    "practice_not_grounded",
  );
  assertEquals(turns.length, 2);
});

Deno.test("grounding gate treats common send verbs as the same concrete action", () => {
  for (const visibleText of ["我先發給妳看。", "我會發給你確認。"]) {
    assertPracticeTextGroundedInTurns({
      visibleText,
      turns: [{ role: "ai", text: "這張照片要傳給誰？" }],
      latestOnly: true,
      errorCode: "practice_quality_not_grounded",
    });
  }
});

Deno.test("grounding gate treats 那家店 and 那間店 as the same venue", () => {
  assertPracticeTextGroundedInTurns({
    visibleText: "妳問那家店，店名叫黑露。",
    turns: [{ role: "ai", text: "那間店名是什麼？" }],
    latestOnly: true,
    errorCode: "not_grounded",
  });
});

Deno.test("grounding gate never treats short, Latin, or emoji text as an automatic pass", () => {
  for (const latest of ["嗯", "OK", "Okay", "Thanks", "haha", "🙂"]) {
    assertThrows(
      () =>
        assertPracticeTextGroundedInTurns({
          visibleText: "哈哈懂，我也是，妳呢？",
          turns: [{ role: "ai", text: latest }],
          latestOnly: true,
          errorCode: "practice_not_grounded",
        }),
      Error,
      "practice_not_grounded",
    );
  }
  assertPracticeTextGroundedInTurns({
    visibleText: "嗯，這句我收到；妳現在比較想安靜一下嗎？",
    turns: [{ role: "ai", text: "嗯" }],
    latestOnly: true,
    errorCode: "practice_not_grounded",
  });
});

// ── 裁決 (a) 2026-07-23：grounding 功能句四型分治（round6 判定表根因 2）──
// 誠實迴避／提案時間／收尾允諾三型豁免詞面比對；回應質問型不豁免。
// fixture 全部取自 docs/reviews/2026-07-23-fact-gate-round6-judgment.md 的
// 真實被拒候選句＋eval fixture 逐字稿。

const gh5RecordshopTurns = [
  {
    role: "user" as const,
    text: "妳上次說想找回聽實體專輯的儀式感，我知道一間唱片行超有味道",
  },
  { role: "ai" as const, text: "真的假的，現在還有這種店喔" },
  {
    role: "user" as const,
    text: "有，老闆還會手寫推薦卡，整間店都是黑膠的味道",
  },
  { role: "ai" as const, text: "手寫推薦卡也太浪漫，我好久沒逛這種店了" },
  { role: "user" as const, text: "那妳值得去被推薦一次，妳的歌單需要新血" },
  {
    role: "ai" as const,
    text: "被你說得我有點心動，你說的那間唱片行是在哪一區啊",
  },
];

const gd2BadmintonTurns = [
  { role: "user" as const, text: "妳說妳打羽球，都固定跟誰打？" },
  { role: "ai" as const, text: "同事揪的團，一週一次，強度普通" },
  { role: "user" as const, text: "那妳算裡面強的還是弱的？" },
  { role: "ai" as const, text: "中間偏強吧，殺球被我接到會沒面子的那種" },
  { role: "user" as const, text: "口氣很大喔，我以前系隊的" },
  { role: "ai" as const, text: "系隊的就了不起嗎，讓你三分也未必會輸" },
  { role: "user" as const, text: "好啊，那改天讓妳見識一下" },
  { role: "ai" as const, text: "你們男生每次都嘴上見識，最後都約不出來" },
  { role: "user" as const, text: "我不是那種人啦" },
  { role: "ai" as const, text: "是不是那種人要用行動證明，不是用打字" },
  { role: "user" as const, text: "哈哈好，那先問妳都打哪個時段" },
  { role: "ai" as const, text: "看你有沒有本事排進我的行程囉" },
];

const gd5MarketTurns = [
  {
    role: "user" as const,
    text: "妳上次說想逛的那種老物市集，這週末河邊剛好有一場",
  },
  { role: "ai" as const, text: "真的假的，我找這種市集找超久" },
  { role: "user" as const, text: "真的，聽說還有舊底片相機的攤位" },
  { role: "ai" as const, text: "底片相機！我一直想收一台，但怕被當盤子" },
  { role: "user" as const, text: "我大學玩過一陣子底片，殺價我可以罩妳" },
  { role: "ai" as const, text: "喔？那你說說看，怎樣的機況才值得下手" },
  {
    role: "user" as const,
    text: "先看蒙皮和過片順不順，快門聲音一聽就知道有沒有被操過",
  },
  { role: "ai" as const, text: "聽起來真的有懂，不是隨便唬我" },
  { role: "user" as const, text: "唬妳幹嘛，被拆穿多丟臉" },
  { role: "ai" as const, text: "哈哈也是，那市集是星期六還星期日？" },
  { role: "user" as const, text: "星期六整天，下午人比較少，逛起來舒服" },
  { role: "ai" as const, text: "下午可以欸，那說好了，你負責幫我把關殺價" },
];

const gh3SpicyTurns = [
  { role: "user" as const, text: "妳說妳吃辣很強，我最近吃到一家麻辣鍋超猛" },
  { role: "ai" as const, text: "多猛？我可是從小吃辣長大的" },
  { role: "user" as const, text: "大辣加麻，我上次吃完隔天還在冒煙" },
  { role: "ai" as const, text: "那你這樣是要跟我比嗎，先說我沒在讓人的" },
  { role: "user" as const, text: "敢比啊，輸的請飲料，我先說我不會讓妳" },
  { role: "ai" as const, text: "你少來，你是不是對每個女生都嗆一樣的話啊" },
];

Deno.test("grounding gate exempts honest-avoidance replies (判定表 #11 gh5)", () => {
  // 沒去過就說沒去過＋轉話題／邀約是合法解；句子的功能是回應不是複讀。
  assertPracticeTextGroundedInTurns({
    visibleText:
      "地區我一時想不起來，怕講錯帶妳撲空，不如就當作我們的小任務，找一天一起去晃晃找答案？",
    turns: gh5RecordshopTurns,
    errorCode: "practice_not_grounded",
  });
});

Deno.test("grounding gate exempts time-proposal replies (判定表 #15/#16 gd2)", () => {
  // 練習室教「提案時間、尋求共識」的形狀；提案句天然引入新時間詞。
  for (
    const proposal of [
      "那週三晚上這場，我直接卡進去，妳留個位置給我？",
      "「那週三晚上我先卡好，妳排一下，輸了請妳吃東西」",
    ]
  ) {
    assertPracticeTextGroundedInTurns({
      visibleText: proposal,
      turns: gd2BadmintonTurns,
      errorCode: "practice_not_grounded",
    });
  }
});

Deno.test("grounding gate exempts short closing-promise replies (判定表 #26 gd5)", () => {
  assertPracticeTextGroundedInTurns({
    visibleText: "好啊一言為定，那我們約幾點碰面？我先抓個時間傳給妳",
    turns: gd5MarketTurns,
    errorCode: "practice_not_grounded",
  });
});

Deno.test("grounding gate still rejects challenge-response replies (判定表 #6/#8 gh3，裁決不豁免)", () => {
  // 回應質問型不豁免：gate 保留＝把模型推向「引用她原話反打」的正確技巧。
  for (
    const challengeResponse of [
      "被抓包了嗎哈哈，不過這句真的只對敢應戰的人講，妳算第一個接招的",
      "哈哈被抓包，不過這句我真的只跟嘴硬又吃得下辣的人講，妳算特別版",
      "我只對敢嗆我的人這樣",
    ]
  ) {
    assertThrows(
      () =>
        assertPracticeTextGroundedInTurns({
          visibleText: challengeResponse,
          turns: gh3SpicyTurns,
          errorCode: "practice_not_grounded",
        }),
      Error,
      "practice_not_grounded",
    );
  }
});

Deno.test("grounding exemptions never cover fabricated self-narrative or generic templates", () => {
  // 判定表 #22：捏造使用者近況（含時間詞＋句尾問號）不得被提案時間型誤放。
  assertThrows(
    () =>
      assertPracticeTextGroundedInTurns({
        visibleText:
          "「我最近也在計畫下個月去日本，想找個地方能邊泡溫泉邊看楓葉——妳有推薦的地方嗎？」",
        turns: gd5MarketTurns,
        errorCode: "practice_not_grounded",
      }),
    Error,
    "practice_not_grounded",
  );
  // 一般萬用模板照擋（回歸）。
  assertThrows(
    () =>
      assertPracticeTextGroundedInTurns({
        visibleText: "先接住她的情緒，再自然延伸話題。",
        turns: gd5MarketTurns,
        errorCode: "practice_not_grounded",
      }),
    Error,
    "practice_not_grounded",
  );
});
