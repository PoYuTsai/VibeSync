#!/usr/bin/env python3
"""正式電子書內容的可讀性與契約稽核（唯讀，不改任何檔案）。

    python3 tools/content/audit_ebook_copy.py                       # 人類可讀摘要
    python3 tools/content/audit_ebook_copy.py --check               # 有任何發現就 exit 1
    python3 tools/content/audit_ebook_copy.py --baseline FILE       # 只擋 baseline 沒有的新發現（棘輪）
    python3 tools/content/audit_ebook_copy.py --write-baseline FILE # 把目前發現寫成 baseline
    python3 tools/content/audit_ebook_copy.py --json FILE --markdown FILE

規則（rule id 固定，baseline 與 allowlist 都靠它）：
  R01 CJK 語境的半形標點 , : ; ! ? ( )（數字:數字、數字,數字 例外）
  R02 CJK 語境的半形符號 ... / + = > < [ "
  R03 行首／行尾空白、三個以上連續換行
  R04 paragraph／caption／annotation 內的雙換行（一個欄位塞多段）
  R05 表格攤平殘留的「｜」
  R06 欄位長度門檻（audit_rules.json lengthLimits；長度＝不含空白的字元數）
  R07 條目 summary 與內文第一段完全相同
  R08 簡體字與用字一致性（信號→訊號、勾子→鉤子、升温→升溫、Line→LINE）
  R09 第 1 冊提前使用未定義的 V／F／E／I／R 代碼
  R10 第 2 冊 2.1 的五變數 glossary 名稱必須存在
  R11 原課本內部指涉（課本 6.1、見第六節、階段 2.6、類型 A、見案例 X、DHV）
  R12 禁用詞與已廢止的教學句
  R13 P0 跨冊定稿句必須存在（整套教材至少出現一次）
  R14 結構契約：id 唯一、crossRef／漏斗目標存在、條目庫 ≥2 條且不巢狀、單選題恰一正解、查閱型章節維持條目庫

exit code：0 通過；1 有（新）發現；2 內容檔不合契約或參數錯誤。
"""
from __future__ import annotations

import argparse
import collections
import datetime
import json
import os
import re
import sys
from dataclasses import dataclass

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from ebook_schema import (  # noqa: E402
    OFFICIAL_DIR, REPO, Field, SchemaError, block_fields, catalog_fields, char_count,
    iter_blocks, load_books,
)

TOOLS_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_RULES = os.path.join(TOOLS_DIR, 'audit_rules.json')
DEFAULT_ALLOWLIST = os.path.join(TOOLS_DIR, 'audit_allowlist.json')

CJK_RE = re.compile(r'[㐀-鿿豈-﫿]')
RULE_TITLES = {
    'R01': '半形標點',
    'R02': '半形符號',
    'R03': '行首行尾空白／連續換行',
    'R04': '單段欄位含雙換行',
    'R05': '表格殘留「｜」',
    'R06': '欄位過長',
    'R07': 'summary 與內文重複',
    'R08': '簡體字／用字不一致',
    'R09': '第 1 冊未定義代碼',
    'R10': '五變數 glossary 缺漏',
    'R11': '原課本指涉',
    'R12': '禁用詞',
    'R13': 'P0 定稿句缺漏',
    'R14': '結構契約',
}
SYMBOL_PATTERNS = [
    ('...', re.compile(r'\.\.\.')),
    ('/', re.compile(r'/')),
    ('+', re.compile(r'\+')),
    ('=', re.compile(r'(?<![A-Za-z0-9])(?<![A-Za-z0-9][ \t])\s*=\s*(?![A-Za-z0-9])')),
    ('>', re.compile(r'(?<![A-Za-z0-9])(?<![A-Za-z0-9][ \t])\s*>\s*(?![A-Za-z0-9])')),
    ('<', re.compile(r'(?<![A-Za-z0-9])(?<![A-Za-z0-9][ \t])\s*<\s*(?![A-Za-z0-9])')),
    ('[', re.compile(r'\[')),
    (']', re.compile(r'\]')),
    ('"', re.compile(r'"')),
]


