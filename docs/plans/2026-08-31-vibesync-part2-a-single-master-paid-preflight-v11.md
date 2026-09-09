# VibeSync Part 2 A｜單次延伸 Master 付費送件前清單 v11

日期：2026-08-31  
狀態：**完整劇本與 exact payload 已完成本地準備；成本已唯讀估算，尚未建立新 Job、尚未扣款。必須等待 Eric 在看見本清單後另外明確回覆「跑」。**

## 送件設定

- 模型：Seedance 2.5（model id：`seedance_2_5`）
- 模式：Video Extension（`video_extension`）
- 延伸方向：forward
- 新生成秒數：11 秒
- Master 結構：已接受 M1 v8 97 格＋預期約 264 個新格；生成後以 ffprobe 驗證，預計只裁穩定尾端 1 格，輸出 360 格／15.0000 秒
- 比例：沿用來源影片 16:9；extension 模式忽略另設 aspect ratio
- 解析度：1080p
- Bitrate：high
- 原生音效：ON（`generate_audio: true`）
- 輸出數：1
- `use_unlim`：false，使用 credits
- Reroll：OFF
- 自動 retry／自動重送：OFF

## 全部參考素材

1. 唯一直接影片／延伸權威
   - M1 v8 accepted Job：`fb7126e5-6027-45d5-956b-298dc8452b69`
   - 97 格／24 fps；Higgsfield 已完成影片 Job，可直接作延伸來源
   - 負責已接受前四秒、人物、黑長袖、兩點抓握、井道、向下方向與原生動態連續
2. Sydney Element
   - `Sydney_V3_WhiteOnepiece`
   - Element：`db109a5a-f9a4-4999-905f-7809d5e1d69a`
   - 狀態：completed
   - Prompt placeholder：`<<<db109a5a-f9a4-4999-905f-7809d5e1d69a>>>`
3. 男主 Element
   - `VibeSync_Male_M1`
   - Element：`247e5e3c-5b28-4650-be9f-4a043943f0f3`
   - 狀態：completed
   - Prompt placeholder：`<<<247e5e3c-5b28-4650-be9f-4a043943f0f3>>>`

直接靜態圖片：**0 張**。  
其他影片參考：**0 段**。  
不使用：M2A v10 錯誤成片、Sydney POV 首圖、K1、K3、K7、任何冰拓撲圖、Contact Sheet、真人夫妻握手照或 Hero phone。

## 15 秒因果與鏡頭鎖

- Master 前約 4.04 秒：已接受 M1 男主 POV，完成右手主握＋左手腕上補強。
- 延伸 0.00–4.30：固定 Sydney 主觀視角；男主有眉毛、髮際、臉側、黑袖薄霜；Sydney 看見自己兩手、雙膝與雙黑靴，雙靴磨削男主下半身殘冰外緣，橘白火花與橘金火冠蓄力，再用全身一次爆破拔出。
- 男主完全自由前不得換鏡；不得用冰霧、蒸氣或白煙遮動作。
- 延伸約 4.30：只用一次橘白峰值爆閃切到《魔戒》Gandalf 墜落式第三人稱側面中遠景。
- 第三人稱使用平牆文法：鏡頭水平看向填滿背景、與畫面平行的牆；無消失點、隧道、走廊、地平線或往畫面深處移動。Sydney 高、男主低，受力鏈陡峭近垂直；軀幹不得水平或呈 Superman 平飛。
- 延伸 4.30–6.70：兩人先由畫面上方明顯掉落至少一個身高，攝影機才輕微跟降；雙靴依序在同一垂直金屬肋持續下滑煞車，再一次蹬牆。男主只從垂直方向偏轉 45–70°、硬上限 80°；脊椎保持向下斜。煞車只減慢垂直速度，不得停住；全程保留向上井壁視差、受風晃動與側向＋向下速度。
- 延伸 6.70–8.80：男主較低、較前，Sydney 較高、較後；男主赤足先落地時 Sydney 兩靴必須仍清楚懸空。Sydney 左手腕上支撐先放、右手主握後放；男主前臂／肩／一次側滾。至少相隔約 0.35–0.50 秒後，Sydney 才以第二個獨立衝擊節拍深蹲落地。嚴禁同高平行、同步或並排落地。
- 延伸 8.80–10.35：Sydney 先讀到陰影，以一次低身斜向短側步／靴滑進安全點；男主反應慢半拍，在濕地赤足與手掌再次打滑，只能以手膝狼狽急爬半個身位。主要厚冰板在男主後肩／腳跟後方 30–50 公分砸下，暗色空白框架再砸 Sydney 舊位置；兩人反應不得同步，物件不得碰人。極前景仍保留 Hero phone 後製軌跡。
- 延伸 10.35–11.00：男主畫面左側一膝一掌、較凌亂且喘得急；Sydney 畫面右側已恢復平衡警戒低蹲，先後望向關閉的中央琥珀門縫，不揭露金魚缸。

## Prompt 鎖

- Prompt 來源：`2026-08-31-vibesync-seedance-part2-a-single-master-forward-extension-11s-v11.txt` 的 COPY ONLY 區塊。
- 送件前將兩個 @Element 名稱機械替換成上述 `<<<Element UUID>>>`，刪除末端純 @tag 行，不改其他文字。
- Exact prompt：17179 characters／17227 UTF-8 bytes。
- SHA-256：`1a93e0884bc19b3996f9b2f3edd87a0bd47c5ec04247bea6b401bcd1b58c74f1`

## 即時 credits 與成本

- 唯讀查詢時間：2026-08-31，本次 v11 準備回合
- 當下餘額：1383.25 credits
- Free-trial unlimited：不可用
- Exact payload 唯讀估算：99 credits（exact 99）
- 若成功扣款後的預期餘額：1284.25 credits
- Cost estimate 回傳唯一調整：canonical `video` 映射為 Seedance 2.5 backend 的 `video_references`
- 估算工具確認：No job submitted

## 與舊 15 秒方法的差異

- 舊 v5：全新 15 秒 Omni Reference＋4 張跨鏡位圖，曾扣 135 credits 並失敗。
- 新 v11：已接受 M1 作唯一時間軸，單次向後延伸 11 秒；0 張直接圖片，避免模型在男主 POV、Sydney POV、煞車幀與尾幀之間亂跳。
- M2A v10 錯誤 Job `96787c40-94e2-4492-8089-6f0853eec6a2` 不作任何參考。

## 硬停止線

目前不得呼叫 `generate_video`。只有 Eric 在看見本清單後另行明確回覆「跑」，才可用本清單鎖定的 exact payload 建立 1 個 Job。若建立失敗、422、NSFW、IP detect 或結果不合格，一律停下報告，不自動 retry、reroll 或重送。
