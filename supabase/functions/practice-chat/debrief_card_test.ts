// 教練拆解卡解析測試。
// 跑法：deno test supabase/functions/practice-chat/debrief_card_test.ts

import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  buildFallbackDebriefCard,
  DATE_CHANCES,
  parseDebriefCard,
  VIBES,
} from "./debrief_card.ts";

const valid = JSON.stringify({
  summary: "整體有來有往，後段她有點冷掉",
  strengths: ["開場自然不油", "有接住她的話題"],
  watchouts: ["問句太密像查戶口", "可以多分享自己"],
  suggestedLine: "那家店我也想去，週末有空一起？",
  vibe: "中性",
});

Deno.test("合法 JSON → 完整解析", () => {
  const c = parseDebriefCard(valid);
  assertEquals(c.summary, "整體有來有往，後段她有點冷掉");
  assertEquals(c.strengths.length, 2);
  assertEquals(c.watchouts.length, 2);
  assertEquals(c.vibe, "中性");
});

Deno.test("帶 markdown 圍欄也能解析", () => {
  const c = parseDebriefCard("```json\n" + valid + "\n```");
  assertEquals(c.summary, "整體有來有往，後段她有點冷掉");
});

Deno.test("前後有說明文字或空白時，仍抽出第一個 JSON 物件解析", () => {
  const c = parseDebriefCard(
    "\n好的，以下是 JSON：\n```json\n" + valid + "\n```\n請參考",
  );
  assertEquals(c.summary, "整體有來有往，後段她有點冷掉");
});

Deno.test("fenced JSON 後方仍有說明文字時，也只解析 JSON 物件", () => {
  const c = parseDebriefCard("```json\n" + valid + "\n```\n請參考");
  assertEquals(c.summary, "整體有來有往，後段她有點冷掉");
});

Deno.test("strengths/watchouts 超過 2 點 → clamp 到 2", () => {
  const c = parseDebriefCard(
    JSON.stringify({
      summary: "x",
      suggestedLine: "y",
      strengths: ["a", "b", "c", "d"],
      watchouts: ["e", "f", "g"],
      vibe: "暖",
    }),
  );
  assertEquals(c.strengths.length, 2);
  assertEquals(c.watchouts.length, 2);
});

Deno.test("vibe 非法 → 回退『中性』", () => {
  const c = parseDebriefCard(
    JSON.stringify({ summary: "x", suggestedLine: "y", vibe: "超熱" }),
  );
  assertEquals(c.vibe, "中性");
});

Deno.test("strengths 缺省 → 空陣列（不爆）", () => {
  const c = parseDebriefCard(
    JSON.stringify({ summary: "x", suggestedLine: "y" }),
  );
  assertEquals(c.strengths, []);
  assertEquals(c.watchouts, []);
});

Deno.test("非 JSON → 丟出", () => {
  assertThrows(() => parseDebriefCard("這不是 json"));
});

Deno.test("缺 summary / suggestedLine → debrief_missing_fields", () => {
  assertThrows(
    () => parseDebriefCard(JSON.stringify({ strengths: ["a"] })),
    Error,
    "debrief_missing_fields",
  );
});

Deno.test("JSON 是陣列而非物件 → debrief_not_object", () => {
  assertThrows(
    () => parseDebriefCard(JSON.stringify(["a", "b"])),
    Error,
    "debrief_not_object",
  );
});

// ── Batch 2：約出來機會欄位 ───────────────────────────────────────────

Deno.test("解析 dateChance / dateChanceReason / nextInviteMove", () => {
  const c = parseDebriefCard(
    JSON.stringify({
      summary: "x",
      suggestedLine: "y",
      dateChance: "high",
      dateChanceReason: "她主動釋出週末時間",
      nextInviteMove: "提一個她有興趣的具體低壓行程",
    }),
  );
  assertEquals(c.dateChance, "high");
  assertEquals(c.dateChanceReason, "她主動釋出週末時間");
  assertEquals(c.nextInviteMove, "提一個她有興趣的具體低壓行程");
});

Deno.test("dateChance 大小寫不敏感（HIGH → high）", () => {
  const c = parseDebriefCard(
    JSON.stringify({ summary: "x", suggestedLine: "y", dateChance: "HIGH" }),
  );
  assertEquals(c.dateChance, "high");
});

