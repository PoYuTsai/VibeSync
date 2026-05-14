# !cc-rotate — Discord 遠端 session rotation 設計

> **狀態**：v1 已實作，Codex review 補強中 · **作者**：Claude (Opus 4.7, 1M ctx) · **日期**：2026-05-14
> **來源**：brainstorming dialog（Q1-Q4 4 個決策節點）· **位於 Phase plan 中**：Phase 1

---

## Background / Goal

VibeSync 用戶（Eric）外出模式靠手機 Discord 操控 host 上的 Claude Code。受限於：

1. `/clear` 是 Claude Code CLI 層指令，只能本地終端觸發 — Discord 訊息打「/clear」對模型只是普通文字
2. Context 達 45% 會被 green-context hook 強制阻擋（hard stop）
3. Bridge 用 MCP 機制跑，Plugin 是 Claude Code 的 MCP child — plugin 不能 kill 自己 parent 還活下來

**結論**：手機 DC 沒辦法清 context、也沒辦法從 plugin 內部 rotate。唯一可行解 = 外層 supervisor wrap 整條啟動鏈，由 supervisor 負責 kill 舊 / spawn 新。

**Goal**：用戶在手機 DC 打 `!cc-rotate` → 安全結束舊 session → 自動開乾淨新 session → 新 session 載入 handoff context → DC 回「ready」。

**v1 實測補充**：Claude Code 的 `SessionStart` hook 只注入 context，不保證會自動產生一輪模型回覆。因此 v1 同時用 `UserPromptSubmit` fallback：若新 session 起來後 30 秒內沒有 ready，Eric 在 DC 補一句 `ready?` 或任何下一步訊息，hook 會在 `cc-rotate.bootstrap.json` 尚存在時重新注入 bootstrap，要求新 session 先讀 handoff、回 ready、刪 bootstrap，再處理新任務。

---

## v1 Scope discipline：**只有一個 Discord 指令**

**v1 唯一 Discord 指令：`!cc-rotate`**。不新增、不實作、不在主要流程提其他 `!cc-*` 命令（特別是 `!cc-handoff`）。

**`!cc-rotate` 必須內建完整 handoff 行為**：

```
!cc-rotate（單一指令）
  = validation
  + handoff（強制執行 + 驗 mtime）
  + 寫 cc-rotate.request.json
  + 等 supervisor SIGTERM
  + spawn 新 session
  + bootstrap 讀 handoff
```

**設計後果**：

1. 失敗訊息**不**給「只跑 handoff，不殺 session」的分支選項 — 那等於 `!cc-handoff`，違反 v1 single-command
2. Context reminder 跟隨統一 green-context bands（30-40% yellow、40-45% orange、45%+ hard stop；高風險工作 35%+ 直接 orange），只說「建議準備 `!cc-rotate`」，**不**讓用戶選 handoff vs rotate
3. 用戶手機只需要記一個指令、做一個動作 — 後果與替代方案都由 host 端決定，**不**把判斷推給手機螢幕
4. `!cc-handoff` 若有需要 → 一律進 Phase 2 / Future Work（見下方 Phase plan），v1 絕不實作

**為什麼**：手機輸入成本高、判斷負擔重；單指令、零判斷是外出模式的核心 UX 原則。把 handoff 包進 rotate 而非平行存在，是刻意的 scope discipline，不是漏設計。

---

## Decisions（brainstorming Q1-Q4 結論）

### D1. 命名：`!cc-rotate`

延續 `docs/discord-codex-command-bridge-design.md` 的 bridge command convention。

**理由**：
1. `!` 前綴專屬 Discord bridge 命令；`/` 保留給 Claude Code UI slash commands（避免 namespace 衝突）
2. Rotate 本質是 **bridge / supervisor 層**行為，不是 Claude Code 內部 slash command
3. `rotate` 比 `clear` 語意更精準 — 換 process 不是清原 process

**否決選項**：`/cc-rotate`、`/cc-clear`、`!cc-clear`

### D2. 位置：C-lite（repo 管邏輯，channel runtime 管本機環境）

