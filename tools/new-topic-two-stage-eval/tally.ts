// 盲測填完之後算規格 §6.5 驗收門檻（不打模型、不連網）。
//
// 讀 out/<tag>/ 的 blind.md（Bruce 填好的）、reveal-map.json、records.json 與 manifest.json，寫出 acceptance.md。
// - 逐句勾「會傳／尷尬／不實」，每版勾有沒有一句有趣，每組填最想傳哪句或都不要，再勾「這組評完了」。
// - 沒勾「這組評完了」的組是「未評」：不計分，也不當成「沒有」。評完的組裡，沒勾＝沒有。
// - 推薦句（★）的會傳、尷尬從逐句勾選算，位置取 records 裡用戶看到的推薦（表上不標）。
// - 方框或「最想傳」看不懂、勾了評完卻沒填最想傳，就整個拒絕，不會猜。
// - 盲測表、解盲表、records、manifest 要一起對得上完整的 22 組 × 2 次 × 兩臂，每組都評完，表上的句子也要跟
//   records 一樣；有任何一項不符，報告都標「未完成」，不能當正式驗收，指令也以失敗結束。
// 用法：deno run --allow-read --allow-write tools/new-topic-two-stage-eval/tally.ts --tag=<tag>

import {
  acceptanceMark,
  type Arm,
  ARMS,
  BLIND_FORM,
  blindLineText,
  catalogSha256,
  type EvalRecord,
  expectedCodes,
  expectedKeys,
  FORMAL_REPEAT,
  listSome,
  mechanicalAcceptance,
  metricsByArm,
  recordProblems,
  setProblems,
} from "./run.ts";

export type Version = "甲" | "乙";
const VERSIONS = ["甲", "乙"] as const;
export type Reveal = Record<string, Record<Version, Arm>>;

export type BlindSentence = {
  willing: boolean;
  awkward: boolean;
  untrue: boolean;
  text: string;
};
export type BlindVersion = {
  sentences: BlindSentence[];
  /** null＝表上沒有這一格（這一版沒有可用的五題，或那一行不見了）。 */
  fun: boolean | null;
};
export type BlindGroup = Record<Version, BlindVersion> & {
  /** 「乙3」這種代號、「都不要」，或 null（還沒填）。 */
  favorite: string | null;
  done: boolean;
};

const BLIND_HEADING = /^## (\S+#\d+)\s*$/;
const VERSION_HEADING = /^### (甲|乙)\s*$/;
const BOX = String.raw`[\[［]([^\]］]*)[\]］]`;
const SENTENCE_LINE = new RegExp(
  String
    .raw`^-\s*(甲|乙)\s*([1-5])\s*${BOX}\s*${BLIND_FORM.willing}\s*${BOX}\s*${BLIND_FORM.awkward}\s*${BOX}\s*${BLIND_FORM.untrue}\s*｜(.*)$`,
  "u",
);
const LOOKS_LIKE_SENTENCE = /^-\s*(甲|乙)\s*[1-5]/u;
const FUN_LINE = new RegExp(
  String.raw`^-\s*${BOX}\s*(甲|乙)\s*${BLIND_FORM.fun}\s*$`,
  "u",
);
const DONE_LINE = new RegExp(String.raw`^-\s*${BOX}\s*${BLIND_FORM.done}`, "u");
const CHECKED = /^[xXvVｘＸｖＶ✓✔√]$/u;

/** 方框：空白＝沒勾；x、v、✓ 之類＝有勾；其他看不懂就拒絕。 */
function box(where: string, raw: string): boolean {
  const value = raw.trim();
  if (value === "") return false;
  if (CHECKED.test(value)) return true;
  throw new Error(
    `${where}的方框看不懂：「[${raw}]」。有就填 [x]，沒有就留 [ ]`,
  );
}

function favoriteValue(code: string, raw: string): string | null {
  const value = raw.replace(/[\s＿]/g, "").replace(
    /[０-９]/g,
    (d) => String.fromCharCode(d.charCodeAt(0) - 0xfee0),
  );
  if (value === "") return null;
  if (value === BLIND_FORM.favoriteNone || /^(甲|乙)[1-5]$/.test(value)) {
    return value;
  }
  throw new Error(
    `${code} 的「十句裡最想傳」要填像「乙3」的代號，或「${BLIND_FORM.favoriteNone}」：${raw.trim()}`,
  );
}

