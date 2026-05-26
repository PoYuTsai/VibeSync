"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
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
  | "prelaunch_sandbox"
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
  postLaunchTotal: number;
  postLaunchPaidUsers: number;
  postLaunchConversionRate: number;
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
  postLaunchTotal: 0,
  postLaunchPaidUsers: 0,
  postLaunchConversionRate: 0,
  tiers: { free: 0, starter: 0, essential: 0 },
  audiences: {
    prelaunch_sandbox: 0,
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
  prelaunch_sandbox: "上線前沙箱",
  friend_test: "朋友/支持測試",
  production: "正式新用戶",
};

const audienceOptions: AudienceType[] = [
  "prelaunch_sandbox",
  "friend_test",
  "production",
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

function UsersTable({
  users,
  savingUserId,
  emptyMessage,
  onAudienceTypeChange,
}: {
  users: AdminUser[];
  savingUserId: string | null;
  emptyMessage: string;
  onAudienceTypeChange: (userId: string, audienceType: AudienceType) => void;
}) {
  return (
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
                  onAudienceTypeChange(
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
                <div className="text-xs text-gray-500">{formatPlan(user)}</div>
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
              {emptyMessage}
            </TableCell>
          </TableRow>
        ) : null}
      </TableBody>
    </Table>
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

  const postLaunchUsers = useMemo(
    () => users.filter((user) => user.audience_type !== "prelaunch_sandbox"),
    [users]
  );
  const sandboxUsers = useMemo(
    () => users.filter((user) => user.audience_type === "prelaunch_sandbox"),
    [users]
  );

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

      await fetchUsers();
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
            上線前沙箱跟上線後用戶分開看，避免內測帳號影響正式成長判斷。
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

      <div className="rounded-lg border border-indigo-100 bg-white/80 p-4 text-sm text-gray-600">
        <div className="font-semibold text-gray-900">目前還在審核中</div>
        <p className="mt-1">
          上架日期確定前，歷史測試帳號先放在「上線前沙箱」。上架後新增的朋友、支持者或真實用戶，改到「朋友/支持測試」或「正式新用戶」。
        </p>
      </div>

      <div className="grid gap-4 md:grid-cols-3 xl:grid-cols-6">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              全部帳號
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{stats.total}</div>
            <p className="text-xs text-gray-500">不含 test_users</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              上線前沙箱
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {stats.audiences.prelaunch_sandbox}
            </div>
            <p className="text-xs text-gray-500">Eric / Bruce / 歷史測試</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              朋友/支持測試
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {stats.audiences.friend_test}
            </div>
            <p className="text-xs text-gray-500">可轉正式支持者</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              正式新用戶
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {stats.audiences.production}
            </div>
            <p className="text-xs text-gray-500">上架後自然或行銷進來</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              上線後付費
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {stats.postLaunchPaidUsers}
            </div>
            <p className="text-xs text-gray-500">朋友 + 正式新用戶</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              上線後轉換率
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {stats.postLaunchConversionRate}%
            </div>
            <p className="text-xs text-gray-500">上線後付費 / 上線後帳號</p>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>上線後追蹤</CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="animate-pulse space-y-2">
              {[1, 2, 3, 4, 5].map((item) => (
                <div key={item} className="h-10 rounded bg-gray-100" />
              ))}
            </div>
          ) : (
            <UsersTable
              users={postLaunchUsers}
              savingUserId={savingUserId}
              emptyMessage="目前還沒有上線後追蹤用戶。上架日確定後，新朋友或正式用戶會放這裡。"
              onAudienceTypeChange={(userId, audienceType) =>
                void updateAudienceType(userId, audienceType)
              }
            />
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>上線前沙箱 / 專案內測</CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="animate-pulse space-y-2">
              {[1, 2, 3, 4, 5].map((item) => (
                <div key={item} className="h-10 rounded bg-gray-100" />
              ))}
            </div>
          ) : (
            <UsersTable
              users={sandboxUsers}
              savingUserId={savingUserId}
              emptyMessage="目前沒有上線前沙箱帳號。"
              onAudienceTypeChange={(userId, audienceType) =>
                void updateAudienceType(userId, audienceType)
              }
            />
          )}
        </CardContent>
      </Card>
    </div>
  );
}