| 內容 | 位置 | Git tracked |
|------|------|-------------|
| Supervisor、validate、bootstrap hook、prompt template | `tools/cc-rotate/`（repo） | ✅ |
| Per-machine config（repo path、claude 啟動命令、signal path） | `~/.claude/channels/discord-vibesync/cc-rotate.local.env` | ❌ |
| Config 範本 | `tools/cc-rotate/cc-rotate.local.env.example` | ✅ |

**硬規則**：
- 🚫 絕對路徑 / token / 私有 ID 絕不進 repo
- 🚫 絕不改 plugin cache (`~/.claude/plugins/cache/...`) — plugin 更新會覆蓋
- ✅ Repo 邏輯可 review、可跨機器；channel runtime 配置 per-machine

### D3. Validation 矩陣

#### 🔴 HARD BLOCK（任一為 true → 拒絕 rotate）

**外部可檢（validate.sh）**

| Code | 條件 | 偵測方式 |
|------|------|---------|
| B1 | git working tree 髒（modified / staged / untracked tracked files） | `git status --porcelain` 非空 |
| B2 | mid-rebase / mid-merge | `.git/REBASE_HEAD` / `MERGE_HEAD` 存在 |
| B3 | 本地有未 push commit | `git status -sb` 顯示 "ahead" |
| B4 | 另一 rotate 進行中 | `cc-rotate.lock` 存在 |

**內部自我盤點（current session 回報）**

| Code | 條件 | 偵測方式 |
|------|------|---------|
| B5 | TodoWrite 有 `in_progress` 項 | 內部狀態 |
| B6 | 有 `run_in_background` Bash 仍 alive | 內部狀態 |
| B7 | 有 background Task agent 未回報 | 內部狀態 |
| B8 | 在 plan mode（ExitPlanMode 未呼叫） | 內部狀態 |
| B9 | Pending permission request | 內部狀態 |
| B10 | Active long-running command（test/build/deploy/archive/export，含非 background） | Session 自我誠實答 yes/no |

#### 🟡 WARN（允許 rotate，寫進 handoff context）

| Code | 條件 |
|------|------|
| W1 | ScheduleWakeup pending |
| W2 | 最後 commit < 5 分鐘前 |
| W3 | 在 superpowers skill 的 checklist 中途 |

#### 🟢 IGNORE（不檢查）

- Repo 外 untracked file
- Git stash
- Context %（紅線時就是要 rotate，不能因為 context 高就阻擋）

#### 失敗訊息格式

```
❌ !cc-rotate 拒絕。原因：
  - B1: 3 個未 commit 變更（tools/foo.dart, docs/bar.md, ...）
  - B5: TodoWrite 有 2 個 in_progress 項

下一步：
  - 解 B1：在 host 端執行 git commit -am "..." && git push
  - 解 B5：等 in_progress 任務完成
  - 全部解掉後，DC 重打 !cc-rotate
```

**訊息不給 alternative 命令選項**（如「只跑 handoff」），遵守 v1 single-command discipline。失敗的修法一律是「解除 block 後重打 `!cc-rotate`」。

### D4. 訊號 + Bootstrap 機制

#### 訊號方式：JSON request file + `inotifywait` watch（可 fallback polling）

**為何不用 SIGUSR1**：之後可能加 `!cc-restart` / `!cc-pause` 等命令，structured payload 比訊號可擴展。

**為何優先用 `inotifywait`**：`inotifywait -e create` 零延遲、零 CPU。若 host 未安裝 `inotify-tools`，v1 supervisor 會 fallback 到短輪詢，避免外出模式因缺一個套件整個不能啟動。

#### 舊 session → supervisor 傳遞

舊 session 寫 `cc-rotate.request.json`：

```json
{
  "type": "rotate",
  "ts": "2026-05-14T12:34:56+08:00",
  "old_pid": 12345,
  "discord_channel_id": "...",
  "discord_user_id": "...",
  "handoff_path": "/home/<linux-user>/.claude/projects/.../reference_session_handoff_latest.md",
  "head_commit": "abc1234",
  "warnings": ["W1: ScheduleWakeup 已排 5 分鐘後喚醒"]
}
```

