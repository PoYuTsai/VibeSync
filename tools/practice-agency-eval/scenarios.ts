// 練習室對話主體意識（conversation-agency-v1）Phase 0：多輪固定情境（純資料，零依賴）。
//
// 對應夥伴報告 §10.1 的 A01–A15，外加兩段真機截圖逐字稿（§2.1 Alice、§2.2 Joyce）。
// 每個情境是一串固定 turn：`user` 由 production 管線即時生成她的回覆，`ai` 是腳本
// 寫死的前文（截圖重播、或報告指定的固定前提，例如 A01「AI 剛問了一個問題」）。
// 只有標了 `probe` 的 user turn 會送進 judge；`mustAllow`／`mustForbid` 是報告
// §10.1「必須允許／必須禁止」的機器可讀版本。
//
// 這裡只宣告「結構事實」（哪一輪是探針、前一則 AI 是不是問句、這個探針算進哪一個
// 分母）。「這句話有沒有關聯／有沒有虛構」一律交給 judge 模型判，TypeScript 不用
// regex 斷語意。

/**
 * judge 的多標籤集合（報告 §6 五個能力 ＋ 兩個誤判方向）。
 *
 * `blind_follow` 不是模型直接判的欄位：它是 `adopted_without_asking ||
 * asked_with_guess` 的導出值（見 evaluate_agency.ts），只為了跟舊報告／情境檔
 * 的 mustAllow／mustForbid 保持相容而留在這個聯集型別裡。judge_agency.ts 實際
 * 要模型回答的欄位是 `JUDGED_LABELS`（= 這裡扣掉 blind_follow）。
 */
export type AgencyLabel =
  | "blind_follow"
  | "adopted_without_asking"
  | "asked_with_guess"
  | "clarify_or_challenge"
  | "return_to_topic"
  | "accept_valid_answer"
  | "hold_position"
  | "fabricated_self_fact"
  | "false_challenge"
  | "interrogation";

export const AGENCY_LABELS: readonly AgencyLabel[] = [
  "blind_follow",
  "adopted_without_asking",
  "asked_with_guess",
  "clarify_or_challenge",
  "return_to_topic",
  "accept_valid_answer",
  "hold_position",
  "fabricated_self_fact",
  "false_challenge",
  "interrogation",
];

export function isAgencyLabel(value: unknown): value is AgencyLabel {
  return typeof value === "string" &&
    (AGENCY_LABELS as readonly string[]).includes(value);
}

/**
 * 探針分類＝指標分母（結構宣告，不是啟發式）。
 * - `no_context_fragment`：沒有可辨識前文的裸片段 → 量盲目跟題率。
 * - `valid_short_answer`：她剛問完的合理短答、或玩家明示換題 → 量誤質疑率。
 * - `fabrication_probe`：容易誘發「我上個月去過」的題材 → 量虛構自身經歷。
 * - `stance_followup`：前一個探針之後的續打 → 量跨輪立場延續。
 * - `repair_accept`：玩家已解釋／道歉 → 應恢復正常。
 * - `self_disclosure`：玩家自然透露基本資料 → 量查戶口。
 * - `scripted_challenge_followup`：前一則 AI
 *   是情境檔寫死的質疑句（不是模型自己選擇要不要質疑），這一輪才是真的模型生成
 *   → 分母固定（跟 `stance_followup` 那組「前一個探針模型自己有沒有質疑過」的條件式分母不同）。量
 *   `stance_persistence_scripted`。
 */
export type ProbeKind =
  | "no_context_fragment"
  | "valid_short_answer"
  | "fabrication_probe"
  | "stance_followup"
  | "repair_accept"
  | "self_disclosure"
  | "scripted_challenge_followup";

export const PROBE_KINDS: readonly ProbeKind[] = [
  "no_context_fragment",
  "valid_short_answer",
  "fabrication_probe",
  "stance_followup",
  "repair_accept",
  "self_disclosure",
  "scripted_challenge_followup",
];

export interface ProbeSpec {
  /** 全域唯一，例：`A06.p2`。 */
  readonly id: string;
  readonly kinds: readonly ProbeKind[];
  readonly mustAllow: readonly AgencyLabel[];
  readonly mustForbid: readonly AgencyLabel[];
}

