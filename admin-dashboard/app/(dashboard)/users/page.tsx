"use client";

import { useCallback, useEffect, useState } from "react";
import { RefreshCcw } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

type Tier = "free" | "starter" | "essential";
type AudienceType =
  | "unknown"
  | "prelaunch_sandbox"
  | "internal"
  | "friend_test"
  | "production";

interface AdminUser {
  id: string;
  email: string;
  created_at: string;
  last_login_at: string | null;
  total_analyses: number | null;
  total_conversations: number | null;
  subscription_tier: Tier;
  raw_subscription_tier: Tier;
  subscription_status: string;
  active_product_id: string | null;
  billing_period: string;
  expires_at: string | null;
  monthly_messages_used: number;
  daily_messages_used: number;
  audience_type: AudienceType;
  audience_notes: string | null;
  audience_updated_at: string | null;
}

interface UserStats {
  total: number;
  thisMonth: number;
  thisWeek: number;
  paidUsers: number;
  conversionRate: number;
  tiers: Record<Tier, number>;
  audiences: Record<AudienceType, number>;
}

interface UsersResponse {
  users: AdminUser[];
  stats: UserStats;
  error?: string;
}

const emptyStats: UserStats = {
  total: 0,
  thisMonth: 0,
  thisWeek: 0,
  paidUsers: 0,
  conversionRate: 0,
  tiers: { free: 0, starter: 0, essential: 0 },
  audiences: {
    unknown: 0,
    prelaunch_sandbox: 0,
    internal: 0,
    friend_test: 0,
    production: 0,
  },
};

const tierLabels: Record<Tier, string> = {
  free: "Free",
  starter: "Starter",
  essential: "Essential",
};

const tierBadgeClasses: Record<Tier, string> = {
  free: "bg-gray-100 text-gray-700",
  starter: "bg-blue-100 text-blue-700",
  essential: "bg-purple-100 text-purple-700",
};

const billingPeriodLabels: Record<string, string> = {
  monthly: "月繳",
  quarterly: "季繳",
  unknown: "週期未同步",
};

const audienceLabels: Record<AudienceType, string> = {
  unknown: "未分類",
  prelaunch_sandbox: "上線前沙箱",
  internal: "內部測試",
  friend_test: "朋友測試",
  production: "正式用戶",
};

const audienceOptions: AudienceType[] = [
  "prelaunch_sandbox",
  "internal",
  "friend_test",
  "production",
  "unknown",
];

const statusLabels: Record<string, string> = {
  active: "有效",
  cancelled: "已取消續訂",
  cancelled_until_expiry: "已取消續訂，仍有效",
  expired: "已過期",
  missing: "缺少訂閱列",
};

