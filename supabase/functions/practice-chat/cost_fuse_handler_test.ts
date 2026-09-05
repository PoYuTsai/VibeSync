// Phase 5 WP2 成本保險絲的 handler 接線（`PRACTICE_COST_FUSE_DAILY_USD`）。
//
// ── 契約 ──────────────────────────────────────────────────────────────────
// 旗標空／未設／非正數：保險絲完全不啟動，**零 DB 讀寫**（連 select 都不發），
// 四面逐位元組等於接線前（那一半由 `agency_flag_off_equivalence_test.ts` 的
// harness 守，這支只驗「RPC／select 零呼叫」這個可數的事實）。
// 旗標是正數：燒斷那一輪強制 `deepseek`，`practice_chat_succeeded` 多一個
// `costFuseDegraded: true`（只在 routing `mixed` 的那組 key 裡），
// `practice_chat_cost_fuse_blown` 一天恰好一筆，DB 讀寫失敗一律 fail-open。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  chatBody,
  type FakeOptions,
  hintBody,
  ledger,
  makeFake,
  makeRequest,
} from "./handler_test_fake.ts";
import { CLAUDE_SONNET_MODEL } from "./claude.ts";
import { COST_FUSE_RPC, COST_FUSE_TABLE } from "./cost_fuse.ts";

const FUSE_ENV = "PRACTICE_COST_FUSE_DAILY_USD";
const ROUTING_ENV = "PRACTICE_CHAT_MODEL_ROUTING";
const AGENCY_ENV = "PRACTICE_CONVERSATIONAL_AGENCY_ENABLED";

/** 她會介入的典型形狀（與 routing 測試同一段 fixture → 這一輪走 Haiku）。 */
const FRAGMENT_TURNS = [
  { role: "user", text: "東東" },
  { role: "ai", text: "東東是誰" },
  { role: "user", text: "阿布達比" },
];
const CLASSIFIER_JSON =
  `{"connection":"caught","impact":"medium","testHandling":"none","boundary":"safe","hintAlignment":"none"}`;

/**
 * fake 的 Claude 每次固定回報 input 120／cacheRead 80／output 15，
 * 換算 Haiku 4.5 官方牌價（$1／$5／$0.1 每 M）＝ $0.000203／輪。
 * 預算取 $0.0001 就是計畫 §4 WP2 驗收寫的那個值：第一輪就會跨過門檻。
 */
const USD_PER_TURN = (120 * 1 + 15 * 5 + 80 * 0.1) / 1_000_000;
const BUDGET = "0.0001";

/** 同一個 fake 連打 N 輪（保險絲的當日累計是 fake 內部狀態，跨輪保留）。 */
async function runTurns(
  turnCount: number,
  options: FakeOptions = {},
  // `null` ＝ 這個環境變數整個不設（顯式傳 `undefined` 會撿到預設值）。
  fuse: string | null = BUDGET,
) {
  const fake = makeFake({
    ledger: ledger({ practice_mode: "beginner" }),
    // 每一輪：chat 生成（Claude 那輪不會用到）＋ 生成後的分類器。
    deepSeekReplies: Array.from(
      { length: turnCount * 2 },
      (_, i) => i % 2 === 0 ? "好啊" : CLASSIFIER_JSON,
    ),
    claudeReplies: Array.from({ length: turnCount }, () => "嗯？你先講東東"),
    ...options,
    env: {
      [ROUTING_ENV]: "mixed",
      [AGENCY_ENV]: "true",
      ...(fuse === null ? {} : { [FUSE_ENV]: fuse }),
      ...options.env,
    },
  });
  const turns: Array<{ succeeded: Record<string, unknown>; lines: string[] }> =
    [];
  const originalLog = console.log;
  const originalWarn = console.warn;
  for (let i = 0; i < turnCount; i++) {
    const lines: string[] = [];
    const capture = (...args: unknown[]) =>
      lines.push(args.map((a) => String(a)).join(" "));
    try {
      console.log = capture;
      console.warn = capture;
      await fake.handler(
        makeRequest(
          chatBody({ practiceMode: "beginner", turns: FRAGMENT_TURNS }),
        ),
      );
      await Promise.allSettled(fake.state.backgroundTasks);
    } finally {
      console.log = originalLog;
      console.warn = originalWarn;
    }
    const succeededLine = lines.find((l) =>
      l.includes('"event":"practice_chat_succeeded"')
    );
    assert(succeededLine, `第 ${i + 1} 輪沒有印出 practice_chat_succeeded`);
    turns.push({
      succeeded: JSON.parse(succeededLine) as Record<string, unknown>,
      lines,
    });
  }
  return { fake, turns };
}