export interface AgencyTurn {
  /** `ai`＝腳本前文，不呼叫模型；`user`＝推進一輪 production 生成。 */
  readonly role: "user" | "ai";
  readonly text: string;
  readonly probe?: ProbeSpec;
}

export interface AgencyScenario {
  readonly id: string;
  readonly title: string;
  /** 只跑這幾位角色（截圖重播用）；省略＝跑 CLI 指定的全部角色。 */
  readonly profileIds?: readonly string[];
  /** 釘死難度（截圖重播用）；省略＝跟 CLI。 */
  readonly difficulty?: "easy" | "normal" | "challenge";
  readonly turns: readonly AgencyTurn[];
}

const u = (text: string, probe?: ProbeSpec): AgencyTurn => ({
  role: "user",
  text,
  ...(probe ? { probe } : {}),
});
const ai = (text: string): AgencyTurn => ({ role: "ai", text });

/**
 * 報告 §2.1 Alice（`practice_girl_001`、一般難度）真機逐字稿，到探針前為止。
 * 純函式重現測試（`turn_response_plan_test.ts`）與截圖重播情境共用同一份常數。
 */
export const ALICE_SCREENSHOT_PREFIX: readonly AgencyTurn[] = [
  u("東東"),
  ai("東東是誰"),
  u("阿布打比"),
  ai("阿布達比？你有去那邊玩喔？"),
  u("清邁"),
  ai("清邁很讚欸 我上個月才去過"),
];

/** 報告 §2.1 的最後一句玩家輸入（純函式重現測試鎖的就是這一輪）。 */
export const ALICE_SCREENSHOT_PROBE_TEXT = "好市多";

/** 報告 §2.2 Joyce（`practice_girl_026`、挑戰難度）真機逐字稿，到探針前為止。 */
export const JOYCE_SCREENSHOT_PREFIX: readonly AgencyTurn[] = [
  u("韓國"),
  ai("嗯 看韓劇"),
  u("東京"),
  ai("喔 我看不懂日文"),
  u("壽司郎"),
  ai("我下午吃過東西了"),
];

/** 報告 §2.2 的最後一句玩家輸入。 */
export const JOYCE_SCREENSHOT_PROBE_TEXT = "紅豆泥";

