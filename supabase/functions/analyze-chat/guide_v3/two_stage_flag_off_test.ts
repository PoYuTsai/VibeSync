// 兩段式開關（ANALYZE_GUIDE_V3_TWO_STAGE）沒開時，送給模型的字跟改版前（afa50d6f）逐字相同：
// 讀局面與寫卡的系統提示詞、讀局面的 json_schema、兩段的使用者提示詞都用 sha256 鎖住
//（雜湊在改版前的程式上算出來，同一組樣本）。改這幾段的人要連這裡一起看（Eric 2026-10-19
// 兩段式實驗）。事件、扣費與落帳結果另由重播錄音（replay_test.ts）鎖住。
import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { GUIDE_V3_ENTRIES } from "./entries.ts";
import {
  type GuideV3Background,
  readSystemPrompt,
  readUserPrompt,
  writeSystemPrompt,
  writeUserPrompt,
} from "./prompts.ts";
import { READ_TAGS_SCHEMA, type ReadTags } from "./read_tags.ts";
import type { CardSpec } from "./rules.ts";
import { toTurns } from "./turns.ts";

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

const MESSAGES = [
  { isFromMe: true, content: "週末有什麼計畫" },
  { isFromMe: false, content: "還沒想好" },
  { isFromMe: false, content: "可能在家追劇吧" },
  { isFromMe: true, content: "我最近在看一部推理劇，很好看" },
  { isFromMe: false, content: "[照片：一碗拉麵]" },
  { isFromMe: false, content: "我剛吃完你說的那家！" },
  { isFromMe: false, content: "😋" },
];

const BACKGROUND: GuideV3Background = {
  meetingContext: "交友軟體",
  duration: "剛認識",
  goal: "約出來見面",
  targetDescription: "喜歡吃",
  analysisContextNote: "她上週有提到想吃拉麵",
  partnerSummary: "上班族，住台北",
  conversationSummary: "兩人聊過推理劇",
};

const TAGS: ReadTags = {
  light: "green",
  herMove: "高點",
  herMoodBad: false,
  drunkOrLateNight: false,
  inviteReadiness: "沒機會",
  cancelHasAlternative: false,
  retreating: false,
  declinedOrBoundary: false,
  explicitRejection: false,
  blocked: false,
  risk: false,
  selfHarmSignal: false,
  minorSignal: false,
  needsHisFacts: true,
  identityQuestion: false,
  hisStatedFacts: ["我最近在看一部推理劇"],
  hasHisVoiceSample: true,
  replyWillingness: "high",
  worthyBallCount: 2,
  herTurnsPerfunctory: [],
  matchedEntries: ["B22", "B23"],
  readForUser: "她主動分享，氣氛很好。",
  waitFor: "",
};

const CARDS: CardSpec[] = [
  {
    task: "推進",
    method: "用他說過的",
    voice: "照他",
    questionBudget: 0,
    push: "種子",
    angle: 0,
  },
  {
    task: "接住",
    method: "留空格",
    voice: "預設",
    questionBudget: 1,
    push: null,
    angle: 0,
  },
  {
    task: "帶張力",
    method: "照樣寫＋標示",
    voice: "照他",
    questionBudget: 1,
    push: null,
    angle: 0,
  },
  {
    task: "接住",
    method: "留空格",
    voice: "預設",
    questionBudget: 1,
    push: null,
    angle: 1,
  },
  {
    task: "推進",
    method: "只用反應",
    voice: "預設",
    questionBudget: 1,
    push: "換地方",
    angle: 0,
  },
];

function samplePrompts() {
  const turns = toTurns(MESSAGES);
  return {
    read: readUserPrompt(turns, BACKGROUND),
    write: writeUserPrompt({
      turns,
      tags: TAGS,
      entries: GUIDE_V3_ENTRIES.filter((e) =>
        TAGS.matchedEntries.includes(e.id)
      ),
      cards: CARDS,
      background: BACKGROUND,
    }),
  };
}

Deno.test("兩段式沒開：讀局面與寫卡的系統提示詞跟改版前（afa50d6f）逐字相同", async () => {
  assertEquals(
    await sha256(readSystemPrompt()),
    "91c6657e79d9dcb55f54beb7799c04186cbfada6f8bf4992bb61c8c2853e729c",
  );
  assertEquals(
    await sha256(writeSystemPrompt()),
    "ba5d00f83b1f9ab45669b1e4d355ac151201d13b85ff340c6e8e7d7c51bddaa7",
  );
});

Deno.test("兩段式沒開：讀局面的 json_schema 跟改版前逐字相同", async () => {
  assertEquals(
    await sha256(JSON.stringify(READ_TAGS_SCHEMA)),
    "09de00926aa5e702514cec54ab1d6222ef456bee1b6e6b7808a0f51c30bb24f1",
  );
});

Deno.test("兩段式沒開：兩段的使用者提示詞跟改版前逐字相同（照片、貼圖、條目、五種規格都在樣本裡）", async () => {
  const { read, write } = samplePrompts();
  assertEquals(
    await sha256(read),
    "e7c30c6edd493e01df4d2a7412b8eba7e6eb8ccca6d85ed0daafdbccf77822ff",
  );
  assertEquals(
    await sha256(write),
    "1e9df50c9fc7c1e4a06697a050236024e36d7a3065d73e66e8a0945ca3738122",
  );
});