function blownLines(lines: string[]) {
  return lines.filter((l) =>
    l.includes('"event":"practice_chat_cost_fuse_blown"')
  );
}

Deno.test("旗標留空／未設／非正數：零 DB 讀寫（不 select、不打累加 RPC）", async () => {
  for (const fuse of [null, "", "   ", "0", "-1", "abc"]) {
    const { fake, turns } = await runTurns(1, {}, fuse);
    assertEquals(
      fake.state.selects.filter((s) => s.table === COST_FUSE_TABLE),
      [],
      `fuse=${JSON.stringify(fuse)}：不得讀保險絲表`,
    );
    assertEquals(
      fake.state.rpcCalls.filter((r) => r.fn === COST_FUSE_RPC),
      [],
      `fuse=${JSON.stringify(fuse)}：不得打累加 RPC`,
    );
    // 保險絲沒啟動 → 這一輪照常走 Haiku，也沒有 costFuseDegraded key。
    assertEquals(turns[0].succeeded.chatModel, "haiku");
    assertEquals(
      Object.hasOwn(turns[0].succeeded, "costFuseDegraded"),
      false,
    );
    assertEquals(blownLines(turns[0].lines).length, 0);
  }
});

Deno.test("routing 未開 mixed：保險絲照樣啟動（Codex R2 P1），只是降級動作沒有作用", async () => {
  // 路由關著時 chat 本來就走 DeepSeek，所以「降級」是 no-op；但記帳不能跟著
  // 關掉——提示／檢討的 Sonnet 錢跟路由旗標無關，照樣在燒。
  const { fake, turns } = await runTurns(1, { env: { [ROUTING_ENV]: "off" } });
  assertEquals(
    Object.hasOwn(turns[0].succeeded, "chatModel"),
    false,
    "routing 關著時整組 routing key 不存在",
  );
  // 讀今日累計仍然發生（保險絲有開）。
  assertEquals(
    fake.state.selects.filter((s) => s.table === COST_FUSE_TABLE).length,
    1,
  );
  // 這一輪 chat 沒打 Claude（路由關著）→ 沒有花費 → 不打累加 RPC。
  assertEquals(fake.state.claudeCalls.length, 0);
  assertEquals(fake.state.rpcCalls.filter((r) => r.fn === COST_FUSE_RPC), []);
});

Deno.test("預算 0.0001：第一輪照走 Haiku 並記帳，第二輪起強制 deepseek ＋ costFuseDegraded", async () => {
  const { fake, turns } = await runTurns(3);

  // 第一輪：進來時累計是 0 → 沒燒斷 → Haiku；結束時累加一輪金額並跨過門檻。
  assertEquals(turns[0].succeeded.chatModel, "haiku");
  assertEquals(Object.hasOwn(turns[0].succeeded, "costFuseDegraded"), false);

  // 第二、三輪：進來時已超標 → 強制 deepseek ＋ telemetry 有 costFuseDegraded。
  for (const index of [1, 2]) {
    assertEquals(
      turns[index].succeeded.chatModel,
      "deepseek",
      `第 ${index + 1} 輪必須被降級`,
    );
    assertEquals(turns[index].succeeded.costFuseDegraded, true);
    // 降級是降級不是報錯：這一輪仍然成功，也仍然只有一次 chat 生成。
    assertEquals(
      (turns[index].succeeded.chatModelCalls as Record<string, number>).haiku,
      0,
    );
  }

  // Claude 只有第一輪打過一次；之後不再付錢。
  assertEquals(fake.state.claudeCalls.length, 1);
  // 累加 RPC 只在真的有 Claude usage 的那一輪打（後兩輪沒有 usage → 不打）。
  const increments = fake.state.rpcCalls.filter((r) => r.fn === COST_FUSE_RPC);
  assertEquals(increments.length, 1);
  assertEquals(increments[0].params.p_usd, USD_PER_TURN);
});

