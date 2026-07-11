# Bruce 三案 UX follow-up — Codex 雙審紀錄

日期：2026-07-11
分支：`codex/bruce-ux-followup`
Review range：`b98a4852..636c7c2b`

## 範圍

- 已分析對話移入獨立「分析紀錄」，可查看、續接、改派與刪除。
- OCR 確認頁首次自動示範左右滑、可重播、尊重 reduce-motion。
- 收藏滿池時提示重複風險；server 增加異常重複 telemetry，不改扣費或 response contract。
- 封存／分析快照補上 content revision envelope，封住同數量編輯、marker 寫入失敗、
  append-only、premium prefix 與 save in-flight 的競態。

## 安全不變量

- 新分析快照自帶 analyzed-prefix `contentRevision` 與 `messageCount`；restore 必須吻合。
- marker 或 settings 寫入失敗一律 fail-open 留在 active，不得誤藏目前對話。
- stale 分析不得覆寫新訊息、不得留下新的 analyze history 或 follow-up side effect。
- legacy markerless snapshot 首次相容還原後立即在記憶體升級 envelope；不新增 Hive field。
- 抽卡 telemetry 只在 RPC 已成功後觀測，不改 quota、idempotency 或 response schema。

## 第二輪雙審

- Client red-team：`APPROVED`，P0/P1/P2 = `0/0/0`；獨立 8-file bundle `130/130`。
- Test / migration / data safety：`APPROVED`，P0/P1/P2 = `0/0/0`；獨立 9-file bundle `125/125`。
- 額外 snapshot failure-matrix audit：`APPROVED`，無剩餘 P0–P2。
- 非阻擋 P3：封存頁「繼續這一段」若 marker 寫入失敗仍會導航，之後可能仍留在
  紀錄頁；屬既有 best-effort 儲存失敗 UX，不涉及資料遺失。

## 驗證

- Flutter 高風險整合 bundle：`126/126`。
- Hint service + Collection screen：`41/41`。
- `flutter analyze`：0 issue。
- Draw handler：Deno `18/18`；`deno check`、`deno fmt --check` 通過。
- `git diff --check`：通過。
- 無 SQL migration、Hive schema migration 或 API response migration。
- 使用者既有 `pubspec.lock` diff hash 維持
  `155151b4d3096ddc42a4457638cd8984fb9d8620`，未納入提交。

## 結論

雙審 `APPROVED`。程式碼可進入 push、PR、`practice-chat` Edge deploy 與下一版
TestFlight build 流程；真機仍需驗證三個產品感受項目。
