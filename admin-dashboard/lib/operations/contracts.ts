// 後台營運 B0 共用契約（凍結）：時區、freshness、health、incident、decision card。
// 規則核心：缺資料一律回 "unknown"，不得顯示成 healthy 或數字 0。
// 資料庫存 timestamptz（UTC）；所有「哪一天」的判斷都以 Asia/Taipei 為準。

export const OPS_TIMEZONE = "Asia/Taipei";

export type Freshness = "fresh" | "stale" | "unknown";

export type HealthStatus = "unknown" | "healthy" | "degraded";

/** 對應 admin_ops_incidents。detail 只放匿名結構化摘要，禁止個資與原文。 */
export interface Incident {
  id: string;
  source: string;
  severity: "info" | "warning" | "critical";
  status: "open" | "resolved";
  title: string;
  detail: Record<string, unknown>;
  openedAt: string;
  resolvedAt: string | null;
  createdAt: string;
}

/** 對應 admin_ops_decision_cards。 */
export interface DecisionCard {
  id: string;
  incidentId: string | null;
  kind: string;
  summary: string;
  options: unknown[];
  decidedOption: string | null;
  decidedAt: string | null;
  createdAt: string;
}

const taipeiDayFormat = new Intl.DateTimeFormat("en-CA", {
  timeZone: OPS_TIMEZONE,
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
});

/** 回傳該時刻在 Asia/Taipei 的日期 key（YYYY-MM-DD）。 */
export function taipeiDayKey(instant: Date): string {
  return taipeiDayFormat.format(instant);
}

/** 缺值或無法解析的時間戳一律 unknown；超過 staleAfterMs 為 stale。 */
export function resolveFreshness(
  lastSeenAt: string | Date | null | undefined,
  now: Date,
  staleAfterMs: number,
): Freshness {
  if (lastSeenAt == null) return "unknown";
  const seen =
    lastSeenAt instanceof Date ? lastSeenAt.getTime() : Date.parse(lastSeenAt);
  if (!Number.isFinite(seen)) return "unknown";
  return now.getTime() - seen > staleAfterMs ? "stale" : "fresh";
}

export interface HealthSample {
  observedAt: string | Date | null;
  isDegraded: boolean;
}

/**
 * 缺 sample 或時間無法判讀 → unknown。
 * stale 的壞消息仍算 degraded；stale 的好消息不得宣稱 healthy → unknown。
 */
export function resolveHealth(
  sample: HealthSample | null | undefined,
  now: Date,
  staleAfterMs: number,
): HealthStatus {
  if (!sample) return "unknown";
  const freshness = resolveFreshness(sample.observedAt, now, staleAfterMs);
  if (freshness === "unknown") return "unknown";
  if (sample.isDegraded) return "degraded";
  return freshness === "fresh" ? "healthy" : "unknown";
}
