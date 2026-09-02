# OCR Golden Set 跑分工具

設計文件：`docs/plans/2026-06-12-ocr-golden-set-design.md`。
黑箱打 `analyze-chat` 的 `recognizeOnly` 端點（不扣 quota），與 ground truth 比對，輸出六指標。**不動任何 OCR code path**。

## 隱私邊界（重要）

- **真實截圖與其 labels 一律不入 git**：圖在 Eric 本機 OneDrive（`OCR_GOLDEN_IMAGES_DIR`），labels 在 `labels/real/`（gitignored——labels 內容即對話逐字稿）。
- 合成圖（`synthetic/`）與其 labels（`labels/synthetic/`）無隱私，入 git。
- 跑分結果 `results/` gitignored；要引用數字時摘要進 docs，不貼原始輸出。

## 跑 prod baseline

```bash
export OCR_GOLDEN_TOKEN="<測試帳號 JWT>"        # 取得方式見下
export OCR_GOLDEN_ANON_KEY="<anon/publishable key>"
deno run --allow-net --allow-read --allow-write --allow-env run_benchmark.ts
```

取得測試帳號 JWT：

```bash
curl -s "https://fcmwrmwdoqiqdnbisdpg.supabase.co/auth/v1/token?grant_type=password" \
  -H "apikey: $OCR_GOLDEN_ANON_KEY" -H "Content-Type: application/json" \
  -d '{"email":"vibesync.test@gmail.com","password":"<密碼>"}' | jq -r .access_token
```

## 跑 local（OCR 改動 land 前回歸）

```bash
supabase functions serve analyze-chat --no-verify-jwt --env-file "$VIBESYNC_LOCAL_EVALS_ENV"
deno run --allow-net --allow-read --allow-write --allow-env run_benchmark.ts \
  --endpoint http://localhost:54321/functions/v1/analyze-chat
```

`VIBESYNC_LOCAL_EVALS_ENV` 必須指向 repo／OneDrive 外的受限環境檔；不要把 `CLAUDE_API_KEY` 放回 `.env.golden`、`supabase/.env` 或命令列。

### 無 Docker 機器（2026-06-13 消融跑分實證路徑）

`supabase functions serve` 需要 Docker。沒有時改用 deno 直跑＋auth 改寫 proxy（function code byte-for-byte 不動）：

```bash
# 1. 測試帳號 JWT（password grant，見上）寫入 /tmp/ocr-bench-token.env：OCR_GOLDEN_TOKEN=<jwt>
# 2. proxy：/rest/v1/* 的 Authorization 改寫成 user JWT（RLS 走 authenticated 自讀）
SUPABASE_URL=<prod url> deno run --allow-net --allow-read --allow-env bench_auth_proxy.ts &
# 3. function 指向 proxy；service key 缺席用 anon key 頂（只夠 auth.getUser，DB 寫入靠 RLS 自讀）
set -a
. "${VIBESYNC_LOCAL_EVALS_ENV:-/mnt/c/Users/eric1/.vibesync-secrets/local-evals.env}"
set +a
SUPABASE_URL=http://localhost:9999 SUPABASE_SERVICE_ROLE_KEY=<anon key> \
  deno run --allow-net --allow-env --allow-read supabase/functions/analyze-chat/index.ts &
# 4. 跑分（OneDrive 圖檔若被整理進子目錄，先攤平到 /tmp 再用 OCR_GOLDEN_IMAGES_DIR 指過去）
deno run --allow-net --allow-read --allow-write --allow-env run_benchmark.ts \
  --endpoint http://localhost:8000

# 多輪結果逐單元對照
./compare_runs.sh results/<runA>.json results/<runB>.json
```

## 2026-09-03 送審前跑分（Sonnet 5、production）

65 單元三輪：修前側邊 98.9%／召回 93.5%／鬼訊息 4（2 張暗色 LINE 引用卡圖 Sonnet 5 不標
`quoted_preview`，`--force-model claude-sonnet-4-6` 會標）；補暗色主題引用卡描述
（`screenshot_ocr_rules.ts`，commit `2c81345a`）後全套：側邊 99.4%、召回 93.7%、逐字 98.6%、
鬼訊息 0，引用卡預覽 63.6%(22)。殘餘：S__5480452 單側長圖側邊 3/6（模型判 mixed）。
同一張圖單次結果會抖（dark_bruce_3 三跑一跑壞），比較請看多跑或整體。

`--force-model <model>`：只對測試帳號生效（server `VALID_FORCE_MODELS`），模型對照用。

## 其他參數

- `--only <unit-id>`：只跑單一 unit（debug 用）
- `--out <dir>`：結果輸出目錄（預設 `results/`）
- 缺圖（換機器沒同步 OneDrive）或缺 label 的 unit 自動跳過並標示。

## 指標定義

LCS 序列對齊（NFKC normalize 後相似度 ≥0.8 視為同一則）後計：

| 指標 | 定義 |
|---|---|
| side accuracy | 對齊訊息 left/right 判對比率（主指標） |
| recall / precision | 漏抓率 / 幻覺率的反面 |
| final unknown rate | 最終 `side: unknown` 比率 |
| 逐字率 / CER | 完全逐字比率 / 字元錯誤率（錯字被「好心修正」會反映在這裡） |
| dedup | 重疊組（多張圖一請求）合併後與去重 expected 比對 |
| classification | 分類與 importPolicy 符合預期；400 reject gate 對 reject label 算正確 |

回應內含 `normalizationTelemetry`（layout 修復數、系統列移除數、重疊去除數），原樣存進 results JSON 供分佈分析。

## 標注流程

- 規則：左=對方、右=我；逐字保留錯字/注音；系統列不標；貼圖 `[sticker]`、照片 `[photo]`。
- AI 看圖產草稿 → Eric 校對。labels schema 見 `labels/real/*.json` 任一檔。
