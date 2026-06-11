#!/usr/bin/env python3
"""合成中線氣泡測試圖 generator（OCR golden set）。

真實圖保證不了「中線氣泡」情境（氣泡水平位置落在 42-58% 含糊帶
→ normalizeBubbleSide() 判 unknown → 測 layout repair 鏈），
故以 HTML + Windows headless Chrome 合成，CSS 精準控制氣泡位置。

跑法（WSL）：python3 generate_synthetic.py
輸出：synthetic/*.png + labels/synthetic/*.json + 自動更新 manifest.json
"""

import json
import os
import subprocess
import tempfile

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CHROME = "/mnt/c/Program Files/Google/Chrome/Application/chrome.exe"
WIDTH, HEIGHT = 780, 1500


def to_windows_path(wsl_path: str) -> str:
    return wsl_path.replace("/mnt/c/", "C:/")


# 每張圖：(id, theme, messages)
# messages: (side, text, width_pct)
#   width_pct 控制氣泡寬度——寬氣泡的視覺中心趨近 50%，製造中線含糊。
SPECS = [
    (
        "mid-light",
        "light",
        [
            ("left", "我跟你說 我今天去看了那間咖啡廳 就是上次你說藏在巷子裡面超難找的那間 結果真的有夠難找", 88),
            ("right", "哈哈哈我就說吧 我第一次去也是繞了二十分鐘才找到門口", 80),
            ("left", "對啊 而且門口完全沒有招牌 我還以為走錯地方了", 78),
            ("right", "他們的招牌就是沒有招牌 老闆說這樣才能過濾掉觀光客 只留下真的想來的人", 86),
            ("left", "這個行銷方式也太大膽了吧 不過他們的手沖真的不錯欸", 82),
            ("right", "對 我每次都點耶加雪菲 你下次可以試試看他們的肯亞", 80),
            ("left", "好 那下次一起去 你帶路我請客", 60),
            ("right", "成交 不過先說好 我要加點他們的肉桂捲 那個也超好吃", 78),
        ],
    ),
    (
        "mid-dark",
        "dark",
        [
            ("left", "欸你昨天傳給我的那部影片我看完了 結局完全出乎我意料 我以為兇手是管家結果根本不是", 88),
            ("right", "對吧對吧 我看到最後十分鐘的時候整個人從沙發上跳起來", 82),
            ("left", "而且導演前面埋的伏筆全部都收回來了 第二集什麼時候出啊", 84),
            ("right", "聽說明年春天 不過官方還沒正式公布 我已經等不及了", 80),
            ("left", "那我們到時候約出來一起看首播", 58),
            ("right", "好啊 順便把上次說好的火鍋也一起吃一吃 一次清空待辦清單", 84),
            ("left", "你這個提議我給滿分", 48),
        ],
    ),
    (
        "mid-stress",
        "stress",
        [
            ("left", "明天的聚餐你確定可以來嗎 大家都很久沒看到你了", 70),
            ("right", "可以啊 我下班直接過去 大概七點到", 62),
            ("left", "好 那我先跟餐廳說八個人 你要坐我旁邊嗎", 66),
            ("right", "當然 不然我跟其他人不熟會很尷尬", 60),
            ("left", "放心啦 他們人都很好 你來就知道了", 62),
            ("right", "希望如此 對了要不要順便帶瓶酒過去", 64),
            ("left", "帶吧 上次你帶的那瓶大家都說讚", 58),
        ],
    ),
]

THEMES = {
    # LINE 亮色：背景淺藍灰、左白右綠——顏色線索正常，含糊只來自位置
    "light": {
        "bg": "#8cabd8",
        "left_bubble": "#ffffff",
        "left_text": "#111111",
        "right_bubble": "#9ade52",
        "right_text": "#111111",
        "header_bg": "#2f4f76",
        "header_text": "#ffffff",
    },
    # LINE 暗色
    "dark": {
        "bg": "#1a1d21",
        "left_bubble": "#2e3238",
        "left_text": "#e8e8e8",
        "right_bubble": "#3a6b35",
        "right_text": "#e8e8e8",
        "header_bg": "#111316",
        "header_text": "#dddddd",
    },
    # 壓力測試：左右同色系灰、邊距內縮——位置與顏色線索同時弱化
    "stress": {
        "bg": "#202327",
        "left_bubble": "#3a3f45",
        "left_text": "#e8e8e8",
        "right_bubble": "#454a51",
        "right_text": "#e8e8e8",
        "header_bg": "#16181b",
        "header_text": "#cccccc",
    },
}

