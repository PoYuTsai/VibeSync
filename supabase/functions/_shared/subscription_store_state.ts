export type SubscriptionStore = "app_store" | "play_store";
export type SubscriptionTier = "free" | "starter" | "essential";
export type SubscriptionStatus =
  | "active"
  | "cancelled"
  | "expired"
  | "billing_issue";
export type VerificationSource =
  | "revenuecat_webhook"
  | "revenuecat_api"
  | "legacy_backfill";
export type VerificationStatus = "verified" | "unverified";
export type RevenueCatEnvironment = "sandbox" | "production";
export type LegacyCutoverStatus = "pending" | "complete" | "auto";

export interface SubscriptionStoreState {
  readonly userId?: string;
  readonly store: SubscriptionStore;
  readonly productId: string | null;
  readonly basePlanId: string | null;
  readonly tier: SubscriptionTier;
  readonly status: SubscriptionStatus;
  readonly expiresAt: Date | null;
  readonly eventAt: Date;
  readonly eventId: string | null;
  readonly verificationSource: VerificationSource;
  readonly verificationStatus: VerificationStatus;
  readonly revenueCatEnvironment: RevenueCatEnvironment | null;
}

export interface StoreSubscriptionEventInput {
  readonly store?: unknown;
  readonly source?: unknown;
  readonly productId?: unknown;
  readonly basePlanId?: unknown;
  readonly tier?: unknown;
  readonly status?: unknown;
  readonly expiresAt?: unknown;
  readonly eventAt?: unknown;
  readonly eventId?: unknown;
  readonly verificationStatus?: unknown;
  readonly revenueCatEnvironment?: unknown;
}

export type RevenueCatSnapshotSubscription = StoreSubscriptionEventInput;

export interface SourceAwareSubscriptionRead {
  readonly effective: SubscriptionStoreState | null;
  readonly sources: readonly SubscriptionStoreState[];
  readonly hasVerifiedSource: boolean;
  readonly cutoverStatus: LegacyCutoverStatus;
  readonly readAt: Date;
}

export interface LegacySubscriptionAggregate {
  readonly tier: SubscriptionTier;
  readonly status: SubscriptionStatus;
  readonly expiresAt: Date | null;
  readonly activeProductId: string | null;
  readonly store: SubscriptionStore | null;
  readonly revenueCatEnvironment: RevenueCatEnvironment | null;
  readonly verificationSource: VerificationSource;
}

export type LegacySubscriptionAggregateResult =
  | { readonly kind: "aggregate"; readonly value: LegacySubscriptionAggregate }
  | { readonly kind: "preserve"; readonly reason: "no_verified_source" };

export interface SourceAwareLegacyAggregateMerge {
  readonly value: LegacySubscriptionAggregate;
  readonly sourceAuthoritative: boolean;
  readonly reason:
    | "cutover_complete"
    | "safe_upgrade"
    | "preserve_legacy_unreconciled"
    | "no_verified_source";
}

export interface SubscriptionStoreRpcClient {
  rpc(
    name: string,
    args: Record<string, unknown>,
  ): PromiseLike<{ data: unknown; error: { message?: string } | null }>;
}

export interface SubscriptionStoreReadClient {
  from(table: string): {
    select(columns: string): {
      eq(
        column: string,
        value: unknown,
      ): PromiseLike<{
        data: unknown;
        error: { message?: string } | null;
      }>;
    };
  };
}

export interface SourceAwareSubscriptionStatesResult {
  readonly read: SourceAwareSubscriptionRead;
  readonly error: { message?: string } | null;
}

export interface RevenueCatStoreSnapshotOptions {
  readonly now?: Date;
  readonly source?: VerificationSource;
  readonly verificationStatus?: VerificationStatus;
  readonly revenueCatEnvironment?: RevenueCatEnvironment | null;
}

