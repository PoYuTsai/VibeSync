// app/(dashboard)/page.tsx
"use client";

export const dynamic = "force-dynamic";

import { useEffect, useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { supabase } from "@/lib/supabase";
import { Users, CreditCard, DollarSign, Zap } from "lucide-react";

interface DashboardStats {
  totalUsers: number;
  activeSubscriptions: number;
  monthlyRevenue: number;
  aiSuccessRate: number;
}

export default function DashboardPage() {
  const [stats, setStats] = useState<DashboardStats>({
    totalUsers: 0,
    activeSubscriptions: 0,
    monthlyRevenue: 0,
    aiSuccessRate: 0,
  });
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function fetchStats() {
      try {
        // 取得真實用戶數 (排除測試帳號)
        const { count: userCount } = await supabase
          .from("real_users")
          .select("*", { count: "exact", head: true });

        // 取得活躍訂閱數
        const { count: subCount } = await supabase
          .from("real_subscriptions")
          .select("*", { count: "exact", head: true })
          .eq("status", "active");

        // 取得本月營收
        const { data: profitData } = await supabase
          .from("monthly_profit")
          .select("revenue")
          .order("month", { ascending: false })
          .limit(1)
          .single();

        // 取得 AI 成功率 (近 7 天平均)
        const { data: aiData } = await supabase
          .from("ai_success_rate")
          .select("success_rate")
          .order("date", { ascending: false })
          .limit(7);

        const avgSuccessRate = aiData?.length
          ? aiData.reduce((sum, d) => sum + Number(d.success_rate), 0) / aiData.length
          : 0;

        setStats({
          totalUsers: userCount || 0,
          activeSubscriptions: subCount || 0,
          monthlyRevenue: profitData?.revenue || 0,
          aiSuccessRate: Math.round(avgSuccessRate * 100) / 100,
        });
      } catch (error) {
        console.error("Failed to fetch stats:", error);
      } finally {
        setLoading(false);
      }
    }

    fetchStats();
  }, []);

  const kpiCards = [
    {
      title: "總用戶數",
      value: stats.totalUsers.toLocaleString(),
      icon: Users,
      description: "排除測試帳號",
    },
    {
      title: "活躍訂閱",
      value: stats.activeSubscriptions.toLocaleString(),
      icon: CreditCard,
      description: "Starter + Essential",
    },
    {
      title: "本月營收",
      value: `$${stats.monthlyRevenue.toLocaleString()}`,
      icon: DollarSign,
      description: "USD",
    },
    {
      title: "AI 成功率",
      value: `${stats.aiSuccessRate}%`,
      icon: Zap,
      description: "近 7 天平均",
    },
  ];

  return (
    <div className="space-y-6">
      <h1 className="text-3xl font-bold">總覽</h1>

      {loading ? (
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
          {[1, 2, 3, 4].map((i) => (
            <Card key={i} className="animate-pulse">
              <CardHeader className="pb-2">
                <div className="h-4 bg-gray-200 rounded w-1/2"></div>
              </CardHeader>
              <CardContent>
                <div className="h-8 bg-gray-200 rounded w-3/4"></div>
              </CardContent>
            </Card>
          ))}
        </div>
      ) : (
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
          {kpiCards.map((card) => (
            <Card key={card.title}>
              <CardHeader className="flex flex-row items-center justify-between pb-2">
                <CardTitle className="text-sm font-medium text-gray-500">
                  {card.title}
                </CardTitle>
                <card.icon className="h-5 w-5 text-gray-400" />
              </CardHeader>
              <CardContent>
                <div className="text-2xl font-bold">{card.value}</div>
                <p className="text-xs text-gray-500 mt-1">{card.description}</p>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