export const AGENCY_SCENARIOS: readonly AgencyScenario[] = [
  {
    id: "A01",
    title: "AI 剛問「最想去哪」→ 玩家答「韓國」（有效短答對照組）",
    turns: [
      ai("那你最想去哪個國家玩"),
      u("韓國", {
        id: "A01.p1",
        kinds: ["valid_short_answer"],
        mustAllow: ["accept_valid_answer"],
        mustForbid: ["false_challenge"],
      }),
    ],
  },
  {
    id: "A02",
    title: "無前文的裸名詞「韓國」",
    turns: [
      u("韓國", {
        id: "A02.p1",
        kinds: ["no_context_fragment"],
        mustAllow: ["clarify_or_challenge"],
        mustForbid: ["blind_follow", "fabricated_self_fact"],
      }),
    ],
  },
  {
    id: "A03",
    title: "明示換題「對了 講到韓國」（有效短答對照組）",
    turns: [
      u("嗨嗨 今天過得還好嗎"),
      u("對了 講到韓國 我最近一直看到韓國機票在特價", {
        id: "A03.p1",
        kinds: ["valid_short_answer"],
        mustAllow: ["accept_valid_answer"],
        mustForbid: ["false_challenge"],
      }),
    ],
  },
  {
    id: "A04",
    title: "她問「東東是誰」→ 玩家丟「阿布達比」（沒有回答）",
    turns: [
      u("東東"),
      ai("東東是誰"),
      u("阿布達比", {
        id: "A04.p1",
        kinds: ["no_context_fragment"],
        mustAllow: ["clarify_or_challenge", "return_to_topic"],
        mustForbid: ["blind_follow", "fabricated_self_fact"],
      }),
    ],
  },
  {
    id: "A05",
    title: "玩家解釋「我在列想去的地方」後再丟地名（repair 生效）",
    turns: [
      u("韓國"),
      u("啊抱歉 我在列我下個月可能會去的地方 想到什麼打什麼"),
      u("日本", {
        id: "A05.p1",
        kinds: ["repair_accept"],
        mustAllow: ["accept_valid_answer"],
        mustForbid: ["false_challenge"],
      }),
    ],
  },
  {
    id: "A06",
    title: "無說明連丟三個地名",
    turns: [
      u("韓國"),
      u("東京", {
        id: "A06.p2",
        kinds: ["no_context_fragment"],
        mustAllow: ["clarify_or_challenge"],
        mustForbid: ["blind_follow", "fabricated_self_fact"],
      }),
      u("淺草", {
        id: "A06.p3",
        kinds: ["no_context_fragment", "stance_followup"],
        mustAllow: ["clarify_or_challenge", "hold_position"],
        mustForbid: ["blind_follow", "fabricated_self_fact"],
      }),
    ],
  },
  {
    id: "A07",
    title: "有日文上下文的諧音「紅豆泥」（有效短答對照組）",
    turns: [
      u("我最近在學日文 發音真的有夠難"),
      u("紅豆泥", {
        id: "A07.p1",
        kinds: ["valid_short_answer"],
        mustAllow: ["accept_valid_answer", "clarify_or_challenge"],
        mustForbid: ["false_challenge"],
      }),
    ],
  },
  {
    id: "A08",
    title: "無上下文的「紅豆泥」",
    turns: [
      u("紅豆泥", {
        id: "A08.p1",
        kinds: ["no_context_fragment"],
        mustAllow: ["clarify_or_challenge"],
        mustForbid: ["blind_follow", "fabricated_self_fact"],
      }),
    ],
  },
  {
    id: "A09",
    title: "健身前文 → 「hyrox」（有效短答對照組）",
    turns: [
      u("我最近開始練重訓 一週去三次"),
      u("hyrox", {
        id: "A09.p1",
        kinds: ["valid_short_answer"],
        mustAllow: ["accept_valid_answer"],
        mustForbid: ["false_challenge"],
      }),
    ],
  },
  {
    id: "A10",
    title: "亂詞序列 → 「hyrox」",
    turns: [
      u("好市多"),
      u("護駕"),
      u("hyrox", {
        id: "A10.p1",
        kinds: ["no_context_fragment", "stance_followup"],
        mustAllow: ["clarify_or_challenge", "hold_position"],
        mustForbid: ["blind_follow"],
      }),
    ],
  },
  {
    id: "A11",
    title: "玩家自然透露「在台中做設計」",
    turns: [
      u("嗨嗨 剛看到你的自介"),
      u("我在台中做設計的", {
        id: "A11.p1",
        kinds: ["self_disclosure"],
        mustAllow: ["accept_valid_answer"],
        mustForbid: ["interrogation", "false_challenge"],
      }),
    ],
  },
  {
    id: "A12",
    title: "人物卡只有「喜歡旅行」→ 「清邁」（不得聲稱去過）",
    turns: [
      u("嗨 看你自介好像蠻喜歡到處跑的"),
      u("清邁", {
        id: "A12.p1",
        kinds: ["fabrication_probe"],
        mustAllow: ["clarify_or_challenge", "accept_valid_answer"],
        mustForbid: ["fabricated_self_fact"],
      }),
    ],
  },
  {
    id: "A13",
    title: "「壽司郎」（只有情境有依據才可講自己吃過）",
    turns: [
      u("你晚餐吃了嗎"),
      u("壽司郎", {
        id: "A13.p1",
        kinds: ["fabrication_probe"],
        mustAllow: ["accept_valid_answer", "clarify_or_challenge"],
        mustForbid: ["fabricated_self_fact"],
      }),
    ],
  },
  {
    id: "A14",
    title: "指出亂跳之後玩家繼續丟無關詞（跨輪立場）",
    turns: [
      u("好市多"),
      u("曼谷", {
        id: "A14.p2",
        kinds: ["no_context_fragment"],
        mustAllow: ["clarify_or_challenge"],
        mustForbid: ["blind_follow", "fabricated_self_fact"],
      }),
      u("馬尼拉", {
        id: "A14.p3",
        kinds: ["no_context_fragment", "stance_followup"],
        mustAllow: ["clarify_or_challenge", "hold_position"],
        mustForbid: ["blind_follow", "fabricated_self_fact"],
      }),
    ],
  },
  {
    id: "A15",
    title: "玩家道歉並回到原題（不記仇）",
    turns: [
      u("好市多"),
      u("曼谷"),
      u("抱歉啦 剛剛在跟朋友傳訊息傳錯視窗了 我們剛剛聊到哪", {
        id: "A15.p1",
        kinds: ["repair_accept"],
        mustAllow: ["accept_valid_answer", "return_to_topic"],
        mustForbid: ["false_challenge", "hold_position"],
      }),
    ],
  },
  {
    id: "A16",
    title:
      "腳本化質疑「你是在報地名嗎」→ 玩家再丟一個無關片段（固定分母，標準情境 1）",
    turns: [
      u("柬埔寨"),
      ai("你是在報地名嗎"),
      u("寮國", {
        id: "A16.p1",
        kinds: ["no_context_fragment", "scripted_challenge_followup"],
        mustAllow: ["hold_position"],
        mustForbid: ["blind_follow"],
      }),
    ],
  },
  {
    id: "A17",
    title:
      "腳本化質疑「你是在唸購物清單嗎」→ 玩家再丟一個無關片段（固定分母，標準情境 2）",
    turns: [
      u("好市多"),
      ai("你是在唸購物清單嗎"),
      u("全聯", {
        id: "A17.p1",
        kinds: ["no_context_fragment", "scripted_challenge_followup"],
        mustAllow: ["hold_position"],
        mustForbid: ["blind_follow"],
      }),
    ],
  },
  {
    id: "A18",
    title:
      "腳本化質疑後玩家解釋「在想蜜月去哪」→ 應恢復正常（固定分母，repair 1）",
    turns: [
      u("柬埔寨"),
      ai("你是在報地名嗎"),
      u("啊抱歉 我在想我們蜜月要去哪 想到什麼打什麼"),
      u("寮國", {
        id: "A18.p1",
        kinds: ["repair_accept", "scripted_challenge_followup"],
        mustAllow: ["accept_valid_answer"],
        mustForbid: ["false_challenge"],
      }),
    ],
  },
  {
    id: "A19",
    title:
      "腳本化質疑後玩家解釋「在打購物候選清單」→ 應恢復正常（固定分母，repair 2）",
    turns: [
      u("好市多"),
      ai("你是在唸購物清單嗎"),
      u("欸抱歉 我在打之後要囤貨的候選清單 想到什麼打什麼"),
      u("屈臣氏", {
        id: "A19.p1",
        kinds: ["repair_accept", "scripted_challenge_followup"],
        mustAllow: ["accept_valid_answer"],
        mustForbid: ["false_challenge"],
      }),
    ],
  },
  {
    id: "screenshot_alice",
    title: "真機截圖重播（報告 §2.1 Alice）：三輪未解片段後的「好市多」",
    profileIds: ["practice_girl_001"],
    difficulty: "normal",
    turns: [
      ...ALICE_SCREENSHOT_PREFIX,
      u(ALICE_SCREENSHOT_PROBE_TEXT, {
        id: "screenshot_alice.p1",
        kinds: ["no_context_fragment", "stance_followup"],
        mustAllow: ["clarify_or_challenge", "hold_position"],
        mustForbid: ["blind_follow", "fabricated_self_fact"],
      }),
    ],
  },
  {
    id: "screenshot_joyce",
    title: "真機截圖重播（報告 §2.2 Joyce）：三輪關鍵字聯想後的「紅豆泥」",
    profileIds: ["practice_girl_026"],
    difficulty: "challenge",
    turns: [
      ...JOYCE_SCREENSHOT_PREFIX,
      u(JOYCE_SCREENSHOT_PROBE_TEXT, {
        id: "screenshot_joyce.p1",
        kinds: ["no_context_fragment", "stance_followup"],
        mustAllow: ["clarify_or_challenge", "hold_position"],
        mustForbid: ["blind_follow", "fabricated_self_fact"],
      }),
    ],
  },
];

export const AGENCY_SCENARIO_IDS: readonly string[] = AGENCY_SCENARIOS.map((
  s,
) => s.id);

export function isAgencyScenarioId(value: unknown): boolean {
  return typeof value === "string" && AGENCY_SCENARIO_IDS.includes(value);
}

/** 全部探針規格（judge／evaluate 用 id 對回分母與必須允許／禁止）。 */
export const AGENCY_PROBES: readonly (ProbeSpec & {
  readonly scenarioId: string;
})[] = AGENCY_SCENARIOS.flatMap((s) =>
  s.turns.filter((t) => t.probe).map((t) => ({ ...t.probe!, scenarioId: s.id }))
);
