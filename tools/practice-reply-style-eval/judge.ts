// 練習室寫實差異化 PR-0：「同 persona 內四選一」LLM 盲測（規格 §10.5）。
//
// 給評審四位角色（A–D）的校準對話，再給一段留出情境的新對話，問「最像哪一位」。
// 四位都是同 persona，猜中率的機率基準是 25%。baseline 預期接近 25%；規格上線門檻
// 是 ≥70% 且不能靠單一口頭禪。LLM 只是輔助訊號，真人感由人工盲測決定。
//
// 防洩漏：user 訊息四位完全相同，不帶身份資訊；但 interrogation（她會講年齡城市
// 職業）與 interest_hit（user 訊息含她的興趣 tag）會讓評審靠「事實」而非「說話方式」
// 猜人，所以兩者都不進評審集合。
//
//   deno run --allow-env --allow-read --allow-write --allow-net=api.deepseek.com \
//     tools/practice-reply-style-eval/judge.ts <artifact.json> [--model=deepseek-v4-flash] [--concurrency=4]

import {
  callDeepSeek,
  DEEPSEEK_MODEL,
} from "../../supabase/functions/practice-chat/deepseek.ts";
import { GIRL_PROFILES } from "../../supabase/functions/practice-chat/practice_persona.ts";

export const CALIBRATION_SCENARIOS = [
  "opening",
  "daily_share",
  "light_joke",
  "disagreement",
  "early_invite",
] as const;
export const HELD_OUT_SCENARIOS = [
  "vulnerability",
  "failed_joke",
  "mature_invite",
  "boundary",
  "memory_mismatch",
] as const;
const LETTERS = ["A", "B", "C", "D"] as const;

interface Turn {
  readonly userText: string;
  readonly bubbles: readonly string[];
}
interface Session {
  readonly profileId: string;
  readonly personaId?: string;
  readonly scenarioId: string;
  readonly repeat: number;
  readonly turns: readonly Turn[];
  readonly error?: string;
}

/**
 * 事實遮罩（Codex R1 P1）：把同組四位的名字、城市、職業、興趣、年齡數字換成 ＊，
 * 評審只能靠說話方式。遮不掉的生活情境（剛飛完、剛收診）仍可能外洩，屬已知限制。
 */
export function factMasker(
  profileIds: readonly string[],
): (text: string) => string {
  const words = new Set<string>();
  for (
    const g of GIRL_PROFILES.filter((g) => profileIds.includes(g.profileId))
  ) {
    for (
      const w of [
        g.displayName,
        g.nameId,
        g.city,
        g.professionLabel,
        ...g.interestTags,
      ]
    ) {
      if (w.length >= 2) words.add(w);
    }
    words.add(String(g.age));
  }
  const sorted = [...words].sort((a, b) => b.length - a.length);
  return (text) => {
    let out = text;
    for (const w of sorted) out = out.split(w).join("＊");
    return out;
  };
}

export function renderTranscript(
  turns: readonly Turn[],
  mask: (text: string) => string = (t) => t,
): string {
  return turns.map((t) =>
    `男：${mask(t.userText)}\n她：${mask(t.bubbles.join(" ／ "))}`
  )
    .join("\n");
}

// 確定性洗牌：trial index 決定 A–D 對到哪位角色，避免位置偏差。
export function letterAssignment(
  profileIds: readonly string[],
  trialIndex: number,
): string[] {
  const order = [...profileIds];
  let seed = trialIndex * 2654435761 + 97;
  for (let i = order.length - 1; i > 0; i--) {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    const j = seed % (i + 1);
    [order[i], order[j]] = [order[j], order[i]];
  }
  return order;
}

export interface Trial {
  readonly index: number;
  readonly personaId: string;
  readonly scenarioId: string;
  readonly repeat: number;
  readonly truthProfileId: string;
  readonly assignment: readonly string[];
  readonly prompt: string;
}

