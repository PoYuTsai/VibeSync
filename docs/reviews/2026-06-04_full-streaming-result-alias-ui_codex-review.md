# 2026-06-04 Full Streaming Result Alias + UI Fix Codex Review

Status: APPROVED
Scope: `analyze-chat` full streaming result finalization and mobile streaming/error card readability.

## Findings

- P0 resolved: streamed content could arrive successfully, but the final `analysis.done` payload path was too strict. If any layer emitted the legacy-compatible final payload under `result` instead of `finalResult`, the app treated the run as missing a complete result and showed `串流分析缺少完整結果，請重新分析。`
- P1 resolved: streaming content cards used semi-transparent light glass on the dark bokeh background, causing dark text to lose contrast on device screenshots.
- P2 resolved: the full-analysis retry card inherited default Material card styling and looked disconnected from the dark brand surface.

## Review Notes

- Server-side `reframer` now accepts `analysis.done.result` as a final result alias and merges it into the assembled legacy-compatible result.
- Server-side `stream_handler` now accepts `finalResult` or `result`, and emits both keys after persistence/post-processing so current and older clients have the same terminal payload.
- Flutter `AnalysisService.analyzeStream` now accepts `analysis.done.finalResult`, `analysis.done.result`, or legacy result-shaped events before parsing `AnalysisResult`.
- Streaming and retry cards now use solid dark-purple surfaces with white text and on-brand accents, avoiding the unreadable dark-on-transparent-glass state.

## Verification

- `deno test supabase\functions\analyze-chat\stream_handler_test.ts supabase\functions\analyze-chat\reframer_test.ts`
- `flutter test --no-pub test\unit\features\analysis\data\services\analysis_service_two_stage_test.dart test\widget\features\analysis\two_stage_loading_widgets_test.dart`
- `flutter analyze --no-pub lib\features\analysis\data\services\analysis_service.dart lib\features\analysis\presentation\widgets\two_stage_loading_widgets.dart test\unit\features\analysis\data\services\analysis_service_two_stage_test.dart`
- `flutter analyze --no-pub lib\features\analysis\presentation\screens\analysis_screen.dart`
- `flutter analyze --no-pub test\widget\features\analysis\two_stage_loading_widgets_test.dart test\widget\features\analysis\analysis_screen_hydration_test.dart`
- `flutter test --no-pub test\widget\features\analysis\analysis_screen_hydration_test.dart`

Note: `analysis_screen_hydration_test.dart` still prints an existing Hive box warning/stack trace from `CoachChatCard`, but exits with `All tests passed`.
