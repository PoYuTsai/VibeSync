"use client";

import { Suspense, useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { Loader2, ShieldAlert, ShieldCheck } from "lucide-react";
import { supabase } from "@/lib/supabase";
import {
  callbackUrlErrorMessage,
  callbackExchangeErrorMessage,
} from "@/lib/operations/admin-legacy-visible";

function AuthCallbackContent({ adminV2 }: { adminV2: boolean }) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [message, setMessage] = useState("正在完成 Google 登入...");
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    async function completeLogin() {
      const code = searchParams.get("code");
      const error = searchParams.get("error_description") ?? searchParams.get("error");
      const hashParams =
        typeof window === "undefined"
          ? new URLSearchParams()
          : new URLSearchParams(window.location.hash.replace(/^#/, ""));

      if (error) {
        // 旗標關閉重現 pre-B1（直接回顯 URL 帶進來的錯誤）；開啟才 generic。
        setFailed(true);
        setMessage(callbackUrlErrorMessage(adminV2, error));
        return;
      }

      let accessToken = hashParams.get("access_token");

      if (code) {
        const { data, error: exchangeError } =
          await supabase.auth.exchangeCodeForSession(code);

        if (exchangeError || !data.session?.access_token) {
          setFailed(true);
          setMessage(callbackExchangeErrorMessage(adminV2, exchangeError?.message));
          return;
        }

        accessToken = data.session.access_token;
      }

      if (!accessToken) {
        const { data } = await supabase.auth.getSession();
        accessToken = data.session?.access_token ?? null;
      }

      if (!accessToken) {
        setFailed(true);
        setMessage("請從登入頁按「使用 Google 登入」，不要直接打開 callback URL。");
        return;
      }

      setMessage("正在驗證後台白名單...");

      const response = await fetch("/api/auth/session", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ accessToken }),
      });

      if (!response.ok) {
        await supabase.auth.signOut();
        router.replace(response.status === 403 ? "/403" : "/login");
        return;
      }

      router.replace("/");
      router.refresh();
    }

    void completeLogin();
  }, [router, searchParams, adminV2]);

  const Icon = failed ? ShieldAlert : ShieldCheck;

  return (
    <div className="flex min-h-screen items-center justify-center bg-gray-100 px-4">
      <div className="w-full max-w-md rounded-lg border bg-white p-8 text-center shadow-sm">
        <div className="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-md bg-gray-900 text-white">
          {failed ? (
            <Icon className="h-6 w-6" />
          ) : (
            <Loader2 className="h-6 w-6 animate-spin" />
          )}
        </div>
        <h1 className="text-xl font-semibold">VibeSync Admin</h1>
        <p className="mt-2 text-sm text-gray-600">{message}</p>
      </div>
    </div>
  );
}

// adminV2 由 server component 在 request 時決定後下發；client 不讀私有 env。
export function AuthCallbackClient({ adminV2 }: { adminV2: boolean }) {
  return (
    <Suspense
      fallback={
        <div className="flex min-h-screen items-center justify-center bg-gray-100">
          <Loader2 className="h-6 w-6 animate-spin" />
        </div>
      }
    >
      <AuthCallbackContent adminV2={adminV2} />
    </Suspense>
  );
}
