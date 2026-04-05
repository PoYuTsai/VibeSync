# Current Test Status - 2026-04-03

## Summary

目前階段：送審前最後穩定化  
目前結論：`Auth`、`刪帳`、`訂閱升級刷新`、`同 Apple ID restore`、主要 `OCR` 案例都已接近可驗收  
目前重點：持續收 `OCR` 邊界案例，不再擴張大功能

## 已完成

- [x] 新註冊 Email 帳號成功建立
- [x] 驗證信可收到，手機點驗證連結可回 App
- [x] 忘記密碼信可收到，手機點連結可回 App 並成功重設密碼
- [x] 重設密碼後可用新密碼登入
- [x] 登出後換帳號，不再殘留上一個帳號的對話/分析/tier
- [x] 刪除帳號成功
- [x] 刪帳後可用同一個 Email 重新註冊
- [x] `Free -> Essential` 升級成功
- [x] 升級後回分析頁，完整回覆會刷新出來
- [x] 同一條流程連測第二次仍正常
- [x] 同 Apple ID 下，切到另一個 VibeSync 帳號後按 `同步已買過的訂閱`，方案會同步過去
- [x] 同 Apple ID restore 行為已確認屬於預期，不視為 bug
- [x] 單邊左側主訊息 + 引用卡的主要測試案例目前正常
- [x] 名字辨識與整體 OCR 體感目前沒有新的明顯問題

## 待測

- [ ] `Free -> Starter`
- [ ] `Starter -> Essential`
- [ ] `Essential -> Starter` 降級週期驗證
- [ ] 不同 Apple ID、從未買過訂閱時按 `同步已買過的訂閱`，應維持 `Free`
- [ ] `Restore` 在重裝 App / 新裝置 / 重開 app 情境下的完整驗證
- [ ] 多張連續截圖（兩張以上）
- [ ] 長截圖交界重疊去重
- [ ] 圖片 / 貼圖 / 影片泡泡情境
- [ ] 短句、續句、單 emoji、重複句情境
- [ ] 右側單邊主訊息 + 引用卡變形案例

## 訂閱測試流程

### 1. Free -> Essential

1. 用 `Free` 帳號登入。
2. 先分析一段對話，確認目前結果是 free 版。
3. 點 `升級解鎖完整回覆`，購買 `Essential`。
4. 回分析頁，預期：
   - 會有明顯 loading / 刷新提示
   - 重新分析後會出現完整回覆
   - 不應再顯示 free 限制提示

### 2. 同 Apple ID restore

1. 先用已買過 `Essential` 的帳號登入。
2. 登出後登入另一個 `Free` 帳號。
3. 到設定頁按 `同步已買過的訂閱`。
4. 預期：
   - 方案可能同步到目前帳號
   - 這是 RevenueCat 預設 transfer 行為
   - 不代表重新扣款

### 3. 不同 Apple ID restore

1. 換到全新的 Apple ID / Sandbox Apple ID。
2. 用 `Free` 帳號登入。
3. 不購買，直接按 `同步已買過的訂閱`。
4. 預期：
   - 應維持 `Free`
   - 不應平白變成 `Starter` 或 `Essential`

### 4. Essential -> Starter

1. 目前先視為商店規則驗證，不視為 app 內立即切換。
2. 若 `Starter` 與 `Essential` 在同一 subscription group：
   - `Starter -> Essential` 應立即升級
   - `Essential -> Starter` 通常應在下一個 renewal 才生效
3. 如果要驗，請同步看 RevenueCat / App Store Connect 的實際狀態。

## OCR 測試流程

### A. 已驗過主案例

1. 單邊左側主訊息
2. 左側主訊息內含引用卡
3. 主訊息 speaker 正確
4. 引用卡不拆成新訊息

### B. 下一輪優先案例

1. 多張連續截圖，兩張交界有重複短句
2. 長截圖內含日期分隔 / 系統列
3. 單 emoji、短句、續句
4. 貼圖 / 圖片 / 影片泡泡
5. 右側單邊主訊息 + 引用卡

### C. 這次 OCR 已補的保守化修正

- OCR cache 現在多綁 `conversationId`，同一批圖不會那麼容易跨對話重播舊 `contactName / warning / importPolicy`
- 短句 continuation 規則已收保守，不再只因為短就很容易被黏回前一則
- 多圖 overlap dedupe 也收保守，太短、太像真實短回覆的重複句，不會那麼容易被誤刪

## 夥伴回報格式

建議直接用這個格式：

```text
測試項目：
帳號：
步驟：
預期：
實際：
是否可重現：
截圖：
補充：
```

## 目前判斷

- `Auth`：接近完成
- `Subscription`：主流程可用，跨 Apple ID restore 仍待補測
- `OCR`：主案例可用，邊界案例持續收斂
- `送審狀態`：若沒有新的 P1，可進最後一輪 checklist
