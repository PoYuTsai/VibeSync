import { assert } from "https://deno.land/std@0.168.0/testing/asserts.ts";

const apiSource = await Deno.readTextFile(
  new URL("../../../ios/VibeSyncKeyboard/KeyboardAPI.swift", import.meta.url),
);
const controllerSource = await Deno.readTextFile(
  new URL(
    "../../../ios/VibeSyncKeyboard/KeyboardViewController.swift",
    import.meta.url,
  ),
);

Deno.test("keyboard client persists a hash-bound UUID before dispatch", () => {
  const atomicWrite = apiSource.indexOf(
    "try data.write(to: fileURL, options: .atomic)",
  );
  const requestBody = apiSource.indexOf('"requestId": requestId');
  const dispatch = apiSource.indexOf("URLSession.shared.dataTask");
  assert(apiSource.includes("UUID().uuidString.lowercased()"));
  assert(apiSource.includes("SHA256.hash(data: data)"));
  assert(apiSource.includes("userId: session.userId"));
  assert(
    atomicWrite >= 0 && requestBody > atomicWrite && dispatch > requestBody,
  );
});

Deno.test("keyboard client retains ambiguous IDs and clears only after presentation", () => {
  const rateLimitCase = apiSource.indexOf("case 429:");
  const rejectedCase = apiSource.indexOf("case 400..<500:", rateLimitCase);
  assert(rateLimitCase >= 0 && rejectedCase > rateLimitCase);
  assert(
    !apiSource.slice(rateLimitCase, rejectedCase).includes(
      "pendingStore.clear",
    ),
  );

  const insert = controllerSource.indexOf(
    "self.textDocumentProxy.insertText(reply)",
  );
  const clear = controllerSource.indexOf(
    "self.api.markPresented(requestId: success.requestId)",
  );
  assert(insert >= 0 && clear > insert);
});

Deno.test("keyboard UI prevents a second billable request while one is active", () => {
  assert(controllerSource.includes("private var isGenerating = false"));
  assert(controllerSource.includes("guard !isGenerating else { return }"));
  assert(controllerSource.includes("isGenerating = true"));
  assert(controllerSource.includes("self.isGenerating = false"));
});
