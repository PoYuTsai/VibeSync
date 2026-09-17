// 開場救星兩段式：真 PostgreSQL 並行驗收（可丟棄本機叢集，非 production）。
//
// 用多條獨立連線（npm:postgres，每條 max:1）與明確交易，驗 PGlite 單連線驗不到的部分：
//   C1 同局同時 claim 只有一個取得資格（鎖序列化 + 真並發競速）
//   C2 租約過期與接手後，舊作業不得結算
//   C3 結果保存／首次扣費／成功次數同一交易：失敗回滾、成功期間外部觀察者看不到中間狀態
//   C4 已完成操作重播不重扣（含兩條連線同時 settle 只扣一次）
//   C5 跨帳號存取隔離（RPC 身分檢查＋anon／authenticated 權限）
//
//   PGHOST=127.0.0.1 PGPORT=54329 PGUSER=postgres PGDATABASE=opener_acceptance \
//     deno run --allow-net=127.0.0.1 --allow-env --allow-read --allow-write \
//     tools/opener-pg-concurrency/run.ts --out=<dir>
//
// 前置：pg_bootstrap.sql（與 PGlite 契約測試相同的 auth／users／subscriptions／increment_usage 樁）
// 與兩支 migration 已套在該資料庫。退出碼：全部 PASS 為 0，否則 1。
import postgres from "npm:postgres@3.4.4";

const env = (k: string, d: string) => Deno.env.get(k) ?? d;
const cfg = { host: env("PGHOST", "127.0.0.1"), port: Number(env("PGPORT", "54329")), user: env("PGUSER", "postgres"), database: env("PGDATABASE", "opener_acceptance") };
const outArg = Deno.args.find((a) => a.startsWith("--out="))?.slice(6) ?? "tools/opener-pg-concurrency/out";
await Deno.mkdir(outArg, { recursive: true });

type Sql = ReturnType<typeof postgres>;
const conn = () => postgres({ ...cfg, max: 1, onnotice: () => {} });
// 每個案例用獨立連線：A／B 是兩個互相競爭的執行者，O 是觀察者。
const A = conn(), B = conn(), O = conn();

const ANALYSIS = { approach: { mode: "anchor_hooks", summary: "可以從她的狗開", avoid: [] }, cues: [{ id: "cue_1", label: "養狗", source: "profile_text", subject: "recipient" }], question: null, profileDigest: "自介：有養一隻狗" };
const CONTRIBUTION = { state: "answered", questionId: null, selectedOptionId: null, freeText: "沒養過" };
const RESULT = { openers: { extend: "牠散步會自己選路嗎", humor: "幽默句", tease: "調情句" }, recommendation: { pick: "extend", reason: "直接問你想知道的事" }, cardReasons: { extend: "直接問你想知道的事" }, access: { contractVersion: 2, servedTier: "free", visibleTypes: ["extend", "humor", "tease"], lockedTypes: ["resonate", "coldRead"] }, materialUse: { inputState: "answered", references: [], traceStatus: "uncertain", displayNote: null } };
const HASH_A = "a".repeat(64);

const uuid = () => crypto.randomUUID();
/** jsonb 會正規化鍵順序：比較內容用鍵排序後的字串。 */
function canonical(v: unknown): string {
  if (Array.isArray(v)) return `[${v.map(canonical).join(",")}]`;
  if (v && typeof v === "object") return `{${Object.keys(v as Record<string, unknown>).sort().map((k) => `${JSON.stringify(k)}:${canonical((v as Record<string, unknown>)[k])}`).join(",")}}`;
  return JSON.stringify(v);
}
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

interface Check { id: string; name: string; status: "PASS" | "FAIL" | "ERROR"; detail: string; ms: number }
const checks: Check[] = [];
const log: string[] = [];
function say(line: string) { log.push(line); console.log(line); }
function expect(cond: boolean, msg: string) { if (!cond) throw new Error(`斷言失敗：${msg}`); }
async function rejects(p: Promise<unknown>, code: string) {
  try { await p; } catch (e) { const m = (e as Error).message ?? String(e); expect(m.includes(code), `預期 ${code}，實際 ${m}`); return; }
  throw new Error(`預期 RAISE ${code}，實際成功`);
}

