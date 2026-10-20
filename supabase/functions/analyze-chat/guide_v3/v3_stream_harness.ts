// v3 串流分析的整條路徑工具：用假 Supabase 跑正式 handler（訂閱、限流、run 的建立、
// 扣費與結案都在記憶體），模型那一跳交給呼叫端（測試給假回覆；黑箱工具在付費閘內才
// 放行真的 API），ai_logs 等其他對外連線一律回成功、不連網。
//
// handler 模組一載入就讀 env 常數（STREAM_ANALYZE_ENABLED、CLAUDE_API_KEY），寫卡的
// streaming_fallback.ts 也在載入時存下 fetch，所以這裡不 import 入口：呼叫端先裝好 env
// 與 test_fetch_dispatcher.ts，再動態 import index.ts，把 createAnalyzeChatHandler 交進來。
// 給 previous_round_handler_test.ts 與 tools/v3-prev-round-blackbox 共用；入口不載入，
// 不隨函式部署。兩段式實驗（ANALYZE_GUIDE_V3_TWO_STAGE）一樣由 env 每次請求設定：開了會多一跳
// 說明步驟，用 v3HarnessStage 分出是哪一步。
import type { createAnalyzeChatHandler } from "../index.ts";
import { EXPLAIN_SCHEMA } from "./explain.ts";
import { MEMORY_SCHEMA } from "./memory.ts";

export const V3_HARNESS_USER_ID = "00000000-0000-4000-8000-0000000000bb";
/// 一般帳號（不在 TEST_EMAILS）：照常算額度與扣費。
export const V3_HARNESS_USER_EMAIL = "prev-round@example.com";

export interface V3HarnessRpc {
  readonly fn: string;
  readonly args: Record<string, unknown>;
}

export interface V3HarnessOutcome {
  readonly status: number;
  /// 串流的 NDJSON 事件；不是串流（例如 4xx）就是空的，看 json。
  readonly events: Record<string, unknown>[];
  readonly json: Record<string, unknown> | null;
  /// analysis_stream_runs 新增的列（conversation_hash、request_context）。
  readonly createdRuns: Record<string, unknown>[];
  readonly rpcs: readonly V3HarnessRpc[];
  /// 送到模型那一跳的 body（讀局面、寫卡、對象記憶），照送出順序。
  readonly modelBodies: Record<string, unknown>[];
  /// markDone 寫進資料庫的結果（含伺服器專用的 guideV3Trace）。
  readonly finalResult: Record<string, unknown> | null;
}

/// 模型那一跳：收到 handler 送出的 body（與原本的 init，真跑時原樣轉送），回
/// Anthropic 的 Response（讀局面是 JSON，寫卡是 SSE）。
export type V3HarnessModel = (
  body: Record<string, unknown>,
  init: RequestInit | undefined,
) => Promise<Response>;

type Row = Record<string, unknown>;

/// 假 Supabase 建的 run 預設用的 id（固定，結果對得回來）。
export const V3_HARNESS_RUN_ID = "11111111-2222-4333-8444-000000000001";

