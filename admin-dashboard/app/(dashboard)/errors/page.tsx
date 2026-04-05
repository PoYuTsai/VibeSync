// app/(dashboard)/errors/page.tsx
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
import { AlertTriangle, AlertCircle, Info } from "lucide-react";

interface ErrorLog {
  id: string;
  created_at: string;
  error_type: string;
  error_message: string;
  user_id: string;
  request_id: string;
}

interface ErrorStats {
  type: string;
  count: number;
}

export default function ErrorsPage() {
  const [errors, setErrors] = useState<ErrorLog[]>([]);
  const [errorStats, setErrorStats] = useState<ErrorStats[]>([]);
  const [loading, setLoading] = useState(true);
  const [totals, setTotals] = useState({
    today: 0,
    thisWeek: 0,
    critical: 0,
  });

  useEffect(() => {
    async function fetchErrors() {
      try {
        // 取得最近的錯誤
        const { data: recentErrors } = await supabase
          .from("ai_logs")
          .select("id, created_at, error_type, error_message, user_id, request_id")
          .eq("status", "failed")
          .order("created_at", { ascending: false })
          .limit(50);

        setErrors(recentErrors || []);

        // 計算錯誤統計
        const now = new Date();
        const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        const weekAgo = new Date(now.setDate(now.getDate() - 7));

        const todayErrors =
          recentErrors?.filter((e) => new Date(e.created_at) >= today).length ||
          0;
        const weekErrors =
          recentErrors?.filter((e) => new Date(e.created_at) >= weekAgo)
            .length || 0;
        const criticalErrors =
          recentErrors?.filter(
            (e) =>
              e.error_type === "API_ERROR" || e.error_type === "TIMEOUT"
          ).length || 0;

        setTotals({
          today: todayErrors,
          thisWeek: weekErrors,
          critical: criticalErrors,
        });

        // 按錯誤類型分組
        const typeMap = new Map<string, number>();
        recentErrors?.forEach((e) => {
          const type = e.error_type || "UNKNOWN";
          typeMap.set(type, (typeMap.get(type) || 0) + 1);
        });

        const stats = Array.from(typeMap.entries())
          .map(([type, count]) => ({ type, count }))
          .sort((a, b) => b.count - a.count);

        setErrorStats(stats);
      } catch (error) {
        console.error("Failed to fetch errors:", error);
      } finally {
        setLoading(false);
      }
    }

    fetchErrors();
  }, []);

  const formatDate = (dateStr: string) => {
    return new Date(dateStr).toLocaleString("zh-TW", {
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
    });
  };

  const getErrorIcon = (type: string) => {
    switch (type) {
      case "API_ERROR":
      case "TIMEOUT":
        return <AlertCircle className="h-4 w-4 text-red-500" />;
      case "RATE_LIMIT":
      case "VALIDATION":
        return <AlertTriangle className="h-4 w-4 text-orange-500" />;
      default:
        return <Info className="h-4 w-4 text-gray-500" />;
    }
  };

  const getErrorBadge = (type: string) => {
    const colors: Record<string, string> = {
      API_ERROR: "bg-red-100 text-red-800",
      TIMEOUT: "bg-red-100 text-red-800",
      RATE_LIMIT: "bg-orange-100 text-orange-800",
      VALIDATION: "bg-yellow-100 text-yellow-800",
      GUARDRAIL: "bg-purple-100 text-purple-800",
      UNKNOWN: "bg-gray-100 text-gray-800",
    };
    return (
      <span
        className={`px-2 py-1 rounded-full text-xs font-medium ${colors[type] || colors.UNKNOWN}`}
      >
        {type}
      </span>
    );
  };

  return (
    <div className="space-y-6">
      <h1 className="text-3xl font-bold">錯誤追蹤</h1>

      <div className="grid gap-4 md:grid-cols-3">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              今日錯誤
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div
              className={`text-2xl font-bold ${totals.today > 10 ? "text-red-600" : "text-gray-900"}`}
            >
              {totals.today}
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              本週錯誤
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{totals.thisWeek}</div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-gray-500">
              嚴重錯誤
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-red-600">
              {totals.critical}
            </div>
            <p className="text-xs text-gray-500">API_ERROR + TIMEOUT</p>
          </CardContent>
        </Card>
      </div>

      <div className="grid gap-4 md:grid-cols-3">
        <Card className="md:col-span-1">
          <CardHeader>
            <CardTitle>錯誤類型分佈</CardTitle>
          </CardHeader>
          <CardContent>
            {loading ? (
              <div className="animate-pulse space-y-2">
                {[1, 2, 3].map((i) => (
                  <div key={i} className="h-8 bg-gray-100 rounded"></div>
                ))}
              </div>
            ) : (
              <div className="space-y-3">
                {errorStats.map((stat) => (
                  <div key={stat.type} className="flex items-center gap-3">
                    {getErrorIcon(stat.type)}
                    <div className="flex-1">
                      <div className="flex justify-between">
                        <span className="text-sm font-medium">{stat.type}</span>
                        <span className="text-sm text-gray-500">
                          {stat.count}
                        </span>
                      </div>
                      <div className="mt-1 h-2 bg-gray-100 rounded-full overflow-hidden">
                        <div
                          className="h-full bg-red-400 rounded-full"
                          style={{
                            width: `${(stat.count / (errors.length || 1)) * 100}%`,
                          }}
                        ></div>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>

        <Card className="md:col-span-2">
          <CardHeader>
            <CardTitle>最近錯誤</CardTitle>
          </CardHeader>
          <CardContent>
            {loading ? (
              <div className="animate-pulse space-y-2">
                {[1, 2, 3, 4, 5].map((i) => (
                  <div key={i} className="h-10 bg-gray-100 rounded"></div>
                ))}
              </div>
            ) : errors.length === 0 ? (
              <div className="text-center py-8 text-gray-500">
                暫無錯誤記錄
              </div>
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>時間</TableHead>
                    <TableHead>類型</TableHead>
                    <TableHead>錯誤訊息</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {errors.slice(0, 10).map((error) => (
                    <TableRow key={error.id}>
                      <TableCell className="whitespace-nowrap">
                        {formatDate(error.created_at)}
                      </TableCell>
                      <TableCell>{getErrorBadge(error.error_type)}</TableCell>
                      <TableCell className="max-w-xs truncate">
                        {error.error_message || "-"}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
