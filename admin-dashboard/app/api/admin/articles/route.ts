import { NextResponse } from "next/server";
import type {
  ArticleSourceFormat,
  ManagedArticleStatus,
} from "@/lib/articles/catalog";
import { getAdminSession } from "@/lib/server/admin-supabase";

export const dynamic = "force-dynamic";

const ARTICLE_STATUSES: ManagedArticleStatus[] = [
  "draft",
  "pending_review",
  "published_in_app",
  "archived",
];
const SOURCE_FORMATS: ArticleSourceFormat[] = ["markdown", "plain_text"];

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function asText(value: unknown, fallback = "") {
  return typeof value === "string" ? value.trim() : fallback;
}

function asNullableText(value: unknown) {
  const text = asText(value);
  return text.length > 0 ? text : null;
}

function asEnum<T extends string>(value: unknown, options: readonly T[], fallback: T) {
  return typeof value === "string" && options.includes(value as T)
    ? (value as T)
    : fallback;
}

function normalizeTags(value: unknown) {
  const rawTags = Array.isArray(value)
    ? value
    : typeof value === "string"
      ? value.split(/[,，#\n]/)
      : [];

  return Array.from(
    new Set(
      rawTags
        .map((tag) => (typeof tag === "string" ? tag.trim() : ""))
        .filter(Boolean)
        .map((tag) => tag.slice(0, 40))
    )
  ).slice(0, 24);
}

async function readBody(request: Request) {
  let body: unknown;

  try {
    body = await request.json();
  } catch {
    return { ok: false as const, error: "Invalid JSON body" };
  }

  if (!isRecord(body)) {
    return { ok: false as const, error: "Invalid JSON body" };
  }

  return { ok: true as const, body };
}

export async function GET() {
  const admin = await getAdminSession();

  if (!admin.ok) {
    return NextResponse.json(
      { error: admin.error },
      { status: admin.status }
    );
  }

  const { data, error } = await admin.session.supabase
    .from("admin_articles")
    .select(
      [
        "id",
        "title",
        "subtitle",
        "category",
        "tags",
        "status",
        "source_format",
        "content",
        "source_name",
        "source_url",
        "app_article_id",
        "notes",
        "created_by_email",
        "updated_by_email",
        "created_at",
        "updated_at",
      ].join(", ")
    )
    .order("updated_at", { ascending: false })
    .limit(500);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ articles: data ?? [] });
}

export async function POST(request: Request) {
  const admin = await getAdminSession();

  if (!admin.ok) {
    return NextResponse.json(
      { error: admin.error },
      { status: admin.status }
    );
  }

  const parsed = await readBody(request);

  if (!parsed.ok) {
    return NextResponse.json({ error: parsed.error }, { status: 400 });
  }

  const title = asText(parsed.body.title);
  const content = asText(parsed.body.content);
  const category = asText(parsed.body.category, "未分類") || "未分類";

  if (!title) {
    return NextResponse.json({ error: "Missing title" }, { status: 400 });
  }

  if (!content) {
    return NextResponse.json({ error: "Missing content" }, { status: 400 });
  }

  const { user, supabase } = admin.session;
  const payload = {
    title: title.slice(0, 160),
    subtitle: asNullableText(parsed.body.subtitle),
    category: category.slice(0, 80),
    tags: normalizeTags(parsed.body.tags),
    status: asEnum(parsed.body.status, ARTICLE_STATUSES, "pending_review"),
    source_format: asEnum(parsed.body.source_format, SOURCE_FORMATS, "markdown"),
    content,
    source_name: asNullableText(parsed.body.source_name),
    source_url: asNullableText(parsed.body.source_url),
    app_article_id: asNullableText(parsed.body.app_article_id),
    notes: asNullableText(parsed.body.notes),
    created_by: user.id,
    created_by_email: user.email ?? null,
    updated_by: user.id,
    updated_by_email: user.email ?? null,
  };

  const { data, error } = await supabase
    .from("admin_articles")
    .insert(payload)
    .select("*")
    .single();

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ article: data });
}

export async function PATCH(request: Request) {
  const admin = await getAdminSession();

  if (!admin.ok) {
    return NextResponse.json(
      { error: admin.error },
      { status: admin.status }
    );
  }

  const parsed = await readBody(request);

  if (!parsed.ok) {
    return NextResponse.json({ error: parsed.error }, { status: 400 });
  }

  const id = asText(parsed.body.id);

  if (!id) {
    return NextResponse.json({ error: "Missing article id" }, { status: 400 });
  }

  const status = asEnum(parsed.body.status, ARTICLE_STATUSES, "pending_review");
  const { user, supabase } = admin.session;
  const { data, error } = await supabase
    .from("admin_articles")
    .update({
      status,
      updated_by: user.id,
      updated_by_email: user.email ?? null,
    })
    .eq("id", id)
    .select("*")
    .single();

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ article: data });
}

export async function DELETE(request: Request) {
  const admin = await getAdminSession();

  if (!admin.ok) {
    return NextResponse.json(
      { error: admin.error },
      { status: admin.status }
    );
  }

  const parsed = await readBody(request);

  if (!parsed.ok) {
    return NextResponse.json({ error: parsed.error }, { status: 400 });
  }

  const id = asText(parsed.body.id);

  if (!id) {
    return NextResponse.json({ error: "Missing article id" }, { status: 400 });
  }

  const { error } = await admin.session.supabase
    .from("admin_articles")
    .delete()
    .eq("id", id);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ ok: true });
}