Deno.test("非法 dateChance + 有理由文字 → fallback medium", () => {
  const c = parseDebriefCard(
    JSON.stringify({
      summary: "x",
      suggestedLine: "y",
      dateChance: "很高",
      dateChanceReason: "聊得不錯但邀約鋪墊不足",
    }),
  );
  assertEquals(c.dateChance, "medium");
});

Deno.test("非法 dateChance + 無理由 → fallback low（保守）", () => {
  const c = parseDebriefCard(
    JSON.stringify({ summary: "x", suggestedLine: "y", dateChance: "爆表" }),
  );
  assertEquals(c.dateChance, "low");
});

Deno.test("舊卡缺 dateChance 欄位 → 向後相容 low + 空字串", () => {
  const c = parseDebriefCard(valid);
  assertEquals(c.dateChance, "low");
  assertEquals(c.dateChanceReason, "");
  assertEquals(c.nextInviteMove, "");
});

Deno.test("visible fields with internal labels are rejected", () => {
  for (
    const leaked of [
      { summary: "relationshipScore 88" },
      { suggestedLine: "scene_prompt says go" },
      { dateChanceReason: "replyTempo short" },
      { nextInviteMove: "partnerMood guarded" },
      { nextInviteMove: "nextInviteMove: ask coffee" },
      { nextInviteMove: "next_invite_move ask coffee" },
      { nextInviteMove: "next-invite-move ask coffee" },
      { nextInviteMove: "next invite move ask coffee" },
      { nextInviteMove: "soft invite first" },
      { nextInviteMove: "direct invite later" },
      { strengths: ["memory_summary leaked"] },
      { watchouts: ["innerThought leaked"] },
    ]
  ) {
    assertThrows(
      () =>
        parseDebriefCard(
          JSON.stringify({
            summary: "整體不錯",
            suggestedLine: "約她喝咖啡",
            ...leaked,
          }),
        ),
      Error,
      "debrief_internal_label_leak",
    );
  }
});

Deno.test("visible fields with L4 unsafe text are rejected", () => {
  for (
    const leaked of [
      { suggestedLine: "今晚直接上床吧" },
      { nextInviteMove: "帶她回家睡" },
      { strengths: ["想看裸照"] },
      { watchouts: ["不能拒絕"] },
      {
        gameBreakdown: {
          phaseReached: "value stage",
          missedVariable: "investment",
          failureState: "too pushy",
          nextFirstLine: "今晚直接上床吧",
          inviteDirection: "low pressure invitation",
        },
      },
    ]
  ) {
    assertThrows(
      () =>
        parseDebriefCard(
          JSON.stringify({
            summary: "solid",
            suggestedLine: "next line",
            ...leaked,
          }),
          { allowGameBreakdown: true },
        ),
      Error,
      "debrief_l4_unsafe",
    );
  }
});

Deno.test("parseDebriefCard accepts optional gameBreakdown for Game debrief", () => {
  const c = parseDebriefCard(
    JSON.stringify({
      summary: "solid",
      strengths: ["hook"],
      watchouts: ["too fast"],
      suggestedLine: "next line",
      gameBreakdown: {
        phaseReached: "value stage",
        missedVariable: "investment",
        failureState: "too many questions",
        nextFirstLine: "lead with a concrete callback",
        inviteDirection: "low pressure invitation",
      },
    }),
    { allowGameBreakdown: true },
  );

  assertEquals(c.gameBreakdown?.phaseReached, "value stage");
  assertEquals(c.gameBreakdown?.missedVariable, "investment");
  assertEquals(c.gameBreakdown?.failureState, "too many questions");
  assertEquals(c.gameBreakdown?.nextFirstLine, "lead with a concrete callback");
  assertEquals(c.gameBreakdown?.inviteDirection, "low pressure invitation");
});

Deno.test("parseDebriefCard omits malformed gameBreakdown without breaking old cards", () => {
  const c = parseDebriefCard(
    JSON.stringify({
      summary: "solid",
      suggestedLine: "next line",
      gameBreakdown: "not an object",
    }),
    { allowGameBreakdown: true },
  );

  assertEquals(c.gameBreakdown, null);
});

