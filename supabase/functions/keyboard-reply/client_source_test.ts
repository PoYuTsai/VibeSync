import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

const apiSource = await Deno.readTextFile(
  new URL("../../../ios/VibeSyncKeyboard/KeyboardAPI.swift", import.meta.url),
);
const controllerSource = await Deno.readTextFile(
  new URL(
    "../../../ios/VibeSyncKeyboard/KeyboardViewController.swift",
    import.meta.url,
  ),
);
const sharedAuthSource = await Deno.readTextFile(
  new URL("../../../ios/VibeSyncKeyboard/SharedAuth.swift", import.meta.url),
);
const bridgeSource = await Deno.readTextFile(
  new URL(
    "../../../lib/core/services/keyboard_token_bridge.dart",
    import.meta.url,
  ),
);

Deno.test("keyboard client persists a hash-bound UUID before dispatch", () => {
  const atomicWrite = apiSource.indexOf("let status = SecItemAdd(");
  const requestBody = apiSource.indexOf('"requestId": requestId');
  const dispatch = apiSource.indexOf("URLSession.shared.dataTask");
  assert(apiSource.includes("UUID().uuidString.lowercased()"));
  assert(apiSource.includes("SHA256.hash(data: data)"));
  assert(apiSource.includes("userId: session.userId"));
  assert(
    apiSource.includes("private static let ttl: TimeInterval = 23 * 60 * 60"),
  );
  assert(apiSource.includes("kSecAttrGeneric: Data(pending.requestId.utf8)"));
  assert(apiSource.includes("status == errSecDuplicateItem"));
  assert(
    atomicWrite >= 0 && requestBody > atomicWrite && dispatch > requestBody,
  );
});

Deno.test("keyboard client keeps bounded independent pending identities", () => {
  assert(apiSource.includes("private static let maxPendingCount = 16"));
  assert(
    apiSource.includes("currentUserEntries.count >= Self.maxPendingCount"),
  );
  assert(apiSource.includes("validEntries.filter { $0.userId == userId }"));
  assert(
    apiSource.includes(
      "currentUserEntries.first(where: { $0.fingerprint == fingerprint })",
    ),
  );
  assert(
    apiSource.includes(
      "for pending in allEntries() where pending.requestId == requestId",
    ),
  );
  assert(apiSource.includes("Self.accountPrefix + fingerprint"));
  assert(apiSource.includes("requestId: pending.requestId"));
  assert(apiSource.includes("kSecReturnPersistentRef: true"));
});

Deno.test("keyboard client clears terminal 429s but retains ambiguous failures", () => {
  assert(apiSource.includes("request.timeoutInterval = 30"));
  const rateLimitCase = apiSource.indexOf("case 429:");
  const rejectedCase = apiSource.indexOf("case 400..<500:", rateLimitCase);
  assert(rateLimitCase >= 0 && rejectedCase > rateLimitCase);
  const rateLimitBranch = apiSource.slice(rateLimitCase, rejectedCase);
  assert(rateLimitBranch.includes('== "MODEL_RATE_LIMITED"'));
  assert(rateLimitBranch.includes('== "QUOTA_EXCEEDED"'));
  assert(rateLimitBranch.includes('["safeToClear"] as? Bool == true'));
  assert(rateLimitBranch.includes("pendingStore.clear"));
  assert(rateLimitBranch.includes("Unknown 429 remains ambiguous"));
  const conflictCase = apiSource.indexOf("case 409:");
  const rateCase = apiSource.indexOf("case 429:", conflictCase);
  const conflictBranch = apiSource.slice(conflictCase, rateCase);
  assert(conflictBranch.includes("KEYBOARD_REPLY_REQUEST_PENDING"));
  assert(conflictBranch.includes("KEYBOARD_REPLY_REQUEST_REPLAY_MISMATCH"));
  assert(conflictBranch.includes("request_conflict_unknown"));
  assert(conflictBranch.includes(".requestPending"));
  const ambiguousServerCase = apiSource.indexOf("default:", rejectedCase);
  const markPresented = apiSource.indexOf(
    "func markPresented",
    ambiguousServerCase,
  );
  const ambiguousServerBranch = apiSource.slice(
    ambiguousServerCase,
    markPresented,
  );
  assert(ambiguousServerBranch.includes('?? "generation_failed"'));
  assert(!ambiguousServerBranch.includes("pendingStore.clear"));

  // The property is "a reply is only marked presented once it actually landed
  // in the text field". Insertion moved behind replyInsertionCoordinator and
  // this scan kept looking for the inlined call it replaced, so it failed on a
  // refactor that had in fact made the guarantee stronger: marking is now
  // conditional on the outcome, not merely sequenced after the attempt.
  const insertReply = controllerSource.indexOf(
    "@objc private func insertGeneratedReply()",
  );
  assert(insertReply >= 0, "insertGeneratedReply is gone");
  const nextFunc = controllerSource.indexOf(
    "\n    private func ",
    insertReply,
  );
  const body = controllerSource.slice(insertReply, nextFunc);
  const attempted = body.indexOf("replyInsertionCoordinator.insertLegacy(");
  const confirmed = body.indexOf("if outcome == .inserted {", attempted);
  const marked = body.indexOf("api.markPresented(", confirmed);
  assert(attempted >= 0, "the reply no longer goes through the coordinator");
  assert(confirmed > attempted, "presentation is not gated on the outcome");
  assert(marked > confirmed, "markPresented escaped the inserted branch");
  assertEquals(
    body.split("api.markPresented(").length - 1,
    1,
    "a second markPresented can mark an insertion that never happened",
  );
});

Deno.test("keyboard UI prevents a second billable request while one is active", () => {
  assert(controllerSource.includes("private var isGenerating = false"));
  assert(controllerSource.includes("guard !isGenerating else { return }"));
  assert(controllerSource.includes("isGenerating = true"));
  assert(controllerSource.includes("self.isGenerating = false"));
});

Deno.test("keyboard quota signal is bound to the authenticated user", () => {
  assert(sharedAuthSource.includes("markQuotaExceeded(userId: String)"));
  assert(sharedAuthSource.includes("Data(userId.utf8)"));
  assert(bridgeSource.includes("value == expectedUserId"));
});
