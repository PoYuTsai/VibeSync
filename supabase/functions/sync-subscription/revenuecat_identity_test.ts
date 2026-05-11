import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";

import {
  buildRevenueCatUserIdCandidates,
  normalizeRevenueCatAppUserId,
} from "./revenuecat_identity.ts";

Deno.test("normalizeRevenueCatAppUserId trims non-empty string values", () => {
  assertEquals(
    normalizeRevenueCatAppUserId("  $RCAnonymousID:abc  "),
    "$RCAnonymousID:abc",
  );
  assertEquals(normalizeRevenueCatAppUserId("   "), null);
  assertEquals(normalizeRevenueCatAppUserId(null), null);
});

Deno.test("buildRevenueCatUserIdCandidates checks Supabase id first then RevenueCat original id", () => {
  assertEquals(
    buildRevenueCatUserIdCandidates("supabase-user", "$RCAnonymousID:abc"),
    ["supabase-user", "$RCAnonymousID:abc"],
  );
});

Deno.test("buildRevenueCatUserIdCandidates deduplicates aliased ids", () => {
  assertEquals(
    buildRevenueCatUserIdCandidates("same-user", " same-user "),
    ["same-user"],
  );
});
