// Phase 2a：DivergencePlanV1（規格 §5.12）shape 守門。shadow-only——server
// 只驗 shape、存快照、出 telemetry，不拿它改回覆。球用 inventory 既有的
// 1-based sourceIndex 指認，不另發 ball id。

import { isStreamStyle, type StreamStyle } from "./stream_events.ts";

export const DIVERGENCE_METHODS = [
  "semantic_decomposition",
  "abstract_up",
  "lateral",
  "drill_down",
  "association",
  "affect_evaluation",
] as const;
export type DivergenceMethod = typeof DIVERGENCE_METHODS[number];

/// 與 prompt 步驟 1b 的「2-8 branches」同源；parser 不得比 prompt 寬。
export const MIN_DIVERGENCE_BRANCHES = 2;
export const MAX_DIVERGENCE_BRANCHES = 8;
const MAX_TEXT_LENGTH = 200;
const MAX_PATH_NODES = 8;

/// 模型可輸出的欄位；prompt 步驟 1b 與 parser 都從這幾張表與常數生成，
/// 不得各自另寫一份。事件行＝`type` 加 DIVERGENCE_PLAN_FIELDS；server 快照
/// 沒有 `type`。
export const DIVERGENCE_PLAN_EVENT_TYPE = "analysis.divergence_plan";
export const DIVERGENCE_PLAN_FIELDS = [
  "schemaVersion",
  "threadFrame",
  "anchorSourceIndex",
  "supportSourceIndices",
  "mergeContextSourceIndices",
  "semanticDistanceCap",
  "newTopicBudget",
  "questionBudget",
  "branchPool",
  "styleBranchIds",
] as const;
export const DIVERGENCE_BRANCH_FIELDS = [
  "id",
  "sourceIndex",
  "method",
  "idea",
  "associationPath",
  "semanticDistance",
] as const;
/// 分支距離 0–3；3＝遠距聯想，cap 最多 2，所以 3 永遠被 cap 排除（§5.10）。
export const MAX_SEMANTIC_DISTANCE = 3;
export const MAX_SEMANTIC_DISTANCE_CAP = 2;
export const MAX_NEW_TOPIC_BUDGET = 1;
export const MAX_QUESTION_BUDGET = 1;
/// 事件行的 key：必填＝type＋除 styleBranchIds 外的欄位；optional 只有
/// styleBranchIds。prompt 與 parser 都從這兩張表生成。
export const DIVERGENCE_PLAN_OPTIONAL_EVENT_KEYS = ["styleBranchIds"] as const;
export const DIVERGENCE_PLAN_REQUIRED_EVENT_KEYS = [
  "type",
  ...DIVERGENCE_PLAN_FIELDS.filter((field) =>
    !(DIVERGENCE_PLAN_OPTIONAL_EVENT_KEYS as readonly string[]).includes(field)
  ),
] as const;
export const DIVERGENCE_PLAN_EVENT_KEYS = [
  ...DIVERGENCE_PLAN_REQUIRED_EVENT_KEYS,
  ...DIVERGENCE_PLAN_OPTIONAL_EVENT_KEYS,
] as const;
const SNAPSHOT_KEYS = new Set<string>(DIVERGENCE_PLAN_FIELDS);
const BRANCH_KEYS = new Set<string>(DIVERGENCE_BRANCH_FIELDS);

/// finalResult 裡持久化但絕不送 client 的 key：計畫含從她訊息推出的
/// threadFrame／idea／associationPath，只給 DB 與 telemetry 用。
export const CLIENT_HIDDEN_FINAL_RESULT_KEYS = [
  "analysisDivergencePlan",
] as const;

export function stripClientHiddenFinalResult<T>(finalResult: T): T {
  if (
    typeof finalResult !== "object" || finalResult === null ||
    Array.isArray(finalResult)
  ) {
    return finalResult;
  }
  const record = finalResult as Record<string, unknown>;
  if (!CLIENT_HIDDEN_FINAL_RESULT_KEYS.some((key) => key in record)) {
    return finalResult;
  }
  const copy = { ...record };
  for (const key of CLIENT_HIDDEN_FINAL_RESULT_KEYS) delete copy[key];
  return copy as T;
}

// ---------------------------------------------------------------------------
// Phase 2b：planner 接管五風格生成（規格 §5.11 步驟 6、§6.3、§14.1）。
// 每個 v2 reply_option 可帶三個歸因欄位，指出它跟哪一枝、用哪個修辭手法、
// 強度多少。它們跟 action／questionCount 一樣是 option 的證據 metadata：
// 進 analysisEvidenceLinkage.variants 與 telemetry；計畫本文（threadFrame／
// idea／associationPath）仍只留 server。server 只做「歸因＋缺省補 anchor」
// 的軟守門，不擋 option：
// Eric 2026-09-02 定案——缺的風格跟 anchor 主線；模型沒吐計畫就走原路。
// 值域全在這裡：prompt 與 parser 都從這幾張表生成，不得各寫一份。

