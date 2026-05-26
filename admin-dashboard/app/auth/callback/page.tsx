"use client";

import { Suspense, useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { Loader2, ShieldAlert, ShieldCheck } from "lucide-react";
import { supabase } from "@/lib/supabase";

function AuthCallbackContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [message, setMessage] = useState("正在完成 Google 登入...");
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    async function completeLogin() {
      const code = searchParams.get("code");
      const error = searchParams.get("error_description") ?? searchParams.get("error");

      if (error) {
        setFailed(true);
        setMessage(error);
        return;
      }

      if (!code) {
        setFailed(true);
        setMessage("Missing OAuth callback code");
        return;
      }

      const { data, error: exchangeError } =
        await supabase.auth.exchangeCodeForSession(code);

      if (exchangeError || !data.session?.access_token) {
        setFailed(true);
        setMessage(exchangeError?.message || "Unable to complete Google login");
        return;
      }

      setMessage("正在驗證後台白名單...");

      const response = await fetch("/api/auth/session", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ accessToken: data.session.access_token }),
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
  }, [router, searchParams]);

  const Icon = failed ? ShieldAlert : ShieldCheck;

  return (
    <div className="flex min-h-screen items-center justify-center bg-gray-100 px-4">
      <div className="w-full max-w-md rounded-lg border bg-white p-8 text-center shadow-sm">
        <div className="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-md bg-gray-900 text-white">
          {failed ? <Icon className="h-6 w-6" /> : <Loader2 className="h-6 w-6 animate-spin" />}
        </div>
        <h1 className="text-xl font-semibold">VibeSync Admin</h1>
        <p className="mt-2 text-sm text-gray-600">{message}</p>
      </div>
    </div>
  );
}

export default function AuthCallbackPage() {
  return (
    <Suspense
      fallback={
        <div className="flex min-h-screen items-center justify-center bg-gray-100">
          <Loader2 className="h-6 w-6 animate-spin" />
        </div>
      }
    >
      <AuthCallbackContent />
    </Suspense>
  );
}
