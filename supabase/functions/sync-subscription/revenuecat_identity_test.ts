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

Deno.test("buildRevenueCatUserIdCandidates rejects a non-anonymous client id (privilege escalation guard)", () => {
  // A client must not be able to claim another user's entitlements by passing
  // that victim's Supabase user id as revenueCatAppUserId. Only anonymous
  // RevenueCat ids (unguessable, device-local) are trusted as a second lookup.
  assertEquals(
    buildRevenueCatUserIdCandidates(
      "attacker-user",
      "11111111-1111-4111-8111-111111111111",
    ),
    ["attacker-user"],
  );
  assertEquals(
    buildRevenueCatUserIdCandidates("attacker-user", "victim-user"),
    ["attacker-user"],
  );
});

Deno.test("buildRevenueCatUserIdCandidates still trusts anonymous RevenueCat ids for restore", () => {
  assertEquals(
    buildRevenueCatUserIdCandidates(
      "supabase-user",
      "  $RCAnonymousID:abc123  ",
    ),
    ["supabase-user", "$RCAnonymousID:abc123"],
  );
});
