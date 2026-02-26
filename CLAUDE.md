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

## Lessons Learned

### Bugs & Fixes
<!--
Format:
### [Date] Bug Title
**Problem:** Description of the bug
**Root Cause:** Why it happened
**Solution:** How it was fixed
**Prevention:** How to avoid this in the future
-->

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
