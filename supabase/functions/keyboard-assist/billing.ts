import { classifyQuotaRpcError } from "../_shared/quota.ts";
import {
  isValidKeyboardAssistRequestId,
  type KeyboardAssistLedgerResult,
  type KeyboardAssistMediaType,
  type KeyboardAssistSpeakerOverride,
  type KeyboardAssistV1Request,
} from "./contract.ts";
import { validateKeyboardAssistLedgerResult } from "./validate.ts";

export const KEYBOARD_ASSIST_COST = 1;
export const KEYBOARD_ASSIST_REPLAY_WINDOW_MS = 24 * 60 * 60 * 1000;
export const KEYBOARD_ASSIST_HMAC_KEY_RETENTION_MS = 25 * 60 * 60 * 1000;

const SHA256_PATTERN = /^[0-9a-f]{64}$/;

export type KeyboardAssistHmacKeyring = {
  currentVersion: number;
  keys: ReadonlyMap<number, string>;
};

export function isStrongKeyboardAssistHmacKey(
  value: unknown,
): value is string {
  if (
    typeof value !== "string" || value.length < 43 ||
    !/^[A-Za-z0-9+/]+={0,2}$/.test(value)
  ) return false;
  try {
    return atob(value).length >= 32 && btoa(atob(value)) === value;
  } catch {
    return false;
  }
}

export function resolveKeyboardAssistHmacKey(
  existing: { hmac_key_version: number } | null,
  keyring: KeyboardAssistHmacKeyring,
): { version: number; secret: string } | null {
  const version = existing?.hmac_key_version ?? keyring.currentVersion;
  if (!Number.isInteger(version) || version < 1 || version > 32767) return null;
  const secret = keyring.keys.get(version);
  return isStrongKeyboardAssistHmacKey(secret) ? { version, secret } : null;
}

export function hasAllKeyboardAssistHmacVersions(
  requiredVersions: unknown,
  keyring: KeyboardAssistHmacKeyring,
): boolean {
  return Array.isArray(requiredVersions) &&
    requiredVersions.every((rawVersion) => {
      const version = Number(rawVersion);
      return Number.isInteger(version) &&
        isStrongKeyboardAssistHmacKey(keyring.keys.get(version));
    });
}

