// 任務卡「再調一下」的整條路徑工具：用假 Supabase 跑正式 handler（訂閱、帳本、免費次數、
// 限流都是假的，額度一律還有、免費次數一律授權），模型呼叫交給呼叫端決定——測試給假回覆，
// 黑箱工具在付費閘內放行真的 API。其他對外連線（ai_logs）一律回成功、不連網。
// 給 refine_guide_v3_handler_test.ts 與 tools/v3-card-refine-blackbox 共用；入口不載入，
// 不隨函式部署。
import { createAnalyzeChatHandler } from "../index.ts";

export const REFINE_HARNESS_USER_ID = "00000000-0000-4000-8000-0000000000aa";

export interface RefineHarnessRpc {
  readonly fn: string;
  readonly args: Record<string, unknown>;
}

export interface RefineHarnessOutcome {
  readonly status: number;
  readonly json: Record<string, unknown>;
  readonly rpcs: readonly RefineHarnessRpc[];
}

/// 模型那一跳：收到 fallback.ts 送出的 body（與原本的 init，真跑時原樣轉送），回
/// Anthropic 的 Response。
export type RefineHarnessModel = (
  body: Record<string, unknown>,
  init: RequestInit | undefined,
) => Promise<Response>;

function fakeSupabase(rpcs: RefineHarnessRpc[]) {
  const nowIso = new Date().toISOString();
  const subscription = {
    tier: "free",
    monthly_messages_used: 0,
    daily_messages_used: 0,
    daily_reset_at: nowIso,
    monthly_reset_at: nowIso,
  };
  const query = (table: string) => {
    // 訂閱有一列；重播帳本與免費次數都還沒有紀錄（第一次、今天還沒用過）。
    const result = {
      data: table === "subscriptions" ? subscription : null,
      error: null,
    };
    // deno-lint-ignore no-explicit-any
    const builder: any = {
      select: () => builder,
      eq: () => builder,
      gte: () => builder,
      is: () => builder,
      update: () => builder,
      insert: () => builder,
      maybeSingle: () => Promise.resolve(result),
      single: () => Promise.resolve(result),
      then: (resolve: (value: unknown) => unknown) => resolve(result),
    };
    return builder;
  };
  return {
    auth: {
      getUser: () =>
        Promise.resolve({
          data: {
            user: { id: REFINE_HARNESS_USER_ID, email: "refine@example.com" },
          },
          error: null,
        }),
    },
    from: query,
    rpc: (fn: string, args: Record<string, unknown>) => {
      rpcs.push({ fn, args });
      if (fn === "consume_refine_free_allowance") {
        return Promise.resolve({
          data: { granted: true, used: 1, remaining: 9 },
          error: null,
        });
      }
      if (fn === "settle_optimize_message_request") {
        return Promise.resolve({
          data: {
            result: args.p_result_json,
            charged: false,
            monthlyUsed: 0,
            dailyUsed: 0,
          },
          error: null,
        });
      }
      return Promise.resolve({ data: null, error: null });
    },
    // deno-lint-ignore no-explicit-any
  } as any;
}

/// 送一次請求（App 的 body 原樣），跑完整個 handler；跑的時候暫時換掉 fetch。
export async function runRefineThroughHandler(
  body: Record<string, unknown>,
  model: RefineHarnessModel,
): Promise<RefineHarnessOutcome> {
  const rpcs: RefineHarnessRpc[] = [];
  const handler = createAnalyzeChatHandler({
    createSupabaseClient: () => fakeSupabase(rpcs),
  });
  const originalFetch = globalThis.fetch;
  globalThis.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
    const url = typeof input === "string"
      ? input
      : input instanceof URL
      ? input.href
      : input.url;
    if (url.startsWith("https://api.anthropic.com/")) {
      return model(JSON.parse(String(init?.body)), init);
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
        body: JSON.stringify(body),
      }),
    );
    return { status: response.status, json: await response.json(), rpcs };
  } finally {
    globalThis.fetch = originalFetch;
  }
}

/// 假模型的回覆：Anthropic messages API 的形狀，內容是一段文字。
export function fakeModelResponse(text: string): Response {
  return new Response(
    JSON.stringify({
      id: "msg_refine_harness",
      type: "message",
      role: "assistant",
      model: "claude-sonnet-5",
      content: [{ type: "text", text }],
      stop_reason: "end_turn",
      usage: { input_tokens: 120, output_tokens: 30 },
    }),
    { status: 200, headers: { "content-type": "application/json" } },
  );
}