@dataclass
class Finding:
    rule: str
    book: str
    chapter: str
    id: str
    field: str
    message: str
    sample: str = ''

    def key(self) -> tuple:
        return (self.rule, self.id, fold_field(self.field))

    def to_dict(self) -> dict:
        return {'rule': self.rule, 'book': self.book, 'chapter': self.chapter,
                'id': self.id, 'field': self.field, 'message': self.message, 'sample': self.sample}


def _has_cjk(text: str) -> bool:
    return bool(CJK_RE.search(text))


def _sample(text: str, index: int, width: int = 14) -> str:
    return text[max(0, index - width):index + width].replace('\n', '⏎')


def _finding(rule: str, field: Field, message: str, sample: str = '') -> Finding:
    return Finding(rule, field.book_id, field.chapter_id or '', field.owner_id, field.name, message, sample)


_FOLD_MAP = str.maketrans({'，': ',', '：': ':', '；': ';', '！': '!', '？': '?', '（': '(', '）': ')', '［': '[',
                           '］': ']', '＞': '>', '＜': '<', '＝': '=', '／': '/', '＋': '+', '。': '.',
                           '「': '', '」': '', '『': '', '』': ''})


def fold_key_text(text: str) -> str:
    """finding key 用：去空白、半形化標點。正規化（工作包 1）不該讓同一個問題換身分。"""
    return re.sub(r'\s+', '', text).translate(_FOLD_MAP)


def fold_field(field: str) -> str:
    """欄位名後面的 #片語 才折疊；欄位名本身（items[1].note）原樣。"""
    name, sep, phrase = field.partition('#')
    return f'{name}{sep}{fold_key_text(phrase)}' if sep else field


# ---------------------------------------------------------------------------
# 欄位層規則
# ---------------------------------------------------------------------------

def rule_r01(fields, cfg, out):
    marks = cfg['punctuation']['halfWidth']
    allow_colon = cfg['punctuation'].get('allowDigitColon', True)
    allow_comma = cfg['punctuation'].get('allowDigitComma', True)
    for field in fields:
        text = field.text
        if not _has_cjk(text):
            continue
        found: collections.Counter = collections.Counter()
        sample = ''
        for index, ch in enumerate(text):
            if ch not in marks:
                continue
            prev = text[index - 1] if index > 0 else ''
            nxt = text[index + 1] if index + 1 < len(text) else ''
            if ch == ':' and allow_colon and prev.isdigit() and nxt.isdigit():
                continue
            if ch == ',' and allow_comma and prev.isdigit() and nxt.isdigit():
                continue
            found[ch] += 1
            if not sample:
                sample = _sample(text, index)
        if found:
            detail = ' '.join(f'{mark}×{count}' for mark, count in sorted(found.items()))
            out.append(_finding('R01', field, f'半形標點 {detail}', sample))


def rule_r02(fields, cfg, out):
    for field in fields:
        text = field.text
        if not _has_cjk(text):
            continue
        hits = []
        sample = ''
        for label, pattern in SYMBOL_PATTERNS:
            match = pattern.search(text)
            if match:
                hits.append(label)
                if not sample:
                    sample = _sample(text, match.start())
        if hits:
            out.append(_finding('R02', field, f"半形符號 {' '.join(hits)}", sample))


def rule_r03(fields, cfg, out):
    for field in fields:
        text = field.text
        problems = []
        if text != text.strip():
            problems.append('整段頭尾有空白')
        if any(line != line.strip(' \t') for line in text.split('\n')):
            problems.append('行首或行尾有空白')
        if '\n\n\n' in text:
            problems.append('三個以上連續換行')
        if problems:
            out.append(_finding('R03', field, '、'.join(problems), text[:40].replace('\n', '⏎')))


def _is_single_paragraph_field(field: Field) -> bool:
    if field.block_type == 'paragraph' and field.name == 'text':
        return True
    return field.name.endswith('caption') or field.name.endswith('annotation')


def rule_r04(fields, cfg, out):
    for field in fields:
        if _is_single_paragraph_field(field) and '\n\n' in field.text:
            count = field.text.count('\n\n') + 1
            out.append(_finding('R04', field, f'一個欄位塞了 {count} 段', field.text[:40].replace('\n', '⏎')))


def rule_r05(fields, cfg, out):
    for field in fields:
        if '｜' in field.text:
            out.append(_finding('R05', field, f"「｜」×{field.text.count('｜')}", field.text[:40].replace('\n', '⏎')))