/** 盲測表裡所有組別代碼（照出現順序，重複的也列出來）。 */
export function blindCodes(markdown: string): string[] {
  return markdown.split("\n").flatMap((line) => {
    const heading = BLIND_HEADING.exec(line);
    return heading ? [heading[1]] : [];
  });
}

function emptyVersion(): BlindVersion {
  return { sentences: [], fun: null };
}

/** 解析填好的盲測表；格式看不懂就拒絕（對象資料的程式碼區塊不看）。 */
export function parseBlind(markdown: string): Map<string, BlindGroup> {
  const groups = new Map<string, BlindGroup>();
  let code: string | null = null;
  let version: Version | null = null;
  let fenced = false;
  for (const line of markdown.split("\n")) {
    if (line.startsWith("```")) {
      fenced = !fenced;
      continue;
    }
    if (fenced) continue;
    const heading = BLIND_HEADING.exec(line);
    if (heading) {
      code = heading[1];
      version = null;
      groups.set(code, {
        甲: emptyVersion(),
        乙: emptyVersion(),
        favorite: null,
        done: false,
      });
      continue;
    }
    if (code === null) continue;
    const group = groups.get(code)!;
    const versionHeading = VERSION_HEADING.exec(line);
    if (versionHeading) {
      version = versionHeading[1] as Version;
      continue;
    }
    const sentence = SENTENCE_LINE.exec(line);
    if (sentence) {
      const name = sentence[1] as Version;
      const where = `${code} 的${name}${sentence[2]}`;
      const sentences = group[name].sentences;
      if (name !== version || Number(sentence[2]) !== sentences.length + 1) {
        throw new Error(
          `${where}位置不對（要在「### ${name}」底下，照 1 到 5 的順序）`,
        );
      }
      sentences.push({
        willing: box(where, sentence[3]),
        awkward: box(where, sentence[4]),
        untrue: box(where, sentence[5]),
        text: sentence[6].trim(),
      });
      continue;
    }
    if (LOOKS_LIKE_SENTENCE.test(line)) {
      throw new Error(
        `${code} 這一行格式不對（方框或「｜」被改到了）：${line}`,
      );
    }
    if (line.includes(BLIND_FORM.fun)) {
      const fun = FUN_LINE.exec(line);
      if (!fun || fun[2] !== version || group[version].fun !== null) {
        throw new Error(`${code} 這一行格式或位置不對：${line}`);
      }
      group[version].fun = box(
        `${code} 的「${version}${BLIND_FORM.fun}」`,
        fun[1],
      );
      continue;
    }
    if (line.startsWith(BLIND_FORM.favorite)) {
      group.favorite = favoriteValue(
        code,
        line.slice(BLIND_FORM.favorite.length),
      );
      continue;
    }
    if (line.includes(BLIND_FORM.done)) {
      const done = DONE_LINE.exec(line);
      if (!done) throw new Error(`${code} 這一行格式不對：${line}`);
      group.done = box(`${code} 的「${BLIND_FORM.done}」`, done[1]);
    }
  }
  return groups;
}

export type ArmTotals = {
  /** 評了幾版（一組兩版各算一次；沒有可用五題的那一版也算，句子 0）。 */
  versions: number;
  sentences: number;
  willing: number;
  awkward: number;
  untrue: number;
  /** 被勾「不實」的句子，解盲後逐句對照輸入。 */
  untrueLines: string[];
  starWilling: number;
  starAwkward: number;
  /** ★ 尷尬的情境（同情境兩次任一次算，只算一個）。 */
  starAwkwardCases: string[];
  fun: number;
  /** 每組（代碼）這一臂有沒有一句有趣。 */
  funByCode: Record<string, boolean>;
  favorite: number;
};

export type Scope = "all" | "basic" | "advanced";
const SCOPES: readonly Scope[] = ["all", "basic", "advanced"];

export type TallyResult = {
  totals: Record<Scope, Record<Arm, ArmTotals>>;
  /** 有計分的組（評完，句子也跟 records 一樣）。 */
  rated: string[];
  /** 表上有、但沒勾「這組評完了」的組（未評，不計分）。 */
  unrated: string[];
  /** 十句都不想傳的組數。 */
  favoriteNone: number;
  /** 表上的句子跟 records 不一樣的版本（這些組不計分）。 */
  mismatches: string[];
};

