import {
  assert,
  assertAlmostEquals,
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  applyArmOverride,
  applySseEvent,
  ARMS,
  buildBlindSheet,
  type CallRecord,
  estimatePlan,
  newProviderCall,
  paidGuardError,
  parseArms,
  parsePaidFlags,
  parseRepeat,
  percentile,
  planCalls,
  summarizeArms,
} from "./ab.ts";
import { CORPUS, REFUSAL_PROBE_IDS } from "./corpus.ts";

const IDS = CORPUS.map((c) => c.id);

Deno.test("plan: A,B×2 is 4 calls per case, C×1 is one, arms interleave inside each case", () => {
  const ab = planCalls(IDS, ["A", "B"], parseRepeat("2", ["A", "B"]));
  assertEquals(ab.length, IDS.length * 4);
  assertEquals(
    planCalls(IDS, ["C"], parseRepeat("1", ["C"])).length,
    IDS.length,
  );
  const abc = planCalls(
    IDS,
    ["A", "B", "C"],
    parseRepeat("A:2,B:2,C:1", ["A", "B", "C"]),
  );
  assertEquals(abc.length, IDS.length * 5);
  for (const id of IDS) {
    const order = ab.filter((c) => c.caseId === id).map((c) => c.arm);
    assertEquals([...order].sort(), ["A", "A", "B", "B"]);
    assert(order[0] !== order[1], `${id} first round is interleaved`);
  }
  // 沒有哪一臂固定先跑。
  assertEquals(
    new Set(ab.filter((c) => c.rep === 1).map((c) => c.arm)).size,
    2,
  );
  assertThrows(() => parseArms("A,D"));
  assertThrows(() => parseRepeat("C:1", ["A", "B"]));
  assert(REFUSAL_PROBE_IDS.every((id) => IDS.includes(id)));
});

Deno.test("estimate: repeats of the same case and arm are priced as cache reads; judge counts send-capable cases", () => {
  const tokens = Object.fromEntries(
    IDS.map((id) => [id, { system: 40_000, user: 300 }]),
  );
  const once = estimatePlan(
    planCalls(IDS, ["A"], { A: 1 } as never),
    tokens,
    6500,
  );
  const twice = estimatePlan(
    planCalls(IDS, ["A"], { A: 2 } as never),
    tokens,
    6500,
  );
  // 一次：40k×$2.50＋300×$2＋6500×$10 ＝ $0.1656。
  assertEquals(Number((once.mainUsd / IDS.length).toFixed(4)), 0.1656);
  assert(twice.mainUsd < 2 * once.mainUsd);
  assertAlmostEquals(twice.mainNoCacheUsd, 2 * once.mainNoCacheUsd, 1e-9);
  const sendable =
    CORPUS.filter((c) => c.expect.messageDecision.includes("send"))
      .length;
  assertEquals(once.judgeCalls, sendable);
  const c = estimatePlan(
    planCalls(IDS, ["C"], { C: 1 } as never),
    tokens,
    6500,
  );
  // C 臂輸出上界多 4000 token。
  assertEquals(
    Number(((c.mainUsd - once.mainUsd) / IDS.length).toFixed(4)),
    0.04,
  );
});

Deno.test("paid guard refuses real calls unless every flag is present and covers the plan", () => {
  const ok = parsePaidFlags([
    "--run",
    "--confirm-paid",
    "--max-calls=84",
    "--budget-usd=17",
  ]);
  assertEquals(paidGuardError(ok, 84, 10), null);
  assert(paidGuardError(parsePaidFlags([]), 84, 10)?.startsWith("dry-run"));
  for (
    const drop of ["--confirm-paid", "--max-calls=84", "--budget-usd=17"]
  ) {
    const flags = parsePaidFlags(
      ["--run", "--confirm-paid", "--max-calls=84", "--budget-usd=17"].filter(
        (a) => a !== drop,
      ),
    );
    assert(paidGuardError(flags, 84, 10)?.startsWith("拒絕"), drop);
  }
  assert(paidGuardError(ok, 85, 10)?.startsWith("拒絕"));
  assert(paidGuardError(ok, 84, 17.5)?.startsWith("拒絕"));
});

