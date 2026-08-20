# Android 備份／重裝／轉機驗證清單（AND-04）

政策：fail-closed。`allowBackup=false` 為主閘；`backup_rules.xml`（Android 11-）與
`data_extraction_rules.xml`（Android 12+ 雲端備份與 D2D 轉移）全域 exclude 為第二道欄。
靜態守門在 `test/unit/android_contract_test.dart`。

XML 只能證明我們宣告了什麼；OEM 轉移工具（Samsung Smart Switch 等）是否尊重宣告
必須實機驗證。不得使用已棄用的 `adb backup` 當證據。

## 實機驗證步驟（每項記錄裝置型號與 Android 版本）

1. **重裝**：安裝 → 登入、產生聊天／分析資料 → 解除安裝 → 重新安裝。
   預期：回到未登入的全新狀態；不得出現舊 token 自動登入、殘留聊天或解密錯誤 crash。
2. **雲端還原**：裝置 A 開啟 Google 備份並觸發備份（設定 → Google → 備份），
   在裝置 B 以同帳號還原。預期：VibeSync 資料不在還原清單中；App 首啟為全新狀態。
3. **D2D 轉機**：用系統轉移流程（Pixel 線傳／Samsung Smart Switch）從 A 轉到 B。
   預期：App 可被複製安裝，但登入狀態、聊天、圖片不隨行；首啟不得 crash。
4. **解密失敗容錯**：若任何路徑導致部分資料殘留（OEM 不尊重宣告），App 首啟必須
   走全新狀態或明確重登，不得 crash、不得顯示他人／舊帳號殘留內容。

## 支援矩陣（最低）

- 一台 stock Android（Pixel，Android 14+）。
- 一台 Samsung One UI（Smart Switch 路徑）。
- API 24 模擬器僅驗安裝與冷啟動（無 D2D）。
