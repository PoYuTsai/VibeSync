#!/usr/bin/env python3
"""把 bruce_nodes.json 機械轉成四本電子書「匯入候選檔」。

原則：他的文字一個字都不改，只做結構映射。
  para→paragraph / bullets→bulletList / compare(+wswhy)→comparison
  case→dialogue+callout / warn→callout(warning) / grad→callout(principle)
  table→entryList（3 欄以上，章層級）或 bulletList（2 欄、或在條目內）

2026-09-03 真源切換（ADR #45）：assets/learning/ebooks/*.json 是產品文案的唯一真源，
這支工具只產生候選檔到 build/ebook_import_candidate/，再用 compare_ebook_import.py 依
穩定 id 比對、人工合併。輸出路徑落在正式資產目錄（含子目錄）一律直接失敗，沒有任何
旗標可以繞過——正式檔只能由人改。

    python3 tools/content/build_ebooks_from_guide.py                  # 寫到 build/ebook_import_candidate/
    python3 tools/content/build_ebooks_from_guide.py --out /tmp/cand  # 指定其他目錄
    python3 tools/content/build_ebooks_from_guide.py --nodes path/to/bruce_nodes.json
"""
import argparse
import collections
import datetime
import json
import os
import re
import sys

BASE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(BASE))
sys.path.insert(0, BASE)

GENERATOR_VERSION = '2.0.0'
OFFICIAL_DIR = os.path.join(REPO, 'assets', 'learning', 'ebooks')
DEFAULT_OUT = os.path.join(REPO, 'build', 'ebook_import_candidate')
DEFAULT_NODES = f'{BASE}/bruce_nodes.json'

# 節點資料由 main() 依參數載入；模組層級不讀檔，測試才 import 得進來。
NODES = None

SPEAKER = {'男:': 'you', '女:': 'other'}


def first_sentence(text, limit=42):
    text = re.split(r'[。！？\n]', text.strip())[0]
    return text if len(text) <= limit else text[:limit].rstrip('，、,') + '…'


class Ctx:
    """負責發 id。"""

    def __init__(self, book, chapter):
        self.prefix = f'ebook-{book}-c{chapter}'
        self.n = 0

    def nid(self, tag='b'):
        self.n += 1
        return f'{self.prefix}-{tag}{self.n}'


def convert_items(items, ctx, inside_entry=False):
    """把 parse 出來的 items 轉成我們的 block list。"""
    blocks = []
    i = 0
    while i < len(items):
        it = items[i]
        kind = it['kind']

        if kind == 'para':
            blocks.append({'type': 'paragraph', 'id': ctx.nid(), 'text': it['text']})

        elif kind == 'bullets':
            blocks.append({
                'type': 'bulletList',
                'id': ctx.nid(),
                'ordered': it['ordered'],
                'items': it['items'],
            })

        elif kind == 'compare':
            caption = None
            if i + 1 < len(items) and items[i + 1]['kind'] == 'wswhy':
                caption = items[i + 1]['text']
                i += 1
            bid = ctx.nid('cmp')
            entries = []
            for stance in ('weak', 'strong'):
                part = it.get(stance)
                if not part:
                    continue
                entries.append({
                    'id': f'{bid}-{stance[0]}',
                    'stance': stance,
                    'label': part['label'],
                    'text': part['text'],
                })
            if entries:
                block = {'type': 'comparison', 'id': bid, 'items': entries}
                if caption:
                    block['caption'] = caption
                blocks.append(block)

        elif kind == 'wswhy':
            blocks.append({'type': 'paragraph', 'id': ctx.nid(), 'text': it['text']})

        elif kind == 'case':
            blocks.extend(convert_case(it, ctx))

        elif kind == 'warn':
            block = {
                'type': 'callout',
                'id': ctx.nid('warn'),
                'tone': 'warning',
                'text': it['text'],
            }
            if it['title']:
                block['title'] = it['title']
            blocks.append(block)

        elif kind == 'grad':
            blocks.append({
                'type': 'callout',
                'id': ctx.nid('grad'),
                'tone': 'principle',
                'text': it['text'],
            })

        elif kind == 'table':
            blocks.extend(convert_table(it, ctx, inside_entry))

        elif kind == 'details':
            if it['title']:
                blocks.append({
                    'type': 'callout',
                    'id': ctx.nid('info'),
                    'tone': 'info',
                    'title': it['title'],
                    'text': '想更嚴謹的話，往下這一段是給你的。',
                })
            blocks.extend(convert_items(it['items'], ctx, inside_entry))

        i += 1
    return blocks


