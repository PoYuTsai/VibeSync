// v3 兩段的正式模型呼叫：讀局面走非串流＋json_schema（callClaudeWithFallback），
// 寫卡走串流（callClaudeStreaming）。兩段各一個 ModelCallBudget（各最多 3 次
// provider 呼叫），每次呼叫交一列 ai_logs 給 recordAiCall（背景寫入，不擋回應）。
// 對象記憶（開關開才有）另一個 ModelCallBudget，只打一次、不換模型。
// 兩段式實驗的說明步驟（開關 ANALYZE_GUIDE_V3_TWO_STAGE 開才有）：同一個模型、同一條備援鏈，
// 自己一個 ModelCallBudget（stage explain，最多 3 次），ai_logs 另記 request_type。
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
  GuideV3ExplainRequest,
  GuideV3ExtractRequest,
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

/// 對象記憶用 Haiku 5.5：每個候選都要對到她的原句才留，模型弱只會少記、不會記錯。
/// 單價在 logger.ts 與 _shared/model_pricing.ts 都有；備援鏈沒有 Haiku 5.5，也不需要。
export const GUIDE_V3_MEMORY_MODEL = "claude-haiku-5-5";
/// 三類各 5 項、每項 2 句原句加兩個判斷欄位，上限大約 1400 token；超過就是這次沒有記憶。
export const GUIDE_V3_MEMORY_MAX_TOKENS = 1500;
/// ai_logs 的 request_type：跟分析本身的那幾列分開算成本。
export const GUIDE_V3_MEMORY_REQUEST_TYPE = "analyze_memory";
const MEMORY_ATTEMPT_TIMEOUT_MS = 15_000;

/// 說明步驟：每張卡一兩句，5 張大約 600 token；5.5 另加思考餘裕（maxTokensFor）。
export const GUIDE_V3_EXPLAIN_MAX_TOKENS = 1200;
/// ai_logs 的 request_type：說明不扣用戶額度，成本跟分析本身的那幾列分開算。
export const GUIDE_V3_EXPLAIN_REQUEST_TYPE = "analyze_explain";
const EXPLAIN_ATTEMPT_TIMEOUT_MS = 15_000;

export function createGuideV3ModelCalls(args: {
  readonly apiKey: string;
  readonly requestType: string;
  readonly tier: string;
  readonly recordAiCall?: (entry: ProviderAttemptLogEntry) => void;
  readonly model?: string;
  /// 開關 ANALYZE_GUIDE_V3_MEMORY 允許時才給 callExtract；沒給就不會多打這一次。
  readonly memory?: boolean;
  /// 黑箱比較模型用；正式路徑一律 GUIDE_V3_MEMORY_MODEL。
  readonly memoryModel?: string;
  /// 開關 ANALYZE_GUIDE_V3_TWO_STAGE 允許時才給 callExplain；沒給就不會多打這一次。
  readonly explain?: boolean;
}): Pick<
  GuideV3StreamDeps,
  "callRead" | "callWrite" | "callExtract" | "callExplain"
> {
  const model = args.model ?? GUIDE_V3_MODEL;
  const budget = (
    stage: "read" | "write" | "memory" | "explain",
    runId: string,
    deadline: number,
    requestType = args.requestType,
  ) =>
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
        requestType,
        args.recordAiCall,
        { responseMode: "stream" },
      ),
    );
  const callExtract = async (req: GuideV3ExtractRequest) => {
    const result = await callClaudeWithFallback(
      {
        model: args.memoryModel ?? GUIDE_V3_MEMORY_MODEL,
        max_tokens: GUIDE_V3_MEMORY_MAX_TOKENS,
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
          Math.min(MEMORY_ATTEMPT_TIMEOUT_MS, req.deadlineAtMs - Date.now()),
        ),
        maxRetries: 1,
        // 記憶是附加的：失敗就這次沒有，不重試、不換模型（最多一次 provider 呼叫）。
        allowModelFallback: false,
        budget: budget(
          "memory",
          req.runId,
          req.deadlineAtMs,
          GUIDE_V3_MEMORY_REQUEST_TYPE,
        ),
        purpose: "guide_v3_memory",
        absoluteDeadlineAtMs: req.deadlineAtMs,
      },
    );
    return { text: extractClaudeText(result.data), model: result.model };
  };
  const callExplain = async (req: GuideV3ExplainRequest) => {
    const result = await callClaudeWithFallback(
      {
        model,
        max_tokens: GUIDE_V3_EXPLAIN_MAX_TOKENS,
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
          Math.min(EXPLAIN_ATTEMPT_TIMEOUT_MS, req.deadlineAtMs - Date.now()),
        ),
        maxRetries: 1,
        allowModelFallback: true,
        budget: budget(
          "explain",
          req.runId,
          req.deadlineAtMs,
          GUIDE_V3_EXPLAIN_REQUEST_TYPE,
        ),
        purpose: "guide_v3_explain",
        absoluteDeadlineAtMs: req.deadlineAtMs,
      },
    );
    return { text: extractClaudeText(result.data), model: result.model };
  };
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
    ...(args.memory ? { callExtract } : {}),
    ...(args.explain ? { callExplain } : {}),
  };
}
