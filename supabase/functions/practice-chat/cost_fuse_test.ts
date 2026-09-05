// 成本保險絲的純函式與 DB client 自測（零網路、零真 DB）。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  COST_FUSE_RPC,
  COST_FUSE_TABLE,
  type CostFuseSupabaseClient,
  parseCostFuseBudget,
  readSpentUsdToday,
  recordChatCost,
  shouldDegrade,
  utcDay,
} from "./cost_fuse.ts";

// ── parseCostFuseBudget ───────────────────────────────────────────────────
Deno.test("parseCostFuseBudget：未設／空白／非正數／非數字一律 null（＝保險絲關）", () => {
  for (
    const raw of [
      undefined,
      "",
      "   ",
      "0",
      "0.0",
      "-1",
      "-0.5",
      "abc",
      "NaN",
      "1abc",
      "1,5",
      "Infinity",
      "-Infinity",
    ]
  ) {
    assertEquals(
      parseCostFuseBudget(raw),
      null,
      `${JSON.stringify(raw)} 必須解析成關閉`,
    );
  }
});

Deno.test("parseCostFuseBudget：正數才開，前後空白容忍", () => {
  assertEquals(parseCostFuseBudget("0.0001"), 0.0001);
  assertEquals(parseCostFuseBudget("5"), 5);
  assertEquals(parseCostFuseBudget(" 12.5 "), 12.5);
  assertEquals(parseCostFuseBudget("1e2"), 100);
});

// ── shouldDegrade ─────────────────────────────────────────────────────────
Deno.test("shouldDegrade：到達門檻就算燒斷（>=，不是 >）", () => {
  assertEquals(shouldDegrade(0, 1), false);
  assertEquals(shouldDegrade(0.9999, 1), false);
  assertEquals(shouldDegrade(1, 1), true);
  assertEquals(shouldDegrade(2, 1), true);
});

// ── utcDay ────────────────────────────────────────────────────────────────
Deno.test("utcDay：UTC 日期（不吃本機時區）", () => {
  assertEquals(utcDay(new Date("2026-09-05T23:59:59Z")), "2026-09-05");
  assertEquals(utcDay(new Date("2026-09-06T00:00:00Z")), "2026-09-06");
});

// ── fake client ───────────────────────────────────────────────────────────
interface FakeCalls {
  selects: Array<{ table: string; columns: string; day: unknown }>;
  rpcs: Array<{ fn: string; params: Record<string, unknown> }>;
}

function fakeClient(opts: {
  row?: Record<string, unknown> | null;
  selectError?: string;
  rpcData?: unknown;
  rpcError?: string;
  selectThrows?: boolean;
  rpcThrows?: boolean;
} = {}): { client: CostFuseSupabaseClient; calls: FakeCalls } {
  const calls: FakeCalls = { selects: [], rpcs: [] };
  const client: CostFuseSupabaseClient = {
    from(table: string) {
      return {
        select(columns: string) {
          let day: unknown;
          const builder = {
            eq(_column: string, value: unknown) {
              day = value;
              return builder;
            },
            maybeSingle() {
              calls.selects.push({ table, columns, day });
              if (opts.selectThrows) throw new Error("boom");
              return Promise.resolve(
                opts.selectError
                  ? { data: null, error: { message: opts.selectError } }
                  : { data: opts.row ?? null, error: null },
              );
            },
          };
          return builder;
        },
      };
    },
    rpc(fn: string, params: Record<string, unknown>) {
      calls.rpcs.push({ fn, params });
      if (opts.rpcThrows) throw new Error("boom");
      return Promise.resolve(
        opts.rpcError
          ? { data: null, error: { message: opts.rpcError } }
          : { data: opts.rpcData ?? null, error: null },
      );
    },
  };
  return { client, calls };
}

/** 這一輪的 console.warn 行（保險絲失敗一律只 warn，不 throw）。 */
async function warnsOf(fn: () => Promise<unknown>): Promise<string[]> {
  const lines: string[] = [];
  const original = console.warn;
  console.warn = (...args: unknown[]) =>
    lines.push(args.map((a) => String(a)).join(" "));
  try {
    await fn();
  } finally {
    console.warn = original;
  }
  return lines;
}

