// 開場救星兩段式的會話／作業 RPC 包裝（migration 20260917120000）。
// 鏡像 new_topic_billing.ts 的錯誤分類：RAISE 的業務碼→明確 kind；
// transport／結果不明→retryable（呼叫端絕不 release、絕不宣稱不扣）。

import { classifyQuotaRpcError } from "../_shared/quota.ts";
import { isValidOpenerGenerateLedgerResult, type OpenerGenerateLedgerResult } from "./opener_flow_payload.ts";
import { type OpenerAnalysisSnapshot, type OpenerContribution, parseStoredOpenerAnalysisSnapshot } from "./opener_stage.ts";

export const OPENER_FLOW_DB_CONTRACT_VERSION = "opener-two-stage-v1";

export type OpenerFlowRpc = (
  fn: string,
  params: Record<string, unknown>,
) => PromiseLike<{ data: unknown; error: { message?: string; code?: string } | null }>;

function isAmbiguousRpcTransportFailure(error: { message?: string; code?: string }): boolean {
  const code = error.code?.trim() ?? "";
  const message = error.message?.toLowerCase() ?? "";
  return code === "" || code.startsWith("08") || code.startsWith("PGRST0") ||
    /(fetch|network|connection|socket|timeout|timed out|reset)/.test(message);
}

const BUSINESS_CODES = [
  "OPENER_SESSION_INVALID",
  "OPENER_SESSION_EXPIRED",
  "OPENER_OPERATION_INPUT_MISMATCH",
  "OPENER_OPERATION_OWNER_MISMATCH",
  "OPENER_OPERATION_LEASE_EXPIRED",
  "OPENER_GENERATION_LIMIT_REACHED",
  "OPENER_SUBSCRIPTION_MISSING",
] as const;
export type OpenerFlowBusinessCode = typeof BUSINESS_CODES[number];

export type OpenerFlowRpcFailure =
  | { kind: "business"; code: OpenerFlowBusinessCode }
  | { kind: "quota_exceeded"; reason: "monthly_limit_exceeded" | "daily_limit_exceeded" }
  | { kind: "retryable"; message: string }
  | { kind: "failed"; message: string };

function classifyRpcError(error: { message?: string; code?: string }): OpenerFlowRpcFailure {
  const message = error.message ?? "";
  for (const code of BUSINESS_CODES) {
    if (message.includes(code)) return { kind: "business", code };
  }
  const quota = classifyQuotaRpcError(message);
  if (quota) return { kind: "quota_exceeded", reason: quota };
  if (isAmbiguousRpcTransportFailure(error)) {
    return { kind: "retryable", message: message || "opener flow rpc transport failed" };
  }
  return { kind: "failed", message: message || "opener flow rpc failed" };
}

async function callRpc(
  rpc: OpenerFlowRpc,
  fn: string,
  params: Record<string, unknown>,
): Promise<{ ok: true; data: Record<string, unknown> } | { ok: false; failure: OpenerFlowRpcFailure }> {
  let response: Awaited<ReturnType<OpenerFlowRpc>>;
  try {
    response = await rpc(fn, params);
  } catch (error) {
    return { ok: false, failure: { kind: "retryable", message: error instanceof Error ? error.message : String(error) } };
  }
  if (response.error) return { ok: false, failure: classifyRpcError(response.error) };
  if (!response.data || typeof response.data !== "object" || Array.isArray(response.data)) {
    return { ok: false, failure: { kind: "retryable", message: `invalid ${fn} response` } };
  }
  return { ok: true, data: response.data as Record<string, unknown> };
}

export interface OpenerSessionView {
  sessionId: string;
  analysisRevision: number;
  snapshot: OpenerAnalysisSnapshot;
  expiresAt: string;
  firstGenerationCost: number;
  quotaCharged: boolean;
  chargedAmount: number;
  generationsUsed: number;
  contractVersion: number;
}

function parseSessionView(raw: unknown): OpenerSessionView | null {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const data = raw as Record<string, unknown>;
  const snapshot = parseStoredOpenerAnalysisSnapshot(data.analysisJson);
  if (!snapshot || typeof data.sessionId !== "string" || typeof data.expiresAt !== "string") return null;
  return {
    sessionId: data.sessionId,
    analysisRevision: typeof data.analysisRevision === "number" ? data.analysisRevision : 1,
    snapshot,
    expiresAt: data.expiresAt,
    firstGenerationCost: typeof data.firstGenerationCost === "number" ? data.firstGenerationCost : 3,
    quotaCharged: data.quotaCharged === true,
    chargedAmount: typeof data.chargedAmount === "number" ? data.chargedAmount : 0,
    generationsUsed: typeof data.generationsUsed === "number" ? data.generationsUsed : 0,
    contractVersion: typeof data.contractVersion === "number" ? data.contractVersion : 2,
  };
}

