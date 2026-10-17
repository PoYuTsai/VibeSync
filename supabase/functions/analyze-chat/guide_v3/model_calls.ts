// v3 兩段的正式模型呼叫：讀局面走非串流＋json_schema（callClaudeWithFallback），
// 寫卡走串流（callClaudeStreaming）。兩段各一個 ModelCallBudget（各最多 3 次
// provider 呼叫），每次呼叫交一列 ai_logs 給 recordAiCall（背景寫入，不擋回應）。
import { SONNET_5_5_MODEL } from "../../_shared/model_request_params.ts";
import { callClaudeWithFallback, extractClaudeText } from "../fallback.ts";
import {
  attemptReporter,
  ModelCallBudget,
  type ProviderAttemptLogEntry,
} from "../model_call_budget.ts";
import { callClaudeStreaming } from "../streaming_fallback.ts";
import { GUIDE_V3_VERSION } from "./guide_text.ts";
import type {
  GuideV3ReadRequest,
  GuideV3StreamDeps,
  GuideV3WriteRequest,
} from "./stream_flow.ts";

/// 原型黑箱（10/14–10/15）跑的是 Sonnet 5.5；備援鏈照共用設定（5.5→5→4.6）。
export const GUIDE_V3_MODEL = SONNET_5_5_MODEL;
/// 可見輸出預算（5.5 另加思考餘裕，見 maxTokensFor）；跟原型一樣。
export const GUIDE_V3_READ_MAX_TOKENS = 1500;
export const GUIDE_V3_WRITE_MAX_TOKENS = 2500;
const READ_ATTEMPT_TIMEOUT_MS = 30_000;

export function createGuideV3ModelCalls(args: {
  readonly apiKey: string;
  readonly requestType: string;
  readonly tier: string;
  readonly recordAiCall?: (entry: ProviderAttemptLogEntry) => void;
  readonly model?: string;
}): Pick<GuideV3StreamDeps, "callRead" | "callWrite"> {
  const model = args.model ?? GUIDE_V3_MODEL;
  const budget = (stage: "read" | "write", runId: string, deadline: number) =>
    new ModelCallBudget(
      deadline,
      {
        stage,
        operation: runId,
        flowVersion: `guide_${GUIDE_V3_VERSION}`,
        tier: args.tier,
      },
      attemptReporter(
        "guide_v3_provider_attempt",
        args.requestType,
        args.recordAiCall,
        { responseMode: "stream" },
      ),
    );
  return {
    async callRead(req: GuideV3ReadRequest) {
      const result = await callClaudeWithFallback(
        {
          model,
          max_tokens: GUIDE_V3_READ_MAX_TOKENS,
          system: req.system,
          messages: [{ role: "user", content: req.user }],
          output_config: {
            format: { type: "json_schema", schema: req.schema },
          },
        },
        args.apiKey,
        {
          timeout: Math.max(
            1,
            Math.min(READ_ATTEMPT_TIMEOUT_MS, req.deadlineAtMs - Date.now()),
          ),
          maxRetries: 1,
          allowModelFallback: true,
          budget: budget("read", req.runId, req.deadlineAtMs),
          purpose: "guide_v3_read",
          absoluteDeadlineAtMs: req.deadlineAtMs,
        },
      );
      return { text: extractClaudeText(result.data), model: result.model };
    },
    async callWrite(req: GuideV3WriteRequest) {
      const claude = await callClaudeStreaming(
        {
          model,
          max_tokens: GUIDE_V3_WRITE_MAX_TOKENS,
          system: req.system,
          messages: [{ role: "user", content: req.user }],
        },
        args.apiKey,
        {
          timeout: Math.max(1, req.deadlineAtMs - Date.now()),
          absoluteDeadlineAtMs: req.deadlineAtMs,
          budget: budget("write", req.runId, req.deadlineAtMs),
          purpose: "guide_v3_write",
        },
      );
      return { model: claude.model, textStream: claude.textStream };
    },
  };
}
