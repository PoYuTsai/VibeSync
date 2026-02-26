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