Deno.test("practice_chat_cost_fuse_blown 一天恰好一筆（跨過門檻的那一次才寫）", async () => {
  const { turns } = await runTurns(3);
  assertEquals(blownLines(turns[0].lines).length, 1, "跨過門檻的那一輪要寫");
  assertEquals(blownLines(turns[1].lines).length, 0, "已經燒斷的輪次不再寫");
  assertEquals(blownLines(turns[2].lines).length, 0);

  const blown = JSON.parse(blownLines(turns[0].lines)[0]) as Record<
    string,
    unknown
  >;
  assertEquals(Object.keys(blown).sort(), [
    "budgetUsd",
    "day",
    "event",
    "level",
    "spentUsd",
  ]);
  assertEquals(blown.level, "warn");
  assertEquals(blown.budgetUsd, Number(BUDGET));
  assertEquals(blown.spentUsd, USD_PER_TURN);
  assertEquals(typeof blown.day, "string");
  // payload 只有數字與日期，沒有逐字稿／使用者／金鑰。
  for (const secret of ["claude-key", "deepseek-key", "阿布達比", "user-1"]) {
    assert(
      !blownLines(turns[0].lines)[0].includes(secret),
      `blown payload 不得含 ${secret}`,
    );
  }
});

Deno.test("預算很大時永遠不燒斷：照走 Haiku、不寫 blown、但仍然記帳", async () => {
  const { fake, turns } = await runTurns(2, {}, "999");
  for (const turn of turns) {
    assertEquals(turn.succeeded.chatModel, "haiku");
    assertEquals(Object.hasOwn(turn.succeeded, "costFuseDegraded"), false);
    assertEquals(blownLines(turn.lines).length, 0);
  }
  assertEquals(
    fake.state.rpcCalls.filter((r) => r.fn === COST_FUSE_RPC).length,
    2,
  );
});

Deno.test("讀今日累計失敗＝fail-open：照常走 Haiku、對話不失敗、只多一行 warn", async () => {
  const { turns } = await runTurns(2, { dailyCostReadError: "db down" });
  for (const turn of turns) {
    assertEquals(turn.succeeded.chatModel, "haiku");
    assertEquals(Object.hasOwn(turn.succeeded, "costFuseDegraded"), false);
    assertEquals(
      turn.lines.filter((l) =>
        l.includes('"event":"practice_chat_cost_fuse_read_failed"')
      ).length,
      1,
    );
  }
});

Deno.test("累加失敗＝fail-open：對話不失敗、不寫 blown、只多一行 warn", async () => {
  const { turns } = await runTurns(2, { dailyCostWriteError: "db down" });
  for (const turn of turns) {
    assertEquals(turn.succeeded.chatModel, "haiku");
    assertEquals(blownLines(turn.lines).length, 0);
    assertEquals(
      turn.lines.filter((l) =>
        l.includes('"event":"practice_chat_cost_fuse_write_failed"')
      ).length,
      1,
    );
  }
});

Deno.test("起始累計就已超標：第一輪就被降級（重啟／跨實例都吃同一份 DB 狀態）", async () => {
  const { turns } = await runTurns(1, { dailyCostUsd: 5 });
  assertEquals(turns[0].succeeded.chatModel, "deepseek");
  assertEquals(turns[0].succeeded.costFuseDegraded, true);
  // 已經燒斷過的那一天不會再寫第二筆 blown。
  assertEquals(blownLines(turns[0].lines).length, 0);
});

