// 動態貼文路徑的 no-canned 與隱私鐵則的**原始碼**守門。
//
// 為什麼另開一支：現行 generated_only_source_test.ts 只讀 handler.ts，
// 生成邏輯放在 moments_handler.ts 的話它一行都蓋不到——沒有這支測試，
// no-canned 鐵則在朋友圈這條路徑上是**零守門**。
//
// 行為面的證明在 moments_handler_test.ts（失敗一定 release、絕不 commit）；
// 這裡守的是「後人不會偷偷加一條 fallback 分支」這種只有讀原始碼才看得出
// 來的退化。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { MAX_MOMENT_ATTEMPTS } from "./moments_constants.ts";

async function read(name: string): Promise<string> {
  return await Deno.readTextFile(new URL(`./${name}`, import.meta.url));
}

const momentsHandler = await read("moments_handler.ts");
const momentsPrompt = await read("moments_prompt.ts");
const momentsImageGen = await read("moments_image_gen.ts");
const momentsValidate = await read("moments_validate.ts");
const practiceHandler = await read("handler.ts");
const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260822120000_practice_moment_posts.sql",
    import.meta.url,
  ),
);

/** 去掉行註解，讓「不得出現」類斷言不會被說明文字誤判。 */
function withoutComments(source: string): string {
  return source
    .split("\n")
    .map((line) => {
      const marker = line.indexOf("//");
      return marker >= 0 ? line.slice(0, marker) : line;
    })
    .join("\n");
}

const executableHandler = withoutComments(momentsHandler);
const executablePrompt = withoutComments(momentsPrompt);
const executableImageGen = withoutComments(momentsImageGen);

Deno.test("生成失敗一定走 release，而且 release 是真的 RPC 呼叫", () => {
  assert(executableHandler.includes('"release_practice_moment_slot"'));
  assert(executableHandler.includes('"commit_practice_moment_post"'));
  assert(executableHandler.includes('"reserve_practice_moment_slot"'));
});

Deno.test("moments_handler 沒有任何罐頭／fallback 產出路徑", () => {
  for (
    const forbidden of [
      "fallback",
      "Fallback",
      "canned",
      "DEFAULT_BODY",
      "PLACEHOLDER_BODY",
      "sampleBody",
      "buildFallback",
    ]
  ) {
    assertEquals(
      executableHandler.includes(forbidden),
      false,
      `moments_handler.ts 不得出現罐頭識別字：${forbidden}`,
    );
  }
});

Deno.test("body 只可能來自驗證通過的模型輸出", () => {
  // p_body 在整個檔案裡只被指派一次，而且指派的是 draft.body。
  const occurrences = [...executableHandler.matchAll(/p_body:\s*([^,\n]+)/g)]
    .map((match) => match[1].trim());
  assertEquals(occurrences, ["draft.body"]);
  // draft 只可能來自 validateMomentDraft。
  const draftAssignments = [
    ...executableHandler.matchAll(/draft = ([^;\n]+)/g),
  ].map((match) => match[1].trim());
  assertEquals(draftAssignments.length, 1);
  assert(draftAssignments[0].startsWith("validateMomentDraft("));
});

Deno.test("死線中止不得 release：那條分支必須在 release 之前 return", () => {
  const deadlineBranch = executableHandler.indexOf(
    "if (Date.now() >= deadlineAt) {",
  );
  assert(deadlineBranch > 0, "找不到死線分支");
  const releaseCall = executableHandler.indexOf(
    "await releaseSlot(",
    deadlineBranch,
  );
  const returnNull = executableHandler.indexOf("return null;", deadlineBranch);
  assert(
    returnNull > 0 && returnNull < releaseCall,
    "死線分支必須先 return，否則死線中止會 release 掉 token，" +
      "下一個請求立刻接手並多燒一次 attempts",
  );
});

Deno.test("限流與 slot 認領封裝在同一個原子 reserve transaction", () => {
  const reserveAt = executableHandler.indexOf('"reserve_practice_moment_slot"');
  const modelAt = executableHandler.indexOf("await deps.callDeepSeek({");
  assert(reserveAt > 0 && modelAt > reserveAt);
  assertEquals(executableHandler.includes("enforceModelRateLimit({"), false);
  assert(executableHandler.includes("p_user_id: userId"));
  assert(executableHandler.includes("p_count_user_usage: !isTestAccount"));
  assert(
    migration.includes("p_user_id, 'practice_moment', p_minute_limit"),
    "reserve SQL 必須在同一 transaction 內計 per-user usage",
  );
});

Deno.test("隱私鐵則：moments_prompt 碰不到任何使用者衍生資料", () => {
  for (
    const forbidden of [
      "relationship_thread",
      "relationshipThread",
      "memorySummary",
      "./hint.ts",
      "./debrief_card.ts",
      "turns",
      "userId",
      "sessionId",
      "practice_chat_sessions",
      "nickname",
    ]
  ) {
    assertEquals(
      executablePrompt.includes(forbidden),
      false,
      `moments_prompt.ts 不得出現使用者衍生資料的痕跡：${forbidden}`,
    );
  }
});

