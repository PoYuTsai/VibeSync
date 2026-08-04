// Tier 2 批 1.5：漏斗埋點驗證 + 建 row 純函式。
// index.ts 只負責 dispatch 與 insert；本檔可單測。
//
// 白名單真相源：docs/integrations/funnel-events-v1.md。改字典必須同一批
// commit 同步改本檔與 client FunnelTracker（鍵盤案教訓：白名單漂移）。
// 隱私鐵則：properties 只收下表鍵；對話內容、對象名、自由文字絕不落庫。

const PAGE_INDEX_MAX = 20;
const GOALS_COUNT_MAX = 5;
const SEEDS_COUNT_MAX = 5;
const STRING_VALUE_MAX = 40;

const CHECKLIST_ITEMS = new Set([
  "profile",
  "first_action",
  "keyboard",
]);

const ABOUT_ME_SOURCES = new Set([
  "checklist",
  "card",
  "settings",
]);

type PropSpec = { kind: "int"; max: number } | { kind: "bool" } | {
  kind: "enum";
  values: Set<string>;
};

const PROP_SPECS: Record<string, PropSpec> = {
  page_index: { kind: "int", max: PAGE_INDEX_MAX },
  goals_count: { kind: "int", max: GOALS_COUNT_MAX },
  seeds_count: { kind: "int", max: SEEDS_COUNT_MAX },
  has_partner: { kind: "bool" },
  has_style: { kind: "bool" },
  has_notes: { kind: "bool" },
  has_custom_topics: { kind: "bool" },
  item: { kind: "enum", values: CHECKLIST_ITEMS },
  source: { kind: "enum", values: ABOUT_ME_SOURCES },
};

/** event → 允許的 properties 鍵。字典外 event 一律 400。 */
export const FUNNEL_EVENT_PROPS: Record<string, readonly string[]> = {
  onboarding_page_view: ["page_index"],
  onboarding_skip: ["page_index"],
  onboarding_branch_answer: ["has_partner"],
  onboarding_questionnaire_submit: ["goals_count"],
  quota_strip_tap: [],
  opener_entry_tap: [],
  coach_entry_tap: ["has_partner"],
  first_analysis_completed: [],
  first_practice_completed: [],
  keyboard_setup_shown: [],
  keyboard_setup_completed: [],
  checklist_item_done: ["item"],
  about_me_opened: ["source"],
  about_me_saved: [
    "has_style",
    "goals_count",
    "seeds_count",
    "has_notes",
    "has_custom_topics",
  ],
  about_me_cleared: [],
};

export interface FunnelRow {
  user_id: string;
  event: string;
  properties: Record<string, unknown>;
  client_ts?: string;
}

export type BuildFunnelResult =
  | { ok: true; row: FunnelRow }
  | { ok: false; error: string };

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

// 值不合 spec → null（呼叫端剝除整鍵），絕不拋錯。
function sanitizeValue(spec: PropSpec, value: unknown): unknown {
  switch (spec.kind) {
    case "int":
      if (typeof value !== "number" || !Number.isInteger(value)) return null;
      if (value < 0 || value > spec.max) return null;
      return value;
    case "bool":
      return typeof value === "boolean" ? value : null;
    case "enum": {
      if (typeof value !== "string") return null;
      const trimmed = value.trim().slice(0, STRING_VALUE_MAX);
      return spec.values.has(trimmed) ? trimmed : null;
    }
  }
}

/**
 * 從信任的 userId + 不信任的 client rawEvent 建出可 insert 的 funnel row。
 * 字典外 event → 拒絕；properties 只留該 event 白名單內且值合規的鍵。
 */
export function buildFunnelRow(
  userId: string,
  rawEvent: unknown,
): BuildFunnelResult {
  if (!isPlainObject(rawEvent)) {
    return { ok: false, error: "Invalid funnel event" };
  }

  const event = rawEvent.event;
  if (typeof event !== "string" || !(event in FUNNEL_EVENT_PROPS)) {
    return { ok: false, error: "Unknown funnel event" };
  }

  const allowedKeys = FUNNEL_EVENT_PROPS[event];
  const rawProps = isPlainObject(rawEvent.properties)
    ? rawEvent.properties
    : {};
  const properties: Record<string, unknown> = {};
  for (const key of allowedKeys) {
    if (!(key in rawProps)) continue;
    const spec = PROP_SPECS[key];
    if (!spec) continue;
    const sanitized = sanitizeValue(spec, rawProps[key]);
    if (sanitized !== null) properties[key] = sanitized;
  }

  const row: FunnelRow = { user_id: userId, event, properties };

  if (typeof rawEvent.clientTs === "string") {
    const parsed = new Date(rawEvent.clientTs);
    if (!Number.isNaN(parsed.getTime())) {
      row.client_ts = parsed.toISOString();
    }
  }

  return { ok: true, row };
}
