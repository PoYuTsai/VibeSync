// components/layout/nav.tsx
"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { cn } from "@/lib/utils";
import {
  Activity,
  AlertCircle,
  CreditCard,
  DollarSign,
  KeyRound,
  LayoutDashboard,
  LogOut,
  TrendingUp,
  Users,
  Zap,
} from "lucide-react";

const navItems = [
  { href: "/", label: "總覽", icon: LayoutDashboard },
  { href: "/users", label: "用戶", icon: Users },
  { href: "/subscriptions", label: "訂閱", icon: CreditCard },
  { href: "/revenue", label: "營收", icon: TrendingUp },
  { href: "/costs", label: "成本", icon: DollarSign },
  { href: "/ai-health", label: "AI 健康", icon: Zap },
  { href: "/errors", label: "錯誤追蹤", icon: AlertCircle },
  { href: "/activity", label: "用戶活動", icon: Activity },
  { href: "/auth-diagnostics", label: "Auth 診斷", icon: KeyRound },
];

export function Nav() {
  const pathname = usePathname();
  const router = useRouter();

  const handleLogout = async () => {
    await fetch("/api/auth/logout", {
      method: "POST",
    });
    router.push("/login");
    router.refresh();
  };

  return (
    <nav className="flex min-h-screen w-64 flex-col bg-gray-900 p-4 text-white">
      <div className="mb-8">
        <h1 className="text-xl font-bold">VibeSync Admin</h1>
      </div>

      <ul className="flex-1 space-y-2">
        {navItems.map((item) => {
          const Icon = item.icon;
          const isActive = pathname === item.href;

          return (
            <li key={item.href}>
              <Link
                href={item.href}
                className={cn(
                  "flex items-center gap-3 rounded-md px-3 py-2 transition-colors",
                  isActive
                    ? "bg-blue-600 text-white"
                    : "text-gray-300 hover:bg-gray-800"
                )}
              >
                <Icon className="h-5 w-5" />
                <span>{item.label}</span>
              </Link>
            </li>
          );
        })}
      </ul>

      <div className="border-t border-gray-800 pt-4">
        <button
          onClick={handleLogout}
          className="flex w-full items-center gap-3 rounded-md px-3 py-2 text-gray-300 hover:bg-gray-800"
        >
          <LogOut className="h-5 w-5" />
          <span>登出</span>
        </button>
      </div>
    </nav>
  );
}
