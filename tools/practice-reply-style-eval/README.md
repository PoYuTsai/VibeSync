# 練習室寫實差異化 reply-style 評測（PR-0 baseline）

規格：`docs/plans/2026-09-02-practice-reply-style-diversity-spec.md`。問題是 100
位女孩只有 5 套 persona 骨架，換人像沒換。這支工具固定情境、換角色，量到底多像；
difficulty bakeoff 固定角色量難度，兩者互補。

每一輪都是真實 DeepSeek 呼叫（prod 同款 `deepseek-v4-flash`，Eric 2026-09-02
授權隨意調用）。144 場約 3 分鐘。

## 三支工具

```bash
export DEEPSEEK_API_KEY=...   # 或放 supabase/.env
# 1. 產生 artifact：4 位 slow_worker × 12 情境 × repeat
deno run --allow-env --allow-read --allow-write --allow-run=git --allow-net=api.deepseek.com \
  tools/practice-reply-style-eval/run_baseline.ts tools/practice-reply-style-eval/out/<date>-<label>.json --repeat=3
# 2. 確定性評測（不打網路）
deno run --allow-read tools/practice-reply-style-eval/evaluate.ts tools/practice-reply-style-eval/out/<file>.json
# 3. 同 persona 四選一 LLM 盲測（寫 <file>-judge.json）
deno run --allow-env --allow-read --allow-write --allow-net=api.deepseek.com \
  tools/practice-reply-style-eval/judge.ts tools/practice-reply-style-eval/out/<file>.json
# 自測
deno test --allow-read --allow-env tools/practice-reply-style-eval/evaluate_test.ts
```

- `run_baseline.ts`：prompt 走 production `buildChatMessages`（含 bakeoff 同一份
  固定 context fixture：2026-08-28 20:30、固定
  thread、記憶摘要、一則貼文），standard 模式、normal 難度，回覆後處理照 handler
  同序（繁體→內部標籤守門→L4 守門）。
  flags：`--profiles`、`--scenarios`、`--repeat`、`--difficulty`、`--concurrency`。
  artifact meta 綁 commit／tree／dirty／prompt policy version／模型／常數。
- `scenarios.ts`：規格 §10.1 的 12 類，最後一則 user 訊息是探針。
- `evaluate.ts`：每人表面風格分佈；角色之間 vs 同角色分半的重心距離（比值 ≈1
  ＝分不出來）；每情境探針回覆的 shape 集中度、同開頭、bigram
  Jaccard。文字距離只 能當警報，不能當成功證明。
- `judge.ts`：校準 5 情境、留出 5 情境（排除 interrogation／interest_hit，避免靠
  年齡職業興趣事實猜人），四選一，機率基準 25%，規格門檻 ≥70%。

## 結果紀錄

- `2026-09-02-run1-baseline-4sw-x3.json`（322fc5e3 未改 prompt 的 baseline）：
  144 場零失敗、420 則回覆、守門退回 0、p50 975ms。 **重心距離比值
  0.80**（角色之間比自己跟自己還像）；探針 Jaccard 跨角色 0.095 vs 同角色
  0.135。同開頭佔比 100% 的情境：daily_share、failed_joke、light_joke。 judge
  四選一 **40%**（Alice 60% 靠空服事實外洩；Bonnie 20% 低於機率）。
- `2026-09-02-run3-style4-x3.json`（c56f6d19，`--style=1`：4 位的 Reply Style
  Profile＋Turn Response Plan，全域表面規則與【示範口吻】拿掉）：144 場零失敗、
  p50 944ms、最長 prompt 8863。**重心距離比值 3.14**（0.80→3.14）；judge 四選一
  **53%**（40%→53%；Alice 87%、Bonnie 53%、Nina 40%、Lumi 33%）。每人表面分佈明顯
  分開（Alice 64% 單則／問句 10%；Lumi 47% 句號收尾、標點 1.35/10 字；Nina／Bonnie
  四成三則）。退步訊號：括號旁白 4/420（baseline 1/420），主要在 failed_joke 與
  boundary；judge 仍遠低於規格 70% 門檻，且 Nina／Lumi 互相混淆。