def limit_key_for(field: Field):
    if field.kind == 'chapter' and field.name == 'title':
        return 'chapterTitle'
    if field.kind == 'entry' and field.name.endswith('summary'):
        return 'entrySummary'
    if field.kind == 'line' and field.name.endswith('.text'):
        return 'dialogueLine'
    if field.name.endswith('annotation'):
        return 'annotation'
    if field.name.endswith('caption'):
        return 'caption'
    if field.kind == 'item' and field.block_type == 'bulletList':
        return 'bulletItem'
    if field.block_type == 'paragraph' and field.name == 'text':
        return 'paragraph'
    if field.block_type == 'callout' and field.name == 'text':
        return 'calloutText'
    return None


def rule_r06(fields, cfg, out):
    limits = cfg['lengthLimits']
    for field in fields:
        key = limit_key_for(field)
        if key is None or key not in limits:
            continue
        length = char_count(field.text)
        if length > limits[key]:
            out.append(_finding('R06', field, f'{key} {length} 字，上限 {limits[key]}', field.text[:30].replace('\n', '⏎')))


def rule_r08(fields, cfg, out):
    simplified = set(cfg.get('simplifiedChars', ''))
    pairs = [(re.compile(item['pattern']), item['preferred']) for item in cfg.get('termPairs', [])]
    for field in fields:
        text = field.text
        problems = []
        chars = sorted({ch for ch in text if ch in simplified})
        if chars:
            problems.append(f"簡體字 {''.join(chars)}")
        for pattern, preferred in pairs:
            match = pattern.search(text)
            if match:
                problems.append(f'「{match.group(0)}」應為「{preferred}」')
        if problems:
            out.append(_finding('R08', field, '；'.join(problems), text[:30].replace('\n', '⏎')))


def rule_r09(fields, cfg, out):
    spec = cfg.get('undefinedCodes')
    if not spec:
        return
    pattern = re.compile(spec['pattern'])
    for field in fields:
        if field.book_id != spec['bookId']:
            continue
        match = pattern.search(field.text)
        if match:
            out.append(_finding('R09', field, f'未定義代碼「{match.group(0)}」', _sample(field.text, match.start())))


def rule_r11(fields, cfg, out):
    patterns = [re.compile(item) for item in cfg.get('textbookRefs', [])]
    for field in fields:
        hits = []
        sample = ''
        for pattern in patterns:
            match = pattern.search(field.text)
            if match:
                hits.append(match.group(0))
                if not sample:
                    sample = _sample(field.text, match.start())
        if hits:
            out.append(_finding('R11', field, f"原課本指涉「{'」「'.join(hits)}」", sample))


def rule_r12(fields, cfg, out):
    phrases = cfg.get('bannedPhrases', [])
    for field in fields:
        for phrase in phrases:
            index = field.text.find(phrase)
            if index >= 0:
                out.append(Finding('R12', field.book_id, field.chapter_id or '', field.owner_id,
                                   f'{field.name}#{fold_key_text(phrase)}', f'禁用詞「{phrase}」', _sample(field.text, index)))


# ---------------------------------------------------------------------------
# 結構層規則（需要整本書的形狀，不只是欄位）
# ---------------------------------------------------------------------------

def rule_r07(books, cfg, out):
    for _name, book in books:
        for chapter in book['chapters']:
            for block, _entry in iter_blocks(chapter['blocks']):
                if block['type'] != 'entryList':
                    continue
                for entry in block['entries']:
                    summary = (entry.get('summary') or '').strip()
                    if not summary or not entry.get('blocks'):
                        continue
                    first = entry['blocks'][0]
                    if first.get('type') in ('paragraph', 'callout') and (first.get('text') or '').strip() == summary:
                        out.append(Finding('R07', book['id'], chapter['id'], entry['id'], 'summary',
                                           f"summary 與 {first['id']} 內文相同", summary[:40]))


def rule_r10(books, cfg, out):
    spec = cfg.get('glossary')
    if not spec:
        return
    for _name, book in books:
        if book['id'] != spec['bookId']:
            continue
        for chapter in book['chapters']:
            if chapter['id'] != spec['chapterId']:
                continue
            text = '\n'.join(f.text for block, _e in iter_blocks(chapter['blocks'])
                             for f in block_fields(block, book['id'], chapter['id']))
            for label in spec['required']:
                if label not in text:
                    out.append(Finding('R10', book['id'], chapter['id'], chapter['id'], f'glossary#{label}',
                                       f'缺少 glossary 名稱「{label}」'))


