// 兩段式讀局面多的欄位說明（READ_TWO_STAGE_NOTES）的外洩哨兵（兩段式主審第 1 輪 P2，Eric 2026-10-20）：
// 兩段式開時（關係訊號開或關），判讀與要等她做什麼照抄那一段就不給；每句哨兵都帶只有提示詞才會寫的
// 記號，一般判讀說她在撒嬌、示愛不會被清掉。開關沒開照舊（見 flag_matrix_test.ts 的雜湊）。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  leakVariants,
  SENTINEL_LISTS,
} from "../../_shared/prompt_leak_harness.ts";
import { vetPlanText } from "./finalize.ts";
import {
  FLAG_MATRIX_TAGS,
  flagMatrixReadText,
  runFlagMatrix,
} from "./flag_matrix_harness.ts";
import { type GuideV3Plan, HOLD_WAIT_FALLBACK } from "./plan.ts";
import { RELATION_LEAK_SENTINELS } from "./relation.ts";
import { WORTHY_LINE_KINDS } from "./read_tags.ts";
import { handleGuideV3Stream } from "./stream_flow.ts";
import {
  READ_TWO_STAGE_NOTES,
  TWO_STAGE_READ_LEAK_SENTINELS,
  TWO_STAGE_READ_SENTINELS,
  TWO_STAGE_READ_SENTINELS_NORMALIZED,
} from "./two_stage_prompts.ts";

/// 主審舉的例子：判讀照抄 herAffection 那一行。
const HER_AFFECTION_LINE = READ_TWO_STAGE_NOTES.split("\n").find((l) =>
  l.startsWith("- herAffection：")
)!.slice(2);

/// 只有提示詞才會寫的記號：欄位名、line／label／kind 的填法、種類名後面接它的定義或「填」、
/// 這一段自己的標題與 App 預設值那一句。
const PROMPT_ONLY_MARKERS: readonly string[] = [
  "establishedCouple",
  "herAffection",
  "herHappyShare",
  "worthyLines",
  "line 填",
  "label 用",
  "kind 填",
  ...WORTHY_LINE_KINDS.flatMap((k) => [`「${k}」（`, `填「${k}」`]),
  "兩段式",
  "欄位",
  "作戰板標籤",
  "App 的預設值",
];

/// 一般判讀自己會講的話：不能被清掉。
const ORDINARY_JUDGMENTS: readonly string[] = [
  "她這一輪在撒嬌或示愛，說想你、要抱抱，可以大方接住。",
  "她在分享開心的事，最後問你她今天好不好看。",
  "你們已經在交往，她叫你寶寶是感情好，不是風險。",
  "她傳了照片和貼圖，心情很好，想聽你的看法。",
  "她說的話跟你們的關係對得上，照對話判斷就好。",
];

const PLAN: GuideV3Plan = {
  decision: "send",
  judgment: "她在分享日常。",
  reason: "照常回",
  waitFor: "",
  push: null,
  specs: [],
  entries: [],
  signals: {
    inviteReadiness: "沒機會",
    cold: { c1: false, herPerfunctoryStreak: 0 },
  },
};

function vetted(judgment: string, waitFor: string, extra: readonly string[]) {
  const removed: string[] = [];
  const out = vetPlanText(
    { ...PLAN, judgment, waitFor },
    (field) => removed.push(field),
    extra,
  );
  return { judgment: out.judgment, waitFor: out.waitFor, removed };
}

