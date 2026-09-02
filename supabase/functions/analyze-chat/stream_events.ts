// supabase/functions/analyze-chat/stream_events.ts
//
// Pure typed-event helpers for the full streaming analyze path.

export const STREAM_STYLES = [
  "extend",
  "resonate",
  "tease",
  "humor",
  "coldRead",
] as const;

export type StreamStyle = typeof STREAM_STYLES[number];

export const STREAM_EVENT_TYPES = [
  "analysis.started",
  "analysis.progress",
  // 球數案修法二：盤點逼進輸出契約（軟版）。模型最先 emit 列全 N 球各標
  // 接/併/略，機制＝強迫分類在選球之前。known-optional：reframer 純放行、
  // 不驗證、不碰丟段路徑；App default:break 可忽略不渲染。
  "analysis.inventory",
  "analysis.decision",
  // Phase 2a shadow：send 決策後模型先吐發散計畫（DivergencePlanV1）。server
  // 只驗 shape、存快照、記 telemetry，不拿它改回覆；App default:break 忽略。
  "analysis.divergence_plan",
  "analysis.recommendation",
  "analysis.reply_option",
  "analysis.metrics",
  "analysis.coach_hint",
  "analysis.report_section",
  "analysis.done",
  "analysis.error",
] as const;

export type StreamEventType = typeof STREAM_EVENT_TYPES[number];

export type StreamEvent = {
  type: StreamEventType;
  [key: string]: unknown;
};

const STREAM_STYLE_SET = new Set<string>(STREAM_STYLES);
const STREAM_EVENT_TYPE_SET = new Set<string>(STREAM_EVENT_TYPES);

export function isStreamStyle(value: unknown): value is StreamStyle {
  return typeof value === "string" && STREAM_STYLE_SET.has(value);
}

export function isStreamEventType(value: unknown): value is StreamEventType {
  return typeof value === "string" && STREAM_EVENT_TYPE_SET.has(value);
}

export interface ParseEventLineOptions {
  /// Phase 2a：只有 v2 請求認得 `analysis.divergence_plan`。v1 在解析層就
  /// 把它當成過去的 unknown line（回 null），不產生任何已辨識事件。
  readonly divergencePlan?: boolean;
}

/// Sonnet 5 在計畫第三枝偶發把 `"sourceIndex":1` 寫成 `"sourceIndex=1"`
/// （2026-09-02 黑箱，約 1/6 份計畫），整行 JSON 壞掉。只對 v2 的
/// divergence_plan 行、只對這個精確形態修一次；其他 JSON 錯誤照舊當 unknown line。
const DIVERGENCE_PLAN_LINE_PREFIX = '{"type":"analysis.divergence_plan"';
const SOURCE_INDEX_EQUALS_GLITCH = /"sourceIndex=(\d+)"/g;

function repairDivergencePlanLineGlitch(line: string): string | null {
  if (!line.startsWith(DIVERGENCE_PLAN_LINE_PREFIX)) return null;
  if (!SOURCE_INDEX_EQUALS_GLITCH.test(line)) return null;
  SOURCE_INDEX_EQUALS_GLITCH.lastIndex = 0;
  return line.replace(SOURCE_INDEX_EQUALS_GLITCH, '"sourceIndex":$1');
}

export function parseEventLine(
  line: string,
  options: ParseEventLineOptions = {},
): StreamEvent | null {
  const trimmed = line.trim();
  if (!trimmed) return null;

  let parsed: unknown;
  try {
    parsed = JSON.parse(trimmed);
  } catch {
    const repaired = options.divergencePlan
      ? repairDivergencePlanLineGlitch(trimmed)
      : null;
    if (repaired === null) return null;
    try {
      parsed = JSON.parse(repaired);
    } catch {
      return null;
    }
    console.log("[divergence_plan] repaired line glitch: sourceIndex=");
  }

  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    return null;
  }

  const record = parsed as Record<string, unknown>;
  if (!isStreamEventType(record.type)) {
    return null;
  }
  if (record.type === "analysis.divergence_plan" && !options.divergencePlan) {
    return null;
  }

  return record as StreamEvent;
}
