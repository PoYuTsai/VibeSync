// 漂移守門：committed 的 client catalog 必須等於由 server GIRL_PROFILES 重新產生的結果。
// 若有人改了 Edge catalog 卻忘了 regenerate，這個測試會紅。
//
//   deno test --allow-read tools/gen-practice-catalog/catalog_sync_test.ts
import { assertEquals } from "jsr:@std/assert@1";
import { buildCatalogDart, catalogTarget } from "./gen_practice_girl_catalog.ts";

Deno.test("client practice_girl_catalog.dart 與 server GIRL_PROFILES 同步", async () => {
  const onDisk = await Deno.readTextFile(catalogTarget);
  assertEquals(
    onDisk,
    buildCatalogDart(),
    "client catalog 已漂移；請執行 deno run --allow-read --allow-write " +
      "tools/gen-practice-catalog/gen_practice_girl_catalog.ts 重新產生",
  );
});