#### 新 session bootstrap：SessionStart hook + bootstrap.json

Supervisor 把 `request.json` rename 為 `cc-rotate.bootstrap.json`，新 claude 啟動時 SessionStart hook 讀它注入 system context。

**新 session 第一回合執行順序**（bootstrap prompt 寫死）：

1. Read `AGENTS.md`
2. Read `docs/shared-agent-rules.md`
3. Read `docs/snapshot.md`
4. Read handoff_path（從 bootstrap.json 取）
5. Run `git log --oneline -5` && `git status`
6. （Optional）若便宜：用 grep 抓 `docs/bug-log.md` 最後 5 條摘要 — 不便宜就 skip
7. Discord reply：`✅ New session ready. HEAD <hash>. Read handoff with N open loops: <list>. Awaiting next task.`
8. Delete `cc-rotate.bootstrap.json`

步驟 1-5 可並行。步驟 6 由 hook 內部決定要不要塞進 prompt（取決於 grep 成本，若 bug-log 超過 200 行就 skip）。

不加：
- ❌ `git fsck`（太重，false positive 多）
- ❌ 完整 `docs/bug-log.md`（重，新 session 不需要 18 條全載入）

#### 舊 session 處理 `!cc-rotate` 協議（寫進 AGENTS.md + UserPromptSubmit hook 雙保險）

```
When Discord message body matches /^!cc-rotate(\s|$)/:
  1. 立即 reply DC："🔄 Validating rotate conditions..."
  2. exec tools/cc-rotate/validate.sh → exit code + JSON report
  3. 自我盤點 B5-B10
  4. 若任何 HARD BLOCK → reply DC 完整失敗訊息（下一步指引解 block 後重打），STOP
  5. 若有 WARN → 把 warn list 帶入 handoff context
  6. Invoke handoff skill（寫 reference_session_handoff_latest.md）
  7. 驗 handoff 檔 mtime ≤ 60 秒 — 否則退出 rotation 回報失敗
  8. 寫 cc-rotate.request.json（含 channel_id / handoff_path / HEAD / warnings）
  9. Reply DC："✅ Handoff OK. Rotating in ~5s. New session will read it."
 10. 不再接受新指令，等 supervisor SIGTERM
```

**UserPromptSubmit hook** 雙保險：