export function buildTrials(sessions: readonly Session[]): Trial[] {
  const ok = sessions.filter((s) => !s.error && s.turns.length > 0);
  // 同 legacy persona 內四選一（規格 §10.5）：>4 位時依 personaId 分組，每組恰 4 位。
  const groups = new Map<string, string[]>();
  for (const s of ok) {
    const key = s.personaId ?? "all";
    const list = groups.get(key) ?? [];
    if (!list.includes(s.profileId)) list.push(s.profileId);
    groups.set(key, list);
  }
  const trials: Trial[] = [];
  let index = 0;
  for (const [personaId, ids] of [...groups.entries()].sort()) {
    const profileIds = [...ids].sort();
    if (profileIds.length !== 4) {
      throw new Error(
        `judge_group_needs_four_profiles: ${personaId} has ${profileIds.length}`,
      );
    }
    const inGroup = ok.filter((s) => profileIds.includes(s.profileId));
    const mask = factMasker(profileIds);
    const calibration = (pid: string) =>
      CALIBRATION_SCENARIOS.map((sid) =>
        inGroup.find((s) =>
          s.profileId === pid && s.scenarioId === sid && s.repeat === 1
        )
      )
        .filter((s): s is Session => s !== undefined)
        .map((s) => renderTranscript(s.turns, mask)).join("\n---\n");
    const heldOut = inGroup.filter((s) =>
      (HELD_OUT_SCENARIOS as readonly string[]).includes(s.scenarioId)
    )
      .sort((a, b) =>
        a.scenarioId.localeCompare(b.scenarioId) ||
        a.profileId.localeCompare(b.profileId) || a.repeat - b.repeat
      );
    for (const s of heldOut) {
      const assignment = letterAssignment(profileIds, index);
      const calibrationBlock = assignment.map((pid, i) =>
        `【${LETTERS[i]}】\n${calibration(pid)}`
      ).join("\n\n");
      const prompt = [
        "以下是四位不同的女生（A、B、C、D）在交友 App 上跟同一個男生的私訊樣本。男生的訊息四位都一樣，只有她們的回覆不同。",
        "",
        calibrationBlock,
        "",
        "====",
        "下面是一段新的對話，出自 A、B、C、D 其中一位：",
        "",
        renderTranscript(s.turns, mask),
        "",
        "＊ 是被遮掉的名字、地點、職業等事實。請只根據她的「說話方式」判斷是誰：句子長短、一次回幾則、語氣詞、標點習慣、笑法、會不會反問、直接還是委婉、怎麼接受或婉拒。不要依賴她提到的職業、地點、年齡、行程等事實。",
        '只回 JSON：{"answer":"A|B|C|D","confidence":0到1,"cue":"一句話說明你靠什麼線索"}',
      ].join("\n");
      trials.push({
        index,
        personaId,
        scenarioId: s.scenarioId,
        repeat: s.repeat,
        truthProfileId: s.profileId,
        assignment,
        prompt,
      });
      index++;
    }
  }
  return trials;
}

export interface TrialResult extends Omit<Trial, "prompt"> {
  readonly answer: string | null;
  readonly answerProfileId: string | null;
  readonly correct: boolean;
  readonly confidence: number | null;
  readonly cue: string;
  readonly error?: string;
}

