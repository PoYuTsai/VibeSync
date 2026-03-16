# VibeSync 頻率調校師

社交溝通技巧教練 App - 幫助用戶提升對話品質與人際互動能力。

## 功能特色

- **熱度分析** - 即時評估對話互動程度 (0-100)
- **智慧建議** - 三種回覆風格：延展、共鳴、調情
- **1.8x 黃金法則** - 維持健康的對話節奏
- **隱私優先** - 對話資料僅存於本地裝置

## 技術架構

| 層級 | 技術 |
|------|------|
| Frontend | Flutter 3.x + Riverpod |
| Backend | Supabase (Auth, PostgreSQL, Edge Functions) |
| AI | Claude API |
| Payment | RevenueCat |

## 開發環境設置

```bash
# 安裝 Flutter 依賴
flutter pub get

# 執行開發版本
flutter run

# 執行測試
flutter test
```

## 專案結構

```
lib/
├── features/       # 功能模組 (Clean Architecture)
│   ├── auth/
│   ├── conversation/
│   ├── analysis/
│   └── subscription/
├── core/           # 共用元件
└── shared/         # 共用 UI 元件
```

## 文件

- [設計規格書](docs/plans/2026-02-26-vibesync-design.md)
- [Claude Code 專案慣例](CLAUDE.md)

## 授權

Private - All Rights Reserved

## 2026-03-16 Hotfix Notes

- Reply analysis now works even when the latest message is from me. The app analyzes up to the latest incoming message instead of hard-blocking the flow.
- Screenshot import now preserves the recognized conversation in UI state and shows an `立即分析` action after successful import.
- Screenshot recognition is more tolerant of partial Claude JSON. If `messages` are present but `messageCount` is missing or malformed, the Edge Function now normalizes the payload instead of failing the whole request.
- Client-side API parsing now handles non-JSON responses more safely and surfaces recognition failures with clearer messages.
- AI logging now checks returned Supabase insert errors instead of assuming `insert()` will throw.
- Admin dashboard auth now uses server-side login/logout routes with an `HttpOnly` cookie instead of a client-readable token cookie.
- Feedback submission now validates category / payload shape, enforces length limits, and truncates Telegram previews to reduce oversharing.
- Local usage fallback now syncs tier/limits from the subscription provider instead of always pretending the user is free-tier.
- `analyze-chat` now validates request shape more strictly: message count/content, analyze mode, draft length, session context, image media types, and recognition-only misuse.
- `admin-dashboard` dependency audit is now clean (`npm audit` reports 0 vulnerabilities after lockfile-only fixes).
- RevenueCat webhook now distinguishes "updated 0 rows" from a real update, inserts missing subscription records safely, and initializes reset timestamps on first write.
- New subscription records now initialize `daily_reset_at` / `monthly_reset_at`, which avoids an unnecessary first-analysis reset write and keeps quota state more consistent.
- Booster purchase UI no longer fakes a successful purchase. It is now explicitly marked as coming soon until RevenueCat one-time purchase support is implemented.
- Screenshot OCR requests (`recognizeOnly`) now accept empty message history and no longer consume quota like a normal analysis request.
- `shared_preferences` is now declared directly in `pubspec.yaml`, and `flutter analyze` currently passes clean with the local Flutter toolchain.
- Conversation history now auto-generates heuristic summary segments for older rounds instead of storing only a placeholder summary.
- OCR-only requests strip the placeholder message before upload, `analyze-chat` now caps total image payload size, and feedback Telegram notifications are rebuilt with readable interpolated text.
- Conversation summaries now slice rounds by actual incoming-message boundaries instead of assuming a strict 2-message pattern, which makes older-context summaries more accurate when one side sends multiple messages in a row.
- Missing `subscriptions` rows now self-heal in both the app subscription loader and `analyze-chat`, so older or partially-migrated accounts are less likely to hit a hard `No subscription found` failure.
- Local verification now covers both sides of the stack: `flutter analyze` passes and the Supabase Edge Functions pass `deno check` with the locally installed Deno toolchain.
- Screenshot recognition no longer crashes when the import confirmation dialog is cancelled, and stale OCR results are ignored after the user cancels the flow.
- The screenshot picker now returns copied image lists instead of sharing the same mutable list instance with the parent screen.
- The legacy `rate_limiter.ts` helper now self-heals missing `subscriptions` / `rate_limits` rows, clamps remaining counts to non-negative values, and reuses the canonical `increment_usage` RPC for quota updates.

See `CLAUDE_CODE_HANDOFF_2026-03-16.md` for the full review summary, outstanding risks, and Claude Code notes.