/// 修辭手法（§6.1 五風格核心機制）。規格 §6.3 原寫「值域＝DivergenceMethod
/// ＋風格專屬 move」，實作刻意讓它與 DIVERGENCE_METHODS **不相交**：2026-09-02
/// 黑箱實測，兩套詞彙一重疊，模型就把 `exaggeration` 這類手法填進分枝的
/// `method`，整份計畫因 unknown method 作廢（12 份丟 3 份）。分枝用六法
/// （怎麼分枝），卡片用手法（怎麼措辭），各自一張表。
export const RHETORICAL_MOVES = [
  "new_angle",
  "concrete_detail",
  "low_friction_entry",
  "reflect_feeling",
  "shared_experience",
  "playful_contrast",
  "playful_challenge",
  "exaggeration",
  "metaphor",
  "callback",
  "tentative_observation",
] as const;
export type RhetoricalMove = typeof RHETORICAL_MOVES[number];
/// repair-first（規格 §26）：模型把手法填進分枝 `method` 時（三輪黑箱 humor
/// 枝三次寫 `exaggeration`，prompt 明講也不聽），按這張表映射回六法並記
/// repair，不再整份作廢。對照依 §5.7 四法定義；telemetry 看得到修了幾次。
export const BRANCH_METHOD_REPAIRS: Readonly<
  Record<RhetoricalMove, DivergenceMethod>
> = {
  new_angle: "lateral",
  concrete_detail: "drill_down",
  low_friction_entry: "drill_down",
  reflect_feeling: "affect_evaluation",
  shared_experience: "association",
  playful_contrast: "association",
  playful_challenge: "affect_evaluation",
  exaggeration: "association",
  metaphor: "association",
  callback: "association",
  tentative_observation: "abstract_up",
};
/// styleIntensity 0–3（§6.3：風格不適合高強度時降強度，不得改 action）。
export const MAX_STYLE_INTENSITY = 3;
/// reply_option 上的歸因欄位；三個一起出現才算有效，缺一個整組視為缺席。
export const REPLY_OPTION_BRANCH_FIELDS = [
  "branchId",
  "rhetoricalMove",
  "styleIntensity",
] as const;
export const STYLE_BRANCH_SOURCES = ["option", "plan", "anchor"] as const;
export type StyleBranchSource = typeof STYLE_BRANCH_SOURCES[number];

export interface ReplyOptionBranchFields {
  readonly branchId: string;
  readonly rhetoricalMove: RhetoricalMove;
  readonly styleIntensity: number;
}

export interface StyleBranchResolution {
  readonly branchId: string;
  /// option＝option 自帶且合法；plan＝計畫 styleBranchIds 指定；anchor＝缺省補。
  readonly source: StyleBranchSource;
  readonly rhetoricalMove?: RhetoricalMove;
  readonly styleIntensity?: number;
  /// option 帶了歸因欄位但不合法（未知枝、未知手法、強度越界或缺欄位）。
  readonly invalid: boolean;
}

/// anchor 主線的那一枝：branchPool 裡第一枝 sourceIndex＝anchorSourceIndex；
/// 模型沒替 anchor 球建枝時退回 pool 第一枝（pool 至少 2 枝，永遠有值）。
export function anchorBranchOf(plan: DivergencePlanV1): DivergenceBranchV1 {
  return plan.branchPool.find((branch) =>
    branch.sourceIndex === plan.anchorSourceIndex
  ) ?? plan.branchPool[0];
}

/// 嚴格解析 reply_option 上的三個歸因欄位；三個都缺回 null（缺席），
/// 任一存在但不合法也回 null（呼叫端用 hasReplyOptionBranchFields 分辨）。
export function parseReplyOptionBranchFields(
  value: unknown,
  plan: DivergencePlanV1,
): ReplyOptionBranchFields | null {
  if (!isRecord(value)) return null;
  const branchId = shortText(value.branchId);
  if (
    branchId === null ||
    !plan.branchPool.some((branch) => branch.id === branchId)
  ) {
    return null;
  }
  const rhetoricalMove = typeof value.rhetoricalMove === "string" &&
      (RHETORICAL_MOVES as readonly string[]).includes(value.rhetoricalMove)
    ? value.rhetoricalMove as RhetoricalMove
    : null;
  const styleIntensity = boundedInt(value.styleIntensity, MAX_STYLE_INTENSITY);
  if (rhetoricalMove === null || styleIntensity === null) return null;
  return { branchId, rhetoricalMove, styleIntensity };
}

