// 練習室寫實差異化（reply-style-v1）PR-0：固定 12 類對話情境（純資料，零依賴）。
//
// 對應規格 §10.1 的 12 類；每個情境是一串 user 訊息，AI 回覆逐輪由 production
// 管線即時生成，最後一則 user 訊息是「探針」——評測與盲測主要看她對探針的回覆。
// 句子刻意不抄 prompt 裡的示範句與 bakeoff 腳本；`{interest}` 會被換成該女孩的
// 第一個興趣 tag（規格 §4.5「精確碰到 profile 興趣」要的是精確匹配，不是泛稱）。

export type ScenarioFamily =
  | "opening"
  | "interrogation"
  | "interest_hit"
  | "daily_share"
  | "vulnerability"
  | "light_joke"
  | "failed_joke"
  | "disagreement"
  | "early_invite"
  | "mature_invite"
  | "boundary"
  | "memory_mismatch";

export interface Scenario {
  readonly id: ScenarioFamily;
  readonly userTurns: readonly string[];
}

export const SCENARIOS: readonly Scenario[] = [
  {
    id: "opening",
    userTurns: ["嗨嗨 剛看到妳的自介覺得蠻有意思的 想說來打個招呼"],
  },
  {
    id: "interrogation",
    userTurns: ["哈囉", "妳幾歲啊", "住哪裡", "做什麼工作", "平常都幾點下班"],
  },
  {
    id: "interest_hit",
    userTurns: [
      "嗨 看到妳有寫喜歡{interest}",
      "我自己也蠻有興趣的 妳是怎麼開始的",
    ],
  },
  {
    id: "daily_share",
    userTurns: [
      "嗨嗨",
      "今天上班被主管唸了一頓 有點悶",
      "剛剛買了杯珍奶安慰自己 哈",
    ],
  },
  {
    id: "vulnerability",
    userTurns: [
      "嗨 今天過得怎樣",
      "我還好 只是最近一直睡不好",
      "老實說有點焦慮 換工作那件事一直懸著",
    ],
  },
  {
    id: "light_joke",
    userTurns: ["哈囉", "妳自介說妳慢熱 那我是不是要先預約排隊"],
  },
  {
    id: "failed_joke",
    userTurns: [
      "嗨嗨",
      "妳知道為什麼咖啡不能開車嗎",
      "因為它會被拿鐵撞到 哈哈哈哈",
    ],
  },
  {
    id: "disagreement",
    userTurns: [
      "妳假日通常都在幹嘛",
      "欸 我跟妳想法不太一樣 我覺得假日待在家很可惜 一定要出門才算休息",
    ],
  },
  {
    id: "early_invite",
    userTurns: [
      "嗨嗨 妳好",
      "妳的照片看起來很有氣質",
      "週末要不要出來喝個咖啡",
    ],
  },
  {
    id: "mature_invite",
    userTurns: [
      "嗨 今天過得如何",
      "我今天去了一趟朋友推薦的小巷弄 發現一間蠻安靜的店",
      "妳平常比較喜歡安靜一點的地方還是熱鬧的",
      "我懂 我也是那種需要充電的人",
      "其實跟妳聊天蠻放鬆的 沒有壓力",
      "如果妳這週有空 想找妳一起去那間店坐坐 不趕時間的那種",
    ],
  },
  {
    id: "boundary",
    userTurns: [
      "嗨",
      "妳身材看起來很好 有在健身嗎",
      "那妳穿泳裝一定很好看 有照片嗎",
    ],
  },
  {
    id: "memory_mismatch",
    userTurns: ["嗨 好久沒聊", "上次妳不是說妳在學衝浪嗎 後來有繼續嗎"],
  },
];

export const SCENARIO_IDS: readonly ScenarioFamily[] = SCENARIOS.map((s) =>
  s.id
);

export function isScenarioId(value: unknown): value is ScenarioFamily {
  return typeof value === "string" &&
    (SCENARIO_IDS as readonly string[]).includes(value);
}

export function renderUserTurn(template: string, interest: string): string {
  return template.replaceAll("{interest}", interest);
}
