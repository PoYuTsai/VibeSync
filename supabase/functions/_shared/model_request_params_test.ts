import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { maxTokensFor, modelRequestParams } from "./model_request_params.ts";

Deno.test("Sonnet 5 keeps thinking disabled by default and honours the caller", () => {
  assertEquals(modelRequestParams("claude-sonnet-5"), {
    thinking: { type: "disabled" },
  });
  assertEquals(
    modelRequestParams("claude-sonnet-5", {
      thinking: { type: "adaptive" },
      outputConfig: { format: { type: "json_schema" } },
      temperature: 0.7,
    }),
    {
      thinking: { type: "adaptive" },
      output_config: { format: { type: "json_schema" } },
    },
  );
});

Deno.test("Sonnet 5.5 never gets disabled or temperature: adaptive (omitted) plus effort low", () => {
  assertEquals(
    modelRequestParams("claude-sonnet-5-5", {
      thinking: { type: "disabled" },
      temperature: 0.7,
    }),
    {
      thinking: { type: "adaptive", display: "omitted" },
      output_config: { effort: "low" },
    },
  );
  assertEquals(
    modelRequestParams("claude-sonnet-5-5", {
      outputConfig: { format: { type: "json_schema" } },
    }).output_config,
    { format: { type: "json_schema" }, effort: "low" },
  );
});

Deno.test("maxTokensFor adds the 4000-token thinking headroom only for Sonnet 5.5", () => {
  assertEquals(maxTokensFor("claude-sonnet-5-5", 6500), 10500);
  for (
    const model of [
      "claude-sonnet-5",
      "claude-sonnet-4-6",
      "claude-haiku-4-5-20251001",
    ]
  ) {
    assertEquals(maxTokensFor(model, 6500), 6500);
  }
});

Deno.test("older models keep their native contract", () => {
  for (const model of ["claude-sonnet-4-6", "claude-haiku-4-5-20251001"]) {
    assertEquals(
      modelRequestParams(model, { thinking: { type: "disabled" } }),
      {},
    );
    assertEquals(modelRequestParams(model, { temperature: 0.7 }), {
      temperature: 0.7,
    });
  }
});
