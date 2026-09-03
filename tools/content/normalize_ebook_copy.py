#!/usr/bin/env python3
"""電子書內容的排版正規化：CJK 語境的半形標點與符號改全形、清掉多餘空白、修正簡體字與用字。

ADR #45 工作包 1。只碰 ebook_schema 列出的使用者可見欄位；id／enum／目標 id／sourceRefs
一律不碰；含 URL 的欄位整欄跳過；永遠不會把欄位改成空字串。規則（每條都有 fixture 測試）：

  N01 , → ，   （數字之間例外：1,000）
  N02 : → ：   （數字之間例外：10:00、2:1）
  N03 ; → ；   ? → ？   ! → ！
  N04 ( ) → （ ）   [ ] → ［ ］
  N05 ... → ……
  N06 / → ／（並去掉兩側空白）
  N07 + → ＋；= > < → ＝ ＞ ＜（英數之間例外：V=0）
  N08 全形標點與括號旁的半形空白移除（全形空白 U+3000 不動）
  N09 每行去頭尾空白；三個以上換行壓成兩個；整段去頭尾空白
  N10 簡體字（audit_rules.json 的 simplifiedMap）與用字（termPairs）：温→溫、信號→訊號、勾子→鉤子、Line→LINE

用法：
  python3 tools/content/normalize_ebook_copy.py --check [DIR|FILES…]   # 只列會改的欄位；有待正規化 exit 1
  python3 tools/content/normalize_ebook_copy.py --diff  [DIR|FILES…]   # 印出每個欄位改前／改後
  python3 tools/content/normalize_ebook_copy.py --write FILE [FILE…]   # 只在明確指定檔案時寫入
第二次執行必須 0 diff（冪等）。
"""
from __future__ import annotations

import argparse
import collections
import json
import os
import re
import sys
from dataclasses import dataclass

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from ebook_schema import (  # noqa: E402
    OFFICIAL_DIR, REPO, Field, SchemaError, iter_fields, load_book, load_books,
)

TOOLS_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_RULES = os.path.join(TOOLS_DIR, 'audit_rules.json')

CJK_RE = re.compile(r'[㐀-鿿豈-﫿]')
URL_RE = re.compile(r'https?://|www\.')
PUNCT_MAP = {',': '，', ':': '：', ';': '；', '?': '？', '!': '！',
             '(': '（', ')': '）', '[': '［', ']': '］'}
DIGIT_KEEP = {',', ':'}   # 數字之間保留半形：1,000、10:00、2:1
ALNUM_GUARDED = {'=': '＝', '>': '＞', '<': '＜'}   # 英數之間保留：V=0
FW_NO_SPACE_BEFORE = '，。：；！？（）「」『』《》【】［］／＋＝＞＜、'
FW_NO_SPACE_AFTER = '，。：；！？（）「」『』《》【】［］／＋＝＞＜、'
_SPACE_BEFORE_FW = re.compile(r' +(?=[' + re.escape(FW_NO_SPACE_BEFORE) + '])')
_SPACE_AFTER_FW = re.compile(r'(?<=[' + re.escape(FW_NO_SPACE_AFTER) + ']) +')
_SLASH = re.compile(r'[ \t]*/[ \t]*')
_PLUS = re.compile(r'[ \t]*\+[ \t]*')
# 兩個 lookbehind：緊鄰的前一字、以及「英數＋一個空白」都不算 CJK 語境（V = 0 也要保留，不只 V=0）
_GUARDED = {half: re.compile(r'(?<![A-Za-z0-9])(?<![A-Za-z0-9][ \t])[ \t]*' + re.escape(half) + r'[ \t]*(?![A-Za-z0-9])')
            for half in ALNUM_GUARDED}


@dataclass
class Change:
    field: Field
    before: str
    after: str
    counts: collections.Counter


def load_rules(path: str = DEFAULT_RULES) -> dict:
    with open(path, encoding='utf-8') as fh:
        return json.load(fh)


