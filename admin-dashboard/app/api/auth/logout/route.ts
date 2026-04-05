import { NextResponse } from "next/server";
import { ADMIN_ACCESS_COOKIE } from "@/lib/auth";

export async function POST() {
  const response = NextResponse.json(
    { success: true },
    {
      headers: {
        "Cache-Control": "no-store",
      },
    },
  );
  response.cookies.set({
    name: ADMIN_ACCESS_COOKIE,
    value: "",
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    maxAge: 0,
  });

  return response;
}