- 對照用 `--style=0`（預設）的 run1 即 baseline；兩次 run 的 prompt 旗標關時逐字相同
  （prompt_test golden hash）。
- `2026-09-02-run6-baseline20-x3.json`（598eb5e0 之後預設 20 位，`--style=0`）：720 場
  零失敗。**跨 persona 整體比值 1.01**，五個 persona 內 0.69–0.85——不只同 persona
  像複製人，五個 persona 之間用表面風格也分不出來。judge（五組四選一、300 trials）
  **34%**。
- `2026-09-02-run8-style20-x3.json`（32ace744，`--style=1`，reject 版守門）：整體比值
  **2.49**，persona 內 1.32（playful_extrovert）～4.03（teasing_humor）；judge **47%**
  （五個 persona 全部 41–52%）。守門擋 16/2093，但 6 場兩次都被擋而整場失敗
  （0.8%）→ 改成修補優先（`stripStageDirections`），run9 驗證。
- `2026-09-03-run10-style20-policy-x3.json`（dc3be879：Codex R1 修正後——policyStance
  承接既有結果、脆弱／玩笑改候選 act、修補優先守門）：720 場零失敗、修補 9/2100。
  整體比值舊定義 2.81（新定義見下表）；persona 內（舊定義）1.89–3.67。
  judge 改成**遮罩事實**（名字／城市／職業／興趣／年齡→＊）＋bootstrap 95%：
  baseline20 **34%（28–38%）** → style **41%（36–48%）**，chance 25%。差異方向一致但
  仍遠低於規格 70% 門檻；這些數字只能證明「有拉開」，真人感與達標要靠人工盲測。
  延遲 p50 1656ms 高於前幾輪（同 prompt 長度），視為 API 當時負載，非本案造成。

### 比值定義更新（2026-09-03，47bcd52b）

上面各 run 記錄的比值是舊定義（奇偶分半，一邊兩次重複會低估雜訊帶）。新定義＝
角色重心距離 ÷ 三種單次分半（repeat 兩兩配對）的同角色距離平均，並附範圍：

| run | 舊 | 新（三種分半範圍） |
|---|---:|---|
| run1 baseline 4 位 | 0.80 | **0.68**（0.56–0.94） |
| run3 style 4 位 | 3.14 | **2.89**（2.62–3.04） |
| run6 baseline 20 位 | 1.01 | **0.84**（0.81–0.87） |
| run10 style 20 位（R1 修正後） | 2.81 | **2.29**（2.13–2.54） |

結論不變：baseline 的角色之間比自己跟自己還像；style 開後拉開約 3 倍，範圍不重疊。
- `2026-09-03-run11-style20-r2fix-x3.json`（12b2d9ce，Codex R2 五項 P1 修正後，最終快照、
  worktree clean）：720 場零失敗、修補 23/2100、守門退回 1。比值 **2.18（2.06–2.35）**，
  persona 內 1.05（clear_boundaries）～2.76（teasing_humor）；遮罩 judge **43%（40–50%）**。
  注意 clear_boundaries 這組掉到 1.05：越界改強制 direct_boundary、cautious 濾掉 tease／
  self_disclose 之後，這四位在界線與防備情境的表達更一致——安全優先於差異，符合規格
  §5.1 順位，但代表這組的個人差異要靠非界線情境撐。
- `2026-09-03-run12-style20-r3fix-x3.json`（e5ab5ee5，Codex R3 三項 P1 修正後：拿掉所有
  啟發式硬判，記憶／拒絕／越界改結構化證據或交給模型；worktree clean）：720 場零失敗、
  修補 18/2100、守門退回 0。比值 **2.02（1.90–2.17）**，persona 內 1.15（clear_boundaries）
  ～2.22（slow_worker）；遮罩 judge **38%（33–43%）**，比 run11 的 43% 低、與 baseline
  34%（28–38%）的區間邊緣重疊。誠實解讀：每拿掉一個硬判（cautious 過濾、候選 act 限制），
  差異化就掉一些；表面距離仍約 baseline 的 2.4 倍，但 LLM 四選一已接近雜訊。真人感與
  可辨識度要靠 PR-2 dogfood 人工盲測，不再追這個數字。