1. 若 `cc-rotate.bootstrap.json` 仍存在 → 重新注入 bootstrap prompt，因為 `SessionStart` 只提供 context，不保證自動開一輪模型回覆。
2. 否則每次 prompt 進入時若內容含 `!cc-rotate` → 注入系統訊息「🔄 You just received !cc-rotate. Follow rotation protocol from AGENTS.md section X」。避免 me 看到 `!cc-rotate` 當成普通對話。

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ ~/.claude/channels/discord-vibesync/   (per-machine, NOT in git)│
│                                                                 │
│   start.sh                                                      │
│      └─ source cc-rotate.local.env                              │
│      └─ exec $VIBESYNC_REPO/tools/cc-rotate/supervisor.sh       │
│                                                                 │
│   cc-rotate.local.env                                           │
│     VIBESYNC_REPO=/mnt/c/.../VibeSync                           │
│     CC_ROTATE_DIR=/home/<linux-user>/.claude/channels/discord-vibesync │
│     CLAUDE_CMD="claude --dangerously-skip-permissions \         │
│                  --channels plugin:discord@claude-plugins-..."  │
│     HANDOFF_DIR=/home/<linux-user>/.claude/projects/<project-slug>/memory │
│                                                                 │
│   cc-rotate.request.json   ← transient, written by old session  │
│   cc-rotate.bootstrap.json ← transient, written by supervisor   │
│   cc-rotate.lock           ← presence = rotation in flight      │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│ $VIBESYNC_REPO/tools/cc-rotate/   (in repo, git tracked)        │
│                                                                 │
│   supervisor.sh            ← outer loop, spawn claude, watch sig│
│   validate.sh              ← external validation (B1-B4)        │
│   bootstrap-hook.sh        ← SessionStart hook contents         │
│   user-prompt-hook.sh      ← UserPromptSubmit hook contents     │
│   bootstrap-prompt.tmpl    ← template for new-session prompt    │
│   cc-rotate.local.env.example ← template for D2 config          │
│   README.md                ← setup + maintenance notes          │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│ Repo root + docs (in repo, git tracked)                         │
│                                                                 │
│   AGENTS.md       ← + "## Rotation Protocol (!cc-rotate)" 段    │
│   CLAUDE.md       ← 同步同段（pre-commit hook 守 sync）        │
│   .gitignore      ← + "*.local.env"                             │
│   docs/plans/2026-05-14-cc-rotate-design.md  ← 本文件            │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│ ~/.claude/settings.json  (per-machine, NOT in git)              │
│                                                                 │
│   hooks:                                                        │
│     SessionStart → $VIBESYNC_REPO/tools/cc-rotate/bootstrap-hook.sh │
│     UserPromptSubmit → $VIBESYNC_REPO/tools/cc-rotate/user-prompt-hook.sh │
└─────────────────────────────────────────────────────────────────┘
```

### Flow diagram

```
  ┌──────────────┐
  │ 手機 DC      │
  │ "!cc-rotate" │
  └──────┬───────┘
         │
         ▼  (Discord plugin 照常 relay 為 MCP notification)
  ┌─────────────────────────────────────────────────────┐
  │ Claude Code 舊 session — me                         │
  │ UserPromptSubmit hook 偵測 !cc-rotate → 注入 SOP    │
  │  Step 1: reply DC "🔄 Validating..."                │
  │  Step 2-3: validate.sh + 自我盤點 B5-B10            │
  │  Step 4: 若 FAIL → reply DC（解 block 後重打）+ STOP│
  │  Step 5: 若 WARN → record into handoff context     │
  │  Step 6-7: handoff skill + mtime verify             │
  │  Step 8: 寫 cc-rotate.request.json                  │
  │  Step 9: reply DC "✅ Rotating..."                  │
  │  Step 10: wait for SIGTERM                          │
  └──────────┬──────────────────────────────────────────┘
             │
             │ (inotifywait or polling sees request.json)
             ▼
  ┌─────────────────────────────────────────────────────┐
  │ supervisor.sh                                       │
  │  1. read request.json                               │
  │  2. touch cc-rotate.lock                            │
  │  3. mv request.json → bootstrap.json                │
  │  4. SIGTERM child claude                            │
  │  5. wait (30s timeout, then SIGKILL)                │
  │  6. spawn new claude with $CLAUDE_CMD               │
  │  7. rm cc-rotate.lock                               │
  │  8. (loop back to inotifywait / polling)            │
  └──────────┬──────────────────────────────────────────┘
             │
             ▼
  ┌─────────────────────────────────────────────────────┐
  │ Claude Code 新 session                              │
  │ SessionStart hook reads bootstrap.json              │
  │  → inject system context with 8 first actions       │
  │ Me (new session):                                   │
  │  1-4. parallel reads (AGENTS, shared-rules,         │
  │       snapshot, handoff)                            │
  │  5. git log/status                                  │
  │  6. (optional) bug-log peek                         │
  │  7. DC reply "✅ ready, HEAD xxx, N open loops"    │
  │  8. rm bootstrap.json                               │
  └─────────────────────────────────────────────────────┘
```

---

## File inventory

### 新增（repo, git tracked）

- `tools/cc-rotate/supervisor.sh`
- `tools/cc-rotate/validate.sh`
- `tools/cc-rotate/bootstrap-hook.sh`
- `tools/cc-rotate/user-prompt-hook.sh`
- `tools/cc-rotate/bootstrap-prompt.tmpl`
- `tools/cc-rotate/cc-rotate.local.env.example`
- `tools/cc-rotate/README.md`
- `docs/plans/2026-05-14-cc-rotate-design.md`（本文件）

### 修改（repo, git tracked）

- `AGENTS.md` — 加 `## Rotation Protocol (!cc-rotate)` 段
- `CLAUDE.md` — 加同步段（指向 AGENTS.md 該段為單一真實來源）
- `.gitignore` — 加 `*.local.env`

