// 額度不夠時的自傷關心（Eric 2026-10-18），從正式入口 createAnalyzeChatHandler 走：她的
// 訊息有自殺、自殘、割腕、輕生、不想活任一個字、會走 v3 的一般文字分析，額度不夠也不回
// 429，改給關心訊息與專線；不打模型、不扣額度。沒有這些字、只在他的訊息、走 v2、潤飾或
// 微調，照舊 429（回應內容一字不差）。資料庫與模型都是替身；事件照種類找，期望的數字都
// 從額度與計費常數算。
//
// 串流層在載入時就抓住 fetch：轉接器必須是第一個 import（見 test_fetch_dispatcher.ts）。
import "../test_fetch_dispatcher.ts";
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  buildQuotaExceededPayload,
  TIER_DAILY_LIMITS,
  TIER_MONTHLY_LIMITS,
} from "../../_shared/quota.ts";
import { bandForBillableChars, countPayloadChars } from "../billing.ts";
import { OPTIMIZE_MESSAGE_COST } from "../optimize_message_billing.ts";
import { CARE_MESSAGE } from "./wire.ts";

const FAKE_SUPABASE_URL = "http://supabase.test";
const USER_ID = "11111111-2222-4333-8444-555555555555";
const FREE_MONTHLY = TIER_MONTHLY_LIMITS.free;
const FREE_DAILY = TIER_DAILY_LIMITS.free;

// 入口模組載入時會把這些 env 讀成常數：STREAM_ANALYZE_ENABLED 正式環境是 true；RevenueCat
// 金鑰不給，額度不夠時的對帳就不連網。import 完把 env 還原，不汙染其他測試。
const IMPORT_ENV: Record<string, string | undefined> = {
  SUPABASE_URL: FAKE_SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY: "fake-service-key",
  CLAUDE_API_KEY: "fake-claude-key",
  STREAM_ANALYZE_ENABLED: "true",
  REVENUECAT_IOS_API_KEY: undefined,
  TEST_MODE: undefined,
};
function swapEnv(values: Record<string, string | undefined>) {
  const saved = Object.fromEntries(
    Object.keys(values).map((k) => [k, Deno.env.get(k)]),
  );
  for (const [k, v] of Object.entries(values)) {
    if (v === undefined) Deno.env.delete(k);
    else Deno.env.set(k, v);
  }
  return () => {
    for (const [k, v] of Object.entries(saved)) {
      if (v === undefined) Deno.env.delete(k);
      else Deno.env.set(k, v);
    }
  };
}
const restoreImportEnv = swapEnv(IMPORT_ENV);
const { createAnalyzeChatHandler } = await import("../index.ts");
restoreImportEnv();

type Msg = { content: string; isFromMe: boolean; quotedReplyPreview?: string };

interface Fake {
  sub: { tier: string; monthlyUsed: number; dailyUsed: number };
  rateLimited?: boolean;
  rpc: { fn: string; args: Record<string, unknown> }[];
  inserts: string[];
  run: Record<string, unknown> | null;
}

/// 讀局面替身回的標記（綠燈、模型沒標自傷）：關心只會來自程式關鍵字。
const READ_TAGS = {
  light: "green",
  herMove: "生活",
  herMoodBad: false,
  drunkOrLateNight: false,
  inviteReadiness: "沒機會",
  cancelHasAlternative: false,
  retreating: false,
  declinedOrBoundary: false,
  explicitRejection: false,
  blocked: false,
  risk: false,
  selfHarmSignal: false,
  minorSignal: false,
  needsHisFacts: false,
  identityQuestion: false,
  hisStatedFacts: [],
  hasHisVoiceSample: false,
  replyWillingness: "high",
  worthyBallCount: 1,
  herTurnsPerfunctory: [],
  matchedEntries: [],
  readForUser: "她在分享日常。",
  waitFor: "",
};

