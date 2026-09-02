import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  CANDIDATE_GUARD_CODES,
  type CandidateGuardCandidate,
  type CandidateGuardInput,
  runCandidateGuard,
} from "./candidate_guard.ts";

const STYLES = ["extend", "resonate", "tease", "humor", "coldRead"];

function card(
  style: string,
  patch: Partial<CandidateGuardCandidate> = {},
): CandidateGuardCandidate {
  return {
    style,
    text: "SEGMENT_SECRET_ONE\nSEGMENT_SECRET_TWO",
    segments: [
      { sourceIndex: 1, sourceMessage: "HER_SECRET_ONE" },
      { sourceIndex: 3, sourceMessage: "HER_SECRET_THREE" },
    ],
    action: "extend",
    selectedBallIds: ["b_1", "b_3"],
    selectedBranchIds: ["br_1"],
    ...patch,
  };
}

/// 一組乾淨的 v2 send：1／3 接、2 併、4 略；計畫兩枝都在 cap 內。
function clean(patch: Partial<CandidateGuardInput> = {}): CandidateGuardInput {
  return {
    decision: {
      messageDecision: "send",
      replyMode: "variants",
      action: "extend",
      selectedBallIds: ["b_1", "b_3"],
      selectedStyle: "extend",
    },
    dispositions: new Map([[1, "接"], [2, "併"], [3, "接"], [4, "略"]]),
    plan: {
      semanticDistanceCap: 1,
      questionBudget: 1,
      newTopicBudget: 0,
      branchPool: [
        {
          id: "br_1",
          method: "drill_down",
          semanticDistance: 1,
          associationPath: ["PATH_SECRET"],
        },
        {
          id: "br_2",
          method: "association",
          semanticDistance: 2,
          associationPath: [],
        },
      ],
    },
    candidates: STYLES.map((style) => card(style)),
    ...patch,
  };
}

const codesOf = (input: CandidateGuardInput) =>
  runCandidateGuard(input).violations.map((v) => v.code);
/// 沒帶 action／balls 的卡：讓決策層的測試不被 variant drift 蓋掉。
const bare = (style: string) =>
  card(style, { action: undefined, selectedBallIds: undefined });

Deno.test("candidate guard: a clean send passes every gate it can check", () => {
  const result = runCandidateGuard(clean());
  assertEquals(result.violations, []);
  assertEquals(result.checked, [
    "reply_mode_card_count",
    "decision_action_conflict",
    "variant_action_drift",
    "variant_ball_drift",
    "source_ball_unknown",
    "skipped_ball_used",
    "merge_ball_isolated",
    "caught_ball_uncovered",
    "card_source_mismatch",
    "placeholder",
    "question_budget",
    "semantic_distance_cap",
    "association_without_path",
    "no_send_with_cards",
  ]);
  // newTopicCount 沒人帶 → 不算檢查過。
  assertFalse(result.checked.includes("new_topic_budget"));
});

Deno.test("candidate guard: no evidence at all checks nothing", () => {
  const result = runCandidateGuard({
    decision: null,
    dispositions: null,
    plan: null,
    candidates: [],
  });
  assertEquals(result, { violations: [], checked: [] });
});

Deno.test("candidate guard: replyMode variants needs at least two cards", () => {
  assertEquals(codesOf(clean({ candidates: [card("extend")] })), [
    "reply_mode_card_count",
  ]);
  // replyMode 缺席時從 messageDecision 推：send＝variants。
  assertEquals(
    codesOf(clean({
      decision: { messageDecision: "send" },
      candidates: [card("extend")],
    })),
    ["reply_mode_card_count"],
  );
});

Deno.test("candidate guard: no-send decisions must not carry reply cards", () => {
  for (
    const messageDecision of [
      "do_not_send",
      "acknowledge_and_stop",
      "need_context",
    ]
  ) {
    const result = runCandidateGuard(clean({
      decision: { messageDecision, action: "pause" },
      candidates: [bare("extend"), bare("tease")],
    }));
    assertEquals(
      result.violations.map((v) => v.code),
      ["no_send_with_cards"],
      messageDecision,
    );
  }
  // 決策說 send 但 replyMode none 一樣是藏卡（沿用 Phase 0 noSendConflict）。
  assertEquals(
    codesOf(clean({
      decision: { messageDecision: "send", replyMode: "none" },
    })),
    ["no_send_with_cards"],
  );
  // 只有兩張卡、決策 action 是 pause：藏卡之外 action 也漂移，兩者都要記。
  assertEquals(
    codesOf(clean({
      decision: { messageDecision: "do_not_send", action: "pause" },
      candidates: [card("extend"), card("tease")],
    })).sort(),
    ["no_send_with_cards", "variant_action_drift", "variant_action_drift"],
  );
  assertEquals(
    codesOf(clean({
      decision: { messageDecision: "do_not_send", action: "pause" },
      candidates: [],
    })),
    [],
  );
});

