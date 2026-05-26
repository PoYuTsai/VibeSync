"use client";

import { useState } from "react";
import { Chrome, ShieldCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { supabase, isSupabaseConfigured } from "@/lib/supabase";

export default function LoginPage() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleGoogleLogin = async () => {
    setLoading(true);
    setError(null);

    if (!isSupabaseConfigured()) {
      setError("Supabase is not configured");
      setLoading(false);
      return;
    }

    const { error: oauthError } = await supabase.auth.signInWithOAuth({
      provider: "google",
      options: {
        redirectTo: `${window.location.origin}/auth/callback`,
      },
    });

    if (oauthError) {
      setError(oauthError.message);
      setLoading(false);
    }
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-gray-100 px-4 dark:bg-gray-900">
      <Card className="w-full max-w-md rounded-lg">
        <CardHeader className="text-center">
          <div className="mx-auto mb-3 flex h-12 w-12 items-center justify-center rounded-md bg-gray-900 text-white">
            <ShieldCheck className="h-6 w-6" />
          </div>
          <CardTitle className="text-2xl">VibeSync Admin Dashboard</CardTitle>
          <p className="text-sm text-gray-500">
            使用白名單 Google 帳號登入 Eric / Bruce 後台。
          </p>
        </CardHeader>
        <CardContent className="space-y-4">
          {error ? (
            <div className="rounded-md bg-red-50 p-3 text-sm text-red-600">
              {error}
            </div>
          ) : null}

          <Button
            type="button"
            className="w-full"
            onClick={() => void handleGoogleLogin()}
            disabled={loading}
          >
            <Chrome className="h-4 w-4" />
            {loading ? "正在前往 Google..." : "使用 Google 登入"}
          </Button>

          <p className="text-center text-xs text-gray-500">
            登入後仍會檢查 Supabase `admin_users` 白名單。
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
