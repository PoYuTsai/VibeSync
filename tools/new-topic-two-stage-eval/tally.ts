// 盲測填完之後算規格 §6.5 驗收門檻（不打模型、不連網）。
//
// 讀 out/<tag>/ 的 blind_ab.md、blind_star.md、explanations_blind.md（Bruce 填好的）、reveal-map.json
// 與 records.json，寫出 acceptance.md。任何一格還是「＿」或格式不對就整個拒絕，不會把沒填的當通過。
// 用法：deno run --allow-read --allow-write tools/new-topic-two-stage-eval/tally.ts --tag=<tag>

import {
  type Arm,
  BLIND_FIELDS,
  type EvalRecord,
  mechanicalAcceptance,
  metricsByArm,
} from "./run.ts";

type BlindKey = keyof typeof BLIND_FIELDS;
type PairValue = { 甲: string; 乙: string };
export type BlindAnswers = Map<
  string,
  Partial<Record<BlindKey, PairValue | string>>
>;

const PAIR_KEYS = new Set<BlindKey>([
  "willingToSend",
  "awkward",
  "fabricated",
  "starSend",
  "starAwkward",
  "fun",
  "titleTopic",
  "reasonUseful",
  "predictsHer",
  "mixedEnglish",
]);

/** 解析一份盲測檔：每個「## 代碼」段落裡，照 BLIND_FIELDS 的前綴取答案。 */
export function parseBlind(markdown: string): BlindAnswers {
  const answers: BlindAnswers = new Map();
  let code: string | null = null;
  for (const line of markdown.split("\n")) {
    const heading = /^## (\S+#\d+)\s*$/.exec(line);
    if (heading) {
      code = heading[1];
      answers.set(code, {});
      continue;
    }
    if (code === null) continue;
    for (
      const [key, prefix] of Object.entries(BLIND_FIELDS) as [
        BlindKey,
        string,
      ][]
    ) {
      if (!line.startsWith(prefix)) continue;
      const value = line.slice(prefix.length).trim();
      if (PAIR_KEYS.has(key)) {
        const m = /^甲\s*(\S+?)\s*；\s*乙\s*(\S+?)\s*$/.exec(value);
        if (!m) {
          throw new Error(`${code} 的「${prefix.trim()}」格式不對：${value}`);
        }
        answers.get(code)![key] = { 甲: m[1], 乙: m[2] };
      } else {
        answers.get(code)![key] = value;
      }
    }
  }
  return answers;
}

function count(code: string, label: string, raw: string, max?: number): number {
  if (!/^\d+$/.test(raw) || (max !== undefined && Number(raw) > max)) {
    throw new Error(
      `${code} 的「${label}」要填 0${
        max === undefined ? " 以上" : `–${max}`
      } 的整數：${raw}`,
    );
  }
  return Number(raw);
}

function yes(code: string, label: string, raw: string): boolean {
  if (raw !== "是" && raw !== "否") {
    throw new Error(`${code} 的「${label}」要填 是 或 否：${raw}`);
  }
  return raw === "是";
}

export type ArmTotals = {
  pairs: number;
  willingToSend: number;
  awkward: number;
  fabricated: number;
  starSend: number;
  starAwkward: number;
  /** 有一次 ★ 尷尬的案例（同案例兩次算一組）。 */
  starAwkwardCases: string[];
  fun: number;
  /** 這一臂在哪些案例有一次以上「不有趣」。 */
  notFunCases: string[];
  favorite: number;
  starBetter: number;
  titleTopic: number;
  reasonUseful: number;
  predictsHer: number;
  mixedEnglish: number;
};

function emptyTotals(): ArmTotals {
  return {
    pairs: 0,
    willingToSend: 0,
    awkward: 0,
    fabricated: 0,
    starSend: 0,
    starAwkward: 0,
    starAwkwardCases: [],
    fun: 0,
    notFunCases: [],
    favorite: 0,
    starBetter: 0,
    titleTopic: 0,
    reasonUseful: 0,
    predictsHer: 0,
    mixedEnglish: 0,
  };
}