async function newUser(sql: Sql): Promise<string> {
  const id = uuid();
  await sql`INSERT INTO auth.users(id) VALUES (${id})`;
  await sql`INSERT INTO public.users(id) VALUES (${id})`;
  await sql`INSERT INTO public.subscriptions(user_id) VALUES (${id})`;
  return id;
}
async function claimAnalysis(sql: Sql, user: string, req: string, owner: string, lease = 65) {
  const [r] = await sql`SELECT public.claim_opener_analysis(${user}::uuid, ${req}::uuid, ${HASH_A}, ${owner}::uuid, 1, 2, ${lease}) AS out`;
  return r.out as Record<string, unknown>;
}
async function settleAnalysis(sql: Sql, user: string, req: string, owner: string, cost = 3) {
  const [r] = await sql`SELECT public.settle_opener_analysis(${user}::uuid, ${req}::uuid, ${owner}::uuid, ${sql.json(ANALYSIS)}::jsonb, ${cost}, 86400) AS out`;
  return r.out as Record<string, unknown>;
}
async function readySession(sql: Sql, user: string, cost = 3): Promise<string> {
  const req = uuid(), owner = uuid();
  const c = await claimAnalysis(sql, user, req, owner);
  expect(c.kind === "claimed", `claim_analysis kind=${c.kind}`);
  const s = await settleAnalysis(sql, user, req, owner, cost);
  return s.sessionId as string;
}
async function claimGen(sql: Sql, user: string, session: string, gen: string, owner: string, lease = 65, hash = HASH_A) {
  const [r] = await sql`SELECT public.claim_opener_generation(${user}::uuid, ${session}::uuid, ${gen}::uuid, ${hash}, ${owner}::uuid, ${sql.json(CONTRIBUTION)}::jsonb, 3, ${lease}) AS out`;
  return r.out as Record<string, unknown>;
}
async function settleGen(sql: Sql, user: string, session: string, gen: string, owner: string, monthly = 30, daily = 10) {
  const [r] = await sql`SELECT public.settle_opener_generation(${user}::uuid, ${session}::uuid, ${gen}::uuid, ${owner}::uuid, ${sql.json(RESULT)}::jsonb, ${monthly}, ${daily}, true, 3) AS out`;
  return r.out as Record<string, unknown>;
}
async function usage(sql: Sql, user: string) {
  const [r] = await sql`SELECT monthly_messages_used AS m, daily_messages_used AS d FROM public.subscriptions WHERE user_id = ${user}::uuid`;
  return { monthly: Number(r.m), daily: Number(r.d) };
}
async function session(sql: Sql, id: string) {
  const [r] = await sql`SELECT state, quota_charged, charged_amount, generations_used FROM public.opener_sessions WHERE session_id = ${id}::uuid`;
  return r;
}
async function run(sql: Sql, user: string, gen: string) {
  const [r] = await sql`SELECT state, charged_amount, result_json, lease_expires_at FROM public.opener_generation_runs WHERE user_id = ${user}::uuid AND generation_id = ${gen}::uuid`;
  return r;
}
async function pendingRuns(sql: Sql, sessionId: string) {
  const [r] = await sql`SELECT count(*)::int AS n FROM public.opener_generation_runs WHERE session_id = ${sessionId}::uuid AND state = 'pending' AND lease_expires_at > now()`;
  return Number(r.n);
}

async function check(id: string, name: string, fn: () => Promise<string>) {
  const t0 = Date.now();
  try {
    const detail = await fn();
    checks.push({ id, name, status: "PASS", detail, ms: Date.now() - t0 });
    say(`PASS ${id} ${name} — ${detail}`);
  } catch (e) {
    const msg = (e as Error).message ?? String(e);
    const status = msg.startsWith("斷言失敗") || msg.startsWith("預期") ? "FAIL" : "ERROR";
    checks.push({ id, name, status, detail: msg, ms: Date.now() - t0 });
    say(`${status} ${id} ${name} — ${msg}`);
  }
}