Deno.test("降級後 DeepSeek 也失敗：失敗事件同樣帶 costFuseDegraded（Codex R1 P2）", async () => {
  // 起始累計就超標 → 這一輪一定被扳回 DeepSeek；兩發 DeepSeek 都丟錯 →
  // 整輪失敗走 practice_chat_generation_failed，沒有 practice_chat_succeeded。
  const fake = makeFake({
    ledger: ledger({ practice_mode: "beginner" }),
    dailyCostUsd: 5,
    deepSeekReplies: [
      new Error("deepseek_timeout"),
      new Error("deepseek_timeout"),
    ],
    claudeReplies: ["不該被用到"],
    env: {
      [ROUTING_ENV]: "mixed",
      [AGENCY_ENV]: "true",
      [FUSE_ENV]: BUDGET,
    },
  });
  const lines: string[] = [];
  const originalLog = console.log;
  const originalWarn = console.warn;
  const capture = (...args: unknown[]) =>
    lines.push(args.map((a) => String(a)).join(" "));
  let response: Response;
  try {
    console.log = capture;
    console.warn = capture;
    response = await fake.handler(
      makeRequest(
        chatBody({ practiceMode: "beginner", turns: FRAGMENT_TURNS }),
      ),
    );
    await Promise.allSettled(fake.state.backgroundTasks);
  } finally {
    console.log = originalLog;
    console.warn = originalWarn;
  }
  assertEquals(response.status, 500);
  assertEquals(
    lines.filter((l) => l.includes('"event":"practice_chat_succeeded"')),
    [],
  );
  const failedLine = lines.find((l) =>
    l.includes('"event":"practice_chat_generation_failed"')
  );
  assert(failedLine, "沒有印出 practice_chat_generation_failed");
  const failed = JSON.parse(failedLine) as Record<string, unknown>;
  assertEquals(failed.costFuseDegraded, true);
  // 真的被降級了：Claude 一次都沒打。
  assertEquals(fake.state.claudeCalls.length, 0);
});

// ── Codex R1 P1：提示／檢討的 Anthropic 花費也要進當日累計 ────────────────
/** hint／debrief 走 SIDE_TURNS（最後一則必須是她）。 */
const SIDE_TURNS = [
  ...FRAGMENT_TURNS,
  { role: "ai", text: "阿布達比？那是哪裡" },
];

function validHint(): string {
  return JSON.stringify({
    warmUp: "阿布達比是突然想去，還是最近在看機票？",
    steady: "阿布達比收到，我先猜妳最近在看機票，猜錯妳糾正我。",
    coaching: "她問了阿布達比是什麼；先二選一接住她的疑問，再沿她的答案分享。",
  });
}

/**
 * fake 的 Claude 每次固定回報 input 120／cacheRead 80／output 15。
 * Sonnet 5 官方牌價（$2／$10／$0.2 每 M）＝ $0.000406／發，是 Haiku 那一發的
 * 兩倍——所以一次提示就足以把 $0.0001 的預算燒穿。
 */
const SONNET_USD_PER_CALL = (120 * 2 + 15 * 10 + 80 * 0.2) / 1_000_000;

