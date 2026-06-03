import { NextResponse } from "next/server";
import { SESSION_COOKIE, verifyPassword, createSessionToken, authConfigured } from "@/lib/auth";

export const dynamic = "force-dynamic";

const TTL_SECONDS = 60 * 60 * 12; // 12h

export async function POST(request: Request) {
  if (!authConfigured()) {
    return NextResponse.json(
      { error: "Auth not configured. Set DIFFRACT_ADMIN_PASSWORD and DIFFRACT_AUTH_SECRET." },
      { status: 503 },
    );
  }

  let password = "";
  try {
    const body = await request.json();
    password = typeof body?.password === "string" ? body.password : "";
  } catch {
    return NextResponse.json({ error: "Invalid request body" }, { status: 400 });
  }

  if (!(await verifyPassword(password))) {
    return NextResponse.json({ error: "Invalid password" }, { status: 401 });
  }

  const token = await createSessionToken(TTL_SECONDS);
  if (!token) {
    return NextResponse.json({ error: "Auth not configured" }, { status: 503 });
  }

  const res = NextResponse.json({ ok: true });
  res.cookies.set(SESSION_COOKIE, token, {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    maxAge: TTL_SECONDS,
  });
  return res;
}
