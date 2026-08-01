# Splash 縮短＋全域教練＋訪客模式 設計檔

> 2026-08-01 brainstorm 定案。來源：onboarding 轉化診斷（外部報告 2026-07-31）Tier 3 #11（Splash）
> 與 Tier 2 拍板時劃出的兩個另案（全域教練 (b)、訪客模式）。
> 報告 Tier 3 #9（報告分頁上鎖）、#10（付費牆感官）**不在本設計**——等漏斗數據（≥2026-08-08）再排。

## 拍板紀錄（Eric 2026-08-01）

- Splash＝縮短到約 2 秒（不做「只有首次播完整版」、不做邊播邊初始化、不維持 3.5 秒）。
- 全域教練入口＝首頁「問教練」卡升級成直接進全域教練對話（不另加入口、不做 bottom tab）。
- 訪客深度＝能真用核心功能、少量額度（不做純 demo 逛逛版、不給完整 30/月）。
- 訪客額度＝**3 則總量**（不按月重置）。
- 強制註冊觸發點＝訪客額度用完／要付費訂閱／要開跟進提醒（三者皆是）。
- 批次與順序＝**批 A（Splash＋全域教練）先做、一顆 build 給 Bruce dogfood；批 B（訪客模式）獨立成案接續**，不混同批。

## 批 A-1｜Splash 縮短（純 client、低風險）

現況：`splash_screen.dart:136-161` `_startAnimationSequence` 硬寫死序列——
標題 0s → 副標題 1.0s → shimmer 1.8s → 圓點 2.0s → `onComplete` 3.5s。

改法：整條時間軸等比壓縮到總長約 2 秒（標題入場 controller 1.6s → 約 0.9s，
後續節點跟著提前）。光球背景動畫（repeat）不動。零邏輯改動。

驗證：widget test 鎖「`onComplete` 在 ≤2 秒內被呼叫」防回歸（動畫 repeat 已有嚴格 gate 慣例，
測試用 `pump` 步進不可 `pumpAndSettle` 光球）。

## 批 A-2｜全域教練（client＋Edge，R2 跨模型審查，無 migration）

### Client

- `CoachScope`（`coach_scope.dart`）加第三種 type `global`（`CoachScopeType` 新增常數，
  既有 `conversation`／`partner` 的 Hive 持久化值絕不動），id 用固定哨兵值。
- coach 歷史統一 box 以 scope 為 key → 全域對話串的持久化、隱私清除 cascade、
  額度計費（沿用 coach_chat scope）全部自動沿用，不新開儲存、不開新額度池。
- 新路由 `/coach`：全螢幕頁掛現有 `CoachSurface`、餵 global scope。
  空狀態＝Sydney 打招呼＋2-3 個引導問句。
- 首頁「問教練」卡 onTap 從「導最近對象跟進區」改成 `context.push('/coach')`。
  對象頁內跟進區、`followUpDeepLink` 完全不動。

### Edge（coach-chat）

- `schemas.ts` scope 白名單加 `{ type: "global" }`；`deriveCoachScopeKey` 認得 global。
- `prompts.ts` 加全域變體：無對象上下文；注入「使用者風格設定」（關於我，
  `buildForCoachFollowUp` 現成管線）；問到特定對象時 prompt 指示引導用戶去對象頁跟進區。
- **v1 邊界：不餵對象資料**（不讀對象卡／分析紀錄）。

### 驗證與交付

- client：scope／route／首頁卡導向 widget test；Edge：schema＋prompt Deno test。
- Edge 改動走跨模型審查（R2）後才 push；push main 即自動部署，盯 push-triggered workflow。
- dogfood（Bruce）：啟動變快體感／首頁問教練直接能聊／填過關於我的帳號感受到個人化。

## 批 B｜訪客模式（R3，獨立成案＋跨模型雙審，本設計先落規格）

### 動線

登入頁加「先逛逛，不用註冊」→ Supabase 匿名登入（後台需開啟 anonymous sign-ins）→
onboarding → 首頁。訪客對 app 是真帳號（有 uid／session），redirect gate、
Hive 帳號分區、埋點照常運作；改動集中在「哪些動作要擋」。

### 額度

- server 端對匿名帳號（JWT `is_anonymous`）改用訪客額度：**總量 3 則，不按月重置**。
- 用完彈**註冊卡**（「註冊解鎖每月 30 則免費額度」），不是付費牆——Free 鐵則的訪客版。
- 首頁額度小條對訪客顯示「訪客額度剩 N 則」。

### 註冊觸發（三處都導註冊頁）

額度用完／點訂閱付費／開跟進提醒。

### 轉正

- 註冊走 Supabase **identity linking**（匿名帳號綁 email 或 Apple/Google），**uid 不變**——
  對象卡、分析紀錄、關於我、額度用量、RevenueCat 歸屬全部無縫延續，零資料搬移。
- 例外：「登入已有帳號」uid 會換，訪客資料不帶過去，介面明講。v1 不做合併。

### 防刷

session 存 iOS keychain，刪 app 重裝後仍在 → 同一匿名帳號、額度不重置。
重置整支手機才能刷新 3 則——風險接受（額度僅 3 則）。

### 風險定位

動 auth gate（`resolveAppRedirect`＋redirect matrix 測試矩陣）＋Edge 額度＋
可能一條 migration＝R3。獨立成案、跨模型雙審。dogfood 腳本：刪 app 裝新版 →
不註冊玩到額度用完 → 撞註冊卡 → 註冊 → 確認訪客期間資料都在。

## 不做／邊界

- 報告分頁上鎖、付費牆感官：等漏斗數據另案。
- 全域教練 v1 不餵對象資料；不做 bottom tab。
- 訪客資料與既有帳號的合併（登入路徑）：v1 不做。
- T2-7（OCR 相片權限預熱）維持撤案。
