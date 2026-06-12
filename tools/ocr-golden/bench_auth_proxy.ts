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

function readUserJwt(): string | null {
  try {
    const text = Deno.readTextFileSync(TOKEN_FILE);
    const m = text.match(/OCR_GOLDEN_TOKEN=(\S+)/);
    return m ? m[1] : null;
  } catch {
    return null;
  }
}

Deno.serve({ port: PORT }, async (req) => {
  const url = new URL(req.url);
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
