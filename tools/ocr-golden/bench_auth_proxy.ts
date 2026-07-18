// 本機跑分用 auth 改寫 proxy——讓「未改碼」的 analyze-chat 在無 Docker、無
// service role key 的機器上跑 local bench。
//
// 背景：index.ts 的 createClient(SUPABASE_URL, SERVICE_KEY) 把同一把 key 同時
// 當 apikey 與 Authorization。本機只有 anon key，PostgREST 會以 anon 角色被
// RLS 擋掉 subscriptions 查表（403 No subscription found）。
// 此 proxy 把 /rest/v1/* 的 Authorization 改寫成測試帳號 user JWT——RLS 走
// authenticated 自讀路徑，function code 維持 byte-for-byte 不動。
//
// 用法：
//   deno run --allow-net --allow-read --allow-env bench_auth_proxy.ts
// env：
//   SUPABASE_URL          prod Supabase URL（轉發目標）
//   OCR_BENCH_TOKEN_FILE  含 OCR_GOLDEN_TOKEN=<user JWT> 的檔案
//                         （每請求重讀，token 過期換檔即可不必重啟）
//   PORT                  預設 9999
//   MOCK_ANALYSIS_RUNS=1   本機 analyze quality smoke 專用：以記憶體模擬
//                         analysis_runs / analysis_stream_runs lifecycle，
//                         不碰 prod table
//
// 僅供本機 benchmark。絕不部署、絕不打非測試帳號流量。

const UPSTREAM = Deno.env.get("SUPABASE_URL");
if (!UPSTREAM) {
  console.error("缺 SUPABASE_URL");
  Deno.exit(1);
}
const TOKEN_FILE = Deno.env.get("OCR_BENCH_TOKEN_FILE") ??
  "/tmp/ocr-bench-token.env";
const PORT = Number(Deno.env.get("PORT") ?? "9999");
const MOCK_ANALYSIS_RUNS = Deno.env.get("MOCK_ANALYSIS_RUNS") === "1";

type JsonRecord = Record<string, unknown>;
const localStreamRuns = new Map<string, JsonRecord>();
const localQuickRuns = new Map<string, JsonRecord>();

function localJson(req: Request, value: JsonRecord): Response {
  const wantsObject = req.headers.get("accept")?.includes(
    "application/vnd.pgrst.object+json",
  );
  return Response.json(wantsObject ? value : [value], {
    headers: { "content-range": "0-0/*" },
  });
}

function eqFilter(url: URL, name: string): string | null {
  const value = url.searchParams.get(name);
  return value?.startsWith("eq.") ? value.slice(3) : value;
}

async function mockStreamRunRequest(
  req: Request,
  url: URL,
): Promise<Response | null> {
  if (!MOCK_ANALYSIS_RUNS) return null;

  if (
    url.pathname === "/rest/v1/analysis_stream_runs" &&
    req.method === "POST"
  ) {
    const input = await req.json() as JsonRecord;
    const now = new Date();
    const row: JsonRecord = {
      id: crypto.randomUUID(),
      user_id: input.user_id,
      conversation_hash: input.conversation_hash,
      status: input.status ?? "pending",
      selected_style: null,
      recommendation_json: null,
      final_result_json: null,
      charged_at: null,
      last_error_code: null,
      retry_count: input.retry_count ?? 0,
      request_context: input.request_context ?? null,
      created_at: now.toISOString(),
      expires_at: new Date(now.getTime() + 24 * 60 * 60 * 1000).toISOString(),
    };
    localStreamRuns.set(String(row.id), row);
    return localJson(req, row);
  }

  if (
    url.pathname === "/rest/v1/rpc/charge_stream_analysis_run" &&
    req.method === "POST"
  ) {
    const input = await req.json() as JsonRecord;
    const row = localStreamRuns.get(String(input.p_run_id));
    if (!row) {
      return Response.json({ message: "mock run not found" }, { status: 404 });
    }
    row.status = "charged";
    row.selected_style = input.p_selected_style;
    row.recommendation_json = input.p_recommendation_json;
    row.charged_at = new Date().toISOString();
    return localJson(req, row);
  }

  if (
    url.pathname === "/rest/v1/rpc/create_charged_analysis_run" &&
    req.method === "POST"
  ) {
    const input = await req.json() as JsonRecord;
    const now = new Date();
    const row: JsonRecord = {
      id: crypto.randomUUID(),
      user_id: input.p_user_id,
      conversation_hash: input.p_conversation_hash,
      charged: true,
      quick_result: input.p_quick_result,
      request_context: input.p_request_context ?? null,
      retry_count: 0,
      created_at: now.toISOString(),
      expires_at: new Date(now.getTime() + 24 * 60 * 60 * 1000).toISOString(),
      consumed_at: null,
    };
    localQuickRuns.set(String(row.id), row);
    return localJson(req, row);
  }

  if (
    url.pathname === "/rest/v1/analysis_stream_runs" &&
    req.method === "PATCH"
  ) {
    const runId = eqFilter(url, "id");
    const row = runId ? localStreamRuns.get(runId) : null;
    if (!row) {
      return Response.json({ message: "mock run not found" }, { status: 404 });
    }
    Object.assign(row, await req.json() as JsonRecord);
    return localJson(req, row);
  }

  return null;
}

function readUserJwt(): string | null {
  try {
    const text = Deno.readTextFileSync(TOKEN_FILE);
    const m = text.match(/OCR_GOLDEN_TOKEN=(\S+)/);
    return m ? m[1] : null;
  } catch {
    return null;
  }
}

Deno.serve({ hostname: "127.0.0.1", port: PORT }, async (req) => {
  const url = new URL(req.url);
  const mockResponse = await mockStreamRunRequest(req, url);
  if (mockResponse) return mockResponse;

  const target = `${UPSTREAM}${url.pathname}${url.search}`;
  const headers = new Headers(req.headers);
  headers.delete("host");

  if (url.pathname.startsWith("/rest/v1/")) {
    const jwt = readUserJwt();
    if (jwt) headers.set("Authorization", `Bearer ${jwt}`);
  }

  const res = await fetch(target, {
    method: req.method,
    headers,
    body: req.body,
  });
  return new Response(res.body, { status: res.status, headers: res.headers });
});

console.log(`bench auth proxy :${PORT} -> ${UPSTREAM}`);
