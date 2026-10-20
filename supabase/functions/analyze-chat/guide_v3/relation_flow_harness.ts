// 關係訊號測試共用的流程替身：把錄音（或改過幾個標記的錄音）餵進正式的 handleGuideV3Stream，
// 時間固定、不呼叫模型、不連網，收集事件、扣費、落帳、送給模型的提示詞與 log。給
// relation_flag_off_test.ts 與 relation_flow_test.ts 共用；入口不載入，不隨函式部署。
import fixtures from "../testdata/guide_v3_replay_fixtures.json" with {
  type: "json",
};
import type { AnalysisStreamRun } from "../stream_run_store.ts";
import { GUIDE_V3_VERSION } from "./guide_text.ts";
import { type GuideV3StreamDeps, handleGuideV3Stream } from "./stream_flow.ts";

export const RELATION_FLOW_T0 = Date.parse("2026-10-16T00:00:00.000Z");

export interface FlowCase {
  readonly name: string;
  readonly messages: readonly { isFromMe: boolean; content: string }[];
  readonly readText: string;
  readonly writeText: string;
}

async function* stream(parts: readonly string[]): AsyncGenerator<string> {
  for (const part of parts) yield part;
}

/// 流程跑完後，送出的、存的、記的都收進 outcome（JSON 化，跟資料庫存的一樣丟掉 undefined）；
/// run 是扣費、結案之後資料庫裡那一列的樣子（續看與重組用）。
export async function runFlowWithRun(
  flowCase: FlowCase,
  extra: Partial<GuideV3StreamDeps>,
): Promise<{ outcome: Record<string, unknown>; run: AnalysisStreamRun }> {
  const T0 = RELATION_FLOW_T0;
  const calls: string[] = [];
  const charges: unknown[] = [];
  const logs: unknown[] = [];
  const requests: Record<string, unknown> = {};
  let markDone: unknown = null;
  let run: AnalysisStreamRun = {
    id: "flow-run",
    user_id: "flow-user",
    conversation_hash: "flow-hash",
    status: "pending",
    selected_style: null,
    decision_kind: null,
    card_task: null,
    recommendation_json: null,
    final_result_json: null,
    charged_at: null,
    last_error_code: null,
    retry_count: 0,
    request_context: { guideVersion: GUIDE_V3_VERSION },
    created_at: new Date(T0).toISOString(),
    expires_at: new Date(T0 + 30 * 60_000).toISOString(),
  };
  const response = await handleGuideV3Stream({
    store: {
      getRun: () => Promise.resolve(run),
      createPendingRun: (args) => {
        calls.push("createPendingRun");
        requests.requestContext = args.requestContext;
        return Promise.resolve(run);
      },
      chargeRunV3: (input) => {
        calls.push(`charge:${input.decisionKind}:${input.cardTask}`);
        charges.push(input);
        run = {
          ...run,
          status: "charged",
          charged_at: new Date(T0).toISOString(),
          card_task: input.cardTask,
          decision_kind: input.decisionKind,
          recommendation_json: input.recommendationJson,
        };
        return Promise.resolve(run);
      },
      markDone: (args) => {
        calls.push("markDone");
        markDone = args.finalResult;
        run = { ...run, status: "done", final_result_json: args.finalResult };
        return Promise.resolve(run);
      },
      markFailedIfPending: (args) => {
        calls.push(`markFailedIfPending:${args.code}`);
        if (run.status !== "pending" || run.charged_at !== null) {
          return Promise.resolve(null);
        }
        run = { ...run, status: "failed", last_error_code: args.code };
        return Promise.resolve(run);
      },
    },
    userId: "flow-user",
    analysisRunId: null,
    conversationHash: "flow-hash",
    messages: flowCase.messages,
    requestType: "analyze",
    effectiveTier: "essential",
    accountIsTest: false,
    quotaUsage: {
      shouldChargeQuota: true,
      quotaReason: "analyze_message_based",
      quotaUnit: "messages",
      chargedMessageCount: 2,
      estimatedMessageCount: 2,
    },
    monthlyLimit: 800,
    dailyLimit: 120,
    subMonthlyUsed: 0,
    subDailyUsed: 0,
    callRead: (req) => {
      calls.push("read");
      requests.read = {
        system: req.system,
        user: req.user,
        schema: req.schema,
      };
      return Promise.resolve({
        text: flowCase.readText,
        model: "claude-sonnet-5-5",
      });
    },
    callWrite: (req) => {
      calls.push("write");
      requests.write = { system: req.system, user: req.user };
      return Promise.resolve({
        model: "claude-sonnet-5-5",
        textStream: stream(flowCase.writeText.match(/[^\n]*\n|[^\n]+$/g) ?? []),
      });
    },
    log: (event, metadata, level) => logs.push({ event, metadata, level }),
    now: () => T0,
    heartbeatIntervalMs: 0,
    ...extra,
  });
  const text = await response.text();
  const outcome = JSON.parse(JSON.stringify({
    status: response.status,
    events: text.split("\n").filter(Boolean).map((l) => JSON.parse(l)),
    calls,
    charges,
    markDone,
    requests,
    logs,
  }));
  return { outcome, run: JSON.parse(JSON.stringify(run)) };
}

export async function runFlow(
  flowCase: FlowCase,
  extra: Partial<GuideV3StreamDeps> = {},
): Promise<Record<string, unknown>> {
  return (await runFlowWithRun(flowCase, extra)).outcome;
}

export function fixtureCase(name: string): FlowCase {
  const found = fixtures.cases.find((c) => c.name === name);
  if (!found) throw new Error(`no replay fixture ${name}`);
  return found;
}

/// 錄音裡的讀局面輸出改幾個標記，做出錄音沒有的決定或欄位（停、自傷關心、未成年、關係訊號）。
export function withReadTags(
  name: string,
  over: Record<string, unknown>,
): FlowCase {
  const base = fixtureCase(name);
  return {
    ...base,
    name: `${name}+${Object.keys(over).join("+")}`,
    readText: JSON.stringify({ ...JSON.parse(base.readText), ...over }),
  };
}
