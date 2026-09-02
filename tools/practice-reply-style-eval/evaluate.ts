// 練習室寫實差異化 PR-0：確定性評測器（不打網路）。
//
// 吃 run_baseline.ts 的 artifact，算兩件事：
// 1. 每位角色的表面風格分佈（則數、字數、問句、你呢、笑聲、emoji、注音、語尾、標點）。
// 2. 「角色之間」與「同一角色不同次」的距離——只有前者明顯大於後者，才算真的有差異。
//    同一角色跨 repeat 的距離就是這套指標的雜訊帶（踩坑：指標沒量過自己的雜訊帶
//    就不能拿它比大小）。
//
// 這裡的距離只能當警報，不能當成功證明（規格 §10.4）：亂塞語尾也能拉開距離。
// 真人感與「像不像同一個人」由 judge.ts 的四選一與人工盲測決定。
//
//   deno run --allow-read tools/practice-reply-style-eval/evaluate.ts <artifact.json> [--json]

export interface ReplyFeatures {
  readonly bubbleCount: number;
  readonly totalChars: number;
  readonly questionCount: number;
  readonly reciprocal: 0 | 1;
  readonly laughter: 0 | 1;
  readonly emoji: 0 | 1;
  readonly zhuyin: 0 | 1;
  readonly particlesPer10: number;
  readonly punctPer10: number;
  readonly periodEnd: 0 | 1;
  /** 括號旁白動作描述（「（語氣冷掉）」）：prompt 明令禁止，出現即品質退步。 */
  readonly narration: 0 | 1;
}

export const FEATURE_KEYS = [
  "bubbleCount",
  "totalChars",
  "questionCount",
  "reciprocal",
  "laughter",
  "emoji",
  "zhuyin",
  "particlesPer10",
  "punctPer10",
  "periodEnd",
] as const satisfies readonly (keyof ReplyFeatures)[];

const QUESTION_RE = /[?？]|(嗎|呢)[。.!！～~]?$/;
const RECIPROCAL_RE = /[你妳]呢/;
const LAUGHTER_RE = /哈{2,}|呵呵|ㄏㄏ|嘿嘿|XD|笑死/i;
const EMOJI_RE = /\p{Extended_Pictographic}/u;
const ZHUYIN_RE = /[ㄅ-ㄩ]/;
const PARTICLE_RE = /(欸|誒|啦|耶|齁|喔|哦|嘛|捏|欸)(?=[\s。，,!！?？~～]|$)/g;
const PUNCT_RE = /[。！!？?，,~～…]/g;
const NARRATION_RE = /[（(][^）)]{2,14}[）)]/u;

export function replyFeatures(bubbles: readonly string[]): ReplyFeatures {
  const text = bubbles.join("\n");
  const stripped = text.replace(/\s+/g, "");
  const chars = Math.max(stripped.length, 1);
  const last = bubbles[bubbles.length - 1] ?? "";
  return {
    bubbleCount: bubbles.length,
    totalChars: stripped.length,
    questionCount: bubbles.filter((b) => QUESTION_RE.test(b)).length,
    reciprocal: RECIPROCAL_RE.test(text) ? 1 : 0,
    laughter: LAUGHTER_RE.test(text) ? 1 : 0,
    emoji: EMOJI_RE.test(text) ? 1 : 0,
    zhuyin: ZHUYIN_RE.test(text) ? 1 : 0,
    particlesPer10: (text.match(PARTICLE_RE)?.length ?? 0) / chars * 10,
    punctPer10: (text.match(PUNCT_RE)?.length ?? 0) / chars * 10,
    periodEnd: /。$/.test(last.trim()) ? 1 : 0,
    narration: NARRATION_RE.test(text) ? 1 : 0,
  };
}

export function shapeKey(f: ReplyFeatures): string {
  return `${f.bubbleCount}|q${
    f.questionCount > 0 ? 1 : 0
  }|l${f.laughter}|e${f.emoji}`;
}

export function charBigrams(text: string): Set<string> {
  const s = text.replace(/\s+/g, "");
  const out = new Set<string>();
  for (let i = 0; i + 1 < s.length; i++) out.add(s.slice(i, i + 2));
  return out;
}

