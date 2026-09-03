#!/usr/bin/env python3
"""把 Bruce 的 index.html 解析成有結構的節點清單（不改任何一個字）。

2026-09-03 起這是「匯入候選」流程的第一步，產出的節點只給 build_ebooks_from_guide.py
產生候選檔；正式 assets 不再由工具覆寫（ADR #45）。`--write-manifest` 只把來源檔的
SHA-256 記進 partner_guide_source_manifest.json，不解析。

輸出節點：{'h2': idx, 'h2title': str, 'sub': str|None, 'items': [...]}
item 種類：para / bullets / compare / case / table / warn / grad / details
"""
import re, json, html as htmlmod, os

BASE = os.path.dirname(os.path.abspath(__file__))
# 原檔不在 repo 裡（是夥伴的檔案）。用 PARTNER_GUIDE_HTML 指過去，
# 不指就用 Eric 桌面上那份。絕不寫死某個 session 的 scratchpad 路徑。
SRC = os.environ.get(
    'PARTNER_GUIDE_HTML',
    '/mnt/c/Users/eric1/OneDrive/Desktop/bruce5stepsdatingtips.html')


def clean(s):
    """去標籤、還原實體、壓空白。保留原文用字。"""
    s = re.sub(r'<br\s*/?>', '\n', s)
    s = re.sub(r'<[^>]+>', '', s)
    s = htmlmod.unescape(s)
    s = re.sub(r'[ \t]+', ' ', s)
    return s.strip()


def parse():
    raw = open(SRC, encoding='utf-8').read()
    body = raw[raw.find('<body'):raw.find('<script')]

    # 先切出所有 h2.sec 區段
    h2s = list(re.finditer(r'<h2 class="sec"[^>]*>(.*?)</h2>', body))
    nodes = []
    for i, m in enumerate(h2s):
        start = m.end()
        end = h2s[i + 1].start() if i + 1 < len(h2s) else len(body)
        section = body[start:end]
        h2title = clean(m.group(1))
        # 段內再依 h3.sub 切
        subs = list(re.finditer(r'<h3 class="sub"[^>]*>(.*?)</h3>', section))
        chunks = []
        if subs:
            if section[:subs[0].start()].strip():
                chunks.append((None, section[:subs[0].start()]))
            for j, s in enumerate(subs):
                e = subs[j + 1].start() if j + 1 < len(subs) else len(section)
                chunks.append((clean(s.group(1)), section[s.end():e]))
        else:
            chunks.append((None, section))
        for subtitle, chunk in chunks:
            nodes.append({
                'h2': i,
                'h2title': h2title,
                'sub': subtitle,
                'items': parse_items(chunk),
            })
    return nodes


def parse_items(chunk):
    """依出現順序抽出區塊級元素。"""
    items = []
    pattern = re.compile(
        # 收尾的 lookahead 少一種容器就會整個案例被吞掉（案例 N 是某個 stage 的
        # 最後一個案例，收尾接的是 <div class="stage">，2026-07-27 之前直接消失）。
        r'<div class="case">(?P<case>.*?)</div>\s*(?=<div class="case">|<h|<div class="principles"|<div class="wrap"|<div class="stage"|$)'
        r'|<div class="ws">(?P<ws>.*?)</div>\s*</div>'
        r'|<p class="wswhy">(?P<wswhy>.*?)</p>'
        r'|<div class="warn">(?P<warn>.*?)</div>'
        r'|<div class="grad">(?P<grad>.*?)</div>'
        r'|<table class="data">(?P<table>.*?)</table>'
        r'|<details class="collapse">(?P<details>.*?)</details>'
        r'|<(?P<listtag>ul|ol)[^>]*>(?P<list>.*?)</(?P=listtag)>'
        r'|<p(?! class="wswhy")[^>]*>(?P<para>.*?)</p>',
        re.S)
    for m in pattern.finditer(chunk):
        if m.group('case') is not None:
            items.append(parse_case(m.group(0)))
        elif m.group('ws') is not None:
            items.append(parse_ws(m.group(0)))
        elif m.group('wswhy') is not None:
            items.append({'kind': 'wswhy', 'text': clean(m.group('wswhy'))})
        elif m.group('warn') is not None:
            body = m.group('warn')
            title = re.search(r'<span class="wt">(.*?)</span>', body)
            items.append({
                'kind': 'warn',
                'title': clean(title.group(1)) if title else None,
                'text': clean(re.sub(r'<span class="wt">.*?</span>', '', body, flags=re.S)),
            })
        elif m.group('grad') is not None:
            items.append({'kind': 'grad', 'text': clean(m.group('grad'))})
        elif m.group('table') is not None:
            items.append(parse_table(m.group('table')))
        elif m.group('details') is not None:
            body = m.group('details')
            summary = re.search(r'<summary>(.*?)</summary>', body, re.S)
            inner = re.sub(r'<summary>.*?</summary>', '', body, flags=re.S)
            items.append({
                'kind': 'details',
                'title': clean(summary.group(1)) if summary else None,
                'items': parse_items(inner),
            })
        elif m.group('list') is not None:
            lis = [clean(x) for x in re.findall(r'<li>(.*?)</li>', m.group('list'), re.S)]
            items.append({
                'kind': 'bullets',
                'ordered': m.group('listtag') == 'ol',
                'items': [x for x in lis if x],
            })
        elif m.group('para') is not None:
            text = clean(m.group('para'))
            if text:
                items.append({'kind': 'para', 'text': text})
    return items


