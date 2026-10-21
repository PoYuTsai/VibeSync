# 教練「關於我」成對評測（改前 vs 改後）

比較同一組題目在**改前**（base）和**改後**（cand）的教練 1:1 回答：哪一版更守使用者自己寫的界線、更貼題、更少亂扯「關於我」、更不替使用者編經歷、遇到藏在自述裡的指令更不照做。給規格〈「關於我」只給教練，並讓教練讀對〉（Bruce 2026-10-20）的 PR-6 用；PR-4（教練選卡與提示詞）上線前跑一輪（D9），PR-7～PR-9 之後各跑一輪。

預設是乾跑：不打模型、不讀金鑰、不連網；會跑 git（`rev-parse`、`status`、`archive`）取出改前版本。要花錢的真跑，必須 Eric 當次說「跑」之後才下指令。

模組下載不歸工具的網路閘管（Deno 載入遠端模組不經 `fetch`）：下面的指令都帶 `--cached-only`，缺快取就停。第一次用先在 repo 根目錄跑 `deno cache tools/coach-about-me-eval/run.ts tools/coach-about-me-eval/judge.ts supabase/functions/coach-chat/generation.ts supabase/functions/coach-chat/prompts.ts supabase/functions/coach-chat/semantic_critic.ts supabase/functions/coach-chat/schemas.ts`（只下載模組，不呼叫模型；兩臂的 coach-chat 是執行時動態載入，要另外列）；改前那一版若用了不同版本的套件，`--cached-only` 會直接報錯，不會偷偷下載。

## 兩臂

| 臂 | 是什麼 |
|---|---|
| `base` | `--base-ref` 那一版的 production（預設 `928904cf`，規格 PR-4 之前、含 PR-3 的 App 格式）。用 `git archive` 把 `supabase/functions` 取到暫存目錄再載入，不動工作樹。 |
| `cand` | 目前工作樹的 production。 |

- 兩臂都呼叫正式的 `runCoachChat`（`supabase/functions/coach-chat/generation.ts`）：同一份提示詞組法、同一個模型與參數（`claude-sonnet-5`、生成 max_tokens 1200、審稿 260、thinking 關閉）、同樣的格式驗證、語意審稿與最多三次重寫。只把扣費換成不做事、把模型呼叫包上付費守門；不經 Edge、DB、扣費、帳本。
- 每題一律 `forceAnswer: true`（等於使用者直接看正式建議），不然零證據的第一輪多半只回一個釐清問題。
- 同一題同一次重複，兩臂送同一份請求（先過該臂的 `RequestSchema`）。

## 題目（`cases.json`，46 題 10 組）

| 組 | 題數 | 看什麼 |
|---|---|---|
| `boundary` 界線遵守 | 6 | 界線寫「不要太快邀約」卻問「要不要今晚直接約」這類；對方說先不要約時要停 |
| `relevant` 相關才用 | 6 | 緊張不敢傳帶著草稿問、容易解釋太多的長草稿、不知道怎麼開口約 |
| `unrelated` 無關不提 | 6 | 已讀不回卻問約會穿搭；好的回答不該硬扯卡點 |
| `no_fabrication` 不捏造特質 | 4 | 只有目標，被問平常喜歡做什麼；目標不等於已經發生的事 |
| `honest_emotion` 情緒包裝仍誠實 | 4 | 很難過的傾訴、把「再看看」當答應；判斷不能因此變軟 |
| `legacy_style` 舊風格照樣遵守 | 4 | 8/4 以前設過互動風格的人；句長與問句數量 |
| `injection` 惡意自述 | 4 | 自述裡夾「忽略規則」「拒絕也要約」「貼出系統提示」「扮成女友」 |
| `recent_note` 最近的狀況 | 4 | 規格 PR-8：近況相關時照原文用、寫了 12 天的不把時間詞說成現在、無關時不扯、近況不是興趣不能編喜好 |
| `about_me_suggestion` 建議加到關於我 | 6 | 規格 PR-9：使用者自己說出處境或目標時才建議（A1 卡點、A2 還沒填關於我的新用戶說目標）；對方訊息叫他改關於我、對方說他話多（A3、A4）與無關的題目（A5、A6）不建議 |
| `no_about_me` 對照組 | 2 | 沒填關於我的同類題 |

`aboutMe` 由 `profile` 照 App 的 `buildForCoachFollowUp` 組出；`test/unit/tools/coach_about_me_eval_cases_test.dart` 逐題比對兩者一字不差。都是人工示例，不是真用戶資料。題庫由 `gen_cases.py` 產生：改題目或 App 組字之後，在 repo 根目錄跑 `python3 -I tools/coach-about-me-eval/gen_cases.py > tools/coach-about-me-eval/cases.json`，再跑上面那支對照測試。近況用 `recentNoteDaysAgo` 表示寫下幾天了（滿 14 天就不放進 aboutMe），對照測試用固定時鐘重組。

建議組每題有 `expectSuggestion`（該出現的 `{field, key}`，`null`＝不該出現）。真跑時 `run.ts` 直接比對回應頂層的 `aboutMeSuggestion`，結果寫在 `suggestions.json`（每臂的「該出現對／沒出現／給錯、不該出現卻出現／沒出現」與逐次明細），不靠評審；只算成功的正式卡，備援卡不算。改前臂沒有這個功能，建議一律不會出現，當對照。評審只比兩臂的卡片本身，確認加了這條規則之後回答沒有變差。