export function summarize(results: readonly TrialResult[]) {
  const valid = results.filter((r) => !r.error);
  const acc = (rs: readonly TrialResult[]) =>
    rs.length ? rs.filter((r) => r.correct).length / rs.length : 0;
  const byProfile: Record<string, number> = {};
  const byPersona: Record<string, number> = {};
  const byScenario: Record<string, number> = {};
  const confusion: Record<string, Record<string, number>> = {};
  for (const pid of new Set(valid.map((r) => r.truthProfileId))) {
    byProfile[pid] = acc(valid.filter((r) => r.truthProfileId === pid));
    confusion[pid] = {};
  }
  for (const sid of new Set(valid.map((r) => r.scenarioId))) {
    byScenario[sid] = acc(valid.filter((r) => r.scenarioId === sid));
  }
  for (const pid of new Set(valid.map((r) => r.personaId))) {
    byPersona[pid] = acc(valid.filter((r) => r.personaId === pid));
  }
  for (const r of valid) {
    if (r.answerProfileId) {
      confusion[r.truthProfileId][r.answerProfileId] =
        (confusion[r.truthProfileId][r.answerProfileId] ?? 0) + 1;
    }
  }
  // bootstrap 95%（1000 次、確定性 LCG）：n=60 一組時單點準確率雜訊約 ±12%。
  let seed = 20260902;
  const rand = () =>
    (seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff;
  const boots: number[] = [];
  for (let i = 0; i < 1000 && valid.length > 0; i++) {
    let hit = 0;
    for (let k = 0; k < valid.length; k++) {
      if (valid[Math.floor(rand() * valid.length)].correct) hit++;
    }
    boots.push(hit / valid.length);
  }
  boots.sort((a, b) => a - b);
  const accuracyCi95 = boots.length
    ? [
      boots[Math.floor(boots.length * 0.025)],
      boots[Math.floor(boots.length * 0.975)],
    ]
    : null;
  return {
    trials: results.length,
    valid: valid.length,
    accuracy: acc(valid),
    accuracyCi95,
    chance: 0.25,
    byPersona,
    byProfile,
    byScenario,
    confusion,
  };
}

async function main(): Promise<void> {
  const path = Deno.args.find((a) => !a.startsWith("--"));
  if (!path) {
    console.error(
      "用法：judge.ts <artifact.json> [--model=…] [--concurrency=4]",
    );
    Deno.exit(2);
  }
  const flag = (k: string, d: string) =>
    Deno.args.find((a) => a.startsWith(`--${k}=`))?.slice(k.length + 3) ?? d;
  const model = flag("model", DEEPSEEK_MODEL);
  const concurrency = Number.parseInt(flag("concurrency", "4"), 10);
  const apiKey = Deno.env.get("DEEPSEEK_API_KEY");
  if (!apiKey) throw new Error("judge_missing_key: DEEPSEEK_API_KEY");
  const artifact = JSON.parse(await Deno.readTextFile(path)) as {
    meta?: Record<string, unknown>;
    results: Session[];
  };
  const trials = buildTrials(artifact.results);
  const results: TrialResult[] = new Array(trials.length);
  let next = 0;
  const worker = async () => {
    while (next < trials.length) {
      const i = next++;
      const t = trials[i];
      const { prompt: _prompt, ...rest } = t;
      try {
        const raw = await callDeepSeek({
          apiKey,
          model,
          messages: [{ role: "user", content: t.prompt }],
          maxTokens: 300,
          temperature: 0,
          jsonMode: true,
          timeoutMs: 60000,
        });
        const parsed = JSON.parse(raw) as {
          answer?: string;
          confidence?: number;
          cue?: string;
        };
        const answer = typeof parsed.answer === "string"
          ? parsed.answer.trim().toUpperCase().slice(0, 1)
          : null;
        const letterIndex = answer
          ? (LETTERS as readonly string[]).indexOf(answer)
          : -1;
        const answerProfileId = letterIndex >= 0
          ? t.assignment[letterIndex]
          : null;
        results[i] = {
          ...rest,
          answer,
          answerProfileId,
          correct: answerProfileId === t.truthProfileId,
          confidence: typeof parsed.confidence === "number"
            ? parsed.confidence
            : null,
          cue: typeof parsed.cue === "string" ? parsed.cue : "",
        };
      } catch (e) {
        results[i] = {
          ...rest,
          answer: null,
          answerProfileId: null,
          correct: false,
          confidence: null,
          cue: "",
          error: e instanceof Error ? e.message : String(e),
        };
      }
      console.error(
        `[judge] ${
          i + 1
        }/${trials.length} ${t.personaId}/${t.scenarioId}#${t.repeat} ${
          results[i].correct ? "✓" : "✗"
        }${results[i].error ? " " + results[i].error : ""}`,
      );
    }
  };
  await Promise.all(Array.from({ length: concurrency }, worker));
  const summary = summarize(results);
  const outPath = path.replace(/\.json$/, "") + "-judge.json";
  await Deno.writeTextFile(
    outPath,
    JSON.stringify(
      {
        meta: {
          sourceArtifact: path,
          sourceCommit: artifact.meta?.commit,
          judgeModel: model,
          temperature: 0,
          generatedAt: new Date().toISOString(),
          calibration: CALIBRATION_SCENARIOS,
          heldOut: HELD_OUT_SCENARIOS,
        },
        summary,
        results,
      },
      null,
      2,
    ) + "\n",
  );
  console.log(JSON.stringify(summary, null, 2));
  console.error(`[judge] 寫入 ${outPath}`);
}

if (import.meta.main) {
  main().catch((e) => {
    console.error(
      `[judge] 致命錯誤：${
        e instanceof Error ? e.stack ?? e.message : String(e)
      }`,
    );
    Deno.exit(1);
  });
}