function emptyTotals(): ArmTotals {
  return {
    versions: 0,
    sentences: 0,
    willing: 0,
    awkward: 0,
    untrue: 0,
    untrueLines: [],
    starWilling: 0,
    starAwkward: 0,
    starAwkwardCases: [],
    fun: 0,
    funByCode: {},
    favorite: 0,
  };
}

/**
 * 把填好的盲測表照解盲表與 records 加總成每臂（全部／基本／進階）。表上沒有的組跳過不算，由
 * completenessProblems 列成「未完成」。
 */
export function tally(input: {
  form: string;
  reveal: Reveal;
  records: EvalRecord[];
}): TallyResult {
  const groups = parseBlind(input.form);
  const totals = Object.fromEntries(
    SCOPES.map((
      scope,
    ) => [scope, { base: emptyTotals(), cand: emptyTotals() }]),
  ) as TallyResult["totals"];
  const result: TallyResult = {
    totals,
    rated: [],
    unrated: [],
    favoriteNone: 0,
    mismatches: [],
  };
  for (const [code, arms] of Object.entries(input.reveal)) {
    const group = groups.get(code);
    if (!group) continue;
    const [caseId, attempt] = code.split("#");
    const versions = VERSIONS.map((name) => {
      const record = input.records.find((r) =>
        r.caseId === caseId && r.attempt === Number(attempt) &&
        r.arm === arms[name]
      );
      const ins = record?.inspection;
      const evaluable = ins?.openingsEvaluable === true && ins.topics !== null;
      return {
        name,
        arm: arms[name],
        record,
        // 用戶看到的推薦（紅燈收尾已改推第一題的，取改推後的）。
        starIndex: evaluable ? ins!.recommendationIndex : null,
        expected: evaluable
          ? ins!.topics!.map((t) => blindLineText(t.openingLine))
          : [],
        marks: group[name],
      };
    });
    const mismatched = versions.filter((v) =>
      !v.record ||
      JSON.stringify(v.marks.sentences.map((s) => s.text)) !==
        JSON.stringify(v.expected)
    );
    result.mismatches.push(...mismatched.map((v) => `${code} ${v.name}`));
    if (!group.done) {
      result.unrated.push(code);
      continue;
    }
    if (mismatched.length) continue;
    for (const v of versions) {
      if (v.expected.length && v.marks.fun === null) {
        throw new Error(`${code} 少了「${v.name}${BLIND_FORM.fun}」那一行`);
      }
    }
    const favorite = group.favorite;
    if (favorite === null) {
      throw new Error(
        `${code} 勾了「${BLIND_FORM.done}」，但「十句裡最想傳」還沒填`,
      );
    }
    if (favorite !== BLIND_FORM.favoriteNone) {
      const name = favorite[0] as Version, n = Number(favorite.slice(1));
      if (n > group[name].sentences.length) {
        throw new Error(
          `${code} 的「十句裡最想傳」填了 ${favorite}，但${name}沒有第 ${n} 句`,
        );
      }
    }
    result.rated.push(code);
    const scopes: Scope[] = ["all", versions[0].record!.mode];
    for (const v of versions) {
      for (const scope of scopes) {
        const t = totals[scope][v.arm];
        t.versions++;
        t.sentences += v.marks.sentences.length;
        v.marks.sentences.forEach((s, i) => {
          if (s.willing) t.willing++;
          if (s.awkward) t.awkward++;
          if (s.untrue) {
            t.untrue++;
            t.untrueLines.push(`${code} ${v.name}${i + 1}：${s.text}`);
          }
        });
        const star = v.starIndex === null
          ? undefined
          : v.marks.sentences[v.starIndex];
        if (star?.willing) t.starWilling++;
        if (star?.awkward) {
          t.starAwkward++;
          if (!t.starAwkwardCases.includes(caseId)) {
            t.starAwkwardCases.push(caseId);
          }
        }
        const fun = v.marks.fun === true;
        if (fun) t.fun++;
        t.funByCode[code] = fun;
      }
    }
    if (favorite === BLIND_FORM.favoriteNone) {
      result.favoriteNone++;
    } else {
      for (const scope of scopes) {
        totals[scope][arms[favorite[0] as Version]].favorite++;
      }
    }
  }
  return result;
}

