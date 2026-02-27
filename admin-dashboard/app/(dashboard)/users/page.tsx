// app/(dashboard)/users/page.tsx
"use client";

export const dynamic = "force-dynamic";

import { useEffect, useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { supabase } from "@/lib/supabase";

interface User {
  id: string;
  email: string;
  created_at: string;
  subscription_tier?: string;
}

export default function UsersPage() {
  const [users, setUsers] = useState<User[]>([]);
  const [loading, setLoading] = useState(true);
  const [stats, setStats] = useState({
    total: 0,
    thisMonth: 0,
    thisWeek: 0,
  });

  useEffect(() => {
    async function fetchUsers() {
      try {
        // 取得用戶列表 (排除測試帳號)
        const { data, count } = await supabase
          .from("real_users")
          .select("id, email, created_at", { count: "exact" })
          .order("created_at", { ascending: false })
          .limit(50);

        // 取得訂閱資訊
        const userIds = data?.map((u) => u.id) || [];
        const { data: subs } = await supabase
          .from("subscriptions")
          .select("user_id, tier")
          .in("user_id", userIds)
          .eq("status", "active");

        const subMap = new Map(subs?.map((s) => [s.user_id, s.tier]));

        const usersWithSub = data?.map((u) => ({
          ...u,
          subscription_tier: subMap.get(u.id) || "free",
        }));

        setUsers(usersWithSub || []);

        // 計算統計
        const now = new Date();
        const thisMonth = new Date(now.getFullYear(), now.getMonth(), 1);
        const thisWeek = new Date(now.setDate(now.getDate() - 7));

        const monthUsers = data?.filter(
          (u) => new Date(u.created_at) >= thisMonth
        ).length;
        const weekUsers = data?.filter(
          (u) => new Date(u.created_at) >= thisWeek
        ).length;

        setStats({
          total: count || 0,
          thisMonth: monthUsers || 0,
          thisWeek: weekUsers || 0,
        });
      } catch (error) {
        console.error("Failed to fetch users:", error);
      } finally {
        setLoading(false);
      }
    }

    fetchUsers();
  }, []);

  const formatDate = (dateStr: string) => {
    return new Date(dateStr).toLocaleDateString("zh-TW", {
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    });
  };

  const getTierBadge = (tier: string) => {
    const colors: Record<string, string> = {
      free: "bg-gray-100 text-gray-800",
      starter: "bg-blue-100 text-blue-800",
      essential: "bg-purple-100 text-purple-800",
    };
    return (
      <span
        className={`px-2 py-1 rounded-full text-xs font-medium ${colors[tier] || colors.free}`}
      >
        {tier.charAt(0).toUpperCase() + tier.slice(1)}
      </span>
    );
  };

  return (
    <div className="space-y-6">
      <h1 className="text-3xl font-bold">用戶</h1>

      <div className="grid gap-4 md:grid-cols-3">
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
              本週新增
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{stats.thisWeek}</div>
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
              {[1, 2, 3, 4, 5].map((i) => (
                <div key={i} className="h-10 bg-gray-100 rounded"></div>
              ))}
            </div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Email</TableHead>
                  <TableHead>訂閱方案</TableHead>
                  <TableHead>註冊日期</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {users.map((user) => (
                  <TableRow key={user.id}>
                    <TableCell className="font-medium">{user.email}</TableCell>
                    <TableCell>{getTierBadge(user.subscription_tier || "free")}</TableCell>
                    <TableCell>{formatDate(user.created_at)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