Deno.test("candidate guard: messageDecision and action must agree (§12)", () => {
  assertEquals(
    codesOf(clean({
      decision: { messageDecision: "send", action: "stop" },
      candidates: STYLES.map(bare),
    })),
    ["decision_action_conflict"],
  );
  assertEquals(
    codesOf(clean({
      decision: { messageDecision: "do_not_send", action: "invite" },
      candidates: [],
    })),
    ["decision_action_conflict"],
  );
  for (const action of ["stop", "pause"]) {
    assertEquals(
      codesOf(clean({
        decision: { messageDecision: "acknowledge_and_stop", action },
        candidates: [],
      })),
      [],
    );
  }
  // action 缺席（現行 v2 send 決策）→ 不檢查。
  assertFalse(
    runCandidateGuard(clean({ decision: { messageDecision: "send" } }))
      .checked.includes("decision_action_conflict"),
  );
});

Deno.test("candidate guard: variants must share action and selectedBallIds", () => {
  const drifted = runCandidateGuard(clean({
    candidates: [
      card("extend"),
      card("tease", { action: "invite" }),
      card("humor", { selectedBallIds: ["b_3", "b_1"] }),
      card("coldRead", { selectedBallIds: ["b_1"] }),
    ],
  }));
  assertEquals(drifted.violations, [
    { code: "variant_action_drift", style: "tease" },
    { code: "variant_ball_drift", style: "coldRead" },
  ]);
  // 決策沒帶 action／balls 時，variants 之間互比。
  const noDecision = runCandidateGuard(clean({
    decision: { messageDecision: "send" },
    candidates: [card("extend"), card("tease", { action: "connect" })],
  }));
  assertEquals(noDecision.violations, [
    { code: "variant_action_drift", style: "tease" },
  ]);
  // 只有一張卡帶 action 又沒有決策 action → 無從比較。
  assertFalse(
    runCandidateGuard(clean({
      decision: { messageDecision: "send" },
      candidates: [card("extend"), card("tease", { action: undefined })],
    })).checked.includes("variant_action_drift"),
  );
});

Deno.test("candidate guard: segments must come from caught balls in the inventory", () => {
  const result = runCandidateGuard(clean({
    candidates: [
      card("extend", {
        segments: [
          { sourceIndex: 1 },
          { sourceIndex: 2 },
          { sourceIndex: 4 },
          { sourceIndex: 9 },
          { sourceIndex: 9 },
        ],
      }),
      card("tease"),
    ],
  }));
  assertEquals(result.violations, [
    { code: "source_ball_unknown", style: "extend", sourceIndex: 9 },
    { code: "skipped_ball_used", style: "extend", sourceIndex: 4 },
    { code: "merge_ball_isolated", style: "extend", sourceIndex: 2 },
    { code: "caught_ball_uncovered", style: "extend", sourceIndex: 3 },
    { code: "card_source_mismatch", style: "tease" },
  ]);
  // 沒有可驗盤點 → 球面四道都不算檢查過（沿用 reframer fail-soft 語意）。
  const unchecked = runCandidateGuard(clean({ dispositions: null })).checked;
  for (
    const code of [
      "source_ball_unknown",
      "skipped_ball_used",
      "merge_ball_isolated",
      "caught_ball_uncovered",
    ]
  ) {
    assertFalse(unchecked.includes(code as typeof unchecked[number]), code);
  }
});