def normalize_text(text: str, rules: dict) -> tuple:
    """回傳 (新文字, 各規則替換次數)。非 CJK 欄位、含 URL 的欄位原樣回傳。"""
    counts: collections.Counter = collections.Counter()
    if not CJK_RE.search(text) or URL_RE.search(text):
        return text, counts

    out = []
    length = len(text)
    for index, ch in enumerate(text):
        full = PUNCT_MAP.get(ch)
        if full is None:
            out.append(ch)
            continue
        if ch in DIGIT_KEEP:
            prev = text[index - 1] if index > 0 else ''
            nxt = text[index + 1] if index + 1 < length else ''
            if prev.isdigit() and nxt.isdigit():
                out.append(ch)
                continue
        counts[f'{ch}→{full}'] += 1
        out.append(full)
    s = ''.join(out)

    hits = s.count('...')
    if hits:
        counts['...→……'] += hits
        s = s.replace('...', '……')
    s, hits = _SLASH.subn('／', s)
    if hits:
        counts['/→／'] += hits
    s, hits = _PLUS.subn('＋', s)
    if hits:
        counts['+→＋'] += hits
    for half, full in ALNUM_GUARDED.items():
        s, hits = _GUARDED[half].subn(full, s)
        if hits:
            counts[f'{half}→{full}'] += hits

    s, hits = _SPACE_BEFORE_FW.subn('', s)
    if hits:
        counts['全形標點前空白'] += hits
    s, hits = _SPACE_AFTER_FW.subn('', s)
    if hits:
        counts['全形標點後空白'] += hits

    lines = s.split('\n')
    stripped = [line.strip() for line in lines]
    changed_lines = sum(1 for a, b in zip(lines, stripped) if a != b)
    if changed_lines:
        counts['行首行尾空白'] += changed_lines
    s = '\n'.join(stripped)
    s, hits = re.subn(r'\n{3,}', '\n\n', s)
    if hits:
        counts['連續換行壓縮'] += hits
    if s != s.strip():
        counts['整段頭尾空白'] += 1
        s = s.strip()

    for src, dst in (rules.get('simplifiedMap') or {}).items():
        hits = s.count(src)
        if hits:
            counts[f'{src}→{dst}'] += hits
            s = s.replace(src, dst)
    for item in rules.get('termPairs') or []:
        s, hits = re.subn(item['pattern'], item['preferred'], s)
        if hits:
            counts[f"→{item['preferred']}"] += hits

    if not s and text.strip():
        # 永遠不會把欄位清空（Dart parser 對空字串 fail closed）。
        return text, collections.Counter()
    return s, counts


def normalize_book(book: dict, rules: dict) -> list:
    """原地正規化一本書的可見欄位，回傳實際改動的欄位。"""
    changes = []
    for field in iter_fields(book):
        after, counts = normalize_text(field.text, rules)
        if after != field.text:
            changes.append(Change(field, field.text, after, counts))
            field.set_text(after)
    return changes


def _resolve_inputs(paths: list) -> list:
    """[(檔名, 完整路徑)]；沒給就是正式資產目錄，給目錄就展開成裡面的書。"""
    if not paths:
        paths = [OFFICIAL_DIR]
    resolved = []
    for path in paths:
        if os.path.isdir(path):
            for name, _book in load_books(path):
                resolved.append((name, os.path.join(path, name)))
        else:
            resolved.append((os.path.basename(path), path))
    return resolved


def format_file_summary(name: str, changes: list) -> str:
    total: collections.Counter = collections.Counter()
    for change in changes:
        total.update(change.counts)
    detail = ' '.join(f'{key}={value}' for key, value in sorted(total.items()))
    return f'{name}: 欄位 {len(changes)}{"，" + detail if detail else ""}'


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('paths', nargs='*', help='電子書 JSON 檔或目錄（預設 assets/learning/ebooks）')
    parser.add_argument('--rules', default=DEFAULT_RULES)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--check', action='store_true', help='只列會改的欄位；有待正規化 exit 1（預設）')
    mode.add_argument('--diff', action='store_true', help='印出每個欄位的改前／改後')
    mode.add_argument('--write', action='store_true', help='寫回；只接受明確的檔案路徑，不接受目錄')
    parser.add_argument('--json', dest='json_path', help='把各檔的替換統計寫成 JSON')
    args = parser.parse_args(argv)

    if args.write and (not args.paths or any(os.path.isdir(path) for path in args.paths)):
        print('--write 只接受明確的檔案路徑（不接受目錄、不接受省略）。', file=sys.stderr)
        return 2
    try:
        rules = load_rules(args.rules)
        inputs = _resolve_inputs(args.paths)
    except (OSError, ValueError) as error:
        print(f'無法讀取：{error}', file=sys.stderr)
        return 2

    report = {}
    pending = 0
    for name, path in inputs:
        try:
            book = load_book(path)
            changes = normalize_book(book, rules)
        except SchemaError as error:
            print(f'{name} 不合契約：{error}', file=sys.stderr)
            return 2
        pending += len(changes)
        total: collections.Counter = collections.Counter()
        for change in changes:
            total.update(change.counts)
        report[name] = {'fieldsChanged': len(changes), 'replacements': dict(sorted(total.items()))}
        print(format_file_summary(name, changes))
        if args.diff:
            for change in changes:
                print(f'  {change.field.path}')
                print('  - ' + change.before.replace('\n', '⏎'))
                print('  + ' + change.after.replace('\n', '⏎'))
        if args.write and changes:
            tmp = f'{path}.tmp'
            with open(tmp, 'w', encoding='utf-8', newline='\n') as fh:
                json.dump(book, fh, ensure_ascii=False, indent=2)
                fh.write('\n')
            os.replace(tmp, path)
    if args.json_path:
        with open(args.json_path, 'w', encoding='utf-8') as fh:
            json.dump(report, fh, ensure_ascii=False, indent=2)
            fh.write('\n')
    if args.write:
        print(f'已寫入 {sum(1 for item in report.values() if item["fieldsChanged"])} 個檔案，共 {pending} 個欄位。')
        return 0
    if args.diff:
        return 0
    return 1 if pending else 0


if __name__ == '__main__':
    sys.exit(main())