def convert_case(case, ctx, with_title=True):
    """對話案例 → dialogue ＋ 註解 ＋ 修正。

    [with_title] 為 False 時不放標題：案例被做成條目時，條目自己已經有標題，
    再放一次會在展開後看到同一行字兩次。
    """
    out = []
    did = ctx.nid('dlg')
    lines = []
    for idx, ln in enumerate(case['lines']):
        who = ln['who']
        speaker = SPEAKER.get(who, 'coach')
        text = ln['text']
        if speaker == 'coach' and who:
            text = f'{who} {text}'.strip()
        if not text:
            continue
        line = {
            'id': f'{did}-l{idx + 1}',
            'speaker': speaker,
            'text': text,
        }
        if ln['die']:
            line['isDeathPoint'] = True
            line['signal'] = 'red'
        if ln['mark']:
            line['annotation'] = ln['mark']
        lines.append(line)
    if lines:
        block = {'type': 'dialogue', 'id': did, 'lines': lines}
        if case['title'] and with_title:
            block['title'] = case['title']
        out.append(block)
    if case['note']:
        out.append({
            'type': 'callout',
            'id': ctx.nid('note'),
            'tone': 'info',
            'title': '這段發生了什麼',
            'text': case['note'],
        })
    if case['fix']:
        out.append({
            'type': 'callout',
            'id': ctx.nid('fix'),
            'tone': 'fix',
            'title': None,
            'text': case['fix'],
        })
    return out


def convert_table(table, ctx, inside_entry):
    rows = [r for r in table['rows'] if r['cells']]
    if not rows:
        return []
    header = rows[0]['cells'] if rows[0]['header'] else None
    body = rows[1:] if header else rows
    body = [r['cells'] for r in body if r['cells']]
    if not body:
        return []
    wide = max(len(c) for c in body) >= 3

    if wide and not inside_entry and len(body) >= 2:
        bid = ctx.nid('tbl')
        entries = []
        for idx, cells in enumerate(body):
            rest = cells[2:]
            entries.append({
                'id': f'{bid}-e{idx + 1}',
                'title': cells[0],
                'summary': cells[1] if len(cells) > 1 else None,
                'blocks': [{
                    'type': 'paragraph',
                    'id': f'{bid}-e{idx + 1}-b1',
                    'text': '｜'.join(x for x in rest if x) or (cells[1] if len(cells) > 1 else cells[0]),
                }],
            })
        for e in entries:
            if e['summary'] is None:
                del e['summary']
        block = {'type': 'entryList', 'id': bid, 'entries': entries}
        if header:
            block['caption'] = '｜'.join(header)
        return [block]

    items = ['｜'.join(x for x in cells if x) for cells in body]
    block = {'type': 'bulletList', 'id': ctx.nid('tbl'), 'items': items}
    if header:
        block['title'] = '｜'.join(header)
    return [block]


def entries_from_nodes(node_range, ctx):
    """每個 h3 小節 → 一條。"""
    entries = []
    for idx, n in enumerate(node_range):
        sub = Ctx(0, 0)
        sub.prefix = f'{ctx.prefix}-e{idx + 1}'
        blocks = convert_items(n['items'], sub, inside_entry=True)
        if not blocks:
            continue
        summary = None
        for b in blocks:
            if b['type'] == 'paragraph':
                summary = first_sentence(b['text'])
                break
            if b['type'] == 'comparison':
                strong = [x for x in b['items'] if x['stance'] == 'strong']
                if strong:
                    summary = first_sentence(strong[0]['text'])
                    break
        entry = {
            'id': f'{ctx.prefix}-e{idx + 1}',
            'title': n['sub'] or f'第 {idx + 1} 條',
            'blocks': blocks,
        }
        if summary:
            entry['summary'] = summary
        entries.append(entry)
    return entries


