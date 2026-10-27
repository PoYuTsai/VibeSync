#!/usr/bin/env bash
# Edge 契約測試的唯一清單：PR CI（.github/workflows/flutter-ci.yml）與
# 部署前關卡（.github/workflows/deploy-edge-function.yml）共用，兩邊不另列。
#
# - 對話分析（analyze-chat）與共用模組（_shared）整個目錄都跑（2026-10-03 健檢
#   F21，Eric 2026-10-12 核准）。之前逐檔白名單漏掉 reframer、post_process、
#   stream_prompt、兩支 prompt 雜湊鎖等 42 支；新增測試檔不必再改這份清單。
# - submit-feedback 整個目錄也跑：漏斗購買事件的帳號比對要在部署前守住（Eric 2026-10-18）。
# - revenuecat-webhook 整個目錄也跑：付費 webhook 寫進 webhook_logs／revenue_events
#   的欄位（含取消原因）與訂閱判斷要在部署前守住（Onboarding 第 7 步）。在那之前
#   subscription_update_test.ts、tiers_test.ts 不在清單裡，付費 webhook 在 CI 沒有守門。
# - 其他函式維持逐檔列出，範圍跟改版前相同。其中 practice-chat 的
#   index_test.ts 與 prompt_test.ts 是 1:1 記憶接線（PR D）動到聊天主路徑時的
#   迴歸證據；在那之前這兩支不在清單裡，聊天主路徑在 PR CI 完全沒有守門。
# - PGlite（WASM Postgres）測試由 CI 的 Postgres 步驟另外跑，這裡用 --ignore
#   排除 analyze-chat 目錄裡的那幾支。
# - 權限只給 --allow-env --allow-read：測試不得寫檔、不得連網。npm／遠端模組
#   下載屬模組解析，不歸 --allow-net 管。
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

pglite_tests=(
  supabase/functions/analyze-chat/opener_two_stage_migration_postgres_test.ts
  supabase/functions/analyze-chat/retention_cleanup_migration_postgres_test.ts
  supabase/functions/analyze-chat/stream_runs_decision_kind_migration_postgres_test.ts
  supabase/functions/analyze-chat/opener_flow_handler_test.ts
)
ignore_list="$(IFS=,; echo "${pglite_tests[*]}")"

deno test --allow-env --allow-read \
  --ignore="${ignore_list}" \
  supabase/functions/analyze-chat \
  supabase/functions/_shared \
  supabase/functions/keyboard-reply \
  supabase/functions/submit-feedback \
  supabase/functions/revenuecat-webhook \
  supabase/functions/coach-chat/prompts_test.ts \
  supabase/functions/coach-chat/generation_test.ts \
  supabase/functions/coach-chat/validate_test.ts \
  supabase/functions/coach-chat/clarification_policy_test.ts \
  supabase/functions/practice-chat/moments_schedule_test.ts \
  supabase/functions/practice-chat/moments_migration_source_test.ts \
  supabase/functions/practice-chat/moments_slot_states_migration_source_test.ts \
  supabase/functions/practice-chat/moments_images_migration_source_test.ts \
  supabase/functions/practice-chat/moments_constants_test.ts \
  supabase/functions/practice-chat/moments_image_gate_test.ts \
  supabase/functions/practice-chat/moments_time_test.ts \
  supabase/functions/practice-chat/moments_prompt_test.ts \
  supabase/functions/practice-chat/moments_validate_test.ts \
  supabase/functions/practice-chat/moments_handler_test.ts \
  supabase/functions/practice-chat/moments_edge_contract_test.ts \
  supabase/functions/practice-chat/moments_generated_only_source_test.ts \
  supabase/functions/practice-chat/moments_dispatch_test.ts \
  supabase/functions/practice-chat/moments_image_gen_test.ts \
  supabase/functions/practice-chat/moments_image_flow_test.ts \
  supabase/functions/practice-chat/moments_image_sweep_test.ts \
  supabase/functions/practice-chat/visible_text_guard_test.ts \
  supabase/functions/practice-chat/moments_memory_test.ts \
  supabase/functions/practice-chat/time_context_test.ts \
  supabase/functions/practice-chat/index_test.ts \
  supabase/functions/practice-chat/agency_flag_off_equivalence_test.ts \
  supabase/functions/practice-chat/chat_model_routing_test.ts \
  supabase/functions/practice-chat/standard_agency_classifier_test.ts \
  supabase/functions/practice-chat/prompt_test.ts \
  supabase/functions/practice-chat/practice_persona_test.ts \
  supabase/functions/delete-account/cleanup_alert_test.ts \
  tools/practice-agency-eval/cache_probe_test.ts \
  tools/new-topic-two-stage-eval/run_test.ts