export function jaccard(a: Set<string>, b: Set<string>): number {
  if (a.size === 0 && b.size === 0) return 1;
  let inter = 0;
  for (const x of a) if (b.has(x)) inter++;
  return inter / (a.size + b.size - inter);
}

// ── artifact 形狀（只列評測會讀的欄位；其餘用 ?. 容忍）──────────────────
interface ArtifactTurn {
  readonly bubbles: readonly string[];
  readonly reply: string;
  readonly elapsedMs?: number;
  readonly promptChars?: number;
  readonly attempts?: number;
  readonly guardRejections?: readonly string[];
}
interface ArtifactSession {
  readonly profileId: string;
  readonly scenarioId: string;
  readonly repeat: number;
  readonly turns: readonly ArtifactTurn[];
  readonly probe: ArtifactTurn | null;
  readonly error?: string;
}
export interface Artifact {
  readonly meta?: Record<string, unknown>;
  readonly results: readonly ArtifactSession[];
}

function mean(xs: number[]): number {
  return xs.length === 0 ? 0 : xs.reduce((a, b) => a + b, 0) / xs.length;
}
function std(xs: number[]): number {
  const m = mean(xs);
  return Math.sqrt(mean(xs.map((x) => (x - m) ** 2)));
}
function percentile(xs: number[], p: number): number {
  if (xs.length === 0) return 0;
  const sorted = [...xs].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.floor(p * sorted.length))];
}
function euclid(a: number[], b: number[]): number {
  return Math.sqrt(a.reduce((s, x, i) => s + (x - b[i]) ** 2, 0));
}

export interface ProfileStats {
  readonly replies: number;
  readonly means: Record<string, number>;
  readonly rates: {
    readonly question: number;
    readonly reciprocal: number;
    readonly laughter: number;
    readonly emoji: number;
    readonly zhuyin: number;
    readonly periodEnd: number;
    readonly narration: number;
  };
  readonly bubbleDist: Record<string, number>;
}

export interface ScenarioStats {
  readonly probes: number;
  /** 探針回覆裡最常見 shape（則數×問句×笑×emoji）佔比；越高越罐頭。 */
  readonly shapeConcentration: number;
  readonly topShape: string;
  /** 探針回覆前兩字相同的最大佔比。 */
  readonly sameOpeningShare: number;
  /** 不同角色探針回覆的字元 bigram Jaccard 均值。 */
  readonly crossProfileJaccard: number;
  /** 同角色不同 repeat 的 bigram Jaccard 均值（雜訊帶）。 */
  readonly withinProfileJaccard: number;
}

export interface EvalSummary {
  readonly sessions: number;
  readonly failed: number;
  readonly replies: number;
  readonly guardRejections: number;
  readonly latencyMs: { p50: number; p95: number };
  readonly promptCharsMax: number;
  readonly perProfile: Record<string, ProfileStats>;
  readonly perScenario: Record<string, ScenarioStats>;
  readonly separation: {
    /** 角色重心兩兩距離均值（z 分數空間）。 */
    readonly betweenProfiles: number;
    /** 同角色 odd/even repeat 分半重心距離均值＝雜訊帶。 */
    readonly withinProfile: number;
    /** between / within；≈1 代表角色之間跟自己跟自己一樣像。 */
    readonly ratio: number;
    /** 所有探針回覆兩兩比對：跨角色 vs 同角色的 bigram Jaccard。 */
    readonly probeJaccard: { cross: number; within: number };
  };
}

