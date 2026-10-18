// 任務卡的「再調一下」走整個 handler：假 Supabase、假模型（guide_v3/refine_harness.ts），
// 看卡片規格驗證、送給模型的提示詞、定稿後回給 App 的字，以及被擋下時沒有授權免費次數、
// 沒有結算。
import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  fakeModelResponse,
  type RefineHarnessOptions,
  type RefineHarnessOutcome,
  runRefineThroughHandler,
} from "./guide_v3/refine_harness.ts";
import { computeOptimizeMessageInputHash } from "./optimize_message_billing.ts";
import { REFINE_REPLY_SYSTEM_PROMPT } from "./refine_prompt.ts";

const REQUEST_ID = "123e4567-e89b-42d3-a456-426614174abc";
const MESSAGES = [
  { isFromMe: true, content: "那家拉麵妳吃過嗎" },
  { isFromMe: false, content: "還沒耶 一直想去" },
];
const DRAFT = "那就週六\n我來訂位";
const PUSH_CARD = { task: "push", voice: "default", method: "reaction" };

async function run(
  body: Record<string, unknown>,
  optimized: string,
  options: RefineHarnessOptions = {},
): Promise<RefineHarnessOutcome & { models: Record<string, unknown>[] }> {
  const models: Record<string, unknown>[] = [];
  const out = await runRefineThroughHandler(
    {
      messages: MESSAGES,
      userDraft: DRAFT,
      requestId: REQUEST_ID,
      billingProtocolVersion: 3,
      ...body,
    },
    (request) => {
      models.push(request);
      return Promise.resolve(fakeModelResponse(JSON.stringify({
        optimizedMessage: {
          original: DRAFT,
          optimized,
          reason: "刪掉多餘的字",
        },
      })));
    },
    options,
  );
  return { ...out, models };
}

function rpcNames(out: RefineHarnessOutcome): string[] {
  return out.rpcs.map((call) => call.fn);
}

function systemText(request: Record<string, unknown>): string {
  return (request.system as { text: string }[])[0].text;
}

function userText(request: Record<string, unknown>): string {
  return (request.messages as { content: string }[])[0].content;
}

Deno.test("任務卡的再調：提示詞帶任務卡規則與陣列草稿，回給 App 的是定稿後的字", async () => {
  const out = await run(
    { refineInstruction: "短一點", guideV3Card: PUSH_CARD },
    "妳說的喔，就週六\n我來訂位",
  );
  assertEquals(out.status, 200);
  assertEquals(out.models.length, 1);
  const request = out.models[0];
  assertEquals(request.model, "claude-sonnet-5");
  assertStringIncludes(systemText(request), "## 任務卡規則");
  assertStringIncludes(systemText(request), "任務是「推進」");
  assertStringIncludes(
    userText(request),
    JSON.stringify({ userDraft: ["那就週六", "我來訂位"] }),
  );
  // 預設口吻：模型寫的「妳」換成「你」；兩則還是兩則。
  const optimized =
    (out.json.optimizedMessage as Record<string, unknown>).optimized;
  assertEquals(optimized, "你說的喔，就週六\n我來訂位");
  // 計費照回覆微調：先授權免費次數、再結算定稿後的字；hash 綁卡片規格。
  assertEquals(rpcNames(out), [
    "increment_model_usage",
    "consume_refine_free_allowance",
    "settle_optimize_message_request",
  ]);
  const settle = out.rpcs[2].args;
  assertEquals(
    (settle.p_result_json as { optimizedMessage: { optimized: string } })
      .optimizedMessage.optimized,
    "你說的喔，就週六\n我來訂位",
  );
  assertEquals(settle.p_charge_quota, false);
  assertEquals(
    settle.p_input_hash,
    await computeOptimizeMessageInputHash({
      messages: MESSAGES,
      userDraft: DRAFT,
      refineInstruction: "短一點",
      guideV3Card: PUSH_CARD,
    }),
  );
  const usage = out.json.usage as Record<string, unknown>;
  assertEquals(usage.quotaReason, "refine_free_daily");
  assertEquals(usage.refineFreeRemaining, 9);
  assertEquals(usage.messagesUsed, 0);
});