function fakeSupabase(f: Fake) {
  const nowIso = new Date().toISOString();
  const today = nowIso.slice(0, 10);
  const query = (
    table: string,
    op: "select" | "insert" | "update",
    values?: Record<string, unknown>,
  ) => {
    const result = () => {
      if (table === "subscriptions" && op === "select") {
        return {
          tier: f.sub.tier,
          monthly_messages_used: f.sub.monthlyUsed,
          daily_messages_used: f.sub.dailyUsed,
          daily_reset_at: nowIso,
          monthly_reset_at: nowIso,
        };
      }
      if (table === "analysis_stream_runs" && op === "insert") {
        f.run = {
          id: "run-quota-care",
          user_id: USER_ID,
          status: "pending",
          selected_style: null,
          decision_kind: null,
          card_task: null,
          recommendation_json: null,
          final_result_json: null,
          charged_at: null,
          last_error_code: null,
          retry_count: 0,
          created_at: nowIso,
          expires_at: new Date(Date.now() + 30 * 60_000).toISOString(),
          ...values,
        };
        return f.run;
      }
      if (table === "analysis_stream_runs" && op === "update" && f.run) {
        f.run = { ...f.run, ...values };
        return f.run;
      }
      if (table === "analysis_stream_runs" && op === "select") return f.run;
      // 微調今天的免費次數已用完：要扣 1 則，才會走到額度預查。
      if (table === "refine_free_allowance") {
        return { day_utc: today, used_count: 9999 };
      }
      return null;
    };
    const q = {
      select: () => q,
      eq: () => q,
      is: () => q,
      gte: () => q,
      maybeSingle: () => Promise.resolve({ data: result(), error: null }),
      single: () => Promise.resolve({ data: result(), error: null }),
    };
    return q;
  };
  return {
    auth: {
      getUser: () =>
        Promise.resolve({
          data: { user: { id: USER_ID, email: "user@example.com" } },
          error: null,
        }),
    },
    from(table: string) {
      return {
        select: () => query(table, "select"),
        insert: (values: Record<string, unknown>) => {
          f.inserts.push(table);
          return query(table, "insert", values);
        },
        update: (values: Record<string, unknown>) =>
          query(table, "update", values),
      };
    },
    rpc(fn: string, args: Record<string, unknown>) {
      f.rpc.push({ fn, args });
      if (fn === "increment_model_usage") {
        return Promise.resolve({
          data: null,
          error: f.rateLimited
            ? { message: "MODEL_RATE_LIMITED_MINUTE" }
            : null,
        });
      }
      if (fn === "charge_stream_analysis_run_v3" && f.run) {
        f.run = {
          ...f.run,
          status: "charged",
          charged_at: nowIso,
          decision_kind: args.p_decision_kind,
          recommendation_json: args.p_recommendation_json,
        };
        return Promise.resolve({ data: f.run, error: null });
      }
      return Promise.resolve({ data: true, error: null });
    },
  };
}

interface Outcome {
  status: number;
  text: string;
  contentType: string;
  fake: Fake;
  modelCalls: number;
  logs: { event: string; metadata: Record<string, unknown> }[];
}

