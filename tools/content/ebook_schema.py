#!/usr/bin/env python3
"""電子書內容檔的 schema 明確走訪。

鏡射 lib/features/learning/domain/models/ebook_block.dart 與
ebook_catalog_repository.dart 的欄位契約：哪些欄位是「使用者看得到的字」、哪些是
id／enum／目標 id／來源標記。所有內容工具（audit、compare、日後的正規化）都必須
經由這裡取得可見字串，不得自己寫「跳過某些 key 的泛用遞迴」——泛用 walker 會把
metadata 當文字，也會在新增 block type 時靜默漏掉欄位。這裡遇到未知型別直接 raise。

只用標準函式庫；Python 3.9+。
"""
from __future__ import annotations

import json
import os
from dataclasses import dataclass, field as dc_field
from typing import Any, Iterator, Optional

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OFFICIAL_DIR_REL = os.path.join('assets', 'learning', 'ebooks')
OFFICIAL_DIR = os.path.join(REPO, OFFICIAL_DIR_REL)

# 與 EbookCatalogRepository.productionAssetPaths 同順序；書架順序＝這個順序。
BOOK_FILES = [
    'book_1_bottleneck.json',
    'book_2_conversation.json',
    'book_3_rescue.json',
    'book_4_meeting.json',
    'book_5_core.json',
    'book_6_frames.json',
    'book_7_chat.json',
]

BLOCK_TYPES = {
    'heading', 'paragraph', 'bulletList', 'callout', 'comparison', 'dialogue',
    'flipCard', 'quiz', 'stageFunnel', 'entryList', 'crossRef', 'checklist',
}

# 這些 key 永遠不是使用者可見文字；任何工具都不得改寫。
METADATA_KEYS = {
    'id', 'type', 'tone', 'stance', 'speaker', 'signal', 'mode', 'retryPolicy',
    'revision', 'isCorrect', 'isDeathPoint', 'ordered', 'targetBookId',
    'targetChapterId', 'targetEntryId', 'number', 'unit', 'access', 'theme',
    'estimatedMinutes', 'schemaVersion', 'contentVersion', 'sourceRefs',
}


class SchemaError(ValueError):
    """內容檔不符合 Dart parser 的契約（parser 會 fail closed，這裡也是）。"""


@dataclass
class Field:
    """一個使用者看得到的字串欄位。

    container／key 讓日後的正規化工具可以原地寫回，但不參與相等比較。
    """

    book_id: str
    chapter_id: Optional[str]
    owner_id: str
    kind: str
    block_type: Optional[str]
    name: str
    text: str
    path: str
    container: Any = dc_field(default=None, repr=False, compare=False)
    key: Any = dc_field(default=None, repr=False, compare=False)

    def set_text(self, new_text: str) -> None:
        self.container[self.key] = new_text
        self.text = new_text


def load_book(path: str) -> dict:
    with open(path, encoding='utf-8') as fh:
        try:
            data = json.load(fh)
        except json.JSONDecodeError as error:
            raise SchemaError(f'{path} 不是合法 JSON：{error}') from error
    if not isinstance(data, dict):
        raise SchemaError(f'{path} 最外層必須是 JSON object')
    return data


def load_books(dir_path: str) -> list:
    """回傳 [(檔名, book dict)]，正式七冊照書架順序，其餘 json 依檔名排在後面。"""
    names = [name for name in os.listdir(dir_path) if name.endswith('.json')]
    ordered = [name for name in BOOK_FILES if name in names]
    ordered += sorted(name for name in names if name not in BOOK_FILES)
    return [(name, load_book(os.path.join(dir_path, name))) for name in ordered]


def char_count(text: str) -> int:
    """可讀長度：不含空白與換行。"""
    return sum(1 for ch in text if not ch.isspace())


def _require_id(obj: dict, where: str) -> str:
    value = obj.get('id')
    if not isinstance(value, str) or not value.strip():
        raise SchemaError(f'{where} 缺少 id')
    return value


def _require_list(obj: dict, key: str, where: str) -> list:
    value = obj.get(key)
    if not isinstance(value, list) or not value:
        raise SchemaError(f'{where}.{key} 必須是非空陣列')
    return value