export function evaluate(artifact: Artifact): EvalSummary {
  const sessions = artifact.results;
  const ok = sessions.filter((s) => !s.error);
  const all: {
    profileId: string;
    scenarioId: string;
    repeat: number;
    f: ReplyFeatures;
    probe: boolean;
    text: string;
  }[] = [];
  const latencies: number[] = [];
  let guardRejections = 0;
  let promptCharsMax = 0;
  for (const s of ok) {
    s.turns.forEach((t, i) => {
      all.push({
        profileId: s.profileId,
        scenarioId: s.scenarioId,
        repeat: s.repeat,
        f: replyFeatures(t.bubbles),
        probe: i === s.turns.length - 1,
        text: t.reply,
      });
      if (t.elapsedMs !== undefined) latencies.push(t.elapsedMs);
      guardRejections += t.guardRejections?.length ?? 0;
      promptCharsMax = Math.max(promptCharsMax, t.promptChars ?? 0);
    });
  }

  const profileIds = [...new Set(all.map((r) => r.profileId))].sort();
  const perProfile: Record<string, ProfileStats> = {};
  for (const pid of profileIds) {
    const rs = all.filter((r) => r.profileId === pid);
    const means: Record<string, number> = {};
    for (const k of FEATURE_KEYS) means[k] = mean(rs.map((r) => r.f[k]));
    const bubbleDist: Record<string, number> = {};
    for (const r of rs) {
      const key = r.f.bubbleCount >= 4 ? "4+" : String(r.f.bubbleCount);
      bubbleDist[key] = (bubbleDist[key] ?? 0) + 1 / rs.length;
    }
    perProfile[pid] = {
      replies: rs.length,
      means,
      rates: {
        question: mean(rs.map((r) => (r.f.questionCount > 0 ? 1 : 0))),
        reciprocal: mean(rs.map((r) => r.f.reciprocal)),
        laughter: mean(rs.map((r) => r.f.laughter)),
        emoji: mean(rs.map((r) => r.f.emoji)),
        zhuyin: mean(rs.map((r) => r.f.zhuyin)),
        periodEnd: mean(rs.map((r) => r.f.periodEnd)),
        narration: mean(rs.map((r) => r.f.narration)),
      },
      bubbleDist,
    };
  }

  // z 分數空間的重心距離。
  const stds = FEATURE_KEYS.map((k) => std(all.map((r) => r.f[k])) || 1);
  const vec = (rs: typeof all) =>
    FEATURE_KEYS.map((k, i) => mean(rs.map((r) => r.f[k])) / stds[i]);
  const centroids = profileIds.map((pid) =>
    vec(all.filter((r) => r.profileId === pid))
  );
  const betweenPairs: number[] = [];
  for (let i = 0; i < centroids.length; i++) {
    for (let j = i + 1; j < centroids.length; j++) {
      betweenPairs.push(euclid(centroids[i], centroids[j]));
    }
  }
  const withinPairs = profileIds.map((pid) => {
    const rs = all.filter((r) => r.profileId === pid);
    const odd = rs.filter((r) => r.repeat % 2 === 1);
    const even = rs.filter((r) => r.repeat % 2 === 0);
    return odd.length && even.length ? euclid(vec(odd), vec(even)) : NaN;
  }).filter((x) => !Number.isNaN(x));
  const betweenProfiles = mean(betweenPairs);
  const withinProfile = mean(withinPairs);

  // 探針回覆的文字相似度：跨角色 vs 同角色。
  const perScenario: Record<string, ScenarioStats> = {};
  const crossAll: number[] = [];
  const withinAll: number[] = [];
  for (const sid of [...new Set(all.map((r) => r.scenarioId))].sort()) {
    const probes = all.filter((r) => r.scenarioId === sid && r.probe);
    const shapes = new Map<string, number>();
    const openings = new Map<string, number>();
    for (const p of probes) {
      const k = shapeKey(p.f);
      shapes.set(k, (shapes.get(k) ?? 0) + 1);
      const o = p.text.replace(/\s+/g, "").slice(0, 2);
      openings.set(o, (openings.get(o) ?? 0) + 1);
    }
    const [topShape, topCount] = [...shapes.entries()].sort((a, b) =>
      b[1] - a[1]
    )[0] ?? ["", 0];
    const cross: number[] = [];
    const within: number[] = [];
    for (let i = 0; i < probes.length; i++) {
      for (let j = i + 1; j < probes.length; j++) {
        const jac = jaccard(
          charBigrams(probes[i].text),
          charBigrams(probes[j].text),
        );
        (probes[i].profileId === probes[j].profileId ? within : cross).push(
          jac,
        );
      }
    }
    crossAll.push(...cross);
    withinAll.push(...within);
    perScenario[sid] = {
      probes: probes.length,
      shapeConcentration: probes.length ? topCount / probes.length : 0,
      topShape,
      sameOpeningShare: probes.length
        ? Math.max(...openings.values()) / probes.length
        : 0,
      crossProfileJaccard: mean(cross),
      withinProfileJaccard: mean(within),
    };
  }

  return {
    sessions: sessions.length,
    failed: sessions.length - ok.length,
    replies: all.length,
    guardRejections,
    latencyMs: {
      p50: percentile(latencies, 0.5),
      p95: percentile(latencies, 0.95),
    },
    promptCharsMax,
    perProfile,
    perScenario,
    separation: {
      betweenProfiles,
      withinProfile,
      ratio: withinProfile > 0 ? betweenProfiles / withinProfile : Infinity,
      probeJaccard: { cross: mean(crossAll), within: mean(withinAll) },
    },
  };
}

