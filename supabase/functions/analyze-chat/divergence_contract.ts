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
export const DIVERGENCE_PLAN_EVENT_KEYS = [
  "type",
  ...DIVERGENCE_PLAN_FIELDS,
] as const;
const PLAN_KEYS = new Set<string>(DIVERGENCE_PLAN_EVENT_KEYS);
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

/// 回 null 就是整個計畫不採用；不做部分修補，shadow 資料寧缺勿錯。
export function parseDivergencePlanV1(
  value: unknown,
): DivergencePlanV1 | null {
  if (!isRecord(value)) return null;
  if (Object.keys(value).some((key) => !PLAN_KEYS.has(key))) return null;
  if (value.type !== undefined && value.type !== DIVERGENCE_PLAN_EVENT_TYPE) {
    return null;
  }
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
    const branch = parseBranch(raw);
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

function parseBranch(value: unknown): DivergenceBranchV1 | null {
  if (!isRecord(value)) return null;
  if (Object.keys(value).some((key) => !BRANCH_KEYS.has(key))) return null;
  const id = shortText(value.id);
  const sourceIndex = positiveInt(value.sourceIndex);
  const idea = shortText(value.idea);
  const semanticDistance = boundedInt(
    value.semanticDistance,
    MAX_SEMANTIC_DISTANCE,
  );
  const method = typeof value.method === "string" &&
      (DIVERGENCE_METHODS as readonly string[]).includes(value.method)
    ? value.method as DivergenceMethod
    : null;
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
