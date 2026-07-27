# Keyboard Assist benchmark

這個工具量測單張截圖 Keyboard Assist 的 fresh latency、public response
contract、明確列出的截圖外事實，以及 quoted-preview
leak。它不把真實截圖、逐字稿、token 或 request image bytes 寫入 git。

## 現況

- `cases/synthetic.json` 只使用 repo 內合成圖，目的是驗證 runner 與契約，不代表
  production-shaped 品質集。
- `cases/adversarial.json`
  暫為空；在匿名化、人審與資料處理流程完成前，不用假案例填滿數字。
- 真實與 held-out manifest 放在本機 ignored 檔案，例如
  `cases/real.local.json`，image path 可為絕對路徑或相對該 manifest 的路徑。
- `results/` 被 gitignore；artifact
  會保存模型回覆供盲評，但不保存圖片、Authorization header 或輸入逐字稿。

## 執行

沒有 production endpoint 預設值，必須明確指定 endpoint。JWT
只從環境變數讀取，禁止放在 CLI history。

```powershell
$env:KEYBOARD_ASSIST_TOKEN = "<test-user-jwt>"
$env:KEYBOARD_ASSIST_ANON_KEY = "<local-or-target-anon-key>"
deno run --allow-env --allow-net --allow-read --allow-write `
  tools/keyboard-assist-benchmark/run_benchmark.ts `
  --endpoint http://127.0.0.1:54321/functions/v1/keyboard-assist `
  --manifest cases/synthetic.json
```

使用本機私有資料集：

```powershell
deno run --allow-env --allow-net --allow-read --allow-write `
  tools/keyboard-assist-benchmark/run_benchmark.ts `
  --endpoint http://127.0.0.1:54321/functions/v1/keyboard-assist `
  --manifest C:\private\keyboard-assist\real.local.json `
  --out C:\private\keyboard-assist\results
```

## Manifest

每個 case 只描述一次可重播評測；`repetitions` 建議為 3。

```json
{
  "id": "anonymous-case-id",
  "suite": "held-out",
  "imageFile": "images/anonymous-case-id.jpg",
  "repetitions": 3,
  "speakerOverride": "none",
  "voice": {
    "primary": "steady",
    "secondary": null
  },
  "forbiddenSubstrings": ["截圖中不存在、模型不可捏造的具體事實"],
  "quoteLeakNeedles": ["不可被當成新訊息輸出的引用預覽文字"],
  "quotedPreviewInstances": 2,
  "expectedStatuses": ["ready", "needs_speaker_confirmation"]
}
```

不要在 committed manifest 放真實姓名、帳號、逐字稿或本機使用者路徑。真實資料的
labels 與 needles 只留在受控本機資料集。

## 指標解讀

- latency 使用 nearest-rank p50／p95，fresh request 與 cache replay 必須分開。
- 0 observed quoted-preview leak 不等於真實 leak rate 為 0；report 顯示
  one-sided Wilson 95% upper bound。
- automated validator 只負責可確定的 schema、長度、Markdown／raw
  JSON、策略重複與明列 forbidden substring。自然度、證據語意與可直接使用率仍需
  `human-scorecard.md`。
- 至少 200 個 production-shaped eligible fresh requests 才可作 rollout
  p95／ready-rate 判斷；合成 runner smoke 不能替代。

## 測試

```powershell
deno test tools/keyboard-assist-benchmark/run_benchmark_test.ts `
  tools/keyboard-assist-benchmark/score_test.ts
```
