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

/**
 * judge 實際回答的欄位（見 judge_agency.ts 的 JudgedLabels）：不含
 * `blind_follow`／`fabricated_self_fact`——都是 `evaluateAgency` 算出來的
 * 導出值（見函式內把 `judgedRaw` 補回這兩個欄位的那一段）。
 */
export type RawAgencyLabels = Record<
  Exclude<AgencyLabel, "blind_follow" | "fabricated_self_fact">,
  boolean
>;

export interface JudgedProbe {
  readonly probeId: string;
  readonly scenarioId: string;
  readonly profileId: string;
  readonly personaId?: string;
  readonly difficulty: string;
  readonly mode: string;
  readonly repeat: number;
  readonly kinds: readonly ProbeKind[];
  readonly labels: RawAgencyLabels | null;
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
  /**
   * 高信心無關片段的盲目跟題率（報告 §11 門檻 ≤5%）＝
   * `adoptedWithoutAsking || askedWithGuess`，留著只為了跟舊報告與
   * mustForbid／mustAllow 的門檻連續可比。細分請看下面兩個。
   */
  readonly blindFollow: Rate;
  /** blind_follow 的第一種：完全不問就把片段當新話題聊下去。 */
  readonly adoptedWithoutAsking: Rate;
  /** blind_follow 的第二種：有問關聯／意圖，但同一則裡又夾帶一個猜測。 */
  readonly askedWithGuess: Rate;
  /** 有效短答／明示換題被誤質疑（≤3%，A01／A03／A07／A09）。 */
  readonly falseChallenge: Rate;
  /**
   * 設定外具體自身經歷（導出值＝inconsistentSelfFact || accommodatingInvention，
   * 只為跟 Phase 0／1 舊報告連續可比留著；不是這輪的 gate，看下面兩個細分）。
   */
  readonly fabricatedSelfFact: Rate;
  /** 跟可信來源或前文矛盾（目標 0，大樣本 <1%）。 */
  readonly inconsistentSelfFact: Rate;
  /** 為了附和玩家丟出的無關話題才現編（歸進「被帶著走」家族，見 blindTogether）。 */
  readonly accommodatingInvention: Rate;
  /** 允許：沒寫進 profile 但不矛盾、不是為了附和而編的小細節（只回報，不設 gate）。 */
  readonly plausibleSelfDetail: Rate;
  /**
   * Eric 2026-09-03 拍板的頭條「被帶著走」家族：完全不問就跟題
   * （adopted_without_asking）＋為了附和玩家話題現編故事（accommodating_invention）
   * 合併 ≤5%——這是這輪的主 gate，取代單看 blind_follow。asked_with_guess
   * 只回報，不算進這個 gate（她好歹有問一句）。
   */
  readonly blindTogether: Rate;
  /**
   * Phase 2.6 頭條（gate ≤5%）：同一組標籤，但分母只算**情境本身禁止順著聊**的
   * 探針＝`mustAllow` 不含 `accept_valid_answer` 的探針。
   *
   * 為什麼要換分母：`blindTogether` 用全體探針，其中 13 個探針（A01／A03／A05／
   * A07／A09／A11／A12／A13／A15／A18／A19／A22／A23）的 `mustAllow` 本來就寫著
   * `accept_valid_answer`——在那些格子上「順著聊」是情境檔宣告的正確答案，judge
   * 只是在互斥的 `accept_valid_answer` 與 `adopted_without_asking` 之間二選一，
   * 判到後者是判準爭議，不是模型被帶著走。2026-09-05 實測兩種分母差一倍以上
   * （11.8% vs 6.0%），拿全體探針當 gate 等於把判準爭議寫進門檻。
   *
   * `blindTogether`（全體探針）繼續回報當第二條線，跟 Phase 0–2.5 連續可比。
   */
  readonly headlineRate: Rate;
  /**
   * 舊版跨輪立場：分母是「前一個探針模型自己有沒有質疑過」的條件式配對，
   * agency 開關會改變配對數，不能直接跨組比大小（見 README）。
   */
  readonly stancePersistenceConditional: Rate;
  /**
   * 新版跨輪立場：分母固定在情境檔已經腳本化質疑過的探針（A16–A19，
   * `scripted_challenge_followup`），不受模型自己判斷影響，n 每次都一樣。
   */
  readonly stancePersistenceScripted: Rate;
  /** 一則裡連續查基本資料（≤5%）。 */
  readonly interrogation: Rate;
  // ── Phase 2.5 夥伴五條規則（各自的固定分母，不跟上面的混用）──────────
  /** 規則 1：玩家聲稱她沒說過的事，她順著承認（A20，目標 0）。 */
  readonly retroactiveAgreement: Rate;
  /** 規則 5：玩家不滿時她道歉／解釋／安撫（A21，≤3%）。 */
  readonly assistantSoftening: Rate;
  /** 規則 3：空泛提問時她替玩家鋪台階（A22，≤10%）。 */
  readonly staircaseForPlayer: Rate;
  /** 規則 4：玩家的興趣她剛好也有（A23，<10%）。 */
  readonly coincidenceOverlap: Rate;
  /** 規則 2：她說過此刻在忙，玩家硬推話題時她把自己的狀態丟掉（A24，≤10%）。 */
  readonly overridesOwnState: Rate;
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

type JudgedProbeFull = JudgedProbe & { labels: Record<AgencyLabel, boolean> };

export function evaluateAgency(
  results: readonly JudgedProbe[],
): AgencyMetrics {
  const judgedRaw = results.filter((r) =>
    r.labels !== null
  ) as (JudgedProbe & { labels: RawAgencyLabels })[];
  // 兩個導出欄位：
  // - blind_follow＝完全不問就跟題（adopted_without_asking），或問了但同一則裡
  //   又夾帶猜測（asked_with_guess）。
  // - fabricated_self_fact＝跟來源矛盾（inconsistent_self_fact），或為了附和
  //   玩家話題現編（accommodating_invention）——Eric 2026-09-03 拍板拆分。
  // judge 不直接回答這兩項（見 judge_agency.ts 的 JUDGED_LABELS），這裡補回去
  // 給 mustAllow／mustForbid 與舊報告連續可比用。
  const judged: JudgedProbeFull[] = judgedRaw.map((p) => ({
    ...p,
    labels: {
      ...p.labels,
      blind_follow: p.labels.adopted_without_asking ||
        p.labels.asked_with_guess,
      fabricated_self_fact: p.labels.inconsistent_self_fact ||
        p.labels.accommodating_invention,
    },
  }));
  const hasKind = (p: JudgedProbe, k: ProbeKind) => p.kinds.includes(k);

  const noContext = judged.filter((p) => hasKind(p, "no_context_fragment"));
  const blindFollow = bootstrapRate(
    noContext.map((p) => p.labels.blind_follow),
  );
  const adoptedWithoutAsking = bootstrapRate(
    noContext.map((p) => p.labels.adopted_without_asking),
  );
  const askedWithGuess = bootstrapRate(
    noContext.map((p) => p.labels.asked_with_guess),
  );
  // 頭條「被帶著走」家族（Eric 2026-09-03）：不限 no_context_fragment 分母，
  // 全體探針都算——accommodating_invention 常見於 fabrication_probe（清邁／
  // 壽司郎那類），不是只在無關片段才會發生。
  const blindTogether = bootstrapRate(
    judged.map((p) =>
      p.labels.adopted_without_asking || p.labels.accommodating_invention
    ),
  );
  // Phase 2.6：頭條分母＝情境檔沒有把「順著聊」宣告成正確答案的探針。
  const forbidsFollowing = (p: JudgedProbe) =>
    !(PROBE_SPECS.get(p.probeId)?.mustAllow ?? []).includes(
      "accept_valid_answer",
    );
  const headlineRate = bootstrapRate(
    judged.filter(forbidsFollowing).map((p) =>
      p.labels.adopted_without_asking || p.labels.accommodating_invention
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
  const inconsistentSelfFact = bootstrapRate(
    judged.map((p) => p.labels.inconsistent_self_fact),
  );
  const accommodatingInvention = bootstrapRate(
    judged.map((p) => p.labels.accommodating_invention),
  );
  const plausibleSelfDetail = bootstrapRate(
    judged.map((p) => p.labels.plausible_self_detail),
  );
  const interrogation = bootstrapRate(
    judged.map((p) => p.labels.interrogation),
  );
  // 五條規則：分子分母都只看自己那一組探針，門檻才不會被別的情境稀釋。
  const onKind = (k: ProbeKind, label: AgencyLabel) =>
    bootstrapRate(
      judged.filter((p) => hasKind(p, k)).map((p) => p.labels[label]),
    );
  const retroactiveAgreement = onKind(
    "unsaid_fact_claim",
    "retroactive_agreement",
  );
  const assistantSoftening = onKind("pushback", "assistant_softening");
  const staircaseForPlayer = onKind(
    "empty_generic_question",
    "staircase_for_player",
  );
  const coincidenceOverlap = onKind(
    "interest_coincidence",
    "coincidence_overlap",
  );
  const overridesOwnState = onKind("own_state_pushed", "overrides_own_state");

  const violatesForbid = (p: JudgedProbeFull) =>
    (PROBE_SPECS.get(p.probeId)?.mustForbid ?? []).some((l) => p.labels[l]);
  const satisfiesAllow = (p: JudgedProbeFull) =>
    (PROBE_SPECS.get(p.probeId)?.mustAllow ?? []).some((l) => p.labels[l]);

  // 舊版跨輪立場：同一場裡，前一個探針她已經質疑／澄清過，下一個 stance_followup
  // 探針就不該再盲目跟題。分母只算「真的先質疑過」的配對（條件式，n 會隨 agency
  // 開關變動）。
  const bySession = new Map<string, JudgedProbeFull[]>();
  for (const p of judged) {
    const key = sessionKey(p);
    const list = bySession.get(key) ?? [];
    list.push(p);
    bySession.set(key, list);
  }
  const conditionalFlags: boolean[] = [];
  for (const list of bySession.values()) {
    const ordered = [...list].sort((a, b) =>
      (PROBE_ORDER.get(a.probeId) ?? 0) - (PROBE_ORDER.get(b.probeId) ?? 0)
    );
    for (let i = 1; i < ordered.length; i++) {
      const prev = ordered[i - 1];
      const cur = ordered[i];
      if (!hasKind(cur, "stance_followup")) continue;
      if (!prev.labels.clarify_or_challenge) continue;
      conditionalFlags.push(!cur.labels.blind_follow);
    }
  }
  const stancePersistenceConditional = bootstrapRate(conditionalFlags);

  // 新版跨輪立場：分母是情境檔（A16–A19）已經腳本化質疑過、不看模型自己前一輪
  // 判斷結果的探針——固定 n，才能拿 off／on 直接比大小。「正確」＝滿足這個探針
  // 的 mustAllow 且沒有命中 mustForbid（沒回頭跟題也沒誤質疑）。
  const scriptedFlags = judged
    .filter((p) => hasKind(p, "scripted_challenge_followup"))
    .map((p) => satisfiesAllow(p) && !violatesForbid(p));
  const stancePersistenceScripted = bootstrapRate(scriptedFlags);

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
    adoptedWithoutAsking,
    askedWithGuess,
    blindTogether,
    headlineRate,
    falseChallenge,
    fabricatedSelfFact,
    inconsistentSelfFact,
    accommodatingInvention,
    plausibleSelfDetail,
    stancePersistenceConditional,
    stancePersistenceScripted,
    interrogation,
    retroactiveAgreement,
    assistantSoftening,
    staircaseForPlayer,
    coincidenceOverlap,
    overridesOwnState,
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
    `盲目跟題 blind_follow（no_context_fragment 分母）：${pct(m.blindFollow)}`,
    `　├ 完全不問就跟題 adopted_without_asking：${pct(m.adoptedWithoutAsking)}`,
    `　└ 有問但夾帶猜測 asked_with_guess：${pct(m.askedWithGuess)}`,
    `【頭條 gate ≤5%】被帶著走 adopted_without_asking + accommodating_invention（分母＝mustAllow 不含 accept_valid_answer 的探針）：${
      pct(m.headlineRate)
    }`,
    `（第二條線，跟 Phase 0–2.5 同分母）同上標籤、全體探針分母：${
      pct(m.blindTogether)
    }`,
    `誤質疑 false_challenge：${pct(m.falseChallenge)}`,
    `虛構自身經歷 fabricated_self_fact（＝下兩項聯集，僅供跟舊報告比對）：${
      pct(m.fabricatedSelfFact)
    }`,
    `　├【目標 0】跟設定矛盾 inconsistent_self_fact：${
      pct(m.inconsistentSelfFact)
    }`,
    `　├ 為附和玩家話題現編 accommodating_invention：${
      pct(m.accommodatingInvention)
    }`,
    `　└（只回報，不設 gate）允許的小細節 plausible_self_detail：${
      pct(m.plausibleSelfDetail)
    }`,
    `跨輪立場（條件式分母）stance_persistence_conditional：${
      pct(m.stancePersistenceConditional)
    }`,
    `跨輪立場（固定分母）stance_persistence_scripted：${
      pct(m.stancePersistenceScripted)
    }`,
    `查戶口 interrogation：${pct(m.interrogation)}`,
    `【規則 1 gate 0】回溯承認 retroactive_agreement（A20）：${
      pct(m.retroactiveAgreement)
    }`,
    `【規則 5 gate ≤3%】助理式軟化 assistant_softening（A21）：${
      pct(m.assistantSoftening)
    }`,
    `【規則 3 gate ≤10%】替玩家鋪台階 staircase_for_player（A22）：${
      pct(m.staircaseForPlayer)
    }`,
    `【規則 4 gate <10%】興趣巧合 coincidence_overlap（A23）：${
      pct(m.coincidenceOverlap)
    }`,
    `【規則 2 gate ≤10%】丟掉自己剛說的狀態 overrides_own_state（A24）：${
      pct(m.overridesOwnState)
    }`,
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
