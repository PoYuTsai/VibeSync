import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { modelRequestParams } from "./model_request_params.ts";

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

Deno.test("Sonnet 5.5 never gets disabled or temperature: between_tools plus explicit effort", () => {
  assertEquals(
    modelRequestParams("claude-sonnet-5-5", {
      thinking: { type: "disabled" },
      temperature: 0.7,
    }),
    {
      thinking: { type: "between_tools" },
      output_config: { effort: "medium" },
    },
  );
  assertEquals(
    modelRequestParams("claude-sonnet-5-5", {
      outputConfig: { format: { type: "json_schema" } },
    }).output_config,
    { format: { type: "json_schema" }, effort: "medium" },
  );
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