Deno.test("candidate guard: every card must follow the selected card's source sequence", () => {
  const reordered = runCandidateGuard(clean({
    candidates: [
      card("extend"),
      card("tease", {
        segments: [
          { sourceIndex: 3, sourceMessage: "HER_SECRET_THREE" },
          { sourceIndex: 1, sourceMessage: "HER_SECRET_ONE" },
        ],
      }),
      card("humor", {
        segments: [
          { sourceIndex: 1, sourceMessage: "HER_SECRET_ONE" },
          { sourceIndex: 3, sourceMessage: "HER_SECRET_THREE_EDITED" },
        ],
      }),
      // 只缺 sourceMessage：索引順序一致就不算不一致。
      card("coldRead", { segments: [{ sourceIndex: 1 }, { sourceIndex: 3 }] }),
    ],
  }));
  assertEquals(
    reordered.violations.filter((v) => v.code === "card_source_mismatch"),
    [
      { code: "card_source_mismatch", style: "tease" },
      { code: "card_source_mismatch", style: "humor" },
    ],
  );
  // 基準卡是 decision.selectedStyle，不是第一張。
  const baseline = runCandidateGuard(clean({
    decision: { messageDecision: "send", selectedStyle: "tease" },
    candidates: [
      card("extend", { segments: [{ sourceIndex: 1 }] }),
      card("tease"),
      card("humor"),
    ],
  }));
  assertEquals(
    baseline.violations.filter((v) => v.code === "card_source_mismatch"),
    [{ code: "card_source_mismatch", style: "extend" }],
  );
});

Deno.test("candidate guard: placeholders are flagged, ordinary punctuation is not", () => {
  for (
    const text of [
      "那天在[地點]拍的",
      "我猜妳是〇〇派",
      "等等去XX夜市",
      "那家叫（店名）的",
      "先去___再說",
      "跟某某一起去",
    ]
  ) {
    assertEquals(
      codesOf(clean({ candidates: [card("extend", { text }), card("tease")] })),
      ["placeholder"],
      text,
    );
  }
  for (
    const text of [
      "妳這行程根本熱血女主角XD",
      "看完比賽還有力氣逛夜市（我嚴重懷疑）",
      "哈哈哈哈 >< 好想去",
      "這個 <3",
    ]
  ) {
    assertEquals(
      codesOf(clean({ candidates: [card("extend", { text }), card("tease")] })),
      [],
      text,
    );
  }
});

Deno.test("candidate guard: question, new-topic and distance budgets come from the plan", () => {
  const over = runCandidateGuard(clean({
    candidates: [
      card("extend", { text: "妳在哪拍的？\n還是誰幫妳拍的？" }),
      card("tease", { newTopicCount: 1 }),
      card("humor", { semanticDistance: 2 }),
      card("coldRead", { selectedBranchIds: ["br_2"] }),
    ],
  }));
  assertEquals(over.violations, [
    { code: "question_budget", style: "extend" },
    { code: "new_topic_budget", style: "tease" },
    { code: "semantic_distance_cap", style: "humor" },
    { code: "semantic_distance_cap", style: "coldRead", branchId: "br_2" },
    { code: "association_without_path", style: "coldRead", branchId: "br_2" },
  ]);
  // 沒計畫、決策也沒帶預算 → 預算類都不算檢查過。
  const unchecked = runCandidateGuard(clean({ plan: null })).checked;
  for (
    const code of [
      "question_budget",
      "new_topic_budget",
      "semantic_distance_cap",
      "association_without_path",
    ]
  ) {
    assertFalse(unchecked.includes(code as typeof unchecked[number]), code);
  }
  // 決策自帶預算時也算數（未來 decision contract）。
  assertEquals(
    codesOf(clean({
      plan: null,
      decision: { messageDecision: "send", questionBudget: 0 },
      candidates: [card("extend", { text: "妳在哪拍的？" }), card("tease")],
    })),
    ["question_budget"],
  );
});

Deno.test("candidate guard: output carries codes, styles and ids only, never text", () => {
  const input = clean({
    candidates: [
      card("extend", {
        text: "SEGMENT_SECRET [地點]？？",
        segments: [{ sourceIndex: 4, sourceMessage: "HER_SECRET_FOUR" }],
        selectedBranchIds: ["br_2"],
      }),
      card("tease"),
    ],
  });
  const serialized = JSON.stringify(runCandidateGuard(input));
  for (const secret of ["SECRET", "地點", "PATH"]) {
    assertFalse(serialized.includes(secret), secret);
  }
  assert(CANDIDATE_GUARD_CODES.length === 15);
});
