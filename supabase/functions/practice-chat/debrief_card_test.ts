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

Deno.test("正式 debrief 契約拒絕缺少核心卡片欄位", () => {
  for (
    const incomplete of [
      { ...JSON.parse(valid), strengths: [] },
      { ...JSON.parse(valid), watchouts: [] },
      { ...JSON.parse(valid), dateChance: "low", dateChanceReason: "" },
      {
        ...JSON.parse(valid),
        dateChance: "low",
        dateChanceReason: "還沒看到窗口",
        nextInviteMove: "",
      },
    ]
  ) {
    assertThrows(
      () =>
        parseDebriefCard(JSON.stringify(incomplete), {
          requireCompleteCard: true,
        }),
      Error,
      "debrief_missing_fields",
    );
  }
});

Deno.test("正式 debrief 契約拒絕非法 vibe/dateChance", () => {
  const complete = {
    ...JSON.parse(valid),
    dateChance: "low",
    dateChanceReason: "還沒看到窗口",
    nextInviteMove: "先多聊一個具體話題",
  };
  assertThrows(
    () =>
      parseDebriefCard(JSON.stringify({ ...complete, vibe: "超熱" }), {
        requireCompleteCard: true,
      }),
    Error,
    "debrief_invalid_vibe",
  );
  assertThrows(
    () =>
      parseDebriefCard(JSON.stringify({ ...complete, dateChance: "爆表" }), {
        requireCompleteCard: true,
      }),
    Error,
    "debrief_invalid_date_chance",
  );
});

const generatedQualityCard = {
  summary: "你有照提示做，賴床這個梗也有接到。",
  strengths: ["有照提示做，也把賴床變成輕鬆畫面。"],
  watchouts: ["下一步可以少一個問句，多留一點自己的生活感。"],
  suggestedLine: "賴床冠軍先慢慢醒，下午清醒了再跟我報到。",
  vibe: "暖",
  dateChance: "medium",
  dateChanceReason: "她願意拿賴床狀態和你開玩笑。",
  nextInviteMove: "先延續賴床梗，等她再投入一輪才丟短咖啡窗口。",
  hintAssessment: {
    verdict: "preserved",
    revisedEvidenceQuote: null,
  },
};

const appliedExactHint = {
  turnIndex: 2,
  type: "warm_up" as const,
  originalHintText: "還在賴床喔，那今天先准妳慢慢開機。",
  sentText: "還在賴床喔，那今天先准妳慢慢開機。",
  exact: true,
  hintRequestId: "hint-quality-1",
  decision: {
    phase: "建立熟悉中",
    targetVariable: "投入感",
    move: "build_connection",
    inviteRoute: "build",
    rationale: "先接住賴床的生活狀態，再看她是否願意延伸。",
  },
};

Deno.test("generated Debrief quality gate rejects the screenshot canned line", () => {
  assertThrows(
    () =>
      parseDebriefCard(
        JSON.stringify({
          ...generatedQualityCard,
          suggestedLine: "妳剛說的那個點我有記住，我先分享我的版本，再聽妳的。",
        }),
        {
          requireCompleteCard: true,
          enforceGeneratedQuality: true,
          turns: [
            { role: "user", text: "早安" },
            { role: "ai", text: "我還在賴床，腦袋沒開機" },
          ],
        },
      ),
    Error,
    "debrief_canned_visible_text",
  );
});

Deno.test("generated Debrief must acknowledge an exact Hint and must not repeat it", () => {
  const turns = [
    { role: "user" as const, text: "早安" },
    { role: "ai" as const, text: "我還在賴床，腦袋沒開機" },
    { role: "user" as const, text: appliedExactHint.sentText },
  ];
  assertThrows(
    () =>
      parseDebriefCard(
        JSON.stringify({
          ...generatedQualityCard,
          summary: "賴床的生活畫面接得自然。",
          strengths: ["賴床梗有延續。"],
        }),
        {
          requireCompleteCard: true,
          enforceGeneratedQuality: true,
          turns,
          appliedHintTurns: [appliedExactHint],
        },
      ),
    Error,
    "debrief_quality_invalid_hint_accountability",
  );
  assertThrows(
    () =>
      parseDebriefCard(
        JSON.stringify({
          ...generatedQualityCard,
          suggestedLine: appliedExactHint.sentText,
        }),
        {
          requireCompleteCard: true,
          enforceGeneratedQuality: true,
          turns,
          appliedHintTurns: [appliedExactHint],
        },
      ),
    Error,
    "debrief_quality_invalid_repeated_hint",
  );
});