def block_fields(block: dict, book_id: str, chapter_id: str) -> list:
    """一個區塊裡所有使用者可見的字串（不含條目內的巢狀區塊）。"""
    if not isinstance(block, dict):
        raise SchemaError(f'{chapter_id} 的區塊必須是 JSON object')
    bid = _require_id(block, f'{chapter_id} 的區塊')
    typ = block.get('type')
    if typ not in BLOCK_TYPES:
        raise SchemaError(f'{bid}.type 未知的區塊型別「{typ}」')
    out: list = []

    def add(container, key, name, kind='block', owner=None, required=False):
        value = container[key] if isinstance(container, list) else container.get(key)
        if value is None:
            if required:
                raise SchemaError(f'{bid}.{name} 缺少')
            return
        if not isinstance(value, str):
            raise SchemaError(f'{bid}.{name} 必須是字串')
        out.append(Field(
            book_id=book_id, chapter_id=chapter_id, owner_id=owner or bid,
            kind=kind, block_type=typ, name=name, text=value,
            path=f'{chapter_id}/{bid}.{name}', container=container, key=key,
        ))

    if typ in ('heading', 'paragraph'):
        add(block, 'text', 'text', required=True)
    elif typ == 'bulletList':
        add(block, 'title', 'title')
        items = _require_list(block, 'items', bid)
        for index in range(len(items)):
            add(items, index, f'items[{index}]', kind='item')
    elif typ == 'callout':
        add(block, 'title', 'title')
        add(block, 'text', 'text', required=True)
    elif typ == 'comparison':
        add(block, 'title', 'title')
        add(block, 'caption', 'caption')
        for index, item in enumerate(_require_list(block, 'items', bid)):
            owner = _require_id(item, f'{bid}.items[{index}]')
            add(item, 'label', f'items[{index}].label', kind='comparisonItem', owner=owner, required=True)
            add(item, 'text', f'items[{index}].text', kind='comparisonItem', owner=owner, required=True)
            add(item, 'note', f'items[{index}].note', kind='comparisonItem', owner=owner)
    elif typ == 'dialogue':
        add(block, 'title', 'title')
        add(block, 'caption', 'caption')
        for index, line in enumerate(_require_list(block, 'lines', bid)):
            owner = _require_id(line, f'{bid}.lines[{index}]')
            add(line, 'text', f'lines[{index}].text', kind='line', owner=owner, required=True)
            add(line, 'timeLabel', f'lines[{index}].timeLabel', kind='line', owner=owner)
            add(line, 'annotation', f'lines[{index}].annotation', kind='line', owner=owner)
    elif typ == 'flipCard':
        for key in ('frontTitle', 'frontText', 'backTitle', 'backText'):
            add(block, key, key, required=True)
        points = block.get('backPoints') or []
        for index in range(len(points)):
            add(points, index, f'backPoints[{index}]', kind='item')
    elif typ == 'quiz':
        add(block, 'question', 'question', required=True)
        add(block, 'scenario', 'scenario')
        add(block, 'takeaway', 'takeaway', required=True)
        for index, choice in enumerate(_require_list(block, 'choices', bid)):
            owner = _require_id(choice, f'{bid}.choices[{index}]')
            add(choice, 'text', f'choices[{index}].text', kind='choice', owner=owner, required=True)
            add(choice, 'feedback', f'choices[{index}].feedback', kind='choice', owner=owner, required=True)
    elif typ == 'stageFunnel':
        add(block, 'title', 'title', required=True)
        add(block, 'intro', 'intro', required=True)
        for index, stage in enumerate(_require_list(block, 'stages', bid)):
            owner = _require_id(stage, f'{bid}.stages[{index}]')
            for key in ('stageName', 'symptom', 'verdictTitle', 'verdictText', 'targetLabel'):
                add(stage, key, f'stages[{index}].{key}', kind='stage', owner=owner, required=True)
    elif typ == 'entryList':
        add(block, 'title', 'title')
        add(block, 'caption', 'caption')
        for index, entry in enumerate(_require_list(block, 'entries', bid)):
            owner = _require_id(entry, f'{bid}.entries[{index}]')
            add(entry, 'title', f'entries[{index}].title', kind='entry', owner=owner, required=True)
            add(entry, 'summary', f'entries[{index}].summary', kind='entry', owner=owner)
    elif typ == 'crossRef':
        add(block, 'label', 'label', required=True)
        add(block, 'contextLabel', 'contextLabel', required=True)
    elif typ == 'checklist':
        add(block, 'title', 'title')
        add(block, 'caption', 'caption')
        for index, item in enumerate(_require_list(block, 'items', bid)):
            owner = _require_id(item, f'{bid}.items[{index}]')
            add(item, 'text', f'items[{index}].text', kind='checklistItem', owner=owner, required=True)
            add(item, 'note', f'items[{index}].note', kind='checklistItem', owner=owner)
    return out


def iter_blocks(blocks: list, entry: Optional[dict] = None) -> Iterator:
    """攤平章節區塊，含條目庫裡的巢狀區塊；yield (block, 所屬條目或 None)。"""
    for block in blocks:
        yield block, entry
        if isinstance(block, dict) and block.get('type') == 'entryList':
            for child in block.get('entries') or []:
                for nested in child.get('blocks') or []:
                    if isinstance(nested, dict) and nested.get('type') == 'entryList':
                        raise SchemaError(f'{child.get("id")} 條目庫不得巢狀在條目裡')
                yield from iter_blocks(child.get('blocks') or [], child)


def iter_fields(book: dict) -> Iterator:
    """一本書裡所有使用者可見的字串，由外而內：書 → 章 → 區塊（含條目內文）。"""
    book_id = _require_id(book, '書')
    for key in ('title', 'subtitle', 'goal'):
        value = book.get(key)
        if not isinstance(value, str):
            raise SchemaError(f'{book_id}.{key} 必須是字串')
        yield Field(book_id, None, book_id, 'book', None, key, value,
                    f'{book_id}.{key}', book, key)
    for chapter in _require_list(book, 'chapters', book_id):
        chapter_id = _require_id(chapter, f'{book_id} 的章節')
        for key in ('title', 'learningGoal'):
            value = chapter.get(key)
            if not isinstance(value, str):
                raise SchemaError(f'{chapter_id}.{key} 必須是字串')
            yield Field(book_id, chapter_id, chapter_id, 'chapter', None, key, value,
                        f'{chapter_id}.{key}', chapter, key)
        for block, _entry in iter_blocks(_require_list(chapter, 'blocks', chapter_id)):
            yield from block_fields(block, book_id, chapter_id)


def catalog_fields(books: list) -> list:
    """[(檔名, book)] → 所有可見欄位（list，方便多條規則重複掃）。"""
    fields: list = []
    for _name, book in books:
        fields.extend(iter_fields(book))
    return fields
