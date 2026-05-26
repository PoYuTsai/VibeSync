import { NextResponse } from "next/server";
import { getAdminSession } from "@/lib/server/admin-supabase";

export const dynamic = "force-dynamic";

interface AiLogRow {
  user_id: string | null;
  created_at: string;
}

interface TestUserRow {
  user_id: string | null;
}

function dateKey(value: string): string {
  return new Date(value).toISOString().slice(0, 10);
}

export async function GET() {
  const admin = await getAdminSession();
  if (!admin.ok) {
    return NextResponse.json({ error: admin.error }, { status: admin.status });
  }

  const since = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
  const [logsResult, testUsersResult] = await Promise.all([
    admin.session.supabase
      .from("ai_logs")
      .select("user_id, created_at")
      .gte("created_at", since)
      .order("created_at", { ascending: true })
      .limit(5000),
    admin.session.supabase.from("test_users").select("user_id"),
  ]);

  const firstError = logsResult.error ?? testUsersResult.error;
  if (firstError) {
    return NextResponse.json({ error: firstError.message }, { status: 500 });
  }

  const testUserIds = new Set(
    ((testUsersResult.data ?? []) as TestUserRow[])
      .map((row) => row.user_id)
      .filter((id): id is string => Boolean(id))
  );
  const logs = ((logsResult.data ?? []) as AiLogRow[]).filter(
    (log) => log.user_id && !testUserIds.has(log.user_id)
  );

  const usersByDate = new Map<string, Set<string>>();
  const wauCutoff = Date.now() - 7 * 24 * 60 * 60 * 1000;
  const wauUsers = new Set<string>();
  const mauUsers = new Set<string>();

  for (const log of logs) {
    if (!log.user_id) continue;
    const key = dateKey(log.created_at);
    const set = usersByDate.get(key) ?? new Set<string>();
    set.add(log.user_id);
    usersByDate.set(key, set);
    mauUsers.add(log.user_id);
    if (new Date(log.created_at).getTime() >= wauCutoff) {
      wauUsers.add(log.user_id);
    }
  }

  const activityData = Array.from(usersByDate.entries()).map(([date, users]) => ({
    date,
    dau: users.size,
  }));
  const avgDAU =
    activityData.length > 0
      ? Math.round(
          activityData.reduce((sum, row) => sum + row.dau, 0) /
            activityData.length
        )
      : 0;

  return NextResponse.json({
    activityData,
    summary: {
      todayDAU: activityData.at(-1)?.dau ?? 0,
      avgDAU,
      peakDAU:
        activityData.length > 0
          ? Math.max(...activityData.map((row) => row.dau))
          : 0,
      wau: wauUsers.size,
      mau: mauUsers.size,
    },
  });
}