/** 把三份盲測與解盲表合成每臂總計；缺任何一格就拒絕。 */
export function tally(input: {
  ab: string;
  star: string;
  explanations: string;
  reveal: Record<string, { 甲: Arm; 乙: Arm }>;
}): Record<Arm, ArmTotals> {
  const ab = parseBlind(input.ab);
  const star = parseBlind(input.star);
  const explanations = parseBlind(input.explanations);
  const totals = { base: emptyTotals(), cand: emptyTotals() };
  for (const [code, arms] of Object.entries(input.reveal)) {
    const a = ab.get(code), s = star.get(code), e = explanations.get(code);
    if (!a || !s || !e) throw new Error(`${code} 在盲測檔裡找不到`);
    const caseId = code.split("#")[0];
    const need = (answers: typeof a, key: BlindKey) => {
      const value = answers[key];
      const missing = value === undefined ||
        (typeof value === "string"
          ? value.includes("＿")
          : value.甲.includes("＿") || value.乙.includes("＿"));
      if (missing) {
        throw new Error(`${code} 的「${BLIND_FIELDS[key].trim()}」還沒填`);
      }
      return value!;
    };
    for (const name of ["甲", "乙"] as const) {
      const t = totals[arms[name]];
      const pair = (answers: typeof a, key: BlindKey) =>
        (need(answers, key) as PairValue)[name];
      t.pairs++;
      t.willingToSend += count(code, "願意直接傳", pair(a, "willingToSend"), 5);
      t.awkward += count(code, "尷尬句數", pair(a, "awkward"), 5);
      t.fabricated += count(code, "捏造或越界句數", pair(a, "fabricated"), 5);
      if (yes(code, "★ 會直接傳", pair(a, "starSend"))) t.starSend++;
      if (yes(code, "★ 尷尬", pair(a, "starAwkward"))) {
        t.starAwkward++;
        if (!t.starAwkwardCases.includes(caseId)) {
          t.starAwkwardCases.push(caseId);
        }
      }
      if (yes(code, "有趣或有個性", pair(a, "fun"))) t.fun++;
      else if (!t.notFunCases.includes(caseId)) t.notFunCases.push(caseId);
      if (yes(code, "標題在說聊什麼", pair(e, "titleTopic"))) t.titleTopic++;
      if (yes(code, "理由說得出她可以回什麼", pair(e, "reasonUseful"))) {
        t.reasonUseful++;
      }
      t.predictsHer += count(code, "預告她會怎樣", pair(e, "predictsHer"));
      t.mixedEnglish += count(code, "中英夾雜", pair(e, "mixedEnglish"));
    }
    const favorite = need(a, "favorite") as string;
    const fav = /^(甲|乙)[1-5]$/.exec(favorite);
    if (!fav) throw new Error(`${code} 的「最想傳」要填像「乙3」：${favorite}`);
    totals[arms[fav[1] as "甲" | "乙"]].favorite++;
    const better = need(s, "starBetter") as string;
    if (better === "甲" || better === "乙") totals[arms[better]].starBetter++;
    else if (better !== "差不多") {
      throw new Error(
        `${code} 的「Free 那句哪個好」要填 甲、乙 或 差不多：${better}`,
      );
    }
  }
  return totals;
}

/** 有互虧依據、規格要求候選一定要「有趣」的案例。 */
export const MUST_BE_FUN = ["B3", "J1", "E3"] as const;