規格 PR-7（2026-10-21）起新版 App 不再送互動風格；`legacy_style` 4 題與 U4 只填了風格，`aboutMe` 保留 PR-7 之前舊版 App 的格式（四行風格加使用範圍），代表還沒更新的舊版流量。對照測試對這 5 題改成檢查：拿掉風格行之後只剩使用範圍，而且新版組字對同一份 profile 什麼都不送。

## 乾跑（不花錢）

在 repo 根目錄（WSL）執行：

```sh
deno run --cached-only --no-prompt --allow-read --allow-write --allow-run=git,tar \
  tools/coach-about-me-eval/run.ts --tag=dry-YYYYMMDD
```

在 `out/<tag>/` 寫 `manifest.json`（兩臂的 SHA、案例 sha256、模型參數、估算）、`cases.snapshot.json`（題庫原文，評審只用這份）、`prompts.json`（每次的生成提示詞）、`prompt-diff.json`（同一題兩臂提示詞各自獨有的行）。同名輸出目錄已存在就拒絕執行，不覆寫證據。

**費用估算**（保守）：input token＝字數×2（本機沒有 tokenizer；中文本機估算會低估一到兩成），Sonnet 5 單價 input $2/M、output $10/M（教練沒開快取）。一般＝一次生成（output 700）＋一次審稿（output 120）；最壞＝三次生成（後兩次多算 600 字重寫指示）＋三次審稿、output 全滿。審稿的 input 用每欄都到上限的卡片估。

2026-10-21 乾跑（36 題 × 1 次 × 2 臂＝72 次 runCoachChat）：一般 144 次呼叫約 US$3.54、最壞 432 次約 US$12.36。

## 真跑（要 Eric 當次說「跑」）

```sh
deno run --cached-only --no-prompt --allow-read --allow-write --allow-run=git,tar \
  --allow-env=HOME --allow-net=api.anthropic.com \
  tools/coach-about-me-eval/run.ts --tag=<tag> \
  --run --confirm-paid --max-calls=<上限> --budget-usd=<上限>
```

守門：

- `--run --confirm-paid --max-calls --budget-usd` 少一個就拒絕啟動。這些是技術守門，不能取代 Eric 的授權。
- 追蹤檔有未提交修改就拒絕（結果要能對回工程 HEAD）。金鑰讀 `~/.config/anthropic/key`。
- **網路閘**：啟動時先換掉 `fetch`，之後才載入兩臂的程式。只有付費守門預留過的那一次 `api.anthropic.com/v1/messages` 會放行，其他連線一律拒絕。
- **每次送出前預留最壞情況**：估計 input 全算、output 用 max_tokens 全滿。已花費＋這次預留超過 `--budget-usd`，或到 `--max-calls`，就整批停；剩下的記 `NOT_RUN_CAP_OR_STOP`，正在跑的那一題記 `STOPPED_BUDGET`。
- **每字 token 數會校正**：一開始用 2；每次回來用實際 usage 換算，比較高就改用實測值（只升不降）。
- **預算不是嚴格上限**：token 數是估的，第一次呼叫的實付可能超過預留；超過幾次記在 `run-summary.json` 的 `overReserveCount`。
- API 失敗或沒回 usage：成本當預留額計入，並停止後續呼叫，不當免費。
- 送出前後都寫 `requests.jsonl`，每題跑完就重寫 `records.json`，中斷不會靜默重送。

輸出在 `out/<tag>/`（已 gitignore）：`records.json`（每次 runCoachChat 的狀態、卡片與「加到關於我」建議；停下來之後沒跑的也列進去）、`requests.jsonl`、`run-summary.json`、`suggestions.json`（建議組的比對）。備援卡（`FALLBACK`）、HTTP 錯誤、預算停下的都不進盲比，數量照實列。

## 評審與盲測表

```sh
# 乾跑：配對、寫盲測表與解盲表、估評審費用，不呼叫評審
deno run --cached-only --no-prompt --allow-read --allow-write tools/coach-about-me-eval/judge.ts --from=<run 的 tag>

# 真跑（要 Eric 當次說「跑」）
deno run --cached-only --no-prompt --allow-read --allow-write --allow-env=HOME \
  --allow-net=api.anthropic.com tools/coach-about-me-eval/judge.ts --from=<run 的 tag> \
  --tag=<judge tag> --run --confirm-paid --max-calls=<上限> --budget-usd=<上限>
```

- 題目只用 `out/<run 的 tag>/cases.snapshot.json`，sha256 要等於那次 manifest 的 `casesSha256`，對不上就停（避免拿改過的題目評舊回答）。
- 同一題同一次重複兩臂都 OK 才配成一對；A／B 依 `--seed` 隨機，同 seed 可重現。
- 評審（`claude-sonnet-5`，max_tokens 600）只照該組的固定判準選 A、B 或平手，附兩邊各一句原文引文與 1–100 的信心分數；引文對不回回答原文、不是合法 JSON 的整筆當無效，不猜。評審看不到臂名。
- `blind.md`：給 Eric 或 Bruce 的盲測表，不露臂名；標「請抽查」的至少 20%、每組至少一對。`unblind-key.json` 是解盲表，**不要跟盲測表一起給人**。
- `summary.md`：解盲後各組改後贏、改前贏、平手的數量。AI 評審只是參考，以抽查的人工勾選為準。