def entries_from_cases(node, ctx):
    entries = []
    idx = 0
    for it in node['items']:
        if it['kind'] != 'case':
            continue
        idx += 1
        sub = Ctx(0, 0)
        sub.prefix = f'{ctx.prefix}-e{idx}'
        blocks = convert_case(it, sub, with_title=False)
        entry = {
            'id': f'{ctx.prefix}-e{idx}',
            'title': it['title'] or f'案例 {idx}',
            'blocks': blocks,
        }
        if it['note']:
            entry['summary'] = first_sentence(it['note'])
        entries.append(entry)
    return entries


def entries_from_warns(node, ctx):
    entries = []
    idx = 0
    for it in node['items']:
        if it['kind'] != 'warn':
            continue
        idx += 1
        entries.append({
            'id': f'{ctx.prefix}-e{idx}',
            'title': it['title'] or f'第 {idx} 項',
            'summary': first_sentence(it['text']),
            # 保留 warning 語氣：這些是「為什麼不要這樣做」，不是中性說明。
            'blocks': [{
                'type': 'callout',
                'id': f'{ctx.prefix}-e{idx}-b1',
                'tone': 'warning',
                'text': it['text'],
            }],
        })
    return entries


def leading_paras(node, ctx):
    return convert_items(node['items'], ctx)


# ---------------------------------------------------------------------------
# 章節映射：node 索引 → 四本 × 五章
# ---------------------------------------------------------------------------

FUNNEL = json.load(open(f'{BASE}/funnel_block.json', encoding='utf-8'))

BOOKS = [
    {
        'id': 'ebook-1-bottleneck', 'number': 1, 'theme': 'compass', 'access': 'free',
        'title': '診斷 · 配對開場',
        'subtitle': '先找到卡點，再修檔案與開場',
        'goal': '找到你目前真正卡住的那一段，並先把檔案與開場修好。',
        'chapters': [
            {'title': '你卡在哪一段', 'goal': '點一次漏斗就定位你現在的階段，其餘先不要練。',
             'lead': [0, 1], 'funnel': True},
            {'title': '照片：六個功能位', 'goal': '你的六張照片各自在做什麼工作？',
             'lead': [2, 3]},
            {'title': 'Bio 與外顯呈現', 'goal': 'Bio 要過濾，也要給一個好接的鉤子。',
             'lead': [4, 5]},
            {'title': '開場：聊她／聊我／聊我們', 'goal': '一則開場要同時做到哪三件事？',
             'lead': [6, 7, 8, 9, 10]},
            {'title': '開場範例庫', 'goal': '依她的檔案類型，找一則你現在就能發的開場。',
             'lead': [11], 'entries': ('subs', list(range(12, 20))),
             'entryTitle': '八種檔案類型', 'tail': [20]},
        ],
    },
    {
        'id': 'ebook-2-conversation', 'number': 2, 'theme': 'lens', 'access': 'premium',
        'title': '續航 · 讓對話活下去',
        'subtitle': '看懂一段對話死在哪一句',
        'goal': '學會用五個標記拆解自己的對話，並停止最常見的三種死法。',
        'chapters': [
            {'title': '變數標記法 V／F／E／I／R', 'goal': '你這句話在動哪一個變數？',
             'lead': [21, 22]},
            {'title': '對話為什麼死', 'goal': '你的對話通常死在哪一種模式？',
             'lead': [23, 24]},
            {'title': '回應性與側面價值', 'goal': '怎麼讓對方覺得「你有在聽」？',
             'lead': [25, 26]},
            {'title': '情緒、玩笑與訊號讀取', 'goal': '什麼時候可以推進，什麼時候該收？',
             'lead': [27, 28, 29, 30]},
            {'title': '對話拆解庫', 'goal': '一段一段看，對話死在哪一句。',
             'entries': ('cases', 31), 'entryTitle': '逐句拆解案例'},
        ],
    },
    {
        'id': 'ebook-3-rescue', 'number': 3, 'theme': 'firstAid', 'access': 'premium',
        'title': '避雷 · 該救還是該停',
        'subtitle': '診斷樹、反效果技巧與疑難情境',
        'goal': '沒進展的時候知道要查哪一層，並避開會反效果的流行技巧。',
        'chapters': [
            {'title': '診斷樹：沒進展時怎麼查', 'goal': '問題在哪一層？從最前面開始查。',
             'lead': [53, 54, 55, 56, 57]},
            {'title': '警告區：會反效果的流行技巧', 'goal': '這些技巧為什麼會反效果？',
             'entries': ('warns', 58), 'entryTitle': '六個反效果技巧', 'lead_first': [58]},
            {'title': '疑難情境', 'goal': '遇到這些狀況時，先做哪一件事？',
             'entries': ('subs', list(range(64, 72))), 'entryTitle': '八個常見狀況'},
            {'title': '常見問題', 'goal': '那些每個人都會問的細節。',
             'entries': ('subs', list(range(72, 84))), 'entryTitle': '十二條問答'},
            {'title': '兩張表帶走', 'goal': '死亡原因排行與綠燈檢查。',
             'lead': [89, 90, 91]},
        ],
    },
    {
        'id': 'ebook-4-meeting', 'number': 4, 'theme': 'bridge', 'access': 'premium',
        'title': '約會 · 從聊天到到場',
        'subtitle': '種子、提案，以及讓她真的出現',
        'goal': '把聊得起來的對話，變成一次真的見到面的約會。',
        'chapters': [
            {'title': '時間窗與兩種卡關', 'goal': '你是沒開口，還是開口的方式錯了？',
             'lead': [32, 33]},
            {'title': '種子：模糊的是時間，不是對象', 'goal': '怎麼丟一個她接得住的鉤子？',
             'lead': [34, 35, 36, 37]},
            {'title': '提案、互惠與被拒絕之後', 'goal': '一個好提案長什麼樣子？',
             'lead': [38, 39, 40, 41]},
            {'title': '種子與提案庫', 'goal': '依話題找一個現在就能用的種子。',
             'lead': [42], 'entries': ('subs', list(range(43, 48))),
             'entryTitle': '五組現成材料'},
            {'title': '到場、十二週訓練與自評', 'goal': '答應之後，怎麼讓她真的出現？',
             'lead': [48, 49, 50, 51, 52, 59, 60, 61, 62, 63, 84, 85, 86, 87, 88]},
        ],
    },
]