Deno.test("任務卡的再調：調出「欠」組整次不給，不授權免費次數、不結算、不扣費", async () => {
  const out = await run(
    { refineInstruction: "更直接", guideV3Card: PUSH_CARD },
    "就週六\n遲到算妳欠我一杯",
  );
  assertEquals(out.status, 502);
  assertEquals(out.json.code, "OPTIMIZE_MESSAGE_SAFETY_BLOCKED");
  assertEquals(out.json.shouldChargeQuota, false);
  assertEquals(rpcNames(out), ["increment_model_usage"]);
});

Deno.test("任務卡的再調：兩則被併成一則就整次不給，同樣不碰免費次數與結算", async () => {
  const out = await run(
    { refineInstruction: "短一點", guideV3Card: PUSH_CARD },
    "就週六，我來訂位",
  );
  assertEquals(out.status, 502);
  assertEquals(out.json.code, "OPTIMIZE_MESSAGE_RESULT_INVALID");
  assertEquals(out.json.shouldChargeQuota, false);
  assertEquals(rpcNames(out), ["increment_model_usage"]);
});

Deno.test("任務卡的再調：今天免費次數用完時照回覆微調扣 1 則（只在結果通過之後）", async () => {
  const out = await run(
    { refineInstruction: "短一點", guideV3Card: PUSH_CARD },
    "就週六\n我來訂位",
    { freeAllowance: "exhausted" },
  );
  assertEquals(out.status, 200);
  assertEquals(rpcNames(out), [
    "increment_model_usage",
    "consume_refine_free_allowance",
    "settle_optimize_message_request",
  ]);
  assertEquals(out.rpcs[2].args.p_charge_quota, true);
  const usage = out.json.usage as Record<string, unknown>;
  assertEquals(usage.messagesUsed, 1);
  assertEquals(usage.quotaReason, "refine_reply_fixed_1");
  assertEquals(usage.refineFreeRemaining, 0);

  // 同樣用完的情況下被擋：照樣不扣、不結算。
  const blocked = await run(
    { refineInstruction: "更直接", guideV3Card: PUSH_CARD },
    "就週六\n遲到算妳欠我一杯",
    { freeAllowance: "exhausted" },
  );
  assertEquals(blocked.status, 502);
  assertEquals(rpcNames(blocked), ["increment_model_usage"]);
});

Deno.test("任務卡規格不合法：400、0 扣費，不打模型、不碰額度", async () => {
  const out = await run(
    {
      refineInstruction: "短一點",
      guideV3Card: { task: "push", voice: "default" },
    },
    "不該被呼叫",
  );
  assertEquals(out.status, 400);
  assertEquals(out.json.code, "INVALID_GUIDE_V3_CARD");
  assertEquals(out.json.shouldChargeQuota, false);
  assertEquals(out.models.length, 0);
  assertEquals(rpcNames(out), []);
});

Deno.test("沒帶卡的微調照舊：原本的提示詞、草稿整段一行、模型的字原樣回", async () => {
  const out = await run(
    { refineInstruction: "短一點" },
    "妳說的喔，就週六我來訂位",
  );
  assertEquals(out.status, 200);
  const request = out.models[0];
  assertEquals(systemText(request), REFINE_REPLY_SYSTEM_PROMPT);
  assertStringIncludes(
    userText(request),
    JSON.stringify({ userDraft: "那就週六 我來訂位" }),
  );
  assertEquals(
    (out.json.optimizedMessage as Record<string, unknown>).optimized,
    "妳說的喔，就週六我來訂位",
  );
  assertEquals(
    out.rpcs[2].args.p_input_hash,
    await computeOptimizeMessageInputHash({
      messages: MESSAGES,
      userDraft: DRAFT,
      refineInstruction: "短一點",
    }),
  );
});

Deno.test("潤飾帶了卡片規格也不理：不進提示詞、不進 hash", async () => {
  const out = await run({ guideV3Card: PUSH_CARD }, "那就週六，我來訂位");
  assertEquals(out.status, 200);
  assert(!systemText(out.models[0]).includes("任務卡規則"));
  const settle = out.rpcs.find((call) =>
    call.fn === "settle_optimize_message_request"
  )!;
  assertEquals(
    settle.args.p_input_hash,
    await computeOptimizeMessageInputHash({
      messages: MESSAGES,
      userDraft: DRAFT,
    }),
  );
  assert(!rpcNames(out).includes("consume_refine_free_allowance"));
});