export type SubscriptionStorePersistenceReason =
  | "accepted"
  | "preserve_no_verified_source"
  | "preserve_legacy_unreconciled"
  | "preserve_verified"
  | "duplicate"
  | "stale"
  | "invalid"
  | "store_mismatch"
  | "database_error"
  | "invalid_response";

export interface SubscriptionStorePersistenceResult {
  readonly accepted: boolean;
  readonly reason: SubscriptionStorePersistenceReason;
}

export type StoreSubscriptionEventReduction =
  | { readonly kind: "accepted"; readonly state: SubscriptionStoreState }
  | {
    readonly kind: "ignored";
    readonly reason:
      | "invalid"
      | "duplicate"
      | "stale"
      | "store_mismatch"
      | "preserve_verified";
  };

const TIER_RANK: Record<SubscriptionTier, number> = {
  free: 0,
  starter: 1,
  essential: 2,
};

function isValidDate(value: Date): boolean {
  return !Number.isNaN(value.getTime());
}

function asDate(value: unknown): Date | null {
  if (value instanceof Date) {
    return isValidDate(value) ? value : null;
  }
  if (typeof value === "string" && value.trim()) {
    const parsed = new Date(value);
    return isValidDate(parsed) ? parsed : null;
  }
  if (typeof value === "number" && Number.isFinite(value) && value > 0) {
    const parsed = new Date(value);
    return isValidDate(parsed) ? parsed : null;
  }
  return null;
}

function asOptionalDate(value: unknown): Date | null | undefined {
  if (value == null) return null;
  return asDate(value) ?? undefined;
}