VISIBLE_KEYS = {'text', 'title', 'caption', 'summary', 'label', 'annotation',
                'items', 'symptom', 'stageName', 'verdictTitle', 'verdictText',
                'targetLabel', 'intro'}


def visible_len(obj, key=None):
    if isinstance(obj, str):
        return len(obj) if key in VISIBLE_KEYS else 0
    if isinstance(obj, dict):
        return sum(visible_len(v, k) for k, v in obj.items())
    if isinstance(obj, list):
        return sum(visible_len(v, key) for v in obj)
    return 0


def prune(blocks):
    """丟掉空字串與空區塊——parser 對空字串是 fail closed 的。"""
    out = []
    for b in blocks:
        t = b['type']
        if t in ('paragraph', 'heading'):
            if not b.get('text', '').strip():
                continue
        elif t == 'bulletList':
            b['items'] = [x.strip() for x in b['items'] if x and x.strip()]
            if len(b['items']) == 0:
                continue
        elif t == 'callout':
            if not b.get('text', '').strip():
                continue
            if b.get('title') is None or not b['title'].strip():
                b.pop('title', None)
        elif t == 'comparison':
            b['items'] = [i for i in b['items']
                          if i['text'].strip() and i['label'].strip()]
            if not b['items']:
                continue
            if 'caption' in b and not b['caption'].strip():
                del b['caption']
        elif t == 'dialogue':
            b['lines'] = [l for l in b['lines'] if l['text'].strip()]
            if not b['lines']:
                continue
        elif t == 'entryList':
            kept = []
            for e in b['entries']:
                e['blocks'] = prune(e['blocks'])
                if e['blocks'] and e['title'].strip():
                    if 'summary' in e and not e['summary'].strip():
                        del e['summary']
                    kept.append(e)
            b['entries'] = kept
            if len(kept) < 2:
                continue
            if b.get('title') is None:
                b.pop('title', None)
        out.append(b)
    return out