def rule_r13(fields, cfg, out):
    corpus = '\n'.join(field.text for field in fields)
    for phrase in cfg.get('canonicalRequired', []):
        if phrase not in corpus:
            out.append(Finding('R13', '', '', 'catalog', f'canonical#{phrase}', f'整套教材找不到定稿句「{phrase}」'))


def rule_r14(books, cfg, out):
    block_ids: dict = {}
    entry_ids: dict = {}
    chapter_index: dict = {}
    duplicates = []
    cross_refs = []
    funnels = []
    library = cfg.get('libraryChapters', {})
    for _name, book in books:
        for chapter in book['chapters']:
            where = f"{book['id']}/{chapter['id']}"
            if chapter['id'] in chapter_index:
                duplicates.append(('章節', chapter['id'], where))
            chapter_index[chapter['id']] = book['id']
            lists = []
            for block, _entry in iter_blocks(chapter['blocks']):
                if block['id'] in block_ids:
                    duplicates.append(('區塊', block['id'], where))
                block_ids[block['id']] = where
                if block['type'] == 'entryList':
                    lists.append(block)
                    if len(block['entries']) < 2:
                        out.append(Finding('R14', book['id'], chapter['id'], block['id'], 'entries', '條目庫少於兩條'))
                    for entry in block['entries']:
                        if entry['id'] in entry_ids:
                            duplicates.append(('條目', entry['id'], where))
                        entry_ids[entry['id']] = chapter['id']
                        if any(child.get('type') == 'entryList' for child in entry.get('blocks') or []):
                            out.append(Finding('R14', book['id'], chapter['id'], entry['id'], 'blocks', '條目裡巢狀條目庫'))
                elif block['type'] == 'crossRef':
                    cross_refs.append((book['id'], chapter['id'], block))
                elif block['type'] == 'stageFunnel':
                    funnels.append((book['id'], chapter['id'], block))
                elif block['type'] == 'quiz' and block.get('mode') == 'single':
                    correct = sum(1 for choice in block['choices'] if choice.get('isCorrect'))
                    if correct != 1:
                        out.append(Finding('R14', book['id'], chapter['id'], block['id'], 'choices', f'單選題有 {correct} 個正解'))
            expected = library.get(chapter['id'])
            if expected is not None:
                biggest = max((len(item['entries']) for item in lists), default=0)
                if biggest < expected:
                    out.append(Finding('R14', book['id'], chapter['id'], chapter['id'], 'entryList',
                                       f'查閱型章節條目數 {biggest} 少於 {expected}'))
    for kind, item_id, where in duplicates:
        out.append(Finding('R14', '', '', item_id, 'id', f'{kind} id 重複（{where}）'))
    for book_id, chapter_id, block in cross_refs:
        if block['targetChapterId'] not in chapter_index or chapter_index[block['targetChapterId']] != block['targetBookId']:
            out.append(Finding('R14', book_id, chapter_id, block['id'], 'target', '交叉指涉目標章不存在'))
        target_entry = block.get('targetEntryId')
        if target_entry and entry_ids.get(target_entry) != block['targetChapterId']:
            out.append(Finding('R14', book_id, chapter_id, block['id'], 'targetEntryId', '交叉指涉目標條目不在目標章'))
    for book_id, chapter_id, block in funnels:
        for stage in block['stages']:
            if chapter_index.get(stage['targetChapterId']) != stage['targetBookId']:
                out.append(Finding('R14', book_id, chapter_id, stage['id'], 'target', '漏斗目標章不存在'))


FIELD_RULES = [rule_r01, rule_r02, rule_r03, rule_r04, rule_r05, rule_r06, rule_r08, rule_r09, rule_r11, rule_r12, rule_r13]
BOOK_RULES = [rule_r07, rule_r10, rule_r14]


# ---------------------------------------------------------------------------
# 執行、allowlist、baseline
# ---------------------------------------------------------------------------

def load_json(path: str) -> dict:
    with open(path, encoding='utf-8') as fh:
        return json.load(fh)


