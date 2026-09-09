// 朋友圈自拍貼文黑箱（local-only，付費，Eric 核准這一輪 40 通真呼叫）：
// 打生產真正的 buildMomentMessages（不重寫、不模擬其邏輯），量「此刻貼文」
// 有沒有把大頭照 photoScene 的固定背景故事講成正在發生的事——同一家族的
// bug 已在 2026-09-08 用 Fiona 真機案例記過一次（見 practice_persona.ts
// photoScene 欄位註解、tools/practice-behavior-smoke/cases.ts 的
// photo-fiona-france／photo-fiona-where／photo-natalie-dog）。
//
// 排程：momentPlanFor 是真的每日排程純函式，但現在 20 張場景圖已上線
// （moments_image_catalog AVAILABLE_MOMENT_IMAGE_IDS），自然情況下候選幾乎
// 不會退回自拍 sentinel（程式註解自己說「目前閘門全開時實測 0 則」）。
// 所以每位角色 20 則裡，前 10 則照真排程結果（含它自然選到的圖或無圖），
// 後 10 則沿用同一批真排程挑出的 themeId/contentKind/brief/dayPart，只把
// imageCandidates 強制改成 [SELF_PORTRAIT_IMAGE_ID]，逼進「這則配自己大頭照」
// 那個分支——這正是 photoScene 會被塞進 prompt 的唯一路徑
// （moments_prompt.ts imageDirective 的 onlySelfPortrait 分支）。
//
// 跑法（repo 根目錄；讀 ~/.config/anthropic/key）：
//   deno run --allow-read --allow-write --allow-env --allow-net=api.anthropic.com \
//     tools/moments-selfie-blackbox/run.ts
// 輸出 tools/moments-selfie-blackbox/out/<profileId>.json（不進 git，僅本機核對用）。
// ponytail: 不做 CLI 旗標，兩個 profile／各 20 則寫死在這支檔案，夠這次量測用。

import { getPracticeGirlProfile } from "../../supabase/functions/practice-chat/practice_persona.ts";
import {
  momentPlanFor,
  type MomentSlotPlan,
} from "../../supabase/functions/practice-chat/moments_schedule.ts";
import { buildMomentMessages } from "../../supabase/functions/practice-chat/moments_prompt.ts";
import {
  resolveAvailableMomentImages,
  SELF_PORTRAIT_IMAGE_ID,
} from "../../supabase/functions/practice-chat/moments_image_catalog.ts";
import { taipeiTimeContextFor } from "../../supabase/functions/practice-chat/time_context.ts";
import { replyStyleFor } from "../../supabase/functions/practice-chat/reply_style.ts";
import { parseJsonObjectFromText } from "../../supabase/functions/analyze-chat/json_text.ts";
import {
  callClaude,
  CLAUDE_SONNET_MODEL,
} from "../../supabase/functions/practice-chat/claude.ts";
import {
  MOMENT_MODEL_MAX_TOKENS,
  MOMENT_MODEL_TEMPERATURE,
  MOMENT_MODEL_TIMEOUT_MS,
} from "../../supabase/functions/practice-chat/moments_constants.ts";

const PROFILE_IDS = ["practice_girl_023", "practice_girl_022"] as const;
const PER_PROFILE = 20;
const FORCED_SELFIE_COUNT = 10; // 20 則裡後 10 則強制走自拍分支

interface CollectedSlot {
  isoDate: string;
  isWeekend: boolean;
  plan: MomentSlotPlan;
  imageCandidates: readonly string[];
  forcedSelfie: boolean;
}

/** 沿真排程日期往前走，蒐集 slot；不重寫 momentPlanFor 的機率邏輯。 */
function collectSlots(girl: ReturnType<typeof getPracticeGirlProfile> & object, need: number): CollectedSlot[] {
  const out: CollectedSlot[] = [];
  const start = new Date("2026-01-01T04:00:00.000Z"); // 台北時間 2026-01-01 12:00
  for (let day = 0; out.length < need && day < 2000; day++) {
    const at = new Date(start.getTime() + day * 86_400_000);
    const time = taipeiTimeContextFor(at);
    const plan = momentPlanFor({ girl, time });
    for (const slot of plan.slots) {
      if (out.length >= need) break;
      const resolvedCandidates = slot.wantsImage
        ? resolveAvailableMomentImages(slot.imageCandidates)
        : [];
      out.push({
        isoDate: time.isoDate,
        isWeekend: time.isWeekend,
        plan: slot,
        imageCandidates: resolvedCandidates,
        forcedSelfie: false,
      });
    }
  }
  return out;
}

