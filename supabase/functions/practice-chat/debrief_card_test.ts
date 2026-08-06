// 教練拆解卡解析測試。
// 跑法：deno test supabase/functions/practice-chat/debrief_card_test.ts

import {
  assert,
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  DEBRIEF_TOOL_SCHEMA,
  DEBRIEF_TOOL_SCHEMA_GAME,
  debriefToolSchemaFor,
  parseDebriefCard,
  repairFlattenedGameBreakdown,
  salvageDebriefCandidate,
} from "./debrief_card.ts";

const valid = JSON.stringify({
  summary: "整體有來有往，後段她有點冷掉",
  strengths: ["開場自然不油", "有接住她的話題"],
  watchouts: ["問句太密像查戶口", "可以多分享自己"],
  suggestedLine: "那家店我也想去，週末有空一起？",
  vibe: "中性",
});

/**
 * 守門嚴重度分級（2026-08-06）後的測試座架：偏好門不再 throw、改回報
 * finding；用這個 helper 同時拿卡與 finding 碼來斷言。
 */
function parseWithFindings(
  raw: string,
  opts: Omit<
    NonNullable<Parameters<typeof parseDebriefCard>[1]>,
    "onQualityFinding"
  > = {},
): { card: ReturnType<typeof parseDebriefCard>; findings: string[] } {
  const findings: string[] = [];
  const card = parseDebriefCard(raw, {
    ...opts,
    onQualityFinding: (code) => findings.push(code),
  });
  return { card, findings };
}

/** fact ledger 等門的碼帶診斷後綴（code:claimKind:…），用前綴比對。 */
function hasFinding(findings: string[], code: string): boolean {
  return findings.some((f) => f === code || f.startsWith(`${code}:`));
}

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

Deno.test("slot-filled 空話貼句在 Beginner 和 Game ＝ finding", () => {
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
    const { findings } = parseWithFindings(
      JSON.stringify({ ...generatedQualityCard, suggestedLine }),
      {
        requireCompleteCard: true,
        enforceGeneratedQuality: true,
        turns,
      },
    );
    assert(
      findings.includes("debrief_quality_invalid_suggested_line"),
      suggestedLine,
    );
  }

  const { findings } = parseWithFindings(
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
  );
  assert(findings.includes("debrief_quality_invalid_next_first_line"));
});