def apply_allowlist(findings: list, allowlist: dict) -> tuple:
    entries = allowlist.get('entries', []) if allowlist else []
    for entry in entries:
        for key in ('rule', 'id', 'reason'):
            if not entry.get(key):
                raise ValueError(f'allowlist 每一筆都要有 rule、id、reason：{entry}')
    kept = []
    suppressed = []
    for finding in findings:
        matched = any(
            entry['rule'] == finding.rule and entry['id'] == finding.id
            and (not entry.get('field') or entry['field'] == finding.field)
            for entry in entries)
        (suppressed if matched else kept).append(finding)
    return kept, suppressed


def collect_stats(books: list, fields: list, thresholds: list) -> dict:
    blocks = 0
    entries = 0
    cross_refs = 0
    chapters = 0
    per_book: dict = {}
    for _name, book in books:
        chapters += len(book['chapters'])
        book_blocks = book_entries = 0
        for chapter in book['chapters']:
            for block, _entry in iter_blocks(chapter['blocks']):
                blocks += 1
                book_blocks += 1
                if block['type'] == 'entryList':
                    entries += len(block['entries'])
                    book_entries += len(block['entries'])
                elif block['type'] == 'crossRef':
                    cross_refs += 1
        per_book[book['id']] = {'chapters': len(book['chapters']), 'blocks': book_blocks, 'entries': book_entries,
                                'strings': 0, 'chars': 0, 'readableChars': 0}
        for threshold in thresholds:
            per_book[book['id']][f'over{threshold}'] = 0
    for field in fields:
        stat = per_book[field.book_id]
        stat['strings'] += 1
        stat['chars'] += len(field.text)
        stat['readableChars'] += char_count(field.text)
        for threshold in thresholds:
            if len(field.text) >= threshold:
                stat[f'over{threshold}'] += 1
    total = {'books': len(books), 'chapters': chapters, 'blocks': blocks, 'entries': entries, 'crossRefs': cross_refs,
             'strings': sum(item['strings'] for item in per_book.values()),
             'chars': sum(item['chars'] for item in per_book.values()),
             'readableChars': sum(item['readableChars'] for item in per_book.values())}
    for threshold in thresholds:
        total[f'over{threshold}'] = sum(item[f'over{threshold}'] for item in per_book.values())
    return {'total': total, 'perBook': per_book}


def run_audit(books: list, rules_cfg: dict, allowlist: dict | None = None) -> dict:
    fields = catalog_fields(books)
    findings: list = []
    for rule in FIELD_RULES:
        rule(fields, rules_cfg, findings)
    for rule in BOOK_RULES:
        rule(books, rules_cfg, findings)
    findings, suppressed = apply_allowlist(findings, allowlist or {})
    findings.sort(key=lambda item: (item.rule, item.book, item.chapter, item.id, item.field))
    return {
        'stats': collect_stats(books, fields, rules_cfg.get('longStringThresholds', [80, 100, 120])),
        'findings': findings,
        'suppressed': suppressed,
        'byRule': collections.Counter(item.rule for item in findings),
    }


def baseline_keys(baseline: dict) -> set:
    return {(item['rule'], item['id'], fold_field(item['field'])) for item in baseline.get('findings', [])}


def compare_with_baseline(findings: list, baseline: dict) -> tuple:
    known = baseline_keys(baseline)
    current = {item.key(): item for item in findings}
    new = [item for key, item in current.items() if key not in known]
    resolved = sorted(known - set(current))
    return new, resolved


def baseline_growth(current: dict, parent: dict) -> list:
    """棘輪只准縮小：回傳 current 有、parent 沒有的鍵。
    parent 完全沒有的規則（新加的規則）准許第一次登錄它的既有發現，其餘一律是放大。"""
    parent_keys = baseline_keys(parent)
    parent_rules = {key[0] for key in parent_keys}
    return sorted(key for key in baseline_keys(current) - parent_keys if key[0] in parent_rules)


def make_baseline(findings: list, source: str) -> dict:
    return {
        'schemaVersion': 1,
        'generatedAt': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
        'source': source,
        'note': '棘輪基準：CI 只擋這份清單以外的新發現。每個工作包修掉一批問題後用 --write-baseline 縮小它，不得手動加項目。',
        'count': len(findings),
        'findings': [{'rule': item.rule, 'id': item.id, 'field': fold_field(item.field)} for item in findings],
    }