interface ResultRow {
  profileId: string;
  displayName: string;
  isoDate: string;
  slot: number;
  themeId: string;
  contentKind: string;
  forcedSelfie: boolean;
  imageCandidatesSent: readonly string[];
  text: string | null;
  imageId: unknown;
  raw: string;
  error?: string;
}

const apiKey = (await Deno.readTextFile(`${Deno.env.get("HOME")}/.config/anthropic/key`)).trim();

let callCount = 0;
const outDir = new URL("./out/", import.meta.url);
await Deno.mkdir(outDir, { recursive: true });

for (const profileId of PROFILE_IDS) {
  const girl = getPracticeGirlProfile(profileId);
  if (!girl) throw new Error(`profile 不存在：${profileId}`);
  console.error(`== ${profileId} ${girl.displayName} photoScene=${girl.photoScene}`);

  const slots = collectSlots(girl, PER_PROFILE);
  if (slots.length < PER_PROFILE) {
    throw new Error(`${profileId} 只湊到 ${slots.length}/${PER_PROFILE} 個 slot`);
  }
  // 後 FORCED_SELFIE_COUNT 則強制自拍分支。
  for (let i = slots.length - FORCED_SELFIE_COUNT; i < slots.length; i++) {
    slots[i] = {
      ...slots[i],
      imageCandidates: [SELF_PORTRAIT_IMAGE_ID],
      forcedSelfie: true,
    };
  }

  const rows: ResultRow[] = [];
  for (const s of slots) {
    const messages = buildMomentMessages({
      girl,
      themeId: s.plan.themeId,
      contentKind: s.plan.contentKind,
      brief: s.plan.brief,
      dayPart: s.plan.dayPart,
      isoDate: s.isoDate,
      isWeekend: s.isWeekend,
      slot: s.plan.slot,
      imageCandidates: s.imageCandidates,
      generatedImage: false,
      replyStyle: replyStyleFor(profileId),
    });
    callCount += 1;
    console.error(`  [${callCount}] ${s.isoDate} slot${s.plan.slot} ${s.plan.themeId} forcedSelfie=${s.forcedSelfie}`);
    let raw = "";
    let text: string | null = null;
    let imageId: unknown = undefined;
    let error: string | undefined;
    try {
      raw = await callClaude({
        apiKey,
        model: CLAUDE_SONNET_MODEL,
        messages,
        maxTokens: MOMENT_MODEL_MAX_TOKENS,
        temperature: MOMENT_MODEL_TEMPERATURE,
        timeoutMs: MOMENT_MODEL_TIMEOUT_MS,
      });
      const parsed = parseJsonObjectFromText(raw) as
        | { text?: unknown; imageId?: unknown }
        | null;
      text = typeof parsed?.text === "string" ? parsed.text : null;
      imageId = parsed?.imageId;
    } catch (e) {
      error = e instanceof Error ? e.message : String(e);
    }
    rows.push({
      profileId,
      displayName: girl.displayName,
      isoDate: s.isoDate,
      slot: s.plan.slot,
      themeId: s.plan.themeId,
      contentKind: s.plan.contentKind,
      forcedSelfie: s.forcedSelfie,
      imageCandidatesSent: s.imageCandidates,
      text,
      imageId,
      raw,
      error,
    });
  }

  const outPath = new URL(`./${profileId}.json`, outDir);
  await Deno.writeTextFile(outPath, JSON.stringify(rows, null, 2));
  console.error(`寫入 ${outPath.pathname}（${rows.length} 則）`);
}

console.error(`共呼叫 Claude ${callCount} 次`);