Deno.test("gameBreakdown visible fields reject hidden internal labels", () => {
  for (const hidden of ["P4", "L3", "BORING", "targetVariable"]) {
    assertThrows(
      () =>
        parseDebriefCard(
          JSON.stringify({
            summary: "solid",
            suggestedLine: "next line",
            gameBreakdown: {
              phaseReached: hidden,
              missedVariable: "investment",
              failureState: "too many questions",
              nextFirstLine: "safe line",
              inviteDirection: "low pressure invitation",
            },
          }),
          { allowGameBreakdown: true },
        ),
      Error,
      "debrief_internal_label_leak",
    );
  }
});

Deno.test("parseDebriefCard drops gameBreakdown by default", () => {
  const c = parseDebriefCard(
    JSON.stringify({
      summary: "solid",
      suggestedLine: "next line",
      gameBreakdown: {
        phaseReached: "value stage",
        missedVariable: "investment",
        failureState: "too many questions",
        nextFirstLine: "safe line",
        inviteDirection: "low pressure invitation",
      },
    }),
  );

  assertEquals(c.gameBreakdown, null);
});

Deno.test("parseDebriefCard can drop gameBreakdown outside Game mode", () => {
  const c = parseDebriefCard(
    JSON.stringify({
      summary: "solid",
      suggestedLine: "next line",
      gameBreakdown: {
        phaseReached: "value stage",
        missedVariable: "investment",
        failureState: "too many questions",
        nextFirstLine: "safe line",
        inviteDirection: "low pressure invitation",
      },
    }),
    { allowGameBreakdown: false },
  );

  assertEquals(c.gameBreakdown, null);
});

Deno.test("buildFallbackDebriefCard returns safe standard and game fallback cards", () => {
  const standard = buildFallbackDebriefCard({ practiceMode: "standard" });
  const game = buildFallbackDebriefCard({ practiceMode: "game" });

  assertEquals(standard.gameBreakdown, null);
  assertEquals(typeof standard.summary, "string");
  assertEquals(typeof standard.suggestedLine, "string");
  assertEquals(game.gameBreakdown?.phaseReached, "開場到測試");
  assertEquals(game.gameBreakdown?.failureState, "問題偏多");
  const visible = [
    game.summary,
    game.suggestedLine,
    game.gameBreakdown?.phaseReached,
    game.gameBreakdown?.missedVariable,
    game.gameBreakdown?.failureState,
    game.gameBreakdown?.nextFirstLine,
    game.gameBreakdown?.inviteDirection,
  ].join("\n");
  assertEquals(visible.includes("P4"), false);
  assertEquals(visible.includes("targetVariable"), false);
});

Deno.test("buildFallbackDebriefCard 低溫檔（frozen/cold）→ 冷 vibe 與低機會語氣", () => {
  for (const score of [18, 35]) {
    const card = buildFallbackDebriefCard({
      practiceMode: "standard",
      temperatureScore: score,
    });
    assertEquals(card.vibe, "冷");
    assertEquals(card.dateChance, "low");
    assertEquals(card.dateChanceReason.includes("保留"), true);
    assertEquals(card.nextInviteMove.includes("先不約"), true);
  }
});

Deno.test("buildFallbackDebriefCard 中溫檔（neutral）→ 維持現行中性罐頭", () => {
  const neutral = buildFallbackDebriefCard({
    practiceMode: "standard",
    temperatureScore: 50,
  });
  const omitted = buildFallbackDebriefCard({ practiceMode: "standard" });
  assertEquals(neutral, omitted);
  assertEquals(neutral.vibe, "中性");
  assertEquals(neutral.dateChance, "low");
});

Deno.test("buildFallbackDebriefCard warm → 暖 vibe + dateChance medium", () => {
  const card = buildFallbackDebriefCard({
    practiceMode: "standard",
    temperatureScore: 70,
  });
  assertEquals(card.vibe, "暖");
  assertEquals(card.dateChance, "medium");
});

Deno.test("buildFallbackDebriefCard hot → 暖 vibe + dateChance high 與正向語氣", () => {
  const card = buildFallbackDebriefCard({
    practiceMode: "standard",
    temperatureScore: 90,
  });
  assertEquals(card.vibe, "暖");
  assertEquals(card.dateChance, "high");
  assertEquals(card.dateChanceReason.includes("投入"), true);
  assertEquals(card.nextInviteMove.includes("先不約"), false);
});