# ---------------------------------------------------------------------------
# 輸出
# ---------------------------------------------------------------------------

def format_stats(stats: dict) -> list:
    total = stats['total']
    lines = [
        f"書 {total['books']}｜章 {total['chapters']}｜區塊 {total['blocks']}｜條目 {total['entries']}｜前往按鈕 {total['crossRefs']}",
        f"可見字串 {total['strings']}｜字元 {total['chars']}（不含空白 {total['readableChars']}）"
        f"｜≥80 字元 {total.get('over80', 0)}｜≥100 {total.get('over100', 0)}｜≥120 {total.get('over120', 0)}",
    ]
    for book_id, item in stats['perBook'].items():
        lines.append(f"  {book_id}: 章 {item['chapters']} 字串 {item['strings']} 字元 {item['chars']} "
                     f"≥80 {item.get('over80', 0)} ≥120 {item.get('over120', 0)}")
    return lines


def format_report(result: dict, limit: int = 6, verbose: bool = False) -> str:
    lines = ['== 內容規模 =='] + format_stats(result['stats'])
    lines.append('')
    lines.append(f"== 發現：{len(result['findings'])} 筆（allowlist 壓掉 {len(result['suppressed'])} 筆）==")
    grouped: dict = collections.defaultdict(list)
    for finding in result['findings']:
        grouped[finding.rule].append(finding)
    for rule in sorted(RULE_TITLES):
        items = grouped.get(rule, [])
        by_book = collections.Counter(item.book or '—' for item in items)
        detail = '、'.join(f'{book} {count}' for book, count in sorted(by_book.items())) if items else '0'
        lines.append(f'{rule} {RULE_TITLES[rule]}：{len(items)}（{detail}）')
        shown = items if verbose else items[:limit]
        for item in shown:
            sample = f'　「{item.sample}」' if item.sample else ''
            lines.append(f'    {item.id}.{item.field}：{item.message}{sample}')
        if not verbose and len(items) > limit:
            lines.append(f'    …另 {len(items) - limit} 筆（--verbose 全列）')
    return '\n'.join(lines)