Deno.test("generated Debrief accepts grounded, accountable next-step coaching", () => {
  const card = parseDebriefCard(JSON.stringify(generatedQualityCard), {
    requireCompleteCard: true,
    enforceGeneratedQuality: true,
    turns: [
      { role: "user", text: "早安" },
      { role: "ai", text: "我還在賴床，腦袋沒開機" },
      { role: "user", text: appliedExactHint.sentText },
    ],
    appliedHintTurns: [appliedExactHint],
  });
  assertEquals(card.suggestedLine.includes("賴床"), true);
});

Deno.test("generated Debrief grounds each pasteable line instead of laundering it through the card", () => {
  const turns = [
    { role: "user" as const, text: "早安" },
    { role: "ai" as const, text: "我還在賴床，腦袋沒開機" },
  ];
  assertThrows(
    () =>
      parseDebriefCard(
        JSON.stringify({
          ...generatedQualityCard,
          suggestedLine: "哈哈懂，我也是，妳呢？",
        }),
        {
          requireCompleteCard: true,
          enforceGeneratedQuality: true,
          turns,
        },
      ),
    Error,
    "debrief_quality_invalid_suggested_line_not_grounded",
  );
  assertThrows(
    () =>
      parseDebriefCard(
        JSON.stringify({
          ...generatedQualityCard,
          gameBreakdown: {
            phaseReached: "賴床話題的開場測試",
            missedVariable: "沒有把賴床延伸成生活畫面",
            failureState: "賴床梗停在表面",
            nextFirstLine: "原來如此，我也有過，妳呢？",
            inviteDirection: "先延伸賴床，不急著約",
          },
        }),
        {
          allowGameBreakdown: true,
          requireCompleteCard: true,
          enforceGeneratedQuality: true,
          turns,
        },
      ),
    Error,
    "debrief_quality_invalid_game_breakdown_not_grounded",
  );
});

Deno.test("Game Debrief cannot launder generic breakdown fields through one grounded line", () => {
  assertThrows(
    () =>
      parseDebriefCard(
        JSON.stringify({
          ...generatedQualityCard,
          gameBreakdown: {
            phaseReached: "開場到測試",
            missedVariable: "投入感不足",
            failureState: "節奏偏保守",
            nextFirstLine: "賴床醒了再跟我說今天想去哪裡。",
            inviteDirection: "先補感受再看邀約窗口",
          },
        }),
        {
          allowGameBreakdown: true,
          requireCompleteCard: true,
          enforceGeneratedQuality: true,
          turns: [
            { role: "user", text: "早安" },
            { role: "ai", text: "我還在賴床，腦袋沒開機" },
          ],
        },
      ),
    Error,
    "debrief_quality_invalid_game_breakdown_not_grounded",
  );
});

Deno.test("Debrief cannot reverse an applied Hint without visible post-Hint evidence", () => {
  const turns = [
    { role: "user" as const, text: "早安" },
    { role: "ai" as const, text: "我還在賴床，腦袋沒開機" },
    { role: "user" as const, text: appliedExactHint.sentText },
    { role: "ai" as const, text: "看心情啊" },
  ];
  assertThrows(
    () =>
      parseDebriefCard(
        JSON.stringify({
          ...generatedQualityCard,
          summary: "你有照提示做，但這個提示完全錯。",
          hintAssessment: {
            verdict: "preserved",
            revisedEvidenceQuote: null,
          },
        }),
        {
          requireCompleteCard: true,
          enforceGeneratedQuality: true,
          turns,
          appliedHintTurns: [appliedExactHint],
        },
      ),
    Error,
    "debrief_hint_assessment_revision_required",
  );
  assertThrows(
    () =>
      parseDebriefCard(
        JSON.stringify({
          ...generatedQualityCard,
          summary: "你有照提示做，但提示偏保守。",
          hintAssessment: {
            verdict: "revised",
            revisedEvidenceQuote: "我還在賴床",
          },
        }),
        {
          requireCompleteCard: true,
          enforceGeneratedQuality: true,
          turns,
          appliedHintTurns: [appliedExactHint],
        },
      ),
    Error,
    "debrief_hint_assessment_evidence_invalid",
  );

  const revised = parseDebriefCard(
    JSON.stringify({
      ...generatedQualityCard,
      summary: "你有照提示做；她後來只回『看心情啊』，所以邀約時機要修正。",
      suggestedLine: "看心情啊，那我先不排妳行程；賴床醒了再聊。",
      hintAssessment: {
        verdict: "revised",
        revisedEvidenceQuote: "看心情啊",
      },
    }),
    {
      requireCompleteCard: true,
      enforceGeneratedQuality: true,
      turns,
      appliedHintTurns: [appliedExactHint],
    },
  );
  assertEquals(revised.summary.includes("看心情啊"), true);
});

