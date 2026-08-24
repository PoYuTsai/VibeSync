// PR D：1:1 聊天的貼文記憶接線。
//
// 這支檔案守兩件事：
//
// A. **迴歸保險**：buildChatMessages 只新增 optional 欄位，欄位缺席時產生的
//    system prompt 必須與接線前**逐字相同**。做法是把接線前的 prompt 逐一
//    算 SHA-256 凍在下面 CHAT_PROMPT_GOLDEN_SHA256，任何一個位元組漂移都會紅。
//    prompt.ts 是已上線的 chat prompt，改壞會影響每一場練習，不只朋友圈。
//
// B. **記憶三態契約**（設計報告決定 E，2026-08-21 複審後縮小的版本）：
//
//    | 使用者提到的貼文 | 她看得到嗎 | 反應 |
//    | 七天內、確實存在 | 看得到 | 自然承接 |
//    | 七天外、確實存在 | 看不到 | 不確定語氣，不否認 |
//    | 完全捏造        | 看不到 | 同上 |
//
//    最容易做錯的是把它寫成兩態（「捏造就否認」）。那是錯的：她只看得到七天內
//    最多三則，第八天的**真**貼文會被她否認，比忘記更傷人設。三態的重點是
//    「看不到的一律用不確定語氣」，不區分真假。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { buildChatMessages } from "./prompt.ts";
import { resolvePracticeProfile } from "./practice_persona.ts";
import { getAcquaintanceOrigin } from "./acquaintance_origin.ts";
import { initialPersistedGameState } from "./game_state.ts";
import type { PracticeSceneContext } from "./life_schedule.ts";

const defaultProfile = resolvePracticeProfile({});
const srProfile = resolvePracticeProfile({ profileId: "practice_girl_051" });
const scene: PracticeSceneContext = {
  id: "evening-dinner-friends",
  statusLine: "剛跟朋友吃完飯，在回家的路上",
  promptLine: "妳剛跟朋友吃完飯，在回家的路上，回覆可以比白天放鬆一點。",
  replyTempo: "normal",
};

/**
 * 接線前既有的呼叫形狀。**這裡刻意一個字都不提 herRecentMoments**——
 * 它代表「今天的 buildChatMessages 呼叫端長什麼樣」，是黃金雜湊的取樣點。
 */
export const CHAT_GOLDEN_CASES = [
  {
    name: "standard-minimal",
    turns: [{ role: "user", text: "嗨" }],
    profile: defaultProfile,
    options: {},
  },
  {
    name: "standard-full",
    turns: [
      { role: "user", text: "今天也太累" },
      { role: "ai", text: "哈哈那你要早點睡欸" },
      { role: "user", text: "上次 Joyce 不是把你的 Line 給我嗎" },
    ],
    profile: defaultProfile,
    options: {
      partnerState: {
        mood: "guarded",
        innerThought: "他剛剛有點急，我想先看他穩不穩。",
      },
      sceneContext: scene,
      acquaintanceOrigin: getAcquaintanceOrigin("dating_app"),
      memorySummary: "更早她提過論文壓力與巷口咖啡",
    },
  },
  {
    name: "beginner-full",
    turns: [
      { role: "user", text: "在忙嗎" },
      { role: "ai", text: "還好啊，剛收工" },
    ],
    profile: defaultProfile,
    options: {
      practiceMode: "beginner",
      temperatureScore: 42,
      familiarityScore: 18,
      partnerState: {
        mood: "comfortable",
        innerThought: "他還算有分寸。",
      },
      sceneContext: scene,
      acquaintanceOrigin: getAcquaintanceOrigin("friend_intro"),
      memorySummary: "更早聊過她週末想去看展",
    },
  },
  {
    name: "game-full",
    turns: [
      { role: "user", text: "嗨" },
      { role: "ai", text: "嗨嗨" },
      { role: "user", text: "你笑起來蠻好看的" },
      { role: "ai", text: "喔？這句你對幾個人講過" },
    ],
    profile: srProfile,
    options: {
      practiceMode: "game",
      temperatureScore: 82,
      familiarityScore: 70,
      partnerState: { mood: "comfortable", innerThought: "他接得住玩笑。" },
      sceneContext: scene,
      acquaintanceOrigin: getAcquaintanceOrigin("dating_app"),
      memorySummary: "更早她自己確認過 Joyce 是朋友",
      gameState: initialPersistedGameState(),
    },
  },
] as const;

/**
 * 接線前（origin/main@bbcc98a6）的 system prompt 雜湊。
 *
 * 這一條紅掉代表 chat prompt 對既有呼叫端**產生了不同的輸出**——PR D 的
 * 前提就是不可以發生這件事。若日後有人刻意修改 chat prompt，請先確認
 * prompt_test.ts 也同步更新，再有意識地更新這裡的值；不要為了讓測試變綠
 * 而直接覆蓋。
 */
const CHAT_PROMPT_GOLDEN_SHA256: ReadonlyArray<readonly [string, string]> = [
  ["standard-minimal", "5979a73d95395bf5a203d9acd45a2051a54284c6b51be72a49d5d5408b88ac5b"],
  ["standard-full", "4415b7d5402d0ae41b4f7d4e36f5c84b6e80cabeb0d99ad18ad235f69467ded7"],
  ["beginner-full", "b901ce9882af072c398a4d4c13a3fb4942f824665391833b36625698be3e2778"],
  ["game-full", "0639e1cfa8b9568f604a9f0164dd55e054e3c8314bb1e9eca01fb76a0839fba2"],
];

async function sha256(text: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(text),
  );
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

Deno.test("迴歸保險：optional 欄位缺席時，chat prompt 與接線前逐字相同", async () => {
  assertEquals(CHAT_PROMPT_GOLDEN_SHA256.length, CHAT_GOLDEN_CASES.length);
  for (const [index, expected] of CHAT_PROMPT_GOLDEN_SHA256.entries()) {
    const testCase = CHAT_GOLDEN_CASES[index];
    assertEquals(testCase.name, expected[0]);
    const sys = buildChatMessages(
      testCase.turns as never,
      testCase.profile,
      testCase.options as never,
    )[0].content;
    assertEquals(
      await sha256(sys),
      expected[1],
      `chat prompt「${testCase.name}」與接線前不再逐字相同——PR D 只允許加 optional 欄位`,
    );
  }
});

Deno.test("迴歸保險：黃金取樣點確實覆蓋到三種練習模式與所有既有注入欄位", () => {
  const names = CHAT_GOLDEN_CASES.map((c) => c.name);
  for (const expected of ["standard", "beginner", "game"]) {
    assert(
      names.some((n) => n.startsWith(expected)),
      `黃金取樣缺少 ${expected} 模式`,
    );
  }
  const full = CHAT_GOLDEN_CASES.find((c) => c.name === "standard-full");
  assert(full);
  for (
    const field of [
      "partnerState",
      "sceneContext",
      "acquaintanceOrigin",
      "memorySummary",
    ]
  ) {
    assert(
      field in full.options,
      `黃金取樣沒有覆蓋既有欄位 ${field}，prompt 漂移時抓不到`,
    );
  }
});
