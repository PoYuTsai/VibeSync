# Keyboard Screenshot Assist 驗收契約

更新：2026-07-27\
狀態：本機實作與契約驗證中；未 deploy、未開 rollout、未通過 signed-device gate

## 驗收原則

這個功能只對「使用者當下明確確認的一張 screenshot」負責。V1
不知道其他聊天、不猜對象、不讀 LINE history；V2
也只有使用者當次明確選定對象後，才可讀取加密、最小、短效且通過 data-quality gate
的 structured context。

以下狀態必須分開：

- implemented：程式碼已存在。
- locally verified：Windows 上可執行的 Deno／Flutter／source contract 測試通過。
- native verified：Mac/Xcode unit tests 與 signed-device matrix 通過。
- dogfood verified：production-shaped dataset、真實延遲與人工盲評過 gate。
- deployed：migration／Edge／TestFlight 已依序發布。

目前不得把 locally verified 寫成 native、dogfood 或 deployed。

## 目前可證基線

| 證據                                                      | 可說的事                                                         | 不可說的事                                                       |
| --------------------------------------------------------- | ---------------------------------------------------------------- | ---------------------------------------------------------------- |
| `docs/bug-log.md` 既有 live smoke                         | 1／2／3 張單次約 15.6／22.8／26.2 秒                             | 不是 p50／p95，也不是 Keyboard Assist current-HEAD               |
| `tools/ocr-golden/results/2026-07-02-03-51-17-local.json` | 舊 run 有 65 units，side 99.38%、recall 94.57%、precision 97.43% | 不是 current-HEAD、不是單張鍵盤 flow，quote-preview set 尚未收斂 |
| `docs/ocr-analysis-maturity-benchmark.md`                 | 定義 `<4s／<7s` 等 OCR 目標                                      | 目標不是現況                                                     |
| Attunely 影片觀察                                         | 截圖到結果的體感約十多秒，可作產品參考                           | 不是可控制條件的 benchmark                                       |

新的 current-HEAD baseline 必須帶 commit SHA、pipeline version、model
aliases、case count、fresh/cache 分流與每階段 trace。

## Hard product invariants

- [ ] V1 request 正好一張 JPEG／PNG／WebP，decoded ≤900 KiB；extra context key
      deterministic 400。
- [ ] V1 只使用 screenshot 與 bounded global voice；UI 明示「只根據這張截圖」。
- [ ] 結果正好三個實質不同策略；callback 成功時插入數 = 0。
- [ ] 只有使用者點某張 result card，且
      owner／document／operation／asset／context revision／TTL
      仍匹配時，才插入一次。
- [ ] 不支援的對話、側別不確定、provider failure、timeout、quota race 都不扣額。
- [ ] 一個 ready batch 原子扣 1 點；replay 不重扣、不重跑 provider。
- [ ] `needs_speaker_confirmation` 是 stored done／no-charge，且 ledger 不存
      transcript／OCR preview。
- [ ] transport／settlement uncertain 先用 image-free authenticated GET 查同
      request ID；GET 永不呼叫 provider。
- [ ] feature flags 預設 off；flag off 回既有文字鍵盤，不影響
      `keyboard-reply`／`analyze-chat`。
- [ ] screenshot 原圖不寫入 App Group；PhotoKit 不可行時停在 Eric
      go／no-go，不偷加 raw-image fallback。

## API／exactly-once acceptance

| Case                                        | Expected                                                                |
| ------------------------------------------- | ----------------------------------------------------------------------- |
| valid fresh POST                            | 200 ready、ledger done、usage +1                                        |
| same owner＋request ID＋same payload replay | 相同 terminal result、usage +0、provider 0 call                         |
| same ID 換一 byte image／speaker／voice     | 409 `request_replay_mismatch`                                           |
| concurrent same ID                          | 一個 owner 執行 pipeline，其餘 pending                                  |
| low side confidence                         | 200 `needs_speaker_confirmation`、done、usage +0、judge 0 call          |
| pending GET before lease expiry             | 425＋bounded `retryAfterMs`                                             |
| expired pending GET                         | conditional invalidate，410 `request_expired_no_charge`                 |
| missing／other owner GET                    | 404，不洩漏 row existence                                               |
| compiler／judge timeout                     | 503、usage +0；依確定性回正確 retry disposition                         |
| settlement uncertain                        | 保留 identity；client 必須 GET，不得自行換 ID 重扣                      |
| settle-time quota race                      | transaction rollback，無 result、無扣額                                 |
| key rotation                                | existing row 依 stored HMAC key version replay；舊 key 至少保留 25 小時 |

SQL acceptance 需在 disposable local PostgreSQL／Supabase 跑
claim、renew、takeover、settle、rollback 與 RLS；source-string test 不是
transaction proof。

## Screenshot／native acceptance

Phase 0 signed-device spike 是功能 go／no-go：

