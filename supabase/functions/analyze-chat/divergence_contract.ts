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

export const MAX_DIVERGENCE_BRANCHES = 12;
const MAX_TEXT_LENGTH = 200;
const MAX_PATH_NODES = 8;

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
  if (value.schemaVersion !== 1) return null;
  const threadFrame = shortText(value.threadFrame);
  const anchorSourceIndex = positiveInt(value.anchorSourceIndex);
  const supportSourceIndices = positiveIntList(value.supportSourceIndices);
  const mergeContextSourceIndices = positiveIntList(
    value.mergeContextSourceIndices,
  );
  const semanticDistanceCap = boundedInt(value.semanticDistanceCap, 3);
  const newTopicBudget = boundedInt(value.newTopicBudget, 1);
  const questionBudget = boundedInt(value.questionBudget, 1);
  if (
    threadFrame === null || anchorSourceIndex === null ||
    supportSourceIndices === null || mergeContextSourceIndices === null ||
    semanticDistanceCap === null || newTopicBudget === null ||
    questionBudget === null
  ) {
    return null;
  }
  if (!Array.isArray(value.branchPool) || value.branchPool.length === 0) {
    return null;
  }
  if (value.branchPool.length > MAX_DIVERGENCE_BRANCHES) return null;
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
  const id = shortText(value.id);
  const sourceIndex = positiveInt(value.sourceIndex);
  const idea = shortText(value.idea);
  const semanticDistance = boundedInt(value.semanticDistance, 3);
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