export function parseKeyboardAssistHmacKeyring(input: {
  currentVersion: string | undefined;
  keysJson: string | undefined;
}): KeyboardAssistHmacKeyring | null {
  const currentVersion = Number(input.currentVersion);
  if (
    !Number.isInteger(currentVersion) || currentVersion < 1 ||
    currentVersion > 32767 || !input.keysJson
  ) return null;
  try {
    const parsed: unknown = JSON.parse(input.keysJson);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return null;
    }
    const keys = new Map<number, string>();
    for (const [rawVersion, secret] of Object.entries(parsed)) {
      const version = Number(rawVersion);
      if (
        !Number.isInteger(version) || version < 1 || version > 32767 ||
        !isStrongKeyboardAssistHmacKey(secret)
      ) return null;
      keys.set(version, secret);
    }
    if (!keys.has(currentVersion)) return null;
    return { currentVersion, keys };
  } catch {
    return null;
  }
}

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new Uint8Array(bytes).buffer,
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export async function computeKeyboardAssistInputHash(input: {
  userId: string;
  imageBytes: Uint8Array;
  mediaType: KeyboardAssistMediaType;
  speakerOverride: KeyboardAssistSpeakerOverride;
  voice: KeyboardAssistV1Request["voice"];
  secret: string;
}): Promise<string> {
  if (!isStrongKeyboardAssistHmacKey(input.secret)) {
    throw new Error("invalid keyboard assist HMAC key");
  }
  const imageDigest = await sha256Hex(input.imageBytes);
  // Deliberately excludes the server-resolved pipelineVersion. A deployment
  // between a lost response and retry must not turn the same payload into 409.
  const canonical = JSON.stringify([
    "vibesync-keyboard-assist-replay-v1",
    "keyboard-assist-v1",
    input.userId,
    imageDigest,
    input.mediaType,
    input.speakerOverride,
    [input.voice.primary, input.voice.secondary],
    null, // contextSource (v1)
    null, // contextRevision (v1)
    // Deliberately excludes priorTurn. It is a generation hint, not identity,
    // and a same-payload retry rebuilt from stored pending metadata has no way
    // to reproduce it; hashing it would turn a safe retry into a 409.
  ]);
  const rawSecret = Uint8Array.from(
    atob(input.secret),
    (character) => character.charCodeAt(0),
  );
  const derivedKey = await crypto.subtle.digest(
    "SHA-256",
    new Uint8Array([
      ...new TextEncoder().encode("vibesync-keyboard-assist-replay-v1\u0000"),
      ...rawSecret,
    ]),
  );
  const key = await crypto.subtle.importKey(
    "raw",
    derivedKey,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(canonical),
  );
  return Array.from(new Uint8Array(signature))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export type KeyboardAssistReplayRow = {
  input_hash: string;
  hmac_key_version: number;
  state: "pending" | "done";
  lease_expires_at: string;
  created_at: string;
  result_json: KeyboardAssistLedgerResult | null;
};

export type KeyboardAssistReplayPreflight =
  | { kind: "fresh" }
  | { kind: "mismatch" }
  | { kind: "pending"; retryAfterMs: number }
  | { kind: "replay"; result: KeyboardAssistLedgerResult };

export function isRetainedKeyboardAssistReplayRow(
  row: KeyboardAssistReplayRow | null,
  now = new Date(),
): row is KeyboardAssistReplayRow {
  if (!row) return false;
  const createdAt = Date.parse(row.created_at);
  return Number.isFinite(createdAt) &&
    createdAt <= now.getTime() + 5 * 60 * 1000 &&
    createdAt >= now.getTime() - KEYBOARD_ASSIST_REPLAY_WINDOW_MS;
}

export function classifyKeyboardAssistReplayPreflight(
  row: KeyboardAssistReplayRow | null,
  inputHash: string,
  now = new Date(),
): KeyboardAssistReplayPreflight {
  if (!isRetainedKeyboardAssistReplayRow(row, now)) {
    return { kind: "fresh" };
  }
  if (!SHA256_PATTERN.test(inputHash) || row.input_hash !== inputHash) {
    return { kind: "mismatch" };
  }
  if (row.state === "done") {
    return validateKeyboardAssistLedgerResult(row.result_json)
      ? { kind: "replay", result: row.result_json }
      : { kind: "mismatch" };
  }
  if (row.state !== "pending" || row.result_json !== null) {
    return { kind: "mismatch" };
  }
  const leaseExpiresAt = Date.parse(row.lease_expires_at);
  if (!Number.isFinite(leaseExpiresAt)) return { kind: "mismatch" };
  const retryAfterMs = leaseExpiresAt - now.getTime();
  return retryAfterMs > 0
    ? { kind: "pending", retryAfterMs: Math.max(250, Math.ceil(retryAfterMs)) }
    : { kind: "fresh" };
}

export type KeyboardAssistStatusRow = Pick<
  KeyboardAssistReplayRow,
  "state" | "lease_expires_at" | "created_at" | "result_json"
>;

export type KeyboardAssistStatus =
  | { kind: "missing" }
  | { kind: "done"; result: KeyboardAssistLedgerResult }
  | { kind: "pending"; retryAfterMs: number }
  | { kind: "expired" }
  | { kind: "corrupt" };

export function classifyKeyboardAssistStatus(
  row: KeyboardAssistStatusRow | null,
  now = new Date(),
): KeyboardAssistStatus {
  if (!row) return { kind: "missing" };
  const createdAt = Date.parse(row.created_at);
  if (
    !Number.isFinite(createdAt) ||
    createdAt > now.getTime() + 5 * 60 * 1000
  ) return { kind: "corrupt" };
  if (createdAt < now.getTime() - KEYBOARD_ASSIST_REPLAY_WINDOW_MS) {
    return { kind: "missing" };
  }
  if (row.state === "done") {
    return validateKeyboardAssistLedgerResult(row.result_json)
      ? { kind: "done", result: row.result_json }
      : { kind: "corrupt" };
  }
  if (row.state !== "pending" || row.result_json !== null) {
    return { kind: "corrupt" };
  }
  const leaseExpiresAt = Date.parse(row.lease_expires_at);
  if (!Number.isFinite(leaseExpiresAt)) return { kind: "corrupt" };
  const retryAfterMs = leaseExpiresAt - now.getTime();
  return retryAfterMs > 0
    ? { kind: "pending", retryAfterMs: Math.max(250, Math.ceil(retryAfterMs)) }
    : { kind: "expired" };
}

export type KeyboardAssistRpc = (
  fn: string,
  params: Record<string, unknown>,
) => PromiseLike<{
  data: unknown;
  error: { message?: string; code?: string } | null;
}>;

function isValidIdentity(input: {
  requestId: string;
  ownerToken: string;
  inputHash: string;
}): boolean {
  return isValidKeyboardAssistRequestId(input.requestId) &&
    isValidKeyboardAssistRequestId(input.ownerToken) &&
    SHA256_PATTERN.test(input.inputHash);
}

function isAmbiguousRpcTransportFailure(error: {
  message?: string;
  code?: string;
}): boolean {
  const code = error.code?.trim() ?? "";
  const message = error.message?.toLowerCase() ?? "";
  return code === "" || code.startsWith("08") || code.startsWith("PGRST0") ||
    /(fetch|network|connection|socket|timeout|timed out|reset)/.test(message);
}

export type KeyboardAssistClaim =
  | { kind: "claimed" }
  | { kind: "pending"; retryAfterMs: number }
  | { kind: "replay"; result: KeyboardAssistLedgerResult }
  | { kind: "mismatch" }
  | { kind: "uncertain"; message: string }
  | { kind: "failed"; message: string };

export async function claimKeyboardAssistRequest(input: {
  rpc: KeyboardAssistRpc;
  userId: string;
  requestId: string;
  inputHash: string;
  hmacKeyVersion: number;
  ownerToken: string;
}): Promise<KeyboardAssistClaim> {
  if (
    !isValidIdentity(input) || !Number.isInteger(input.hmacKeyVersion) ||
    input.hmacKeyVersion < 1 || input.hmacKeyVersion > 32767
  ) return { kind: "failed", message: "invalid keyboard assist claim" };
  let response: Awaited<ReturnType<KeyboardAssistRpc>>;
  try {
    response = await input.rpc("claim_keyboard_assist_request", {
      p_user_id: input.userId,
      p_request_id: input.requestId,
      p_input_hash: input.inputHash,
      p_hmac_key_version: input.hmacKeyVersion,
      p_owner_token: input.ownerToken,
    });
  } catch (error) {
    return {
      kind: "uncertain",
      message: error instanceof Error ? error.message : String(error),
    };
  }
  if (response.error) {
    if (response.error.message?.includes("KEYBOARD_ASSIST_REPLAY_MISMATCH")) {
      return { kind: "mismatch" };
    }
    return isAmbiguousRpcTransportFailure(response.error)
      ? {
        kind: "uncertain",
        message: response.error.message ?? "claim transport failed",
      }
      : {
        kind: "failed",
        message: response.error.message ?? "claim failed",
      };
  }
  if (!response.data || typeof response.data !== "object") {
    return { kind: "uncertain", message: "invalid claim response" };
  }
  const data = response.data as Record<string, unknown>;
  if (data.kind === "claimed") return { kind: "claimed" };
  if (
    data.kind === "pending" && typeof data.retryAfterMs === "number" &&
    Number.isFinite(data.retryAfterMs) && data.retryAfterMs > 0
  ) {
    return { kind: "pending", retryAfterMs: Math.ceil(data.retryAfterMs) };
  }
  if (
    data.kind === "replay" &&
    validateKeyboardAssistLedgerResult(data.result)
  ) return { kind: "replay", result: data.result };
  return { kind: "uncertain", message: "invalid claim result" };
}

export async function renewKeyboardAssistClaim(input: {
  rpc: KeyboardAssistRpc;
  userId: string;
  requestId: string;
  inputHash: string;
  ownerToken: string;
}): Promise<boolean> {
  if (!isValidIdentity(input)) return false;
  try {
    const response = await input.rpc("renew_keyboard_assist_claim", {
      p_user_id: input.userId,
      p_request_id: input.requestId,
      p_input_hash: input.inputHash,
      p_owner_token: input.ownerToken,
    });
    return response.error === null && response.data === true;
  } catch {
    return false;
  }
}

export async function releaseKeyboardAssistClaim(input: {
  rpc: KeyboardAssistRpc;
  userId: string;
  requestId: string;
  inputHash: string;
  ownerToken: string;
}): Promise<boolean> {
  if (!isValidIdentity(input)) return false;
  try {
    const response = await input.rpc("release_keyboard_assist_claim", {
      p_user_id: input.userId,
      p_request_id: input.requestId,
      p_input_hash: input.inputHash,
      p_owner_token: input.ownerToken,
    });
    return response.error === null && response.data === true;
  } catch {
    return false;
  }
}

export async function expireKeyboardAssistRequest(input: {
  rpc: KeyboardAssistRpc;
  userId: string;
  requestId: string;
}): Promise<boolean> {
  if (!isValidKeyboardAssistRequestId(input.requestId)) return false;
  try {
    const response = await input.rpc("expire_keyboard_assist_request", {
      p_user_id: input.userId,
      p_request_id: input.requestId,
    });
    return response.error === null && response.data === true;
  } catch {
    return false;
  }
}

export type KeyboardAssistSettlement =
  | {
    kind: "settled";
    charged: boolean;
    result: KeyboardAssistLedgerResult;
  }
  | {
    kind: "quota_exceeded";
    reason: "monthly_limit_exceeded" | "daily_limit_exceeded";
  }
  | { kind: "mismatch" }
  | { kind: "stale_owner" }
  | { kind: "uncertain"; message: string }
  | { kind: "failed"; message: string };

export async function settleKeyboardAssistRequest(input: {
  rpc: KeyboardAssistRpc;
  userId: string;
  requestId: string;
  inputHash: string;
  ownerToken: string;
  result: KeyboardAssistLedgerResult;
  monthlyLimit: number;
  dailyLimit: number;
  chargeQuota: boolean;
}): Promise<KeyboardAssistSettlement> {
  if (
    !isValidIdentity(input) || !validateKeyboardAssistLedgerResult(input.result)
  ) {
    return { kind: "failed", message: "invalid keyboard assist settlement" };
  }
  let response: Awaited<ReturnType<KeyboardAssistRpc>>;
  try {
    response = await input.rpc("settle_keyboard_assist_request", {
      p_user_id: input.userId,
      p_request_id: input.requestId,
      p_input_hash: input.inputHash,
      p_owner_token: input.ownerToken,
      p_result_json: input.result,
      p_monthly_limit: input.monthlyLimit,
      p_daily_limit: input.dailyLimit,
      p_charge_quota: input.chargeQuota,
    });
  } catch (error) {
    return {
      kind: "uncertain",
      message: error instanceof Error ? error.message : String(error),
    };
  }
  if (response.error) {
    const quotaReason = classifyQuotaRpcError(response.error.message);
    if (quotaReason) {
      return { kind: "quota_exceeded", reason: quotaReason };
    }
    if (response.error.message?.includes("KEYBOARD_ASSIST_REPLAY_MISMATCH")) {
      return { kind: "mismatch" };
    }
    if (response.error.message?.includes("KEYBOARD_ASSIST_OWNER_MISMATCH")) {
      return { kind: "stale_owner" };
    }
    return isAmbiguousRpcTransportFailure(response.error)
      ? {
        kind: "uncertain",
        message: response.error.message ?? "settlement transport failed",
      }
      : {
        kind: "failed",
        message: response.error.message ?? "settlement failed",
      };
  }
  if (!response.data || typeof response.data !== "object") {
    return { kind: "uncertain", message: "invalid settlement response" };
  }
  const data = response.data as Record<string, unknown>;
  if (
    typeof data.charged !== "boolean" ||
    !validateKeyboardAssistLedgerResult(data.result)
  ) return { kind: "uncertain", message: "invalid settlement result" };
  return {
    kind: "settled",
    charged: data.charged,
    result: data.result,
  };
}