export function hasReplyOptionBranchFields(value: unknown): boolean {
  return isRecord(value) &&
    REPLY_OPTION_BRANCH_FIELDS.some((field) => value[field] !== undefined);
}

/// 歸因優先序：option 自帶合法 > 計畫 styleBranchIds > anchor 主線。
export function resolveStyleBranch(
  plan: DivergencePlanV1,
  style: StreamStyle,
  option: unknown,
): StyleBranchResolution {
  const fields = parseReplyOptionBranchFields(option, plan);
  if (fields) return { ...fields, source: "option", invalid: false };
  const invalid = hasReplyOptionBranchFields(option);
  const planned = plan.styleBranchIds?.[style];
  if (planned !== undefined) {
    return { branchId: planned, source: "plan", invalid };
  }
  return { branchId: anchorBranchOf(plan).id, source: "anchor", invalid };
}

export interface DivergenceBranchV1 {
  readonly id: string;
  readonly sourceIndex: number;
  readonly method: DivergenceMethod;
  readonly idea: string;
  readonly associationPath: readonly string[];
  readonly semanticDistance: number;
}

export interface DivergencePlanV1 {
  readonly schemaVersion: 1;
  readonly threadFrame: string;
  readonly anchorSourceIndex: number;
  readonly supportSourceIndices: readonly number[];
  readonly mergeContextSourceIndices: readonly number[];
  readonly semanticDistanceCap: number;
  readonly newTopicBudget: number;
  readonly questionBudget: number;
  readonly branchPool: readonly DivergenceBranchV1[];
  readonly styleBranchIds?: Readonly<Partial<Record<StreamStyle, string>>>;
}

/// 兩份契約：wire event（模型吐的那行）必須帶 `type`；server 快照（持久化的
/// analysisDivergencePlan）不得帶 `type`。兩者都回 null 就是整份不採用；不做
/// 部分修補，shadow 資料寧缺勿錯。
export function parseDivergencePlanEvent(
  value: unknown,
  repairs?: string[],
): DivergencePlanV1 | null {
  if (!isRecord(value)) return null;
  if (value.type !== DIVERGENCE_PLAN_EVENT_TYPE) return null;
  const { type: _type, ...snapshot } = value;
  return parseDivergencePlanV1(snapshot, repairs);
}

/// 容許的修補之一：Sonnet 5 實測（2026-09-02 黑箱）會在某一枝把 `sourceIndex`
/// 寫成 `sourceIndex<N>`——有時多一個 key（`"sourceIndex1": 1, "sourceIndex": 1`），
/// 有時直接取代（只有 `"sourceIndex2": 2`）。N 與值必須相等（有正常 key 時也要
/// 等於它）才視為手誤：丟掉多餘 key、補回 `sourceIndex`，並記進 repairs；
/// 值不同、不是數字、或兩個以上 glitch key 互相矛盾，仍整份作廢。
const BRANCH_SOURCE_INDEX_GLITCH = /^sourceIndex(\d+)$/;

export function parseDivergencePlanV1(
  value: unknown,
  repairs?: string[],
): DivergencePlanV1 | null {
  if (!isRecord(value)) return null;
  if (Object.keys(value).some((key) => !SNAPSHOT_KEYS.has(key))) return null;
  if (value.schemaVersion !== 1) return null;
  const threadFrame = shortText(value.threadFrame);
  const anchorSourceIndex = positiveInt(value.anchorSourceIndex);
  const supportSourceIndices = positiveIntList(value.supportSourceIndices);
  const mergeContextSourceIndices = positiveIntList(
    value.mergeContextSourceIndices,
  );
  const semanticDistanceCap = boundedInt(
    value.semanticDistanceCap,
    MAX_SEMANTIC_DISTANCE_CAP,
  );
  const newTopicBudget = boundedInt(value.newTopicBudget, MAX_NEW_TOPIC_BUDGET);
  const questionBudget = boundedInt(value.questionBudget, MAX_QUESTION_BUDGET);
  if (
    threadFrame === null || anchorSourceIndex === null ||
    supportSourceIndices === null || mergeContextSourceIndices === null ||
    semanticDistanceCap === null || newTopicBudget === null ||
    questionBudget === null
  ) {
    return null;
  }
  if (
    !Array.isArray(value.branchPool) ||
    value.branchPool.length < MIN_DIVERGENCE_BRANCHES ||
    value.branchPool.length > MAX_DIVERGENCE_BRANCHES
  ) {
    return null;
  }
  const branchPool: DivergenceBranchV1[] = [];
  const ids = new Set<string>();
  for (const raw of value.branchPool) {
    const branch = parseBranch(raw, repairs);
    if (!branch || ids.has(branch.id)) return null;
    ids.add(branch.id);
    branchPool.push(branch);
  }
  let styleBranchIds: Partial<Record<StreamStyle, string>> | undefined;
  if (value.styleBranchIds !== undefined) {
    if (!isRecord(value.styleBranchIds)) return null;
    styleBranchIds = {};
    for (const [style, id] of Object.entries(value.styleBranchIds)) {
      if (!isStreamStyle(style) || typeof id !== "string" || !ids.has(id)) {
        return null;
      }
      styleBranchIds[style] = id;
    }
  }
  return {
    schemaVersion: 1,
    threadFrame,
    anchorSourceIndex,
    supportSourceIndices,
    mergeContextSourceIndices,
    semanticDistanceCap,
    newTopicBudget,
    questionBudget,
    branchPool,
    ...(styleBranchIds ? { styleBranchIds } : {}),
  };
}

