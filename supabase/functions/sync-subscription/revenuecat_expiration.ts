function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function parseDate(value: unknown): Date | null {
  if (typeof value !== "string" || !value.trim()) return null;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function isActiveAt(expiresDate: unknown, now = Date.now()): boolean {
  const parsed = parseDate(expiresDate);
  if (parsed == null) return true;
  return parsed.getTime() > now;
}

export function latestIsoDate(values: Iterable<string | null>): string | null {
  let latest: Date | null = null;

  for (const value of values) {
    const parsed = parseDate(value);
    if (parsed == null) continue;
    if (latest == null || parsed.getTime() > latest.getTime()) {
      latest = parsed;
    }
  }

  return latest?.toISOString() ?? null;
}

export function latestActiveExpirationDateFromRevenueCatPayload(
  subscriber: Record<string, unknown>,
  now = Date.now(),
): string | null {
  const dates: string[] = [];

  const entitlements = isPlainObject(subscriber.entitlements)
    ? subscriber.entitlements
    : {};
  for (const value of Object.values(entitlements)) {
    if (!isPlainObject(value)) continue;
    if (!isActiveAt(value.expires_date, now)) continue;
    if (typeof value.expires_date === "string") {
      dates.push(value.expires_date);
    }
  }

  const subscriptions = isPlainObject(subscriber.subscriptions)
    ? subscriber.subscriptions
    : {};
  for (const value of Object.values(subscriptions)) {
    if (!isPlainObject(value)) continue;
    if (!isActiveAt(value.expires_date, now)) continue;
    if (typeof value.expires_date === "string") {
      dates.push(value.expires_date);
    }
  }

  return latestIsoDate(dates);
}
