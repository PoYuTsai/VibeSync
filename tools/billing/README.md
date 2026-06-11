# ADR #19 計費鏡像 fixture 生成器

`test/fixtures/adr19_billing_mirror_vectors.json` 的生成腳本。
以 server 權威實作（`supabase/functions/analyze-chat/billing.ts`）生成
字數/分段帶/payload hash 期望值，Dart 端（`message_calculator_test.dart`）
與 JS 端（`billing_test.ts`）共同對拍。

`known_sha256_abc` 的 hash 是外部已知常數（sha256("abc")），釘死
SHA-256 演算法本身不被兩端同時改壞。

重新生成（改公式 / 加樣本後）：

```bash
cd tools/billing
deno run --allow-read gen_mirror_fixture.ts > ../../test/fixtures/adr19_billing_mirror_vectors.json
```

注意：fixture 變更必須跑兩端測試（`deno test` + `flutter test`）確認同步。
