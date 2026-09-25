// 規劃判類評測（需求凍結 §6-1、§6-2）。
//   --oracle：免費。用語料的正確標註組計畫，檢查寫手輸入「不該進的原文 0 次、該進的都在」。
//   dry run（預設）：免費。建規劃請求、印大小，不連網。
//   --live：付費①。規劃 × 語料 × --repeats 次，走 production 請求建構器（callClaudeWithFallback、
//           Sonnet 5、thinking disabled、不帶 temperature），只在 Eric 說「跑」之後使用。
// 用法：deno run -A tools/opener-plan-write-eval/plan_eval.ts [--oracle] [--live] [--repeats=3] [--cap-usd=5] [--out=<dir>]

import { callClaudeWithFallback } from "../../supabase/functions/analyze-chat/fallback.ts";
import { parseJsonObjectFromText } from "../../supabase/functions/analyze-chat/json_text.ts";
import { OPENER_FLOW_MODEL } from "../../supabase/functions/analyze-chat/opener_flow_prompt.ts";
import type { OpenerType } from "../../supabase/functions/analyze-chat/opener_payload.ts";
import {
  buildOpenerPlanUserContent,
  digestOpenerPlan,
  OPENER_PLAN_MAX_TOKENS,
  OPENER_PLAN_PROMPT,
  OPENER_PLAN_TIMEOUT_MS,
  type OpenerPlan,
  type OpenerPlanContext,
  type OpenerSpanRole,
  parseOpenerPlan,
} from "../../supabase/functions/analyze-chat/opener_plan.ts";
import { buildOpenerWriteUserContent } from "../../supabase/functions/analyze-chat/opener_write.ts";
import { type CapturedCall, corpusSnapshot, EVAL_DIR, installFetchCapture, parseArgs, readApiKey } from "./lib.ts";

interface CorpusSpan {
  quote: string;
  role: OpenerSpanRole;
  topicPart?: string | null;
  term?: string | null;
  readAs?: string | null;
}
interface CorpusItem {
  id: string;
  profileId: string;
  freeText: string;
  trap: boolean;
  note: string;
  spans: CorpusSpan[];
}

const PAID: OpenerType[] = ["extend", "resonate", "tease", "humor", "coldRead"];
/** 寫手絕不能看到原文的角色。 */
const HIDDEN_ROLES: OpenerSpanRole[] = ["background", "invite_request", "hostile", "sexual", "noise", "instruction", "profanity_tone"];
/** 安全閘門要算召回的角色。 */
const SAFETY_ROLES: OpenerSpanRole[] = ["hostile", "sexual", "invite_request"];

const args = parseArgs(Deno.args);
const allItems: CorpusItem[] = JSON.parse(await Deno.readTextFile(`${EVAL_DIR}corpus.json`)).items;
/** --limit=N 只跑前 N 句（煙霧測試）。 */
const corpus = args.limit === undefined ? allItems : allItems.slice(0, Number(args.limit));

function ctxFor(item: CorpusItem): OpenerPlanContext {
  return { snapshot: corpusSnapshot(item.profileId), freeText: item.freeText, option: null, visibleTypes: PAID };
}

/** 寫手輸入裡，不該進的原文（角色屬於 HIDDEN_ROLES 的逐字片段，去掉可合法出現的活動詞）。 */
function hiddenLeaks(item: CorpusItem, writerInput: string): string[] {
  const leaks: string[] = [];
  for (const span of item.spans) {
    if (!HIDDEN_ROLES.includes(span.role)) continue;
    // 邀約裡的活動本身可以當話題進寫手；檢查的是整段邀約原句。
    const quote = span.quote.trim();
    if (quote.length >= 3 && writerInput.includes(quote) && quote !== span.topicPart) leaks.push(`${span.role}:${quote}`);
  }
  return leaks;
}

