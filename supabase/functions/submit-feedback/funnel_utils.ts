// Tier 2 批 1.5：漏斗埋點驗證 + 建 row 純函式。
// index.ts 只負責 dispatch 與 insert；本檔可單測。
//
// 白名單真相源：docs/integrations/funnel-events-v1.md。改字典必須同一批
// commit 同步改本檔與 client FunnelTracker（鍵盤案教訓：白名單漂移）。
// 隱私鐵則：properties 只收下表鍵；對話內容、對象名、自由文字絕不落庫。

const PAGE_INDEX_MAX = 20;
const GOALS_COUNT_MAX = 5;
const SEEDS_COUNT_MAX = 5;
// 鎖卡區塊出現時至少鎖 1 張，排卡最多 5 張（Eric 2026-10-18）。
const LOCKED_COUNT_MIN = 1;
const LOCKED_COUNT_MAX = 5;
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

// 付費頁從哪裡打開（對應 app 的 PaywallEntry）。
const PAYWALL_ENTRIES = new Set([
  "general",
  "locked_cards",
  "quota_exhausted",
]);

// 買到的付費方案；free 不是購買結果，不收。
const PAID_TIERS = new Set([
  "starter",
  "essential",
]);

// 額度不足事件（onboarding 轉換第 6 步）：哪個功能、哪一種額度、誰先擋下。
const QUOTA_BLOCK_FEATURES = new Set([
  "analyze",
  "opener",
  "new_topic",
  "coach",
  "practice",
  "keyboard",
]);

// App 分不出每日或每月時送 unknown。
const QUOTA_BLOCK_SCOPES = new Set([
  "daily",
  "monthly",
  "unknown",
]);

// precheck＝App 先擋（請求沒送出）；server＝伺服器回 429／402 或鍵盤的額度訊號。
const QUOTA_BLOCK_SOURCES = new Set([
  "precheck",
  "server",
]);

// 只拿來比對、不落庫的鍵（主審 r2 P2；Eric 2026-10-18 核准）：購買事件帶開始購買
// 時的帳號。認證權杖在送出當下才取，付款確認期間換了帳號，事件就會用到別人的登入；
// 跟登入的不同就整筆拒絕。row 的 user_id 本來就是帳號，驗完不存。
const PURCHASER_KEY = "purchaser";
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// int 的 min 沒寫就是 0。
type PropSpec =
  | { kind: "int"; min?: number; max: number }
  | { kind: "bool" }
  | { kind: "enum"; values: Set<string> };

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
  is_recommended: { kind: "bool" },
  entry: { kind: "enum", values: PAYWALL_ENTRIES },
  tier: { kind: "enum", values: PAID_TIERS },
  locked_count: {
    kind: "int",
    min: LOCKED_COUNT_MIN,
    max: LOCKED_COUNT_MAX,
  },
  feature: { kind: "enum", values: QUOTA_BLOCK_FEATURES },
  scope: { kind: "enum", values: QUOTA_BLOCK_SCOPES },
  // 不叫 source：這張表以鍵名全域共用值域，source 已經是 about_me_opened 的鍵。
  block_source: { kind: "enum", values: QUOTA_BLOCK_SOURCES },
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
  new_topic_copied: ["is_recommended"],
  paywall_opened: ["entry"],
  paywall_purchase_completed: ["tier", "entry", PURCHASER_KEY],
  locked_cards_upgrade_tap: ["locked_count"],
  quota_block_shown: ["feature", "scope", "block_source"],
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
      if (value < (spec.min ?? 0) || value > spec.max) return null;
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
 * 字典外 event → 拒絕；購買事件的 purchaser 不是登入帳號 → 拒絕；
 * properties 只留該 event 白名單內且值合規的鍵（purchaser 不存）。
 */
export function buildFunnelRow(
  userId: string,
  rawEvent: unknown,
): BuildFunnelResult {
  if (!isPlainObject(rawEvent)) {
    return { ok: false, error: "Invalid funnel event" };
  }

  // 只認字典、白名單自己的鍵（主審 r1 P2）：用 in 的話 toString、constructor
  // 這類原型上的名字也會過，接著取到函式而丟錯，端點回 500；字典外要一律 400。
  const event = rawEvent.event;
  if (typeof event !== "string" || !Object.hasOwn(FUNNEL_EVENT_PROPS, event)) {
    return { ok: false, error: "Unknown funnel event" };
  }

  const allowedKeys = FUNNEL_EVENT_PROPS[event];
  const rawProps = isPlainObject(rawEvent.properties)
    ? rawEvent.properties
    : {};
  if (allowedKeys.includes(PURCHASER_KEY)) {
    const purchaser = Object.hasOwn(rawProps, PURCHASER_KEY)
      ? rawProps[PURCHASER_KEY]
      : undefined;
    if (
      typeof purchaser !== "string" ||
      !UUID_PATTERN.test(purchaser) ||
      purchaser !== userId
    ) {
      return { ok: false, error: "Funnel purchaser mismatch" };
    }
  }

  const properties: Record<string, unknown> = {};
  for (const key of allowedKeys) {
    if (key === PURCHASER_KEY) continue; // 只比對，不落庫
    if (!Object.hasOwn(rawProps, key)) continue;
    if (!Object.hasOwn(PROP_SPECS, key)) continue;
    const spec = PROP_SPECS[key];
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