### 新增（per-machine, NOT in git）

- `~/.claude/channels/discord-vibesync/cc-rotate.local.env`（從 example 複製 + 填值，`chmod 600`）

### 修改（per-machine, NOT in git）

- `~/.claude/channels/discord-vibesync/start.sh`（改成 source env + exec supervisor）
- `~/.claude/settings.json`（加兩個 hook）

---

## Failure modes & risks

### R1 — Plugin update 覆蓋
**狀態**：✅ 風險為零，因為我們完全不碰 plugin code

### R2 — `inotify-tools` 未安裝
**症狀**：監聽延遲從即時事件退回短輪詢
**Mitigation**：supervisor 只把 `jq` 視為 hard dependency；`inotifywait` 缺失時 warning 並 fallback polling，不阻擋 bridge 啟動

### R3 — `bootstrap.json` 殘留
**症狀**：新 session 啟動 crash / 沒走完 step 8 → 下次冷啟動誤觸 rotation context
**Mitigation**：bootstrap hook 加 TTL — 若檔案 mtime > 30 分鐘 → 視為 stale，刪掉並 echo「stale bootstrap discarded」。TTL 從 10 分鐘拉到 30 分鐘，因為 mobile flow 可能需要使用者看到「沒有 ready」後補一句 `ready?` 觸發 UserPromptSubmit fallback。

### R4 — Handoff skill 寫檔失敗
**症狀**：handoff context 過大被拒 / disk full → rotation 後新 session 沒 context
**Mitigation**：Step 7 強制驗 mtime ≤ 60s。失敗 → 退出 rotation，session 保留，reply DC 失敗

### R5 — SIGTERM 後 claude 卡住
**症狀**：舊 session 在等 Anthropic API → SIGTERM 可能要 10+ 秒
**Mitigation**：supervisor `wait` 30s timeout，超時 SIGKILL。可能留 plugin 殭屍 → 額外 `pkill -P $old_pid`

### R6 — Discord plugin 在新 process 拒絕連線
**症狀**：plugin 啟動 token 載入 + WS 連線需 ~3-5s
**Mitigation**：bootstrap prompt 第 7 步 reply DC — 若 timeout，supervisor 不會偵測。若 SessionStart 沒自動觸發模型回覆，UserPromptSubmit fallback 會在下一則 Discord 訊息重新注入 bootstrap。

### R7 — 雙 rotate 並發（誤觸或網路重送）
**Mitigation**：B4 lock file。第二次直接 reject。Supervisor 完成後刪 lock

### R8 — 新 session 不認得 bootstrap context
**症狀**：AGENTS.md 沒寫 protocol / hook 失效 → bootstrap context 被當普通系統訊息
**Mitigation**：bootstrap prompt 用 `🔄 ROTATION BOOTSTRAP — YOUR VERY FIRST ACTIONS` 強烈 prefix；整合測試覆蓋；`UserPromptSubmit` fallback 在 manifest 存在時優先注入 bootstrap，避免新 session 空轉。

---

## Phase plan

### Phase 1（本次 ship）

D1-D4 全部。**v1 不做 force flag**（任一 hard block 觸發 → 直接拒絕）。

### Phase 2（未來可選；v1 絕不做）

- `!cc-rotate --force`：二次確認流（DC 回「確定？回 yes 5 秒內」），仍強制 handoff
- `!cc-status`：查當前 session 健康度（context%、active tasks、最後 commit）
- `!cc-handoff`：**只寫 handoff、不殺 session 的獨立指令**。v1 刻意不做，因為違反 single-command discipline — 多一個指令 = 多一層手機判斷負擔。要在 Phase 2 引入時，需先評估「為何 v1 的『rotate 內建 handoff』不夠用」
- 自動 rotate：依 unified green-context bands 主動觸發（要考慮是否打擾進行中工作）