// ── readSpentUsdToday ─────────────────────────────────────────────────────
Deno.test("readSpentUsdToday：沒有列＝今天還沒花錢（0）", async () => {
  const { client, calls } = fakeClient({ row: null });
  assertEquals(await readSpentUsdToday(client, "2026-09-05"), 0);
  assertEquals(calls.selects, [{
    table: COST_FUSE_TABLE,
    columns: "spent_usd",
    day: "2026-09-05",
  }]);
});

Deno.test("readSpentUsdToday：numeric 回字串也要吃得下", async () => {
  const { client } = fakeClient({ row: { spent_usd: "1.25" } });
  assertEquals(await readSpentUsdToday(client, "2026-09-05"), 1.25);
});

Deno.test("readSpentUsdToday：DB 錯誤／丟例外／髒值一律 null（fail-open 由呼叫端決定）", async () => {
  for (
    const opts of [
      { selectError: "boom" },
      { selectThrows: true },
      { row: { spent_usd: "not-a-number" } },
      { row: { spent_usd: null } },
    ]
  ) {
    const { client } = fakeClient(opts);
    const warns = await warnsOf(async () => {
      assertEquals(
        await readSpentUsdToday(client, "2026-09-05"),
        null,
        JSON.stringify(opts),
      );
    });
    assertEquals(warns.length, 1, `${JSON.stringify(opts)} 必須只 warn 一行`);
    assert(warns[0].includes("practice_chat_cost_fuse_read_failed"));
  }
});

// ── recordChatCost ────────────────────────────────────────────────────────
const USAGE = {
  inputTokens: 1_000_000,
  outputTokens: 0,
  cacheReadInputTokens: 0,
  cacheCreationInputTokens: 0,
};

Deno.test("recordChatCost：用 Haiku 4.5 官方牌價估價，累加後回傳前後值", async () => {
  // 1M input token × $1／M ＝ $1。
  const { client, calls } = fakeClient({ rpcData: 3 });
  assertEquals(await recordChatCost(client, "2026-09-05", USAGE), {
    usd: 1,
    before: 2,
    after: 3,
  });
  assertEquals(calls.rpcs, [{
    fn: COST_FUSE_RPC,
    params: { p_day: "2026-09-05", p_usd: 1 },
  }]);
});

Deno.test("recordChatCost：估算金額為 0 時完全不打 RPC", async () => {
  const { client, calls } = fakeClient({ rpcData: 1 });
  assertEquals(
    await recordChatCost(client, "2026-09-05", {
      inputTokens: 0,
      outputTokens: 0,
      cacheReadInputTokens: 0,
      cacheCreationInputTokens: 0,
    }),
    null,
  );
  assertEquals(calls.rpcs, []);
});

Deno.test("recordChatCost：DB 錯誤／丟例外／髒回傳一律 null ＋ 一行 warn", async () => {
  for (
    const opts of [
      { rpcError: "boom" },
      { rpcThrows: true },
      { rpcData: "not-a-number" },
      { rpcData: null },
    ]
  ) {
    const { client } = fakeClient(opts);
    const warns = await warnsOf(async () => {
      assertEquals(
        await recordChatCost(client, "2026-09-05", USAGE),
        null,
        JSON.stringify(opts),
      );
    });
    assertEquals(warns.length, 1, `${JSON.stringify(opts)} 必須只 warn 一行`);
    assert(warns[0].includes("practice_chat_cost_fuse_write_failed"));
  }
});

Deno.test("recordChatCost：RPC 回傳陣列或單欄物件（PostgREST 兩種形狀）都吃得下", async () => {
  for (const data of [[3], [{ increment_practice_chat_daily_cost: 3 }], 3]) {
    const { client } = fakeClient({ rpcData: data });
    assertEquals(
      await recordChatCost(client, "2026-09-05", USAGE),
      { usd: 1, before: 2, after: 3 },
      JSON.stringify(data),
    );
  }
});