function writerInputFor(item: CorpusItem, plan: OpenerPlan): string {
  const ctx = ctxFor(item);
  const digest = digestOpenerPlan(plan, ctx);
  return buildOpenerWriteUserContent({ snapshot: ctx.snapshot, freeText: item.freeText, plan, digest, primaryStyle: "extend", arm: "styles" });
}

/** 預測片段對到期望片段：用字元重疊最多的那段的角色。 */
function predictedRoleFor(expected: CorpusSpan, freeText: string, plan: OpenerPlan): OpenerSpanRole | null {
  const at = freeText.indexOf(expected.quote);
  if (at < 0) return null;
  const range = [at, at + expected.quote.length];
  let best: { role: OpenerSpanRole; overlap: number } | null = null;
  let cursor = 0;
  for (const span of plan.spans) {
    const s = freeText.indexOf(span.quote, cursor);
    if (s < 0) continue;
    cursor = s + span.quote.length;
    const overlap = Math.max(0, Math.min(range[1], s + span.quote.length) - Math.max(range[0], s));
    if (overlap > 0 && (!best || overlap > best.overlap)) best = { role: span.role, overlap };
  }
  return best?.role ?? null;
}

// ── --oracle：免費結構檢查 ──
if (args.oracle) {
  let leakCount = 0;
  let adoptedMissing = 0;
  for (const item of corpus) {
    const plan = parseOpenerPlan({ spans: item.spans, anchorCueIds: ["cue_1"] }, ctxFor(item));
    const input = writerInputFor(item, plan);
    const leaks = hiddenLeaks(item, input);
    leakCount += leaks.length;
    if (leaks.length) console.log(`LEAK ${item.id}: ${leaks.join(" | ")}`);
    for (const span of item.spans) {
      if (["topic", "question", "draft_message", "sender_fact"].includes(span.role)) {
        // 草稿與本人自述照原句送（不用模型讀法，避免讀法偷加細節）；話題與問題用讀法。
        const text = ["draft_message", "sender_fact"].includes(span.role) || !span.readAs ? span.quote : span.readAs;
        if (!input.includes(text)) {
          adoptedMissing += 1;
          console.log(`MISSING ${item.id}: ${span.role}:${text}`);
        }
      }
    }
  }
  const planChars = OPENER_PLAN_PROMPT.length;
  console.log(JSON.stringify({ items: corpus.length, hiddenLeaks: leakCount, adoptedMissing, plannerSystemChars: planChars }));
  if (leakCount || adoptedMissing) Deno.exit(1);
  Deno.exit(0);
}

