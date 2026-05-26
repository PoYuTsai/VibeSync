import Link from "next/link";
import {
  AlertCircle,
  ArrowRight,
  DollarSign,
  KeyRound,
  Server,
  Zap,
} from "lucide-react";
import { Card, CardContent } from "@/components/ui/card";

const systemItems = [
  {
    href: "/ai-health",
    title: "AI 健康",
    description: "AI 成功率、失敗數、guardrail 過濾。生成怪怪的時候先看這裡。",
    icon: Zap,
  },
  {
    href: "/errors",
    title: "錯誤追蹤",
    description: "近 7 天錯誤、API timeout、rate limit。有人回報壞掉時看這裡。",
    icon: AlertCircle,
  },
  {
    href: "/auth-diagnostics",
    title: "Auth 診斷",
    description: "登入、註冊、重設密碼、deep link。帳號問題時再打開。",
    icon: KeyRound,
  },
  {
    href: "/costs",
    title: "AI 成本明細",
    description: "Claude / token usage 造成的 AI 成本。月結仍以財務月結為主。",
    icon: DollarSign,
  },
];

export default function SystemPage() {
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold">系統狀態</h1>
        <p className="mt-2 text-sm text-gray-600">
          這裡放出問題才需要看的工程診斷工具，平常營運不用每天點。
        </p>
      </div>

      <Card className="overflow-hidden bg-[#0e0a24] bg-[linear-gradient(135deg,#09090e_0%,#171236_48%,#2a0b36_100%)] text-white">
        <CardContent className="flex flex-col gap-4 p-5 md:flex-row md:items-center">
          <div className="flex h-12 w-12 items-center justify-center rounded-lg border border-white/15 bg-white/10">
            <Server className="h-6 w-6 text-fuchsia-100" />
          </div>
          <div>
            <div className="text-lg font-semibold">平常先看總覽、用戶、營收、活動</div>
            <p className="mt-1 text-sm text-indigo-100/75">
              系統狀態是排查用，不放在主流程裡，避免後台變成工程 debug 面板。
            </p>
          </div>
        </CardContent>
      </Card>

      <div className="grid gap-4 md:grid-cols-2">
        {systemItems.map((item) => {
          const Icon = item.icon;

          return (
            <Link key={item.href} href={item.href}>
              <Card className="h-full transition-transform hover:-translate-y-0.5 hover:shadow-xl">
                <CardContent className="flex h-full items-start gap-4 p-5">
                  <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-indigo-50 text-indigo-700">
                    <Icon className="h-5 w-5" />
                  </div>
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2">
                      <h2 className="font-semibold">{item.title}</h2>
                      <ArrowRight className="ml-auto h-4 w-4 text-gray-400" />
                    </div>
                    <p className="mt-2 text-sm leading-relaxed text-gray-600">
                      {item.description}
                    </p>
                  </div>
                </CardContent>
              </Card>
            </Link>
          );
        })}
      </div>
    </div>
  );
}
