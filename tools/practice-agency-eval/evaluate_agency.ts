// 練習室對話主體意識 Phase 0：judge 輸出 → 指標（純函式，不打網路）。
//
// 每個指標的分母是 scenarios.ts 裡宣告的探針分類（結構事實），分子是 judge 的標籤
// （語意）。TypeScript 不判語意。
//
//   deno run --allow-read tools/practice-agency-eval/evaluate_agency.ts \
//     tools/practice-agency-eval/out/<file>-judge.json

import {
  AGENCY_PROBES,
  type AgencyLabel,
  type ProbeKind,
} from "./scenarios.ts";

export interface JudgedProbe {
  readonly probeId: string;
  readonly scenarioId: string;
  readonly profileId: string;
  readonly personaId?: string;
  readonly difficulty: string;
  readonly mode: string;
  readonly repeat: number;
  readonly kinds: readonly ProbeKind[];
  readonly labels: Record<AgencyLabel, boolean> | null;
  readonly error?: string;
}

export interface Rate {
  readonly n: number;
  readonly hits: number;
  readonly rate: number;
  readonly ci95: readonly [number, number] | null;
}

/** bootstrap 95%（1000 次、確定性 LCG，與 reply-style judge 同一套）。 */
export function bootstrapRate(
  flags: readonly boolean[],
  seed = 20260903,
): Rate {
  const n = flags.length;
  const hits = flags.filter(Boolean).length;
  if (n === 0) return { n: 0, hits: 0, rate: 0, ci95: null };
  let s = seed;
  const rand = () => (s = (s * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff;
  const boots: number[] = [];
  for (let i = 0; i < 1000; i++) {
    let hit = 0;
    for (let k = 0; k < n; k++) if (flags[Math.floor(rand() * n)]) hit++;
    boots.push(hit / n);
  }
  boots.sort((a, b) => a - b);
  return {
    n,
    hits,
    rate: hits / n,
    ci95: [
      boots[Math.floor(boots.length * 0.025)],
      boots[Math.floor(boots.length * 0.975)],
    ],
  };
}

const PROBE_ORDER = new Map<string, number>(
  AGENCY_PROBES.map((p, i) => [p.id, i]),
);
const PROBE_SPECS = new Map(AGENCY_PROBES.map((p) => [p.id, p]));

const sessionKey = (p: JudgedProbe) =>
  `${p.mode}|${p.difficulty}|${p.profileId}|${p.scenarioId}|${p.repeat}`;

export interface AgencyMetrics {
  readonly probes: number;
  readonly judged: number;
  readonly parseFailures: number;
  /** 高信心無關片段的盲目跟題率（報告 §11 門檻 ≤5%）。 */
  readonly blindFollow: Rate;
  /** 有效短答／明示換題被誤質疑（≤3%，A01／A03／A07／A09）。 */
  readonly falseChallenge: Rate;
  /** 設定外具體自身經歷（大樣本 <1%）。 */
  readonly fabricatedSelfFact: Rate;
  /** 指出怪異後、玩家未解釋前，下一個片段探針沒有回去盲目跟題（≥95%）。 */
  readonly stancePersistence: Rate;
  /** 一則裡連續查基本資料（≤5%）。 */
  readonly interrogation: Rate;
  /** 命中任何一個 mustForbid。 */
  readonly forbidViolation: Rate;
  /** 至少命中一個 mustAllow。 */
  readonly allowSatisfied: Rate;
  readonly perScenario: Record<string, {
    readonly n: number;
    readonly blindFollow: number;
    readonly clarifyOrChallenge: number;
    readonly falseChallenge: number;
    readonly fabricatedSelfFact: number;
    readonly forbidViolation: number;
    readonly allowSatisfied: number;
  }>;
}

export function evaluateAgency(
  results: readonly JudgedProbe[],
): AgencyMetrics {
  const judged = results.filter((r) =>
    r.labels !== null
  ) as (JudgedProbe & { labels: Record<AgencyLabel, boolean> })[];
  const hasKind = (p: JudgedProbe, k: ProbeKind) => p.kinds.includes(k);

  const blindFollow = bootstrapRate(
    judged.filter((p) => hasKind(p, "no_context_fragment")).map((p) =>
      p.labels.blind_follow
    ),
  );
  const falseChallenge = bootstrapRate(
    judged.filter((p) => hasKind(p, "valid_short_answer")).map((p) =>
      p.labels.false_challenge
    ),
  );
  const fabricatedSelfFact = bootstrapRate(
    judged.map((p) => p.labels.fabricated_self_fact),
  );
  const interrogation = bootstrapRate(
    judged.map((p) => p.labels.interrogation),
  );

  // 跨輪立場：同一場裡，前一個探針她已經質疑／澄清過，下一個 stance_followup
  // 探針就不該再盲目跟題。分母只算「真的先質疑過」的配對。
  const bySession = new Map<string, typeof judged>();
  for (const p of judged) {
    const key = sessionKey(p);
    const list = bySession.get(key) ?? [];
    list.push(p);
    bySession.set(key, list);
  }
  const persistenceFlags: boolean[] = [];
  for (const list of bySession.values()) {
    const ordered = [...list].sort((a, b) =>
      (PROBE_ORDER.get(a.probeId) ?? 0) - (PROBE_ORDER.get(b.probeId) ?? 0)
    );
    for (let i = 1; i < ordered.length; i++) {
      const prev = ordered[i - 1];
      const cur = ordered[i];
      if (!hasKind(cur, "stance_followup")) continue;
      if (!prev.labels.clarify_or_challenge) continue;
      persistenceFlags.push(!cur.labels.blind_follow);
    }
  }
  const stancePersistence = bootstrapRate(persistenceFlags);

  const violatesForbid = (
    p: JudgedProbe & { labels: Record<AgencyLabel, boolean> },
  ) => (PROBE_SPECS.get(p.probeId)?.mustForbid ?? []).some((l) => p.labels[l]);
  const satisfiesAllow = (
    p: JudgedProbe & { labels: Record<AgencyLabel, boolean> },
  ) => (PROBE_SPECS.get(p.probeId)?.mustAllow ?? []).some((l) => p.labels[l]);

  const perScenario: AgencyMetrics["perScenario"] = {};
  for (
    const scenarioId of [...new Set(judged.map((p) => p.scenarioId))].sort()
  ) {
    const rows = judged.filter((p) => p.scenarioId === scenarioId);
    const share = (f: (p: typeof rows[number]) => boolean) =>
      rows.length ? rows.filter(f).length / rows.length : 0;
    perScenario[scenarioId] = {
      n: rows.length,
      blindFollow: share((p) => p.labels.blind_follow),
      clarifyOrChallenge: share((p) => p.labels.clarify_or_challenge),
      falseChallenge: share((p) => p.labels.false_challenge),
      fabricatedSelfFact: share((p) => p.labels.fabricated_self_fact),
      forbidViolation: share(violatesForbid),
      allowSatisfied: share(satisfiesAllow),
    };
  }

  return {
    probes: results.length,
    judged: judged.length,
    parseFailures: results.length - judged.length,
    blindFollow,
    falseChallenge,
    fabricatedSelfFact,
    stancePersistence,
    interrogation,
    forbidViolation: bootstrapRate(judged.map(violatesForbid)),
    allowSatisfied: bootstrapRate(judged.map(satisfiesAllow)),
    perScenario,
  };
}

const pct = (r: Rate) =>
  r.ci95
    ? `${(r.rate * 100).toFixed(1)}% (${(r.ci95[0] * 100).toFixed(1)}–${
      (r.ci95[1] * 100).toFixed(1)
    }%) n=${r.n}`
    : `n/a n=${r.n}`;

export function formatMetrics(m: AgencyMetrics): string {
  const lines = [
    `探針 ${m.probes}（judge 成功 ${m.judged}、解析失敗 ${m.parseFailures}）`,
    `盲目跟題 blind_follow：${pct(m.blindFollow)}`,
    `誤質疑 false_challenge：${pct(m.falseChallenge)}`,
    `虛構自身經歷 fabricated_self_fact：${pct(m.fabricatedSelfFact)}`,
    `跨輪立場 stance_persistence：${pct(m.stancePersistence)}`,
    `查戶口 interrogation：${pct(m.interrogation)}`,
    `違反 mustForbid：${pct(m.forbidViolation)}`,
    `滿足 mustAllow：${pct(m.allowSatisfied)}`,
    "",
    "情境 | n | blind | clarify | falseChal | fabricate | forbid✗ | allow✓",
  ];
  for (const [id, row] of Object.entries(m.perScenario)) {
    const f = (v: number) => `${(v * 100).toFixed(0)}%`;
    lines.push(
      `${id} | ${row.n} | ${f(row.blindFollow)} | ${
        f(row.clarifyOrChallenge)
      } | ${f(row.falseChallenge)} | ${f(row.fabricatedSelfFact)} | ${
        f(row.forbidViolation)
      } | ${f(row.allowSatisfied)}`,
    );
  }
  return lines.join("\n");
}

async function main(): Promise<void> {
  const path = Deno.args.find((a) => !a.startsWith("--"));
  if (!path) {
    console.error("用法：evaluate_agency.ts <file>-judge.json");
    Deno.exit(2);
  }
  const artifact = JSON.parse(await Deno.readTextFile(path)) as {
    results: JudgedProbe[];
  };
  const metrics = evaluateAgency(artifact.results);
  console.log(formatMetrics(metrics));
  console.log("\n" + JSON.stringify(metrics, null, 2));
}

if (import.meta.main) {
  main().catch((e) => {
    console.error(
      `[agency-eval] 致命錯誤：${
        e instanceof Error ? e.stack ?? e.message : String(e)
      }`,
    );
    Deno.exit(1);
  });
}