const [{ v: pgVersion }] = await O`SELECT version() AS v`;
const [{ marker }] = await O`SELECT public.opener_flow_contract_version() AS marker`;
say(`# opener 兩段式 · 真 PostgreSQL 並行驗收 · ${new Date().toISOString()}`);
say(`- server：${pgVersion}`);
say(`- contract marker：${marker}`);
say(`- 連線：A／B（競爭執行者，各自獨立連線）＋O（觀察者）；host ${cfg.host}:${cfg.port} db ${cfg.database}`);
say("");

// ── C1 同局同時 claim ────────────────────────────────────────────────────
await check("C1a", "鎖序列化：A 在交易內 claim G1 並持有 800ms，B 的 claim G2 必須等到 A commit 後才回、且是 session_busy", async () => {
  const user = await newUser(O); const sess = await readySession(O, user);
  const g1 = uuid(), g2 = uuid(), oa = uuid(), ob = uuid();
  const bStart = Date.now();
  let bElapsed = 0; let bKind = "";
  const aTx = A.begin(async (tx) => {
    const [r] = await tx`SELECT public.claim_opener_generation(${user}::uuid, ${sess}::uuid, ${g1}::uuid, ${HASH_A}, ${oa}::uuid, ${tx.json(CONTRIBUTION)}::jsonb, 3, 65) AS out`;
    expect((r.out as Record<string, unknown>).kind === "claimed", "A 未取得資格");
    await sleep(800);
  });
  await sleep(100);
  const bJob = claimGen(B, user, sess, g2, ob).then((r) => { bElapsed = Date.now() - bStart; bKind = String(r.kind); });
  await Promise.all([aTx, bJob]);
  expect(bKind === "session_busy", `B kind=${bKind}`);
  expect(bElapsed >= 700, `B 在 ${bElapsed}ms 就返回，沒有等 A 的交易`);
  expect((await pendingRuns(O, sess)) === 1, "有效 pending run 必須恰好 1");
  return `B 等了 ${bElapsed}ms 才回 session_busy；有效 pending run=1`;
});

await check("C1b", "真並發競速 ×20：兩條連線同時對同局 claim 不同 generationId，每輪恰好一個 claimed、另一個 session_busy", async () => {
  let claimed = 0, busy = 0;
  for (let i = 0; i < 20; i++) {
    const user = await newUser(O); const sess = await readySession(O, user);
    const [ra, rb] = await Promise.all([claimGen(A, user, sess, uuid(), uuid()), claimGen(B, user, sess, uuid(), uuid())]);
    const kinds = [ra.kind, rb.kind].sort();
    expect(kinds.join(",") === "claimed,session_busy", `第 ${i + 1} 輪 kinds=${kinds.join(",")}`);
    expect((await pendingRuns(O, sess)) === 1, `第 ${i + 1} 輪 pending run≠1`);
    claimed++; busy++;
  }
  return `20/20 輪：claimed ${claimed}、session_busy ${busy}`;
});

await check("C1c", "同 generationId 同 owner 兩條連線同時 claim（傳輸層重試）→ 兩邊都 claimed 但只有一列 run", async () => {
  const user = await newUser(O); const sess = await readySession(O, user); const g = uuid(), o = uuid();
  const [ra, rb] = await Promise.all([claimGen(A, user, sess, g, o), claimGen(B, user, sess, g, o)]);
  expect(ra.kind === "claimed" && rb.kind === "claimed", `kinds=${ra.kind},${rb.kind}`);
  const [{ n }] = await O`SELECT count(*)::int AS n FROM public.opener_generation_runs WHERE session_id = ${sess}::uuid`;
  expect(Number(n) === 1, `run 列數=${n}`);
  return "兩邊 claimed、run 列數 1";
});

