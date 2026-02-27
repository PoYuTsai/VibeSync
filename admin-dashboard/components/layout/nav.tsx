// components/layout/nav.tsx
"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { cn } from "@/lib/utils";
import {
  LayoutDashboard,
  Users,
  CreditCard,
  TrendingUp,
  DollarSign,
  Zap,
  AlertCircle,
  Activity,
  LogOut,
} from "lucide-react";
import { supabase } from "@/lib/supabase";

const navItems = [
  { href: "/", label: "總覽", icon: LayoutDashboard },
  { href: "/users", label: "用戶", icon: Users },
  { href: "/subscriptions", label: "訂閱", icon: CreditCard },
  { href: "/revenue", label: "營收", icon: TrendingUp },
  { href: "/costs", label: "成本", icon: DollarSign },
  { href: "/ai-health", label: "AI 健康度", icon: Zap },
  { href: "/errors", label: "錯誤追蹤", icon: AlertCircle },
  { href: "/activity", label: "用戶活躍度", icon: Activity },
];

export function Nav() {
  const pathname = usePathname();
  const router = useRouter();

  const handleLogout = async () => {
    await supabase.auth.signOut();
    document.cookie = "sb-access-token=; path=/; expires=Thu, 01 Jan 1970 00:00:00 GMT";
    router.push("/login");
  };

  return (
    <nav className="w-64 bg-gray-900 text-white min-h-screen p-4 flex flex-col">
      <div className="mb-8">
        <h1 className="text-xl font-bold">VibeSync Admin</h1>
      </div>

      <ul className="space-y-2 flex-1">
        {navItems.map((item) => {
          const Icon = item.icon;
          const isActive = pathname === item.href;

          return (
            <li key={item.href}>
              <Link
                href={item.href}
                className={cn(
                  "flex items-center gap-3 px-3 py-2 rounded-md transition-colors",
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

      <div className="pt-4 border-t border-gray-800">
        <button
          onClick={handleLogout}
          className="flex items-center gap-3 px-3 py-2 rounded-md text-gray-300 hover:bg-gray-800 w-full"
        >
          <LogOut className="h-5 w-5" />
          <span>登出</span>
        </button>
      </div>
    </nav>
  );
}
