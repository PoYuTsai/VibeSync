"use client";

export const dynamic = "force-dynamic";

import { useEffect, useState } from "react";
import { CreditCard, DollarSign, ShieldCheck, Users } from "lucide-react";

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

interface DashboardResponse {
  totalUsers: number;
  activeSubscriptions: number;
  monthlyRevenue: number;
  monthlyProfit: number;
  marginPercent: number;
  aiSuccessRate: number;
}

const EMPTY_STATS: DashboardResponse = {
  totalUsers: 0,
  activeSubscriptions: 0,
  monthlyRevenue: 0,
  monthlyProfit: 0,
  marginPercent: 0,
  aiSuccessRate: 0,
};

export default function DashboardPage() {
  const [stats, setStats] = useState<DashboardResponse>(EMPTY_STATS);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function fetchStats() {
      try {
        const response = await fetch("/api/admin/dashboard", {
          cache: "no-store",
        });
        if (!response.ok) {
          throw new Error("Failed to load dashboard");
        }

        const payload = (await response.json()) as DashboardResponse;
        setStats(payload);
      } catch (error) {
        console.error("Failed to fetch dashboard:", error);
      } finally {
        setLoading(false);
      }
    }

    void fetchStats();
  }, []);

  const cards = [
    {
      title: "Total users",
      value: stats.totalUsers.toLocaleString(),
      description: "Registered real users",
      icon: Users,
    },
    {
      title: "Active subscriptions",
      value: stats.activeSubscriptions.toLocaleString(),
      description: "Starter + Essential",
      icon: CreditCard,
    },
    {
      title: "Monthly revenue",
      value: `$${stats.monthlyRevenue.toLocaleString()}`,
      description: `Profit $${stats.monthlyProfit.toLocaleString()} / margin ${stats.marginPercent}%`,
      icon: DollarSign,
    },
    {
      title: "AI success rate",
      value: `${stats.aiSuccessRate}%`,
      description: "Recent AI success trend",
      icon: ShieldCheck,
    },
  ];

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold">Dashboard</h1>
        <p className="mt-2 text-sm text-gray-500">
          Launch-facing operating summary across users, subscriptions, revenue,
          and AI reliability.
        </p>
      </div>

      {loading ? (
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
          {[1, 2, 3, 4].map((index) => (
            <Card key={index} className="animate-pulse">
              <CardHeader className="pb-2">
                <div className="h-4 w-1/2 rounded bg-gray-200" />
              </CardHeader>
              <CardContent>
                <div className="h-8 w-3/4 rounded bg-gray-200" />
              </CardContent>
            </Card>
          ))}
        </div>
      ) : (
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
          {cards.map((card) => (
            <Card key={card.title}>
              <CardHeader className="flex flex-row items-center justify-between pb-2">
                <CardTitle className="text-sm font-medium text-gray-500">
                  {card.title}
                </CardTitle>
                <card.icon className="h-5 w-5 text-gray-400" />
              </CardHeader>
              <CardContent>
                <div className="text-2xl font-bold">{card.value}</div>
                <p className="mt-1 text-xs text-gray-500">{card.description}</p>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