function fakeSupabase(args: {
  email: string;
  tier: string;
  createdRuns: Row[];
  rpcs: V3HarnessRpc[];
  finals: Row[];
  runId?: string;
}) {
  const nowIso = new Date().toISOString();
  let run: Row | null = null;
  const subscription = {
    tier: args.tier,
    monthly_messages_used: 0,
    daily_messages_used: 0,
    daily_reset_at: nowIso,
    monthly_reset_at: nowIso,
  };
  const from = (table: string) => {
    let op: "select" | "insert" | "update" = "select";
    let values: Row = {};
    const result = () => {
      if (table === "subscriptions") {
        return {
          data: op === "select" ? { ...subscription } : null,
          error: null,
        };
      }
      if (table === "analysis_stream_runs") {
        if (op === "insert") {
          args.createdRuns.push(values);
          run = {
            id: args.runId ?? V3_HARNESS_RUN_ID,
            selected_style: null,
            decision_kind: null,
            card_task: null,
            recommendation_json: null,
            final_result_json: null,
            charged_at: null,
            last_error_code: null,
            created_at: nowIso,
            expires_at: new Date(Date.now() + 30 * 60_000).toISOString(),
            ...values,
          };
        } else if (op === "update" && run) {
          run = { ...run, ...values };
          if (values.status === "done") {
            args.finals.push(values.final_result_json as Row);
          }
        }
        return { data: run ? { ...run } : null, error: null };
      }
      return { data: null, error: null };
    };
    // deno-lint-ignore no-explicit-any
    const builder: any = {
      select: () => builder,
      eq: () => builder,
      gte: () => builder,
      is: () => builder,
      insert: (v: Row) => {
        op = "insert";
        values = v;
        return builder;
      },
      update: (v: Row) => {
        op = "update";
        values = v;
        return builder;
      },
      maybeSingle: () => Promise.resolve(result()),
      single: () => Promise.resolve(result()),
      then: (resolve: (value: unknown) => unknown) => resolve(result()),
    };
    return builder;
  };
  return {
    auth: {
      getUser: () =>
        Promise.resolve({
          data: { user: { id: V3_HARNESS_USER_ID, email: args.email } },
          error: null,
        }),
    },
    from,
    rpc: (fn: string, rpcArgs: Row) => {
      args.rpcs.push({ fn, args: rpcArgs });
      if (fn === "charge_stream_analysis_run_v3" && run) {
        run = {
          ...run,
          status: "charged",
          charged_at: new Date().toISOString(),
          decision_kind: rpcArgs.p_decision_kind,
          card_task: rpcArgs.p_card_task,
          recommendation_json: rpcArgs.p_recommendation_json,
        };
        return Promise.resolve({ data: { ...run }, error: null });
      }
      // increment_model_usage 等：沒錯就是放行。
      return Promise.resolve({ data: null, error: null });
    },
    // deno-lint-ignore no-explicit-any
  } as any;
}

/// 送一次 v3 串流分析（App 的 body 原樣），跑完整個 handler。env 只在這次請求期間
/// 換上（例如 ANALYZE_GUIDE_V3、ANALYZE_GUIDE_V3_PREV_ROUND；值給 undefined＝沒設），
/// 結束後還原；fetch 也一樣。
export async function runGuideV3StreamThroughHandler(args: {
  readonly createHandler: typeof createAnalyzeChatHandler;
  readonly body: Record<string, unknown>;
  readonly model: V3HarnessModel;
  readonly env?: Readonly<Record<string, string | undefined>>;
  readonly email?: string;
  readonly tier?: string;
  /// 換掉假 Supabase 建的 run 的 id（短版稱讚照 runId 抽，測試要指定抽到哪一邊時用）；沒給是 V3_HARNESS_RUN_ID。
  readonly runId?: string;
}): Promise<V3HarnessOutcome> {
  const createdRuns: Row[] = [];
  const rpcs: V3HarnessRpc[] = [];
  const finals: Row[] = [];
  const modelBodies: Row[] = [];
  const handler = args.createHandler({
    createSupabaseClient: () =>
      fakeSupabase({
        email: args.email ?? V3_HARNESS_USER_EMAIL,
        tier: args.tier ?? "essential",
        createdRuns,
        rpcs,
        finals,
        ...(args.runId ? { runId: args.runId } : {}),
      }),
  });
  const savedEnv = Object.keys(args.env ?? {}).map((k) =>
    [k, Deno.env.get(k)] as const
  );
  for (const [k, v] of Object.entries(args.env ?? {})) {
    if (v === undefined) Deno.env.delete(k);
    else Deno.env.set(k, v);
  }
  const originalFetch = globalThis.fetch;
  globalThis.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
    const url = typeof input === "string"
      ? input
      : input instanceof URL
      ? input.href
      : input.url;
    if (url.startsWith("https://api.anthropic.com/")) {
      const body = JSON.parse(String(init?.body)) as Row;
      modelBodies.push(body);
      return args.model(body, init);
    }
    return Promise.resolve(new Response("{}", { status: 201 }));
  }) as typeof fetch;
  try {
    const response = await handler(
      new Request("http://localhost/analyze-chat", {
        method: "POST",
        headers: {
          Authorization: "Bearer fake-token",
          "Content-Type": "application/json",
        },
        body: JSON.stringify(args.body),
      }),
    );
    const text = await response.text();
    const isStream = (response.headers.get("content-type") ?? "").includes(
      "ndjson",
    );
    return {
      status: response.status,
      events: isStream
        ? text.split("\n").filter(Boolean).map((l) => JSON.parse(l))
        : [],
      json: isStream ? null : JSON.parse(text),
      createdRuns,
      rpcs,
      modelBodies,
      finalResult: finals.at(-1) ?? null,
    };
  } finally {
    globalThis.fetch = originalFetch;
    for (const [k, v] of savedEnv) {
      if (v === undefined) Deno.env.delete(k);
      else Deno.env.set(k, v);
    }
  }
}