Deno.test("提示的 Sonnet 花費進當日累計：一次 hint 就燒穿預算，下一輪 chat 直接 deepseek", async () => {
  const fake = makeFake({
    // 這一場必須已經開始，否則 hint 會停在配額層的 403。
    ledger: ledger({
      practice_mode: "beginner",
      ai_count: 1,
      charged: true,
      temperature_score: 30,
      familiarity_score: 0,
    }),
    deepSeekReplies: ["好啊", CLASSIFIER_JSON],
    claudeReplies: [validHint(), "嗯？你先講東東"],
    env: {
      [ROUTING_ENV]: "mixed",
      [AGENCY_ENV]: "true",
      [FUSE_ENV]: BUDGET,
    },
  });

  const runOne = async (body: unknown) => {
    const lines: string[] = [];
    const originalLog = console.log;
    const originalWarn = console.warn;
    const capture = (...args: unknown[]) =>
      lines.push(args.map((a) => String(a)).join(" "));
    let response: Response;
    try {
      console.log = capture;
      console.warn = capture;
      response = await fake.handler(makeRequest(body));
      await Promise.allSettled(fake.state.backgroundTasks);
    } finally {
      console.log = originalLog;
      console.warn = originalWarn;
    }
    return { response, lines };
  };

  // 1) 提示：照常走 Sonnet（保險絲不降級提示），花費被記進當日累計。
  const hint = await runOne(
    hintBody({ practiceMode: "beginner", turns: SIDE_TURNS }),
  );
  assertEquals(hint.response.status, 200);
  assertEquals(fake.state.claudeCalls.length, 1);
  assertEquals(fake.state.claudeCalls[0].model, CLAUDE_SONNET_MODEL);
  const increments = fake.state.rpcCalls.filter((r) => r.fn === COST_FUSE_RPC);
  assertEquals(increments.length, 1);
  assertEquals(increments[0].params.p_usd, SONNET_USD_PER_CALL);
  // 跨過門檻的那一次寫一筆 blown。
  assertEquals(blownLines(hint.lines).length, 1);
  assertEquals(
    (JSON.parse(blownLines(hint.lines)[0]) as Record<string, unknown>).spentUsd,
    SONNET_USD_PER_CALL,
  );

  // 2) 下一輪 chat：被提示燒掉的錢壓進降級 → 直接 deepseek，Claude 不再被打。
  const chat = await runOne(
    chatBody({ practiceMode: "beginner", turns: FRAGMENT_TURNS }),
  );
  const succeededLine = chat.lines.find((l) =>
    l.includes('"event":"practice_chat_succeeded"')
  );
  assert(succeededLine);
  const succeeded = JSON.parse(succeededLine) as Record<string, unknown>;
  assertEquals(succeeded.chatModel, "deepseek");
  assertEquals(succeeded.costFuseDegraded, true);
  assertEquals(fake.state.claudeCalls.length, 1, "chat 那輪不得再打 Claude");
  // blown 一天一筆：第二輪不再寫。
  assertEquals(blownLines(chat.lines).length, 0);
});

Deno.test("旗標未設：hint 路徑的 callClaude 參數一個 onUsage key 都沒有（single_shot 零改動）", async () => {
  const withoutFuse = makeFake({
    ledger: ledger({
      practice_mode: "beginner",
      ai_count: 1,
      charged: true,
      temperature_score: 30,
      familiarity_score: 0,
    }),
    claudeReplies: [validHint()],
    env: { [ROUTING_ENV]: "mixed", [AGENCY_ENV]: "true" },
  });
  const originalLog = console.log;
  const originalWarn = console.warn;
  try {
    console.log = () => {};
    console.warn = () => {};
    await withoutFuse.handler(
      makeRequest(hintBody({ practiceMode: "beginner", turns: SIDE_TURNS })),
    );
    await Promise.allSettled(withoutFuse.state.backgroundTasks);
  } finally {
    console.log = originalLog;
    console.warn = originalWarn;
  }
  assertEquals(withoutFuse.state.claudeCalls.length, 1);
  assertEquals(
    Object.hasOwn(withoutFuse.state.claudeCalls[0], "onUsage"),
    false,
    "旗標未設時 single_shot 不得把 onUsage 傳給 callClaude",
  );
  assertEquals(
    withoutFuse.state.rpcCalls.filter((r) => r.fn === COST_FUSE_RPC),
    [],
  );
});

// ── Codex R2 P1：DB 死線 ──────────────────────────────────────────────────
Deno.test("讀今日累計永不回應：撞死線後 fail-open，對話照常 200 ＋ telemetry 記 costFuseTimeout", async () => {
  const { turns } = await runTurns(1, { dailyCostReadNeverCompletes: true });
  // 保險絲逾時不能讓對話變慢到失敗，也不能改變模型選擇。
  assertEquals(turns[0].succeeded.chatModel, "haiku");
  assertEquals(Object.hasOwn(turns[0].succeeded, "costFuseDegraded"), false);
  assertEquals(turns[0].succeeded.costFuseTimeout, "read");
  assertEquals(
    turns[0].lines.filter((l) =>
      l.includes('"event":"practice_chat_cost_fuse_read_failed"')
    ).length,
    1,
  );
  assert(
    turns[0].lines.some((l) => l.includes("cost_fuse_timeout")),
    "warn 要說清楚是逾時不是一般 DB 錯誤",
  );
});

