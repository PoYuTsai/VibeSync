#!/usr/bin/env python3
"""依穩定 id 比對「匯入候選檔」與「正式電子書 JSON」，只產報告、不合併。

用途：夥伴更新來源 HTML 後，先用 build_ebooks_from_guide.py 產生候選檔到
build/ebook_import_candidate/，再用這支列出：新增／刪除的 id、文字變動、區塊型別
變動、sourceRefs 變動。人工決定要把哪些差異併進正式檔；正式檔永遠不由工具覆寫。

    python3 tools/content/compare_ebook_import.py
    python3 tools/content/compare_ebook_import.py --candidate build/ebook_import_candidate --json out.json
    python3 tools/content/compare_ebook_import.py --fail-on-diff   # 有任何差異就 exit 1
"""
from __future__ import annotations

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from ebook_schema import (  # noqa: E402
    OFFICIAL_DIR, REPO, SchemaError, block_fields, iter_blocks, load_books,
)

DEFAULT_CANDIDATE_DIR = os.path.join(REPO, 'build', 'ebook_import_candidate')


def index_books(books: list) -> dict:
    """[(檔名, book)] → {book_id: {...}}，每層都以穩定 id 當 key。"""
    index: dict = {}
    for filename, book in books:
        book_id = book['id']
        entry = {
            'file': filename,
            'meta': {key: book.get(key) for key in ('title', 'subtitle', 'goal', 'contentVersion', 'sourceRefs')},
            'chapters': {},
            'blocks': {},
            'entries': {},
        }
        for order, chapter in enumerate(book['chapters']):
            chapter_id = chapter['id']
            entry['chapters'][chapter_id] = {
                'order': order,
                'meta': {key: chapter.get(key) for key in ('number', 'title', 'learningGoal', 'sourceRefs')},
            }
            for block, owner_entry in iter_blocks(chapter['blocks']):
                fields = {f.name: f.text for f in block_fields(block, book_id, chapter_id)}
                entry['blocks'][block['id']] = {
                    'chapter': chapter_id,
                    'entry': owner_entry['id'] if owner_entry else None,
                    'type': block['type'],
                    'fields': fields,
                }
                if block['type'] == 'entryList':
                    for child in block['entries']:
                        entry['entries'][child['id']] = {
                            'chapter': chapter_id,
                            'list': block['id'],
                            'title': child['title'],
                            'summary': child.get('summary'),
                        }
        index[book_id] = entry
    return index


def _diff_ids(official: dict, candidate: dict) -> tuple:
    left = set(official)
    right = set(candidate)
    return sorted(right - left), sorted(left - right), sorted(left & right)


def compare_indexes(official: dict, candidate: dict) -> dict:
    result: dict = {'books': {}, 'booksOnlyOfficial': [], 'booksOnlyCandidate': []}
    added_books, removed_books, common_books = _diff_ids(official, candidate)
    result['booksOnlyCandidate'] = added_books
    result['booksOnlyOfficial'] = removed_books
    for book_id in common_books:
        left = official[book_id]
        right = candidate[book_id]
        book_result: dict = {
            'file': left['file'],
            'metaChanged': [key for key in left['meta'] if left['meta'][key] != right['meta'][key]],
            'chapters': {'added': [], 'removed': [], 'changed': []},
            'blocks': {'added': [], 'removed': [], 'changed': []},
            'entries': {'added': [], 'removed': [], 'changed': []},
        }
        added, removed, common = _diff_ids(left['chapters'], right['chapters'])
        book_result['chapters']['added'] = added
        book_result['chapters']['removed'] = removed
        for chapter_id in common:
            changed = [key for key in left['chapters'][chapter_id]['meta']
                       if left['chapters'][chapter_id]['meta'][key] != right['chapters'][chapter_id]['meta'][key]]
            if left['chapters'][chapter_id]['order'] != right['chapters'][chapter_id]['order']:
                changed.append('order')
            if changed:
                book_result['chapters']['changed'].append({'id': chapter_id, 'fields': changed})
        added, removed, common = _diff_ids(left['blocks'], right['blocks'])
        book_result['blocks']['added'] = added
        book_result['blocks']['removed'] = removed
        for block_id in common:
            old = left['blocks'][block_id]
            new = right['blocks'][block_id]
            changed = []
            if old['type'] != new['type']:
                changed.append(f'type:{old["type"]}→{new["type"]}')
            if old['chapter'] != new['chapter'] or old['entry'] != new['entry']:
                changed.append('位置')
            for name in sorted(set(old['fields']) | set(new['fields'])):
                if old['fields'].get(name) != new['fields'].get(name):
                    changed.append(name)
            if changed:
                book_result['blocks']['changed'].append({'id': block_id, 'fields': changed})
        added, removed, common = _diff_ids(left['entries'], right['entries'])
        book_result['entries']['added'] = added
        book_result['entries']['removed'] = removed
        for entry_id in common:
            old = left['entries'][entry_id]
            new = right['entries'][entry_id]
            changed = [key for key in ('chapter', 'list', 'title', 'summary') if old[key] != new[key]]
            if changed:
                book_result['entries']['changed'].append({'id': entry_id, 'fields': changed})
        result['books'][book_id] = book_result
    result['hasDiff'] = bool(added_books or removed_books) or any(
        book['metaChanged'] or any(
            book[level][kind] for level in ('chapters', 'blocks', 'entries') for kind in ('added', 'removed', 'changed'))
        for book in result['books'].values())
    return result