/// 讀局面的假回覆：Anthropic messages API 的形狀，內容是讀局面標記的 JSON 文字。
export function fakeReadResponse(tags: Record<string, unknown>): Response {
  return new Response(
    JSON.stringify({
      id: "msg_v3_harness_read",
      type: "message",
      role: "assistant",
      model: "claude-sonnet-5-5",
      content: [{ type: "text", text: JSON.stringify(tags) }],
      stop_reason: "end_turn",
      usage: { input_tokens: 120, output_tokens: 60 },
    }),
    { status: 200, headers: { "content-type": "application/json" } },
  );
}

/// 寫卡的假回覆：Anthropic 的 SSE，一行一張卡。
export function fakeWriteResponse(lines: readonly string[]): Response {
  const encoder = new TextEncoder();
  const events = [
    `data: ${
      JSON.stringify({
        type: "message_start",
        message: {
          model: "claude-sonnet-5-5",
          usage: { input_tokens: 200, output_tokens: 1 },
        },
      })
    }\n\n`,
    ...lines.map((text) =>
      `data: ${
        JSON.stringify({
          type: "content_block_delta",
          delta: { type: "text_delta", text: `${text}\n` },
        })
      }\n\n`
    ),
    'data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":80}}\n\n',
  ];
  return new Response(
    new ReadableStream<Uint8Array>({
      start(controller) {
        for (const event of events) controller.enqueue(encoder.encode(event));
        controller.close();
      },
    }),
    { status: 200, headers: { "content-type": "text/event-stream" } },
  );
}

export type V3HarnessStage = "read" | "write" | "memory" | "explain";

/// 送到模型那一跳是哪一步：寫卡是串流；非串流的照 json_schema 分（說明步驟、對象記憶各有
/// 自己的 schema），其他是讀局面。
export function v3HarnessStage(body: Record<string, unknown>): V3HarnessStage {
  if (body.stream === true) return "write";
  const schema = (body.output_config as
    | { format?: { schema?: unknown } }
    | undefined)?.format?.schema;
  const same = (a: unknown, b: unknown) =>
    JSON.stringify(a) === JSON.stringify(b);
  if (same(schema, EXPLAIN_SCHEMA)) return "explain";
  if (same(schema, MEMORY_SCHEMA)) return "memory";
  return "read";
}

/// 說明步驟的假回覆：Anthropic messages API 的形狀，內容是每張卡一段說明的 JSON 文字。
export function fakeExplainResponse(
  explanations: readonly { card: number; text: string }[],
): Response {
  return new Response(
    JSON.stringify({
      id: "msg_v3_harness_explain",
      type: "message",
      role: "assistant",
      model: "claude-sonnet-5-5",
      content: [{ type: "text", text: JSON.stringify({ explanations }) }],
      stop_reason: "end_turn",
      usage: { input_tokens: 150, output_tokens: 90 },
    }),
    { status: 200, headers: { "content-type": "application/json" } },
  );
}