async function analyze(
  body: Record<string, unknown>,
  opts: {
    monthlyUsed?: number;
    dailyUsed?: number;
    guideV3?: string;
    rateLimited?: boolean;
  } = {},
): Promise<Outcome> {
  const fake: Fake = {
    sub: {
      tier: "free",
      monthlyUsed: opts.monthlyUsed ?? 0,
      dailyUsed: opts.dailyUsed ?? 0,
    },
    rateLimited: opts.rateLimited,
    rpc: [],
    inserts: [],
    run: null,
  };
  let modelCalls = 0;
  const logs: Outcome["logs"] = [];
  const restoreEnv = swapEnv({
    ANALYZE_GUIDE_V3: opts.guideV3 ?? "on",
    // 記憶開關開著：證明額度不夠走關心時也不會打。
    ANALYZE_GUIDE_V3_MEMORY: "on",
    MIN_CLIENT_BUILD: undefined,
  });
  const originalFetch = globalThis.fetch;
  globalThis.fetch = ((input: string | URL | Request) => {
    const url = String(input instanceof Request ? input.url : input);
    if (!url.startsWith("https://api.anthropic.com/")) {
      return Promise.reject(new Error(`unexpected fetch: ${url}`));
    }
    modelCalls++;
    return Promise.resolve(
      new Response(
        JSON.stringify({
          id: "msg_fake",
          type: "message",
          role: "assistant",
          model: "claude-sonnet-5-5",
          content: [{ type: "text", text: JSON.stringify(READ_TAGS) }],
          stop_reason: "end_turn",
          usage: { input_tokens: 1, output_tokens: 1 },
        }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      ),
    );
  }) as typeof fetch;
  const quiet = [console.log, console.warn, console.error];
  const capture = (line: unknown, metadata?: unknown) => {
    const event = String(line).split(" ").at(-1) ?? "";
    logs.push({
      event,
      metadata: (metadata ?? {}) as Record<string, unknown>,
    });
  };
  console.log = console.warn = console.error = capture;
  try {
    const handler = createAnalyzeChatHandler({
      createSupabaseClient: () => fakeSupabase(fake) as never,
    });
    const response = await handler(
      new Request("http://localhost/analyze-chat", {
        method: "POST",
        headers: {
          Authorization: "Bearer fake-token",
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
      }),
    );
    // 串流要讀完，流程（含紀錄與 log）才跑完。
    const text = await response.text();
    return {
      status: response.status,
      text,
      contentType: response.headers.get("content-type") ?? "",
      fake,
      modelCalls,
      logs,
    };
  } finally {
    [console.log, console.warn, console.error] = quiet;
    globalThis.fetch = originalFetch;
    restoreEnv();
  }
}

/// 現行 App 的對話分析請求（串流、協定版本 3）。
function chatAnalysis(messages: Msg[], extra: Record<string, unknown> = {}) {
  return {
    responseMode: "stream",
    messages,
    billingProtocolVersion: 3,
    analysisContractVersion: 3,
    ...extra,
  };
}

/// 這段對話第一次分析要扣幾則（照 billing.ts 的分段帶）。
function unitsFor(messages: Msg[]): number {
  const band = bandForBillableChars(countPayloadChars(messages));
  assert(band.band !== "reject");
  return band.units;
}

const HIS = "最近工作還順利嗎？上次你說新主管很難搞";
const HER_SELF_HARM: Msg[] = [
  { content: HIS, isFromMe: true },
  {
    content: "其實壓力大到每天都睡不好，有時候會覺得不想活了，也不知道能跟誰說",
    isFromMe: false,
  },
];
const HER_PLAIN: Msg[] = [
  { content: HIS, isFromMe: true },
  {
    content: "其實壓力大到每天都睡不好，下班只想躺著，也不知道能跟誰說這些事情",
    isFromMe: false,
  },
];
const HIS_SELF_HARM_ONLY: Msg[] = [
  { content: "我最近真的累到覺得不想活了，工作一直出包", isFromMe: true },
  {
    content: "怎麼了？先別這樣想，我們找時間出來吃個飯聊聊好不好",
    isFromMe: false,
  },
];
/// 她引用了他那句話：引用的內容不算她說的（伺服器只掃她自己的訊息本文）。
const HER_QUOTES_HIS: Msg[] = [
  { content: "我最近工作壓力很大，常常加班到半夜才回家", isFromMe: true },
  {
    content: "先好好休息吧，我們週末出來走走，換個心情再說",
    isFromMe: false,
    quotedReplyPreview: "我真的不想活了",
  },
];
/// 只有「想死」：不在那五個字裡（讀局面成功時交給模型），額度不夠照舊 429。
const HER_WANTS_TO_DIE: Msg[] = [
  { content: HIS, isFromMe: true },
  {
    content: "今天熱到想死，冷氣又壞掉，整個人快融化了，晚上只想待在家",
    isFromMe: false,
  },
];
/// 只有未成年字眼：維持現狀，額度不夠照舊 429（Eric 2026-10-18）。
const HER_MINOR: Msg[] = [
  { content: HIS, isFromMe: true },
  {
    content: "我今年才高二啦，每天考試考到好累，晚上還要去補習班上課",
    isFromMe: false,
  },
];

/// 少一則就夠：剩下的比這段對話要扣的少，但還沒用完（不會先被「已用完」那道擋下）。
function projectedShort(messages: Msg[], limit: number): number {
  const units = unitsFor(messages);
  assert(units >= 2, "這段對話要扣 2 則以上，才測得到「剩的不夠但還沒用完」");
  return limit - (units - 1);
}

function events(text: string): Record<string, unknown>[] {
  return text.split("\n").filter(Boolean).map((l) => JSON.parse(l));
}

function byType(evs: Record<string, unknown>[], type: string) {
  return evs.filter((e) => e.type === type);
}

/// 走到關心訊息：串流、只有開始／判讀／完成；不打模型；RPC 只有限流與一筆不扣的紀錄。
function assertQuotaCare(out: Outcome, label: string) {
  assertEquals(out.status, 200, `${label}: status ${out.text}`);
  assert(out.contentType.includes("ndjson"), `${label}: 要是串流`);
  const evs = events(out.text);
  assertEquals(byType(evs, "analysis.started").length, 1, label);
  assertEquals(byType(evs, "analysis.card"), [], label);
  assertEquals(byType(evs, "analysis.error"), [], label);
  const [read] = byType(evs, "analysis.read");
  assertEquals(read.decision, "care", label);
  assertEquals(read.careKind, "self_harm", label);
  assertEquals(read.careMessage, CARE_MESSAGE, label);
  const [done] = byType(evs, "analysis.done");
  const usage = (done.finalResult as Record<string, unknown>).usage as Record<
    string,
    unknown
  >;
  assertEquals(usage.messagesUsed, 0, label);
  assertEquals(usage.shouldChargeQuota, false, label);

  assertEquals(out.modelCalls, 0, `${label}: 不得呼叫模型`);
  assertEquals(
    out.fake.rpc.map((r) => r.fn),
    ["increment_model_usage", "charge_stream_analysis_run_v3"],
    `${label}: 只有限流與不扣的關心紀錄（沒有 increment_usage、沒有超額確認）`,
  );
  const record = out.fake.rpc[1].args;
  assertEquals(record.p_charge_quota, false, label);
  assertEquals(record.p_message_count, 0, label);
  assertEquals(record.p_decision_kind, "do_not_send", label);
  assertEquals(
    (record.p_recommendation_json as Record<string, unknown>).action,
    "care",
    label,
  );
  assertEquals(out.fake.run?.status, "done", `${label}: run 以 done 結案`);
  const trace = (out.fake.run?.final_result_json as Record<string, unknown>)
    .guideV3Trace as Record<string, unknown>;
  assertEquals(trace.care, {
    kind: "self_harm",
    trigger: "keyword",
    insufficientQuota: true,
  }, label);
  const outcome = out.logs.find((l) => l.event === "guide_v3_outcome");
  assert(outcome, `${label}: 有 outcome log`);
  assertEquals(outcome.metadata.insufficientQuota, true, label);
  assertEquals(outcome.metadata.charged, false, label);
}

/// 照舊 429：回應內容跟改版前一字不差，沒建 run、沒打模型。
function assertProjected429(
  out: Outcome,
  expected: {
    cost: number;
    reason: "monthly_limit_exceeded" | "daily_limit_exceeded";
    monthlyUsed: number;
    dailyUsed: number;
  },
  label: string,
) {
  assertEquals(out.status, 429, `${label}: status ${out.text}`);
  assertEquals(
    out.text,
    JSON.stringify(buildQuotaExceededPayload({
      sub: {
        tier: "free",
        monthly_messages_used: expected.monthlyUsed,
        daily_messages_used: expected.dailyUsed,
        daily_reset_at: null,
        monthly_reset_at: null,
      },
      cost: expected.cost,
      reason: expected.reason,
      monthlyLimit: FREE_MONTHLY,
      dailyLimit: FREE_DAILY,
    })),
    label,
  );
  assertEquals(out.fake.inserts, [], `${label}: 不建 run`);
  assertEquals(out.modelCalls, 0, `${label}: 不打模型`);
  assertEquals(
    out.fake.rpc.some((r) => r.fn === "charge_stream_analysis_run_v3"),
    false,
    label,
  );
}

Deno.test("本月剩的不夠、她說不想活了：不回 429，直接給關心訊息與專線，不打模型、不扣", async () => {
  const monthlyUsed = projectedShort(HER_SELF_HARM, FREE_MONTHLY);
  const out = await analyze(chatAnalysis(HER_SELF_HARM), { monthlyUsed });
  assertQuotaCare(out, "本月不夠");
});

Deno.test("今天剩的不夠、她說不想活了：同樣直接給關心訊息，不打模型、不扣", async () => {
  const dailyUsed = projectedShort(HER_SELF_HARM, FREE_DAILY);
  const out = await analyze(chatAnalysis(HER_SELF_HARM), { dailyUsed });
  assertQuotaCare(out, "今天不夠");
});

Deno.test("剩的不夠、沒有那五個字（含只有想死、只有未成年、只在他的訊息或她引用的內容）：照舊 429，一字不差", async () => {
  const cases: [string, Msg[]][] = [
    ["沒有自傷字眼", HER_PLAIN],
    ["只有想死", HER_WANTS_TO_DIE],
    ["只有未成年", HER_MINOR],
    ["只在他的訊息", HIS_SELF_HARM_ONLY],
    ["只在她引用的內容", HER_QUOTES_HIS],
  ];
  for (const [label, messages] of cases) {
    const monthlyUsed = projectedShort(messages, FREE_MONTHLY);
    const out = await analyze(chatAnalysis(messages), { monthlyUsed });
    assertProjected429(out, {
      cost: unitsFor(messages),
      reason: "monthly_limit_exceeded",
      monthlyUsed,
      dailyUsed: 0,
    }, label);
  }
  const dailyUsed = projectedShort(HER_PLAIN, FREE_DAILY);
  assertProjected429(
    await analyze(chatAnalysis(HER_PLAIN), { dailyUsed }),
    {
      cost: unitsFor(HER_PLAIN),
      reason: "daily_limit_exceeded",
      monthlyUsed: 0,
      dailyUsed,
    },
    "今天不夠、沒有自傷字眼",
  );
});

Deno.test("剩的不夠、她有自傷字眼，但走 v2（開關關閉、App 協定版本 2）：照舊 429", async () => {
  const monthlyUsed = projectedShort(HER_SELF_HARM, FREE_MONTHLY);
  const expected = {
    cost: unitsFor(HER_SELF_HARM),
    reason: "monthly_limit_exceeded" as const,
    monthlyUsed,
    dailyUsed: 0,
  };
  assertProjected429(
    await analyze(chatAnalysis(HER_SELF_HARM), {
      monthlyUsed,
      guideV3: "off",
    }),
    expected,
    "開關關閉",
  );
  assertProjected429(
    await analyze(
      chatAnalysis(HER_SELF_HARM, { analysisContractVersion: 2 }),
      { monthlyUsed },
    ),
    expected,
    "協定版本 2",
  );
  // test 只開給測試帳號；一般帳號照舊走 v2。
  assertProjected429(
    await analyze(chatAnalysis(HER_SELF_HARM), {
      monthlyUsed,
      guideV3: "test",
    }),
    expected,
    "開關 test、一般帳號",
  );
});

Deno.test("額度用完、她有自傷字眼的潤飾與微調：照舊 429（只有一般分析會走關心）", async () => {
  const expected = {
    cost: OPTIMIZE_MESSAGE_COST,
    reason: "monthly_limit_exceeded" as const,
    monthlyUsed: FREE_MONTHLY,
    dailyUsed: 0,
  };
  assertProjected429(
    await analyze(
      { messages: HER_SELF_HARM, userDraft: "那我陪你聊聊好嗎" },
      { monthlyUsed: FREE_MONTHLY },
    ),
    expected,
    "潤飾",
  );
  assertProjected429(
    await analyze(
      {
        messages: HER_SELF_HARM,
        userDraft: "那我陪你聊聊好嗎",
        refineInstruction: "短一點",
        requestId: crypto.randomUUID(),
      },
      { monthlyUsed: FREE_MONTHLY },
    ),
    expected,
    "微調",
  );
});

Deno.test("額度夠、她說不想活了：照今天的 v3 流程先讀局面（打一次模型），再照關鍵字給關心、不扣", async () => {
  const out = await analyze(chatAnalysis(HER_SELF_HARM));
  assertEquals(out.status, 200);
  const [read] = byType(events(out.text), "analysis.read");
  assertEquals(read.careKind, "self_harm");
  assertEquals(out.modelCalls, 1, "讀局面那一次");
  const trace = (out.fake.run?.final_result_json as Record<string, unknown>)
    .guideV3Trace as { care: Record<string, unknown> };
  assertEquals(trace.care, { kind: "self_harm", trigger: "keyword" });
  const record = out.fake.rpc.find((r) =>
    r.fn === "charge_stream_analysis_run_v3"
  )!;
  assertEquals(record.args.p_charge_quota, false);
});

Deno.test("超過 2000 字、剩的不夠、她說不想活了：不用先確認長內容，直接給關心（不扣、不認領確認）", async () => {
  const messages: Msg[] = [
    { content: "我真的不想活了，" + "好".repeat(1100), isFromMe: false },
    { content: "對不起一直跟你講這些，" + "累".repeat(1000), isFromMe: false },
  ];
  const band = bandForBillableChars(countPayloadChars(messages));
  assertEquals(band.band, "overcharge");
  const monthlyUsed = projectedShort(messages, FREE_MONTHLY);
  const out = await analyze(chatAnalysis(messages), { monthlyUsed });
  assertQuotaCare(out, "超過 2000 字");
  assertEquals(
    out.fake.rpc.some((r) => r.fn === "claim_overcharge_confirmation"),
    false,
  );

  // 對照：額度夠的時候照舊要先確認長內容（409，不分析）。
  const enough = await analyze(chatAnalysis(messages));
  assertEquals(enough.status, 409);
  assertEquals(
    JSON.parse(enough.text).code,
    "OVERCHARGE_CONFIRMATION_REQUIRED",
  );
  assertEquals(enough.modelCalls, 0);
});

Deno.test("剩的不夠、她說不想活了，其他關卡照舊：模型限流照樣 429、超過 4000 字照樣 400", async () => {
  const monthlyUsed = projectedShort(HER_SELF_HARM, FREE_MONTHLY);
  const limited = await analyze(chatAnalysis(HER_SELF_HARM), {
    monthlyUsed,
    rateLimited: true,
  });
  assertEquals(limited.status, 429);
  assertEquals(JSON.parse(limited.text).code, "MODEL_RATE_LIMITED");
  assertEquals(limited.fake.inserts, []);
  assertEquals(limited.modelCalls, 0);

  const tooLong: Msg[] = [
    { content: "我真的不想活了，" + "好".repeat(1990), isFromMe: false },
    { content: "好".repeat(1990), isFromMe: false },
    { content: "好".repeat(100), isFromMe: false },
  ];
  assertEquals(
    bandForBillableChars(countPayloadChars(tooLong)).band,
    "reject",
  );
  const rejected = await analyze(chatAnalysis(tooLong), { monthlyUsed });
  assertEquals(rejected.status, 400);
  assertEquals(
    JSON.parse(rejected.text).code,
    "CONTENT_TOO_LONG_FOR_ANALYSIS",
  );
  assertEquals(rejected.fake.inserts, []);
  assertEquals(rejected.modelCalls, 0);
});
