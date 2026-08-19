# 練習室 NPC 行為評測（behavior smoke）

單元測試鎖的是 prompt **文字**（規則有沒有寫進去），這裡鎖的是模型**行為**
（規則有沒有被聽進去）。`deepseek-v4-flash` 是浮動指標，上游換版時粗俗諧音
辨識、台語理解、身份防線都可能悄悄回歸——發版前跑一次這個當警報。

## 跑法

```bash
# repo 根目錄；需要 supabase/.env 的 DEEPSEEK_API_KEY 與網路
deno run --allow-read --allow-net tools/practice-behavior-smoke/run_smoke.ts
```

任何 FAIL → exit 1。NPC 生成溫度 0.7（貼近線上），單發有隨機性：FAIL 先
重看印出的回覆內容，再判是真回歸還是抖動（連跑兩次都 FAIL 才算回歸）。

## 刻意不進 CI

需要網路與真 API key；依賴本機產物/外部服務的工具測試混進 CI 會連紅
（Dev Brain 已登記坑）。定位是 pre-release 手動關卡，跟
`tools/keyboard-assist-benchmark` 同類。

## 案例維護

`cases.ts`。收錄原則（同諧音坑筆記）：**收實測會漏的，不收覺得常見的**。
真機撞到新盲點就抄一條進來，那條就是新的回歸鎖。判準寫在 `criterion`
給 LLM 評審（temperature 0）；能用正則確定判的放 `bannedPatterns` 先跑。