Deno.test("generated Debrief must acknowledge an exact Hint and must not repeat it", () => {
  const turns = [
    { role: "user" as const, text: "早安" },
    { role: "ai" as const, text: "我還在賴床，腦袋沒開機" },
    { role: "user" as const, text: appliedExactHint.sentText },
  ];
  const accountability = parseWithFindings(
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
  );
  assert(
    accountability.findings.includes(
      "debrief_quality_invalid_hint_accountability",
    ),
  );
  const repeated = parseWithFindings(
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
  );
  assert(
    repeated.findings.includes("debrief_quality_invalid_repeated_hint"),
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

Deno.test("generated Debrief accepts concrete round-level summaries without generic role drift", () => {
  const card = parseDebriefCard(
    JSON.stringify({
      ...groundedResidenceCard,
      summary: "這輪接住台南生活圈，也讓她補出中西區活動。",
    }),
    {
      requireCompleteCard: true,
      enforceGeneratedQuality: true,
      turns: residenceTurns,
    },
  );

  assertEquals(
    card.summary,
    "這輪接住台南生活圈，也讓她補出中西區活動。",
  );
});

Deno.test("generated Debrief permits a negated warning about missing shop location", () => {
  const turns = [
    {
      role: "user" as const,
      text: "剛看到妳喜歡咖啡，我今天路過一家聞起來超香的店。",
    },
    { role: "ai" as const, text: "哦？在哪啊，我最近也在物色新店。" },
  ];
  const safeCard = {
    summary: "你用咖啡店開場，她有接話並追問店的位置。",
    strengths: ["你有用咖啡店開場，也帶出路過聞到很香的具體畫面。"],
    watchouts: ["她問店在哪，你應該先說不記得，不要亂補附近。"],
    suggestedLine: "我真的沒記住在哪；妳最近物色新店都看哪一區？",
    vibe: "暖",
    dateChance: "low",
    dateChanceReason: "她說最近也在物色新店，但還沒有主動談時間或見面。",
    nextInviteMove: "下一步先回她沒記住位置，再延伸她最近物色新店的話題。",
  };
  const parseOptions = {
    requireCompleteCard: true,
    enforceGeneratedQuality: true,
    turns,
  };
  const card = parseDebriefCard(
    JSON.stringify(safeCard),
    parseOptions,
  );

  assertEquals(card.watchouts, [
    "她問店在哪，你應該先說不記得，不要亂補附近。",
  ]);
  const fabricated = parseWithFindings(
    JSON.stringify({
      ...safeCard,
      suggestedLine: "在哪啊，就是公司旁邊那間啦。",
    }),
    parseOptions,
  );
  assert(
    hasFinding(
      fabricated.findings,
      "debrief_quality_invalid_unsupported_detail",
    ),
  );
});

Deno.test("Beginner 把她的事實冒充成自己的貼句＝finding", () => {
  const { findings } = parseWithFindings(
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
  );
  assert(hasFinding(findings, "debrief_quality_invalid_unsupported_detail"));
});

Deno.test("Game 把她的事實冒充成自己的 nextFirstLine＝finding", () => {
  const { findings } = parseWithFindings(
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
  );
  assert(hasFinding(findings, "debrief_quality_invalid_unsupported_detail"));
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

Deno.test("貼句欄詞面 grounding 降為 finding（兩個可貼欄各自記碼）", () => {
  const turns = [
    { role: "user" as const, text: "早安" },
    { role: "ai" as const, text: "我還在賴床，腦袋沒開機" },
  ];
  const suggested = parseWithFindings(
    JSON.stringify({
      ...generatedQualityCard,
      suggestedLine: "我今天下班想整理書櫃，週末妳都怎麼放空？",
    }),
    {
      requireCompleteCard: true,
      enforceGeneratedQuality: true,
      turns,
    },
  );
  assert(
    hasFinding(
      suggested.findings,
      "debrief_quality_invalid_suggested_line_not_grounded",
    ),
  );
  const game = parseWithFindings(
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
  );
  assert(
    hasFinding(
      game.findings,
      "debrief_quality_invalid_game_breakdown_not_grounded",
    ),
  );
});

Deno.test("Game Debrief analytical breakdown fields are meta-commentary and skip word-surface grounding", () => {
  // 2026-07-23 判定表：分析欄位（後設評語）詞面 n-gram 接地 20/20 全誤殺，
  // 已拍板移除；捏造防線由 fact ledger 與罐頭/術語 gate 負責。
  // 可貼的 nextFirstLine 仍須接地（見上一個測試）。
  const card = parseDebriefCard(
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
  );
  assertEquals(card.gameBreakdown?.phaseReached, "開場到測試");
});
Deno.test("generic 欄位角色（Beginner 與 Game）＝finding", () => {
  const turns = [
    { role: "user" as const, text: "早安，妳平常住哪裡？" },
    { role: "ai" as const, text: "我住台南，最常在中西區活動。" },
  ];
  const beginner = parseWithFindings(
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
  );
  assert(
    hasFinding(beginner.findings, "debrief_quality_invalid_summary_role"),
  );

  const game = parseWithFindings(
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
  );
  assert(
    hasFinding(game.findings, "debrief_quality_invalid_game_failure_role"),
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
    const { findings } = parseWithFindings(JSON.stringify(testCase.card), {
      requireCompleteCard: true,
      enforceGeneratedQuality: true,
      turns: residenceTurns,
    });
    assert(hasFinding(findings, testCase.error), testCase.error);
  }
});

Deno.test("捏造對方主動邀約＝偏好門：記 finding、卡照端出", () => {
  const { card, findings } = parseWithFindings(
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
  );
  assertEquals(card.dateChance, "high");
  assert(findings.includes("debrief_quality_invalid_partner_initiative"));

  const invitationTurns = [
    { role: "user" as const, text: "妳平常住哪裡？" },
    {
      role: "ai" as const,
      text: "我住台南，週六有空，要不要一起喝咖啡？",
    },
  ];
  // 有真實邀約證據＋模型照舊填了已棄用的 hintAssessment：欄位被忽略、零 finding。
  const supported = parseWithFindings(
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
  assertEquals(supported.card.dateChance, "high");
  assert(
    !supported.findings.includes("debrief_quality_invalid_partner_initiative"),
  );
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
    const { findings } = parseWithFindings(JSON.stringify(card), {
      requireCompleteCard: true,
      enforceGeneratedQuality: true,
      turns,
    });
    assert(
      hasFinding(findings, "debrief_quality_invalid_unsupported_detail"),
    );
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

Deno.test("generated Debrief normalizes every visible field to Taiwan Traditional Chinese", () => {
  const c = parseDebriefCard(
    JSON.stringify({
      summary: "她很积极，也愿意回应细节。",
      strengths: ["你愿意尝试，也注意细节。"],
      watchouts: ["建议别急着推进。"],
      suggestedLine: "这个建议我愿意试试看。",
      vibe: "暖",
      dateChance: "medium",
      dateChanceReason: "她积极回应，但细节仍少。",
      nextInviteMove: "愿意时再问她一次再推进。",
      gameBreakdown: {
        phaseReached: "已到尝试推进的阶段",
        missedVariable: "细节还不够",
        failureState: "建议太空泛",
        nextFirstLine: "我愿意听你的建议",
        inviteDirection: "先问她意愿再推进",
      },
    }),
    {
      allowGameBreakdown: true,
      requireCompleteCard: true,
      enforceGeneratedQuality: true,
    },
  );

  assertEquals(c.summary, "她很積極，也願意回應細節。");
  assertEquals(c.strengths, ["你願意嘗試，也注意細節。"]);
  assertEquals(c.watchouts, ["建議別急著推進。"]);
  assertEquals(c.suggestedLine, "這個建議我願意試試看。");
  assertEquals(c.dateChanceReason, "她積極回應，但細節仍少。");
  assertEquals(c.nextInviteMove, "願意時再問她一次再推進。");
  assertEquals(c.gameBreakdown, {
    phaseReached: "已到嘗試推進的階段",
    missedVariable: "細節還不夠",
    failureState: "建議太空泛",
    nextFirstLine: "我願意聽你的建議",
    inviteDirection: "先問她意願再推進",
  });
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

// eval 第 6 輪根因：Sonnet 偶發把 tool_use 巢狀物件寫成 tool-call 的
// `<parameter name="X">` 拍平語法——gameBreakdown 變成字串、其餘四欄逸出頂層。
// repair 只救序列化形態，內容 gate 全不變。fixture 取自
// tools/practice_single_shot_eval/results/2026-07-23T02-43-11-260Z.json shot 68。
Deno.test("Game debrief repairs flattened tool-call gameBreakdown string", () => {
  const c = parseDebriefCard(
    JSON.stringify({
      summary: "連續資訊型提問像查戶口，她已明講不舒服",
      strengths: ["被提醒後立刻道歉，沒有硬凹或反駁"],
      watchouts: ["連問下班活動、健身房、籍貫家庭，像做問卷不是聊天"],
      suggestedLine: "健身房挑連鎖的方便啦，妳算自律的吧？",
      vibe: "冷",
      dateChance: "low",
      dateChanceReason: "她直接說像查戶口，明顯是防備狀態",
      nextInviteMove: "先自我揭露，累積幾輪自在感後再談見面",
      gameBreakdown:
        '\n<parameter name="phaseReached">還在互相認識的資訊交換階段',
      missedVariable: "沒有給出自己的內容或感受，只是一直丟問題",
      failureState: "問答變成單向盤問，她說『像做戶口調查』",
      nextFirstLine: "健身房挑連鎖的方便啦，妳算自律的吧？",
      inviteDirection: "先修聊天方式：多分享自己、少問資訊題",
    }),
    { allowGameBreakdown: true },
  );

  assertEquals(c.gameBreakdown, {
    phaseReached: "還在互相認識的資訊交換階段",
    missedVariable: "沒有給出自己的內容或感受，只是一直丟問題",
    failureState: "問答變成單向盤問，她說『像做戶口調查』",
    nextFirstLine: "健身房挑連鎖的方便啦，妳算自律的吧？",
    inviteDirection: "先修聊天方式：多分享自己、少問資訊題",
  });
});

Deno.test("repairFlattenedGameBreakdown reparents multi-segment string and strips escaped top-level keys", () => {
  const p: Record<string, unknown> = {
    summary: "solid",
    gameBreakdown:
      '\n<parameter name="phaseReached">還在認識</parameter>\n<parameter name="missedVariable">沒分享自己</parameter>',
    failureState: "單向盤問",
    nextFirstLine: "先丟一個自己的故事",
    inviteDirection: "暫不邀約",
  };
  repairFlattenedGameBreakdown(p);
  assertEquals(p.gameBreakdown, {
    phaseReached: "還在認識",
    missedVariable: "沒分享自己",
    failureState: "單向盤問",
    nextFirstLine: "先丟一個自己的故事",
    inviteDirection: "暫不邀約",
  });
  // 逸出頂層的欄位搬回巢狀後必須移除，不得殘留多餘 key。
  assertEquals("failureState" in p, false);
  assertEquals("nextFirstLine" in p, false);
  assertEquals("inviteDirection" in p, false);
  assertEquals(p.summary, "solid");
});

Deno.test("flattened gameBreakdown still rejects when fields remain missing after repair", () => {
  // 頂層只有三欄、字串只含 phaseReached → 抽完仍缺 inviteDirection，
  // 照舊 missing_fields，絕不填罐頭預設值。
  assertThrows(
    () =>
      parseDebriefCard(
        JSON.stringify({
          summary: "solid",
          suggestedLine: "next line",
          gameBreakdown: '\n<parameter name="phaseReached">還在認識',
          missedVariable: "沒分享自己",
          failureState: "單向盤問",
          nextFirstLine: "先丟一個自己的故事",
        }),
        { allowGameBreakdown: true },
      ),
    Error,
    "debrief_game_breakdown_missing_fields",
  );
});

Deno.test('string gameBreakdown without <parameter prefix (e.g. "null") is not repaired', () => {
  for (const gameBreakdown of ["null", "not an object"]) {
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

Deno.test("parseDebriefCard 每個可見欄位拒絕「投入度 X/100」分數形、放行裸詞投入度", () => {
  // 9fd3b8a5 去列字後隱藏層標頭＝「投入度 X/100」，模型照抄即洩內部分數。
  // 裸詞「投入度」是分析欄合法後設評語詞，只攔帶分數形的窄型態。
  for (const field of DEBRIEF_VISIBLE_FIELDS) {
    assertThrows(
      () =>
        parseDebriefCard(
          debriefJsonWithVisibleField(field, "她的投入度 72/100，繼續保持"),
          { allowGameBreakdown: true },
        ),
      Error,
      undefined,
      `field=${field} should reject score-shape leak`,
    );
  }
  const okCard = parseDebriefCard(
    debriefJsonWithVisibleField("summary", "整場投入度不高，可以多丟開放問題"),
    { allowGameBreakdown: true },
  );
  assertEquals(okCard.summary, "整場投入度不高，可以多丟開放問題");
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

Deno.test("DEBRIEF_TOOL_SCHEMA matches the parser contract (schema wide, parser strict)", () => {
  const schema = DEBRIEF_TOOL_SCHEMA as {
    type: string;
    properties: Record<string, Record<string, unknown>>;
    required: string[];
    additionalProperties: boolean;
  };
  assertEquals(schema.type, "object");
  assertEquals([...schema.required].sort(), [
    "dateChance",
    "dateChanceReason",
    "nextInviteMove",
    "strengths",
    "suggestedLine",
    "summary",
    "vibe",
    "watchouts",
  ]);
  assertEquals(schema.additionalProperties, false);
  // Game breakdown 與 hidden hintAssessment 是選填：schema 用選填欄位涵蓋，
  // 不做兩套 schema；缺欄與否由 parser（allowGameBreakdown／assertHintAssessment）硬 gate。
  assertEquals("gameBreakdown" in schema.properties, true);
  assertEquals(schema.required.includes("gameBreakdown"), false);
  assertEquals("hintAssessment" in schema.properties, true);
  assertEquals(schema.required.includes("hintAssessment"), false);
  const breakdown = schema.properties.gameBreakdown as {
    required: string[];
  };
  assertEquals([...breakdown.required].sort(), [
    "failureState",
    "inviteDirection",
    "missedVariable",
    "nextFirstLine",
    "phaseReached",
  ]);

  // 一張過 parser 完整契約的合法卡，必須同時滿足 schema 必填鍵。
  const legal = {
    summary: "你說今天忙到剛下班，她接著分享只想散步放空。",
    strengths: ["你先分享自己剛下班的狀態，讓對話有具體情境。"],
    watchouts: ["下一步要接住她想散步放空，不要只停在自己的忙碌。"],
    suggestedLine: "下班後散步很療癒，妳最常走哪一段？",
    vibe: "中性",
    dateChance: "medium",
    dateChanceReason: "她回覆自己剛下班想散步放空，但還沒提時間或見面。",
    nextInviteMove: "先問她最常去哪裡散步，等她多分享再看邀約窗口。",
  };
  const card = parseDebriefCard(JSON.stringify(legal), {
    requireCompleteCard: true,
    enforceGeneratedQuality: true,
    turns: [
      { role: "user", text: "今天忙到剛下班" },
      { role: "ai", text: "我也剛下班，只想散步放空" },
    ],
  });
  assertEquals(card.dateChance, "medium");
  for (const key of schema.required) {
    assertEquals(key in legal, true, `required key ${key} missing`);
  }
  assertEquals(
    Object.keys(legal).every((key) => key in schema.properties),
    true,
  );
});

Deno.test("parseDebriefCard converts truncated JSON into a classifiable machine code", () => {
  const error = assertThrows(() => parseDebriefCard('{"summary":"寫到一半'));
  assert(error instanceof Error);
  assertEquals(error.message, "debrief_json_parse_failed");
});

Deno.test("DEBRIEF_TOOL_SCHEMA_GAME promotes gameBreakdown to required", () => {
  const required = DEBRIEF_TOOL_SCHEMA_GAME.required as string[];
  assertEquals(required.includes("gameBreakdown"), true);
  assertEquals(
    (DEBRIEF_TOOL_SCHEMA.required as string[]).includes("gameBreakdown"),
    false,
  );
});

Deno.test("主觀 substance rubric＝finding、紅線照擋", () => {
  const turns = [
    { role: "user" as const, text: "今天忙到剛下班" },
    { role: "ai" as const, text: "我也剛下班，只想散步放空" },
  ];
  const card = {
    summary: "你說今天忙到剛下班，她接著分享只想散步放空。",
    strengths: ["有接到她說想散步的話"],
    watchouts: ["下一步要接住她想散步放空，不要只停在自己的忙碌。"],
    suggestedLine: "下班後散步很療癒，妳最常走哪一段？",
    vibe: "中性",
    dateChance: "medium",
    dateChanceReason: "她回覆自己剛下班想散步放空，但還沒提時間或見面。",
    nextInviteMove: "先問她最常去哪裡散步，等她多分享再看邀約窗口。",
  };
  const baseOpts = {
    requireCompleteCard: true,
    enforceGeneratedQuality: true,
    turns,
  };
  // 主觀 substance rubric＝偏好門：記 finding、卡照常供給。
  const { card: served, findings } = parseWithFindings(
    JSON.stringify(card),
    baseOpts,
  );
  assertEquals(served.strengths.length, 1);
  assert(findings.includes("debrief_quality_invalid_strength_substance"));
  // 紅線不降級：內部標籤洩漏仍整張打回。
  assertThrows(
    () =>
      parseDebriefCard(
        JSON.stringify({
          ...card,
          summary: "targetVariable: Investment 你說今天忙到剛下班。",
        }),
        baseOpts,
      ),
    Error,
    "debrief_internal_label_leak",
  );
});

Deno.test("regression: 「下次見面時，可以說：…」meta 前綴混進貼句欄＝finding（round5 #62/#18）", () => {
  for (
    const suggestedLine of [
      "下次見面時，可以說：「妳上次提的那間我查好了」。",
      "下次可以先說你自己最近在做什麼，或問她的安排。",
    ]
  ) {
    const { findings } = parseWithFindings(
      JSON.stringify({ ...generatedQualityCard, suggestedLine }),
      {
        requireCompleteCard: true,
        enforceGeneratedQuality: true,
        turns: [
          { role: "user", text: "早安" },
          { role: "ai", text: "我還在賴床，腦袋沒開機" },
        ],
      },
    );
    assert(
      findings.includes("debrief_quality_invalid_meta_line"),
      suggestedLine,
    );
  }
});

// ── 裁決 (a) 2026-07-23：grounding 功能句四型分治（呼叫點回歸）──
// raw 取自 tools/practice_single_shot_eval/results/2026-07-23T02-43-11-260Z.json
// gd2 r0/r2（判定表 #15/#16 提案時間豁免）、gd5 r3（#26 收尾允諾豁免）、
// gd3 r3（#22 捏造使用者近況，照擋）。

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

const gd2ProposalBreakdown = {
  phaseReached: "還在互相吐槽測試階段，氣氛熱但還沒進到真的約定",
  missedVariable: "她已經給了「排進我行程」的窗口，但沒被你接成實際時間地點",
  failureState: "你回到問時段這種資訊題，把她丟出來的曖昧窗口又變回問答",
  nextFirstLine: "妳說讓我見識，那週三晚上我先卡，妳排一下",
  inviteDirection: "先鋪一句具體畫面，再順勢問能不能那天去，不要只問時段",
};

const gd2ProposalCardBase = {
  summary: "聊羽球玩笑接得順，但問答收尾讓氣氛沒再往上走",
  strengths: [
    "接住「系隊的就了不起嗎」的吐槽並回嗆「讓妳見識」，玩笑有來有回",
    "「我不是那種人啦」有回應她的測試，沒被激怒或討好",
  ],
  watchouts: [
    "最後一句「先問妳都打哪個時段」又變成問資訊，把她給的機會用問答接掉",
    "她已經丟出「看你有沒有本事排進我的行程」這個窗口，你沒有直接接成具體提議",
  ],
  vibe: "中性",
  dateChance: "medium",
  dateChanceReason:
    "她願意玩梗、丟出行程窗口，但你沒接成具體邀約，只停在聊得順",
  nextInviteMove: "先給具體畫面，再順勢提議那天過去，不要只問時段",
};

Deno.test("generated Debrief exempts time-proposal pasteable lines from word-surface grounding (判定表 #15/#16)", () => {
  for (
    const suggestedLine of [
      "那週三晚上這場，我直接卡進去，妳留個位置給我？",
      "「那週三晚上我先卡好，妳排一下，輸了請妳吃東西」",
    ]
  ) {
    const card = parseDebriefCard(
      JSON.stringify({
        ...gd2ProposalCardBase,
        suggestedLine,
        gameBreakdown: gd2ProposalBreakdown,
      }),
      {
        allowGameBreakdown: true,
        requireCompleteCard: true,
        enforceGeneratedQuality: true,
        turns: gd2BadmintonTurns,
      },
    );
    assertEquals(card.suggestedLine.includes("週三晚上"), true);
  }
});

Deno.test("generated Debrief exempts short closing-promise nextFirstLine from word-surface grounding (判定表 #26)", () => {
  const card = parseDebriefCard(
    JSON.stringify({
      summary: "從市集興趣聊出專業感，順勢接住她的邀約窗口，氣氛熱絡。",
      strengths: [
        "用底片相機知識展現真實專業，她說「不是隨便唬我」給出肯定",
        "接住她問市集時間的訊號，直接給星期六下午的具體提議",
      ],
      watchouts: [
        "她已主動說「說好了，你負責幫我把關殺價」，這是明確窗口，別再用問答題稀釋",
        "目前只停在「陪逛市集」的默契，還沒把時間地點細節鎖死",
      ],
      suggestedLine: "好啊一言為定，我週六下午先訂好碰面時間跟地點傳給妳！",
      vibe: "暖",
      dateChance: "high",
      dateChanceReason:
        "她接梗又主動確認時間、還自己說好要一起逛，三個正向訊號都到齊",
      nextInviteMove: "趁她給的窗口還熱，直接把星期六下午約定時間地點講死",
      gameBreakdown: {
        phaseReached: "已經從聊興趣推進到她主動敲定星期六下午一起逛市集",
        missedVariable: "窗口出現後還沒把「投入感」轉成明確的碰面時間地點",
        failureState:
          "目前只是口頭說好，沒有把行動細節鎖住，容易隨對話結束而淡掉",
        nextFirstLine: "好啊一言為定，那我們約幾點碰面？我先抓個時間傳給妳",
        inviteDirection: "順著她給的窗口直接明確邀約，把市集這件事變成真的行程",
      },
    }),
    {
      allowGameBreakdown: true,
      requireCompleteCard: true,
      enforceGeneratedQuality: true,
      turns: gd5MarketTurns,
    },
  );
  assertEquals(card.gameBreakdown?.nextFirstLine.includes("一言為定"), true);
});

Deno.test("捏造使用者近況的貼句＝finding（判定表 #22，回歸）", () => {
  const { findings } = parseWithFindings(
    JSON.stringify({
      ...gd2ProposalCardBase,
      summary: "開場資訊堆砌，連續追問生活細節，觸發她的防線",
      suggestedLine:
        "「我最近也在計畫下個月去日本，想找個地方能邊泡溫泉邊看楓葉——妳有推薦的地方嗎？」",
      gameBreakdown: null,
    }),
    {
      requireCompleteCard: true,
      enforceGeneratedQuality: true,
      turns: gd2BadmintonTurns,
    },
  );
  assert(
    hasFinding(
      findings,
      "debrief_quality_invalid_suggested_line_not_grounded",
    ),
  );
});

// ===== 2026-07-23 真機回歸：exact＋preserved 的「對話狀態回顧」不得整卡打回 =====
// 來源：ai_logs 8a15dec5（practice_debrief_game 兩請求四發全滅）的 rejectedCandidates raw。
// 契約澄清：批評對象是「對話/局面」（聊天停在資訊交換、卡在一問一答）＝合法回顧；
// 批評對象是「這句/回覆/提示那句」仍照殺。

const fieldExactHint = {
  turnIndex: 4,
  type: "steady" as const,
  originalHintText:
    "有啦，有在練。不過我的菜單沒妳那麼講究，練腿那天也是亂吃😂 妳練腿通常吃爆什麼？",
  sentText:
    "有啦，有在練。不過我的菜單沒妳那麼講究，練腿那天也是亂吃😂 妳練腿通常吃爆什麼？",
  exact: true,
  hintRequestId: "hint-field-20260723",
  decision: {
    phase: "建立熟悉中",
    targetVariable: "生活樣本",
    move: "build_connection",
    inviteRoute: "build",
    rationale: "先接住她的訓練生活，再看她投入程度。",
  },
};

const fieldTurns = [
  { role: "user" as const, text: "我平常亂吃流派，練腿吃什麼都隨便" },
  {
    role: "ai" as const,
    text: "笑死 你也太廢了吧😂 練腿那天亂吃隔天會超慘",
  },
  {
    role: "user" as const,
    text: "敵。那妳練腿的日子是不是就得吃得更扎實一點？",
  },
  {
    role: "ai" as const,
    text:
      "喔～你懂喔？練腿那天我一定吃爆，不然隔天直接變殘廢😂 等等 你該不會也有在練吧",
  },
  {
    role: "user" as const,
    text:
      "有啦，有在練。不過我的菜單沒妳那麼講究，練腿那天也是亂吃😂 妳練腿通常吃爆什麼？",
  },
  {
    role: "ai" as const,
    text:
      "白飯配雞胸肉啊 再補個蛋 碳水蛋白質一起來 練完那餐真的不能省 不然腿會抗議😂",
  },
];

const fieldSonnetCard = {
  summary: "聊得順、有接住健身話題，但仍停在資訊交換，尚未推進到邀約",
  strengths: [
    "你有照提示做，跟著她的健身邏輯延伸問「練腿吃什麼」，接住她的梗",
    "用自嘲「亂吃流派」呼應她的玩笑，讓她笑著回「笑死」「太廢了吧」",
  ],
  watchouts: [
    "下一步：她給了具體菜單細節（白飯雞胸蛋）後可以順勢聊感受或畫面，別再問下一題資訊",
    "整段仍是一問一答的資訊交換，還沒帶進她本人的情緒或你的立場",
  ],
  suggestedLine: "白飯配雞胸這麼扎實，妳這樣吃完會不會反而更有精神想出去晃晃？",
  vibe: "中性",
  dateChance: "medium",
  dateChanceReason: "她願意細聊飲食細節、接梗自然，但沒有釋出時間或場景線索",
  nextInviteMove:
    "先別邀約，順著飲食話題多聊一輪感受，等她主動提時間或地點再接",
  gameBreakdown: {
    phaseReached: "還在開場熟悉階段，聊得算輕鬆但沒往下一層推進",
    missedVariable: "她的情緒和感受沒被聊到，一直停在飲食資訊上",
    failureState:
      "卡在一問一答的資訊乒乓，內容都是「吃什麼」沒有延伸到她的心情或畫面",
    nextFirstLine:
      "白飯配雞胸這麼扎實，妳這樣吃完會不會反而更有精神想出去晃晃？",
    inviteDirection:
      "先不邀約，順勢聊她練完的感受或放鬆方式，鋪墊夠了再找時間窗口",
  },
  hintAssessment: { verdict: "preserved", revisedEvidenceQuote: null },
};

const fieldParseOptions = {
  allowGameBreakdown: true,
  requireCompleteCard: true,
  turns: fieldTurns,
  appliedHintTurns: [fieldExactHint],
  enforceGeneratedQuality: true,
};
Deno.test("debriefToolSchemaFor：hintAssessment 已退役，任何模式都不必填", () => {
  const plain = debriefToolSchemaFor({ game: false });
  const game = debriefToolSchemaFor({ game: true });
  assertEquals(
    (plain.required as string[]).includes("hintAssessment"),
    false,
  );
  assertEquals(
    (game.required as string[]).includes("hintAssessment"),
    false,
  );
  assertEquals(
    (game.required as string[]).includes("gameBreakdown"),
    true,
  );
});

// 2026-07-23 真 API eval 第二、三輪抓到的 FP 措辭家族——契約固定：
// 進度陳述/條件教學句/路線語不算翻案或捏造。
Deno.test("真機回歸 2026-07-23：eval 抓到的 FP 措辭家族全放行", () => {
  const variants: Array<Partial<typeof fieldSonnetCard>> = [
    // credit＋但＋進度陳述（整場停在資訊交換）
    { summary: "你接住健身話題並照提示延伸，但整場仍停在資訊交換階段" },
    // credit＋但＋缺乏下一步鋪墊（negEval 不得只因「照提示」就咬）
    {
      summary:
        "照提示接住她的訓練節奏，聊天自然流暢，但缺乏下一步鋪墊，投入度停留在舒適分享。",
    },
    // 「不要急著邀約」＝build 路線語，不是 repair
    {
      nextInviteMove:
        "先用「你懂喔」拉近距離，再從訓練或飲食習慣找到可以一起做的畫面，不要急著邀約。",
    },
    // 「沒有…她主動延伸的邀約訊號」＝否定句，不是她主動邀約過的宣稱
    {
      dateChanceReason:
        "聊天順暢舒服，但只有生活資訊交換，沒有場景畫面、時間線索或她主動延伸的邀約訊號。",
    },
    // 「等她主動釋出時間或場景再考慮邀約」＝未來條件教學句
    {
      gameBreakdown: {
        ...fieldSonnetCard.gameBreakdown,
        inviteDirection:
          "先別邀約，順著訓練話題多聊幾輪，等她主動釋出時間或場景再考慮邀約",
      },
    },
  ];
  for (const patch of variants) {
    const card = parseDebriefCard(
      JSON.stringify({ ...fieldSonnetCard, ...patch }),
      { ...fieldParseOptions },
    );
    assert(card.summary.length > 0);
  }
});

// schema 把 revisedEvidenceQuote 升必填後，模型在 preserved 時傾向填「她的
// 原句」而非 null（2026-07-23 eval ×2）——引句可在 ai turn 逐字找到＝無害
Deno.test("partner initiative 證據：可以＋後續動作不算拍板", () => {
  const { findings } = parseWithFindings(
    JSON.stringify({
      ...fieldSonnetCard,
      dateChanceReason: "她主動提了見面邀約，時間也點頭了",
    }),
    {
      ...fieldParseOptions,
      turns: [
        ...fieldTurns.slice(0, -1),
        { role: "ai" as const, text: "下午可以再看看吧" },
      ],
    },
  );
  assert(
    hasFinding(findings, "debrief_quality_invalid_partner_initiative"),
  );
});

// Codex 三審 P2：「可以」後接的話/語氣詞再＋動作＝保留句，時間 pattern 不得先放行。
Deno.test("partner initiative 證據：可以＋語氣詞＋再看仍不算拍板", () => {
  for (
    const turnText of [
      "下午可以的話再看看吧",
      "下午可以欸再看看吧",
      "下午可以喔再說",
      "下午可以吧再喬",
    ]
  ) {
    const { findings } = parseWithFindings(
      JSON.stringify({
        ...fieldSonnetCard,
        dateChanceReason: "她主動提了見面邀約，時間也點頭了",
      }),
      {
        ...fieldParseOptions,
        turns: [
          ...fieldTurns.slice(0, -1),
          { role: "ai" as const, text: turnText },
        ],
      },
    );
    assert(
      hasFinding(findings, "debrief_quality_invalid_partner_initiative"),
      turnText,
    );
  }
});

// Codex 四審 P2：保留句 bail 限本子句，同 turn 其他子句的真證據仍要收。
Deno.test("partner initiative 證據：保留句後的真空檔/真邀約子句仍算數", () => {
  for (
    const turnText of [
      "下午可以再看看吧，我週六有空",
      "下午可以再說，我週六有空",
      "下午可以再看看吧，要不要一起喝咖啡",
    ]
  ) {
    const card = parseDebriefCard(
      JSON.stringify({
        ...fieldSonnetCard,
        dateChanceReason: "她主動提了見面邀約，時間也點頭了",
      }),
      {
        ...fieldParseOptions,
        turns: [
          ...fieldTurns.slice(0, -1),
          { role: "ai" as const, text: turnText },
        ],
      },
    );
    assertEquals(card.dateChanceReason.length > 0, true, turnText);
  }
});
// ===== salvage pass：紅線以外一律讓路（2026-08-06 黑名單拍板）=====
// 事故：ai_logs practice_debrief_standard 08-05 13:44:47/13:45:19 兩筆，逐字稿
// 只有「你好」「嗨～你好」，唯一能通過詞面比對的建議句是複讀「你好」——兩發
// 全滅轉 503。守門嚴重度分級後 grounding 在正式發已是 finding，salvage 只剩
// 結構性失敗與紅線要處理。

const salvageGreetingTurns = [
  { role: "user" as const, text: "你好" },
  { role: "ai" as const, text: "嗨～你好" },
];

// 鏡像 salvageDebriefCandidate 實際使用的解析設定。
const salvageOptions = {
  requireCompleteCard: true,
  enforceGeneratedQuality: true,
  degradeStructuralDefects: true,
  salvagePass: true,
  turns: salvageGreetingTurns,
} as const;

function salvageGreetingCard(suggestedLine: string): string {
  return JSON.stringify({
    summary: "對話僅止於打招呼，尚未展開任何話題，無法判斷互動品質。",
    strengths: ["有主動開口打招呼，禮貌開場"],
    watchouts: ["未接續任何話題，對話停在寒暄無法留下記憶點"],
    suggestedLine,
    vibe: "中性",
    dateChance: "low",
    dateChanceReason: "她只回了「嗨～你好」，未釋出任何延伸或時間線索。",
    nextInviteMove: "先從她的背景聊起，建立輕鬆話題後再觀察熱度。",
  });
}

Deno.test("salvage：ai_logs 當天被打回的真實候選解得出來", () => {
  const card = parseDebriefCard(
    salvageGreetingCard("嗨～剛看到你資料上有健身教練，平常帶課會很累嗎？"),
    salvageOptions,
  );
  assertEquals(
    card.suggestedLine,
    "嗨～剛看到你資料上有健身教練，平常帶課會很累嗎？",
  );
  assertEquals(card.dateChance, "low");
});

Deno.test("salvage 不放掉 L4：露骨越界候選照樣打回", () => {
  // 樣本取自 visible_text_guard_test.ts:167 的 L4 fail-closed 攻擊字串。
  assertThrows(
    () =>
      parseDebriefCard(
        salvageGreetingCard("偷偷加重量還不能拒絕吧，現在跟我回家"),
        salvageOptions,
      ),
    Error,
    "debrief_l4_unsafe",
  );
});

Deno.test("salvage 不放掉罐頭簽名", () => {
  // 樣本取自 practice_visible_quality.ts 的 KNOWN_CANNED_SIGNATURES。
  assertThrows(
    () =>
      parseDebriefCard(
        salvageGreetingCard(
          "妳剛說的那個點我有記住，我先分享我的版本，再聽妳的。",
        ),
        salvageOptions,
      ),
    Error,
    "debrief_canned_visible_text",
  );
});

Deno.test("捏造對方主動邀約：正式發記 finding、salvage 讓路（捏造已移出紅線）", () => {
  const fabricated = JSON.stringify({
    summary: "她主動提出要見面，你沒有接住這個機會。",
    strengths: ["有禮貌開場"],
    watchouts: ["她主動約你出來，你沒有回應"],
    suggestedLine: "妳說想見面的話，我這邊都可以配合。",
    vibe: "暖",
    dateChance: "high",
    dateChanceReason: "她主動提出見面。",
    nextInviteMove: "直接敲定時間。",
  });
  // 正式發：卡照端出、finding 記錄捏造碼。
  const { findings } = parseWithFindings(fabricated, {
    requireCompleteCard: true,
    enforceGeneratedQuality: true,
    turns: salvageGreetingTurns,
  });
  assert(findings.includes("debrief_quality_invalid_partner_initiative"));
  // salvage：紅線以外讓路，照樣端出（2026-08-06 Eric 拍板捏造移出紅線）。
  const card = parseDebriefCard(fabricated, salvageOptions);
  assertEquals(card.dateChance, "high");
});

Deno.test("正式發 grounding 降為 finding：短對話不再連殺兩發", () => {
  const { card, findings } = parseWithFindings(
    salvageGreetingCard("嗨～剛看到你資料上有健身教練，平常帶課會很累嗎？"),
    {
      requireCompleteCard: true,
      enforceGeneratedQuality: true,
      turns: salvageGreetingTurns,
    },
  );
  assertEquals(
    card.suggestedLine,
    "嗨～剛看到你資料上有健身教練，平常帶課會很累嗎？",
  );
  assert(
    findings.includes("debrief_quality_invalid_suggested_line_not_grounded"),
  );
});

Deno.test("salvageDebriefCandidate：優先採用主模型候選（attemptFailures 順序）", () => {
  const salvaged = salvageDebriefCandidate({
    failures: [
      {
        model: "claude-sonnet-5",
        code: "debrief_quality_invalid_suggested_line_not_grounded",
        raw: salvageGreetingCard(
          "嗨～剛看到你資料上有健身教練，平常帶課會很累嗎？",
        ),
      },
      {
        model: "claude-haiku-4-5-20251001",
        code: "debrief_quality_invalid_suggested_line_not_grounded",
        raw: salvageGreetingCard("最近在忙什麼？還是剛下課放鬆中？"),
      },
    ],
    parseOptions: {
      requireCompleteCard: true,
      enforceGeneratedQuality: true,
      turns: salvageGreetingTurns,
    },
  });
  assertEquals(salvaged?.model, "claude-sonnet-5");
  assertEquals(
    salvaged?.card.suggestedLine,
    "嗨～剛看到你資料上有健身教練，平常帶課會很累嗎？",
  );
});

Deno.test("salvageDebriefCandidate：主模型候選違反不可退讓守門時，換下一張", () => {
  const salvaged = salvageDebriefCandidate({
    failures: [
      // Sonnet 這張踩 L4，不可搶救
      {
        model: "claude-sonnet-5",
        code: "debrief_quality_invalid_suggested_line_not_grounded",
        raw: salvageGreetingCard("偷偷加重量還不能拒絕吧，現在跟我回家"),
      },
      {
        model: "claude-haiku-4-5-20251001",
        code: "debrief_quality_invalid_suggested_line_not_grounded",
        raw: salvageGreetingCard("最近在忙什麼？還是剛下課放鬆中？"),
      },
    ],
    parseOptions: {
      requireCompleteCard: true,
      enforceGeneratedQuality: true,
      turns: salvageGreetingTurns,
    },
  });
  assertEquals(salvaged?.model, "claude-haiku-4-5-20251001");
});

Deno.test("salvageDebriefCandidate：沒有 raw（傳輸層失敗）或全部搶救失敗 → null", () => {
  const parseOptions = {
    requireCompleteCard: true,
    enforceGeneratedQuality: true,
    turns: salvageGreetingTurns,
  };
  // 逾時/5xx 這類傳輸失敗沒有候選原文
  assertEquals(
    salvageDebriefCandidate({
      failures: [
        { model: "claude-sonnet-5", code: "claude_timeout" },
        { model: "claude-haiku-4-5-20251001", code: "claude_timeout" },
      ],
      parseOptions,
    }),
    null,
  );
  // 兩張都踩不可退讓守門
  assertEquals(
    salvageDebriefCandidate({
      failures: [
        {
          model: "claude-sonnet-5",
          code: "debrief_quality_invalid_suggested_line_not_grounded",
          raw: salvageGreetingCard("偷偷加重量還不能拒絕吧，現在跟我回家"),
        },
        { model: "claude-haiku-4-5-20251001", raw: "這根本不是 JSON" },
      ],
      parseOptions,
    }),
    null,
  );
});

// 2026-08-06 Eric 拍板把 salvage 從白名單翻成黑名單，推翻了原本的
// 「salvage 只收 grounding 敗因」（Codex 二審 #4 訂下的規則）。
// 新規則：只有紅線（露骨／內部洩漏／溫度洩漏／罐頭）不得搶救，其他一律端出去。
Deno.test("salvage 黑名單：非紅線敗因照常搶救，紅線敗因一律不救", () => {
  const parseOptions = {
    requireCompleteCard: true,
    enforceGeneratedQuality: true,
    turns: salvageGreetingTurns,
  };
  const goodRaw = salvageGreetingCard(
    "嗨～剛看到你資料上有健身教練，平常帶課會很累嗎？",
  );
  for (
    const code of [
      "debrief_quality_invalid_hint_accountability",
      "debrief_quality_invalid_suggested_line_not_grounded",
      "debrief_quality_invalid_partner_initiative",
      "debrief_missing_fields",
    ]
  ) {
    assertEquals(
      salvageDebriefCandidate({
        failures: [{ model: "claude-sonnet-5", code, raw: goodRaw }],
        parseOptions,
      })?.model,
      "claude-sonnet-5",
      code,
    );
  }
  for (
    const code of [
      "debrief_l4_unsafe",
      "debrief_canned_visible_text",
      "debrief_temperature_leak",
    ]
  ) {
    assertEquals(
      salvageDebriefCandidate({
        failures: [{ model: "claude-sonnet-5", code, raw: goodRaw }],
        parseOptions,
      }),
      null,
      code,
    );
  }
});

// 2026-08-06 真機案例：Kelly 局候選的 Game 拆盤四欄字面複製同一句籠統話。
// salvage 端把 gameBreakdown 整塊丟掉、卡片其餘部分照常端出去，而不是讓整張卡
// 也搶救不了（「正常一定要有輸出」優先於拆盤完整性）。
function salvageGameEchoCard(): string {
  return JSON.stringify({
    summary: "你有照提示做，她也願意延續話題。",
    strengths: ["你有照提示做，接住她丟回來的梗"],
    watchouts: ["下一步別只追問，多補一點生活感"],
    suggestedLine: "剛剛這個點我有接到，妳比較想先聊哪一段？",
    vibe: "中性",
    dateChance: "medium",
    dateChanceReason: "她願意延續話題和你來回。",
    nextInviteMove: "先接她剛丟回來的話題，再補一點你的生活畫面。",
    gameBreakdown: {
      phaseReached: "熟悉進度仍在延續她剛丟回來的話題。",
      missedVariable: "下一步缺的是你對她剛丟回來的話題的生活感。",
      failureState: "她仍停在低壓延續她剛丟回來的話題的節奏。",
      nextFirstLine: "剛剛這個點我有接到，妳比較想先聊哪一段？",
      inviteDirection: "先補你對她剛丟回來的話題的生活畫面，保留低壓節奏。",
    },
  });
}

Deno.test("真機回歸 2026-08-06：Game 拆盤四欄複製同句籠統話的候選，salvage 丟掉拆盤區塊而不是丟整張卡", () => {
  const salvaged = salvageDebriefCandidate({
    failures: [{
      model: "claude-haiku-4-5-20251001",
      code: "debrief_missing_fields",
      raw: salvageGameEchoCard(),
    }],
    parseOptions: {
      allowGameBreakdown: true,
      requireCompleteCard: true,
      enforceGeneratedQuality: true,
      turns: [
        { role: "user" as const, text: "下次還要一起去旅行嗎" },
        { role: "ai" as const, text: "哈哈 想得美喔 你先規劃得動再說" },
      ],
    },
  });
  assertEquals(salvaged?.model, "claude-haiku-4-5-20251001");
  assertEquals(salvaged?.card.gameBreakdown, null);
  assertEquals(
    salvaged?.card.suggestedLine,
    "剛剛這個點我有接到，妳比較想先聊哪一段？",
  );
});

Deno.test("真機回歸 2026-08-06：Game 拆盤字面回聲在前兩發（非 salvage）仍照擋，逼重生成", () => {
  assertThrows(
    () =>
      parseDebriefCard(salvageGameEchoCard(), {
        allowGameBreakdown: true,
        requireCompleteCard: true,
        enforceGeneratedQuality: true,
        turns: [
          { role: "user" as const, text: "下次還要一起去旅行嗎" },
          { role: "ai" as const, text: "哈哈 想得美喔 你先規劃得動再說" },
        ],
      }),
    Error,
    "debrief_game_breakdown_field_echo",
  );
});

// ── 2026-08-06 W3：乙類（結構／格式）改修補或降級，不再丟整張卡 ──
// 只有 salvage 可以開 degradeStructuralDefects；前兩發照擋，留給 retry 一次
// 產出完整卡的機會。分類見 docs/plans/2026-08-06-practice-no-503.md。

const w3CompleteCard = {
  ...JSON.parse(valid),
  dateChance: "low",
  dateChanceReason: "還沒看到窗口",
  nextInviteMove: "先多聊一個具體話題",
};

Deno.test("W3 debrief：列舉外的 vibe/dateChance 在 salvage 落安全預設而不是丟整張卡", () => {
  const card = parseDebriefCard(
    JSON.stringify({ ...w3CompleteCard, vibe: "超熱", dateChance: "爆表" }),
    { requireCompleteCard: true, degradeStructuralDefects: true },
  );
  assertEquals(card.vibe, "中性");
  // dateChanceReason 非空＝有訊號可談，落 medium（見 parseDebriefCard 的預設）。
  assertEquals(card.dateChance, "medium");
  assertEquals(card.summary.length > 0, true);
});

Deno.test('W3 debrief：Game 拆盤寫成字串 "null" 時，salvage 丟掉那一塊而不是丟整張卡', () => {
  const raw = JSON.stringify({ ...w3CompleteCard, gameBreakdown: "null" });
  // 前兩發照擋：Game 卡少了拆盤仍該重生成一次。
  assertThrows(
    () =>
      parseDebriefCard(raw, {
        requireCompleteCard: true,
        allowGameBreakdown: true,
      }),
    Error,
    "debrief_game_breakdown_missing_fields",
  );
  const card = parseDebriefCard(raw, {
    requireCompleteCard: true,
    allowGameBreakdown: true,
    degradeStructuralDefects: true,
  });
  assertEquals(card.gameBreakdown, null);
  assertEquals(card.summary.length > 0, true);
});

Deno.test("W3 debrief：Game 拆盤缺欄位時，salvage 丟掉那一塊而不是丟整張卡", () => {
  const raw = JSON.stringify({
    ...w3CompleteCard,
    gameBreakdown: {
      phaseReached: "賴床話題的熟悉建立",
      missedVariable: "",
      failureState: "照貼提示後停在禮貌收尾",
      nextFirstLine: "慢慢開機也行，我先分享我的起床儀式",
      inviteDirection: "先延續賴床話題，再看她是否多投入",
    },
  });
  assertThrows(
    () =>
      parseDebriefCard(raw, {
        requireCompleteCard: true,
        allowGameBreakdown: true,
      }),
    Error,
    "debrief_game_breakdown_missing_fields",
  );
  const card = parseDebriefCard(raw, {
    requireCompleteCard: true,
    allowGameBreakdown: true,
    degradeStructuralDefects: true,
  });
  assertEquals(card.gameBreakdown, null);
});

Deno.test("W3 debrief：核心欄位缺席不在降級範圍，degrade 也照擋", () => {
  // 刻意偏離計畫檔把 debrief_missing_fields 列為乙類：strengths/watchouts 全空的
  // 卡是「使用者看得到的殘卡」，不是形狀壞掉，端出去比 503 更糟。
  assertThrows(
    () =>
      parseDebriefCard(
        JSON.stringify({ ...w3CompleteCard, strengths: [], watchouts: [] }),
        { requireCompleteCard: true, degradeStructuralDefects: true },
      ),
    Error,
    "debrief_missing_fields",
  );
});