Deno.test("隱私鐵則：moments_image_gen 碰不到任何使用者衍生資料", () => {
  // 生圖 prompt 的輸入只有 committed body、theme_id 與常數模板（PR-3）。
  // userId 允許存在——它只進 claim RPC 的限流參數，這裡另擋「對話／記憶」
  // 模組與欄位的 import 痕跡，防後人把聊天內容餵進場景描述。
  for (
    const forbidden of [
      "relationship_thread",
      "relationshipThread",
      "memorySummary",
      "./hint.ts",
      "./debrief_card.ts",
      "./moments_memory.ts",
      "./prompt.ts",
      "practice_chat_sessions",
      "nickname",
      "turns",
    ]
  ) {
    assertEquals(
      executableImageGen.includes(forbidden),
      false,
      `moments_image_gen.ts 不得出現使用者衍生資料的痕跡：${forbidden}`,
    );
  }
  // userId 只允許以 claim 限流參數的形式出現。
  assert(executableImageGen.includes("p_user_id: userId"));
  const userIdUses = [...executableImageGen.matchAll(/userId/g)].length;
  const declaredUses =
    [...executableImageGen.matchAll(/userId: string|p_user_id: userId|userId, isTestAccount|, userId,/g)]
      .length;
  assert(
    userIdUses <= declaredUses + 2,
    "userId 在 moments_image_gen 出現太多次，疑似流進生圖 prompt",
  );
});

Deno.test("no-canned 圖片版：image_gen 失敗只 release，絕不落替代圖", () => {
  for (
    const forbidden of [
      "fallbackImage",
      "placeholderImage",
      "DEFAULT_IMAGE",
      "canned",
    ]
  ) {
    assertEquals(
      executableImageGen.includes(forbidden),
      false,
      `moments_image_gen.ts 不得出現替代圖識別字：${forbidden}`,
    );
  }
  assert(executableImageGen.includes('"release_practice_moment_image"'));
  assert(executableImageGen.includes('"commit_practice_moment_image"'));
  assert(executableImageGen.includes('"claim_practice_moment_image"'));
});

Deno.test("隱私鐵則：moments_handler 只把 userId 用在讀解鎖與限流，不進 prompt", () => {
  const buildAt = executableHandler.indexOf("messages: buildMomentMessages({");
  const buildEnd = executableHandler.indexOf("}),", buildAt);
  assert(buildAt > 0 && buildEnd > buildAt);
  const buildArgs = executableHandler.slice(buildAt, buildEnd);
  for (const forbidden of ["userId", "user.", "turns", "session"]) {
    assertEquals(
      buildArgs.includes(forbidden),
      false,
      `buildMomentMessages 的參數不得含 ${forbidden}`,
    );
  }
});

Deno.test("驗證管線掛齊四道可見文字守門", () => {
  for (
    const required of [
      "rejectVisibleInternalLabelLeak",
      "rejectL4UnsafeVisibleText",
      "containsRawImageFilename",
      "containsPromptLeak",
      "toTraditionalChinese",
    ]
  ) {
    assert(
      momentsValidate.includes(required),
      `moments_validate.ts 必須掛上 ${required}`,
    );
  }
});

Deno.test("TS 側 MAX_MOMENT_ATTEMPTS 等於 SQL CHECK 的上界", () => {
  assert(
    migration.includes(`CHECK (attempts BETWEEN 0 AND ${MAX_MOMENT_ATTEMPTS})`),
  );
  assert(
    momentsHandler.includes("p_max_attempts: MAX_MOMENT_ATTEMPTS"),
    "handler 必須把常數傳給 RPC，不得留字面值",
  );
});

Deno.test("dispatch 是純加法，且不碰 chat／hint／debrief 路徑", () => {
  const dispatchAt = practiceHandler.indexOf(
    'rawBody.mode === "practice_moments"',
  );
  assert(dispatchAt > 0, "handler.ts 必須有 practice_moments 分支");
  const collectionAt = practiceHandler.indexOf(
    'rawBody.mode === "practice_collection"',
  );
  const validateAt = practiceHandler.indexOf(
    "request = validateRequest(rawBody)",
  );
  assert(collectionAt > 0 && validateAt > 0);
  assert(
    dispatchAt > collectionAt && dispatchAt < validateAt,
    "分支必須插在既有的唯讀 mode 旁、聊天請求解析之前",
  );
  const branch = withoutComments(
    practiceHandler.slice(
      dispatchAt,
      practiceHandler.indexOf("return jsonResponse(momentsResult", dispatchAt),
    ),
  );
  for (
    const forbidden of ["buildChatMessages", "buildHintMessages", "debrief"]
  ) {
    assertEquals(branch.includes(forbidden), false);
  }
});
