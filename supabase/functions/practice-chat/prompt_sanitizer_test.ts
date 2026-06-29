import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { scrubRawImageFilenames } from "./prompt_sanitizer.ts";

Deno.test("scrubRawImageFilenames replaces raw screenshot filenames with one abstract placeholder", () => {
  assertEquals(
    scrubRawImageFilenames("S__42795075.jpg"),
    "[image concept omitted]",
  );
  assertEquals(
    scrubRawImageFilenames("IMG_1234.PNG"),
    "[image concept omitted]",
  );
  assertEquals(
    scrubRawImageFilenames("photo.webp"),
    "[image concept omitted]",
  );
});

Deno.test("scrubRawImageFilenames removes local paths with raw screenshot filenames", () => {
  assertEquals(
    scrubRawImageFilenames(
      String.raw`C:\Users\eric1\OneDrive\Desktop\S__42795075.jpg`,
    ),
    "[image concept omitted]",
  );
  assertEquals(
    scrubRawImageFilenames(String.raw`/tmp/uploads/IMG_1234.heic`),
    "[image concept omitted]",
  );
});