| Gate                                               |                                            Target | Current |
| -------------------------------------------------- | ------------------------------------------------: | ------- |
| keyboard 已開啟後 screenshot → PhotoKit asset 可讀 |                                     記錄 p50／p95 | 未測    |
| recent screenshot preview／preflight               |                                           p95 <1s | 未測    |
| `.authorized`／`.limited`／`.denied`               |                                fail-closed matrix | 未測    |
| iOS 13 deployment path                             |                 明確支援或另案提高 minimum target | 未測    |
| extension memory delta／peak                       |                          無 jetsam，記錄裝置與 OS | 未測    |
| documentIdentifier 在 LINE A→B                     |                                能否可靠識別需實測 | 未測    |
| extension kill／restart                            | pending metadata 可安全復原；asset 消失時不可插入 | 未測    |
| signed archive                                     |                     包含 `VibeSyncKeyboard.appex` | 未測    |

必要 cases：

- LINE／Instagram／Messages。
- iPhone SE／Pro Max／iPad floating keyboard。
- portrait／landscape／Dynamic Type／Reduce Motion。
- Full Access、Photos、consent、auth 在 idle 與 request 中途撤銷。
- request 後切換另一聊天室、另一 app、另一登入帳號。
- out-of-order callback、late callback、double tap、expired result。

任何 callback、timer、replay hydration 或 extension restart 都不得直接持有或呼叫
`textDocumentProxy.insertText`；插入只有 UI tap event → insertion coordinator
一條路。

## Context／privacy acceptance

- owner ID、consent version、createdAt／expiresAt、schema version、context
  revision 全部 required。
- AES-GCM roundtrip、tamper、wrong key、corrupt payload、atomic replacement、64
  KiB cap 都有 native tests。
- App Group 只存 allowlisted structured facts／outcome aggregate／voice；不得存
  raw history、完整 transcript、relationship heat、未驗證人格推論。
- consent revoke、logout、account delete、owner switch、partner
  merge／split／delete、data-quality downgrade 一律 purge 或 fail closed。
- write failure 保留上一份尚未過期的 valid snapshot；不可留下半檔。
- telemetry allowlist 必須丟棄 image、prompt、message、reply、contact name。
- 公開 privacy policy／App Store Connect 更新是發布 gate；repo
  文件本身不代表已發布。

## Quality／grounding acceptance

OCR set：

- ≥60 張 human-reviewed 真實單圖＋≥20 synthetic／adversarial。
- ≥20 held-out；quote-preview ≥100 independent instances，且 held-out 有覆蓋。
- side accuracy ≥98%、message recall ≥95%、precision ≥97%、最後可回應 anchor
  ≥99%。
- unsupported／non-chat false accept ≤3%。
- observed quoted-preview leak 必須為 0，並同時報 one-sided 95% upper bound。

Reply set：

- 50 contexts × 3 stochastic runs。
- screenshot 外事實、假好感分／心理診斷、prompt injection 服從皆為 0。
- ≥90% context 至少 2／3 option 可直接用。
- ≥80% context 三策略實質不同。
- 對 current keyboard baseline blinded preference ≥65%。

自動 validator 只能抓 schema、長度、策略重複、Markdown／raw JSON 與 manifest
明列的 forbidden facts；語意 grounding
與自然度必須另做人評，不能讓同一模型自評後直接宣稱通過。

## Latency acceptance

Fresh e2e 從使用者點「使用這張截圖」到三張卡 ready：

| Stage                                |        Launch target |
| ------------------------------------ | -------------------: |
| UI acknowledgment                    |           p95 <150ms |
| recent screenshot preview／preflight |              p95 <1s |
| multimodal OCR／compiler             |     p50 ≤5s、p95 ≤8s |
| judge＋finalize                      |     p50 ≤4s、p95 ≤8s |
| fresh end-to-end                     |   p50 ≤10s、p95 ≤18s |
| cache replay                         | p50 <0.2s、p95 <0.5s |

- percentile 至少用 200 個 production-shaped eligible requests。
- fresh、cache、speaker confirmation、non-chat 分桶；不可混在一起稀釋 p95。
- 記錄 auth、image decode、provider
  queue、compiler、normalize、judge、settlement。
- server 若只達 p50 ≤15s／p95 ≤25s，可進內部 dogfood，不可擴 rollout。

## 本機驗證命令

```powershell
deno test tools/keyboard-assist-benchmark/run_benchmark_test.ts `
  tools/keyboard-assist-benchmark/score_test.ts

deno test supabase/functions/keyboard-assist

flutter test test/unit/features/keyboard
```

Live benchmark 必須明確帶 local／staging endpoint；工具沒有 production
default，也不接受 CLI token。詳見 `tools/keyboard-assist-benchmark/README.md`。

## Rollout gate

1. server/client flags 都維持 off，先完成 local contract 與 transaction tests。
2. Mac/Xcode tests、signed-device PhotoKit spike 未通過前，不開 screenshot
   flag。
3. 先 internal dogfood，累積 100／200 production-shaped eligible requests與
   trace。
4. quality、privacy、latency、quota、crash／jetsam 全過才逐步 rollout。
5. 任一 hard invariant、5xx >5%、p95 >20 秒、unsupported fact、auto insert 或
   double charge，立即 server flag off；rollback 不刪 ledger、不輪替尚在 replay
   window 的 key。
