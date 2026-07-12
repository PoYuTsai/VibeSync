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

Deno.test("legacy list clamp filters empty/non-string entries before keeping two", () => {
  const c = parseDebriefCard(
    JSON.stringify({
      summary: "x",
      suggestedLine: "y",
      strengths: ["", 123, "a", "b"],
      watchouts: [null, "", "c", "d"],
      vibe: "中性",
    }),
  );
  assertEquals(c.strengths, ["a", "b"]);
  assertEquals(c.watchouts, ["c", "d"]);
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
  watchouts: ["下一步可以少一個賴床問句，多留一點自己的生活感。"],
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

const residenceTurns = [
  { role: "user" as const, text: "妳平常住哪裡？" },
  { role: "ai" as const, text: "我住台南，最常在中西區活動。" },
];

const groundedResidenceCard = {
  summary: "她說自己住台南、常在中西區活動，你有接住這兩個生活圈資訊。",
  strengths: ["你先問她住哪裡，讓她分享台南與中西區生活圈。"],
  watchouts: ["下一步可以問她在中西區最常做什麼，別只重複地名。"],
  suggestedLine: "原來妳常在中西區活動，休假最常去哪裡放空？",
  vibe: "中性",
  dateChance: "low",
  dateChanceReason: "她分享台南與中西區生活圈，但還沒提見面或時間。",
  nextInviteMove: "先問她在中西區最常去哪裡放空，等她回答再交換自己的生活圈。",
  hintAssessment: {
    verdict: "preserved",
    revisedEvidenceQuote: null,
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

Deno.test("generated Debrief rejects slot-filled canned next lines in Beginner and Game", () => {
  const turns = [
    { role: "user" as const, text: "還在賴床喔，那今天先慢慢開機。" },
    { role: "ai" as const, text: "哈哈有慢慢開機了" },
  ];
  for (
    const suggestedLine of [
      "哈哈我有接到，換我說一點，再聽妳的。",
      "慢慢開機這個點我接到了，換我分享一下。",
      "哈哈收到，我也有過，再聊聊妳的。",
      "慢慢開機我懂，我也是，妳呢？",
    ]
  ) {
    assertThrows(
      () =>
        parseDebriefCard(
          JSON.stringify({ ...generatedQualityCard, suggestedLine }),
          {
            requireCompleteCard: true,
            enforceGeneratedQuality: true,
            turns,
          },
        ),
      Error,
      "debrief_quality_invalid_suggested_line",
    );
  }

  assertThrows(
    () =>
      parseDebriefCard(
        JSON.stringify({
          ...generatedQualityCard,
          suggestedLine: "哈哈有慢慢開機，我今天靠咖啡把自己叫醒。",
          gameBreakdown: {
            phaseReached: "賴床話題仍在建立熟悉",
            missedVariable: "投入感",
            failureState: "話題還能再延伸",
            nextFirstLine: "哈哈收到，我也有過，再聊聊妳的。",
            inviteDirection: "先延續賴床話題，再看她是否多投入",
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
    "debrief_quality_invalid_next_first_line",
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

Deno.test("generated Beginner Debrief rejects partner facts rewritten into the pasteable line", () => {
  assertThrows(
    () =>
      parseDebriefCard(
        JSON.stringify({
          summary: "她提到台南生活圈，互動仍在交換資訊。",
          strengths: ["有接到她住台南這個具體資訊。"],
          watchouts: ["下一步別亂補不存在的共同生活圈。"],
          suggestedLine: "我也是台南人，妳最常去哪一區？",
          vibe: "中性",
          dateChance: "medium",
          dateChanceReason: "她分享台南生活圈，但還沒提見面或時間。",
          nextInviteMove: "先問她最常活動的台南區域。",
        }),
        {
          requireCompleteCard: true,
          enforceGeneratedQuality: true,
          turns: [{ role: "ai", text: "我住台南，最常在中西區活動。" }],
        },
      ),
    Error,
    "debrief_quality_invalid_unsupported_detail",
  );
});

Deno.test("generated Game Debrief rejects partner facts rewritten into nextFirstLine", () => {
  assertThrows(
    () =>
      parseDebriefCard(
        JSON.stringify({
          summary: "她提到台南生活圈，這輪仍在交換資訊。",
          strengths: ["你有接住她住台南的資訊，也保留追問生活圈的方向。"],
          watchouts: ["別把她的台南生活圈冒充成自己的。"],
          suggestedLine: "妳住台南喔，最常去哪一區？",
          vibe: "中性",
          dateChance: "medium",
          dateChanceReason: "她分享台南生活圈，但還沒提見面或時間。",
          nextInviteMove: "先延伸她常活動的台南區域。",
          gameBreakdown: {
            phaseReached: "台南生活資訊交換",
            missedVariable: "還沒有形成雙方投入",
            failureState: "共同生活圈證據不足",
            nextFirstLine: "我的生活圈也在台南，這也太巧。",
            inviteDirection: "先問她在台南常去哪裡",
          },
        }),
        {
          allowGameBreakdown: true,
          requireCompleteCard: true,
          enforceGeneratedQuality: true,
          turns: [{ role: "ai", text: "我住台南，最常在中西區活動。" }],
        },
      ),
    Error,
    "debrief_quality_invalid_unsupported_detail",
  );
});

Deno.test("generated Debrief permits partner callbacks, questions, and user-owned facts", () => {
  const card = parseDebriefCard(
    JSON.stringify({
      summary: "雙方都提到台南，這個共同點有逐字稿證據。",
      strengths: ["你有接住雙方都住台南，也保留追問生活圈的方向。"],
      watchouts: ["她住台南；下一步問她在中西區最常去哪裡。"],
      suggestedLine: "我也住台南，妳最常去哪一區？",
      vibe: "暖",
      dateChance: "medium",
      dateChanceReason: "雙方都明確提過台南。",
      nextInviteMove: "她住台南；下一步問她平常怎麼安排休息時間。",
    }),
    {
      requireCompleteCard: true,
      enforceGeneratedQuality: true,
      turns: [
        { role: "user", text: "我住台南，平常在東區活動。" },
        { role: "ai", text: "我也住台南，最常在中西區活動。" },
      ],
    },
  );
  assertEquals(card.suggestedLine.includes("我也住台南"), true);
});

Deno.test("preserved Debrief cannot indirectly blame an exact Hint in Beginner or Game fields", () => {
  const turns = [
    { role: "user" as const, text: "早安" },
    { role: "ai" as const, text: "我還在賴床，腦袋沒開機" },
    { role: "user" as const, text: appliedExactHint.sentText },
    { role: "ai" as const, text: "哈哈有慢慢開機了" },
  ];
  const gameBreakdown = {
    phaseReached: "賴床話題的熟悉建立",
    missedVariable: "還在賴床喔這句沒有給她好接的球",
    failureState: "照貼提示後停在禮貌收尾",
    nextFirstLine: "慢慢開機也行，我先分享我的起床儀式",
    inviteDirection: "先延續賴床話題，再看她是否多投入",
  };
  const cases: Array<{
    card: Record<string, unknown>;
    allowGameBreakdown?: boolean;
  }> = [
    {
      card: {
        ...generatedQualityCard,
        watchouts: [
          "只回『還在賴床喔，那今天先准妳慢慢開機』只是禮貌收尾，沒有給她好接的球。",
        ],
      },
    },
    {
      card: {
        ...generatedQualityCard,
        summary: "你有照提示做，但這句只是禮貌收尾，沒有給球。",
      },
    },
    {
      card: {
        ...generatedQualityCard,
        summary: "你有照提示做，但只停在禮貌收尾。",
      },
    },
    {
      card: {
        ...generatedQualityCard,
        strengths: ["你有照提示做，但這個回應只是禮貌收尾。"],
      },
    },
    {
      card: {
        ...generatedQualityCard,
        watchouts: ["照提示做後，球沒有丟回去，話題像句點。"],
      },
    },
    {
      card: {
        ...generatedQualityCard,
        dateChanceReason: "你的回覆太客套，沒留接點。",
      },
    },
    {
      card: {
        ...generatedQualityCard,
        watchouts: ["沒有把話題往前帶，也沒有留下回應空間。"],
      },
    },
    {
      card: {
        ...generatedQualityCard,
        watchouts: ["回覆收得太乾淨，沒留鉤子，互動斷在這裡。"],
      },
    },
    {
      card: {
        ...generatedQualityCard,
        watchouts: ["這樣回像把門關上，沒有延伸。"],
      },
    },
    {
      card: {
        ...generatedQualityCard,
        nextInviteMove: "剛才那句太客套，下一步要多給她一顆球。",
      },
    },
    {
      card: { ...generatedQualityCard, gameBreakdown },
      allowGameBreakdown: true,
    },
    {
      card: {
        ...generatedQualityCard,
        gameBreakdown: {
          ...gameBreakdown,
          phaseReached: "賴床這輪只停在禮貌收尾",
          missedVariable: "賴床話題的投入感",
          failureState: "賴床話題還能再延伸",
        },
      },
      allowGameBreakdown: true,
    },
  ];
  for (const testCase of cases) {
    assertThrows(
      () =>
        parseDebriefCard(JSON.stringify(testCase.card), {
          allowGameBreakdown: testCase.allowGameBreakdown,
          requireCompleteCard: true,
          enforceGeneratedQuality: true,
          turns,
          appliedHintTurns: [appliedExactHint],
        }),
      Error,
      "debrief_hint_assessment_revision_required",
    );
  }

  for (
    const summary of [
      "你有照提示做，但這句讓對話停住了。",
      "你有照提示做，但把話題聊死了。",
      "你有照提示做，但沒有讓對話延續。",
      "你有照提示做，但這句太乾。",
      "你有照提示做，但收尾感太重。",
      "你有照提示做，但對話沒有出口。",
      "你有照提示做，但沒有留下下一球。",
      "你有照提示做，但讓她很難接下去。",
      "你有照提示做，但她收到的這句太乾。",
      "你有照提示做，但她看到的回覆太客套。",
      "你有照提示做。這句像客服。",
      "你有照提示做，回覆太平淡。",
      "你有照提示做。這句很無聊。",
      "你有照提示做。回覆缺少生活感。",
      "你有照提示做。這句不夠有趣。",
      "你有照提示做，但對方看完覺得這句太客套。",
      "你有照提示做，但她看完只覺得很難繼續。",
      "你有照提示做，但她對你的回覆覺得太客套。",
      "你有照提示做，但對方看到你的回覆後覺得太客套。",
      "你有照提示做，但她覺得這句太客套。",
      "你有照提示做，但她認為回覆太平淡。",
      "你有照提示做，但對方感覺這個回答像客服。",
      "你有照提示做，但她說這句很無聊。",
      "她覺得這句太客套。",
      "她認為回覆太平淡。",
      "對方感覺這個回答像客服。",
      "她說這句很無聊。",
      "你有照提示做，唯獨這句少了鉤子。",
      "你有照提示做；這句容易冷場。",
      "你有照提示做；這句讓人接不下去。",
      "你有照提示做；這句缺乏溫度。",
      "你有照提示做；這句顯得敷衍。",
      "你有照提示做；回覆略嫌平庸。",
    ]
  ) {
    assertThrows(
      () =>
        parseDebriefCard(
          JSON.stringify({ ...generatedQualityCard, summary }),
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
  }

  assertThrows(
    () =>
      parseDebriefCard(
        JSON.stringify({
          ...generatedQualityCard,
          dateChanceReason: "這句讓她很難接下去。",
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
          gameBreakdown: {
            phaseReached: "賴床話題仍在建立熟悉",
            missedVariable: "賴床話題的投入感",
            failureState: "把賴床話題聊死",
            nextFirstLine: "慢慢開機也行，我先分享我的起床儀式",
            inviteDirection: "先延續賴床話題，再看她是否多投入",
          },
        }),
        {
          allowGameBreakdown: true,
          requireCompleteCard: true,
          enforceGeneratedQuality: true,
          turns,
          appliedHintTurns: [appliedExactHint],
        },
      ),
    Error,
    "debrief_hint_assessment_revision_required",
  );

  for (
    const failureState of [
      "賴床回覆像客服",
      "太平淡",
      "缺少生活感",
      "很無聊",
    ]
  ) {
    assertThrows(
      () =>
        parseDebriefCard(
          JSON.stringify({
            ...generatedQualityCard,
            gameBreakdown: {
              phaseReached: "賴床話題仍在建立熟悉",
              missedVariable: "賴床話題的投入感",
              failureState,
              nextFirstLine: "慢慢開機也行，我先分享我的起床儀式",
              inviteDirection: "先延續賴床話題，再看她是否多投入",
            },
          }),
          {
            allowGameBreakdown: true,
            requireCompleteCard: true,
            enforceGeneratedQuality: true,
            turns,
            appliedHintTurns: [appliedExactHint],
          },
        ),
      Error,
      "debrief_hint_assessment_revision_required",
    );
  }

  for (
    const failureState of [
      "賴床互動停在表面",
      "賴床互動沒有往深處走",
    ]
  ) {
    const objectiveOutcomeCard = parseDebriefCard(
      JSON.stringify({
        ...generatedQualityCard,
        gameBreakdown: {
          phaseReached: "賴床話題仍在建立熟悉",
          missedVariable: "賴床話題的投入感",
          failureState,
          nextFirstLine: "慢慢開機也行，我先分享我的起床儀式",
          inviteDirection: "先延續賴床話題，再看她是否多投入",
        },
      }),
      {
        allowGameBreakdown: true,
        requireCompleteCard: true,
        enforceGeneratedQuality: true,
        turns,
        appliedHintTurns: [appliedExactHint],
      },
    );
    assertEquals(
      objectiveOutcomeCard.gameBreakdown?.failureState,
      failureState,
    );
  }
});

Deno.test("preserved Debrief may critique her response or a clearly identified non-Hint user turn", () => {
  const baseTurns = [
    { role: "user" as const, text: "早安" },
    { role: "ai" as const, text: "我還在賴床，腦袋沒開機" },
    { role: "user" as const, text: appliedExactHint.sentText },
    { role: "ai" as const, text: "哈哈" },
  ];
  for (
    const watchout of [
      "提示本身沒問題；她這句只回哈哈，很難繼續。",
      "這句有接住她賴床；但她只禮貌收尾，沒給球。",
      "對方的回覆太客套，沒有留接點。",
      "提示本身沒問題；她後來的回覆太客套，沒有留接點。",
      "你的回覆有接住賴床，但她沒給球。",
      "她最後沒給球，下一步可以先等她多投入。",
      "她回得太客套，下一步先換一個好接的球。",
      "照提示做後，她只回哈哈，沒給球。",
      "你有照提示做，但她最後沒給球。",
      "你有照提示做，但這次她只回哈哈，沒給球。",
      "你有照提示做，但她看到你的回覆後只回哈哈。",
      "你有照提示做，但對方對你的回覆只回哈哈。",
      "照貼後，對方的回覆太客套。",
      "目前她只回哈哈，還沒多投入。",
      "這輪她只回哈哈，先觀察。",
      "從她只回哈哈來看，還要再觀察。",
      "回覆只有哈哈，先觀察她會不會多聊。",
      "這句不像禮貌收尾，還有留球。",
      "這句不只是禮貌收尾，還有留球。",
      "這句不只停在禮貌收尾，還往前推了一步。",
      "上一句沒給球，但這次有接住賴床。",
      "前一則沒給球，但這次有接住賴床。",
      "下一步你的回覆不要只問問題，補一點自己的生活感。",
    ]
  ) {
    let card;
    try {
      card = parseDebriefCard(
        JSON.stringify({ ...generatedQualityCard, watchouts: [watchout] }),
        {
          requireCompleteCard: true,
          turns: baseTurns,
          appliedHintTurns: [appliedExactHint],
        },
      );
    } catch (error) {
      throw new Error(`${watchout}: ${String(error)}`);
    }
    assertEquals(card.watchouts, [watchout]);
  }

  const laterUserText = "好啦我先睡";
  const laterTurnCard = parseDebriefCard(
    JSON.stringify({
      ...generatedQualityCard,
      watchouts: [
        `你後來只回「${laterUserText}」，話題像句點；這不是原本 Hint 的問題。`,
      ],
    }),
    {
      requireCompleteCard: true,
      turns: [
        ...baseTurns,
        { role: "user", text: laterUserText },
        { role: "ai", text: "好喔晚安" },
      ],
      appliedHintTurns: [appliedExactHint],
    },
  );
  assertEquals(laterTurnCard.watchouts[0].includes(laterUserText), true);

  assertThrows(
    () =>
      parseDebriefCard(
        JSON.stringify({
          ...generatedQualityCard,
          watchouts: [
            "你後來照貼提示只停在禮貌收尾，沒有給球。",
          ],
        }),
        {
          requireCompleteCard: true,
          turns: [
            ...baseTurns,
            { role: "user", text: laterUserText },
            { role: "ai", text: "好喔晚安" },
          ],
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
          watchouts: [
            "她只回哈哈，但你照提示那句太客套，沒有留接點。",
          ],
        }),
        {
          requireCompleteCard: true,
          turns: baseTurns,
          appliedHintTurns: [appliedExactHint],
        },
      ),
    Error,
    "debrief_hint_assessment_revision_required",
  );

  const partnerOutcomeCard = parseDebriefCard(
    JSON.stringify({
      ...generatedQualityCard,
      summary: "你有照提示做，但她這輪只回哈哈。",
      dateChanceReason: "聊天有舒適感，但邀約鋪墊不足。",
      gameBreakdown: {
        phaseReached: "賴床話題仍在建立熟悉",
        missedVariable: "賴床話題的投入感",
        failureState: "賴床話題沒有延伸",
        nextFirstLine: "慢慢開機也行，我先分享我的起床儀式",
        inviteDirection: "先延續賴床話題，再看她是否多投入",
      },
    }),
    {
      allowGameBreakdown: true,
      requireCompleteCard: true,
      turns: baseTurns,
      appliedHintTurns: [appliedExactHint],
    },
  );
  assertEquals(partnerOutcomeCard.summary.includes("她這輪只回哈哈"), true);

  for (
    const summary of [
      "你有照提示做，但目前還不適合約。",
      "你有照提示做，但還要再累積一輪。",
      "你有照提示做，但這輪先穩住。",
      "你有照提示做，但邀約窗口還沒開。",
      "你有照提示做，但下一步可以補一點自己的感受。",
    ]
  ) {
    const routeStateCard = parseDebriefCard(
      JSON.stringify({ ...generatedQualityCard, summary }),
      {
        requireCompleteCard: true,
        turns: baseTurns,
        appliedHintTurns: [appliedExactHint],
      },
    );
    assertEquals(routeStateCard.summary, summary);
  }

  const partnerReplyCard = parseDebriefCard(
    JSON.stringify({
      ...generatedQualityCard,
      summary: "你有照提示做，但她的回覆太客套。",
    }),
    {
      requireCompleteCard: true,
      turns: baseTurns,
      appliedHintTurns: [appliedExactHint],
    },
  );
  assertEquals(partnerReplyCard.summary.includes("她的回覆太客套"), true);

  for (
    const dateChanceReason of [
      "你的回覆讓互動自然。",
      "你的回覆有接住她，邀約窗口尚未出現。",
      "你的回覆沒有加壓，互動自然。",
      "你的回覆不會太急，互動自然。",
      "這句沒有太用力，互動自然。",
      "這句不突兀，互動有承接。",
      "這句不會太單薄，互動自然。",
      "這句沒有缺少生活感，互動自然。",
      "這句不是不夠具體，互動自然。",
    ]
  ) {
    const dateCard = parseDebriefCard(
      JSON.stringify({ ...generatedQualityCard, dateChanceReason }),
      {
        requireCompleteCard: true,
        turns: baseTurns,
        appliedHintTurns: [appliedExactHint],
      },
    );
    assertEquals(dateCard.dateChanceReason, dateChanceReason);
  }

  for (
    const nextInviteMove of [
      "延續賴床梗，等她再投入一輪。",
      "沿著賴床梗多聊一輪。",
      "窗口還沒開，繼續累積投入。",
      "繼續聊賴床梗，等她投入再約。",
      "維持現在節奏，再聊一輪賴床。",
      "把賴床梗拉長一輪，再看窗口。",
      "多聊一輪賴床話題，再看她投入。",
      "保留賴床梗，等她多回一點。",
      "賴床梗再玩一輪，之後看窗口。",
    ]
  ) {
    const nextMoveCard = parseDebriefCard(
      JSON.stringify({ ...generatedQualityCard, nextInviteMove }),
      {
        requireCompleteCard: true,
        turns: baseTurns,
        appliedHintTurns: [appliedExactHint],
      },
    );
    assertEquals(nextMoveCard.nextInviteMove, nextInviteMove);
  }
});

Deno.test("generated Debrief rejects overlong fields instead of slicing visible half sentences", () => {
  const turns = [
    { role: "user" as const, text: "早安" },
    { role: "ai" as const, text: "我還在賴床，腦袋沒開機" },
  ];
  const proseCases = [
    ["summary", "賴床".repeat(61)],
    ["suggestedLine", "賴床".repeat(61)],
    ["dateChanceReason", "賴床".repeat(61)],
    ["nextInviteMove", "賴床".repeat(61)],
  ] as const;
  for (const [field, value] of proseCases) {
    assertThrows(
      () =>
        parseDebriefCard(
          JSON.stringify({ ...generatedQualityCard, [field]: value }),
          {
            requireCompleteCard: true,
            enforceGeneratedQuality: true,
            turns,
          },
        ),
      Error,
      "debrief_quality_invalid_overlong",
    );
  }

  const overlongWatchout = "賴床".repeat(51);
  for (const field of ["strengths", "watchouts"] as const) {
    assertThrows(
      () =>
        parseDebriefCard(
          JSON.stringify({
            ...generatedQualityCard,
            [field]: [overlongWatchout],
          }),
          {
            requireCompleteCard: true,
            enforceGeneratedQuality: true,
            turns,
          },
        ),
      Error,
      "debrief_quality_invalid_overlong",
    );
  }

  const legacyWatchout =
    "下一步延續賴床話題時，多放一點自己的生活畫面，再問她今天怎麼慢慢開機，讓她比較好接下一球。";
  const legacy = parseDebriefCard(
    JSON.stringify({
      ...generatedQualityCard,
      watchouts: [legacyWatchout],
    }),
  );
  assertEquals(legacy.watchouts[0].length, 40);

  const completeGenerated = parseDebriefCard(
    JSON.stringify({
      ...generatedQualityCard,
      watchouts: [legacyWatchout],
    }),
    {
      requireCompleteCard: true,
      enforceGeneratedQuality: true,
      turns,
    },
  );
  assertEquals(completeGenerated.watchouts[0], legacyWatchout);
});

Deno.test("generated Game Debrief rejects an overlong breakdown field before clamping", () => {
  const baseBreakdown = {
    phaseReached: "賴床互動仍在建立熟悉",
    missedVariable: "賴床話題還缺投入感",
    failureState: "賴床只停在表面問答",
    nextFirstLine: "賴床冠軍醒了嗎？我剛找到一間咖啡店。",
    inviteDirection: "先延續賴床梗，再看她是否願意投入。",
  };
  for (
    const field of [
      "phaseReached",
      "missedVariable",
      "failureState",
      "nextFirstLine",
      "inviteDirection",
    ] as const
  ) {
    const overlong = "賴床".repeat(71);
    assertThrows(
      () =>
        parseDebriefCard(
          JSON.stringify({
            ...generatedQualityCard,
            gameBreakdown: { ...baseBreakdown, [field]: overlong },
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
      "debrief_quality_invalid_overlong",
    );
  }
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
          suggestedLine: "我今天下班想整理書櫃，週末妳都怎麼放空？",
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
            nextFirstLine: "我最近在學做陶器，妳有碰過嗎？",
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
    "debrief_quality_invalid_field_not_grounded",
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

Deno.test("generated Debrief rejects generic Beginner and Game field roles", () => {
  const turns = [
    { role: "user" as const, text: "早安，妳平常住哪裡？" },
    { role: "ai" as const, text: "我住台南，最常在中西區活動。" },
  ];
  assertThrows(
    () =>
      parseDebriefCard(
        JSON.stringify({
          summary: "整體互動自然，但還能更有生活感。",
          strengths: ["語氣自然，聊天不會太用力。"],
          watchouts: ["可以增加一點投入感。"],
          suggestedLine: "妳住台南喔，最常去哪一區？",
          vibe: "中性",
          dateChance: "medium",
          dateChanceReason: "目前聊天舒服，但還需要更多互動。",
          nextInviteMove: "先累積熟悉感，再找自然窗口。",
        }),
        {
          requireCompleteCard: true,
          enforceGeneratedQuality: true,
          turns,
        },
      ),
    Error,
    "debrief_quality_invalid_summary_role",
  );

  assertThrows(
    () =>
      parseDebriefCard(
        JSON.stringify({
          ...groundedResidenceCard,
          gameBreakdown: {
            phaseReached: "台南話題進行到互動階段",
            missedVariable: "台南這題還沒推動投入感",
            failureState: "台南話題目前有點卡住",
            nextFirstLine: "妳說台南，最常去哪一區？",
            inviteDirection: "先聊台南，再找自然窗口",
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
    "debrief_quality_invalid_game_failure_role",
  );
});

Deno.test("generated Debrief rejects grounded but generic text in every analytical role", () => {
  const cases = [
    {
      card: {
        ...groundedResidenceCard,
        summary: "她說住台南，這個話題有接到。",
      },
      error: "debrief_quality_invalid_summary_substance",
    },
    {
      card: { ...groundedResidenceCard, strengths: ["回覆有接到她住台南。"] },
      error: "debrief_quality_invalid_strength_substance",
    },
    {
      card: { ...groundedResidenceCard, watchouts: ["下一步可以再問台南。"] },
      error: "debrief_quality_invalid_watchout_substance",
    },
    {
      card: {
        ...groundedResidenceCard,
        suggestedLine: "台南聽起來很有生活感。",
      },
      error: "debrief_quality_invalid_suggested_line",
    },
    {
      card: {
        ...groundedResidenceCard,
        dateChanceReason: "她願意說自己住台南。",
      },
      error: "debrief_quality_invalid_date_reason_substance",
    },
    {
      card: { ...groundedResidenceCard, nextInviteMove: "接著聊她住台南。" },
      error: "debrief_quality_invalid_next_move_substance",
    },
  ];
  for (const testCase of cases) {
    assertThrows(
      () =>
        parseDebriefCard(JSON.stringify(testCase.card), {
          requireCompleteCard: true,
          enforceGeneratedQuality: true,
          turns: residenceTurns,
        }),
      Error,
      testCase.error,
    );
  }
});

Deno.test("generated Debrief cannot launder residence grounding into a partner invitation", () => {
  assertThrows(
    () =>
      parseDebriefCard(
        JSON.stringify({
          ...groundedResidenceCard,
          summary: "她說住台南，也主動提了見面邀約。",
          watchouts: ["下一步可以確認台南邀約時間。"],
          suggestedLine: "台南邀約聽起來不錯，妳想約哪天？",
          vibe: "暖",
          dateChance: "high",
          dateChanceReason: "她主動說想在台南見面。",
          nextInviteMove: "接住她的台南邀約，問哪天。",
        }),
        {
          requireCompleteCard: true,
          enforceGeneratedQuality: true,
          turns: residenceTurns,
        },
      ),
    Error,
    "debrief_quality_invalid_partner_initiative",
  );

  const invitationTurns = [
    { role: "user" as const, text: "妳平常住哪裡？" },
    {
      role: "ai" as const,
      text: "我住台南，週六有空，要不要一起喝咖啡？",
    },
  ];
  const supported = parseDebriefCard(
    JSON.stringify({
      summary: "她說住台南，也主動提了週六一起喝咖啡的邀約。",
      strengths: ["你有接住她週六喝咖啡的邀請，沒有急著加碼。"],
      watchouts: ["下一步先確認她週六想約哪個時段，別替她決定地點。"],
      suggestedLine: "週六咖啡可以，妳偏下午還是晚上？",
      vibe: "暖",
      dateChance: "high",
      dateChanceReason: "她主動提出週六一起喝咖啡，已經有明確時間窗口。",
      nextInviteMove: "先問她週六偏下午還是晚上，再一起確認咖啡地點。",
      hintAssessment: {
        verdict: "preserved",
        revisedEvidenceQuote: null,
      },
    }),
    {
      requireCompleteCard: true,
      enforceGeneratedQuality: true,
      turns: invitationTurns,
    },
  );
  assertEquals(supported.dateChance, "high");
});

Deno.test("generated Debrief fact-checks every analytical field without rejecting partner-owned callbacks", () => {
  const turns = [{ role: "ai" as const, text: "我住台南，最常在中西區活動。" }];
  const base = {
    summary: "她說自己住台南、常在中西區活動，你有接住這兩個生活圈資訊。",
    strengths: ["你先問她住哪裡，讓她分享台南與中西區生活圈。"],
    watchouts: ["她住台南；下一步別假設共同生活圈。"],
    suggestedLine: "妳住台南喔，最常去哪一區？",
    vibe: "中性",
    dateChance: "medium",
    dateChanceReason: "她分享台南與中西區，但還沒提見面或時間。",
    nextInviteMove: "她住台南；下一步問她平常怎麼安排休息時間。",
  };

  const supported = parseDebriefCard(JSON.stringify(base), {
    requireCompleteCard: true,
    enforceGeneratedQuality: true,
    turns,
  });
  assertEquals(supported.summary.includes("住台南"), true);

  for (
    const card of [
      {
        ...base,
        summary: "她說自己住高雄、常在中西區活動，你有接住這兩個生活圈資訊。",
      },
      {
        ...base,
        strengths: ["你把她住高雄當成已知資訊，讓生活圈分析偏離逐字稿。"],
      },
      { ...base, watchouts: ["她住高雄；下一步別假設共同生活圈。"] },
      {
        ...base,
        dateChanceReason: "她住高雄，但還沒提見面或時間。",
      },
      {
        ...base,
        nextInviteMove: "她住高雄；下一步問她平常怎麼安排休息時間。",
      },
    ]
  ) {
    assertThrows(
      () =>
        parseDebriefCard(JSON.stringify(card), {
          requireCompleteCard: true,
          enforceGeneratedQuality: true,
          turns,
        }),
      Error,
      "debrief_quality_invalid_unsupported_detail",
    );
  }
});

Deno.test("preserved build Hint blocks third-person invite coaching but revised evidence may upgrade", () => {
  const baseTurns = [
    { role: "user" as const, text: "早安" },
    { role: "ai" as const, text: "我還在賴床，腦袋沒開機" },
    { role: "user" as const, text: appliedExactHint.sentText },
  ];
  for (
    const nextInviteMove of [
      "現在可以約她去吃東西。",
      "下一步就約她喝咖啡。",
      "可以問她哪天有空。",
      "可以把賴床話題收成一個見面邀約。",
      "接下來可以去喝咖啡。",
    ]
  ) {
    assertThrows(
      () =>
        parseDebriefCard(
          JSON.stringify({ ...generatedQualityCard, nextInviteMove }),
          {
            requireCompleteCard: true,
            enforceGeneratedQuality: true,
            turns: baseTurns,
            appliedHintTurns: [appliedExactHint],
          },
        ),
      Error,
      "debrief_hint_assessment_revision_required",
    );
  }

  const revisedTurns = [
    ...baseTurns,
    { role: "ai" as const, text: "我週六下午有空，可以喝咖啡。" },
  ];
  const revised = parseDebriefCard(
    JSON.stringify({
      ...generatedQualityCard,
      summary: "你有照提示做；她後來說『我週六下午有空』。",
      dateChanceReason: "她主動說『我週六下午有空』，窗口已出現。",
      nextInviteMove: "她說『我週六下午有空』；下一步可以約她喝咖啡。",
      hintAssessment: {
        verdict: "revised",
        revisedEvidenceQuote: "我週六下午有空",
      },
    }),
    {
      requireCompleteCard: true,
      enforceGeneratedQuality: true,
      turns: revisedTurns,
      appliedHintTurns: [appliedExactHint],
    },
  );
  assertEquals(revised.nextInviteMove.includes("約她喝咖啡"), true);
});

Deno.test("preserved Hint route reads suggested lines, natural direct advice, and negated plans", () => {
  const buildTurns = [
    { role: "user" as const, text: "早安" },
    { role: "ai" as const, text: "我還在賴床，腦袋沒開機" },
    { role: "user" as const, text: appliedExactHint.sentText },
  ];
  for (
    const nextInviteMove of [
      "建議約她見面，沿用賴床這個梗。",
      "不妨約她喝咖啡，再回呼賴床這個梗。",
    ]
  ) {
    assertThrows(
      () =>
        parseDebriefCard(
          JSON.stringify({ ...generatedQualityCard, nextInviteMove }),
          {
            requireCompleteCard: true,
            enforceGeneratedQuality: true,
            turns: buildTurns,
            appliedHintTurns: [appliedExactHint],
          },
        ),
      Error,
      "debrief_hint_assessment_revision_required",
    );
  }

  const negatedMove = "下一步可以先不要問她哪天有空，先延續賴床這個梗。";
  const negated = parseDebriefCard(
    JSON.stringify({
      ...generatedQualityCard,
      nextInviteMove: negatedMove,
    }),
    {
      requireCompleteCard: true,
      enforceGeneratedQuality: true,
      turns: buildTurns,
      appliedHintTurns: [appliedExactHint],
    },
  );
  assertEquals(negated.nextInviteMove, negatedMove);

  const directHint = {
    ...appliedExactHint,
    originalHintText: "賴床醒了，週六一起喝杯咖啡吧？",
    sentText: "賴床醒了，週六一起喝杯咖啡吧？",
    hintRequestId: "hint-quality-direct",
    decision: {
      phase: "邀約窗口已開",
      targetVariable: "見面行動",
      move: "direct_invite",
      inviteRoute: "direct",
      rationale: "她已經給出週六窗口，直接收成低壓咖啡邀約。",
    },
  };
  const directTurns = [
    { role: "user" as const, text: "早安" },
    { role: "ai" as const, text: "我還在賴床，腦袋沒開機" },
    { role: "user" as const, text: directHint.sentText },
  ];
  assertThrows(
    () =>
      parseDebriefCard(
        JSON.stringify({
          ...generatedQualityCard,
          summary: "你有照提示送出週六咖啡邀約，但拆解又把邀約撤回。",
          suggestedLine: "賴床先不約妳，繼續聊妳怎麼開機。",
          nextInviteMove: "週六咖啡邀約已送出，先等她回覆。",
        }),
        {
          requireCompleteCard: true,
          enforceGeneratedQuality: true,
          turns: directTurns,
          appliedHintTurns: [directHint],
        },
      ),
    Error,
    "debrief_hint_assessment_revision_required",
  );
});

Deno.test("preserved Hint accepts natural forward coaching openers", () => {
  const turns = [
    { role: "user" as const, text: "早安" },
    { role: "ai" as const, text: "我還在賴床，腦袋沒開機" },
    { role: "user" as const, text: appliedExactHint.sentText },
  ];
  for (
    const watchout of [
      "可以多放一點自己的賴床口味。",
      "建議補一個自己的賴床習慣。",
      "不妨沿著賴床梗多分享一句。",
    ]
  ) {
    const card = parseDebriefCard(
      JSON.stringify({ ...generatedQualityCard, watchouts: [watchout] }),
      {
        requireCompleteCard: true,
        enforceGeneratedQuality: true,
        turns,
        appliedHintTurns: [appliedExactHint],
      },
    );
    assertEquals(card.watchouts[0], watchout);
  }

  const naturalWindowState = parseDebriefCard(
    JSON.stringify({
      ...generatedQualityCard,
      dateChanceReason: "賴床有來回，但邀約窗口還沒開。",
    }),
    {
      requireCompleteCard: true,
      enforceGeneratedQuality: true,
      turns,
      appliedHintTurns: [appliedExactHint],
    },
  );
  assertEquals(
    naturalWindowState.dateChanceReason.includes("窗口還沒開"),
    true,
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