/** 有互虧依據、規格要求候選一定要「有趣」的案例。 */
export const MUST_BE_FUN = ["B3", "J1", "E3"] as const;

/**
 * 正式驗收的完整度：manifest、records、解盲表與盲測表要一起對得上完整的 22 組 × 2 次 × 兩臂，每組都評完，
 * 表上的句子也跟 records 一樣。回傳問題清單；空的才算完整。
 */
export function completenessProblems(input: {
  manifest: unknown;
  casesSha256: string;
  records: EvalRecord[];
  reveal: Reveal;
  form: string;
  result: Pick<TallyResult, "unrated" | "mismatches">;
}): string[] {
  const problems: string[] = [];
  const m = input.manifest as {
    status?: unknown;
    candidateDirty?: unknown;
    modelCallsMade?: unknown;
    comparison?: unknown;
    sha256?: { cases?: unknown };
    options?: {
      repeat?: unknown;
      only?: unknown;
      arms?: unknown;
      compare?: unknown;
    };
  } | null;
  if (typeof m !== "object" || m === null) {
    problems.push("manifest.json 格式不對");
  } else {
    // 模型對照（同一份提示詞換模型）是小型診斷，不能當改前改後的 §6.5 驗收。
    if (m.comparison === "model" || m.options?.compare === "model") {
      problems.push("這是模型對照（--compare=model），不是 §6.5 驗收");
    }
    if (m.status !== "FINISHED_QUALITY_UNREVIEWED") {
      problems.push(`評測沒有跑完（manifest status＝${String(m.status)}）`);
    }
    if (m.options?.repeat !== FORMAL_REPEAT) {
      problems.push(
        `每組跑了 ${
          String(m.options?.repeat)
        } 次，正式驗收要 ${FORMAL_REPEAT} 次`,
      );
    }
    if (m.options?.only !== null) {
      problems.push(`只跑了部分案例（--only=${String(m.options?.only)}）`);
    }
    if (JSON.stringify(m.options?.arms) !== JSON.stringify(ARMS)) {
      problems.push(`只跑了 ${String(m.options?.arms)} 臂，正式驗收要兩臂`);
    }
    if (m.sha256?.cases !== input.casesSha256) {
      problems.push("案例檔跟評測當時不同（cases.json 的 sha256 對不上）");
    }
    if (m.candidateDirty !== false) {
      problems.push("評測時工作樹有未提交修改，結果對不回工程版本");
    }
    if (m.modelCallsMade !== expectedKeys().length) {
      problems.push(
        `模型呼叫 ${
          String(m.modelCallsMade)
        } 次，正式驗收要 ${expectedKeys().length} 次`,
      );
    }
  }
  problems.push(...recordProblems(input.records));
  const codes = expectedCodes();
  problems.push(
    ...setProblems("解盲表的組別", Object.keys(input.reveal), codes),
  );
  const badReveal = Object.entries(input.reveal).filter(([, arms]) =>
    !(
      (arms.甲 === "base" && arms.乙 === "cand") ||
      (arms.甲 === "cand" && arms.乙 === "base")
    )
  ).map(([code]) => code);
  if (badReveal.length) {
    problems.push(
      `解盲表的甲乙不是一邊基準、一邊候選：${badReveal.join("、")}`,
    );
  }
  problems.push(
    ...setProblems("blind.md 的組別", blindCodes(input.form), codes),
  );
  const { unrated, mismatches } = input.result;
  if (unrated.length) {
    problems.push(
      `未評（沒勾「${BLIND_FORM.done}」）${unrated.length} 組：${
        listSome(unrated)
      }`,
    );
  }
  if (mismatches.length) {
    problems.push(
      `表上的句子跟 records 不一樣（這些組不計分）${mismatches.length} 處：${
        listSome(mismatches)
      }`,
    );
  }
  return problems;
}

/** true＝過、false＝沒過、null＝沒有資料可判、"explain"＝不判失敗但要交代。 */
type RowState = boolean | null | "explain";