function asOptionalText(value: unknown): string | null | undefined {
  if (value == null) return null;
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function isStore(value: unknown): value is SubscriptionStore {
  return value === "app_store" || value === "play_store";
}

function isTier(value: unknown): value is SubscriptionTier {
  return value === "free" || value === "starter" || value === "essential";
}

function isStatus(value: unknown): value is SubscriptionStatus {
  return value === "active" || value === "cancelled" ||
    value === "expired" || value === "billing_issue";
}

function isVerificationSource(value: unknown): value is VerificationSource {
  return value === "revenuecat_webhook" || value === "revenuecat_api" ||
    value === "legacy_backfill";
}

function isVerificationStatus(value: unknown): value is VerificationStatus {
  return value === "verified" || value === "unverified";
}

function isRevenueCatEnvironment(
  value: unknown,
): value is RevenueCatEnvironment {
  return value === "sandbox" || value === "production";
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function tierFromProductId(value: unknown): SubscriptionTier | null {
  if (typeof value !== "string") return null;
  const normalized = value.trim().toLowerCase();
  if (normalized.includes("essential")) return "essential";
  if (normalized.includes("starter")) return "starter";
  if (normalized.includes("free")) return "free";
  return null;
}

function firstText(...values: unknown[]): string | null {
  for (const value of values) {
    const text = asOptionalText(value);
    if (text !== undefined && text !== null) return text;
  }
  return null;
}

function snapshotDate(
  record: Record<string, unknown>,
  ...keys: string[]
): Date | null | undefined {
  for (const key of keys) {
    if (!(key in record)) continue;
    const value = record[key];
    if (value == null) return null;
    return asDate(value) ?? undefined;
  }
  return undefined;
}

function snapshotEventDate(
  record: Record<string, unknown>,
  ...keys: string[]
): Date | null {
  for (const key of keys) {
    if (!(key in record)) continue;
    const parsed = asDate(record[key]);
    if (parsed != null) return parsed;
  }
  return null;
}

/**
 * RevenueCat uses upper-case store/environment labels in webhook payloads.
 * Keep this mapping deliberately closed: an unknown label must not be
 * guessed into one of the two supported stores.
 */
export function normalizeRevenueCatStore(
  value: unknown,
): SubscriptionStore | null {
  if (typeof value !== "string") return null;
  switch (value.trim().toLowerCase()) {
    case "app_store":
      return "app_store";
    case "play_store":
      return "play_store";
    default:
      return null;
  }
}

export function normalizeRevenueCatEnvironment(
  value: unknown,
): RevenueCatEnvironment | null {
  if (typeof value !== "string") return null;
  switch (value.trim().toLowerCase()) {
    case "sandbox":
      return "sandbox";
    case "production":
      return "production";
    default:
      return null;
  }
}

/**
 * Google Play can return a product id in the `<subscription>:<basePlan>` form.
 * Keep the complete product id for legacy/admin reporting and only derive the
 * base plan when the store is explicitly Play and no authoritative field was
 * provided.
 */
export function extractRevenueCatBasePlanId(
  store: SubscriptionStore,
  productId: unknown,
  explicitBasePlanId?: unknown,
): string | null {
  const explicit = asOptionalText(explicitBasePlanId);
  if (explicit !== undefined && explicit !== null) return explicit;
  if (store !== "play_store") return null;
  const product = asOptionalText(productId);
  if (product === undefined || product === null) return null;
  const separator = product.lastIndexOf(":");
  if (separator < 1 || separator >= product.length - 1) return null;
  const basePlan = product.slice(separator + 1).trim();
  return basePlan.length > 0 ? basePlan : null;
}

function isEffectiveAt(
  state: SubscriptionStoreState,
  at: Date,
): boolean {
  if (state.verificationStatus !== "verified") return false;
  if (state.status === "expired") return false;
  if (!isValidDate(state.eventAt) || state.eventAt.getTime() > at.getTime()) {
    return false;
  }
  // A non-terminal row without an authoritative expiry cannot prove that
  // access is still valid. Ingestion rejects such rows; keep the read-time
  // projection fail closed as a second boundary.
  if (state.expiresAt == null) return false;
  return isValidDate(state.expiresAt) &&
    state.expiresAt.getTime() > at.getTime();
}

/**
 * Selects one complete, verified store row at a point in time.
 *
 * The returned object is the winning input row itself. This prevents callers
 * from combining a tier from one store with an expiry or store identifier from
 * another source.
 */
export function resolveEffectiveEntitlementAt(
  states: readonly SubscriptionStoreState[],
  at: Date,
): SubscriptionStoreState | null {
  if (!isValidDate(at)) return null;

  const candidates = states.filter((state) => isEffectiveAt(state, at));
  candidates.sort((left, right) => {
    const tierDifference = TIER_RANK[right.tier] - TIER_RANK[left.tier];
    if (tierDifference !== 0) return tierDifference;

    const eventDifference = right.eventAt.getTime() - left.eventAt.getTime();
    if (eventDifference !== 0) return eventDifference;

    return left.store.localeCompare(right.store);
  });

  return candidates[0] ?? null;
}

/**
 * Applies exactly one typed event to exactly one store row.
 *
 * Missing/unknown fields and cross-store updates are rejected before a state
 * can be constructed. Event id is authoritative for duplicates; event time is
 * authoritative for stale/out-of-order events.
 */
export function reduceStoreSubscriptionEvent(
  current: SubscriptionStoreState | null,
  event: StoreSubscriptionEventInput,
): StoreSubscriptionEventReduction {
  if (!isStore(event.store) || !isVerificationSource(event.source)) {
    return { kind: "ignored", reason: "invalid" };
  }
  if (current != null && current.store !== event.store) {
    return { kind: "ignored", reason: "store_mismatch" };
  }

  const eventId = asOptionalText(event.eventId);
  const eventAt = asDate(event.eventAt);
  const productId = asOptionalText(event.productId);
  const basePlanId = asOptionalText(event.basePlanId);
  const expiresAt = asOptionalDate(event.expiresAt);
  const environment = event.revenueCatEnvironment == null
    ? null
    : isRevenueCatEnvironment(event.revenueCatEnvironment)
    ? event.revenueCatEnvironment
    : undefined;
  const verificationStatus = event.verificationStatus == null
    ? event.source === "legacy_backfill" ? "unverified" : "verified"
    : event.verificationStatus;

  if (
    eventId == null || eventAt == null || productId === undefined ||
    basePlanId === undefined || expiresAt === undefined ||
    !isTier(event.tier) || !isStatus(event.status) ||
    !isVerificationStatus(verificationStatus) || environment === undefined
  ) {
    return { kind: "ignored", reason: "invalid" };
  }
  if (event.tier !== "free" && productId === null) {
    return { kind: "ignored", reason: "invalid" };
  }
  // Every non-terminal lifecycle signal must carry a finite authoritative
  // expiry. Without it, accepting the event could either revoke access
  // immediately (cancel/billing) or create a perpetual grant (purchase/
  // renewal). A free terminal expiry remains the explicit exception and may
  // omit the value.
  if (
    expiresAt === null &&
    !(event.tier === "free" && event.status === "expired")
  ) {
    return { kind: "ignored", reason: "invalid" };
  }
  if (
    event.source === "legacy_backfill" && verificationStatus !== "unverified"
  ) {
    return { kind: "ignored", reason: "invalid" };
  }

  if (current != null) {
    if (
      current.verificationStatus === "verified" &&
      verificationStatus === "unverified"
    ) {
      return { kind: "ignored", reason: "preserve_verified" };
    }
    if (
      current.verificationStatus !== "verified" &&
      verificationStatus === "verified"
    ) {
      // Verified provenance may replace an unverified backfill regardless of
      // event time; the authority upgrade is not an ordering regression.
    } else {
      if (current.eventId === eventId) {
        return { kind: "ignored", reason: "duplicate" };
      }
      if (eventAt.getTime() <= current.eventAt.getTime()) {
        return { kind: "ignored", reason: "stale" };
      }
    }
  }

  return {
    kind: "accepted",
    state: {
      userId: current?.userId,
      store: event.store,
      productId,
      basePlanId,
      tier: event.tier,
      status: event.status,
      expiresAt,
      eventAt,
      eventId,
      verificationSource: event.source,
      verificationStatus,
      revenueCatEnvironment: environment,
    },
  };
}

/**
 * Keeps RevenueCat's per-subscription store boundary intact. An empty snapshot
 * intentionally produces no event; callers must not turn it into a free state.
 */
export function splitRevenueCatSnapshot(
  entries: readonly RevenueCatSnapshotSubscription[],
): StoreSubscriptionEventInput[] {
  return entries.map((entry) => ({
    ...entry,
    source: entry.source ?? "revenuecat_api",
  }));
}

/**
 * Converts one RevenueCat subscriber snapshot into at most one complete state
 * event per supported store. Store is taken from the subscription record or
 * an explicit caller contract; it is never guessed from the product id.
 * Empty/unsupported snapshots produce no event, so they cannot erase a paid
 * legacy aggregate.
 */
export function buildRevenueCatStoreEvents(
  subscriber: Record<string, unknown>,
  options: RevenueCatStoreSnapshotOptions = {},
): StoreSubscriptionEventInput[] {
  const now = options.now ?? new Date();
  if (!isValidDate(now)) return [];

  const subscriptionMap = isPlainObject(subscriber.subscriptions)
    ? subscriber.subscriptions
    : {};
  const entitlementMap = isPlainObject(subscriber.entitlements)
    ? subscriber.entitlements
    : {};
  const sourceEntries = Object.entries(subscriptionMap).length > 0
    ? Object.entries(subscriptionMap)
    : Object.entries(entitlementMap);
  const byStore = new Map<SubscriptionStore, StoreSubscriptionEventInput>();

  for (const [mapProductId, raw] of sourceEntries) {
    if (!isPlainObject(raw)) continue;
    const store = normalizeRevenueCatStore(raw.store);
    if (store === null) continue;

    const productId = firstText(raw.product_identifier, mapProductId);
    const tier = isTier(raw.tier) ? raw.tier : tierFromProductId(productId);
    if (productId === null || tier === null) continue;

    const expiresAt = snapshotDate(raw, "expires_date", "expires_at");
    if (expiresAt === undefined) continue;
    if (expiresAt !== null && expiresAt.getTime() <= now.getTime()) continue;

    const status = (raw.billing_issues_detected_at != null ||
        raw.billing_issues_detected_at_ms != null)
      ? "billing_issue"
      : raw.unsubscribe_detected_at != null || raw.cancelled_at != null ||
          raw.cancelled_at_ms != null
      ? "cancelled"
      : "active";
    const eventAt = snapshotEventDate(
      raw,
      ...(status === "billing_issue"
        ? [
          "billing_issues_detected_at",
          "billing_issues_detected_at_ms",
          "event_at",
          "updated_at",
          "last_purchase_date",
          "purchase_date",
          "original_purchase_date",
        ]
        : status === "cancelled"
        ? [
          "unsubscribe_detected_at",
          "cancelled_at",
          "cancelled_at_ms",
          "event_at",
          "updated_at",
          "last_purchase_date",
          "purchase_date",
          "original_purchase_date",
        ]
        : [
          "event_at",
          "updated_at",
          "last_purchase_date",
          "purchase_date",
          "original_purchase_date",
        ]) as string[],
    );
    if (eventAt == null) continue;

    const basePlanId = extractRevenueCatBasePlanId(
      store,
      productId,
      firstText(
        raw.base_plan_id,
        raw.product_plan_identifier,
        raw.product_plan_id,
      ),
    );
    const environment = typeof raw.is_sandbox === "boolean"
      ? raw.is_sandbox ? "sandbox" : "production"
      : normalizeRevenueCatEnvironment(raw.environment) ??
        options.revenueCatEnvironment ?? null;
    const resolvedEventAt = eventAt;
    const transactionId = firstText(
      raw.transaction_id,
      raw.store_transaction_id,
      raw.id,
    );
    const originalTransactionId = firstText(raw.original_transaction_id);
    const resolvedEventId = [
      transactionId ?? "revenuecat-snapshot",
      store,
      originalTransactionId ?? productId,
      basePlanId ?? "none",
      tier,
      status,
      resolvedEventAt.toISOString(),
      expiresAt?.toISOString() ?? "none",
    ].join(":");

    const candidate: StoreSubscriptionEventInput = {
      store,
      source: options.source ?? "revenuecat_api",
      productId,
      basePlanId,
      tier,
      status,
      expiresAt,
      eventAt: resolvedEventAt,
      eventId: resolvedEventId,
      verificationStatus: options.verificationStatus ?? "verified",
      revenueCatEnvironment: environment,
    };
    const previous = byStore.get(store);
    if (previous === undefined || snapshotEventWins(candidate, previous)) {
      byStore.set(store, candidate);
    }
  }

  return Array.from(byStore.entries())
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([, event]) => event);
}

function snapshotEventWins(
  candidate: StoreSubscriptionEventInput,
  previous: StoreSubscriptionEventInput,
): boolean {
  const candidateTier = isTier(candidate.tier) ? TIER_RANK[candidate.tier] : -1;
  const previousTier = isTier(previous.tier) ? TIER_RANK[previous.tier] : -1;
  if (candidateTier !== previousTier) return candidateTier > previousTier;
  const candidateAt = asDate(candidate.eventAt)?.getTime() ?? -Infinity;
  const previousAt = asDate(previous.eventAt)?.getTime() ?? -Infinity;
  if (candidateAt !== previousAt) return candidateAt > previousAt;
  const candidateExpiry = asDate(candidate.expiresAt)?.getTime() ?? -Infinity;
  const previousExpiry = asDate(previous.expiresAt)?.getTime() ?? -Infinity;
  if (candidateExpiry !== previousExpiry) {
    return candidateExpiry > previousExpiry;
  }
  return String(candidate.productId).localeCompare(String(previous.productId)) >
    0;
}

export function buildSourceAwareSubscriptionRead(
  states: readonly SubscriptionStoreState[],
  at: Date,
  cutoverStatus: LegacyCutoverStatus = "pending",
): SourceAwareSubscriptionRead {
  const occurredVerified = states.filter((state) =>
    state.verificationStatus === "verified" &&
    isValidDate(state.eventAt) && state.eventAt.getTime() <= at.getTime()
  );
  return {
    effective: resolveEffectiveEntitlementAt(states, at),
    sources: occurredVerified,
    hasVerifiedSource: occurredVerified.length > 0,
    cutoverStatus,
    readAt: at,
  };
}

function aggregateFromSourceAwareRead(
  read: SourceAwareSubscriptionRead,
): LegacySubscriptionAggregate | null {
  if (!read.hasVerifiedSource) return null;
  const aggregate = aggregateLegacySubscription(read.sources, read.readAt);
  return aggregate.kind === "aggregate" ? aggregate.value : null;
}

/**
 * Merges the read-time store projection into a legacy aggregate without
 * treating one verified store snapshot as proof that an ambiguous legacy paid
 * row has been reconciled. Pending cutover is monotonic: a free legacy row may
 * upgrade, but a paid legacy row is never downgraded or metadata-replaced by a
 * lower (or fully expired) store projection until service-role reconciliation
 * marks the user complete.
 */
export function mergeSourceAwareLegacyAggregate(
  legacy: LegacySubscriptionAggregate,
  read: SourceAwareSubscriptionRead,
): SourceAwareLegacyAggregateMerge {
  const source = aggregateFromSourceAwareRead(read);
  if (source == null) {
    return {
      value: legacy,
      sourceAuthoritative: false,
      reason: "no_verified_source",
    };
  }
  if (read.cutoverStatus !== "pending") {
    return {
      value: source,
      sourceAuthoritative: true,
      reason: "cutover_complete",
    };
  }

  const legacyRank = TIER_RANK[legacy.tier];
  const sourceRank = TIER_RANK[source.tier];
  if (sourceRank > legacyRank) {
    return {
      value: source,
      sourceAuthoritative: true,
      reason: "safe_upgrade",
    };
  }
  return {
    value: legacy,
    sourceAuthoritative: false,
    reason: "preserve_legacy_unreconciled",
  };
}

function parseSubscriptionStoreStateRow(
  row: Record<string, unknown>,
  expectedUserId: string,
): SubscriptionStoreState | null {
  if (row.user_id !== expectedUserId) return null;
  const result = reduceStoreSubscriptionEvent(null, {
    store: row.store,
    source: row.verification_source,
    productId: row.product_id,
    basePlanId: row.base_plan_id,
    tier: row.tier,
    status: row.status,
    expiresAt: row.expires_at,
    eventAt: row.event_at,
    eventId: row.event_id,
    verificationStatus: row.verification_status,
    revenueCatEnvironment: row.revenuecat_environment,
  });
  if (result.kind !== "accepted") return null;
  return {
    ...result.state,
    userId: typeof row.user_id === "string" ? row.user_id : undefined,
  };
}

/**
 * Client-facing source-aware read contract. Invalid rows are ignored rather
 * than guessed into entitlements; callers receive the effective complete row
 * plus every parseable store source for diagnostics/reconciliation.
 */
export async function readSourceAwareSubscriptionStates(
  supabase: SubscriptionStoreReadClient,
  userId: string,
  at: Date,
): Promise<SourceAwareSubscriptionStatesResult> {
  let cutoverStatus: LegacyCutoverStatus = "pending";
  const emptyRead = (): SourceAwareSubscriptionRead =>
    buildSourceAwareSubscriptionRead([], at, cutoverStatus);
  try {
    const cutoverResponse = await supabase
      .from("subscription_store_state_reconciliations")
      .select("status")
      .eq("user_id", userId);
    const cutoverRows = Array.isArray(cutoverResponse.data)
      ? cutoverResponse.data
      : [cutoverResponse.data];
    const status = cutoverRows.find((row) =>
      typeof row === "object" && row !== null && !Array.isArray(row)
    ) as Record<string, unknown> | undefined;
    if (status?.status === "complete" || status?.status === "auto") {
      cutoverStatus = status.status;
    }
  } catch {
    // Missing/unavailable reconciliation evidence is deliberately pending.
    // It may only reduce authority, never erase a legacy paid entitlement.
  }

  try {
    const { data, error } = await supabase
      .from("subscription_store_states")
      .select("*")
      .eq("user_id", userId);
    if (error != null) {
      return {
        read: emptyRead(),
        error,
      };
    }
    if (!Array.isArray(data)) {
      return {
        read: emptyRead(),
        error: { message: "invalid subscription store state response" },
      };
    }
    const states = data
      .filter((row): row is Record<string, unknown> =>
        typeof row === "object" && row !== null && !Array.isArray(row)
      )
      .map((row) => parseSubscriptionStoreStateRow(row, userId))
      .filter((state): state is SubscriptionStoreState => state !== null);
    return {
      read: buildSourceAwareSubscriptionRead(states, at, cutoverStatus),
      error: null,
    };
  } catch {
    return {
      read: emptyRead(),
      error: { message: "subscription store state read failed" },
    };
  }
}

function parseLegacyAggregateStatus(value: unknown): SubscriptionStatus {
  if (value === "billing_issue") return "active";
  return isStatus(value) ? value : "active";
}

/** Converts the legacy subscriptions row into the shared aggregate shape. */
export function legacyAggregateFromRow(
  row: Record<string, unknown>,
): LegacySubscriptionAggregate {
  const tier = isTier(row.tier) ? row.tier : "free";
  const store = isStore(row.store) ? row.store : null;
  const productId = asOptionalText(row.active_product_id);
  const expiresAt = asOptionalDate(row.expires_at);
  const environment = row.revenuecat_environment == null
    ? null
    : isRevenueCatEnvironment(row.revenuecat_environment)
    ? row.revenuecat_environment
    : null;
  return {
    tier,
    status: parseLegacyAggregateStatus(row.status),
    expiresAt: expiresAt === undefined ? null : expiresAt,
    activeProductId: productId === undefined ? null : productId,
    store,
    revenueCatEnvironment: environment,
    verificationSource: "legacy_backfill",
  };
}

/** Applies one complete aggregate projection without touching quota counters. */
export function applyLegacyAggregateToRow<T extends Record<string, unknown>>(
  row: T,
  aggregate: LegacySubscriptionAggregate,
): T {
  return {
    ...row,
    tier: aggregate.tier,
    status: aggregate.status,
    expires_at: aggregate.expiresAt?.toISOString() ?? null,
    active_product_id: aggregate.activeProductId,
    store: aggregate.store,
    revenuecat_environment: aggregate.revenueCatEnvironment,
  } as T;
}

/**
 * Shared read-time contract for every quota/entitlement consumer. It queries
 * store rows at the supplied clock and applies the explicit legacy cutover
 * rule; it never trusts the materialized subscriptions.tier alone.
 */
export async function resolveSourceAwareSubscriptionRow<
  T extends Record<string, unknown>,
>(
  supabase: SubscriptionStoreReadClient,
  userId: string,
  legacyRow: T,
  at: Date = new Date(),
): Promise<{
  row: T;
  read: SourceAwareSubscriptionRead;
  merge: SourceAwareLegacyAggregateMerge;
}> {
  const sourceResult = await readSourceAwareSubscriptionStates(
    supabase,
    userId,
    at,
  );
  const legacy = legacyAggregateFromRow(legacyRow);
  if (sourceResult.error != null) {
    return {
      row: legacyRow,
      read: sourceResult.read,
      merge: {
        value: legacy,
        sourceAuthoritative: false,
        reason: "no_verified_source",
      },
    };
  }
  const merge = mergeSourceAwareLegacyAggregate(legacy, sourceResult.read);
  return {
    row: applyLegacyAggregateToRow(legacyRow, merge.value),
    read: sourceResult.read,
    merge,
  };
}

export function aggregateLegacySubscription(
  states: readonly SubscriptionStoreState[],
  at: Date,
): LegacySubscriptionAggregateResult {
  const verified = states.filter((state) =>
    state.verificationStatus === "verified" &&
    isValidDate(state.eventAt) && state.eventAt.getTime() <= at.getTime()
  );
  if (verified.length === 0) {
    return { kind: "preserve", reason: "no_verified_source" };
  }

  const effective = resolveEffectiveEntitlementAt(verified, at);
  const latestVerified =
    [...verified].sort((left, right) =>
      right.eventAt.getTime() - left.eventAt.getTime()
    )[0];
  const source = effective ?? latestVerified;
  const aggregateStatus = effective?.status ?? "expired";

  return {
    kind: "aggregate",
    value: {
      tier: effective?.tier ?? "free",
      status: aggregateStatus === "billing_issue" ? "active" : aggregateStatus,
      expiresAt: source.expiresAt,
      activeProductId: effective?.productId ?? source.productId,
      store: source.store,
      revenueCatEnvironment: source.revenueCatEnvironment,
      verificationSource: source.verificationSource,
    },
  };
}

/**
 * Shared adapter for every RevenueCat state writer. The database RPC owns the
 * row lock and legacy aggregate transaction; callers never update either table
 * directly from a snapshot path.
 */
export async function persistSubscriptionStoreState(
  supabase: SubscriptionStoreRpcClient,
  userId: string,
  event: StoreSubscriptionEventInput,
  options: { resetUsage?: boolean } = {},
): Promise<SubscriptionStorePersistenceResult> {
  if (typeof userId !== "string" || userId.trim().length === 0) {
    return { accepted: false, reason: "invalid" };
  }
  const validation = reduceStoreSubscriptionEvent(null, event);
  if (validation.kind === "ignored") {
    return { accepted: false, reason: validation.reason };
  }

  const state = validation.state;
  let response: { data: unknown; error: { message?: string } | null };
  try {
    response = await supabase.rpc("upsert_subscription_store_state", {
      p_user_id: userId,
      p_store: state.store,
      p_product_id: state.productId,
      p_base_plan_id: state.basePlanId,
      p_tier: state.tier,
      p_status: state.status,
      p_expires_at: state.expiresAt?.toISOString() ?? null,
      p_event_at: state.eventAt.toISOString(),
      p_event_id: state.eventId,
      p_verification_source: state.verificationSource,
      p_verification_status: state.verificationStatus,
      p_revenuecat_environment: state.revenueCatEnvironment,
      p_reset_usage: options.resetUsage === true,
    });
  } catch {
    return { accepted: false, reason: "database_error" };
  }

  if (response.error != null) {
    return { accepted: false, reason: "database_error" };
  }

  const row = Array.isArray(response.data) ? response.data[0] : response.data;
  if (
    typeof row !== "object" || row == null ||
    typeof (row as { accepted?: unknown }).accepted !== "boolean" ||
    typeof (row as { reason?: unknown }).reason !== "string"
  ) {
    return { accepted: false, reason: "invalid_response" };
  }

  const result = row as { accepted: boolean; reason: string };
  const allowedReasons: SubscriptionStorePersistenceReason[] = [
    "accepted",
    "preserve_no_verified_source",
    "preserve_legacy_unreconciled",
    "preserve_verified",
    "duplicate",
    "stale",
    "invalid",
    "store_mismatch",
    "database_error",
    "invalid_response",
  ];
  if (
    !allowedReasons.includes(
      result.reason as SubscriptionStorePersistenceReason,
    )
  ) {
    return { accepted: false, reason: "invalid_response" };
  }
  return {
    accepted: result.accepted,
    reason: result.reason as SubscriptionStorePersistenceReason,
  };
}
