# 官網展示頁 Handoff

更新日期：2026-03-16

## 背景

目前 live 官網：
- [首頁](https://vibesyncai.app/)
- [隱私權政策](https://vibesyncai.app/privacy)
- [服務條款](https://vibesyncai.app/terms)

已確認：
- `/privacy` 與 `/terms` 已存在，且內容方向正確
- 首頁 footer 已連到 `/privacy` 與 `/terms`

仍需修正：
- 首頁隱私區塊仍使用「絕不上傳雲端」這種與實際產品流程不一致的說法
- 首頁底部 App Store 下載按鈕仍是 `href="#"` 的假連結

---

## 必改 1：首頁隱私區塊文案

### 推薦最終版

標題：

```text
隱私優先，清楚透明
```

內文：

```text
對話內容預設保存在你的裝置中；只有在你主動使用分析或截圖辨識時，系統才會傳送完成該次請求所需的內容，用於產生 AI 建議。
```

### 不要再使用

- `絕不上傳雲端`
- `僅存於本地裝置`
- `完全不會離開你的手機`

---

## 必改 2：底部 App Store 按鈕

### 原則

- 不要保留 `href="#"` 假連結
- 如果 App 還沒公開上架，就不要做成可點擊但沒有目的地的下載按鈕

### 做法 A：如果已有正式 App Store URL

請把按鈕連到真正的 App Store 頁面：

```html
<a
  href="{{APP_STORE_URL}}"
  target="_blank"
  rel="noopener noreferrer"
  class="..."
>
  立即下載 VibeSync
</a>
```

### 做法 B：如果還沒有正式 App Store URL

建議改成不可點擊的狀態，不要假裝可下載：

```html
<div class="inline-flex items-center justify-center px-10 py-4 text-lg font-bold text-white/80 bg-white/10 rounded-full cursor-default">
  App Store 即將上線
</div>
```

如果是只給夥伴測試，也可以改成：

```text
TestFlight 測試中
```

但不建議把 private TestFlight 連結直接掛在公開首頁。

---

## Footer 連結規格

請保持：

- `/privacy`
- `/terms`

不要改回：

- `privacy.html`
- `terms.html`

---

## 建議 QA

- [ ] 首頁隱私文案已改成最終版
- [ ] 底部下載按鈕不再是 `#`
- [ ] `/privacy` 可正常開啟
- [ ] `/terms` 可正常開啟
- [ ] 手機版 footer 排版正常