/// 還沒升版的 Edge 寫的帳本列：它不認 guideV3Card，hash 用的是不含卡的那一份。
async function legacyHash(): Promise<string> {
  return await computeOptimizeMessageInputHash({
    messages: MESSAGES,
    userDraft: DRAFT,
    refineInstruction: "短一點",
  });
}

const LEGACY_RESULT = {
  optimizedMessage: { optimized: "那就週六，我來訂位", reason: "舊版調的" },
};

Deno.test("跨版本重播：舊 Edge 已結算的同一顆 requestId，升版後重試照 replay 給，不扣、不換身分", async () => {
  const out = await run(
    { refineInstruction: "短一點", guideV3Card: PUSH_CARD },
    "不該被呼叫",
    { ledgerRow: { inputHash: await legacyHash(), result: LEGACY_RESULT } },
  );
  assertEquals(out.status, 200);
  assertEquals(
    (out.json.optimizedMessage as Record<string, unknown>).optimized,
    "那就週六，我來訂位",
  );
  assertEquals(out.models.length, 0);
  assert(!rpcNames(out).includes("consume_refine_free_allowance"));
  assert(!rpcNames(out).includes("settle_optimize_message_request"));
  const usage = out.json.usage as Record<string, unknown>;
  assertEquals(usage.messagesUsed, 0);
  assertEquals(usage.quotaReason, "optimize_message_idempotent_replay");
});

Deno.test("跨版本重播：舊 Edge 在預檢之後才寫進帳本（並行重試），結算改拿那一列、不再扣", async () => {
  const out = await run(
    { refineInstruction: "短一點", guideV3Card: PUSH_CARD },
    "就週六\n我來訂位",
    {
      freeAllowance: "exhausted",
      ledgerRow: {
        inputHash: await legacyHash(),
        result: LEGACY_RESULT,
        appearsAtSettle: true,
      },
    },
  );
  assertEquals(out.status, 200);
  assertEquals(
    (out.json.optimizedMessage as Record<string, unknown>).optimized,
    "那就週六，我來訂位",
  );
  const settles = out.rpcs.filter((call) =>
    call.fn === "settle_optimize_message_request"
  );
  assertEquals(settles.length, 2);
  assertEquals(settles[1].args.p_input_hash, await legacyHash());
  assertEquals(settles[1].args.p_charge_quota, false);
  assert(!rpcNames(out).includes("increment_usage"));
  const usage = out.json.usage as Record<string, unknown>;
  assertEquals(usage.messagesUsed, 0);
});

Deno.test("跨版本重播只認不含卡的那一份：帳本列是別的 hash 照舊回不一致", async () => {
  const preflight = await run(
    { refineInstruction: "短一點", guideV3Card: PUSH_CARD },
    "不該被呼叫",
    { ledgerRow: { inputHash: "f".repeat(64), result: LEGACY_RESULT } },
  );
  assertEquals(preflight.status, 400);
  assertEquals(preflight.json.code, "OPTIMIZE_MESSAGE_REQUEST_REPLAY_MISMATCH");
  assertEquals(preflight.models.length, 0);

  const atSettle = await run(
    { refineInstruction: "短一點", guideV3Card: PUSH_CARD },
    "就週六\n我來訂位",
    {
      ledgerRow: {
        inputHash: "f".repeat(64),
        result: LEGACY_RESULT,
        appearsAtSettle: true,
      },
    },
  );
  assertEquals(atSettle.status, 409);
  assertEquals(atSettle.json.code, "OPTIMIZE_MESSAGE_REQUEST_REPLAY_MISMATCH");

  // 一般微調（沒帶卡）不另外認舊 hash：行為跟以前一樣。
  const plain = await run(
    { refineInstruction: "短一點" },
    "不該被呼叫",
    {
      ledgerRow: {
        inputHash: await computeOptimizeMessageInputHash({
          messages: MESSAGES,
          userDraft: DRAFT,
          refineInstruction: "短一點",
          guideV3Card: PUSH_CARD,
        }),
        result: LEGACY_RESULT,
      },
    },
  );
  assertEquals(plain.status, 400);
});