def compare_dirs(official_dir: str, candidate_dir: str) -> dict:
    official = index_books(load_books(official_dir))
    candidate = index_books(load_books(candidate_dir))
    result = compare_indexes(official, candidate)
    result['officialDir'] = official_dir
    result['candidateDir'] = candidate_dir
    return result


def format_summary(result: dict, limit: int = 8) -> str:
    lines = [f"正式：{result.get('officialDir', '?')}", f"候選：{result.get('candidateDir', '?')}"]
    if result['booksOnlyCandidate']:
        lines.append(f"只在候選的書：{', '.join(result['booksOnlyCandidate'])}")
    if result['booksOnlyOfficial']:
        lines.append(f"只在正式的書：{', '.join(result['booksOnlyOfficial'])}")
    for book_id, book in result['books'].items():
        counts = []
        for level in ('chapters', 'blocks', 'entries'):
            added = len(book[level]['added'])
            removed = len(book[level]['removed'])
            changed = len(book[level]['changed'])
            if added or removed or changed:
                counts.append(f'{level} +{added} −{removed} ~{changed}')
        if book['metaChanged']:
            counts.append(f"書層欄位變動 {', '.join(book['metaChanged'])}")
        lines.append(f"{book_id}（{book['file']}）：{'；'.join(counts) if counts else '無差異'}")
        for level in ('chapters', 'blocks', 'entries'):
            for kind in ('added', 'removed'):
                for item in book[level][kind][:limit]:
                    lines.append(f"  {level} {'新增' if kind == 'added' else '刪除'}：{item}")
            for item in book[level]['changed'][:limit]:
                lines.append(f"  {level} 變動：{item['id']}（{', '.join(item['fields'])}）")
    lines.append('結論：' + ('有差異，需人工合併' if result['hasDiff'] else '無差異'))
    return '\n'.join(lines)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--official', default=OFFICIAL_DIR, help='正式 JSON 目錄（預設 assets/learning/ebooks）')
    parser.add_argument('--candidate', default=DEFAULT_CANDIDATE_DIR, help='候選 JSON 目錄（預設 build/ebook_import_candidate）')
    parser.add_argument('--json', dest='json_path', help='把完整比對結果寫成 JSON')
    parser.add_argument('--fail-on-diff', action='store_true', help='有任何差異時 exit 1（預設只報告）')
    args = parser.parse_args(argv)
    if not os.path.isdir(args.candidate):
        print(f'找不到候選目錄：{args.candidate}（先跑 build_ebooks_from_guide.py）', file=sys.stderr)
        return 2
    try:
        result = compare_dirs(args.official, args.candidate)
    except SchemaError as error:
        print(f'內容檔不合契約：{error}', file=sys.stderr)
        return 2
    print(format_summary(result))
    if args.json_path:
        with open(args.json_path, 'w', encoding='utf-8') as fh:
            json.dump(result, fh, ensure_ascii=False, indent=2)
            fh.write('\n')
    return 1 if (args.fail_on_diff and result['hasDiff']) else 0


if __name__ == '__main__':
    sys.exit(main())
