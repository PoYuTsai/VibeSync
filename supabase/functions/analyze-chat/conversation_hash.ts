// Canonical conversation hash for durable stream validation.
// A reconnect/retry must reject when any analyzed context field drifts
// (RUN_CONVERSATION_MISMATCH). Hash must be:
//   - deterministic across key order (JSON insertion order is not stable)
//   - stable across Unicode normalization forms (NFC vs NFD)
//   - stable across trivial whitespace on user-typed strings
//   - SHA-256 hex64 (collision risk negligible for our scale)

export interface HashInput {
  messages?: unknown;
  userDraft?: unknown;
  partnerSummary?: unknown;
  sessionContext?: unknown;
  conversationSummary?: unknown;
  effectiveStyleContext?: unknown;
  knownContactName?: unknown;
  previousStage?: unknown;
  analysisFragmentStartIndex?: unknown;
}

function normalizeString(value: string): string {
  // NFC: 中文標點 + 重音拉丁字母可能用 precomposed 或 combining marks 編碼，
  // bytes 不同但視覺相同。一律規一化到 canonical composition，
  // 避免 client copy/paste 跨來源時 hash 漂掉誤觸 409。
  return value.normalize("NFC").trim();
}

function canonicalize(value: unknown): unknown {
  if (typeof value === "string") return normalizeString(value);
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value && typeof value === "object") {
    const sortedKeys = Object.keys(value as Record<string, unknown>).sort();
    const result: Record<string, unknown> = {};
    for (const k of sortedKeys) {
      result[k] = canonicalize((value as Record<string, unknown>)[k]);
    }
    return result;
  }
  return value;
}

export async function hashConversation(input: HashInput): Promise<string> {
  const hashPayload: Record<string, unknown> = {
    messages: input.messages ?? [],
    userDraft: input.userDraft ?? "",
    partnerSummary: input.partnerSummary ?? "",
    sessionContext: input.sessionContext ?? null,
    conversationSummary: input.conversationSummary ?? "",
    effectiveStyleContext: input.effectiveStyleContext ?? "",
    knownContactName: input.knownContactName ?? "",
  };
  // Preserve the pre-stage-prior hash for requests that do not carry this
  // optional field, so a deploy cannot invalidate an already-running stream.
  if (
    typeof input.previousStage === "string" &&
    normalizeString(input.previousStage).length > 0
  ) {
    hashPayload.previousStage = input.previousStage;
  }
  if (Number.isInteger(input.analysisFragmentStartIndex)) {
    hashPayload.analysisFragmentStartIndex = input.analysisFragmentStartIndex;
  }
  const canonical = canonicalize(hashPayload);
  const encoded = new TextEncoder().encode(JSON.stringify(canonical));
  const digest = await crypto.subtle.digest("SHA-256", encoded);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