export async function readOpenerFlowDbContractVersion(rpc: OpenerFlowRpc): Promise<string | null> {
  try {
    const response = await rpc("opener_flow_contract_version", {});
    if (response.error || typeof response.data !== "string") return null;
    return response.data;
  } catch {
    return null;
  }
}

// ── 第一段 ────────────────────────────────────────────────────────────────

export type OpenerAnalysisClaim =
  | { kind: "claimed" }
  | { kind: "pending"; retryAfterMs: number }
  | { kind: "replay"; session: OpenerSessionView }
  | { kind: "expired" }
  | { kind: "error"; failure: OpenerFlowRpcFailure };

export async function claimOpenerAnalysis(input: {
  rpc: OpenerFlowRpc;
  userId: string;
  analysisRequestId: string;
  inputHash: string;
  ownerToken: string;
  flowVersion: number;
  contractVersion: number;
  leaseSeconds: number;
}): Promise<OpenerAnalysisClaim> {
  const call = await callRpc(input.rpc, "claim_opener_analysis", {
    p_user_id: input.userId,
    p_analysis_request_id: input.analysisRequestId,
    p_input_hash: input.inputHash,
    p_owner_token: input.ownerToken,
    p_flow_version: input.flowVersion,
    p_contract_version: input.contractVersion,
    p_lease_seconds: input.leaseSeconds,
  });
  if (!call.ok) return { kind: "error", failure: call.failure };
  const data = call.data;
  if (data.kind === "claimed") return { kind: "claimed" };
  if (data.kind === "expired") return { kind: "expired" };
  if (data.kind === "pending" && typeof data.retryAfterMs === "number") {
    return { kind: "pending", retryAfterMs: Math.max(250, Math.ceil(data.retryAfterMs)) };
  }
  if (data.kind === "replay") {
    const session = parseSessionView(data);
    if (session) return { kind: "replay", session };
  }
  return { kind: "error", failure: { kind: "retryable", message: "invalid claim_opener_analysis result" } };
}

export async function releaseOpenerAnalysisClaim(input: {
  rpc: OpenerFlowRpc;
  userId: string;
  analysisRequestId: string;
  ownerToken: string;
}): Promise<boolean> {
  try {
    const response = await input.rpc("release_opener_analysis_claim", {
      p_user_id: input.userId,
      p_analysis_request_id: input.analysisRequestId,
      p_owner_token: input.ownerToken,
    });
    return response.error === null && response.data === true;
  } catch {
    return false;
  }
}

export type OpenerAnalysisSettlement =
  | { kind: "settled"; replayed: boolean; sessionId: string; analysisRevision: number; expiresAt: string; firstGenerationCost: number; snapshot: OpenerAnalysisSnapshot }
  | { kind: "error"; failure: OpenerFlowRpcFailure };

export async function settleOpenerAnalysis(input: {
  rpc: OpenerFlowRpc;
  userId: string;
  analysisRequestId: string;
  ownerToken: string;
  snapshot: OpenerAnalysisSnapshot;
  firstGenerationCost: number;
  ttlSeconds: number;
}): Promise<OpenerAnalysisSettlement> {
  const call = await callRpc(input.rpc, "settle_opener_analysis", {
    p_user_id: input.userId,
    p_analysis_request_id: input.analysisRequestId,
    p_owner_token: input.ownerToken,
    p_analysis_json: input.snapshot,
    p_first_generation_cost: input.firstGenerationCost,
    p_ttl_seconds: input.ttlSeconds,
  });
  if (!call.ok) return { kind: "error", failure: call.failure };
  const data = call.data;
  const snapshot = parseStoredOpenerAnalysisSnapshot(data.analysisJson);
  if (typeof data.sessionId !== "string" || typeof data.expiresAt !== "string" || !snapshot) {
    return { kind: "error", failure: { kind: "retryable", message: "invalid settle_opener_analysis result" } };
  }
  return {
    kind: "settled",
    replayed: data.replayed === true,
    sessionId: data.sessionId,
    analysisRevision: typeof data.analysisRevision === "number" ? data.analysisRevision : 1,
    expiresAt: data.expiresAt,
    firstGenerationCost: typeof data.firstGenerationCost === "number" ? data.firstGenerationCost : input.firstGenerationCost,
    snapshot,
  };
}

// ── 第二段 ────────────────────────────────────────────────────────────────

export type OpenerGenerationClaim =
  | { kind: "claimed"; session: OpenerSessionView }
  | { kind: "pending"; retryAfterMs: number }
  | { kind: "session_busy"; generationId: string | null; retryAfterMs: number }
  | { kind: "replay"; session: OpenerSessionView; result: OpenerGenerateLedgerResult }
  | { kind: "error"; failure: OpenerFlowRpcFailure };

