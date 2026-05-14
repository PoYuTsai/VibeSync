# cc-rotate — Discord 遠端 session rotation

> 設計來源：[`docs/plans/2026-05-14-cc-rotate-design.md`](../../docs/plans/2026-05-14-cc-rotate-design.md)
> v1 唯一指令：`!cc-rotate`（手機 Discord 輸入）

---

## 一句話

外出模式手機 DC 打 `!cc-rotate` → host 上的 Claude Code 安全交接（validate → handoff → 殺舊 → spawn 新）→ 新 session 載入 context → DC 回 "ready"。

---

## 檔案清單

| 檔 | 角色 | 執行於 |
|----|------|--------|
| `supervisor.sh` | 外層守護迴圈，spawn claude / 偵測 rotate 訊號 / 殺舊 / 啟新 | 取代 `start.sh` 的 entry point |
| `validate.sh` | 外部 hard block 檢查（B1-B4），JSON 輸出 + exit code | 由舊 session 在 rotate 前呼叫 |
| `bootstrap-hook.sh` | SessionStart hook，讀 `bootstrap.json` 注入 system context（含 TTL stale check）| Claude Code 每次啟動時 |
| `user-prompt-hook.sh` | UserPromptSubmit hook，偵測 `!cc-rotate` 注入 protocol 提醒 | 每次 user prompt 進來時 |
| `bootstrap-prompt.tmpl` | 新 session 第一回合的 prompt 模板 | 由 bootstrap-hook 展開使用 |
| `cc-rotate.local.env.example` | Per-machine 配置範本 | 複製到 channel runtime 後填值 |

---

## Per-machine setup（**Eric 手動，一次性**）

### 步驟 1：安裝依賴

```bash
sudo apt update && sudo apt install -y inotify-tools jq
```

`inotify-tools` 給 supervisor 用、`jq` 給 validate / hook 處理 JSON 用。

### 步驟 2：建立本機 config

```bash
cp /mnt/c/Users/eric1/OneDrive/Desktop/VibeSync/tools/cc-rotate/cc-rotate.local.env.example \
   ~/.claude/channels/discord-vibesync/cc-rotate.local.env
chmod 600 ~/.claude/channels/discord-vibesync/cc-rotate.local.env
```

開檔填四個必填欄位（範本內有註解）。

### 步驟 3：改 channel runtime 的 `start.sh`

備份原本的 `start.sh`，改成：

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cc-rotate.local.env"
exec "$VIBESYNC_REPO/tools/cc-rotate/supervisor.sh"
```

### 步驟 4：註冊 hooks 到 `~/.claude/settings.json`

合併以下到 `~/.claude/settings.json`（**不是** `.claude/settings.local.json`）：

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "/mnt/c/Users/eric1/OneDrive/Desktop/VibeSync/tools/cc-rotate/bootstrap-hook.sh"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "/mnt/c/Users/eric1/OneDrive/Desktop/VibeSync/tools/cc-rotate/user-prompt-hook.sh"
          }
        ]
      }
    ]
  }
}
```

絕對路徑要對應你本機（與 `cc-rotate.local.env` 的 `VIBESYNC_REPO` 一致）。

### 步驟 5：重啟 bridge

```bash
# 殺舊 bridge
pkill -F ~/.claude/channels/discord-vibesync/bridge.pid 2>/dev/null || true
# 用新 start.sh 重啟
~/.claude/channels/discord-vibesync/start.sh
```

從手機 DC 確認新 session 起來能正常聊天。

---

## 驗證（手動整合測試 1-8）

完整測試在 [design doc 的 Test plan 段](../../docs/plans/2026-05-14-cc-rotate-design.md#test-plan)。最低必跑：

1. **Clean rotate**：clean tree → DC 打 `!cc-rotate` → 新 session ~30s 內在 DC 回 "ready"
2. **B1 攔截**：故意改一檔不 commit → 打 `!cc-rotate` → DC 收 B1 拒絕訊息
3. **B3 攔截**：commit 但不 push → 打 → DC 收 B3 拒絕訊息

---

## Troubleshooting

| 症狀 | 可能原因 | 排查 |
|------|---------|------|
| `!cc-rotate` 打了沒反應 | UserPromptSubmit hook 沒掛 / 路徑錯 | `cat ~/.claude/settings.json \| jq .hooks` |
| Rotation 後新 session 沒接 context | bootstrap.json 沒生成 / SessionStart hook 沒掛 | `ls ~/.claude/channels/discord-vibesync/cc-rotate.*.json` |
| Supervisor 起不來 | inotify-tools 沒裝 | `which inotifywait` |
| 新 session 起來但 DC 沒回 "ready" | plugin 還在重連 / Discord token 過期 | `tail -50 ~/.claude/channels/discord-vibesync/bridge.out` |
| Stale bootstrap.json 卡住 | 前次 rotate 中途崩 | `rm ~/.claude/channels/discord-vibesync/cc-rotate.bootstrap.json`（或 wait TTL = 10 min 自動清）|
| Lock 卡住（B4 一直觸發） | 前次 rotate 中途崩 + lock 沒清 | `rm ~/.claude/channels/discord-vibesync/cc-rotate.lock`（supervisor 也會用 `LOCK_STALE_SECONDS` 自動清）|

---

## Codex review 必過（v1 ship gate）

設計文件的 [Codex review gate 段](../../docs/plans/2026-05-14-cc-rotate-design.md#codex-review-gate強制v1-ship-前必過) 列了 10 條必查清單（race / cleanup / TTL / hook 衝突 / shell quoting）。

實作完成後**必交** Codex review，verdict 走 VibeSync `CLAUDE.md` 既有規則。

---

## v1 不做（明文，避免 scope creep）

- ❌ `!cc-handoff` 獨立指令 — 違反 single-command discipline
- ❌ `!cc-rotate --force` — Phase 2
- ❌ 自動 rotate / 跨 channel — Phase 2/3

完整 14 項見 [design doc v1 明文不做表](../../docs/plans/2026-05-14-cc-rotate-design.md#v1-明文不做避免被討好性-scope-creep)。