### Phase 3（更遠）

- 整合 `!codex` bridge 用同一個 command framework
- 多 channel support — 把 cc-rotate 抽象成 `~/.claude/tools/cc-rotate/`，跨 channel 共用

---

## v1 明文不做（避免被討好性 scope creep）

| 項 | 為何不做 |
|----|---------|
| ❌ `!cc-handoff` 獨立指令 | 違反 v1 single-command discipline；`!cc-rotate` 已內建 handoff |
| ❌ 任何 `!cc-*` 命令（除 `!cc-rotate`） | 同上；多指令 = 多手機判斷 = 違反外出模式 UX 原則 |
| ❌ 失敗訊息給「handoff-only」分支 | 同上；不讓用戶在手機選 handoff vs rotate |
| ❌ Context reminder 提 handoff 選項 | unified green-context bands 只說「建議準備 `!cc-rotate`」 |
| ❌ `--force` flag | 手機誤觸成本太高；要做請走 Phase 2 二次確認 |
| ❌ 自動 rotate | v1 user 主動觸發；自動觸發要先觀察 v1 行為 |
| ❌ 改 plugin cache | 絕對紅線 |
| ❌ 跨 channel 共用 | 等真有第二個 channel 再抽象（YAGNI）|
| ❌ Web/Desktop push notification | 手機 DC 是唯一觸發點 |
| ❌ 加密 `cc-rotate.local.env` | `chmod 600` 已足夠 |
| ❌ Session-level rate limit | 你不會自己 spam 自己 |

---

## Test plan

### 單元測試（validate.sh）

| Case | Setup | Expected |
|------|-------|----------|
| Clean | tidy tree, pushed, no rebase, no lock | exit 0, JSON 空 |
| B1 dirty | `echo x > foo.txt` | exit 1, JSON.B1 = list |
| B2 mid-rebase | 模擬 `.git/REBASE_HEAD` | exit 1, JSON.B2 = true |
| B3 ahead | local commit unpushed | exit 1, JSON.B3 = N commits |
| B4 lock | `touch cc-rotate.lock` | exit 1, JSON.B4 = true |
| Combo | B1 + B3 同時 | exit 1, JSON 包含兩條 |

### 整合測試（手動，第一次 ship 必跑）

1. **Clean rotate**：clean tree + 無 active task → `!cc-rotate` → 新 session < 30s 在 DC 回 "ready"；若無自動 ready，DC 補一句 `ready?`，應由 UserPromptSubmit fallback 完成 bootstrap
2. **B1 攔截**：故意改一檔不 commit → `!cc-rotate` → DC 收 B1 訊息
3. **B3 攔截**：commit 但不 push → `!cc-rotate` → DC 收 B3 訊息
4. **B5 攔截**：session 有 TodoWrite in_progress → `!cc-rotate` → DC 收 B5 訊息
5. **Handoff 驗證**：rotate 後讀 `reference_session_handoff_latest.md`，HEAD / open loops / 下步 / 風險都齊
6. **Bootstrap 驗證**：新 session 首 reply 涵蓋 1-8 actions
7. **R3 stale bootstrap**：手動放 30 分鐘前 bootstrap.json，啟動 claude → 應 ignore 且刪除
8. **B4 並發**：lock 存在時打第二個 `!cc-rotate` → 立即 reject

### 測試覆蓋限制

- R5（API 慢回應 + SIGTERM）：無法自動，靠運維觀察
- R6（DC gateway 重連時序）：無法自動，靠手動 timing 觀察

---

## 後續維護觸發點

- 改 supervisor / validate / bootstrap → 必跑整合測試 1-8
- 改 AGENTS.md 的 rotation protocol → pre-commit hook 應自動同步到 CLAUDE.md
- Phase 2 加 force flag → 必更新本文件 + 寫 ADR 記錄
- Phase 3 抽象到 `~/.claude/tools/` → 必 deprecate `tools/cc-rotate/`，repo 留 readme 指向新位置

---

## Codex review gate（強制，v1 ship 前必過）