// ── C2 租約過期與接手 ────────────────────────────────────────────────────
await check("C2a", "G1 租約 1s 過期→B 以 G2 接手→A 的 G1 晚回 settle 必須 OPENER_OPERATION_LEASE_EXPIRED，不扣費、不計次、結果不落地", async () => {
  const user = await newUser(O); const sess = await readySession(O, user); const g1 = uuid(), g2 = uuid(), oa = uuid(), ob = uuid();
  expect((await claimGen(A, user, sess, g1, oa, 1)).kind === "claimed", "G1 claim");
  await sleep(1300);
  expect((await claimGen(B, user, sess, g2, ob)).kind === "claimed", "G2 接手");
  await rejects(settleGen(A, user, sess, g1, oa), "OPENER_OPERATION_LEASE_EXPIRED");
  const s = await session(O, sess); const u = await usage(O, user); const r1 = await run(O, user, g1);
  expect(Number(s.generations_used) === 0 && s.quota_charged === false, "session 被動到");
  expect(u.monthly === 0 && u.daily === 0, "額度被扣");
  expect(r1.state === "pending" && r1.result_json === null, `G1 run state=${r1.state}`);
  const ok = await settleGen(B, user, sess, g2, ob);
  expect(ok.replayed === false && Number(ok.chargedNow) === 3, "G2 正常結算");
  return "G1 settle 被 fencing 拒絕；G2 結算 chargedNow=3";
});

await check("C2b", "租約過期後 A 的 settle 與 B 的接手 claim 同時發出 ×10：A 一律不得結算，B 一律取得資格", async () => {
  for (let i = 0; i < 10; i++) {
    const user = await newUser(O); const sess = await readySession(O, user); const g1 = uuid(), g2 = uuid(), oa = uuid(), ob = uuid();
    expect((await claimGen(A, user, sess, g1, oa, 1)).kind === "claimed", "G1 claim");
    await sleep(1200);
    const [aRes, bRes] = await Promise.all([settleGen(A, user, sess, g1, oa).then(() => "settled", (e) => (e as Error).message), claimGen(B, user, sess, g2, ob)]);
    expect(String(aRes).includes("OPENER_OPERATION_LEASE_EXPIRED"), `第 ${i + 1} 輪 A 結果=${aRes}`);
    expect(bRes.kind === "claimed", `第 ${i + 1} 輪 B kind=${bRes.kind}`);
    expect((await usage(O, user)).monthly === 0, "A 不得扣費");
  }
  return "10/10 輪 A 被拒、B 接手";
});

// ── C3 原子性 ────────────────────────────────────────────────────────────
await check("C3a", "首次扣費時額度已滿（increment_usage RAISE）→ settle 整筆回滾：結果不落地、成功數不動、run 仍 pending", async () => {
  const user = await newUser(O); const sess = await readySession(O, user); const g = uuid(), o = uuid();
  expect((await claimGen(A, user, sess, g, o)).kind === "claimed", "claim");
  await O`UPDATE public.subscriptions SET monthly_messages_used = 30 WHERE user_id = ${user}::uuid`;
  await rejects(settleGen(A, user, sess, g, o, 30, 10), "QUOTA_EXCEEDED");
  const s = await session(O, sess); const r = await run(O, user, g); const u = await usage(O, user);
  expect(Number(s.generations_used) === 0 && s.quota_charged === false && Number(s.charged_amount) === 0, "session 部分更新");
  expect(r.state === "pending" && r.result_json === null && Number(r.charged_amount) === 0, "run 部分更新");
  expect(u.monthly === 30, "額度被動到");
  return "回滾後 session／run／subscriptions 全部原樣";
});