Deno.test("累加永不回應：撞死線後 fail-open，對話照常 200 ＋ telemetry 記 costFuseTimeout", async () => {
  const { turns } = await runTurns(1, { dailyCostWriteNeverCompletes: true });
  assertEquals(turns[0].succeeded.chatModel, "haiku");
  assertEquals(turns[0].succeeded.costFuseTimeout, "write");
  assertEquals(blownLines(turns[0].lines).length, 0, "寫沒成功就不寫 blown");
  assertEquals(
    turns[0].lines.filter((l) =>
      l.includes('"event":"practice_chat_cost_fuse_write_failed"')
    ).length,
    1,
  );
});

Deno.test("沒逾時的一般路徑不得出現 costFuseTimeout key", async () => {
  const { turns } = await runTurns(1, {}, "999");
  assertEquals(Object.hasOwn(turns[0].succeeded, "costFuseTimeout"), false);
});

Deno.test("routing off 時 hint 照樣累加；同一天切成 mixed，下一輪 chat 直接 deepseek（Codex R2 P1）", async () => {
  const hintLedger = ledger({
    practice_mode: "beginner",
    ai_count: 1,
    charged: true,
    temperature_score: 30,
    familiarity_score: 0,
  });
  const quiet = async (fake: ReturnType<typeof makeFake>, body: unknown) => {
    const lines: string[] = [];
    const originalLog = console.log;
    const originalWarn = console.warn;
    const capture = (...args: unknown[]) =>
      lines.push(args.map((a) => String(a)).join(" "));
    let response: Response;
    try {
      console.log = capture;
      console.warn = capture;
      response = await fake.handler(makeRequest(body));
      await Promise.allSettled(fake.state.backgroundTasks);
    } finally {
      console.log = originalLog;
      console.warn = originalWarn;
    }
    return { response, lines };
  };

  // 1) 路由**關著**跑一次提示：Sonnet 的錢照樣記進當日累計。
  const routingOff = makeFake({
    ledger: hintLedger,
    claudeReplies: [validHint()],
    env: {
      [ROUTING_ENV]: "off",
      [AGENCY_ENV]: "true",
      [FUSE_ENV]: BUDGET,
    },
  });
  const hint = await quiet(
    routingOff,
    hintBody({ practiceMode: "beginner", turns: SIDE_TURNS }),
  );
  assertEquals(hint.response.status, 200);
  const increments = routingOff.state.rpcCalls.filter((r) =>
    r.fn === COST_FUSE_RPC
  );
  assertEquals(increments.length, 1, "routing off 也要累加");
  assertEquals(increments[0].params.p_usd, SONNET_USD_PER_CALL);

  // 2) 同一天把路由切成 mixed（新的 Edge 實例，但當日累計來自 DB）：
  //    下一輪 chat 立刻被降級。
  const routingMixed = makeFake({
    ledger: ledger({ practice_mode: "beginner" }),
    dailyCostUsd: SONNET_USD_PER_CALL,
    deepSeekReplies: ["好啊", CLASSIFIER_JSON],
    claudeReplies: ["不該被用到"],
    env: {
      [ROUTING_ENV]: "mixed",
      [AGENCY_ENV]: "true",
      [FUSE_ENV]: BUDGET,
    },
  });
  const chat = await quiet(
    routingMixed,
    chatBody({ practiceMode: "beginner", turns: FRAGMENT_TURNS }),
  );
  const succeededLine = chat.lines.find((l) =>
    l.includes('"event":"practice_chat_succeeded"')
  );
  assert(succeededLine);
  const succeeded = JSON.parse(succeededLine) as Record<string, unknown>;
  assertEquals(succeeded.chatModel, "deepseek");
  assertEquals(succeeded.costFuseDegraded, true);
  assertEquals(routingMixed.state.claudeCalls.length, 0);
});

