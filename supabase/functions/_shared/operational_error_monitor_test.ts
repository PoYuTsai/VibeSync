import {
  assertEquals,
  assertRejects,
  assertStrictEquals,
} from "jsr:@std/assert@1";

import {
  type MutableSentryEvent,
  type SafeEdgeFailure,
  sanitizeOperationalEvent,
  withOperationalErrorMonitoring,
} from "./operational_error_monitor.ts";

const sensitive = "PRIVATE_CHAT_0912_alice@example.com";

Deno.test("privacy scrub keeps grouping fields but removes content", () => {
  const event: MutableSentryEvent = {
    event_id: "event-1",
    platform: "javascript",
    release: "1.0.1+340",
    message: sensitive,
    user: { id: sensitive },
    request: {
      url: `https://example.com/?chat=${sensitive}`,
      headers: { authorization: sensitive },
      data: sensitive,
    },
    breadcrumbs: [{ message: sensitive }],
    contexts: { private: sensitive },
    extra: { private: sensitive },
    tags: {
      runtime: "supabase-edge",
      edge_function: "coach-chat",
      edge_region: "ap-southeast-1",
      private: sensitive,
    },
    fingerprint: ["edge", "coach-chat", "http_5xx", "503"],
    exception: {
      values: [{
        type: "TypeError",
        value: sensitive,
        mechanism: {
          type: "generic",
          handled: false,
          description: sensitive,
          data: { private: sensitive },
        },
        stacktrace: {
          frames: [{
            filename:
              `file:///home/${sensitive}/supabase/functions/coach-chat/index.ts`,
            function: "handleRequest",
            lineno: 42,
            colno: 7,
            abs_path: sensitive,
            context_line: sensitive,
            pre_context: [sensitive],
            post_context: [sensitive],
            vars: { chat: sensitive },
          }],
        },
      }],
    },
  };

  const safe = sanitizeOperationalEvent(event);
  const encoded = JSON.stringify(safe);

  assertEquals(encoded.includes(sensitive), false);
  assertEquals(safe.event_id, "event-1");
  assertEquals(safe.tags, {
    runtime: "supabase-edge",
    edge_function: "coach-chat",
    edge_region: "ap-southeast-1",
  });
  assertEquals(safe.fingerprint, [
    "edge",
    "coach-chat",
    "http_5xx",
    "503",
  ]);
  assertEquals(safe.exception?.values?.[0].value, "TypeError");
  assertEquals(
    safe.exception?.values?.[0].stacktrace?.frames?.[0],
    {
      filename: "supabase_functions_coach-chat_index.ts",
      function: "handleRequest",
      lineno: 42,
      colno: 7,
    },
  );
});

Deno.test("successful response is returned without reporting", async () => {
  const failures: SafeEdgeFailure[] = [];
  const response = new Response("ok", { status: 200 });
  const monitored = withOperationalErrorMonitoring(
    "coach-chat",
    () => response,
    (failure) => {
      failures.push(failure);
      return Promise.resolve();
    },
  );

  const actual = await monitored(new Request("https://example.com/private"));

  assertStrictEquals(actual, response);
  assertEquals(failures, []);
});

Deno.test("5xx reports metadata without reading response content", async () => {
  const failures: SafeEdgeFailure[] = [];
  const response = new Response(sensitive, { status: 503 });
  const monitored = withOperationalErrorMonitoring(
    "analyze-chat",
    () => response,
    (failure) => {
      failures.push(failure);
      return Promise.resolve();
    },
  );

  const actual = await monitored(new Request("https://example.com/private"));

  assertStrictEquals(actual, response);
  assertEquals(failures, [{
    functionName: "analyze-chat",
    kind: "http_5xx",
    status: 503,
    errorType: "EdgeHttpError",
  }]);
  assertEquals(JSON.stringify(failures).includes(sensitive), false);
  assertEquals(await actual.text(), sensitive);
});

Deno.test("thrown error is rethrown while reporter receives no message", async () => {
  const failures: SafeEdgeFailure[] = [];
  const original = new Error(sensitive);
  original.name = sensitive;
  const monitored = withOperationalErrorMonitoring(
    "practice-chat",
    () => {
      throw original;
    },
    (failure) => {
      failures.push(failure);
      return Promise.resolve();
    },
  );

  const thrown = await assertRejects(
    () => monitored(new Request("https://example.com/private")),
  );

  assertStrictEquals(thrown, original);
  assertEquals(failures.length, 1);
  assertEquals(failures[0].functionName, "practice-chat");
  assertEquals(failures[0].kind, "unhandled_exception");
  assertEquals(failures[0].errorType, "Error");
  assertEquals(JSON.stringify(failures).includes(sensitive), false);
});

Deno.test("reporting failure never changes endpoint behavior", async () => {
  const response = new Response("still returned", { status: 500 });
  const monitored = withOperationalErrorMonitoring(
    "submit-feedback",
    () => response,
    () => Promise.reject(new Error(sensitive)),
  );

  const actual = await monitored(new Request("https://example.com/private"));

  assertStrictEquals(actual, response);
});