await check("C3b", "成功結算期間，觀察者每 20ms 讀三張表：只能看到「全部未變」或「全部已變」，不得出現中間狀態", async () => {
  const user = await newUser(O); const sess = await readySession(O, user); const g = uuid(), o = uuid();
  expect((await claimGen(A, user, sess, g, o)).kind === "claimed", "claim");
  const snapshots: string[] = [];
  let polling = true;
  const poller = (async () => {
    while (polling) {
      const [row] = await O`SELECT s.generations_used, s.quota_charged, r.state AS run_state, (r.result_json IS NOT NULL) AS has_result, u.monthly_messages_used AS monthly
        FROM public.opener_sessions s JOIN public.opener_generation_runs r ON r.session_id = s.session_id AND r.generation_id = ${g}::uuid
        JOIN public.subscriptions u ON u.user_id = s.user_id WHERE s.session_id = ${sess}::uuid`;
      snapshots.push(JSON.stringify(row));
      await sleep(20);
    }
  })();
  // A 在交易內結算後持有 600ms 才 commit：中間狀態若外洩，觀察者一定看得到。
  await A.begin(async (tx) => {
    const [r] = await tx`SELECT public.settle_opener_generation(${user}::uuid, ${sess}::uuid, ${g}::uuid, ${o}::uuid, ${tx.json(RESULT)}::jsonb, 30, 10, true, 3) AS out`;
    expect((r.out as Record<string, unknown>).replayed === false, "settle");
    await sleep(600);
  });
  await sleep(100);
  polling = false; await poller;
  const before = JSON.stringify({ generations_used: 0, quota_charged: false, run_state: "pending", has_result: false, monthly: 0 });
  const after = JSON.stringify({ generations_used: 1, quota_charged: true, run_state: "done", has_result: true, monthly: 3 });
  const distinct = [...new Set(snapshots)];
  expect(distinct.every((s) => s === before || s === after), `出現中間狀態：${distinct.filter((s) => s !== before && s !== after).join(" | ")}`);
  expect(snapshots.includes(before) && snapshots.includes(after), `觀察者沒同時看到前後狀態（${snapshots.length} 次取樣）`);
  return `${snapshots.length} 次取樣，只有前／後兩種狀態`;
});

// ── C4 重播 ──────────────────────────────────────────────────────────────
await check("C4a", "已完成的 generationId 再 settle → replayed=true、chargedNow=0、額度與成功數不變、回同一份結果", async () => {
  const user = await newUser(O); const sess = await readySession(O, user); const g = uuid(), o = uuid();
  expect((await claimGen(A, user, sess, g, o)).kind === "claimed", "claim");
  const first = await settleGen(A, user, sess, g, o);
  expect(first.replayed === false && Number(first.chargedNow) === 3, "first settle");
  const again = await settleGen(B, user, sess, g, o);
  expect(again.replayed === true && Number(again.chargedNow) === 0 && Number(again.generationsUsed) === 1, `replay=${JSON.stringify(again)}`);
  expect(canonical(again.result) === canonical(RESULT), `replay 結果不同：${canonical(again.result)}`);
  const u = await usage(O, user);
  expect(u.monthly === 3 && u.daily === 3, `額度=${JSON.stringify(u)}`);
  const c = await claimGen(B, user, sess, g, o);
  expect(c.kind === "replay", `claim 同 ID kind=${c.kind}`);
  return "replay 不重扣、claim 同 ID 回 replay";
});

await check("C4b", "兩條連線同時對同一 generationId 首次 settle ×10：恰好一個 replayed=false、另一個 replayed=true，額度只扣一次、成功數 1", async () => {
  for (let i = 0; i < 10; i++) {
    const user = await newUser(O); const sess = await readySession(O, user); const g = uuid(), o = uuid();
    expect((await claimGen(A, user, sess, g, o)).kind === "claimed", "claim");
    const [ra, rb] = await Promise.all([settleGen(A, user, sess, g, o), settleGen(B, user, sess, g, o)]);
    const flags = [ra.replayed, rb.replayed].sort();
    expect(flags.join(",") === "false,true", `第 ${i + 1} 輪 replayed=${flags.join(",")}`);
    const u = await usage(O, user); const s = await session(O, sess);
    expect(u.monthly === 3 && u.daily === 3 && Number(s.generations_used) === 1, `第 ${i + 1} 輪 額度=${JSON.stringify(u)} 成功數=${s.generations_used}`);
  }
  return "10/10 輪只扣一次";
});