# ---------------------------------------------------------------------------
# 交叉指涉 → crossRef 區塊
#
# 原檔到處寫「見案例 K」「課本 6.1」「見第六節」，但案例庫在第 2 本、警告區在
# 第 3 本，讀者看到那行字沒有任何辦法過去。這裡機械偵測指涉、解析目標，在該
# 條目（或該區塊）後面補一顆前往按鈕。原文一個字都不改。
#
# 解不到目標一律 raise：死連結靜默留著，比整份 build 失敗難發現得多。
# ---------------------------------------------------------------------------

CN_DIGITS = {'一': 1, '二': 2, '三': 3, '四': 4, '五': 5,
             '六': 6, '七': 7, '八': 8, '九': 9, '十': 10}

REF_PATTERNS = [
    ('case', re.compile(r'見案例\s*([A-Z])')),
    ('rule', re.compile(r'課本\s*(\d+\.\d+)')),
    ('section', re.compile(r'見第([一二三四五六七八九十]+)節')),
]

ENTRY_KEYS = ('title', 'summary')


def visible_strings(obj, key=None):
    """走訪一段 JSON，吐出所有會被讀者看到的字串。"""
    if isinstance(obj, str):
        if key in VISIBLE_KEYS:
            yield obj
    elif isinstance(obj, dict):
        for k, v in obj.items():
            yield from visible_strings(v, k)
    elif isinstance(obj, list):
        for v in obj:
            yield from visible_strings(v, key)


def build_ref_index(docs):
    """案例字母／規則編號／節號 → 跳轉目標。"""
    index = {'case': {}, 'rule': {}, 'section': {}}
    for doc in docs:
        for ci, chapter in enumerate(doc['chapters'], start=1):
            def target(entry_id=None, label=None):
                return {
                    'targetBookId': doc['id'],
                    'targetChapterId': chapter['id'],
                    'targetEntryId': entry_id,
                    'label': label,
                    'bookTitle': doc['title'],
                    'chapterNumber': ci,
                    'chapterTitle': chapter['title'],
                }

            for block in chapter['blocks']:
                if block['type'] != 'entryList':
                    continue
                for entry in block['entries']:
                    title = entry['title']
                    m = re.match(r'案例\s*([A-Z])\b', title)
                    if m:
                        index['case'][m.group(1)] = target(entry['id'], title)
                    m = re.match(r'^\W*(\d+)\.(\d+)\b', title)
                    if m:
                        index['rule'][f'{m.group(1)}.{m.group(2)}'] = \
                            target(entry['id'], title)
                        # 「第六節」= 原檔第 6 節，也就是放 6.x 那一章。
                        index['section'].setdefault(
                            int(m.group(1)), target(None, chapter['title']))
    return index


def resolve_ref(kind, raw, index):
    if kind == 'section':
        key = CN_DIGITS.get(raw)
    elif kind == 'case':
        key = raw
    else:
        key = raw
    hit = index[kind].get(key)
    if hit is None:
        raise SystemExit(f'交叉指涉解不到目標：{kind}={raw}')
    return hit


def cross_ref_block(bid, hit, same_book):
    if same_book:
        # 不再帶章名：按鈕第二行已經是目標本身的標題，帶了會比跨書那顆長一截。
        context = f'本書 · 第 {hit["chapterNumber"]} 章'
    else:
        context = f'《{hit["bookTitle"]}》第 {hit["chapterNumber"]} 章'
    block = {
        'type': 'crossRef',
        'id': bid,
        'label': hit['label'],
        'contextLabel': context,
        'targetBookId': hit['targetBookId'],
        'targetChapterId': hit['targetChapterId'],
    }
    if hit['targetEntryId']:
        block['targetEntryId'] = hit['targetEntryId']
    return block


def refs_in(obj, index):
    """依出現順序解析一段 JSON 裡的所有指涉，同一個目標只取第一次。"""
    hits = []
    seen = set()
    for text in visible_strings(obj):
        for kind, pattern in REF_PATTERNS:
            for m in pattern.finditer(text):
                hit = resolve_ref(kind, m.group(1), index)
                key = (hit['targetChapterId'], hit['targetEntryId'])
                if key in seen:
                    continue
                seen.add(key)
                hits.append(hit)
    return hits