export function acceptanceMarkdown(input: {
  tag: string;
  totals: Record<Arm, ArmTotals>;
  records: EvalRecord[];
}): string {
  const { base, cand } = input.totals;
  const acc = mechanicalAcceptance(metricsByArm(input.records));
  const mark = (pass: boolean | null) =>
    pass === null ? "未評估" : pass ? "✓" : "✗";
  const funMissing = MUST_BE_FUN.filter((id) => cand.notFunCases.includes(id));
  const rows: Array<[string, boolean | null, string]> = [
    [
      "1. 候選 0 件捏造／越界（盲測計數；另要逐筆看 records 確認）",
      cand.fabricated === 0,
      `候選 ${cand.fabricated}、基準 ${base.fabricated}`,
    ],
    [
      "2a. 尷尬句總數：候選 ≤ 基準的一半",
      cand.awkward <= base.awkward / 2,
      `候選 ${cand.awkward}、基準 ${base.awkward}`,
    ],
    [
      "2b. ★ 尷尬：候選 ≤ 基準，且至多 1 個案例",
      cand.starAwkward <= base.starAwkward && cand.starAwkwardCases.length <= 1,
      `候選 ${cand.starAwkward}（案例：${
        cand.starAwkwardCases.join("、") || "無"
      }）、基準 ${base.starAwkward}`,
    ],
    [
      "3a. 願意直接傳總數：候選 ≥ 基準",
      cand.willingToSend >= base.willingToSend,
      `候選 ${cand.willingToSend}、基準 ${base.willingToSend}`,
    ],
    [
      "3b. ★ 會直接傳的組數：候選 ≥ 基準",
      cand.starSend >= base.starSend,
      `候選 ${cand.starSend}、基準 ${base.starSend}`,
    ],
    [
      "4a. 有趣／有個性的組數：候選 ≥ 基準的八成",
      cand.fun >= base.fun * 0.8,
      `候選 ${cand.fun}、基準 ${base.fun}`,
    ],
    [
      "4b. B3、J1、E3 候選每次都「有趣」",
      funMissing.length === 0,
      funMissing.length === 0 ? "都是" : `沒做到：${funMissing.join("、")}`,
    ],
    [
      "5a. 可交付率：候選 ≥ 基準",
      acc.deliverableRate.pass,
      `候選 ${acc.deliverableRate.cand}、基準 ${acc.deliverableRate.base}`,
    ],
    [
      "5b. 一則兩個以上問句：候選 0",
      acc.multiQuestionLines.pass,
      `候選 ${acc.multiQuestionLines.cand}`,
    ],
    [
      "5c. 四種尷尬句型合計：候選 < 基準",
      acc.awkwardPatternLines.pass,
      `候選 ${acc.awkwardPatternLines.cand}、基準 ${acc.awkwardPatternLines.base}`,
    ],
    [
      "5d. 近似重句：候選 ≤ 基準 × 1.5",
      acc.nearDuplicatePairs.pass,
      `候選 ${acc.nearDuplicatePairs.cand}、基準 ${acc.nearDuplicatePairs.base}`,
    ],
    [
      "5e. 超過 35 字：候選 ≤ 基準",
      acc.over35.pass,
      `候選 ${acc.over35.cand}、基準 ${acc.over35.base}`,
    ],
    [
      "6a. ★ 標題手法字：候選 0（命中要人工確認）",
      acc.starTitleTechnique.pass,
      `候選 ${acc.starTitleTechnique.cand}`,
    ],
    [
      "6b. ★ 解釋夾英文：候選 0（命中要人工確認）",
      acc.starExplanationEnglish.pass,
      `候選 ${acc.starExplanationEnglish.cand}`,
    ],
  ];
  const allPass = rows.every(([, pass]) => pass === true);
  return [
    `# 新話題驗收（規格 §6.5）· ${input.tag}`,
    "",
    `整體：${
      allPass ? "全部通過" : "有未通過或未評估的項目"
    }。第 1 項另要逐筆看 records.json 確認沒有捏造或越界。`,
    "",
    "| 門檻 | 結果 | 數字 |",
    "|---|---|---|",
    ...rows.map(([label, pass, detail]) =>
      `| ${label} | ${mark(pass)} | ${detail} |`
    ),
    "",
    "## 參考（不判過關）",
    "",
    "| 項目 | 基準 | 候選 |",
    "|---|---|---|",
    `| 組數 | ${base.pairs} | ${cand.pairs} |`,
    `| 十句裡最想傳 | ${base.favorite} | ${cand.favorite} |`,
    `| Free 那句比較好 | ${base.starBetter} | ${cand.starBetter} |`,
    `| ★ 標題在說聊什麼 | ${base.titleTopic} | ${cand.titleTopic} |`,
    `| ★ 理由說得出她可以回什麼 | ${base.reasonUseful} | ${cand.reasonUseful} |`,
    `| ★ 預告她會怎樣（處） | ${base.predictsHer} | ${cand.predictsHer} |`,
    `| ★ 中英夾雜（處） | ${base.mixedEnglish} | ${cand.mixedEnglish} |`,
    "",
  ].join("\n");
}

async function main(args: string[]): Promise<void> {
  const tag = /^--tag=([A-Za-z0-9][A-Za-z0-9_-]{0,79})$/.exec(args[0] ?? "")
    ?.[1];
  if (!tag || args.length !== 1) {
    throw new Error("用法：tally.ts --tag=<tag>");
  }
  const out = new URL(`./out/${tag}/`, import.meta.url);
  const read = (name: string) => Deno.readTextFile(new URL(name, out));
  const totals = tally({
    ab: await read("blind_ab.md"),
    star: await read("blind_star.md"),
    explanations: await read("explanations_blind.md"),
    reveal: JSON.parse(await read("reveal-map.json")),
  });
  const records = JSON.parse(await read("records.json")) as EvalRecord[];
  const markdown = acceptanceMarkdown({ tag, totals, records });
  await Deno.writeTextFile(new URL("acceptance.md", out), markdown);
  console.log(markdown);
}

if (import.meta.main) await main(Deno.args);
