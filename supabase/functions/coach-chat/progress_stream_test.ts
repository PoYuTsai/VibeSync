import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  COACH_PROGRESS_MEDIA_TYPE,
  coachProgressStreamResponse,
  wantsCoachProgressStream,
} from "./progress_stream.ts";

async function readEvents(response: Response) {
  const body = await response.text();
  return body.trim().split("\n").map((line) => JSON.parse(line));
}

Deno.test("progress negotiation is opt-in so legacy clients stay buffered", () => {
  assertEquals(
    wantsCoachProgressStream(
      new Request("http://localhost", {
        headers: { Accept: COACH_PROGRESS_MEDIA_TYPE },
      }),
    ),
    true,
  );
  assertEquals(
    wantsCoachProgressStream(new Request("http://localhost")),
    false,
  );
});

Deno.test("progress stream emits only lifecycle stages before validated done", async () => {
  const response = coachProgressStreamResponse(async (onProgress) => {
    onProgress({ stage: "request" });
    onProgress({ stage: "generating", attempt: 1, maxAttempts: 3 });
    onProgress({ stage: "validating", attempt: 1, maxAttempts: 3 });
    onProgress({ stage: "finalizing" });
    return {
      status: 200,
      body: {
        card: { answer: "validated answer" },
        provider: "claude",
      },
    };
  });

  assertEquals(response.status, 200);
  assert(
    response.headers.get("content-type")?.includes(
      COACH_PROGRESS_MEDIA_TYPE,
    ),
  );
  const events = await readEvents(response);
  assertEquals(
    events.slice(0, -1).map((event) => event.type),
    [
      "coach.progress",
      "coach.progress",
      "coach.progress",
      "coach.progress",
    ],
  );
  assertEquals(
    events.slice(0, -1).map((event) => event.stage),
    ["request", "generating", "validating", "finalizing"],
  );
  for (const event of events.slice(0, -1)) {
    assertEquals("answer" in event, false);
    assertEquals("card" in event, false);
    assertEquals("result" in event, false);
  }
  assertEquals(events.at(-1), {
    type: "coach.done",
    result: {
      card: { answer: "validated answer" },
      provider: "claude",
    },
  });
});

Deno.test("post-start quota failure stays an error terminal frame", async () => {
  const response = coachProgressStreamResponse(async (onProgress) => {
    onProgress({ stage: "finalizing" });
    return {
      status: 429,
      body: {
        error: "Daily limit exceeded",
        message: "今日額度已用完",
        used: 15,
        limit: 15,
      },
    };
  });

  const events = await readEvents(response);
  assertEquals(events.at(-1), {
    type: "coach.error",
    status: 429,
    error: {
      error: "Daily limit exceeded",
      message: "今日額度已用完",
      used: 15,
      limit: 15,
    },
  });
});