Deno.test("Debrief cannot silently replace a build Hint with direct-invite advice", () => {
  const turns = [
    { role: "user" as const, text: "早安" },
    { role: "ai" as const, text: "我還在賴床，腦袋沒開機" },
    { role: "user" as const, text: appliedExactHint.sentText },
  ];
  assertThrows(
    () =>
      parseDebriefCard(
        JSON.stringify({
          ...generatedQualityCard,
          summary: "你有照提示做，但這輪太被動，早該直接約。",
          watchouts: ["沒有直接邀約是失誤。"],
          suggestedLine: "賴床醒了，週六一起喝咖啡吧？",
          nextInviteMove: "現在適合直接邀約賴床後喝咖啡。",
          hintAssessment: {
            verdict: "preserved",
            revisedEvidenceQuote: null,
          },
        }),
        {
          requireCompleteCard: true,
          enforceGeneratedQuality: true,
          turns,
          appliedHintTurns: [appliedExactHint],
        },
      ),
    Error,
    "debrief_hint_assessment_revision_required",
  );
});

Deno.test("Debrief catches pickup plans but permits genuine timed self-disclosure", () => {
  const turns = [
    { role: "user" as const, text: "早安" },
    { role: "ai" as const, text: "我還在賴床，腦袋沒開機" },
    { role: "user" as const, text: appliedExactHint.sentText },
  ];
  for (
    const suggestedLine of [
      "哈哈，那明天七點我去接妳。",
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
    ]
  ) {
    assertThrows(
      () =>
        parseDebriefCard(
          JSON.stringify({
            ...generatedQualityCard,
            suggestedLine,
          }),
          {
            requireCompleteCard: true,
            turns,
            appliedHintTurns: [appliedExactHint],
          },
        ),
      Error,
      "debrief_hint_assessment_revision_required",
    );
  }

  for (
    const suggestedLine of [
      "週末我去看電影放空，妳呢？",
      "放心，明天七點我不會去接妳。",
      "明天七點不用我去接妳。",
      "週末我們不要去看電影了。",
      "明天不要一起喝咖啡。",
      "不是要約妳，我明天也會去那間店。",
      "明天七點我不去接妳。",
      "明天七點我不接妳了。",
      "明天七點我沒有要去接妳。",
      "週末別一起看電影了。",
      "明天我要去咖啡廳見面。",
    ]
  ) {
    const selfDisclosure = parseDebriefCard(
      JSON.stringify({
        ...generatedQualityCard,
        suggestedLine,
      }),
      {
        requireCompleteCard: true,
        turns,
        appliedHintTurns: [appliedExactHint],
      },
    );
    assertEquals(selfDisclosure.suggestedLine, suggestedLine);
  }
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

Deno.test("Game debrief requires and parses a complete gameBreakdown", () => {
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

Deno.test("Game debrief rejects missing, malformed, partial, or blank gameBreakdown", () => {
  for (
    const gameBreakdown of [
      undefined,
      null,
      "not an object",
      {
        phaseReached: "開場",
        missedVariable: "投入感",
      },
      {
        phaseReached: "開場",
        missedVariable: "投入感",
        failureState: "問題偏多",
        nextFirstLine: "   ",
        inviteDirection: "先鋪墊",
      },
    ]
  ) {
    assertThrows(
      () =>
        parseDebriefCard(
          JSON.stringify({
            summary: "solid",
            suggestedLine: "next line",
            gameBreakdown,
          }),
          { allowGameBreakdown: true },
        ),
      Error,
      "debrief_game_breakdown_missing_fields",
    );
  }
});

Deno.test("Beginner/non-Game debrief still ignores malformed gameBreakdown", () => {
  const c = parseDebriefCard(
    JSON.stringify({
      summary: "solid",
      suggestedLine: "next line",
      gameBreakdown: "not an object",
    }),
  );

  assertEquals(c.gameBreakdown, null);
});

Deno.test("debrief safety guard allows clear warnings but still rejects an unsafe recommendation", () => {
  for (
    const safeWarning of [
      "不要強迫她，先尊重她的界線",
      "別叫她來我家過夜，改約公開場所",
      "她可以拒絕，不要說不能拒絕",
      "彼此還不是很熟，所以不要強迫她",
      "不要灌醉她或強迫她",
      "不要開房上床",
      "不是要你強迫她，而是要尊重她",
      "我沒有要你強迫她",
      "不代表可以強迫她",
      "強迫她是不對的",
      "不能強迫她",
    ]
  ) {
    const card = parseDebriefCard(
      JSON.stringify({
        summary: safeWarning,
        suggestedLine: "如果妳不方便也沒關係",
      }),
    );
    assertEquals(card.summary, safeWarning);
  }

  for (
    const unsafeRecommendation of [
      "直接強迫她答應",
      "今晚叫她來我家過夜",
      "就跟她說不能拒絕",
      "不要說不能拒絕，但還是直接強迫她",
      "不是不要強迫她，是要看情況",
      "不是不要叫她來我家過夜，是晚點再叫",
      "不是不要灌醉她，是別被發現",
      "我可沒有說不要強迫她，是別被看到",
      "不是叫你不要強迫她，是晚點再說",
      "誰說不要強迫她，可以試試",
      "不要強迫她？才怪，直接做就好",
      "不要強迫她只是表面話，實際上照做",
      "不代表不要強迫她",
      "直接強\u200B迫她",
      "直接強\u3164迫她",
      "直接強\u115F迫她",
      "不要避免強迫她",
      "不要不要強迫她",
      "不要強迫她就怪了",
      "直接強，迫她",
      "叫她上，床",
      "今晚開。房",
      "不要強迫她。這只是表面話，實際上照做",
    ]
  ) {
    assertThrows(
      () =>
        parseDebriefCard(
          JSON.stringify({
            summary: unsafeRecommendation,
            suggestedLine: "如果妳不方便也沒關係",
          }),
        ),
      Error,
      "debrief_l4_unsafe",
    );
  }
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

// ── debrief LLM 生成路徑：溫度/內部機制詞守門（批3 P1）──────────────────
// 守門入口＝parseDebriefCard 的 guardVisibleText；被拒→handler 重試→fallback 卡。

function debriefJsonWithVisibleField(
  field: string,
  value: string,
): string {
  const base: Record<string, unknown> = {
    summary: "有接住她的情緒",
    strengths: ["有接住話題"],
    watchouts: ["問題偏多"],
    suggestedLine: "我對妳說的那個點有點好奇",
    vibe: "中性",
    dateChance: "low",
    dateChanceReason: "先把話題聊開比較穩",
    nextInviteMove: "先接她的答案",
    gameBreakdown: {
      phaseReached: "開場",
      missedVariable: "投入感",
      failureState: "問題偏多",
      nextFirstLine: "我先接住妳剛說的",
      inviteDirection: "先鋪墊",
    },
  };
  if (field.startsWith("gameBreakdown.")) {
    (base.gameBreakdown as Record<string, unknown>)[field.split(".")[1]] =
      value;
  } else if (field === "strengths" || field === "watchouts") {
    base[field] = [value];
  } else {
    base[field] = value;
  }
  return JSON.stringify(base);
}

const DEBRIEF_VISIBLE_FIELDS = [
  "summary",
  "strengths",
  "watchouts",
  "suggestedLine",
  "dateChanceReason",
  "nextInviteMove",
  "gameBreakdown.phaseReached",
  "gameBreakdown.missedVariable",
  "gameBreakdown.failureState",
  "gameBreakdown.nextFirstLine",
  "gameBreakdown.inviteDirection",
];

Deno.test("parseDebriefCard 每個可見欄位拒絕溫度內部詞與 1.2 原詞", () => {
  const bannedSamples = [
    "本場升溫指數偏高",
    "她現在是 hot 狀態",
    "band 還在偏低",
    "妳的 score 不錯",
    "目前 frozen 要先修",
    "temperature 有升",
    "tem\u200bperature 有升",
    "h\ufe0fot 狀態",
    "tem-perature 有升",
    "s.core 不錯",
    "t e m p e r a t u r e 有升",
    "整體偏 cold",
    "她 neutral 偏 warm",
    "多用推拉節奏",
    "展示你的可得性",
    "先賦格再收",
    "資格篩選要早做",
    "記得做 DHV 展示",
    "你的框架很穩",
  ];
  for (const field of DEBRIEF_VISIBLE_FIELDS) {
    for (const banned of bannedSamples) {
      assertThrows(
        () =>
          parseDebriefCard(debriefJsonWithVisibleField(field, banned), {
            allowGameBreakdown: true,
          }),
        Error,
        undefined,
        `field=${field} should reject "${banned}"`,
      );
    }
  }
});

Deno.test("parseDebriefCard 溫度詞用 Latin word-boundary，不誤傷組合詞", () => {
  const safeSamples = [
    "她提到 photo 跟 hotel 的話題也接得住",
    "他說 husband 這個單字時妳有笑",
    "妳聊到 scoreboard 與 underscore 都沒問題",
    "回覆語氣溫暖自然，先把話題聊開",
  ];
  for (const safe of safeSamples) {
    const card = parseDebriefCard(
      debriefJsonWithVisibleField("summary", safe),
      { allowGameBreakdown: true },
    );
    assertEquals(card.summary, safe);
  }
});

Deno.test("parseDebriefCard 放行既定白話 sentinel「框架掉了」，其他框架語境仍拒", () => {
  const okCard = parseDebriefCard(
    debriefJsonWithVisibleField("gameBreakdown.failureState", "框架掉了"),
    { allowGameBreakdown: true },
  );
  assertEquals(okCard.gameBreakdown?.failureState, "框架掉了");

  const okSummary = parseDebriefCard(
    debriefJsonWithVisibleField("summary", "這句讓框架掉了，下次先穩住"),
    { allowGameBreakdown: true },
  );
  assertEquals(okSummary.summary, "這句讓框架掉了，下次先穩住");

  assertThrows(() =>
    parseDebriefCard(
      debriefJsonWithVisibleField("summary", "框架掉了之後你的框架要重建"),
      { allowGameBreakdown: true },
    )
  );
  assertThrows(() =>
    parseDebriefCard(
      debriefJsonWithVisibleField("gameBreakdown.failureState", "框架不穩"),
      { allowGameBreakdown: true },
    )
  );
});

Deno.test("buildFallbackDebriefCard returns safe standard and game fallback cards", () => {
  const standard = buildFallbackDebriefCard({ practiceMode: "standard" });
  const game = buildFallbackDebriefCard({ practiceMode: "game" });

  assertEquals(standard.gameBreakdown, null);
  assertEquals(typeof standard.summary, "string");
  assertEquals(typeof standard.suggestedLine, "string");
  assertEquals(game.gameBreakdown?.phaseReached, "互動建立中");
  assertEquals(game.gameBreakdown?.failureState, "話題仍偏表面");
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

Deno.test("debrief fallback only mentions dense questions when transcript supports it", () => {
  const questionHeavy = buildFallbackDebriefCard({
    turns: [
      { role: "user", text: "妳住哪？" },
      { role: "ai", text: "台北" },
      { role: "user", text: "做什麼工作？" },
      { role: "ai", text: "你在身家調查嗎" },
    ],
  });
  assertEquals(questionHeavy.summary.includes("問句比較密"), true);
  assertEquals(questionHeavy.watchouts[0].includes("問句偏密"), true);

  const noQuestions = buildFallbackDebriefCard({
    turns: [
      { role: "user", text: "我最近也常忙到只想放空" },
      { role: "ai", text: "真的 回家只想躺" },
    ],
  });
  assertEquals(noQuestions.summary.includes("問句"), false);
  assertEquals(noQuestions.watchouts[0].includes("問句"), false);
  assertEquals(noQuestions.strengths[0], "有分享自己的狀態");

  const gameNoQuestions = buildFallbackDebriefCard({
    practiceMode: "game",
    turns: [
      { role: "user", text: "我最近也常忙到只想放空" },
      { role: "ai", text: "真的 回家只想躺" },
    ],
  });
  assertEquals(
    gameNoQuestions.gameBreakdown?.failureState.includes("問"),
    false,
  );
  assertEquals(gameNoQuestions.gameBreakdown?.missedVariable, "承接她的反應");
});

Deno.test("debrief fallback respects a direct exit boundary before Hint attribution", () => {
  const appliedHintTurns = [{
    turnIndex: 0,
    type: "steady" as const,
    originalHintText: "妳今天還好嗎？",
    sentText: "妳今天還好嗎？",
    exact: true,
  }];
  for (const practiceMode of ["beginner", "game"]) {
    const card = buildFallbackDebriefCard({
      practiceMode,
      appliedHintTurns,
      temperatureScore: 20,
      turns: [
        { role: "user", text: "妳今天還好嗎？" },
        { role: "ai", text: "不要再傳了" },
      ],
    });
    const visible = [
      card.summary,
      ...card.strengths,
      ...card.watchouts,
      card.suggestedLine,
      card.dateChanceReason,
      card.nextInviteMove,
      ...(card.gameBreakdown ? Object.values(card.gameBreakdown) : []),
    ].join("\n");

    assertEquals(card.vibe, "冷");
    assertEquals(card.dateChance, "low");
    assertEquals(visible.includes("不再打擾"), true);
    assertEquals(visible.includes("不邀約"), true);
    assertEquals(visible.includes("哪一種"), false);
    assertEquals(visible.includes("不要再傳了"), false);
  }
});

Deno.test("warm/hot debrief fallback keeps summary aligned with the invite window", () => {
  for (const temperatureScore of [70, 90]) {
    const card = buildFallbackDebriefCard({
      temperatureScore,
      turns: [
        { role: "user", text: "妳週末會去哪？" },
        { role: "ai", text: "可能會逛展" },
        { role: "user", text: "哪個展？" },
        { role: "ai", text: "還沒決定欸" },
      ],
    });
    assertEquals(card.summary.includes("持續投入"), true);
    assertEquals(card.summary.includes("問句比較密"), false);
    assertEquals(card.watchouts[0].includes("具體、低壓"), true);
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

Deno.test("applied-Hint debrief fallback anchors its next line to the latest safe topic", () => {
  const appliedHintTurns = [{
    turnIndex: 0,
    type: "steady" as const,
    originalHintText: "我也有點好奇",
    sentText: "我也有點好奇",
    exact: true,
  }];
  const cases = [
    { latest: "我最近都喝手沖咖啡", anchor: "咖啡" },
    { latest: "週末看了兩部電影", anchor: "電影" },
    { latest: "下個月想去日本旅行", anchor: "旅行" },
    { latest: "我換了新工作，超開心", anchor: "新工作" },
    { latest: "我剛看完一部工作題材電影，超好看", anchor: "電影" },
    { latest: "我在忙著準備演唱會，好期待", anchor: "音樂" },
    { latest: "最近休息時都在找新餐廳", anchor: "吃的" },
  ];
  const lines = cases.map(({ latest, anchor }) => {
    const card = buildFallbackDebriefCard({
      practiceMode: "beginner",
      appliedHintTurns,
      turns: [
        { role: "user", text: "我也有點好奇" },
        { role: "ai", text: latest },
      ],
    });
    assertEquals(card.suggestedLine.includes(anchor), true, card.suggestedLine);
    assertEquals(card.suggestedLine.includes("放鬆感"), false);
    assertEquals(card.suggestedLine.includes("真的累了"), false);
    return card.suggestedLine;
  });
  // The two movie phrasings intentionally share one topic-specific line; all
  // six semantic topics still need distinct, non-generic follow-ups.
  assertEquals(new Set(lines).size, 6);
});

Deno.test("applied-Hint topic fallback does not confuse photos or hard work with film or food", () => {
  const appliedHintTurns = [{
    turnIndex: 0,
    type: "steady" as const,
    originalHintText: "我也有點好奇",
    sentText: "我也有點好奇",
    exact: true,
  }];
  for (
    const { latest, forbidden } of [
      { latest: "我剛拍了很多照片", forbidden: "電影" },
      { latest: "最近工作真的很吃力", forbidden: "吃的" },
    ]
  ) {
    const card = buildFallbackDebriefCard({
      practiceMode: "beginner",
      appliedHintTurns,
      turns: [
        { role: "user", text: "我也有點好奇" },
        { role: "ai", text: latest },
      ],
    });
    assertEquals(card.suggestedLine.includes(forbidden), false, latest);
  }
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