export function acceptanceMarkdown(input: {
  tag: string;
  result: TallyResult;
  records: EvalRecord[];
  /** completenessProblems 的結果；有任何一項，整份報告都是「未完成」。 */
  problems: string[];
}): string {
  const { totals } = input.result;
  const base = totals.all.base, cand = totals.all.cand;
  const metrics = metricsByArm(input.records);
  const acc = mechanicalAcceptance(metrics);
  const complete = input.problems.length === 0;
  const mark = (state: RowState) =>
    !complete
      ? "未完成"
      : state === "explain"
      ? "需交代"
      : acceptanceMark(state, true);
  const situations =
    new Set(input.result.rated.map((code) => code.split("#")[0])).size;
  // B3、J1、E3 每一次都要有候選的評分，而且有一句有趣；缺一組也不算過。
  const mustBeFun = MUST_BE_FUN.flatMap((id) =>
    Array.from({ length: FORMAL_REPEAT }, (_, i) => `${id}#${i + 1}`)
  );
  const funMissing = mustBeFun.filter((code) =>
    !Object.hasOwn(cand.funByCode, code)
  );
  const funFailed = mustBeFun.filter((code) => cand.funByCode[code] === false);
  // 會傳與 ★ 會傳：基本、進階分開看，任一邊退步都要交代（不能用另一邊的進步蓋過去）。
  const regressions = (["basic", "advanced"] as const).flatMap((scope) => {
    const label = scope === "basic" ? "基本" : "進階";
    const { base: b, cand: c } = totals[scope];
    return [
      ...(c.willing < b.willing
        ? [`${label}會傳句數 候選 ${c.willing} < 基準 ${b.willing}`]
        : []),
      ...(c.starWilling < b.starWilling
        ? [`${label} ★ 會傳 候選 ${c.starWilling} < 基準 ${b.starWilling}`]
        : []),
    ];
  });
  const split = (pick: (t: ArmTotals) => number) =>
    `基本 候選 ${pick(totals.basic.cand)}、基準 ${
      pick(totals.basic.base)
    }；進階 候選 ${pick(totals.advanced.cand)}、基準 ${
      pick(totals.advanced.base)
    }`;
  const rows: Array<[string, RowState, string]> = [
    [
      "1. 不實（捏造、主詞弄反、越界）：候選 0 句（下面逐句列出，要對照輸入確認）",
      cand.untrue === 0,
      `候選 ${cand.untrue}、基準 ${base.untrue}`,
    ],
    [
      "2a. 尷尬句數：候選 ≤ 基準的一半",
      cand.awkward <= base.awkward / 2,
      `候選 ${cand.awkward}／${cand.sentences} 句、基準 ${base.awkward}／${base.sentences} 句`,
    ],
    [
      "2b. ★ 尷尬：候選次數 ≤ 基準，且至多 1 個情境（同情境兩次任一次算）",
      cand.starAwkward <= base.starAwkward && cand.starAwkwardCases.length <= 1,
      `候選 ${cand.starAwkward}／${cand.versions} 次、${cand.starAwkwardCases.length}／${situations} 個情境（${
        cand.starAwkwardCases.join("、") || "無"
      }）；基準 ${base.starAwkward}／${base.versions} 次、${base.starAwkwardCases.length}／${situations} 個情境`,
    ],
    [
      "3a. 會傳句數：候選 ≥ 基準",
      cand.willing >= base.willing,
      `候選 ${cand.willing}、基準 ${base.willing}（${
        split((t) => t.willing)
      }）`,
    ],
    [
      "3b. ★ 會傳次數：候選 ≥ 基準",
      cand.starWilling >= base.starWilling,
      `候選 ${cand.starWilling}／${cand.versions}、基準 ${base.starWilling}／${base.versions}（${
        split((t) => t.starWilling)
      }）`,
    ],
    [
      "3c. 3a、3b 基本與進階分開看：任一邊退步要交代",
      regressions.length === 0 ? true : "explain",
      regressions.join("；") || "都沒有退步",
    ],
    [
      "4a. 有一句有趣的版本數：候選 ≥ 基準的八成",
      cand.fun >= base.fun * 0.8,
      `候選 ${cand.fun}／${cand.versions}、基準 ${base.fun}／${base.versions}`,
    ],
    [
      "4b. B3、J1、E3 候選每次都有一句有趣",
      funMissing.length === 0 && funFailed.length === 0,
      funMissing.length === 0 && funFailed.length === 0 ? "都有" : [
        funFailed.length ? `沒有：${funFailed.join("、")}` : "",
        funMissing.length ? `沒有評分：${funMissing.join("、")}` : "",
      ].filter(Boolean).join("；"),
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
      "5c. 四種尷尬句型合計：候選 < 基準（基準已是 0 時候選也要 0）",
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
  const allPass = complete && rows.every(([, state]) => state === true);
  const ref = (
    label: string,
    pick: (t: ArmTotals) => string | number,
  ) =>
    `| ${label} | ${
      SCOPES.flatMap((scope) => ARMS.map((arm) => pick(totals[scope][arm])))
        .join(" | ")
    } |`;
  const iNoReply = SCOPES.flatMap((scope) =>
    ARMS.map((arm) => metrics[arm][scope].iNoReplyExplainLines)
  ).join(" | ");
  return [
    `# 新話題驗收（規格 §6.5）· ${input.tag}`,
    "",
    complete
      ? `整體：${
        allPass ? "全部通過" : "有未通過、未評估或需交代的項目"
      }。第 1 項另要逐句對照輸入確認；★ 解釋的人工評分這輪暫緩（未評，不算通過也不算失敗）。`
      : "整體：**未完成**——資料不完整，不能當正式驗收。下面的數字只算有計分的組，每一項都標「未完成」。",
    "",
    ...(complete ? [] : [
      "## 資料不完整",
      "",
      ...input.problems.map((problem) => `- ${problem}`),
      "",
    ]),
    "| 門檻 | 結果 | 數字 |",
    "|---|---|---|",
    ...rows.map(([label, state, detail]) =>
      `| ${label} | ${mark(state)} | ${detail} |`
    ),
    "",
    "## 候選被勾「不實」的句子（逐句對照輸入確認）",
    "",
    ...(cand.untrueLines.length
      ? cand.untrueLines.map((line) => `- ${line}`)
      : ["- 沒有"]),
    "",
    "## 參考（不判過關）",
    "",
    "| 項目 | 基準 全部 | 候選 全部 | 基準 基本 | 候選 基本 | 基準 進階 | 候選 進階 |",
    "|---|---|---|---|---|---|---|",
    ref("有計分的版本", (t) => t.versions),
    ref("會傳（句）", (t) => `${t.willing}／${t.sentences}`),
    ref("尷尬（句）", (t) => `${t.awkward}／${t.sentences}`),
    ref("不實（句）", (t) => `${t.untrue}／${t.sentences}`),
    ref("★ 會傳（次）", (t) => `${t.starWilling}／${t.versions}`),
    ref("★ 尷尬（次）", (t) => `${t.starAwkward}／${t.versions}`),
    ref("有一句有趣（版）", (t) => `${t.fun}／${t.versions}`),
    ref("十句裡最想傳", (t) => t.favorite),
    `| 我沒回她：道歉、解釋或提空窗（句，機械計數、全部輸出） | ${iNoReply} |`,
    "",
    `- 十句都不想傳：${input.result.favoriteNone} 組（有計分 ${input.result.rated.length} 組）。`,
    "- ★ 解釋的人工評分：這輪暫緩、未評（Eric 2026-10-06 決定不填第三份表）；6a、6b 的機械檢查照常。",
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
  const form = await read("blind.md");
  const reveal = JSON.parse(await read("reveal-map.json")) as Reveal;
  const records = JSON.parse(await read("records.json")) as EvalRecord[];
  const result = tally({ form, reveal, records });
  const problems = completenessProblems({
    manifest: JSON.parse(await read("manifest.json")),
    casesSha256: await catalogSha256(),
    records,
    reveal,
    form,
    result,
  });
  const markdown = acceptanceMarkdown({ tag, result, records, problems });
  await Deno.writeTextFile(new URL("acceptance.md", out), markdown);
  console.log(markdown);
  if (problems.length) {
    throw new Error(
      `資料不完整（${problems.length} 項），acceptance.md 已標「未完成」，不能當正式驗收`,
    );
  }
}

if (import.meta.main) await main(Deno.args);