function formatDate(date: string | null): string {
  if (!date) {
    return "-";
  }

  return new Date(date).toLocaleDateString("zh-TW", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
}

function formatStatus(status: string): string {
  return statusLabels[status] ?? status;
}

function formatUsage(user: AdminUser): string {
  return `${user.monthly_messages_used} / ${user.daily_messages_used}`;
}

function formatPlan(user: AdminUser): string {
  if (user.subscription_tier === "free") {
    return "Free";
  }

  const tier = tierLabels[user.subscription_tier];
  const period = billingPeriodLabels[user.billing_period] ??
    billingPeriodLabels.unknown;
  return `${tier} ${period}`;
}

function TierBadge({ tier }: { tier: Tier }) {
  return (
    <span
      className={`inline-flex rounded-full px-2 py-1 text-xs font-medium ${tierBadgeClasses[tier]}`}
    >
      {tierLabels[tier]}
    </span>
  );
}

export default function UsersPage() {
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [stats, setStats] = useState<UserStats>(emptyStats);
  const [loading, setLoading] = useState(true);
  const [savingUserId, setSavingUserId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const fetchUsers = useCallback(async () => {
    setLoading(true);
    setError(null);

    try {
      const response = await fetch("/api/admin/users", {
        credentials: "same-origin",
      });
      const payload = (await response.json()) as UsersResponse;

      if (!response.ok) {
        throw new Error(payload.error ?? "讀取用戶資料失敗");
      }

      setUsers(payload.users);
      setStats(payload.stats);
    } catch (fetchError) {
      setError(fetchError instanceof Error ? fetchError.message : "讀取失敗");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void fetchUsers();
  }, [fetchUsers]);

  const updateAudienceType = async (
    userId: string,
    audienceType: AudienceType
  ) => {
    setSavingUserId(userId);
    setError(null);

    try {
      const response = await fetch("/api/admin/users", {
        method: "PATCH",
        credentials: "same-origin",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ userId, audienceType }),
      });
      const payload = (await response.json()) as {
        label?: {
          audience_type: AudienceType;
          notes: string | null;
          updated_at: string | null;
        };
        error?: string;
      };

      if (!response.ok || !payload.label) {
        throw new Error(payload.error ?? "更新用戶分類失敗");
      }

      setUsers((current) =>
        current.map((user) =>
          user.id === userId
            ? {
                ...user,
                audience_type: payload.label!.audience_type,
                audience_notes: payload.label!.notes,
                audience_updated_at: payload.label!.updated_at,
              }
            : user
        )
      );
      setStats((current) => {
        const previous = users.find((user) => user.id === userId)
          ?.audience_type;
        if (!previous || previous === payload.label!.audience_type) {
          return current;
        }

        return {
          ...current,
          audiences: {
            ...current.audiences,
            [previous]: Math.max(0, current.audiences[previous] - 1),
            [payload.label!.audience_type]:
              current.audiences[payload.label!.audience_type] + 1,
          },
        };
      });
    } catch (updateError) {
      setError(updateError instanceof Error ? updateError.message : "更新失敗");
    } finally {
      setSavingUserId(null);
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold">用戶</h1>
          <p className="mt-1 text-sm text-gray-500">
            依 Supabase subscriptions 顯示目前可用權益，cancelled 但未到期仍列為付費權益。
          </p>
        </div>
        <Button
          type="button"
          variant="outline"
          onClick={() => void fetchUsers()}
          disabled={loading}
        >
          <RefreshCcw className="h-4 w-4" />
          重新整理
        </Button>
      </div>

      {error ? (
        <div className="rounded-md border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
          {error}
        </div>
      ) : null}

      <div className="grid gap-4 md:grid-cols-5">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              總用戶數
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{stats.total}</div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              付費用戶
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{stats.paidUsers}</div>
            <p className="text-xs text-gray-500">Starter + Essential</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              本月新增
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{stats.thisMonth}</div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              轉換率
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{stats.conversionRate}%</div>
            <p className="text-xs text-gray-500">付費 / 總用戶</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              正式用戶
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {stats.audiences.production}
            </div>
            <p className="text-xs text-gray-500">
              朋友測試 {stats.audiences.friend_test}
            </p>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>最近註冊用戶</CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="animate-pulse space-y-2">
              {[1, 2, 3, 4, 5].map((item) => (
                <div key={item} className="h-10 rounded bg-gray-100" />
              ))}
            </div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Email</TableHead>
                  <TableHead>用戶分類</TableHead>
                  <TableHead>訂閱方案</TableHead>
                  <TableHead>狀態</TableHead>
                  <TableHead>月 / 日用量</TableHead>
                  <TableHead>到期日</TableHead>
                  <TableHead>註冊日期</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {users.map((user) => (
                  <TableRow key={user.id}>
                    <TableCell className="font-medium">{user.email}</TableCell>
                    <TableCell>
                      <select
                        className="h-9 rounded-md border bg-white px-2 text-sm"
                        value={user.audience_type}
                        disabled={savingUserId === user.id}
                        onChange={(event) =>
                          void updateAudienceType(
                            user.id,
                            event.target.value as AudienceType
                          )
                        }
                      >
                        {audienceOptions.map((option) => (
                          <option key={option} value={option}>
                            {audienceLabels[option]}
                          </option>
                        ))}
                      </select>
                    </TableCell>
                    <TableCell>
                      <div className="space-y-1">
                        <TierBadge tier={user.subscription_tier} />
                        <div className="text-xs text-gray-500">
                          {formatPlan(user)}
                        </div>
                      </div>
                    </TableCell>
                    <TableCell className="capitalize">
                      {formatStatus(user.subscription_status)}
                    </TableCell>
                    <TableCell>{formatUsage(user)}</TableCell>
                    <TableCell>{formatDate(user.expires_at)}</TableCell>
                    <TableCell>{formatDate(user.created_at)}</TableCell>
                  </TableRow>
                ))}
                {users.length === 0 ? (
                  <TableRow>
                    <TableCell colSpan={7} className="py-8 text-center text-gray-500">
                      目前沒有用戶資料
                    </TableCell>
                  </TableRow>
                ) : null}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