def link_cross_refs(docs):
    index = build_ref_index(docs)
    count = 0
    for doc in docs:
        for chapter in doc['chapters']:
            linked = []
            for block in chapter['blocks']:
                linked.append(block)
                if block['type'] == 'entryList':
                    for entry in block['entries']:
                        # 條目的按鈕放在條目最後面：讀者已經讀完那段才需要它。
                        hits = [h for h in refs_in(entry, index)
                                if h['targetEntryId'] != entry['id']]
                        for n, hit in enumerate(hits, start=1):
                            entry['blocks'].append(cross_ref_block(
                                f'{entry["id"]}-xref{n}', hit,
                                hit['targetBookId'] == doc['id']))
                            count += 1
                    continue
                hits = refs_in(block, index)
                for n, hit in enumerate(hits, start=1):
                    linked.append(cross_ref_block(
                        f'{block["id"]}-xref{n}', hit,
                        hit['targetBookId'] == doc['id']))
                    count += 1
            chapter['blocks'] = linked
    print(f'交叉指涉按鈕: {count} 顆')


def build(out_dir):
    used = set()
    docs = []
    for book in BOOKS:
        chapters = []
        for ci, spec in enumerate(book['chapters'], start=1):
            ctx = Ctx(book['number'], ci)
            blocks = []
            sections = []

            for idx in spec.get('lead', []):
                used.add(idx)
                sections.append(NODES[idx]['h2title'])
                blocks.extend(leading_paras(NODES[idx], ctx))

            if spec.get('funnel'):
                blocks.insert(2, json.loads(json.dumps(FUNNEL)))

            if 'entries' in spec:
                mode, target = spec['entries']
                if mode == 'subs':
                    nodes = [NODES[i] for i in target]
                    for i in target:
                        used.add(i)
                        sections.append(NODES[i]['h2title'])
                    ctx.n += 1
                    lid = f'{ctx.prefix}-lib'
                    sub = Ctx(0, 0)
                    sub.prefix = lid
                    entries = entries_from_nodes(nodes, sub)
                elif mode == 'cases':
                    used.add(target)
                    sections.append(NODES[target]['h2title'])
                    lid = f'{ctx.prefix}-lib'
                    sub = Ctx(0, 0)
                    sub.prefix = lid
                    # 案例庫的引言段落也要保留
                    blocks.extend(convert_items(
                        [x for x in NODES[target]['items'] if x['kind'] != 'case'], ctx))
                    entries = entries_from_cases(NODES[target], sub)
                else:  # warns
                    used.add(target)
                    sections.append(NODES[target]['h2title'])
                    lid = f'{ctx.prefix}-lib'
                    sub = Ctx(0, 0)
                    sub.prefix = lid
                    blocks.extend(convert_items(
                        [x for x in NODES[target]['items'] if x['kind'] != 'warn'], ctx))
                    entries = entries_from_warns(NODES[target], sub)

                blocks.append({
                    'type': 'entryList',
                    'id': lid,
                    'title': spec.get('entryTitle'),
                    'entries': entries,
                })

            for idx in spec.get('tail', []):
                used.add(idx)
                sections.append(NODES[idx]['h2title'])
                blocks.extend(leading_paras(NODES[idx], ctx))

            blocks = prune(blocks)
            text_len = visible_len(blocks)
            chapters.append({
                'id': f'ebook-{book["number"]}-chapter-{ci}',
                'number': f'{book["number"]}.{ci}',
                'title': spec['title'],
                'learningGoal': spec['goal'],
                # 中文閱讀速度抓每分鐘 320 字，再加一分鐘給互動與思考。
                'estimatedMinutes': max(3, round(text_len / 320) + 1),
                'sourceRefs': [{
                    'document': 'partner-five-steps-guide',
                    'sections': sorted(set(sections)),
                }],
                'blocks': blocks,
            })

        doc = {
            'schemaVersion': 1,
            'id': book['id'],
            'contentVersion': 3,
            'number': book['number'],
            'title': book['title'],
            'subtitle': book['subtitle'],
            'goal': book['goal'],
            'access': book['access'],
            'theme': book['theme'],
            'estimatedMinutes': sum(c['estimatedMinutes'] for c in chapters),
            'sourceRefs': [{
                'document': 'partner-five-steps-guide',
                'sections': [f'第 {book["number"]} 部'],
            }],
            'chapters': chapters,
        }
        docs.append(doc)

    # 交叉指涉要等四本都建好才解得到目標（案例庫在第 2 本、被引用在第 3 本）。
    link_cross_refs(docs)

    for doc in docs:
        name = {1: 'book_1_bottleneck', 2: 'book_2_conversation',
                3: 'book_3_rescue', 4: 'book_4_meeting'}[doc['number']]
        path = os.path.join(out_dir, f'{name}.json')
        with open(path, 'w', encoding='utf-8', newline='\n') as fh:
            json.dump(doc, fh, ensure_ascii=False, indent=2)
            fh.write('\n')
        counts = collections.Counter()

        def walk(bs):
            for b in bs:
                counts[b['type']] += 1
                if b['type'] == 'entryList':
                    for e in b['entries']:
                        walk(e['blocks'])
        for c in doc['chapters']:
            walk(c['blocks'])
        print(f"{name}: {len(doc['chapters'])} 章, {doc['estimatedMinutes']} 分, {dict(counts)}")

    missing = sorted(set(range(len(NODES))) - used)
    print('未使用的節點:', missing if missing else '無')
    return docs


