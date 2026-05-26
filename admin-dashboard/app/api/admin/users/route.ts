import { NextResponse } from "next/server";
import { getAdminSession } from "@/lib/server/admin-supabase";

export const dynamic = "force-dynamic";

type Tier = "free" | "starter" | "essential";
type AudienceType =
  | "unknown"
  | "prelaunch_sandbox"
  | "internal"
  | "friend_test"
  | "production";

const AUDIENCE_TYPES: AudienceType[] = [
  "unknown",
  "prelaunch_sandbox",
  "internal",
  "friend_test",
  "production",
];

interface DbUser {
  id: string;
  email: string;
  created_at: string;
  last_login_at: string | null;
  total_analyses: number | null;
  total_conversations: number | null;
}

interface DbSubscription {
  user_id: string;
  tier: Tier | string | null;
  status: string | null;
  expires_at: string | null;
  active_product_id: string | null;
  billing_period: string | null;
  monthly_messages_used: number | null;
  daily_messages_used: number | null;
  monthly_reset_at: string | null;
  daily_reset_at: string | null;
}

interface DbUserLabel {
  user_id: string;
  audience_type: AudienceType | string | null;
  notes: string | null;
  updated_at: string | null;
}

function isAudienceType(value: unknown): value is AudienceType {
  return typeof value === "string" &&
    AUDIENCE_TYPES.includes(value as AudienceType);
}

function normalizeTier(tier: string | null | undefined): Tier {
  return tier === "starter" || tier === "essential" ? tier : "free";
}

function normalizeBillingPeriod(value: string | null | undefined): string {
  if (value === "monthly" || value === "quarterly") {
    return value;
  }

  return "unknown";
}

function normalizeAudienceType(value: unknown): AudienceType {
  return isAudienceType(value) ? value : "unknown";
}

function hasFutureExpiration(subscription: DbSubscription): boolean {
  if (!subscription.expires_at) {
    return false;
  }

  const expiresAt = new Date(subscription.expires_at).getTime();
  return Number.isFinite(expiresAt) && expiresAt > Date.now();
}

function hasPaidEntitlement(subscription: DbSubscription | undefined): boolean {
  if (!subscription) {
    return false;
  }

  const tier = normalizeTier(subscription.tier);
  if (tier === "free") {
    return false;
  }

  if (subscription.status === "active") {
    return true;
  }

  return subscription.status === "cancelled" && hasFutureExpiration(subscription);
}

function effectiveTier(subscription: DbSubscription | undefined): Tier {
  if (!hasPaidEntitlement(subscription)) {
    return "free";
  }

  return normalizeTier(subscription?.tier);
}

function statusLabel(subscription: DbSubscription | undefined): string {
  if (!subscription) {
    return "missing";
  }

  if (subscription.status === "cancelled" && hasPaidEntitlement(subscription)) {
    return "cancelled_until_expiry";
  }

  return subscription.status ?? "unknown";
}

function createdAfter(user: DbUser, date: Date): boolean {
  return new Date(user.created_at) >= date;
}

