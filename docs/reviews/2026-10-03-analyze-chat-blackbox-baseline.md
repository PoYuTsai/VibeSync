# 對話分析黑箱基準線（2026-10-03，Sonnet 5.5 正式設定）

> 用途：給之後每一刀（prompt 減法、送出即定稿、結構刀）當「改之前」的比較基準，並量出同一版本重跑的自然浮動範圍（雜訊範圍）。
> Eric 2026-10-03 核准（「跑」）。原始資料：`tools/analyze-v2-blackbox/out/2026-10-03-baseline-c3/`（`records.json` 每次呼叫一筆、`arm-C.json` 給評測器、`critic-C.json` 評審結果、`summary.md`）。

## 跑了什麼

- 程式：`main` @ `9adbf87c`（工具標 dirty=true 是因為主工作區有未追蹤的評測輸出檔，追蹤中的程式沒有改動）；實送 prompt 的 sha256 記在 `records.json` 的 `meta.v2SystemPromptSha256Rebuilt`。
- 模型：`claude-sonnet-5-5`，production helper 原樣（也就是 2026-10-03 起 `ANALYZE_STREAM_SONNET_55=true` 的正式設定）；備援鏈關閉，失敗就記失敗。
- 語料：`tools/analyze-v2-blackbox/corpus.ts` 的 23 案（開場、熱絡、冷淡、邀約前後、婉拒、她問他意見、長對話等），每案 3 次，共 69 次。付費方案五種風格；**免費方案兩種風格仍沒有黑箱資料**。
- 評審：固定 Sonnet 5（`run_critic.ts`），只審送出案的選中卡，45 案。
- 花費：主跑 US$3.13（約每次分析 US$0.045）＋評審約 US$0.20（輸入 94,245、輸出 1,345 token）。

## 結果

| 指標 | 數值 |
|---|---|
| 決定（送／收尾／先別回）正確 | 69/69；23 案每案 3 次的決定完全一致 |
| 評測器全部 gate 通過 | 58/69（84%）；失敗只有兩種：問句超過額度 6 次、用到超過上限的發散分枝 5 次 |
| 評審判定「要重寫」 | 7/45（約 16%），另 1 案評審輸出無效；違規類型：編造用戶本人的事 3、沒對準她的目的 3、開場太空泛 1、投入不對等 1、不可執行 1、接錯球 1、輔助球搶主線 1（一案可多項） |
| 拒答、截斷、HTTP 錯誤 | 0、0、0 |

### 等待時間（從呼叫模型起算，不含 OCR、權益同步、冷啟動）

| 時間點 | 送出案（n=45）p50／p95 | 先別回／收尾（n=24）p50／p95 |
|---|---|---|
| 出現決定 | 3.4 秒／8.3 秒 | 3.6 秒／5.8 秒 |
| 第一張卡（＝推薦卡） | 8.2 秒／11.1 秒 | — |
| 五張卡到齊 | 15.2 秒／18.9 秒 | — |
| 完成事件（**現在 App 到這時才能複製**） | 18.9 秒／24.7 秒 | 8.6 秒／10.2 秒 |

## 雜訊範圍（同一版本重跑會差多少）

這是之後判斷「改好了還是運氣」的尺：

- 評測器每一輪的通過數：第 1 輪 18/23、第 2 輪 21/23、第 3 輪 19/23。**單輪就可能差 3 案（約 13 個百分點）**。
- 失敗的 7 案裡，只有 `she_shares_bad_day` 三輪都失敗；其他 6 案都是三輪裡有過有不過。
- 評審每一輪判要重寫的數量：1–3 張（15 張裡），約 7%–20%。
- 結論：任何 prompt 改動至少跑 3 輪，新舊差距要大過上面這些範圍才算數；只跑 1 輪的「變好」不能採信。

## 怎麼重跑

照 `tools/analyze-v2-blackbox/README.md`：先 dry-run（不打模型）看次數與估價，等 Eric 說「跑」，再用 `--run --confirm-paid --max-calls --budget-usd --tag` 跑；評審另跑 `run_critic.ts`。這次的指令：

```sh
deno run --allow-env --allow-read --allow-run=git \
  --allow-write=tools/analyze-v2-blackbox/out --allow-net=api.anthropic.com \
  tools/analyze-v2-blackbox/run_blackbox.ts --arms=C --repeat=C:3 \
  --run --confirm-paid --max-calls=69 --budget-usd=9.85 --tag=2026-10-03-baseline-c3
```

（`--budget-usd` 要比 dry-run 印出的估價高一點點：估價是 9.8430 美元，印成 9.84；上限設 9.84 會被停損擋下。）