def format_markdown(result: dict, source: str, limit: int = 8) -> str:
    stats = result['stats']
    total = stats['total']
    lines = [
        '# 電子書內容稽核基準',
        '',
        f'來源：`{source}`　產生：{datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")}',
        '',
        '## 內容規模',
        '',
        '| 冊 | 章 | 可見字串 | 可見字元 | ≥80 | ≥100 | ≥120 |',
        '|---|---:|---:|---:|---:|---:|---:|',
    ]
    for book_id, item in stats['perBook'].items():
        lines.append(f"| {book_id} | {item['chapters']} | {item['strings']} | {item['chars']} | "
                     f"{item.get('over80', 0)} | {item.get('over100', 0)} | {item.get('over120', 0)} |")
    lines.append(f"| **合計** | **{total['chapters']}** | **{total['strings']}** | **{total['chars']}** | "
                 f"**{total.get('over80', 0)}** | **{total.get('over100', 0)}** | **{total.get('over120', 0)}** |")
    lines += ['', f"區塊 {total['blocks']}、條目 {total['entries']}、前往按鈕 {total['crossRefs']}。字元數含標點與空白；"
              f"不含空白為 {total['readableChars']}。", '', '## 發現', '',
              '| 規則 | 說明 | 筆數 | 分佈 |', '|---|---|---:|---|']
    grouped: dict = collections.defaultdict(list)
    for finding in result['findings']:
        grouped[finding.rule].append(finding)
    for rule in sorted(RULE_TITLES):
        items = grouped.get(rule, [])
        by_book = collections.Counter(item.book or '—' for item in items)
        detail = '、'.join(f'{book} {count}' for book, count in sorted(by_book.items())) if items else '—'
        lines.append(f'| {rule} | {RULE_TITLES[rule]} | {len(items)} | {detail} |')
    lines.append('')
    for rule in sorted(RULE_TITLES):
        items = grouped.get(rule, [])
        if not items:
            continue
        lines.append(f'### {rule} {RULE_TITLES[rule]}（{len(items)}）')
        lines.append('')
        for item in items[:limit]:
            sample = f'　「{item.sample}」' if item.sample else ''
            lines.append(f'- `{item.id}` {item.field}：{item.message}{sample}')
        if len(items) > limit:
            lines.append(f'- …另 {len(items) - limit} 筆，見 JSON')
        lines.append('')
    return '\n'.join(lines).rstrip() + '\n'


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('source', nargs='?', default=OFFICIAL_DIR, help='電子書 JSON 目錄（預設 assets/learning/ebooks）')
    parser.add_argument('--rules', default=DEFAULT_RULES)
    parser.add_argument('--allowlist', default=DEFAULT_ALLOWLIST)
    parser.add_argument('--check', action='store_true', help='有任何發現就 exit 1')
    parser.add_argument('--baseline', help='棘輪：只有 baseline 以外的新發現才 exit 1')
    parser.add_argument('--write-baseline', dest='write_baseline', help='把目前的發現寫成 baseline JSON')
    parser.add_argument('--parent-baseline', dest='parent_baseline',
                        help='棘輪只准縮小：--baseline 相對這份（通常是 main 的）不得多出既有規則的項目')
    parser.add_argument('--json', dest='json_path', help='完整結果寫成 JSON')
    parser.add_argument('--markdown', dest='markdown_path', help='人類可讀摘要寫成 Markdown')
    parser.add_argument('--verbose', action='store_true', help='列出全部發現')
    parser.add_argument('--quiet', action='store_true', help='只印結論')
    args = parser.parse_args(argv)

    try:
        rules_cfg = load_json(args.rules)
        allowlist = load_json(args.allowlist) if os.path.exists(args.allowlist) else {}
        books = load_books(args.source)
        result = run_audit(books, rules_cfg, allowlist)
    except (SchemaError, ValueError, OSError) as error:
        print(f'稽核無法執行：{error}', file=sys.stderr)
        return 2

    source_label = os.path.relpath(args.source, REPO) if os.path.isabs(args.source) else args.source
    if not args.quiet:
        print(format_report(result, verbose=args.verbose))
    if args.json_path:
        payload = {'source': source_label, 'stats': result['stats'],
                   'findings': [item.to_dict() for item in result['findings']],
                   'suppressed': [item.to_dict() for item in result['suppressed']]}
        with open(args.json_path, 'w', encoding='utf-8') as fh:
            json.dump(payload, fh, ensure_ascii=False, indent=2)
            fh.write('\n')
    if args.markdown_path:
        with open(args.markdown_path, 'w', encoding='utf-8') as fh:
            fh.write(format_markdown(result, source_label))
    if args.write_baseline:
        with open(args.write_baseline, 'w', encoding='utf-8') as fh:
            json.dump(make_baseline(result['findings'], source_label), fh, ensure_ascii=False, indent=2)
            fh.write('\n')
        print(f"baseline 已寫入 {args.write_baseline}（{len(result['findings'])} 筆）")

    if args.baseline:
        try:
            baseline = load_json(args.baseline)
        except (OSError, ValueError) as error:
            print(f'讀不到 baseline：{error}', file=sys.stderr)
            return 2
        if args.parent_baseline:
            try:
                parent = load_json(args.parent_baseline)
            except (OSError, ValueError) as error:
                print(f'讀不到 parent baseline：{error}', file=sys.stderr)
                return 2
            grown = baseline_growth(baseline, parent)
            if grown:
                print(f'baseline 放大了 {len(grown)} 筆（棘輪只准縮小；新規則除外）：')
                for rule, item_id, field in grown:
                    print(f'  {rule} {item_id}.{field}')
                return 1
        new, resolved = compare_with_baseline(result['findings'], baseline)
        print(f"baseline 比對：新發現 {len(new)} 筆；已解決 {len(resolved)} 筆（baseline 共 {baseline.get('count', len(baseline.get('findings', [])))} 筆）")
        for item in new:
            sample = f'　「{item.sample}」' if item.sample else ''
            print(f'  新 {item.rule} {item.id}.{item.field}：{item.message}{sample}')
        if resolved and not args.quiet:
            print('  已解決的項目可用 --write-baseline 縮小 baseline。')
        return 1 if new else 0
    if args.check:
        return 1 if result['findings'] else 0
    return 0


if __name__ == '__main__':
    sys.exit(main())