def parse_case(block):
    title = re.search(r'<div class="ch">(.*?)</div>', block, re.S)
    lines = []
    for m in re.finditer(r'<div class="msg[^"]*">(.*?)</div>\s*(?=<div|$)', block, re.S):
        seg = m.group(1)
        who = re.search(r'<span class="who">(.*?)</span>', seg)
        die = 'class="die"' in seg
        mark = re.search(r'<span class="mk">(.*?)</span>', seg)
        text = re.sub(r'<span class="(who|die|mk)">.*?</span>', '', seg, flags=re.S)
        lines.append({
            'who': clean(who.group(1)) if who else '',
            'text': clean(text),
            'die': die,
            'mark': clean(mark.group(1)) if mark else None,
            'aside': 'msg aside' in m.group(0),
        })
    note = re.search(r'<div class="case-note">(.*?)</div>', block, re.S)
    fix = re.search(r'<div class="fix">(.*?)</div>', block, re.S)
    return {
        'kind': 'case',
        'title': clean(title.group(1)) if title else None,
        'lines': lines,
        'note': clean(note.group(1)) if note else None,
        'fix': clean(fix.group(1)) if fix else None,
    }


def parse_ws(block):
    out = {'kind': 'compare', 'weak': None, 'strong': None}
    for stance in ('weak', 'strong'):
        m = re.search(r'<div class="box %s">(.*?)</div>\s*(?=<div class="box|$)' % stance,
                      block, re.S)
        if not m:
            continue
        seg = m.group(1)
        label = re.search(r'<span class="t">(.*?)</span>', seg)
        text = re.sub(r'<span class="t">.*?</span>', '', seg, flags=re.S)
        out[stance] = {
            'label': clean(label.group(1)) if label else ('弱' if stance == 'weak' else '強'),
            'text': clean(text),
        }
    return out


def parse_table(block):
    rows = []
    for r in re.findall(r'<tr>(.*?)</tr>', block, re.S):
        cells = [clean(c) for c in re.findall(r'<t[hd][^>]*>(.*?)</t[hd]>', r, re.S)]
        header = '<th' in r
        rows.append({'header': header, 'cells': cells})
    return {'kind': 'table', 'rows': rows}


MANIFEST = os.path.join(BASE, 'partner_guide_source_manifest.json')
PARSER_VERSION = '1.1.0'


def write_source_manifest(src=SRC, manifest_path=MANIFEST):
    """把來源 HTML 的 SHA-256、大小與時間寫進 manifest；原檔不進 repo，只留 digest。"""
    import datetime
    import hashlib
    digest = hashlib.sha256()
    with open(src, 'rb') as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b''):
            digest.update(chunk)
    manifest = json.load(open(manifest_path, encoding='utf-8')) if os.path.exists(manifest_path) else {'schemaVersion': 1}
    source = manifest.setdefault('source', {})
    source['sha256'] = digest.hexdigest()
    source['bytes'] = os.path.getsize(src)
    source['fileName'] = os.path.basename(src)
    source['hashedAt'] = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    manifest.setdefault('generator', {})['parse_partner_guide'] = PARSER_VERSION
    with open(manifest_path, 'w', encoding='utf-8') as fh:
        json.dump(manifest, fh, ensure_ascii=False, indent=2)
        fh.write('\n')
    print(f'manifest 已更新：{manifest_path}（sha256 {source["sha256"][:12]}…）')


if __name__ == '__main__':
    import sys
    if '--write-manifest' in sys.argv:
        write_source_manifest()
        sys.exit(0)
    nodes = parse()
    out = os.environ.get('PARTNER_NODES_JSON', f'{BASE}/bruce_nodes.json')
    json.dump(nodes, open(out, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    import collections
    kinds = collections.Counter(i['kind'] for n in nodes for i in n['items'])
    print('節點數:', len(nodes))
    print('元素統計:', dict(kinds))
    for n in nodes:
        ks = collections.Counter(i['kind'] for i in n['items'])
        print(f"  h2={n['h2']:2d} sub={str(n['sub'])[:22]:24s} {dict(ks)}")