export function renderMarkdown(summary: EvalSummary): string {
  const pct = (x: number) => `${Math.round(x * 100)}%`;
  const num = (x: number, d = 2) => x.toFixed(d);
  const lines: string[] = [];
  lines.push(
    `場次 ${summary.sessions}（失敗 ${summary.failed}）、回覆 ${summary.replies}、守門退回 ${summary.guardRejections}、延遲 p50 ${summary.latencyMs.p50}ms／p95 ${summary.latencyMs.p95}ms、最長 prompt ${summary.promptCharsMax} code units`,
    "",
    "## 每位角色的表面風格",
    "",
    "| profile | n | 則數 | 字數 | 1則 | 2則 | 3則+ | 問句率 | 你呢 | 笑 | emoji | 注音 | 語尾/10字 | 標點/10字 | 句號收尾 | 旁白 |",
    "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
  );
  for (const [pid, p] of Object.entries(summary.perProfile)) {
    const b = p.bubbleDist;
    lines.push(
      `| ${pid} | ${p.replies} | ${num(p.means.bubbleCount)} | ${
        num(p.means.totalChars, 1)
      } | ${pct(b["1"] ?? 0)} | ${pct(b["2"] ?? 0)} | ${
        pct((b["3"] ?? 0) + (b["4+"] ?? 0))
      } | ${pct(p.rates.question)} | ${pct(p.rates.reciprocal)} | ${
        pct(p.rates.laughter)
      } | ${pct(p.rates.emoji)} | ${pct(p.rates.zhuyin)} | ${
        num(p.means.particlesPer10)
      } | ${num(p.means.punctPer10)} | ${pct(p.rates.periodEnd)} | ${
        pct(p.rates.narration)
      } |`,
    );
  }
  const s = summary.separation;
  lines.push(
    "",
    "## 角色之間拉不拉得開",
    "",
    `- 重心距離：角色之間 ${num(s.betweenProfiles)}、同角色分半（雜訊帶）${
      num(s.withinProfile)
    }、比值 **${num(s.ratio)}**（≈1 代表分不出來）`,
    `- 探針回覆 bigram Jaccard：跨角色 ${
      num(s.probeJaccard.cross, 3)
    }、同角色 ${num(s.probeJaccard.within, 3)}（兩者接近＝換人跟沒換一樣）`,
    "",
    "## 每個情境的罐頭程度（探針回覆）",
    "",
    "| scenario | n | 最常見形狀 | 佔比 | 同開頭佔比 | 跨角色 Jaccard | 同角色 Jaccard |",
    "|---|---:|---|---:|---:|---:|---:|",
  );
  for (const [sid, sc] of Object.entries(summary.perScenario)) {
    lines.push(
      `| ${sid} | ${sc.probes} | ${sc.topShape} | ${
        pct(sc.shapeConcentration)
      } | ${pct(sc.sameOpeningShare)} | ${num(sc.crossProfileJaccard, 3)} | ${
        num(sc.withinProfileJaccard, 3)
      } |`,
    );
  }
  return lines.join("\n") + "\n";
}

if (import.meta.main) {
  const path = Deno.args.find((a) => !a.startsWith("--"));
  if (!path) {
    console.error("用法：evaluate.ts <artifact.json> [--json]");
    Deno.exit(2);
  }
  const artifact = JSON.parse(await Deno.readTextFile(path)) as Artifact;
  const summary = evaluate(artifact);
  console.log(
    Deno.args.includes("--json")
      ? JSON.stringify(summary, null, 2)
      : renderMarkdown(summary),
  );
}
