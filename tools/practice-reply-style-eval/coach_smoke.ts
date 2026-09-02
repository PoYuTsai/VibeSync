// 練習室寫實差異化 PR-4／PR-5：Hint／Debrief／Moments 真模型輸出煙霧測試。
//
// 對 20 位代表角色各取 run15 一段對話，style 開／關各打一次 Hint、Debrief、Moments
// 的 production prompt，跑 production parser（parseHintResult／parseDebriefCard／
// validateMomentDraft），數：解析失敗、守門退回、以及輸出有沒有把基準數字或設定
// 講出來（「1～2 則」「3～14 字」這種形狀）。模型用 DeepSeek（Hint／Debrief 在
// production 主打 Claude、DeepSeek 是失效轉移；這裡量的是格式契約與洩漏，不是文采）。
//
// 用法：
//   deno run --allow-env --allow-read --allow-write --allow-net=api.deepseek.com \
//     tools/practice-reply-style-eval/coach_smoke.ts <run-artifact.json> [--out=<file>] [--concurrency=6]

import { callDeepSeek } from "../../supabase/functions/practice-chat/deepseek.ts";
import {
  GIRL_PROFILES,
  resolvePracticeProfile,
} from "../../supabase/functions/practice-chat/practice_persona.ts";
import {
  buildHintMessages,
  parseHintResult,
} from "../../supabase/functions/practice-chat/hint.ts";
import { buildDebriefMessages } from "../../supabase/functions/practice-chat/prompt.ts";
import { parseDebriefCard } from "../../supabase/functions/practice-chat/debrief_card.ts";
import { buildMomentMessages } from "../../supabase/functions/practice-chat/moments_prompt.ts";
import { validateMomentDraft } from "../../supabase/functions/practice-chat/moments_validate.ts";
import { replyStyleFor } from "../../supabase/functions/practice-chat/reply_style.ts";
import type { PracticeTurn } from "../../supabase/functions/practice-chat/validate.ts";
import { DEFAULT_PROFILE_IDS, readDeepSeekKey } from "./run_baseline.ts";

interface Round {
  userText: string;
  reply: string;
}
interface SessionRecord {
  profileId: string;
  scenarioId: string;
  repeat: number;
  turns: Round[];
  probe: Round;
}

// 基準數字外洩：阿拉伯／中文數字的範圍或單值接「則／字／顆／句」，
// 例：「1～2 則」「3～14 字」「通常只回一則」「大概十個字」「兩三則」（Codex R2 加寬）。
const NUM = "(?:\\d+|[一二兩三四五六七八九十]+)";
const BASELINE_LEAK_RE = new RegExp(
  `(?:${NUM}\\s*[～~\\-–到]\\s*${NUM}|(?:通常|平常|大概|大約|一般|一次)\\s*(?:只)?(?:回|發|講|打)?\\s*${NUM})\\s*(?:個)?(?:則|字|顆|句)`,
  "u",
);
// 設定／機制字眼：一般「基準」「設定」「風格檔」也算（會有誤中，人工看 raw）。
const SETTING_LEAK_RE =
  /(hidden evidence|preset|reply-style|基準|設定|風格檔|打字習慣|說話習慣|系統)/iu;

function flag(name: string, fallback: string): string {
  return Deno.args.find((a) => a.startsWith(`--${name}=`))?.slice(
    name.length + 3,
  ) ?? fallback;
}

