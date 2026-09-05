#!/usr/bin/env python3
"""練習室對話主體意識：production telemetry 唯讀彙整（Phase 4.5b 監看清單）。

用法（WSL；PAT 讀 ~/.supabase/access-token）：
    python3 scripts/practice_agency_telemetry.py --hours 24 [--timeline]

抓 Edge `function_logs` 裡 practice-chat 的 `practice_chat_succeeded`／
`practice_chat_model_fallback`／`practice_chat_standard_agency_classifier_failed`，
依 practiceMode × difficulty 彙整：模型路由、fallback、forcedAct（含 read_only 佔比，
回退門檻 5%）、standard 分類器 ok/failed、statePersisted／stateSkipReason、
分類器耗時 p95、Haiku usage 估價。兩個坑：Management API 時間窗超過 24h 會靜默回 0
（固定切 6h）；連續呼叫會 429（每片之間 sleep）。practice-chat 的 logger 印的是 JSON。
"""
import argparse, collections, datetime as dt, hashlib, json, pathlib, sys, time, urllib.parse, urllib.request

REF = "fcmwrmwdoqiqdnbisdpg"
ENDPOINT = f"https://api.supabase.com/v1/projects/{REF}/analytics/endpoints/logs.all"
SLICE = dt.timedelta(hours=6)
HAIKU_PRICE = {"inputTokens": 1.0, "outputTokens": 5.0, "cacheReadInputTokens": 0.1, "cacheCreationInputTokens": 1.25}  # USD / M tokens
TPE = dt.timezone(dt.timedelta(hours=8))


def fetch(hours: float) -> list[dict]:
    pat = (pathlib.Path.home() / ".supabase" / "access-token").read_text().strip()
    end = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
    cur = end - dt.timedelta(hours=hours)
    sql = "select timestamp, event_message from function_logs where event_message like '%practice_chat_%' order by timestamp limit 1000"
    rows = []
    while cur < end:
        up = min(cur + SLICE, end)
        q = urllib.parse.urlencode({"sql": sql, "iso_timestamp_start": cur.strftime("%Y-%m-%dT%H:%M:%SZ"), "iso_timestamp_end": up.strftime("%Y-%m-%dT%H:%M:%SZ")})
        req = urllib.request.Request(f"{ENDPOINT}?{q}", headers={"Authorization": f"Bearer {pat}", "User-Agent": "curl/8.0"})
        for attempt in range(3):
            try:
                with urllib.request.urlopen(req, timeout=60) as r:
                    payload = json.load(r)
                break
            except urllib.error.HTTPError as e:
                if e.code == 429 and attempt < 2:
                    time.sleep(15); continue
                raise
        if payload.get("error"):
            sys.exit(f"logs query failed {cur:%m-%d %H:%M}Z: {payload['error']}")
        got = payload.get("result") or []
        if len(got) >= 1000:
            print(f"WARN slice {cur:%m-%d %H:%M}Z hit the 1000-row cap; shrink SLICE", file=sys.stderr)
        for row in got:
            try:
                p = json.loads(row["event_message"])
            except Exception:
                continue
            p["_ts"] = dt.datetime.fromtimestamp(int(row["timestamp"]) / 1e6, dt.timezone.utc)
            rows.append(p)
        cur = up
        time.sleep(4)
    return rows


def pct(n: int, d: int) -> str:
    return "n/a" if d == 0 else f"{n}/{d} ({100.0 * n / d:.1f}%)"


