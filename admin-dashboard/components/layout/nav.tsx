"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { OFFICIAL_SITE_LABEL, OFFICIAL_SITE_URL } from "@/lib/external-links";
import { cn } from "@/lib/utils";
import {
  Activity,
  AlertCircle,
  BookOpen,
  ExternalLink,
  Globe2,
  HandCoins,
  LayoutDashboard,
  LogOut,
  TrendingUp,
  Users,
} from "lucide-react";

const navItems = [
  { href: "/", label: "總覽", icon: LayoutDashboard },
  { href: "/users", label: "用戶", icon: Users },
  { href: "/revenue", label: "營收", icon: TrendingUp, aliases: ["/subscriptions"] },
  { href: "/activity", label: "用戶活動", icon: Activity },
  { href: "/finance", label: "財務月結", icon: HandCoins, aliases: ["/costs"] },
  { href: "/articles", label: "文章專區", icon: BookOpen },
  {
    href: "/system",
    label: "系統狀態",
    icon: AlertCircle,
    aliases: ["/ai-health", "/errors", "/auth-diagnostics"],
  },
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
    <nav className="flex min-h-screen w-64 flex-col border-r border-white/10 bg-[#09090e] bg-[linear-gradient(150deg,#09090e_0%,#171236_52%,#2a0b36_100%)] p-4 text-white shadow-2xl shadow-indigo-950/30">
      <div className="mb-5">
        <p className="text-xs font-semibold uppercase tracking-[0.2em] text-indigo-200/70">
          VibeSync
        </p>
        <h1 className="mt-1 bg-gradient-to-r from-indigo-200 via-fuchsia-200 to-indigo-100 bg-clip-text text-xl font-black text-transparent">
          Admin
        </h1>
      </div>

      <a
        href={OFFICIAL_SITE_URL}
        target="_blank"
        rel="noreferrer"
        className="mb-6 rounded-lg border border-white/15 bg-white/10 p-3 text-sm text-white shadow-lg shadow-fuchsia-950/20 backdrop-blur transition-colors hover:bg-white/15"
      >
        <div className="flex items-center gap-2 font-semibold">
          <Globe2 className="h-4 w-4 text-fuchsia-200" />
          <span>{OFFICIAL_SITE_LABEL}</span>
          <ExternalLink className="ml-auto h-3.5 w-3.5 text-indigo-100/80" />
        </div>
        <div className="mt-1 truncate text-xs text-indigo-100/75">
          {OFFICIAL_SITE_URL.replace("https://", "")}
        </div>
      </a>

      <ul className="flex-1 space-y-1.5">
        {navItems.map((item) => {
          const Icon = item.icon;
          const isActive =
            pathname === item.href || item.aliases?.includes(pathname);

          return (
            <li key={item.href}>
              <Link
                href={item.href}
                className={cn(
                  "flex items-center gap-3 rounded-md px-3 py-2 transition-colors",
                  isActive
                    ? "border border-white/15 bg-white/15 text-white shadow-sm"
                    : "text-indigo-100/75 hover:bg-white/10 hover:text-white"
                )}
              >
                <Icon className="h-5 w-5" />
                <span>{item.label}</span>
              </Link>
            </li>
          );
        })}
      </ul>

      <div className="border-t border-white/10 pt-4">
        <button
          onClick={handleLogout}
          className="flex w-full items-center gap-3 rounded-md px-3 py-2 text-indigo-100/75 transition-colors hover:bg-white/10 hover:text-white"
        >
          <LogOut className="h-5 w-5" />
          <span>登出</span>
        </button>
      </div>
    </nav>
  );
}
