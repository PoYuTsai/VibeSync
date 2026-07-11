import { assert } from "https://deno.land/std@0.168.0/testing/asserts.ts";

const source = await Deno.readTextFile(
  new URL("./index.ts", import.meta.url),
);

function indexOfRequired(snippet: string): number {
  const index = source.indexOf(snippet);
  assert(index >= 0, `Expected index.ts to contain: ${snippet}`);
  return index;
}

Deno.test("index.ts keeps Edge serve entrypoint wired to injectable handler", () => {
  const createHandlerIndex = indexOfRequired("createPracticeChatHandler({");
  const createClientIndex = indexOfRequired("createClient(");
  const callDeepSeekIndex = indexOfRequired("callDeepSeek");
  const callClaudeIndex = indexOfRequired("callClaude");
  const serveIndex = indexOfRequired("serve(handleRequest)");

  assert(
    createHandlerIndex < serveIndex,
    "handler must be created before serve(handleRequest)",
  );
  assert(
    createClientIndex < serveIndex,
    "entrypoint must still create the Supabase client for the handler",
  );
  assert(
    callDeepSeekIndex < serveIndex,
    "entrypoint must still wire the production DeepSeek caller",
  );
  assert(
    callClaudeIndex < serveIndex,
    "entrypoint must wire the production Claude generated failover",
  );
});