export async function GET() {
  const admin = await getAdminSession();

  if (!admin.ok) {
    return NextResponse.json(
      { error: admin.error },
      { status: admin.status }
    );
  }

  const { supabase } = admin.session;

  const { data: testUsers, error: testUsersError } = await supabase
    .from("test_users")
    .select("user_id");

  if (testUsersError) {
    return NextResponse.json(
      { error: testUsersError.message },
      { status: 500 }
    );
  }

  const testUserIds = new Set(
    (testUsers ?? [])
      .map((row) => row.user_id as string | null)
      .filter((id): id is string => Boolean(id))
  );

  const { data: users, error: usersError } = await supabase
    .from("users")
    .select(
      "id, email, created_at, last_login_at, total_analyses, total_conversations"
    )
    .order("created_at", { ascending: false })
    .limit(1000);

  if (usersError) {
    return NextResponse.json(
      { error: usersError.message },
      { status: 500 }
    );
  }

  const realUsers = ((users ?? []) as DbUser[]).filter(
    (user) => !testUserIds.has(user.id)
  );
  const userIds = realUsers.map((user) => user.id);

  let subscriptions: DbSubscription[] = [];
  let userLabels: DbUserLabel[] = [];

  if (userIds.length > 0) {
    const { data: subscriptionRows, error: subscriptionsError } = await supabase
      .from("subscriptions")
      .select(
        "user_id, tier, status, expires_at, active_product_id, billing_period, monthly_messages_used, daily_messages_used, monthly_reset_at, daily_reset_at"
      )
      .in("user_id", userIds);

    if (subscriptionsError) {
      return NextResponse.json(
        { error: subscriptionsError.message },
        { status: 500 }
      );
    }

    subscriptions = (subscriptionRows ?? []) as DbSubscription[];

    const { data: labelRows, error: labelsError } = await supabase
      .from("admin_user_labels")
      .select("user_id, audience_type, notes, updated_at")
      .in("user_id", userIds);

    if (labelsError) {
      return NextResponse.json(
        { error: labelsError.message },
        { status: 500 }
      );
    }

    userLabels = (labelRows ?? []) as DbUserLabel[];
  }

  const subscriptionByUserId = new Map(
    subscriptions.map((subscription) => [subscription.user_id, subscription])
  );
  const labelByUserId = new Map(
    userLabels.map((label) => [label.user_id, label])
  );

  const enrichedUsers = realUsers.slice(0, 50).map((user) => {
    const subscription = subscriptionByUserId.get(user.id);
    const label = labelByUserId.get(user.id);
    const tier = effectiveTier(subscription);

    return {
      ...user,
      subscription_tier: tier,
      raw_subscription_tier: normalizeTier(subscription?.tier),
      subscription_status: statusLabel(subscription),
      active_product_id: subscription?.active_product_id ?? null,
      billing_period: normalizeBillingPeriod(subscription?.billing_period),
      expires_at: subscription?.expires_at ?? null,
      monthly_messages_used: subscription?.monthly_messages_used ?? 0,
      daily_messages_used: subscription?.daily_messages_used ?? 0,
      monthly_reset_at: subscription?.monthly_reset_at ?? null,
      daily_reset_at: subscription?.daily_reset_at ?? null,
      audience_type: normalizeAudienceType(label?.audience_type),
      audience_notes: label?.notes ?? null,
      audience_updated_at: label?.updated_at ?? null,
    };
  });

  const now = new Date();
  const thisMonth = new Date(now.getFullYear(), now.getMonth(), 1);
  const thisWeek = new Date(now);
  thisWeek.setDate(thisWeek.getDate() - 7);

  const tierCounts = realUsers.reduce<Record<Tier, number>>(
    (counts, user) => {
      const tier = effectiveTier(subscriptionByUserId.get(user.id));
      counts[tier] += 1;
      return counts;
    },
    { free: 0, starter: 0, essential: 0 }
  );

  const paidUsers = tierCounts.starter + tierCounts.essential;
  const audienceCounts = realUsers.reduce<Record<AudienceType, number>>(
    (counts, user) => {
      const label = labelByUserId.get(user.id);
      const audienceType = normalizeAudienceType(label?.audience_type);
      counts[audienceType] += 1;
      return counts;
    },
    {
      unknown: 0,
      prelaunch_sandbox: 0,
      internal: 0,
      friend_test: 0,
      production: 0,
    }
  );

  return NextResponse.json({
    users: enrichedUsers,
    stats: {
      total: realUsers.length,
      thisMonth: realUsers.filter((user) => createdAfter(user, thisMonth))
        .length,
      thisWeek: realUsers.filter((user) => createdAfter(user, thisWeek))
        .length,
      paidUsers,
      conversionRate:
        realUsers.length > 0
          ? Math.round((paidUsers / realUsers.length) * 100)
          : 0,
      tiers: tierCounts,
      audiences: audienceCounts,
    },
  });
}

export async function PATCH(req: Request) {
  const admin = await getAdminSession();

  if (!admin.ok) {
    return NextResponse.json(
      { error: admin.error },
      { status: admin.status }
    );
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const payload = body as Record<string, unknown>;
  const userId = typeof payload.userId === "string"
    ? payload.userId.trim()
    : "";
  const audienceType = normalizeAudienceType(payload.audienceType);
  const notes = typeof payload.notes === "string"
    ? payload.notes.trim().slice(0, 500)
    : null;

  if (!userId) {
    return NextResponse.json({ error: "Missing userId" }, { status: 400 });
  }

  if (!isAudienceType(payload.audienceType)) {
    return NextResponse.json(
      { error: "Invalid audienceType" },
      { status: 400 }
    );
  }

  const { supabase, user } = admin.session;
  const { data, error } = await supabase
    .from("admin_user_labels")
    .upsert(
      {
        user_id: userId,
        audience_type: audienceType,
        notes,
        updated_by: user.id,
      },
      { onConflict: "user_id" }
    )
    .select("user_id, audience_type, notes, updated_at")
    .single();

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({
    label: {
      user_id: data.user_id,
      audience_type: normalizeAudienceType(data.audience_type),
      notes: data.notes ?? null,
      updated_at: data.updated_at ?? null,
    },
  });
}