def p95(values: list[float]) -> str:
    if not values:
        return "n/a"
    s = sorted(values)
    return f"{s[min(len(s) - 1, int(round(0.95 * (len(s) - 1))))]:.0f}ms (n={len(s)})"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--hours", type=float, default=24)
    ap.add_argument("--timeline", action="store_true", help="逐輪列出（給對拍真機影片用）")
    args = ap.parse_args()
    rows = fetch(args.hours)
    chat = [p for p in rows if p.get("event") == "practice_chat_succeeded" and p.get("mode") == "chat"]
    fallbacks = [p for p in rows if p.get("event") == "practice_chat_model_fallback"]
    clf_failed = [p for p in rows if p.get("event") == "practice_chat_standard_agency_classifier_failed"]
    print(f"# practice-chat telemetry，最近 {args.hours:g} 小時（{len(rows)} 筆事件、{len(chat)} 輪 chat）\n")
    groups = collections.defaultdict(list)
    for p in chat:
        groups[(p.get("practiceMode") or "standard", p.get("difficulty"))].append(p)
    print("| mode/difficulty | 輪 | 場 | haiku | deepseek | none | forced≠null | check_out | read_only | readOnly 佔比 | standardClf ok/failed | statePersisted false (原因) | clf p95 |")
    print("|---|--:|--:|--:|--:|--:|--:|--:|--:|--|--|--|--|")
    total_read_only = 0
    for (mode, diff), ps in sorted(groups.items(), key=lambda kv: (kv[0][0], str(kv[0][1]))):
        ag = [p.get("conversationAgency") or {} for p in ps]
        models = collections.Counter(p.get("chatModel", "-") for p in ps)
        forced = collections.Counter(a.get("forcedAct") for a in ag)
        ro = sum(1 for a in ag if a.get("readOnlyReply"))
        total_read_only += ro
        clf = collections.Counter(a.get("standardClassifier") for a in ag if "standardClassifier" in a)
        skip = collections.Counter(a.get("stateSkipReason", "rpc_failed") for a in ag if a.get("statePersisted") is False)
        durs = [a["standardClassifierDurationMs"] for a in ag if isinstance(a.get("standardClassifierDurationMs"), (int, float))]
        print(f"| {mode}/{diff} | {len(ps)} | {len({p.get('session') for p in ps})} | {models.get('haiku', 0)} | {models.get('deepseek', 0)} | {models.get('none', 0)} | {sum(v for k, v in forced.items() if k)} | {forced.get('check_out', 0)} | {forced.get('read_only', 0)} | {pct(ro, len(ps))} | {clf.get('ok', 0)}/{clf.get('failed', 0)} | {sum(skip.values())} {dict(skip) if skip else ''} | {p95(durs)} |")
    print(f"\n- read_only 佔全部回合：**{pct(total_read_only, len(chat))}**（回退門檻 > 5%）")
    print(f"- Claude fallback 事件：{len(fallbacks)}；standard 分類器失敗事件：{len(clf_failed)} {collections.Counter(p.get('errorClass') for p in clf_failed) if clf_failed else ''}")
    usage = collections.Counter()
    for p in chat:
        for k, v in (p.get("chatModelUsage") or {}).items():
            if isinstance(v, (int, float)):
                usage[k] += v
    cost = sum(usage[k] / 1e6 * HAIKU_PRICE.get(k, 0) for k in usage)
    haiku_rounds = sum(1 for p in chat if p.get("chatModel") == "haiku")
    print(f"- Haiku usage：{dict(usage)} → 估 ${cost:.3f}（{haiku_rounds} 輪，每輪 ${cost / haiku_rounds if haiku_rounds else 0:.4f}）；cacheRead>0 的輪數：{sum(1 for p in chat if (p.get('chatModelUsage') or {}).get('cacheReadInputTokens', 0) > 0)}")
    forced_all = collections.Counter((p.get("practiceMode") or "standard", (p.get("conversationAgency") or {}).get("forcedAct")) for p in chat)
    print(f"- forcedAct × mode：{ {f'{m}:{f}': n for (m, f), n in forced_all.items() if f} }")
    if args.timeline:
        print("\n## 逐輪")
        for p in sorted(chat, key=lambda x: x["_ts"]):
            a = p.get("conversationAgency") or {}
            print(f"{p['_ts'].astimezone(TPE):%m-%d %H:%M:%S} u={p.get('user')} s={p.get('session')} r={p.get('roundIndex')} {p.get('practiceMode')}/{p.get('difficulty')} model={p.get('chatModel', '-')} shape={a.get('utteranceShape')} coh={a.get('coherence')} pol={a.get('policyMode')} forced={a.get('forcedAct')} unres={a.get('unresolvedCount')} clf={a.get('standardClassifier', '-')} persisted={a.get('statePersisted', '-')} ro={a.get('readOnlyReply', '')} dT={p.get('temperatureDelta')}")


if __name__ == "__main__":
    main()