// ── dry run／live ──
const live = args.live === true;
const repeats = Number(args.repeats ?? 3);
/** --repeat=N 只跑第 N 次（三個程序並行各跑一次，各自有上限）。 */
const onlyRepeat = args.repeat === undefined ? null : Number(args.repeat);
const capUsd = Number(args["cap-usd"] ?? 5);
const out = String(args.out ?? `${EVAL_DIR}out/${live ? "live" : "dry"}-plan`);
await Deno.mkdir(out, { recursive: true });
const apiKey = live ? await readApiKey() : "";
let spent = 0;
const rows: Array<Record<string, unknown>> = [];
for (let repeat = 1; repeat <= repeats; repeat++) {
  if (onlyRepeat !== null && repeat !== onlyRepeat) continue;
  for (const item of corpus) {
    const ctx = ctxFor(item);
    const user = buildOpenerPlanUserContent(ctx);
    if (!live) {
      rows.push({ id: item.id, repeat, userChars: user.length });
      continue;
    }
    if (spent + 0.03 > capUsd) {
      rows.push({ id: item.id, repeat, status: "NOT_SENT_BUDGET" });
      continue;
    }
    const calls: CapturedCall[] = [];
    const restore = installFetchCapture(calls);
    let raw: string | null = null;
    let error: string | null = null;
    try {
      const result = await callClaudeWithFallback(
        { model: OPENER_FLOW_MODEL, max_tokens: OPENER_PLAN_MAX_TOKENS, system: OPENER_PLAN_PROMPT, messages: [{ role: "user", content: user }] },
        apiKey,
        { timeout: OPENER_PLAN_TIMEOUT_MS, maxRetries: 1, allowModelFallback: false, purpose: "plan", absoluteDeadlineAtMs: Date.now() + OPENER_PLAN_TIMEOUT_MS },
      );
      const data = result.data as { content?: Array<{ type?: string; text?: string }> };
      raw = (data.content ?? []).filter((b) => b.type === "text").map((b) => b.text ?? "").join("");
    } catch (e) {
      error = e instanceof Error ? e.message : String(e);
    } finally {
      restore();
    }
    const cost = calls.reduce((s, c) => s + (c.costUsd ?? 0), 0);
    spent += cost;
    const plan = raw ? parseOpenerPlan(parseJsonObjectFromText(raw), ctx) : null;
    const expectedRoles = item.spans.map((s) => s.role);
    const predictedRoles = plan ? item.spans.map((s) => predictedRoleFor(s, item.freeText, plan)) : [];
    const leaks = plan ? hiddenLeaks(item, writerInputFor(item, plan)) : [];
    const row = {
      id: item.id, repeat, trap: item.trap, profileId: item.profileId, error, costUsd: cost,
      elapsedMs: calls[0]?.elapsedMs ?? null, planSource: plan?.source ?? null, repaired: plan?.repairedFields ?? [],
      expectedRoles, predictedRoles, leaks, raw,
    };
    rows.push(row);
    await Deno.writeTextFile(`${out}/${item.id}.${repeat}.json`, JSON.stringify({ item, row, calls }, null, 1));
    console.log(JSON.stringify({ id: item.id, repeat, ok: !error, spentUsd: Number(spent.toFixed(5)), match: expectedRoles.map((r, i) => r === predictedRoles[i]) }));
  }
}

// ── 指標（只在 live 有意義）──
if (live) {
  const perRepeat = [] as Array<Record<string, unknown>>;
  for (let repeat = 1; repeat <= repeats; repeat++) {
    if (onlyRepeat !== null && repeat !== onlyRepeat) continue;
    const rs = rows.filter((r) => r.repeat === repeat && Array.isArray(r.expectedRoles)) as Array<{ trap: boolean; expectedRoles: string[]; predictedRoles: (string | null)[]; leaks: string[] }>;
    const pairs = rs.flatMap((r) => r.expectedRoles.map((e, i) => ({ e, p: r.predictedRoles[i], trap: r.trap })));
    const recall = Object.fromEntries(SAFETY_ROLES.map((role) => {
      const exp = pairs.filter((x) => x.e === role);
      return [role, exp.length ? exp.filter((x) => x.p === role).length / exp.length : null];
    }));
    // 陷阱誤判：期望不是冒犯／性冒犯，卻被判成冒犯／性冒犯。
    const trapFalseOffense = pairs.filter((x) => x.trap && !["hostile", "sexual"].includes(x.e) && ["hostile", "sexual"].includes(String(x.p))).length;
    perRepeat.push({
      repeat,
      spans: pairs.length,
      accuracy: pairs.filter((x) => x.e === x.p).length / Math.max(1, pairs.length),
      safetyRecall: recall,
      trapFalseOffense,
      writerLeaks: rs.reduce((s, r) => s + r.leaks.length, 0),
    });
  }
  await Deno.writeTextFile(`${out}/metrics${onlyRepeat ? `.r${onlyRepeat}` : ""}.json`, JSON.stringify({ spentUsd: spent, perRepeat }, null, 1));
  console.log(JSON.stringify({ spentUsd: spent, perRepeat }, null, 1));
} else {
  const sizes = rows.map((r) => Number(r.userChars));
  console.log(JSON.stringify({ dryRun: true, requests: rows.length, plannerSystemChars: OPENER_PLAN_PROMPT.length, userCharsMax: Math.max(...sizes) }));
}