export async function claimOpenerGeneration(input: {
  rpc: OpenerFlowRpc;
  userId: string;
  sessionId: string;
  generationId: string;
  inputHash: string;
  ownerToken: string;
  contribution: OpenerContribution;
  maxGenerations: number;
  leaseSeconds: number;
}): Promise<OpenerGenerationClaim> {
  const call = await callRpc(input.rpc, "claim_opener_generation", {
    p_user_id: input.userId,
    p_session_id: input.sessionId,
    p_generation_id: input.generationId,
    p_input_hash: input.inputHash,
    p_owner_token: input.ownerToken,
    p_contribution_json: input.contribution,
    p_max_generations: input.maxGenerations,
    p_lease_seconds: input.leaseSeconds,
  });
  if (!call.ok) return { kind: "error", failure: call.failure };
  const data = call.data;
  if (data.kind === "pending" && typeof data.retryAfterMs === "number") {
    return { kind: "pending", retryAfterMs: Math.max(250, Math.ceil(data.retryAfterMs)) };
  }
  if (data.kind === "session_busy" && typeof data.retryAfterMs === "number") {
    return {
      kind: "session_busy",
      generationId: typeof data.generationId === "string" ? data.generationId : null,
      retryAfterMs: Math.max(250, Math.ceil(data.retryAfterMs)),
    };
  }
  const session = parseSessionView(data.session);
  if (data.kind === "claimed" && session) return { kind: "claimed", session };
  if (data.kind === "replay" && session && isValidOpenerGenerateLedgerResult(data.result)) {
    return { kind: "replay", session, result: data.result };
  }
  return { kind: "error", failure: { kind: "retryable", message: "invalid claim_opener_generation result" } };
}

export async function releaseOpenerGenerationClaim(input: {
  rpc: OpenerFlowRpc;
  userId: string;
  generationId: string;
  ownerToken: string;
}): Promise<boolean> {
  try {
    const response = await input.rpc("release_opener_generation_claim", {
      p_user_id: input.userId,
      p_generation_id: input.generationId,
      p_owner_token: input.ownerToken,
    });
    return response.error === null && response.data === true;
  } catch {
    return false;
  }
}

export interface OpenerGenerationUsage {
  chargedNow: number;
  sessionChargedTotal: number;
  generationsUsed: number;
  generationsRemaining: number;
  replayed: boolean;
}

export type OpenerGenerationSettlement =
  | { kind: "settled"; usage: OpenerGenerationUsage; result: OpenerGenerateLedgerResult }
  | { kind: "error"; failure: OpenerFlowRpcFailure };

export async function settleOpenerGeneration(input: {
  rpc: OpenerFlowRpc;
  userId: string;
  sessionId: string;
  generationId: string;
  ownerToken: string;
  result: OpenerGenerateLedgerResult;
  monthlyLimit: number;
  dailyLimit: number;
  chargeQuota: boolean;
  maxGenerations: number;
}): Promise<OpenerGenerationSettlement> {
  const call = await callRpc(input.rpc, "settle_opener_generation", {
    p_user_id: input.userId,
    p_session_id: input.sessionId,
    p_generation_id: input.generationId,
    p_owner_token: input.ownerToken,
    p_result_json: input.result,
    p_monthly_limit: input.monthlyLimit,
    p_daily_limit: input.dailyLimit,
    p_charge_quota: input.chargeQuota,
    p_max_generations: input.maxGenerations,
  });
  if (!call.ok) return { kind: "error", failure: call.failure };
  const data = call.data;
  if (
    typeof data.chargedNow !== "number" || typeof data.generationsUsed !== "number" ||
    typeof data.generationsRemaining !== "number" || typeof data.sessionChargedTotal !== "number" ||
    !isValidOpenerGenerateLedgerResult(data.result)
  ) {
    return { kind: "error", failure: { kind: "retryable", message: "invalid settle_opener_generation result" } };
  }
  return {
    kind: "settled",
    usage: {
      chargedNow: data.chargedNow,
      sessionChargedTotal: data.sessionChargedTotal,
      generationsUsed: data.generationsUsed,
      generationsRemaining: data.generationsRemaining,
      replayed: data.replayed === true,
    },
    result: data.result,
  };
}

export function buildReplayUsage(session: OpenerSessionView, maxGenerations: number): OpenerGenerationUsage {
  return {
    chargedNow: 0,
    sessionChargedTotal: session.chargedAmount,
    generationsUsed: session.generationsUsed,
    generationsRemaining: Math.max(0, maxGenerations - session.generationsUsed),
    replayed: true,
  };
}
