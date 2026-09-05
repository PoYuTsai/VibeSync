// practice-chat handler 的共用測試替身（fake Supabase／DeepSeek／Claude）。
//
// 原本整份住在 `index_test.ts`；conversation-agency-v1 Phase 2.7 需要第二個
// 測試檔（`agency_flag_off_equivalence_test.ts`）跑同一個 handler，而 Deno 的
// 測試登錄是「模組被 import 就註冊」——一個 `_test.ts` import 另一個
// `_test.ts` 會讓被 import 那份的每個 Deno.test 跑兩次（實測確認）。所以替身
// 移到這個非 `_test.ts` 模組，兩個測試檔各自 import。
//
// 這個檔不會被 `index.ts` import，因此不進 Edge Function 的 bundle。
// 內容是從 `index_test.ts` **原樣搬過來**的（只加 export），行為零改動。

import { type ClaudeArgs } from "./claude.ts";
import { type DeepSeekArgs } from "./deepseek.ts";
import {
  type ClaudeCaller,
  createPracticeChatHandler,
  type DeepSeekCaller,
  type PracticeSupabaseClient,
} from "./handler.ts";

export const NOW = new Date("2026-06-28T04:00:00.000Z");
export const RESET_AT = "2026-06-28T00:00:00.000Z";

export type RpcResult = {
  data?: unknown;
  error?: string;
  /**
   * 永不 resolve 的 RPC，用來驗「選配查詢不得吊死核心路徑」。
   * 呼叫端沒有逾時的話，用到這個的測試會直接掛住不返回。
   */
  neverResolves?: boolean;
};

export interface FakeOptions {
  user?: { id: string; email?: string | null } | null;
  userError?: string;
  sub?: Record<string, unknown> | null;
  preparedSub?: Record<string, unknown> | null;
  subError?: string;
  ledger?: Record<string, unknown> | null;
  ledgerError?: string;
  hintRequest?: Record<string, unknown> | null;
  hintRequestError?: string;
  thread?: Record<string, unknown> | null;
  threadError?: string;
  drawEvents?: ReadonlyArray<Record<string, unknown>>;
  drawEventsError?: string;
  /** practice_sr_draw_tickets 讀回列（grant 後查詢）；預設未消耗券。 */
  srTicketRow?: Record<string, unknown> | null;
  srTicketReadError?: string;
  srTicketUpsertError?: string;
  /**
   * WP3：`practice_relationship_threads` 單欄 UPDATE 的結果。
   * `rows` 預設 1（有這一列）；0＝thread 不存在或角色已換。
   */
  threadUpdate?: { error?: string; rejects?: boolean; rows?: number };
  aiLogsError?: string;
  aiLogsNeverCompletes?: boolean;
  rpc?: Record<string, RpcResult[]>;
  deepSeekReplies?: ReadonlyArray<string | Error>;
  claudeReplies?: ReadonlyArray<string | Error>;
  /**
   * Phase 4.4（Codex R2 P2）：模擬 `callClaude` 在 HTTP 200 但丟錯
   * （`max_tokens`／`refusal`／內容空）時的真實時序——provider 已經回了 usage，
   * 所以 callback 先響，然後才拒絕。省略＝失敗完全不記帳（連線層失敗）。
   */
  claudeUsageBeforeError?: boolean;
  monotonicNowValues?: ReadonlyArray<number>;
  env?: Record<string, string | undefined>;
  randomUUID?: string;
}

export interface FakeState {
  selects: Array<{ table: string; columns: string }>;
  inserts: Array<{ table: string; values: Record<string, unknown> }>;
  updates: Array<
    {
      table: string;
      values: Record<string, unknown>;
      /** WP3：單欄 UPDATE 的 WHERE 綁了哪幾欄（順序即呼叫順序）。 */
      where: Array<[string, unknown]>;
    }
  >;
  upserts: Array<{ table: string; values: Record<string, unknown> }>;
  rpcCalls: Array<{ fn: string; params: Record<string, unknown> }>;
  deepSeekCalls: DeepSeekArgs[];
  claudeCalls: ClaudeArgs[];
  semanticCalls: unknown[];
  events: string[];
  backgroundTasks: Promise<void>[];
  debriefCount: number;
}

export function subscription(overrides: Record<string, unknown> = {}) {
  return {
    tier: "starter",
    monthly_messages_used: 10,
    daily_messages_used: 2,
    daily_reset_at: RESET_AT,
    monthly_reset_at: RESET_AT,
    ...overrides,
  };
}

