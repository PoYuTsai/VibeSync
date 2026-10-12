// 兩段式 opener 的 source-scan 守門（同 opener_stream_branch_test.ts 慣例）：
// dispatch 存在、generic 月日 gate 排除、串流分支 transport-only、旗標閘門。
import { assert, assertFalse } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { classifyAnalyzeChatRequest } from "./request_shape.ts";
import { PROMPT_LEAK_DEFENSE_DIRECTIVE } from "./prompt_leak.ts";
import {
  hasOpenerFlowPromptLeak,
  OPENER_ANALYZE_PROMPT,
  OPENER_FLOW_PROMPT_SENTINELS,
  OPENER_FLOW_REPAIR_PROMPT,
  OPENER_GENERATE_PROMPT,
  OPENER_GENERATE_REPAIR_PROMPT,
} from "./opener_flow_prompt.ts";
import { OPENER_PLAN_PROMPT } from "./opener_plan.ts";
import { buildOpenerWritePrompt, OPENER_REWRITE_PROMPT } from "./opener_write.ts";

const indexSource = await Deno.readTextFile(new URL("./analyze_chat_handler.ts", import.meta.url));
const handlerSource = await Deno.readTextFile(new URL("./opener_flow_handler.ts", import.meta.url));

Deno.test("index：opener_analyze／opener_generate 分類與 dispatch 存在，且不被 generic 月日 gate 接管", () => {
  for (const mode of ["opener_analyze", "opener_generate"]) {
    const resolution = classifyAnalyzeChatRequest({ mode, userDraft: "草稿", images: [{}] });
    assert(resolution.ok && resolution.shape.kind === mode, `${mode} 帶草稿／圖片仍分類為自己`);
  }
  assert(indexSource.includes('const isOpenerFlowMode = requestShape.kind === "opener_analyze" ||'));
  assert(indexSource.includes("if (isOpenerFlowMode) {"));
  const gates = indexSource.split("!isOpenerFlowMode &&").length - 1;
  assert(gates >= 2, "月與日兩個 generic gate 都必須排除兩段式");
  assert(
    indexSource.indexOf("if (isOpenerFlowMode) {") < indexSource.indexOf("if (isOpenerMode) {"),
    "兩段式 dispatch 在舊單段 opener branch 之前",
  );
});

Deno.test("handler：串流被 OPENER_STREAM_ENABLED 閘住、只包模型呼叫與 complete；settle 不在 stream 包裝本體", () => {
  assert(handlerSource.includes('env("OPENER_STREAM_ENABLED") === "true"'));
  const start = handlerSource.indexOf("function streamOrRun(");
  const end = handlerSource.indexOf("// ═══", start);
  const wrapper = handlerSource.slice(start, end);
  assertFalse(wrapper.includes("settleOpenerGeneration"), "串流包裝本體不得自帶結算");
  assertFalse(wrapper.includes("settleOpenerAnalysis"));
  assert(wrapper.includes("emitJsonResponseAsStreamOutcome"));
  assert(wrapper.includes(`${"$"}{input.prefix}.started`));
});

Deno.test("handler：新局旗標與 DB 能力標記只擋第一段；第二段沒有 OPENER_TWO_STAGE_ENABLED 閘門", () => {
  const analyzeStart = handlerSource.indexOf("export async function handleOpenerAnalyzeRequest");
  const generateStart = handlerSource.indexOf("export async function handleOpenerGenerateRequest");
  const analyze = handlerSource.slice(analyzeStart, generateStart);
  const generate = handlerSource.slice(generateStart);
  assert(analyze.includes('env("OPENER_TWO_STAGE_ENABLED") === "false"'));
  assert(analyze.includes("readOpenerFlowDbContractVersion"));
  assertFalse(generate.includes("OPENER_TWO_STAGE_ENABLED"), "停用新局不得擋既有局取回或完成");
  // 第二段：模型前必有 claim（次數／併發／重播在模型前）、限流在 claim 後、settle 在投影後。
  const claimAt = generate.indexOf("await claimOpenerGeneration(claimArgs)");
  const rateAt = generate.indexOf('scope: "opener"');
  const modelAt = generate.indexOf("system: OPENER_GENERATE_PROMPT");
  const projectAt = generate.indexOf("projectOpenerGenerateResult(");
  const settleAt = generate.indexOf("await settleAndRespond(projected");
  assert(claimAt >= 0 && claimAt < rateAt && rateAt < modelAt && modelAt < projectAt && projectAt < settleAt);
  // 結構刀路徑同樣在 claim／限流之後才呼叫模型、產出結果後才結算；結算 RPC 全檔只有一處（新舊路徑共用）。
  const planWriteAt = generate.indexOf("await runOpenerPlanWrite(");
  const planSettleAt = generate.indexOf("await settleAndRespond(outcome.result");
  assert(rateAt < planWriteAt && planWriteAt < planSettleAt);
  assert(generate.split("await settleOpenerGeneration(").length === 2);
  // 扣費只發生在 settle RPC（SQL 內），handler 沒有任何直接 increment_usage 呼叫。
  assertFalse(handlerSource.includes("increment_usage"));
  assertFalse(handlerSource.includes("chargeOpenerQuota"));
});

Deno.test("外洩守門：兩段式每一份提示詞被吐出來都擋得到，拿掉結尾的保密指示也一樣", () => {
  const prompts: Record<string, string> = {
    analyze: OPENER_ANALYZE_PROMPT,
    generate: OPENER_GENERATE_PROMPT,
    generateRepair: OPENER_GENERATE_REPAIR_PROMPT,
    flowRepair: OPENER_FLOW_REPAIR_PROMPT,
    plan: OPENER_PLAN_PROMPT,
    writerFree: buildOpenerWritePrompt("free"),
    writerStyles: buildOpenerWritePrompt("styles"),
    rewrite: OPENER_REWRITE_PROMPT,
  };
  for (const [name, prompt] of Object.entries(prompts)) {
    assert(hasOpenerFlowPromptLeak(prompt), name);
    const body = prompt.replace(PROMPT_LEAK_DEFENSE_DIRECTIVE, "");
    assert(hasOpenerFlowPromptLeak(body), `${name}：沒有保密指示的本文`);
    // 只吐出開頭第一段（身分句）也算。
    assert(hasOpenerFlowPromptLeak(body.split("\n")[0]), `${name}：開頭一行`);
  }
  // 片段表的每一條都要真的出自某一份提示詞，改提示詞時這裡會提醒同步。
  const all = Object.values(prompts).join("\n");
  for (const sentinel of OPENER_FLOW_PROMPT_SENTINELS) {
    assert(all.includes(sentinel), sentinel);
  }
});

Deno.test("外洩守門：正常的分析與開場白輸出不誤擋", () => {
  const normal = [
    JSON.stringify({
      profileDigest: "自介：有養一隻狗，假日會去河堤",
      approach: { mode: "anchor_hooks", summary: "她的自介有兩三個可接的點，先確認你想聊哪個", avoid: [] },
    }),
    JSON.stringify({
      openers: { extend: "妳家狗散步會自己選路嗎", coldRead: "我最近也在找河堤的散步路線，妳都從哪一段開始走" },
      cardReasons: { extend: "直接問你想知道的事，她一句就能回" },
      pioneerPlan: { ifCold: "先停一下，別連發", handoff: "她回了就貼回分析" },
      directions: { coldRead: "先講一點你自己的散步習慣，再問她" },
    }),
    "這一段寫得很好，事實都有來源，規劃也很清楚",
  ];
  for (const text of normal) assertFalse(hasOpenerFlowPromptLeak(text), text);
});
