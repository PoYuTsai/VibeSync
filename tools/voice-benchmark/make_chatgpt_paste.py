#!/usr/bin/env python3
"""把 cases/*.json 轉成可直接貼 free ChatGPT 的盲測輸入。

用法：python3 make_chatgpt_paste.py
輸出：chatgpt_paste/case{1,2,3}.txt

設計原則：
- 與 app 收到的素材對齊（對話全文 + sessionContext 背景），對 ChatGPT 不多餵也不少餵。
- 三題用同一句自然人問法，避免問法差異污染盲測歸因。
- 「我／她」標記取代 isFromMe，貼上後 ChatGPT 不需要懂 JSON。
"""

import json
from pathlib import Path

CASES = [
    ("case1_chengwei_r", "case1.txt"),
    ("case2_rouyi", "case2.txt"),
    ("case3_ashley_probe", "case3.txt"),
]

ASK = "幫我看一下這段對話現在的狀況，然後告訴我接下來怎麼回比較好？"

ROOT = Path(__file__).parent
OUT = ROOT / "chatgpt_paste"
OUT.mkdir(exist_ok=True)

for case_name, out_name in CASES:
    data = json.loads((ROOT / "cases" / f"{case_name}.json").read_text(encoding="utf-8"))
    ctx = data.get("sessionContext", {})

    lines = ["以下是我跟一個女生的對話（「我」是我自己，「她」是對方）。"]
    bg = []
    if ctx.get("meetingContext"):
        bg.append(f"認識場景：{ctx['meetingContext']}")
    if ctx.get("duration"):
        bg.append(f"目前進度：{ctx['duration']}")
    if ctx.get("analysisContextNote"):
        # sessionContext 是寫給 AI 的第三人稱；真人貼 ChatGPT 會用第一人稱
        bg.append(f"補充背景：{ctx['analysisContextNote'].replace('用戶', '我')}")
    if bg:
        lines.append("")
        lines.extend(bg)
    lines.append("")
    for m in data["messages"]:
        who = "我" if m.get("isFromMe") else "她"
        # 多行訊息縮成單行，保持貼上時逐則一行
        content = m["content"].replace("\n", " / ")
        lines.append(f"{who}：{content}")
    lines.append("")
    lines.append(ASK)

    (OUT / out_name).write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"{out_name}: {len(data['messages'])} 則訊息 → {OUT / out_name}")