export function ledger(overrides: Record<string, unknown> = {}) {
  const row: Record<string, unknown> = {
    ai_count: 0,
    charged: false,
    debrief_count: 0,
    practice_mode: "standard",
    temperature_score: null,
    familiarity_score: null,
    hint_count: 0,
    ...overrides,
  };
  if (!("debrief_request_ledger" in overrides)) {
    const requestId = typeof row.last_debrief_request_id === "string"
      ? row.last_debrief_request_id
      : null;
    const result = row.last_debrief_result ?? null;
    const startedAt = typeof row.last_debrief_started_at === "string"
      ? row.last_debrief_started_at
      : null;
    const generationToken = result === null && startedAt !== null
      ? typeof row.last_debrief_generation_token === "string"
        ? row.last_debrief_generation_token
        : "stored-generation-token"
      : null;
    row.debrief_request_ledger = requestId === null ? {} : {
      [requestId]: {
        result,
        started_at: startedAt,
        generation_token: generationToken,
        counted: true,
      },
    };
  }
  return row;
}

export function chatBody(overrides: Record<string, unknown> = {}) {
  return {
    mode: "chat",
    sessionId: "session-1",
    roundIndex: 1,
    turns: [{ role: "user", text: "hi" }],
    ...overrides,
  };
}

export function hintBody(overrides: Record<string, unknown> = {}) {
  return {
    mode: "hint",
    sessionId: "session-1",
    acceptedQualitySchemaVersion: "semantic-quality-v2",
    turns: [
      { role: "user", text: "今天精神怎樣" },
      { role: "ai", text: "我今天突然很想喝咖啡" },
    ],
    ...overrides,
  };
}

export function debriefBody(overrides: Record<string, unknown> = {}) {
  return {
    mode: "debrief",
    sessionId: "session-1",
    acceptedQualitySchemaVersion: "semantic-quality-v2",
    requestId: "debrief-default-request",
    turns: [
      { role: "user", text: "今天忙到剛下班" },
      { role: "ai", text: "我也剛下班，只想散步放空" },
    ],
    ...overrides,
  };
}

export function validDebriefJson(overrides: Record<string, unknown> = {}) {
  return JSON.stringify({
    summary: "你說今天忙到剛下班，她接著分享只想散步放空。",
    strengths: ["你先分享自己今天忙到剛下班，讓對話有具體情境。"],
    watchouts: ["下一步要接住她想散步放空，不要只停在自己的忙碌。"],
    suggestedLine: "下班後散步很療癒，妳最常走哪一段？",
    vibe: "中性",
    dateChance: "medium",
    dateChanceReason: "她回覆自己剛下班，只想散步放空，但還沒提時間或見面。",
    nextInviteMove: "先問她最常去哪裡散步，等她多分享再看是否出現邀約窗口。",
    hintAssessment: {
      verdict: "preserved",
      revisedEvidenceQuote: null,
    },
    ...overrides,
  });
}

export function validHintJson(overrides: Record<string, string> = {}) {
  return JSON.stringify({
    warmUp: "聽起來這杯咖啡有任務，是想醒腦還是想放空？",
    steady: "咖啡念頭收到，我先押妳今天比較想放空，猜錯妳糾正我。",
    coaching:
      "她主動說突然想喝咖啡；先用醒腦或放空二選一接她的狀態，再沿她的答案分享。",
    ...overrides,
  });
}

