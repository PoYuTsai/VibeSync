# VibeSync Project

## Project Overview

VibeSync 是一款聊天輔助 SaaS App，幫助用戶提升與陌生朋友聊天的技巧。核心功能包括：
- 熱度分析 (Enthusiasm Gauge 0-100)
- 三種回覆建議 (延展/共鳴/調情)
- Needy 警示系統
- 1.8x 黃金法則字數控制

Target Audience: 願意投資自我提升的男性用戶

## Tech Stack

- **Frontend**: Flutter 3.x + Riverpod
- **Backend**: Supabase (Auth, PostgreSQL, Edge Functions)
- **AI**: Claude API (Haiku + Sonnet 混合策略)
- **Subscription**: RevenueCat
- **Local DB**: Hive (加密儲存)

## Development Conventions

### Code Style
- 使用 Flutter 官方 linting rules
- 檔案命名：snake_case
- Class 命名：PascalCase
- 每個 feature 使用 Clean Architecture (data/domain/presentation)

### Git Commit
- 使用繁體中文 commit message
- 格式：`[類型] 簡短描述`
- 類型：feat, fix, refactor, docs, test, chore

### Privacy First
- 對話內容永不上傳伺服器儲存
- API 請求處理完即丟
- 本地資料使用 AES-256 加密

## Core Rules (AI Prompt)

### 1.8x 黃金法則
回覆字數 ≤ 對方字數 × 1.8，這是最高指導原則

### 熱度策略對照
- 0-30 (冰點)：鏡像冷處理、抽離
- 31-60 (溫和)：引導式提問、拋餌
- 61-80 (熱情)：80% 鏡像、保持沉穩
- 81-100 (高熱)：推拉、適度挑戰

## Debugging Protocol

### When Bug Occurs
1. **記錄** - 立即在下方 Bugs & Fixes 區塊記錄
2. **分析** - 找出 root cause，不只是表面修復
3. **修復** - 寫測試驗證修復
4. **預防** - 更新此文件避免再犯

### Bug Report Format
```markdown
#### [YYYY-MM-DD] Bug 標題
**症狀**: 發生了什麼
**重現步驟**: 1. 2. 3.
**Root Cause**: 為什麼發生
**修復**: 怎麼修的
**預防**: 如何避免再犯
**相關檔案**: `path/to/file.dart:123`
```

### Common Pitfalls (累積中)
- [ ] Hive 未初始化就存取 → 確保 `StorageService.initialize()` 完成
- [ ] Riverpod provider 未 dispose → 使用 `autoDispose`
- [ ] 未處理 API error → 永遠 try-catch 外部呼叫
- [ ] Web 平台 secure storage 限制 → MVP 專注 mobile
- [ ] Edge Function 冷啟動 → 加 loading state + timeout 處理
- [ ] 訊息格式解析失敗 → 提供清楚錯誤訊息和格式範例

---

## Testing Strategy

### 測試分層
```
test/
├── unit/           # 純邏輯測試 (無 UI)
│   ├── services/
│   └── repositories/
├── widget/         # 單一元件測試
│   └── widgets/
└── integration/    # 完整流程測試
    └── flows/
```

### TDD 流程
1. **Red** - 先寫失敗的測試
2. **Green** - 寫最小程式碼讓測試通過
3. **Refactor** - 重構但保持測試通過

### 測試命名規範
```dart
test('should return cold level when score is 25', () { ... });
test('should throw exception when messages is empty', () { ... });
```

### 執行測試
```bash
# 全部測試
flutter test

# 特定檔案
flutter test test/unit/services/analysis_service_test.dart

# 含覆蓋率
flutter test --coverage
```

---

## Local Development

### 啟動 Demo
```bash
# Web (最快看效果)
flutter run -d chrome

# iOS Simulator
flutter run -d "iPhone 15 Pro"

# Android Emulator
flutter run -d emulator-5554

# 列出所有裝置
flutter devices
```

### Hot Reload vs Hot Restart
- **Hot Reload (r)**: 保留 state，快速更新 UI
- **Hot Restart (R)**: 重置 state，完整重啟

### Supabase 本地開發
```bash
# 啟動本地 Supabase (含 PostgreSQL, Auth, Edge Functions)
npx supabase start

# 本地 Dashboard
http://localhost:54323

# 停止
npx supabase stop
```

---

## Model Selection (Claude Code)

### 開發時使用模型建議
| 任務類型 | 建議模型 | 原因 |
|----------|----------|------|
| 簡單修 bug | Haiku | 快、便宜 |
| 寫新功能 | Sonnet | 平衡 |
| 架構設計 | Opus | 深度思考 |
| Code Review | Sonnet | 夠用 |

### 切換模型
```bash
# 在 Claude Code 中
/model sonnet
/model haiku
/model opus
```

---

## Lessons Learned

### Bugs & Fixes
<!-- 遇到 bug 時在此記錄，格式見上方 Debugging Protocol -->

### Design Decisions

#### [2026-02-26] 對話資料不上雲
**決定**: 對話歷史只存本地，伺服器不保留
**原因**:
1. 隱私風險最小化
2. GDPR 合規簡化
3. App Store 審核友善
4. 用戶信任度提升

#### [2026-02-26] 混合 AI 模型策略
**決定**: 70% Haiku + 30% Sonnet
**原因**:
1. 成本降低 60-70%
2. 簡單情境不需要大模型
3. 複雜情境保持品質

## Notes

- This file is auto-read by Claude Code at conversation start
- Update this file when encountering bugs or learning important patterns
- Design spec is in `docs/plans/2026-02-26-vibesync-design.md`
