# 開場救星結構刀評測

新管線（`OPENER_PLAN_WRITE=true`：規劃 → 寫手 → 另外挑）與舊路徑（旗標關，等同 f80b59bd）的評測工具。
需求與閘門：Codex 工作資料夾 `opener-structural-cut/01_需求凍結.md` §6。

生成都走真的 `handleOpenerGenerateRequest`：PGlite 會話資料庫、production 預設呼叫器（ModelCallBudget、fallback、thinking 契約）。只有第一段分析改用固定快照（不花錢、不引入分析變異）。評測用 fetch 攔截記錄實際送出的請求與回應，不改產品程式。

| 檔案 | 內容 |
|---|---|
| `cases.json` | 22 題固定案例：V2 的 F1–F10、H01–H08、N01/N03/N05/N10（A 臂），含快照 |
| `corpus.json` | 114 句補充語料（14 種角色、58 句陷阱），五位撰寫者 × 兩位覆核者標註一致才收 |
| `bruce_calibration.json` | Bruce 9/23 原始作答逐字轉錄：主表 36 句＋附表有標註的 60 句 |
| `plan_eval.ts` | `--oracle` 免費結構檢查；`--live` 付費①規劃判類 |
| `blackbox.ts` | `--arm=A|B|OLD` 黑箱；`--live` 付費② |
| `judge.ts` | `--calibrate` 校準；`--runs=` 盲評黑箱輸出（打亂順序、不給風格名） |
| `report.ts` | 依臂 × 次彙整閘門指標 |

## 用法（repo 根目錄；沒有 `--live` 都是免費 dry run）

```sh
deno run -A tools/opener-plan-write-eval/plan_eval.ts --oracle                 # 免費：寫手輸入不漏不該進的原文
deno run -A tools/opener-plan-write-eval/plan_eval.ts --live --repeats=3       # 付費①，約 US$2.5
deno run -A tools/opener-plan-write-eval/judge.ts --calibrate --live           # 付費，約 US$0.5
deno run -A tools/opener-plan-write-eval/blackbox.ts --arm=A --live            # 付費②，三臂合計約 US$4.5
deno run -A tools/opener-plan-write-eval/judge.ts --runs=<A>,<B>,<OLD> --live  # 付費，約 US$1.4
deno run -A tools/opener-plan-write-eval/report.ts <judged.json>
```

付費腳本都有 `--cap-usd` 上限與單次預留；讀 `~/.config/anthropic/key`。**每一段付費都要 Eric 說「跑」才執行。**
輸出在 `out/`（不進 git）。
