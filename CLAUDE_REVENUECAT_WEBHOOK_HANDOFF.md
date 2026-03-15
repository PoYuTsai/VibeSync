# RevenueCat Webhook Fix Handoff (for Claude Code)

## What We Observed

- Supabase Edge Function logs show repeated errors: `Invalid webhook authorization`.
- RevenueCat webhook events show Failure/Retrying.
- Example event type: `PRODUCT_CHANGE` contains both `product_id` and `new_product_id`.

## Root Cause (Most Likely)

- RevenueCat is sending an `Authorization` header value that does not exactly match what the Edge Function expects.
- Common mismatch: the RevenueCat field is the full header value, so it must be either:
  - `Bearer <secret>` (recommended)
  - or `<secret>` (now accepted after the patch below)

## Changes Already Applied In This Repo

File changed:
- `supabase/functions/revenuecat-webhook/index.ts`

Changes:
- Accept `Authorization: Bearer <secret>` OR `Authorization: <secret>`.
- Add safe debug logs on auth failure (no secret printed), and on missing `event`.
- Fix tier selection for `PRODUCT_CHANGE` by using `new_product_id` when present.
- Fix webhook log insert error handling (supabase-js returns `{ error }`, it does not throw).

## Patch (git diff)

```diffdiff --git a/supabase/functions/revenuecat-webhook/index.ts b/supabase/functions/revenuecat-webhook/index.ts index 49a8fe6..6516213 100644 --- a/supabase/functions/revenuecat-webhook/index.ts +++ b/supabase/functions/revenuecat-webhook/index.ts @@ -53,17 +53,43 @@ Deno.serve(async (req) => {        return jsonResponse({ error: "Server misconfigured" }, 500);      }   -    const authHeader = req.headers.get("Authorization") || ""; -    if (authHeader !== `Bearer ${webhookSecret}`) { -      console.error("Invalid webhook authorization"); +    const authHeaderRaw = req.headers.get("Authorization") || ""; +    const authHeader = authHeaderRaw.trim(); + +    const expectedBearer = `Bearer ${webhookSecret}`; +    const isAuthorized = authHeader === expectedBearer || authHeader === webhookSecret; + +    if (!isAuthorized) { +      console.error( +        "Invalid webhook authorization", +        JSON.stringify({ +          hasAuth: authHeader.length > 0, +          startsWithBearer: authHeader.startsWith("Bearer "), +          authLength: authHeader.length, +        }) +      );        return jsonResponse({ error: "Unauthorized" }, 401);      }   +    if (authHeader === webhookSecret) { +      console.warn( +        "Webhook authorization matched raw secret (missing 'Bearer ' prefix). " + +          "Update RevenueCat Authorization header value to: 'Bearer <secret>'." +      ); +    } +      const body = await req.json();      // Avoid logging full webhook payload (can contain sensitive subscriber info).        const { event } = body;      if (!event) { +      console.error( +        "No event in body", +        JSON.stringify({ +          bodyType: typeof body, +          bodyKeys: body && typeof body === "object" ? Object.keys(body) : null, +        }) +      );        return jsonResponse({ error: "No event in body" }, 400);      }   @@ -71,11 +97,19 @@ Deno.serve(async (req) => {        type,        app_user_id,        product_id, +      new_product_id,        entitlement_ids,        expiration_at_ms,      } = event;   -    console.log(`Event type: ${type}, User: ${app_user_id}, Product: ${product_id}`); +    const effectiveProductId = +      type === "PRODUCT_CHANGE" && new_product_id +        ? new_product_id +        : product_id; + +    console.log( +      `Event type: ${type}, User: ${app_user_id}, product_id: ${product_id}, new_product_id: ${new_product_id}` +    );        // app_user_id 是我們在 RevenueCat.login() 時傳入的 Supabase user id      if (!app_user_id || app_user_id.startsWith("$RCAnonymousID")) { @@ -99,7 +133,7 @@ Deno.serve(async (req) => {        case "PRODUCT_CHANGE":        case "UNCANCELLATION":        case "SUBSCRIPTION_EXTENDED": -        newTier = getTierFromProductId(product_id); +        newTier = getTierFromProductId(effectiveProductId);          shouldUpdate = true;          console.log(`Upgrading user ${app_user_id} to ${newTier}`);          break; @@ -174,16 +208,21 @@ Deno.serve(async (req) => {        // 記錄 webhook 事件到 logs 表（可選）      try { -      await supabase.from("webhook_logs").insert({ +      const { error: logError } = await supabase.from("webhook_logs").insert({          source: "revenuecat",          event_type: type,          user_id: app_user_id,          payload: body,          created_at: new Date().toISOString(),        }); -    } catch (logError) { -      // 記錄失敗不影響主流程 -      console.log("Failed to log webhook event (non-fatal):", logError); + +      if (logError) { +        // 記錄失敗不影響主流程 +        console.log("Failed to log webhook event (non-fatal):", logError); +      } +    } catch (unexpectedError) { +      // 意外例外（例如網路層） +      console.log("Failed to log webhook event (non-fatal):", unexpectedError);      }        return jsonResponse({
```

## Deploy / Verify

1. Ensure Supabase Edge Function secret is set:
   - `REVENUECAT_WEBHOOK_SECRET=<secret>`

2. In RevenueCat Webhook settings:
   - Set "Authorization header value" to: `Bearer <secret>`
   - (If you set it to `<secret>` only, it will still work but will log a warning.)

3. Deploy Edge Function:
   - Preferred: commit and push to `main` (GitHub Action `.github/workflows/deploy-edge-function.yml` will deploy with `--no-verify-jwt`).
   - Or deploy manually with Supabase CLI.

4. Verification:
   - Send a test event.
   - Trigger a real sandbox purchase change.
   - Supabase logs should show the event and should no longer show `Invalid webhook authorization`.