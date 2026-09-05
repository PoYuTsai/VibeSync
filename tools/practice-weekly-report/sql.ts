// 練習室週報的 SQL 產生器（Phase 5 WP1）。
//
// 這支只組字串、不打網路。所有語句都必須是單一 SELECT——`assertReadOnlySql`
// 是程式內的守門，report.ts 在送出前對每一條語句再叫一次，所以就算之後有人
// 在這裡不小心寫出寫入語句，也會在送到 Management API 之前就炸掉。

export interface DateRange {
  /** 起日（含），ISO `YYYY-MM-DD`，以 UTC 00:00 為界。 */
  readonly from: string;
  /** 迄日（不含），ISO `YYYY-MM-DD`，以 UTC 00:00 為界。 */
  readonly to: string;
}

/** `MAX_AI_REPLIES = 20`（handler.ts）＝現行一場的 AI 回合上限。 */
export const MAX_TURNS = 20;

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

const WRITE_KEYWORDS =
  /\b(insert|update|delete|drop|alter|truncate|create|grant|revoke|merge|copy|vacuum|call|do|set|refresh|comment)\b/i;

function assertIsoDate(value: string): string {
  if (!ISO_DATE.test(value)) {
    throw new Error(`invalid_date: ${value}`);
  }
  return value;
}

/**
 * 唯讀守門：只放行單一、以 SELECT 開頭、不含任何寫入關鍵字的語句。
 *
 * 關鍵字用 `\b` 邊界比對，所以 `created_at`／`updated_at` 這種欄位名不會被
 * 誤判（`create` 後面接 `d` 仍是字元，邊界不成立）。分號一律擋掉，避免
 * 「SELECT 1; DROP ...」這種夾帶。
 */
export function assertReadOnlySql(sql: string): string {
  const trimmed = sql.trim();
  if (!trimmed) throw new Error("read_only_guard: empty statement");
  if (!/^select\b/i.test(trimmed)) {
    throw new Error(`read_only_guard: statement must start with SELECT`);
  }
  if (trimmed.includes(";")) {
    throw new Error("read_only_guard: semicolon is not allowed");
  }
  const match = WRITE_KEYWORDS.exec(trimmed);
  if (match) {
    throw new Error(`read_only_guard: forbidden keyword ${match[0]}`);
  }
  return sql;
}

/** 預設時間窗：`to` 為給定日期（不含），`from` 為往前 7 天。 */
export function defaultRange(now: Date = new Date()): DateRange {
  const to = new Date(Date.UTC(
    now.getUTCFullYear(),
    now.getUTCMonth(),
    now.getUTCDate(),
  ));
  const from = new Date(to.getTime() - 7 * 24 * 60 * 60 * 1000);
  return {
    from: from.toISOString().slice(0, 10),
    to: to.toISOString().slice(0, 10),
  };
}

/**
 * 場次帳本：`practice_chat_sessions` 一列＝一場。按 `practice_mode` ×
 * `ai_count` 分組，讓 aggregate 端同時算得出場次、回合直方圖、提示／檢討
 * 次數與扣費場次。
 */
export function buildSessionsSql(range: DateRange): string {
  const from = assertIsoDate(range.from);
  const to = assertIsoDate(range.to);
  return assertReadOnlySql(
    `SELECT practice_mode,
       ai_count,
       count(*)::int AS sessions,
       coalesce(sum(hint_count), 0)::int AS hints,
       coalesce(sum(debrief_count), 0)::int AS debriefs,
       (count(*) FILTER (WHERE charged))::int AS charged
FROM public.practice_chat_sessions
WHERE created_at >= '${from} 00:00:00+00'::timestamptz
  AND created_at < '${to} 00:00:00+00'::timestamptz
GROUP BY practice_mode, ai_count
ORDER BY practice_mode, ai_count`,
  );
}

/**
 * 生成帳本：`ai_logs` 只有 hint／debrief 兩種練習室列（聊天回合不寫 DB）。
 * `input_tokens`／`output_tokens` 在寫入端固定是 0（telemetry.ts 的隱私邊界），
 * 所以成本只能用「呼叫次數 × 單次估價」，不是真 token 數；`retry_count` 是
 * 同一列內的重試次數，要加進呼叫數才對得回 Anthropic console。
 */
export function buildAiLogsSql(range: DateRange): string {
  const from = assertIsoDate(range.from);
  const to = assertIsoDate(range.to);
  return assertReadOnlySql(
    `SELECT request_body->>'mode' AS mode,
       request_body->>'practiceMode' AS practice_mode,
       model,
       status,
       fallback_used,
       count(*)::int AS call_rows,
       coalesce(sum(retry_count), 0)::int AS retries
FROM public.ai_logs
WHERE created_at >= '${from} 00:00:00+00'::timestamptz
  AND created_at < '${to} 00:00:00+00'::timestamptz
  AND request_type LIKE 'practice\\_%'
GROUP BY 1, 2, 3, 4, 5
ORDER BY 1, 2, 3, 4`,
  );
}
