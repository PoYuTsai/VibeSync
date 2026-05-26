"use client";

import { ChangeEvent, FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import {
  FileText,
  Plus,
  RefreshCcw,
  Search,
  Tags,
  Trash2,
  Upload,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  appPublishedArticles,
  defaultArticleCategories,
  type ArticleSourceFormat,
  type ManagedArticleStatus,
} from "@/lib/articles/catalog";
import { cn } from "@/lib/utils";

interface ManagedArticle {
  id: string;
  title: string;
  subtitle: string | null;
  category: string;
  tags: string[];
  status: ManagedArticleStatus;
  source_format: ArticleSourceFormat;
  content: string;
  source_name: string | null;
  source_url: string | null;
  app_article_id: string | null;
  notes: string | null;
  created_by_email: string | null;
  updated_by_email: string | null;
  created_at: string;
  updated_at: string;
}

interface ArticlesResponse {
  articles: ManagedArticle[];
  error?: string;
}

interface ArticleFormState {
  title: string;
  subtitle: string;
  category: string;
  tags: string;
  status: ManagedArticleStatus;
  source_format: ArticleSourceFormat;
  source_name: string;
  source_url: string;
  content: string;
  notes: string;
}

type ArticleFilter = "all" | "app" | ManagedArticleStatus;

const emptyForm: ArticleFormState = {
  title: "",
  subtitle: "",
  category: "核心社交心法",
  tags: "",
  status: "pending_review",
  source_format: "markdown",
  source_name: "",
  source_url: "",
  content: "",
  notes: "",
};

const statusLabels: Record<ManagedArticleStatus, string> = {
  draft: "草稿",
  pending_review: "待上架",
  published_in_app: "已上架紀錄",
  archived: "封存",
};

const sourceFormatLabels: Record<ArticleSourceFormat, string> = {
  markdown: "Markdown / .md",
  plain_text: "純文字",
};

const filterLabels: Record<ArticleFilter, string> = {
  all: "全部",
  app: "App 已上架",
  pending_review: "待上架",
  draft: "草稿",
  published_in_app: "已上架紀錄",
  archived: "封存",
};

function splitTags(input: string) {
  return input
    .split(/[,，#\n]/)
    .map((tag) => tag.trim())
    .filter(Boolean);
}

function formatDateTime(value: string | null | undefined) {
  if (!value) return "-";
  return new Date(value).toLocaleDateString("zh-TW");
}

export default function ArticlesPage() {
  const [managedArticles, setManagedArticles] = useState<ManagedArticle[]>([]);
  const [form, setForm] = useState<ArticleFormState>(emptyForm);
  const [filter, setFilter] = useState<ArticleFilter>("all");
  const [search, setSearch] = useState("");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const loadArticles = useCallback(async () => {
    setLoading(true);
    setError(null);

    try {
      const response = await fetch("/api/admin/articles", {
        credentials: "same-origin",
      });
      const payload = (await response.json()) as ArticlesResponse;

      if (!response.ok) {
        throw new Error(payload.error ?? "讀取文章失敗");
      }

      setManagedArticles(payload.articles ?? []);
    } catch (err) {
      setError(err instanceof Error ? err.message : "讀取文章失敗");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadArticles();
  }, [loadArticles]);

  const allCategories = useMemo(() => {
    return Array.from(
      new Set([
        ...defaultArticleCategories,
        ...managedArticles.map((article) => article.category),
      ])
    ).sort((a, b) => a.localeCompare(b, "zh-Hant"));
  }, [managedArticles]);

  const tagCounts = useMemo(() => {
    const counts = new Map<string, number>();

    for (const article of appPublishedArticles) {
      for (const tag of article.tags) {
        counts.set(tag, (counts.get(tag) ?? 0) + 1);
      }
    }

    for (const article of managedArticles) {
      for (const tag of article.tags ?? []) {
        counts.set(tag, (counts.get(tag) ?? 0) + 1);
      }
    }

    return Array.from(counts.entries())
      .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0], "zh-Hant"))
      .slice(0, 28);
  }, [managedArticles]);

  const filteredAppArticles = useMemo(() => {
    if (filter !== "all" && filter !== "app" && filter !== "published_in_app") {
      return [];
    }

    const query = search.trim().toLowerCase();

    return appPublishedArticles.filter((article) => {
      if (!query) return true;
      return [
        article.id,
        article.title,
        article.subtitle,
        article.category,
        article.readTime,
        article.source,
        ...article.tags,
      ]
        .join(" ")
        .toLowerCase()
        .includes(query);
    });
  }, [filter, search]);

  const filteredManagedArticles = useMemo(() => {
    const query = search.trim().toLowerCase();

    return managedArticles.filter((article) => {
      if (filter === "app") return false;
      if (filter !== "all" && article.status !== filter) return false;
      if (!query) return true;

      return [
        article.title,
        article.subtitle,
        article.category,
        article.source_name,
        article.notes,
        ...article.tags,
      ]
        .filter(Boolean)
        .join(" ")
        .toLowerCase()
        .includes(query);
    });
  }, [filter, managedArticles, search]);

  const pendingCount = managedArticles.filter(
    (article) => article.status === "pending_review"
  ).length;
  const draftCount = managedArticles.filter((article) => article.status === "draft").length;
  const categoryCount = allCategories.length;

  function updateForm<K extends keyof ArticleFormState>(
    key: K,
    value: ArticleFormState[K]
  ) {
    setForm((current) => ({ ...current, [key]: value }));
  }

  async function handleFileInput(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];

    if (!file) return;

    const text = await file.text();
    const titleFromFile = file.name.replace(/\.(md|markdown|txt)$/i, "");

    setForm((current) => ({
      ...current,
      title: current.title || titleFromFile,
      source_format: file.name.match(/\.(md|markdown)$/i) ? "markdown" : "plain_text",
      content: text,
    }));
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSaving(true);
    setError(null);

    try {
      const response = await fetch("/api/admin/articles", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        credentials: "same-origin",
        body: JSON.stringify({
          ...form,
          tags: splitTags(form.tags),
        }),
      });
      const payload = (await response.json()) as ArticlesResponse;

      if (!response.ok) {
        throw new Error(payload.error ?? "新增文章失敗");
      }

      setForm(emptyForm);
      await loadArticles();
    } catch (err) {
      setError(err instanceof Error ? err.message : "新增文章失敗");
    } finally {
      setSaving(false);
    }
  }

  async function updateStatus(id: string, status: ManagedArticleStatus) {
    setSaving(true);
    setError(null);

    try {
      const response = await fetch("/api/admin/articles", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        credentials: "same-origin",
        body: JSON.stringify({ id, status }),
      });
      const payload = (await response.json()) as ArticlesResponse;

      if (!response.ok) {
        throw new Error(payload.error ?? "更新狀態失敗");
      }

      await loadArticles();
    } catch (err) {
      setError(err instanceof Error ? err.message : "更新狀態失敗");
    } finally {
      setSaving(false);
    }
  }

  async function deleteArticle(id: string) {
    if (!window.confirm("確定要刪除這篇後台文章嗎？")) return;

    setSaving(true);
    setError(null);

    try {
      const response = await fetch("/api/admin/articles", {
        method: "DELETE",
        headers: { "Content-Type": "application/json" },
        credentials: "same-origin",
        body: JSON.stringify({ id }),
      });
      const payload = (await response.json()) as ArticlesResponse;

      if (!response.ok) {
        throw new Error(payload.error ?? "刪除文章失敗");
      }

      await loadArticles();
    } catch (err) {
      setError(err instanceof Error ? err.message : "刪除文章失敗");
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-3 md:flex-row md:items-end md:justify-between">
        <div>
          <h1 className="text-3xl font-bold">文章專區</h1>
          <p className="mt-2 text-sm text-gray-600">
            管理 App 已上架文章索引，以及 Eric / Bruce 要準備上架的新文章。
          </p>
        </div>
        <Button
          type="button"
          variant="outline"
          onClick={() => void loadArticles()}
          disabled={loading || saving}
        >
          <RefreshCcw className="h-4 w-4" />
          重新整理
        </Button>
      </div>

      {error ? (
        <div className="rounded-md border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
          {error}
        </div>
      ) : null}

      <div className="grid gap-4 md:grid-cols-4">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm text-gray-500">App 已上架</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{appPublishedArticles.length}</div>
            <p className="mt-1 text-xs text-gray-500">目前 App 內已有文章</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm text-gray-500">待上架</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{pendingCount}</div>
            <p className="mt-1 text-xs text-gray-500">已貼上，等整理進 App</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm text-gray-500">草稿</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{draftCount}</div>
            <p className="mt-1 text-xs text-gray-500">還在整理或改寫</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm text-gray-500">分類</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{categoryCount}</div>
            <p className="mt-1 text-xs text-gray-500">方便後續索引與整理</p>
          </CardContent>
        </Card>
      </div>

      <div className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_430px]">
        <div className="space-y-4">
          <Card>
            <CardContent className="space-y-4">
              <div className="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
                <div className="flex flex-wrap gap-2">
                  {(Object.keys(filterLabels) as ArticleFilter[]).map((value) => (
                    <button
                      key={value}
                      type="button"
                      onClick={() => setFilter(value)}
                      className={cn(
                        "rounded-full border px-3 py-1.5 text-sm transition-colors",
                        filter === value
                          ? "border-indigo-200 bg-indigo-600 text-white"
                          : "border-indigo-100 bg-white/80 text-slate-600 hover:bg-indigo-50"
                      )}
                    >
                      {filterLabels[value]}
                    </button>
                  ))}
                </div>
                <label className="relative min-w-0 lg:w-72">
                  <Search className="absolute left-3 top-2.5 h-4 w-4 text-gray-400" />
                  <input
                    value={search}
                    onChange={(event) => setSearch(event.target.value)}
                    className="h-9 w-full rounded-md border bg-white pl-9 pr-3 text-sm"
                    placeholder="搜尋標題、分類、標籤"
                  />
                </label>
              </div>

              <div className="rounded-md border bg-indigo-50/70 p-3 text-sm text-indigo-950">
                <div className="flex items-center gap-2 font-semibold">
                  <Tags className="h-4 w-4" />
                  標籤索引
                </div>
                <div className="mt-3 flex flex-wrap gap-2">
                  {tagCounts.map(([tag, count]) => (
                    <button
                      key={tag}
                      type="button"
                      onClick={() => setSearch(tag)}
                      className="rounded-full border border-indigo-100 bg-white/90 px-3 py-1 text-xs text-indigo-800 hover:bg-white"
                    >
                      #{tag} <span className="text-indigo-400">{count}</span>
                    </button>
                  ))}
                </div>
              </div>
            </CardContent>
          </Card>

          <div className="space-y-3">
            {loading ? (
              [1, 2, 3].map((item) => (
                <div key={item} className="h-28 animate-pulse rounded-lg bg-white/70" />
              ))
            ) : filteredAppArticles.length + filteredManagedArticles.length === 0 ? (
              <Card>
                <CardContent className="py-10 text-center text-sm text-gray-500">
                  沒有符合條件的文章。
                </CardContent>
              </Card>
            ) : (
              <>
                {filteredManagedArticles.map((article) => (
                  <Card key={article.id}>
                    <CardContent className="space-y-3">
                      <div className="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
                        <div>
                          <div className="flex flex-wrap items-center gap-2">
                            <span className="rounded-full bg-fuchsia-50 px-2 py-1 text-xs font-medium text-fuchsia-700">
                              {statusLabels[article.status]}
                            </span>
                            <span className="rounded-full bg-indigo-50 px-2 py-1 text-xs font-medium text-indigo-700">
                              {article.category}
                            </span>
                          </div>
                          <h2 className="mt-3 text-lg font-semibold">{article.title}</h2>
                          {article.subtitle ? (
                            <p className="mt-1 text-sm text-gray-600">{article.subtitle}</p>
                          ) : null}
                        </div>
                        <div className="flex items-center gap-2">
                          <select
                            value={article.status}
                            onChange={(event) =>
                              void updateStatus(
                                article.id,
                                event.target.value as ManagedArticleStatus
                              )
                            }
                            disabled={saving}
                            className="h-9 rounded-md border bg-white px-2 text-sm"
                          >
                            {Object.entries(statusLabels).map(([value, label]) => (
                              <option key={value} value={value}>
                                {label}
                              </option>
                            ))}
                          </select>
                          <Button
                            type="button"
                            variant="outline"
                            size="icon-sm"
                            onClick={() => void deleteArticle(article.id)}
                            disabled={saving}
                            aria-label="刪除文章"
                          >
                            <Trash2 className="h-4 w-4" />
                          </Button>
                        </div>
                      </div>

                      <div className="flex flex-wrap gap-2">
                        {(article.tags ?? []).map((tag) => (
                          <span
                            key={tag}
                            className="rounded-full bg-slate-100 px-2 py-1 text-xs text-slate-600"
                          >
                            #{tag}
                          </span>
                        ))}
                      </div>

                      <div className="grid gap-2 text-xs text-gray-500 md:grid-cols-3">
                        <div>格式：{sourceFormatLabels[article.source_format]}</div>
                        <div>更新：{formatDateTime(article.updated_at)}</div>
                        <div>上傳：{article.created_by_email ?? "-"}</div>
                      </div>
                    </CardContent>
                  </Card>
                ))}

                {filteredAppArticles.map((article) => (
                  <Card key={`app-${article.id}`}>
                    <CardContent className="space-y-3">
                      <div className="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
                        <div>
                          <div className="flex flex-wrap items-center gap-2">
                            <span className="rounded-full bg-emerald-50 px-2 py-1 text-xs font-medium text-emerald-700">
                              App 已上架
                            </span>
                            <span className="rounded-full bg-indigo-50 px-2 py-1 text-xs font-medium text-indigo-700">
                              {article.category}
                            </span>
                          </div>
                          <h2 className="mt-3 text-lg font-semibold">
                            {article.id}. {article.title}
                          </h2>
                          <p className="mt-1 text-sm text-gray-600">{article.subtitle}</p>
                        </div>
                        <div className="rounded-md bg-slate-50 px-3 py-2 text-sm text-slate-600">
                          {article.readTime}
                        </div>
                      </div>

                      <div className="flex flex-wrap gap-2">
                        {article.tags.map((tag) => (
                          <span
                            key={tag}
                            className="rounded-full bg-slate-100 px-2 py-1 text-xs text-slate-600"
                          >
                            #{tag}
                          </span>
                        ))}
                      </div>
                      <div className="text-xs text-gray-500">
                        來源：{article.source || "未標示"}
                      </div>
                    </CardContent>
                  </Card>
                ))}
              </>
            )}
          </div>
        </div>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Plus className="h-5 w-5" />
              新增待上架文章
            </CardTitle>
          </CardHeader>
          <CardContent>
            <form className="space-y-4" onSubmit={(event) => void handleSubmit(event)}>
              <div className="rounded-md border bg-blue-50 p-3 text-sm text-blue-900">
                給 Eric / Bruce：格式不限，Markdown、.md 檔、純文字直接貼上都可以。
              </div>

              <label className="block rounded-md border border-dashed bg-white/70 p-4 text-sm text-gray-600">
                <div className="flex items-center gap-2 font-medium text-gray-800">
                  <Upload className="h-4 w-4" />
                  上傳 .md / .txt
                </div>
                <input
                  type="file"
                  accept=".md,.markdown,.txt,text/markdown,text/plain"
                  onChange={(event) => void handleFileInput(event)}
                  className="mt-3 block w-full text-sm"
                />
              </label>

              <label className="space-y-1 text-sm font-medium text-gray-700">
                標題
                <input
                  value={form.title}
                  onChange={(event) => updateForm("title", event.target.value)}
                  className="h-10 w-full rounded-md border bg-white px-3"
                  placeholder="例：冷掉的對話怎麼重新接上"
                  required
                />
              </label>

              <label className="space-y-1 text-sm font-medium text-gray-700">
                副標
                <input
                  value={form.subtitle}
                  onChange={(event) => updateForm("subtitle", event.target.value)}
                  className="h-10 w-full rounded-md border bg-white px-3"
                  placeholder="一句話說明這篇文章幫用戶解什麼問題"
                />
              </label>

              <div className="grid grid-cols-2 gap-3">
                <label className="space-y-1 text-sm font-medium text-gray-700">
                  分類
                  <input
                    list="article-category-options"
                    value={form.category}
                    onChange={(event) => updateForm("category", event.target.value)}
                    className="h-10 w-full rounded-md border bg-white px-3"
                  />
                  <datalist id="article-category-options">
                    {allCategories.map((category) => (
                      <option key={category} value={category} />
                    ))}
                  </datalist>
                </label>

                <label className="space-y-1 text-sm font-medium text-gray-700">
                  狀態
                  <select
                    value={form.status}
                    onChange={(event) =>
                      updateForm("status", event.target.value as ManagedArticleStatus)
                    }
                    className="h-10 w-full rounded-md border bg-white px-3"
                  >
                    <option value="pending_review">待上架</option>
                    <option value="draft">草稿</option>
                    <option value="published_in_app">已上架紀錄</option>
                  </select>
                </label>
              </div>

              <label className="space-y-1 text-sm font-medium text-gray-700">
                標籤
                <input
                  value={form.tags}
                  onChange={(event) => updateForm("tags", event.target.value)}
                  className="h-10 w-full rounded-md border bg-white px-3"
                  placeholder="逗號分隔：開話題, 邀約, 低壓"
                />
              </label>

              <div className="grid grid-cols-2 gap-3">
                <label className="space-y-1 text-sm font-medium text-gray-700">
                  格式
                  <select
                    value={form.source_format}
                    onChange={(event) =>
                      updateForm(
                        "source_format",
                        event.target.value as ArticleSourceFormat
                      )
                    }
                    className="h-10 w-full rounded-md border bg-white px-3"
                  >
                    <option value="markdown">Markdown / .md</option>
                    <option value="plain_text">純文字</option>
                  </select>
                </label>

                <label className="space-y-1 text-sm font-medium text-gray-700">
                  來源
                  <input
                    value={form.source_name}
                    onChange={(event) => updateForm("source_name", event.target.value)}
                    className="h-10 w-full rounded-md border bg-white px-3"
                    placeholder="原創 / 參考來源"
                  />
                </label>
              </div>

              <label className="space-y-1 text-sm font-medium text-gray-700">
                來源連結
                <input
                  value={form.source_url}
                  onChange={(event) => updateForm("source_url", event.target.value)}
                  className="h-10 w-full rounded-md border bg-white px-3"
                  placeholder="https://..."
                />
              </label>

              <label className="space-y-1 text-sm font-medium text-gray-700">
                文章內容
                <textarea
                  value={form.content}
                  onChange={(event) => updateForm("content", event.target.value)}
                  rows={12}
                  className="w-full rounded-md border bg-white px-3 py-2 font-mono text-sm"
                  placeholder="可以貼 Markdown，也可以直接貼純文字。"
                  required
                />
              </label>

              <label className="space-y-1 text-sm font-medium text-gray-700">
                備註
                <textarea
                  value={form.notes}
                  onChange={(event) => updateForm("notes", event.target.value)}
                  rows={3}
                  className="w-full rounded-md border bg-white px-3 py-2"
                  placeholder="例：Bruce 初稿，待 Eric 改標題。"
                />
              </label>

              <Button type="submit" disabled={saving} className="w-full">
                <FileText className="h-4 w-4" />
                儲存文章
              </Button>
            </form>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