實作完成後**必須**交 Codex review。理由（per VibeSync `CLAUDE.md` 分工原則「OCR / 演算法 / 效能 / 重構 plan / process supervisor → Codex 主導 review」）：

1. **Process 管理風險**：`supervisor.sh` 涉及 SIGTERM / SIGKILL / spawn child / wait timeout — 任一 race condition 都會壞掉 bridge runtime
2. **訊號與檔案系統**：`inotifywait` / polling fallback + JSON file 之間的時序（write-fsync vs event fire vs supervisor read）容易有 race
3. **Hook 互動**：SessionStart hook 與 UserPromptSubmit hook 與 me 三方的執行順序保證
4. **Discord reply 副作用**：失敗 mid-rotation 時，DC 可能只收到「Validating...」沒收到結果 — 用戶以為卡住

### Codex review 必查清單（寫進 `docs/reviews/` 對應 review 檔）

- [ ] **Race**：舊 session 寫 `request.json` 與 supervisor `inotify` / polling 讀取之間是否需要 fsync？
- [ ] **Race**：supervisor SIGTERM 後，舊 session 在 `wait` timeout 前若先自己 exit，supervisor `wait` 行為？
- [ ] **Race**：新 session SessionStart hook 讀 `bootstrap.json` 與新 session 處理第一個 Discord message 是否可能順序顛倒？
- [ ] **Cleanup**：rotation 中途 supervisor 自己 crash 時，lock / request / bootstrap 殘留如何清？
- [ ] **R3 TTL**：bootstrap.json TTL 10 分鐘的判斷邏輯是否經得起 clock skew / NTP 跳？
- [ ] **R5 zombie**：SIGKILL 後 plugin child 是否真的被 `pkill -P` 殺乾淨？
- [ ] **Idempotency**：用戶連打兩次 `!cc-rotate`，B4 lock 之外的保護？
- [ ] **Hook 載入**：`UserPromptSubmit` hook 偵測 `!cc-rotate` 注入提醒是否會跟既有 hooks 衝突？
- [ ] **Error path**：handoff skill 失敗（disk full / context too large）時，DC 是否一定收得到失敗訊息？
- [ ] **Shell quoting**：所有 bash 變數展開有沒有正確 `"$VAR"` 防 word splitting？

Codex review verdict 流程依 VibeSync CLAUDE.md 既有規則：🔴 / 🟡 → 直接改；🟠 → Eric 拍板；🟢 → 建議不動。

---

## 開發任務拆分（供 TaskCreate / 實作 session 參考）

1. 建 `tools/cc-rotate/` 骨架 + README + .env.example + .gitignore 更新
2. 寫 `validate.sh`（B1-B4 + JSON output）
3. 寫 `bootstrap-prompt.tmpl`（8 first actions 模板）
4. 寫 `bootstrap-hook.sh`（SessionStart：讀 bootstrap.json + TTL check + 注入 context）
5. 寫 `user-prompt-hook.sh`（UserPromptSubmit：偵測 !cc-rotate + 注入 protocol reminder）
6. 寫 `supervisor.sh`（outer loop + inotifywait/polling + SIGTERM/spawn）
7. 更新 `AGENTS.md` + `CLAUDE.md`（加 Rotation Protocol 段）
8. （手動）安裝 `jq`（`inotify-tools` 建議但非必需）、寫 `cc-rotate.local.env`、改 `start.sh`、改 `~/.claude/settings.json`
9. 跑單元測試 + 整合測試 1-8
10. Commit + push（按 VibeSync 「commit 後立即 push」規則）

---

## 補充：本設計**取代不了**的東西

`!cc-rotate` 解決「外出模式 context 紅線」**單一**問題。不解決：

- 手機 CLI 操作體驗（要 SSH + Tailscale 才能完整代替終端）
- 多 task 並行（一次仍只有一個 claude）
- 安裝 / 配置（仍需本機 setup 一次）
- 跨 repo（v1 hardcode VibeSync）

這些是 Phase 2/3 的範圍。

---

**v1 已實作；後續以實機整合測試與 Codex review findings 推進。**
