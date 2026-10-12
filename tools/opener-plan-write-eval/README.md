# 開場救星結構刀評測

新管線（`OPENER_PLAN_WRITE=true`：規劃 → 寫手 → 另外挑）與舊路徑（旗標關，等同 f80b59bd）的評測工具。
需求與閘門：Codex 工作資料夾 `opener-structural-cut/01_需求凍結.md` §6。

生成都走真的 `handleOpenerGenerateRequest`：PGlite 會話資料庫、production 預設呼叫器（ModelCallBudget、fallback、thinking 契約）。只有第一段分析改用固定快照（不花錢、不引入分析變異）。評測用 fetch 攔截記錄實際送出的請求與回應，不改產品程式。

| 檔案 | 內容 |
|---|---|
| `cases.json` | 32 題固定案例：V2 的 F1–F10、H01–H08、N01/N03/N05/N10（A 臂），加 L01–L04 沒線索案例，加 R01–R06 尺度邊緣探針（2026-10-12），含快照 |
| `corpus.json` | 114 句補充語料（14 種角色、58 句陷阱），五位撰寫者 × 兩位覆核者標註一致才收 |
| `bruce_calibration.json` | Bruce 9/23 原始作答逐字轉錄：主表 36 句＋附表有標註的 60 句 |
| `plan_eval.ts` | `--oracle` 免費結構檢查；`--live` 付費①規劃判類 |
| `blackbox.ts` | `--arm=B|OLD` 黑箱（A 旗標開也走舊路徑，已停用）；`--model=` 換結構刀模型；`--live` 付費② |
| `judge.ts` | `--calibrate` 校準；`--runs=` 盲評黑箱輸出（打亂順序、不給風格名）；評審固定 Sonnet 5 |
| `report.ts` | 依臂（含模型）× 次彙整閘門指標 |

L02（只有一張自拍）以 `imageCount=1`、零線索快照近似；現有 schema 沒有實際照片欄位，`blackbox.ts` 也不送圖片。此案例只覆蓋沒線索生成，不驗證照片辨識或照片計費。

## 用法（repo 根目錄；沒有 `--live` 都是免費 dry run）

```sh
deno run -A tools/opener-plan-write-eval/plan_eval.ts --oracle                 # 免費：寫手輸入不漏不該進的原文
deno run -A tools/opener-plan-write-eval/plan_eval.ts --live --repeats=3       # 付費①，約 US$2.5
deno run -A tools/opener-plan-write-eval/judge.ts --calibrate --live           # 付費，約 US$0.5
deno run -A tools/opener-plan-write-eval/blackbox.ts --arm=B --live            # 付費②，B 臂 78 次，費用依實際 token
deno run -A tools/opener-plan-write-eval/judge.ts --runs=<A>,<B>,<OLD> --live  # 付費，約 US$1.4
deno run -A tools/opener-plan-write-eval/report.ts <judged.json>
```

付費腳本都有 `--cap-usd` 上限與單次預留；讀 `~/.config/anthropic/key`。**每一段付費都要 Eric 說「跑」才執行。**

## 換 Sonnet 5.5 對照（ADR #54，2026-10-12）

- `blackbox.ts --model=claude-sonnet-5-5` 等於 production 開了 `OPENER_SONNET_55`：結構刀的寫手、修格式、改寫用 5.5，規劃維持 Sonnet 5（ADR #54 決定 6），思考參數與 max_tokens 餘裕照共用呼叫層；5.5 掛掉會退 Sonnet 5（每一跳實際送的模型看輸出檔 `calls[].model`）。`--arm=OLD` 不吃這個開關。
- 評審固定 Sonnet 5（`judge.ts` 的 `JUDGE_MODEL`）：校準是用它做的，生成換模型時評審不跟著換。`report.ts` 把 5.5 的輸出列成 `B·5.5`。
- R01–R06 是尺度邊緣探針（喝酒夜生活、想稱讚身材、她寫了不約炮、犯罪紀錄片、想撩、離婚單親）：量 5.5 會不會把正常的交友內容當成要拒答。拒答的生成回 422 `OPENER_CONTENT_REFUSED`，在報表逐題清單顯示為「（422）」。
- 乾跑（沒有 `--live`）最後會印這組設定真跑的估價：input＝提示詞字數×1.5、全用快取寫入單價；一般 output 規劃 500、寫手 900，5.5 每次另加約 1000 思考 token；最壞每次 output 全滿，再加一次修格式。`judge.ts --runs=` 乾跑也會印評審估價。估算偏保守。

```sh
deno run -A tools/opener-plan-write-eval/blackbox.ts --arm=B --repeats=2 --out=tools/opener-plan-write-eval/out/<tag>-s5
deno run -A tools/opener-plan-write-eval/blackbox.ts --arm=B --repeats=2 --model=claude-sonnet-5-5 --out=tools/opener-plan-write-eval/out/<tag>-s55
deno run -A tools/opener-plan-write-eval/judge.ts --runs=<s5 輸出>,<s55 輸出>
```

2026-10-12 乾跑（32 案 × 2 次）：Sonnet 5 一般 US$2.13、最壞 US$6.65；5.5 一般 US$3.41、最壞 US$14.33；評審 128 次一般 US$1.10、最壞 US$1.74。
輸出在 `out/`（不進 git）。
