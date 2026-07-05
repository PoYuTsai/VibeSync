# 練習室稀有度真 gacha 化設計（2026-07-05）

Eric 拍板三決定：**加權真 gacha／每卡獨立稀有度（與 persona 解耦）／v1 不做保底**。

## 現狀（已查證）

- rarity 目前純前端裝飾：`lib/features/practice_chat/domain/entities/practice_girl_rarity.dart` 由 personaId 推導（teasing_humor→SR、cool_rational/clear_boundaries→R、其餘→N），server 無此欄位。
- 抽卡均勻隨機：`supabase/functions/practice-chat/practice_persona.ts` `selectPracticeDrawProfile()`，`pool[hashSeed(seed) % pool.length]`。
- 翻牌演出無 SR 差異；無保底、無重複補償。

## 1. 資料層

- Server `practice_persona.ts` 100 位 profile 各加 `rarity: 'sr' | 'r' | 'n'`，**server 為唯一真相源**。
- 總量維持 SR20/R40/N40，打散到每 persona：每型 20 位 = 4 SR / 8 R / 8 N。首版指定由實作者給預設（每型挑外型/文案較突出者），純資料日後可調。
- Client catalog 由既有 gen 腳本重產帶入 rarity；`practiceGirlRarityFor()` 改查 catalog，簽名不變，未知 id 兜底 N。
- 已知代價（接受）：舊 client（≤307）本地 persona 推導的徽章與新指定不一致，純顯示層。

## 2. Server 加權取樣

- 機率：**SR 10% / R 30% / N 60%**（現況均勻下 SR 實得 20%）。
- 演算法：候選池計算（切池 gate、排除 current、排除本窗已抽）**全不動**；之後用 `hashSeed` 派生兩值——先按權重選稀有度層，再於該層內均勻取一。維持 deterministic（同 seed 同池必同人）。
- 退避：該層候選為空 → SR→R→N 依序退層，全空回整池均勻。永遠抽得出人，絕不 400。
- 不動：冪等 replay（反查 ledger profile_id，不重取樣）、catalogSize gate（加權在切池後套用，正交）、扣費/額度/限流。

## 3. Client 呈現

- **翻牌演出本體一格不動**（紅線：CC 不畫卡背/翻面特效）。
- 揭曉結果卡：邊框/光暈套既有 `_rarityColor`（SR 金/R 紫/N 灰藍）＋rarity 徽章＋星等，沿用圖鑑元件樣式。
- SR 專屬翻牌大特效 → 另案交 Codex，不進本批。

## 4. 測試（TDD 先紅後綠）

- Deno：加權分布（固定 seed 集合大樣本，SR 10%±2%）；退避鏈；決定性；001–060 切池 gate 回歸。
- Flutter：catalog 100 位皆有 rarity 且每 persona 4/8/8；查表版 `practiceGirlRarityFor` 未知 id 回 N；圖鑑篩選/星等回歸。
- Gen 腳本重產 client catalog byte-for-byte 比對。

## 5. 交付順序

資料層 → server 加權 → client 結果卡 → Codex 雙審（高風險區）→ 全綠才 push（push=auto-deploy）。