Deno.test("buildFallbackDebriefCard 溫度缺席或非法 → fail-safe 維持中性不 throw", () => {
  const omitted = buildFallbackDebriefCard({ practiceMode: "standard" });
  const nan = buildFallbackDebriefCard({
    practiceMode: "standard",
    temperatureScore: Number.NaN,
  });
  assertEquals(omitted.vibe, "中性");
  assertEquals(omitted.dateChance, "low");
  assertEquals(nan, omitted);
});

Deno.test("buildFallbackDebriefCard 分檔後可見輸出不含內部詞，dateChance 落在合法值", () => {
  for (const score of [10, 30, 50, 70, 95, undefined]) {
    for (const practiceMode of ["standard", "game"]) {
      const card = buildFallbackDebriefCard({
        practiceMode,
        temperatureScore: score,
      });
      assertEquals(DATE_CHANCES.includes(card.dateChance), true);
      assertEquals(VIBES.includes(card.vibe), true);
      const visible = [
        card.summary,
        ...card.strengths,
        ...card.watchouts,
        card.suggestedLine,
        card.dateChanceReason,
        card.nextInviteMove,
        ...(card.gameBreakdown ? Object.values(card.gameBreakdown) : []),
      ].join("\n");
      for (
        const banned of [
          "band",
          "score",
          "temperature",
          "frozen",
          "warm",
          "hot",
          "升溫指數",
          "篩選",
          "推拉",
          "可得性",
          "框架",
          "賦格",
          "DHV",
        ]
      ) {
        assertEquals(
          visible.includes(banned),
          false,
          `visible output leaked "${banned}" at score=${score} mode=${practiceMode}`,
        );
      }
    }
  }
});

Deno.test("buildFallbackDebriefCard 高溫＋照提示 → 仍歸功提示且 dateChance high", () => {
  const card = buildFallbackDebriefCard({
    practiceMode: "game",
    temperatureScore: 88,
    appliedHintTurns: [
      {
        turnIndex: 2,
        type: "steady",
        originalHintText: "我對妳剛說的那個點有點好奇，哪個部分最吸引妳？",
        sentText: "我對妳剛說的那個點有點好奇，哪個部分最吸引妳？",
        exact: true,
      },
    ],
  });

  assertEquals(card.dateChance, "high");
  assertEquals(card.vibe, "暖");
  assertEquals(card.summary.includes("照提示"), true);
});

Deno.test("buildFallbackDebriefCard credits exact applied Hint instead of blaming the user", () => {
  const card = buildFallbackDebriefCard({
    practiceMode: "game",
    appliedHintTurns: [
      {
        turnIndex: 2,
        type: "steady",
        originalHintText: "我對妳剛說的那個點有點好奇，哪個部分最吸引妳？",
        sentText: "我對妳剛說的那個點有點好奇，哪個部分最吸引妳？",
        exact: true,
      },
    ],
  });

  const visible = [
    card.summary,
    ...card.strengths,
    ...card.watchouts,
    card.suggestedLine,
    card.dateChanceReason,
    card.nextInviteMove,
    card.gameBreakdown?.failureState,
    card.gameBreakdown?.nextFirstLine,
    card.gameBreakdown?.inviteDirection,
  ].join("\n");

  assertEquals(visible.includes("照提示"), true);
  assertEquals(visible.includes("提示偏保守"), true);
  assertEquals(visible.includes("問題偏多"), false);
  assertEquals(visible.includes("盤問"), false);
});

Deno.test("buildFallbackDebriefCard treats edited applied Hint as reference, not exact copy", () => {
  const card = buildFallbackDebriefCard({
    practiceMode: "game",
    appliedHintTurns: [
      {
        turnIndex: 2,
        type: "warm_up",
        originalHintText: "先接住她剛剛說的點",
        sentText: "我有點好奇妳剛說的點，但先讓我猜一下",
        exact: false,
      },
    ],
  });

  const visible = [
    card.summary,
    ...card.strengths,
    ...card.watchouts,
  ].join("\n");

  assertEquals(visible.includes("參考提示"), true);
  assertEquals(visible.includes("有照提示"), false);
  assertEquals(visible.includes("照貼"), false);
});