// ── C5 跨帳號隔離 ────────────────────────────────────────────────────────
await check("C5a", "他人猜到 sessionId／generationId：claim 與 settle 都 OPENER_SESSION_INVALID；同 requestId 各自成局、拿不到對方快照", async () => {
  const ua = await newUser(O), ub = await newUser(O); const sess = await readySession(O, ua); const g = uuid(), o = uuid();
  expect((await claimGen(A, ua, sess, g, o)).kind === "claimed", "A claim");
  await rejects(claimGen(B, ub, sess, uuid(), uuid()), "OPENER_SESSION_INVALID");
  await rejects(settleGen(B, ub, sess, g, o), "OPENER_SESSION_INVALID");
  const req = uuid(), oa2 = uuid(), ob2 = uuid();
  expect((await claimAnalysis(A, ua, req, oa2)).kind === "claimed", "A analysis claim");
  await settleAnalysis(A, ua, req, oa2);
  const other = await claimAnalysis(B, ub, req, ob2);
  expect(other.kind === "claimed", `B 同 requestId 應各自成局，實際 ${other.kind}`);
  const [{ n }] = await O`SELECT count(*)::int AS n FROM public.opener_sessions WHERE analysis_request_id = ${req}::uuid`;
  expect(Number(n) === 2, `同 requestId 的 session 列數=${n}`);
  return "跨帳號 claim／settle 拒絕；同 requestId 各自成局";
});

await check("C5b", "anon／authenticated 不能讀兩張表、不能執行任何 opener RPC；service_role 可讀", async () => {
  // 權限錯誤會讓交易 abort：每個斷言各自一個交易，SET LOCAL ROLE 只活在該交易內。
  const asRole = (role: string, stmt: string) => O.begin(async (tx) => { await tx.unsafe(`SET LOCAL ROLE ${role}`); return await tx.unsafe(stmt); });
  for (const role of ["anon", "authenticated"]) {
    for (const table of ["opener_sessions", "opener_generation_runs"]) {
      await rejects(asRole(role, `SELECT count(*) FROM public.${table}`), "permission denied");
    }
    await rejects(asRole(role, `SELECT public.claim_opener_generation('${uuid()}'::uuid, '${uuid()}'::uuid, '${uuid()}'::uuid, 'x', '${uuid()}'::uuid, '{}'::jsonb, 3, 65)`), "permission denied");
    await rejects(asRole(role, `SELECT public.settle_opener_generation('${uuid()}'::uuid, '${uuid()}'::uuid, '${uuid()}'::uuid, '${uuid()}'::uuid, '{}'::jsonb, 30, 10, true, 3)`), "permission denied");
    await rejects(asRole(role, `SELECT public.claim_opener_analysis('${uuid()}'::uuid, '${uuid()}'::uuid, 'x', '${uuid()}'::uuid, 1, 2, 65)`), "permission denied");
    await rejects(asRole(role, `SELECT public.opener_flow_contract_version()`), "permission denied");
  }
  await asRole("service_role", `SELECT count(*) FROM public.opener_sessions`);
  const [{ marker }] = await asRole("service_role", `SELECT public.opener_flow_contract_version() AS marker`) as unknown as Array<{ marker: string }>;
  expect(marker === "opener-two-stage-v1", "service_role marker");
  return "anon／authenticated 全部 permission denied；service_role 可讀、可查 marker";
});

await Promise.all([A.end(), B.end(), O.end()]);
const failed = checks.filter((c) => c.status !== "PASS");
say("");
say(`## 結果：${checks.length - failed.length}/${checks.length} PASS${failed.length ? `，${failed.length} 未通過` : ""}`);
await Deno.writeTextFile(`${outArg}/results.json`, JSON.stringify({ pgVersion, marker, cfg: { host: cfg.host, port: cfg.port, database: cfg.database }, checks }, null, 2));
await Deno.writeTextFile(`${outArg}/results.md`, log.join("\n") + "\n");
Deno.exit(failed.length ? 1 : 0);
