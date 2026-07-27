import { assertEquals } from "jsr:@std/assert@1";

import { containsOwnPriorCandidates } from "./own_output_leak.ts";
import type { NormalizedKeyboardAssistCompilerOutput } from "./normalize.ts";

function transcript(
  texts: string[],
): NormalizedKeyboardAssistCompilerOutput {
  return {
    conversationType: "chat",
    suggestedMySide: "right",
    sideConfidence: "high",
    confidence: "high",
    turnState: "reply_due",
    cue: "討論週末行程",
    uncertainty: null,
    messages: texts.map((text, index) => ({
      index,
      side: index % 2 === 0 ? "left" : "right",
      text,
    })),
    candidates: [],
  } as NormalizedKeyboardAssistCompilerOutput;
}

Deno.test("no prior turn can never reject a transcript", () => {
  assertEquals(
    containsOwnPriorCandidates(transcript(["晚點跟你說喔好嗎"]), null),
    false,
  );
});

Deno.test("an unsent prior candidate read back as a message is rejected", () => {
  const result = containsOwnPriorCandidates(
    transcript(["你八月會回台東嗎", "那我把八月十五那天空下來"]),
    {
      offeredTexts: [
        "那我把八月十五那天空下來",
        "熱氣球我一直都很想去看看",
      ],
      insertedText: null,
    },
  );
  assertEquals(result, true);
});

Deno.test("a partially cropped candidate still counts as a leak", () => {
  const result = containsOwnPriorCandidates(
    transcript(["把八月十五那天空下來"]),
    {
      offeredTexts: ["那我把八月十五那天空下來"],
      insertedText: null,
    },
  );
  assertEquals(result, true);
});

Deno.test("the line the user actually sent stays part of the chat", () => {
  const sent = "那我把八月十五那天空下來";
  const result = containsOwnPriorCandidates(
    transcript(["你八月會回台東嗎", sent, "好啊那就這樣說定了"]),
    {
      offeredTexts: [sent, "熱氣球我一直都很想去看看"],
      insertedText: sent,
    },
  );
  assertEquals(
    result,
    false,
    "the adopted suggestion is the strongest continuity signal we have",
  );
});

Deno.test("whitespace and width differences do not hide a leak", () => {
  const result = containsOwnPriorCandidates(
    transcript(["那我把 八月十五 那天空下來"]),
    {
      offeredTexts: ["那我把八月十五那天空下來"],
      insertedText: null,
    },
  );
  assertEquals(result, true);
});

Deno.test("short pleasantries cannot trigger a false rejection", () => {
  const result = containsOwnPriorCandidates(
    transcript(["好啊", "嗯嗯"]),
    { offeredTexts: ["好啊", "嗯嗯"], insertedText: null },
  );
  assertEquals(
    result,
    false,
    "short fragments collide by accident and must not cost the user a retry",
  );
});