# stress 主題用窄版心：氣泡離螢幕邊緣遠，中心更貼近 50%
STRESS_INSET_PCT = 14


def build_html(theme_name: str, messages) -> str:
    t = THEMES[theme_name]
    inset = STRESS_INSET_PCT if theme_name == "stress" else 3
    rows = []
    for side, text, width_pct in messages:
        align = "flex-start" if side == "left" else "flex-end"
        bubble_bg = t[f"{side}_bubble"]
        bubble_text = t[f"{side}_text"]
        rows.append(f"""
        <div class="row" style="justify-content:{align}">
          <div class="bubble" style="background:{bubble_bg};color:{bubble_text};max-width:{width_pct}%">{text}</div>
        </div>""")
    rows_html = "\n".join(rows)
    return f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><style>
  * {{ margin:0; padding:0; box-sizing:border-box; }}
  body {{
    width:{WIDTH}px; min-height:{HEIGHT}px; background:{t["bg"]};
    font-family:"Microsoft JhengHei","PingFang TC",sans-serif; font-size:28px; line-height:1.45;
  }}
  .header {{
    background:{t["header_bg"]}; color:{t["header_text"]};
    padding:26px 30px 20px; font-size:30px; font-weight:bold;
  }}
  .chat {{ padding:24px {inset}% 40px; display:flex; flex-direction:column; gap:18px; }}
  .row {{ display:flex; }}
  .bubble {{ padding:16px 22px; border-radius:24px; word-break:break-word; }}
</style></head><body>
  <div class="header">&lt;　小琪</div>
  <div class="chat">{rows_html}</div>
</body></html>"""


def main() -> None:
    if not os.path.exists(CHROME):
        raise SystemExit(f"找不到 Chrome：{CHROME}")
    os.makedirs(f"{SCRIPT_DIR}/synthetic", exist_ok=True)
    os.makedirs(f"{SCRIPT_DIR}/labels/synthetic", exist_ok=True)

    for img_id, theme, messages in SPECS:
        html = build_html(theme, messages)
        # HTML 暫存檔必須在 /mnt/c 下，Windows Chrome 才讀得到
        with tempfile.NamedTemporaryFile(
            "w", suffix=".html", dir=SCRIPT_DIR, delete=False, encoding="utf-8"
        ) as f:
            f.write(html)
            html_path = f.name
        png_path = f"{SCRIPT_DIR}/synthetic/{img_id}.png"
        try:
            subprocess.run(
                [
                    CHROME,
                    "--headless=new",
                    "--disable-gpu",
                    "--hide-scrollbars",
                    f"--window-size={WIDTH},{HEIGHT}",
                    f"--screenshot={to_windows_path(png_path)}",
                    f"file:///{to_windows_path(html_path)}",
                ],
                check=True,
                capture_output=True,
                timeout=60,
            )
        finally:
            os.unlink(html_path)
        print(f"✓ synthetic/{img_id}.png")

        label = {
            "id": img_id,
            "contactName": "小琪",
            "classification": "valid_chat",
            "importPolicy": "allow",
            "messages": [{"side": s, "text": txt} for s, txt, _ in messages],
            "notes": f"合成中線氣泡測試（{theme}），寬氣泡視覺中心趨近 50% 壓 42-58 含糊帶",
        }
        with open(
            f"{SCRIPT_DIR}/labels/synthetic/{img_id}.json", "w", encoding="utf-8"
        ) as f:
            json.dump(label, f, ensure_ascii=False, indent=2)

    # manifest 同步（去重後 append）
    manifest_path = f"{SCRIPT_DIR}/manifest.json"
    with open(manifest_path, encoding="utf-8") as f:
        manifest = json.load(f)
    existing = {u["id"] for u in manifest["units"]}
    for img_id, theme, _ in SPECS:
        if img_id in existing:
            continue
        scenarios = ["midline"]
        if theme == "dark":
            scenarios.append("dark_mode")
        if theme == "stress":
            scenarios.append("adversarial")
        manifest["units"].append({
            "id": img_id,
            "source": "synthetic",
            "images": [f"{img_id}.png"],
            "label": f"synthetic/{img_id}.json",
            "scenarios": scenarios,
        })
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"manifest units: {len(manifest['units'])}")


if __name__ == "__main__":
    main()