export function makeRequest(body: unknown) {
  return new Request("http://localhost/practice-chat", {
    method: "POST",
    headers: {
      Authorization: "Bearer test-token",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

export function makeFake(options: FakeOptions = {}) {
  const state: FakeState = {
    selects: [],
    inserts: [],
    updates: [],
    upserts: [],
    rpcCalls: [],
    deepSeekCalls: [],
    claudeCalls: [],
    semanticCalls: [],
    events: [],
    backgroundTasks: [],
    debriefCount: typeof options.ledger?.debrief_count === "number"
      ? options.ledger.debrief_count
      : 0,
  };
  const rpcByName = new Map<string, number>();
  let deepSeekIndex = 0;
  let claudeIndex = 0;
  let monotonicNowIndex = 0;

  // deno-lint-ignore no-explicit-any
  const client: any = {
    auth: {
      getUser(_token: string) {
        if (options.userError) {
          return Promise.resolve({
            data: { user: null },
            error: { message: options.userError },
          });
        }
        return Promise.resolve({
          data: {
            user: options.user === undefined
              ? { id: "user-1", email: "user@example.com" }
              : options.user,
          },
          error: null,
        });
      },
    },
    from(table: string) {
      return {
        insert(values: Record<string, unknown>) {
          state.inserts.push({ table, values });
          state.events.push(`insert:${table}`);
          if (table === "ai_logs" && options.aiLogsNeverCompletes) {
            return new Promise(() => {});
          }
          return Promise.resolve({
            data: null,
            error: table === "ai_logs" && options.aiLogsError
              ? { message: options.aiLogsError }
              : null,
          });
        },
        upsert(
          values: Record<string, unknown>,
          _opts?: Record<string, unknown>,
        ) {
          state.upserts.push({ table, values });
          state.events.push(`upsert:${table}`);
          return Promise.resolve({
            data: null,
            error: table === "practice_sr_draw_tickets" &&
                options.srTicketUpsertError
              ? { message: options.srTicketUpsertError }
              : null,
          });
        },
        select(columns: string) {
          state.selects.push({ table, columns });
          function selectResult() {
            if (table === "practice_profile_draw_events") {
              return Promise.resolve(
                options.drawEventsError
                  ? {
                    data: null,
                    error: { message: options.drawEventsError },
                  }
                  : { data: options.drawEvents ?? [], error: null },
              );
            }
            return Promise.resolve({ data: null, error: null });
          }
          // deno-lint-ignore no-explicit-any
          const builder: any = {
            eq(_column: string, _value: unknown) {
              return builder;
            },
            maybeSingle() {
              if (table === "subscriptions") {
                return Promise.resolve(
                  options.subError
                    ? { data: null, error: { message: options.subError } }
                    : {
                      data: options.sub === undefined
                        ? subscription()
                        : options.sub,
                      error: null,
                    },
                );
              }
              if (table === "practice_chat_sessions") {
                return Promise.resolve(
                  options.ledgerError
                    ? { data: null, error: { message: options.ledgerError } }
                    : {
                      data: options.ledger === undefined
                        ? ledger()
                        : options.ledger,
                      error: null,
                    },
                );
              }
              if (table === "practice_hint_requests") {
                return Promise.resolve(
                  options.hintRequestError
                    ? {
                      data: null,
                      error: { message: options.hintRequestError },
                    }
                    : {
                      data: options.hintRequest === undefined
                        ? null
                        : options.hintRequest,
                      error: null,
                    },
                );
              }
              if (table === "practice_sr_draw_tickets") {
                return Promise.resolve(
                  options.srTicketReadError
                    ? {
                      data: null,
                      error: { message: options.srTicketReadError },
                    }
                    : {
                      data: options.srTicketRow === undefined
                        ? { consumed_at: null }
                        : options.srTicketRow,
                      error: null,
                    },
                );
              }
              if (table === "practice_relationship_threads") {
                return Promise.resolve(
                  options.threadError
                    ? { data: null, error: { message: options.threadError } }
                    : {
                      data: options.thread === undefined
                        ? null
                        : options.thread,
                      error: null,
                    },
                );
              }
              return selectResult();
            },
            then(
              onfulfilled?: (value: unknown) => unknown,
              onrejected?: (reason: unknown) => unknown,
            ) {
              return selectResult().then(onfulfilled, onrejected);
            },
          };
          return builder;
        },
        update(values: Record<string, unknown>) {
          const where: Array<[string, unknown]> = [];
          state.updates.push({ table, values, where });
          state.events.push(`update:${table}`);
          const result = () => {
            if (table !== "practice_relationship_threads") {
              return Promise.resolve({ data: null, error: null });
            }
            const spec = options.threadUpdate ?? {};
            if (spec.rejects) {
              return Promise.reject(new Error("thread update rejected"));
            }
            if (spec.error) {
              return Promise.resolve({
                data: null,
                error: { message: spec.error },
              });
            }
            const rows = spec.rows ?? 1;
            return Promise.resolve({
              data: Array.from({ length: rows }, () => ({
                visible_thread_id: "thread",
              })),
              error: null,
            });
          };
          // deno-lint-ignore no-explicit-any
          const builder: any = {
            eq(column: string, value: unknown) {
              where.push([column, value]);
              return builder;
            },
            select(_columns: string) {
              return result();
            },
            then(
              onfulfilled?: (value: unknown) => unknown,
              onrejected?: (reason: unknown) => unknown,
            ) {
              return result().then(onfulfilled, onrejected);
            },
          };
          return builder;
        },
      };
    },
    rpc(fn: string, params: Record<string, unknown>) {
      state.rpcCalls.push({ fn, params });
      state.events.push(`rpc:${fn}`);
      const index = rpcByName.get(fn) ?? 0;
      rpcByName.set(fn, index + 1);
      const defaultResult: RpcResult = (() => {
        if (fn === "prepare_practice_subscription_usage") {
          if (options.subError) return { error: options.subError };
          if (options.preparedSub === null || options.sub === null) {
            return { error: "PRACTICE_SUBSCRIPTION_NOT_FOUND" };
          }
          return {
            data: options.preparedSub ?? options.sub ?? subscription(),
          };
        }
        if (fn === "commit_practice_chat_turn") {
          return { data: { new_ai_count: 1, did_charge: true } };
        }
        if (fn === "update_practice_learning_state") {
          // 鏡射正式 SQL 的 [0,100] 夾制（practice_partner_state.sql
          // GREATEST(0, LEAST(100, ...))），低溫重扣才不會在 mock 出現負分。
          const clampScore = (value: number) =>
            Math.max(0, Math.min(100, value));
          return {
            data: {
              updated: true,
              temperature_score: clampScore(
                (params.p_expected_temperature_score as number) +
                  (params.p_temperature_delta as number),
              ),
              familiarity_score: clampScore(
                (params.p_expected_familiarity_score as number) +
                  (params.p_familiarity_delta as number),
              ),
              partner_mood: params.p_partner_mood ?? "neutral",
              partner_inner_thought: params.p_partner_inner_thought ?? "",
            },
          };
        }
        if (fn === "record_practice_debrief") {
          return { data: params.p_result };
        }
        if (fn === "claim_practice_debrief") {
          return {
            data: {
              current_debrief_count: options.ledger?.debrief_count ?? 0,
              replay: false,
              in_flight: false,
              stored_result: null,
            },
          };
        }
        if (fn === "claim_practice_hint_generation") {
          return {
            data: {
              current_hint_count: options.ledger?.hint_count ?? 0,
              replay: false,
              stored_result: null,
              stored_charged: null,
            },
          };
        }
        if (fn === "claim_legacy_practice_hint_replacement") {
          return {
            data: {
              current_hint_count: options.ledger?.hint_count ?? 1,
              claimed: true,
              replay: false,
              stored_result: null,
              quota_already_paid:
                (options.hintRequest?.result as Record<string, unknown> | null)
                  ?.costDeducted === 1,
            },
          };
        }
        if (fn === "record_practice_hint") {
          const isConsumed = params.p_charged !== false;
          const currentHintCount =
            typeof options.ledger?.hint_count === "number"
              ? options.ledger.hint_count
              : 0;
          const newHintCount = currentHintCount + (isConsumed ? 1 : 0);
          const storedResult = params.p_request_id && params.p_result
            ? {
              ...(params.p_result as Record<string, unknown>),
              hintUsedCount: newHintCount,
            }
            : null;
          return {
            data: {
              new_hint_count: newHintCount,
              did_charge: params.p_charge_quota === true,
              stored_result: storedResult,
              stored_charged: isConsumed,
            },
          };
        }
        if (fn === "record_legacy_practice_hint_replacement") {
          const currentHintCount =
            typeof options.ledger?.hint_count === "number"
              ? options.ledger.hint_count
              : 1;
          const quotaAlreadyPaid =
            (options.hintRequest?.result as Record<string, unknown> | null)
              ?.costDeducted === 1;
          return {
            data: {
              new_hint_count: currentHintCount,
              did_charge: params.p_charge_quota === true,
              stored_result: {
                ...(params.p_result as Record<string, unknown>),
                costDeducted: quotaAlreadyPaid || params.p_charge_quota === true
                  ? 1
                  : 0,
                hintUsedCount: currentHintCount,
              },
              stored_charged: true,
            },
          };
        }
        if (fn === "settle_prefetched_practice_hint") {
          const currentHintCount =
            typeof options.ledger?.hint_count === "number"
              ? options.ledger.hint_count
              : 0;
          const didCharge = params.p_charge_quota === true;
          return {
            data: {
              new_hint_count: currentHintCount + 1,
              did_charge: didCharge,
              stored_result: {
                ...(options.hintRequest?.result as Record<string, unknown>),
                costDeducted: didCharge ? 1 : 0,
                hintUsedCount: currentHintCount + 1,
              },
              stored_charged: true,
            },
          };
        }
        if (fn === "discard_prefetched_practice_hint") {
          return {
            data: {
              discarded: true,
              replay: false,
              stored_result: null,
              stored_charged: false,
            },
          };
        }
        if (fn === "release_practice_hint_generation") {
          return { data: { released: true } };
        }
        if (fn === "release_legacy_practice_hint_replacement") {
          return { data: true };
        }
        if (fn === "release_practice_debrief_generation") {
          return { data: true };
        }
        if (fn === "invalidate_legacy_practice_ai_snapshot") {
          return { data: true };
        }
        return { data: true };
      })();
      const result = options.rpc?.[fn]?.[index] ?? defaultResult;
      if (result.neverResolves) return new Promise<never>(() => {});
      if (
        fn === "record_practice_debrief" &&
        options.rpc?.[fn]?.[index] === undefined &&
        !result.error
      ) {
        state.debriefCount++;
      }
      return Promise.resolve(
        result.error
          ? { data: null, error: { message: result.error } }
          : { data: result.data ?? null, error: null },
      );
    },
  };

  const deepSeek: DeepSeekCaller = (args) => {
    state.deepSeekCalls.push(args);
    state.events.push("deepseek");
    const reply = options.deepSeekReplies?.[deepSeekIndex] ?? "AI reply";
    deepSeekIndex++;
    if (reply instanceof Error) {
      return Promise.reject(reply);
    }
    return Promise.resolve(reply);
  };
  const claude: ClaudeCaller = (args) => {
    state.claudeCalls.push(args);
    state.events.push("claude");
    const reply = options.claudeReplies?.[claudeIndex] ?? "AI reply";
    claudeIndex++;
    // Phase 4.4：只有 chat 路由那條路會傳 onUsage（hint／debrief 不傳），固定值
    // 讓 telemetry 可重現。時序與 production 的 `callClaude` 一致：provider 回了
    // usage 就記帳（含 200 但丟錯），連線層失敗（逾時／HTTP 錯）則完全不記。
    const emitUsage = () =>
      args.onUsage?.({
        inputTokens: 120,
        cacheReadInputTokens: 80,
        cacheCreationInputTokens: 0,
        outputTokens: 15,
      });
    if (reply instanceof Error) {
      if (options.claudeUsageBeforeError) emitUsage();
      return Promise.reject(reply);
    }
    emitUsage();
    return Promise.resolve(reply);
  };
  // reviewer 整層已拆：deps 不再有 semanticAdjudicate；state.semanticCalls
  // 保留為永遠空陣列，讓「reviewer 零呼叫」斷言持續守住。
  return {
    state,
    handler: createPracticeChatHandler({
      createSupabaseClient: () => client as PracticeSupabaseClient,
      callDeepSeek: deepSeek,
      callClaude: claude,
      getEnv: (name) => {
        if (Object.hasOwn(options.env ?? {}, name)) return options.env?.[name];
        if (name === "DEEPSEEK_API_KEY") return "deepseek-key";
        if (name === "CLAUDE_API_KEY" && options.claudeReplies) {
          return "claude-key";
        }
        return "";
      },
      now: () => NOW,
      monotonicNow: options.monotonicNowValues
        ? () => {
          const values = options.monotonicNowValues!;
          const value = values[Math.min(monotonicNowIndex, values.length - 1)];
          monotonicNowIndex += 1;
          return value;
        }
        : undefined,
      randomUUID: () => options.randomUUID ?? "generation-token-1",
      waitUntil: (task) => state.backgroundTasks.push(task),
      telemetryPersistTimeoutMs: options.aiLogsNeverCompletes ? 5 : undefined,
    }),
  };
}

export async function run(options: FakeOptions, body: unknown = chatBody()) {
  const fake = makeFake(options);
  const response = await fake.handler(makeRequest(body));
  const json = await response.json();
  return { ...fake, response, json };
}

export async function sha256HexOf(text: string | Uint8Array): Promise<string> {
  const bytes = typeof text === "string"
    ? new TextEncoder().encode(text)
    : text;
  const digest = await crypto.subtle.digest(
    "SHA-256",
    bytes.buffer.slice(
      bytes.byteOffset,
      bytes.byteOffset + bytes.byteLength,
    ) as ArrayBuffer,
  );
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
