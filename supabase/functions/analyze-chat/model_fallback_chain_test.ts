import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  nextFallbackModel,
  providerMaxAttempts,
} from "./model_fallback_chain.ts";

const SONNET_5_5 = "claude-sonnet-5-5";
const SONNET_5 = "claude-sonnet-5";
const SONNET_4_6 = "claude-sonnet-4-6";
const HAIKU_4_5 = "claude-haiku-4-5-20251001";

function chainFrom(primary: string): string[] {
  const models = [primary];
  for (
    let next = nextFallbackModel(primary, primary);
    next;
    next = nextFallbackModel(primary, next)
  ) {
    models.push(next);
  }
  return models;
}

Deno.test("Sonnet 5.5 primary walks 5.5 → Sonnet 5 → 4.6 and never reaches Haiku", () => {
  assertEquals(chainFrom(SONNET_5_5), [SONNET_5_5, SONNET_5, SONNET_4_6]);
  // 退到 Sonnet 5 之後仍照 5.5 那條鏈走，不接 Sonnet 5 自己的 Haiku。
  assertEquals(nextFallbackModel(SONNET_5_5, SONNET_4_6), undefined);
  assertEquals(providerMaxAttempts(SONNET_5_5), 3);
});

Deno.test("Sonnet 5 primary keeps 5 → 4.6 → Haiku", () => {
  assertEquals(chainFrom(SONNET_5), [SONNET_5, SONNET_4_6, HAIKU_4_5]);
  assertEquals(providerMaxAttempts(SONNET_5), 3);
});

Deno.test("older primaries keep their tail of the chain", () => {
  assertEquals(chainFrom(SONNET_4_6), [SONNET_4_6, HAIKU_4_5]);
  assertEquals(providerMaxAttempts(SONNET_4_6), 2);
  assertEquals(chainFrom(HAIKU_4_5), [HAIKU_4_5]);
  assertEquals(providerMaxAttempts(HAIKU_4_5), 1);
});

Deno.test("unknown primaries and models off the chain have no fallback", () => {
  for (const model of ["claude-opus-5-5", "constructor", "__proto__", ""]) {
    assertEquals(nextFallbackModel(model, model), undefined, model);
    assertEquals(providerMaxAttempts(model), 1, model);
  }
  assertEquals(nextFallbackModel(SONNET_5_5, HAIKU_4_5), undefined);
});