Deno.test("兩段式欄位說明的哨兵：每句都照抄自那一段、都帶只有提示詞才會寫的記號；整理過的那份一起比，也登記在共用清單", () => {
  for (const sentinel of TWO_STAGE_READ_SENTINELS) {
    assert(READ_TWO_STAGE_NOTES.includes(sentinel), sentinel);
    assert(
      PROMPT_ONLY_MARKERS.some((marker) => sentinel.includes(marker)),
      `沒有提示詞記號：${sentinel}`,
    );
  }
  // 每一行都至少有一句，只有「是感情好，不是風險」那一行沒有記號、刻意不挑。
  const lines = READ_TWO_STAGE_NOTES.split("\n").filter((l) => l.trim());
  const uncovered = lines.filter((line) =>
    !TWO_STAGE_READ_SENTINELS.some((s) => line.includes(s))
  );
  assertEquals(uncovered, [
    "- 已經在交往的兩人互用親暱的稱呼、撒嬌，是感情好，不是風險。",
  ]);
  assertEquals(TWO_STAGE_READ_LEAK_SENTINELS, [
    ...new Set([
      ...TWO_STAGE_READ_SENTINELS,
      ...TWO_STAGE_READ_SENTINELS_NORMALIZED,
    ]),
  ]);
  // 共用的哨兵測試（各種照抄寫法、至少 8 字、一般聊天與錄下的輸出都不中）照這份清單跑。
  assertEquals(
    SENTINEL_LISTS.TWO_STAGE_READ_SENTINELS,
    TWO_STAGE_READ_SENTINELS,
  );
  assertEquals(
    SENTINEL_LISTS.TWO_STAGE_READ_SENTINELS_NORMALIZED,
    TWO_STAGE_READ_SENTINELS_NORMALIZED,
  );
});

Deno.test("兩段式的判讀檢查：主審的例子（照抄 herAffection 那一行）與每句哨兵的各種照抄寫法都不給；一般判讀照給", () => {
  assertEquals(HER_AFFECTION_LINE.startsWith("herAffection："), true);
  for (
    const extra of [
      TWO_STAGE_READ_LEAK_SENTINELS,
      [...TWO_STAGE_READ_LEAK_SENTINELS, ...RELATION_LEAK_SENTINELS],
    ]
  ) {
    assertEquals(
      vetted(`她今天很黏你。${HER_AFFECTION_LINE}`, "", extra),
      { judgment: "", waitFor: "", removed: ["judgment"] },
    );
    const missed: string[] = [];
    for (const sentinel of TWO_STAGE_READ_SENTINELS) {
      for (const variant of leakVariants(sentinel)) {
        const out = vetted(
          `她回得很長，${variant}，可以接著聊。`,
          `等她${variant}再回`,
          extra,
        );
        if (
          out.judgment !== "" || out.waitFor !== HOLD_WAIT_FALLBACK ||
          out.removed.join() !== "judgment,waitFor"
        ) missed.push(variant);
      }
    }
    assertEquals(missed, []);
    for (const judgment of ORDINARY_JUDGMENTS) {
      assertEquals(vetted(judgment, "", extra).removed, [], judgment);
    }
  }
});

Deno.test("走正式流程：兩段式開（關係訊號開或關）時判讀照抄 herAffection 那一行就不給、記 log；兩段式沒開照舊給（跟 main 一樣）", async () => {
  const leaky = (combo: { twoStage: boolean; relation: boolean }) =>
    JSON.stringify({
      ...JSON.parse(flagMatrixReadText(combo)),
      readForUser: `${FLAG_MATRIX_TAGS.readForUser}${HER_AFFECTION_LINE}`,
    });
  type Outcome = {
    events: { type: string; judgment?: string }[];
    logs: { event: string; metadata: Record<string, unknown> }[];
  };
  for (
    const combo of [
      { twoStage: true, relation: false },
      { twoStage: true, relation: true },
    ]
  ) {
    const outcome = await runFlagMatrix(handleGuideV3Stream, combo, {
      readText: leaky(combo),
    }) as unknown as Outcome;
    const read = outcome.events.find((e) => e.type === "analysis.read")!;
    assertEquals(read.judgment, "", JSON.stringify(combo));
    assert(
      outcome.logs.some((l) =>
        l.event === "guide_v3_coach_text_removed" &&
        l.metadata.field === "judgment"
      ),
    );
    // 卡照常送。
    assert(outcome.events.some((e) => e.type === "analysis.card"));
  }
  for (
    const combo of [
      { twoStage: false, relation: false },
      { twoStage: false, relation: true },
    ]
  ) {
    const outcome = await runFlagMatrix(handleGuideV3Stream, combo, {
      readText: leaky(combo),
    }) as unknown as Outcome;
    const read = outcome.events.find((e) => e.type === "analysis.read")!;
    assert(String(read.judgment).includes(HER_AFFECTION_LINE));
  }
});