async function main() {
  const artifactPath = Deno.args.find((a) => !a.startsWith("--"));
  if (!artifactPath) throw new Error("用法：coach_smoke.ts <artifact.json>");
  const artifact = JSON.parse(await Deno.readTextFile(artifactPath));
  const results = artifact.results as SessionRecord[];
  const profiles = new Set<string>(DEFAULT_PROFILE_IDS);
  const sessions = results.filter((r) =>
    profiles.has(r.profileId) && r.repeat === 1 &&
    r.scenarioId === "daily_share"
  );
  const apiKey = await readDeepSeekKey();
  const concurrency = Number.parseInt(flag("concurrency", "6"), 10);
  const outPath = flag(
    "out",
    artifactPath.replace(/\.json$/, "-coach-smoke.json"),
  );

  type Row = {
    profileId: string;
    surface: "hint" | "debrief" | "moments";
    variant: "off" | "on";
    ok: boolean;
    error: string | null;
    baselineLeak: boolean;
    settingLeak: boolean;
    outputChars: number;
    raw: string;
  };
  const rows: Row[] = [];
  const jobs = sessions.flatMap((s) =>
    (["hint", "debrief", "moments"] as const).flatMap((surface) =>
      (["off", "on"] as const).map((variant) => ({ s, surface, variant }))
    )
  );
  let next = 0;
  let done = 0;
  const call = (
    messages: { role: string; content: string }[],
    maxTokens: number,
  ) =>
    callDeepSeek({
      apiKey,
      messages: messages as {
        role: "system" | "user" | "assistant";
        content: string;
      }[],
      maxTokens,
      temperature: 0.7,
      timeoutMs: 45_000,
    });
  const worker = async () => {
    while (next < jobs.length) {
      const { s, surface, variant } = jobs[next++];
      const profile = resolvePracticeProfile({ profileId: s.profileId });
      const style = variant === "on" ? replyStyleFor(s.profileId) : null;
      const turns: PracticeTurn[] = [];
      for (const r of s.turns) {
        turns.push({ role: "user", text: r.userText });
        turns.push({ role: "ai", text: r.reply });
      }
      turns.push({ role: "user", text: s.probe.userText });
      turns.push({ role: "ai", text: s.probe.reply });
      let raw = "";
      let ok = false;
      let error: string | null = null;
      try {
        if (surface === "hint") {
          raw = await call(
            buildHintMessages({
              turns,
              profile,
              practiceMode: "beginner",
              temperatureScore: 40,
              familiarityScore: 10,
              replyStyle: style,
            }),
            900,
          );
          parseHintResult(raw);
        } else if (surface === "debrief") {
          raw = await call(
            buildDebriefMessages(turns, profile, {
              practiceMode: "beginner",
              temperatureScore: 40,
              familiarityScore: 10,
              replyStyle: style,
            }),
            1400,
          );
          parseDebriefCard(raw, { turns });
        } else {
          const girl = GIRL_PROFILES.find((g) => g.profileId === s.profileId)!;
          raw = await call(
            buildMomentMessages({
              girl,
              themeId: "coffee_break",
              contentKind: "daily_life",
              brief: "在常去的咖啡店坐一下，看窗外發呆",
              dayPart: "afternoon",
              isoDate: "2026-09-03",
              isWeekend: false,
              slot: 0,
              imageCandidates: [],
              replyStyle: style,
            }),
            300,
          );
          validateMomentDraft({ raw, imageCandidates: [] });
        }
        ok = true;
      } catch (e) {
        error = e instanceof Error ? e.message : String(e);
      }
      rows.push({
        profileId: s.profileId,
        surface,
        variant,
        ok,
        error,
        baselineLeak: BASELINE_LEAK_RE.test(raw),
        settingLeak: SETTING_LEAK_RE.test(raw),
        outputChars: raw.length,
        raw,
      });
      done++;
      if (done % 20 === 0) {
        console.error(`[coach-smoke] ${done}/${jobs.length}`);
      }
    }
  };
  await Promise.all(Array.from({ length: concurrency }, worker));

  const summary: Record<string, Record<string, unknown>> = {};
  for (const surface of ["hint", "debrief", "moments"]) {
    for (const variant of ["off", "on"]) {
      const sub = rows.filter((r) =>
        r.surface === surface && r.variant === variant
      );
      const errors: Record<string, number> = {};
      for (const r of sub) {
        if (r.error) errors[r.error] = (errors[r.error] ?? 0) + 1;
      }
      summary[`${surface}/${variant}`] = {
        n: sub.length,
        ok: sub.filter((r) => r.ok).length,
        baselineLeak: sub.filter((r) => r.baselineLeak).length,
        settingLeak: sub.filter((r) => r.settingLeak).length,
        errors,
      };
    }
  }
  await Deno.writeTextFile(
    outPath,
    JSON.stringify(
      { source: artifactPath, sessions: sessions.length, summary, rows },
      null,
      2,
    ),
  );
  console.log(JSON.stringify(summary, null, 2));
}

if (import.meta.main) await main();