Deno.test("arm C rewrites thinking, effort and max_tokens; A and B go out untouched", () => {
  const body = {
    model: "claude-sonnet-5-5",
    max_tokens: 6500,
    thinking: { type: "between_tools" },
    output_config: { effort: "medium" },
  };
  assertEquals(applyArmOverride(body, ARMS.A), body);
  assertEquals(applyArmOverride(body, ARMS.B), body);
  assertEquals(applyArmOverride(body, ARMS.C), {
    model: "claude-sonnet-5-5",
    max_tokens: 10500,
    thinking: { type: "adaptive", display: "omitted" },
    output_config: { effort: "low" },
  });
});

Deno.test("SSE observer records served model, usage, refusal category and cost", () => {
  const call = newProviderCall({
    model: "claude-sonnet-5-5",
    max_tokens: 6500,
  });
  applySseEvent(call, {
    type: "message_start",
    message: {
      model: "claude-sonnet-5-5",
      usage: {
        input_tokens: 100,
        output_tokens: 1,
        cache_creation_input_tokens: 30_000,
        cache_read_input_tokens: 0,
      },
    },
  });
  applySseEvent(call, {
    type: "message_delta",
    delta: {
      stop_reason: "refusal",
      stop_details: { type: "refusal", category: "general_harms" },
    },
    usage: { output_tokens: 40 },
  });
  assertEquals(call.servedModel, "claude-sonnet-5-5");
  assertEquals(call.stopReason, "refusal");
  assertEquals(call.stopDetails?.category, "general_harms");
  assertEquals(call.usage.output_tokens, 40);
  assertEquals(call.usage.cache_creation_input_tokens, 30_000);
  // 100×$2＋30k×$2.50＋40×$10 ＝ $0.0756。
  assertEquals(Number(call.costUsd.toFixed(4)), 0.0756);
});

function record(
  arm: "A" | "B",
  caseId: string,
  latencyMs: number,
  stopReason: string,
  category?: string,
): CallRecord {
  const pc = newProviderCall({ model: ARMS[arm].model });
  pc.httpStatus = 200;
  pc.stopReason = stopReason;
  pc.stopDetails = category ? { category } : null;
  pc.usage.output_tokens = 1000;
  pc.costUsd = 0.1;
  return {
    arm,
    caseId,
    rep: 1,
    model: ARMS[arm].model,
    latencyMs,
    costUsd: 0.1,
    providerCalls: [pc],
    result: {
      name: `${caseId}#1`,
      status: 200,
      elapsedMs: latencyMs,
      eventTypes: ["analysis.decision", "analysis.done"],
      decision: { messageDecision: "acknowledge_and_stop" },
      replyOptions: [],
      telemetry: { usage: { output_tokens: 1000 } },
      clientText:
        `{"type":"analysis.decision","messageDecision":"acknowledge_and_stop","closingMessage":"好啊 ${arm}"}\n`,
    },
  };
}

Deno.test("summary counts max_tokens, refusals by category, percentiles and evaluate passes per arm", () => {
  const rs = [
    record("A", "defer_vague_busy", 10_000, "end_turn"),
    record("A", "soft_reject_after_invite", 30_000, "max_tokens"),
    record("B", "defer_vague_busy", 20_000, "refusal", "general_harms"),
    record("B", "soft_reject_after_invite", 40_000, "end_turn"),
  ];
  const [a, b] = summarizeArms(rs);
  assertEquals([a.arm, a.maxTokens, a.refusals, a.evalPassed], ["A", 1, 0, 2]);
  assertEquals(b.refusalCategories, { general_harms: 1 });
  assertEquals([b.p50Ms, b.p95Ms], [20_000, 40_000]);
  assertEquals(b.costUsd, 0.2);
  assertEquals(percentile([], 50), null);
});

Deno.test("blind sheet is seeded, hides the arm and maps 甲／乙 back in the reveal", () => {
  const rs = IDS.flatMap((
    id,
  ) => [record("A", id, 1, "end_turn"), record("B", id, 1, "end_turn")]);
  const first = buildBlindSheet(rs)!;
  const again = buildBlindSheet(rs)!;
  assertEquals(first, again);
  // deno-lint-ignore no-explicit-any
  const cases = (first.reveal as any).cases as {
    caseId: string;
    甲: string;
    乙: string;
  }[];
  assertEquals(cases.length, 10);
  assertEquals(new Set(cases.map((c) => c.caseId)).size, 10);
  assert(cases.every((c) => [c.甲, c.乙].sort().join() === "A,B"));
  assert(!first.markdown.includes("claude-"));
  // 收尾句帶臂名只是測試標記：第一題的甲要對到 reveal。
  assert(first.markdown.includes(`收尾句：好啊 ${cases[0].甲}`));
});