function parseBranch(
  raw: unknown,
  repairs?: string[],
): DivergenceBranchV1 | null {
  if (!isRecord(raw)) return null;
  const value = repairBranchSourceIndexGlitch(raw, repairs);
  if (value === null) return null;
  if (Object.keys(value).some((key) => !BRANCH_KEYS.has(key))) return null;
  const id = shortText(value.id);
  const sourceIndex = positiveInt(value.sourceIndex);
  const idea = shortText(value.idea);
  const semanticDistance = boundedInt(
    value.semanticDistance,
    MAX_SEMANTIC_DISTANCE,
  );
  const method = repairBranchMethod(value.method, id, repairs);
  if (
    id === null || sourceIndex === null || idea === null || method === null ||
    semanticDistance === null
  ) {
    return null;
  }
  if (!Array.isArray(value.associationPath)) return null;
  if (value.associationPath.length > MAX_PATH_NODES) return null;
  const associationPath: string[] = [];
  for (const node of value.associationPath) {
    const text = shortText(node);
    if (text === null) return null;
    associationPath.push(text);
  }
  return { id, sourceIndex, method, idea, associationPath, semanticDistance };
}

function repairBranchMethod(
  value: unknown,
  id: string | null,
  repairs?: string[],
): DivergenceMethod | null {
  if (typeof value !== "string") return null;
  if ((DIVERGENCE_METHODS as readonly string[]).includes(value)) {
    return value as DivergenceMethod;
  }
  if ((RHETORICAL_MOVES as readonly string[]).includes(value)) {
    const repaired = BRANCH_METHOD_REPAIRS[value as RhetoricalMove];
    repairs?.push(`${id ?? "?"}:method:${value}->${repaired}`);
    return repaired;
  }
  return null;
}

function repairBranchSourceIndexGlitch(
  value: Record<string, unknown>,
  repairs?: string[],
): Record<string, unknown> | null {
  const glitchKeys = Object.keys(value).filter((key) =>
    BRANCH_SOURCE_INDEX_GLITCH.test(key)
  );
  if (glitchKeys.length === 0) return value;
  const declared = value.sourceIndex === undefined
    ? null
    : positiveInt(value.sourceIndex);
  if (value.sourceIndex !== undefined && declared === null) return null;
  let sourceIndex = declared;
  for (const key of glitchKeys) {
    const suffix = Number(BRANCH_SOURCE_INDEX_GLITCH.exec(key)![1]);
    if (value[key] !== suffix) return null;
    if (sourceIndex === null) sourceIndex = suffix;
    else if (suffix !== sourceIndex) return null;
  }
  const copy: Record<string, unknown> = { ...value, sourceIndex };
  for (const key of glitchKeys) delete copy[key];
  repairs?.push(...glitchKeys.map((key) => `${stringId(value.id)}:${key}`));
  return copy;
}

function stringId(value: unknown): string {
  return typeof value === "string" ? value : "?";
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function shortText(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed !== "" && trimmed.length <= MAX_TEXT_LENGTH ? trimmed : null;
}

function positiveInt(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) && value > 0
    ? value
    : null;
}

function boundedInt(value: unknown, max: number): number | null {
  return typeof value === "number" && Number.isInteger(value) && value >= 0 &&
      value <= max
    ? value
    : null;
}

function positiveIntList(value: unknown): number[] | null {
  if (!Array.isArray(value)) return null;
  const list: number[] = [];
  for (const item of value) {
    const parsed = positiveInt(item);
    if (parsed === null || list.includes(parsed)) return null;
    list.push(parsed);
  }
  return list;
}