def assert_not_official_dir(out_dir, official_dir=OFFICIAL_DIR):
    """輸出路徑落在正式資產目錄（含子目錄）就直接失敗；沒有旗標可以繞過。"""
    out = os.path.realpath(out_dir)
    official = os.path.realpath(official_dir)
    if out == official or out.startswith(official + os.sep):
        raise SystemExit(
            f'拒絕寫入正式資產目錄：{out}\n'
            '正式 JSON 是產品真源（ADR #45），只能由人合併。請用 --out 指到 build/ebook_import_candidate '
            '或其他目錄，再用 compare_ebook_import.py 比對。')


def write_candidate_summary(out_dir, docs, nodes_path):
    """在候選目錄留下產生資訊與相對正式檔的差異摘要，讓 reviewer 不用自己算。"""
    from compare_ebook_import import compare_dirs, format_summary
    summary = {
        'generator': 'build_ebooks_from_guide.py',
        'generatorVersion': GENERATOR_VERSION,
        'generatedAt': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
        'nodes': os.path.relpath(nodes_path, REPO) if nodes_path.startswith(REPO) else nodes_path,
        'books': [doc['id'] for doc in docs],
    }
    if os.path.isdir(OFFICIAL_DIR):
        diff = compare_dirs(OFFICIAL_DIR, out_dir)
        summary['diffAgainstOfficial'] = diff
        print(format_summary(diff))
    with open(os.path.join(out_dir, 'candidate_summary.json'), 'w', encoding='utf-8', newline='\n') as fh:
        json.dump(summary, fh, ensure_ascii=False, indent=2)
        fh.write('\n')


def main(argv=None):
    global NODES
    parser = argparse.ArgumentParser(description='把夥伴指引節點轉成電子書匯入候選檔（不覆寫正式資產）。')
    parser.add_argument('--nodes', default=os.environ.get('PARTNER_NODES_JSON', DEFAULT_NODES),
                        help='parse_partner_guide.py 產出的節點 JSON')
    parser.add_argument('--out', default=os.environ.get('EBOOK_OUT_DIR', DEFAULT_OUT),
                        help='候選檔輸出目錄（預設 build/ebook_import_candidate；不得是正式資產目錄）')
    args = parser.parse_args(argv)
    assert_not_official_dir(args.out)
    if not os.path.exists(args.nodes):
        raise SystemExit(f'找不到節點檔：{args.nodes}（先跑 parse_partner_guide.py）')
    NODES = json.load(open(args.nodes, encoding='utf-8'))
    os.makedirs(args.out, exist_ok=True)
    docs = build(args.out)
    write_candidate_summary(args.out, docs, args.nodes)
    print(f'候選檔已寫到 {args.out}；正式檔未動。下一步：compare_ebook_import.py → 人工合併 → audit_ebook_copy.py。')


if __name__ == '__main__':
    main()
