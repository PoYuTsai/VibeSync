"""normalize_ebook_copy.py 的 fixture 測試：每條規則一個正例與一個必須不動的反例。

    python3 -m unittest tools.content.tests.test_normalize_ebook_copy -v
"""
import copy
import io
import json
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

TOOLS_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS_DIR)

import ebook_schema as schema  # noqa: E402
import normalize_ebook_copy as norm  # noqa: E402

RULES = norm.load_rules()


def n(text):
    return norm.normalize_text(text, RULES)[0]


class NormalizeTextTests(unittest.TestCase):
    def test_n01_n03_punctuation_in_cjk_context(self):
        self.assertEqual(n('如果你兩週只配對到 3 個人,就算技巧完美;天花板也是 3!為什麼?'),
                         '如果你兩週只配對到 3 個人，就算技巧完美；天花板也是 3！為什麼？')
        self.assertEqual(n('第二個觀念:失敗很常見'), '第二個觀念：失敗很常見')

    def test_digit_exceptions_keep_half_width(self):
        self.assertEqual(n('晚上 10:00 見，比例 2:1，總共 1,000 元。'), '晚上 10:00 見，比例 2:1，總共 1,000 元。')
        self.assertEqual(n('(晚上 10:00)哈哈哈那個真的很扯'), '（晚上 10:00）哈哈哈那個真的很扯')

    def test_pure_ascii_and_url_fields_untouched(self):
        self.assertEqual(n('pure ascii, no cjk (skip)?'), 'pure ascii, no cjk (skip)?')
        self.assertEqual(n('連結: https://example.com/a?b=1,c'), '連結: https://example.com/a?b=1,c')
        self.assertEqual(n('...'), '...')  # 沒有 CJK 的訊息「...」不動

    def test_n04_brackets(self):
        self.assertEqual(n('好啊 [帳號]。我 IG 很無聊(都是食物)'), '好啊［帳號］。我 IG 很無聊（都是食物）')
        self.assertEqual(n('(1)選擇效應是反的'), '（1）選擇效應是反的')

    def test_n05_ellipsis(self):
        self.assertEqual(n('不知道你會不會想...如果你有空的話'), '不知道你會不會想……如果你有空的話')

    def test_n06_slash(self):
        self.assertEqual(n('改天約? / 有空出來吃飯?'), '改天約？／有空出來吃飯？')
        self.assertEqual(n('只有 I,沒有 V/E/R'), '只有 I，沒有 V／E／R')
        self.assertEqual(n('她很快就問你要 IG / Line'), '她很快就問你要 IG／LINE')

    def test_n07_symbols_with_alnum_guard(self):
        self.assertEqual(n('一句具體生活細節 + 一句幽默'), '一句具體生活細節＋一句幽默')
        self.assertEqual(n('紅燈之後繼續加壓 = 死亡'), '紅燈之後繼續加壓＝死亡')
        self.assertEqual(n('行為 > 情緒 > 字面'), '行為＞情緒＞字面')
        self.assertEqual(n('整段只有 I,V=0、E=0、R=0'), '整段只有 I，V=0、E=0、R=0')
        self.assertEqual(n('中文 V = 0 也是英數比較'), '中文 V = 0 也是英數比較')  # 有空白的英數運算子一樣保留

    def test_n08_spaces_next_to_full_width_punctuation(self):
        self.assertEqual(n('❌ 錯誤: 在嗎? / 是不是討厭我了'), '❌ 錯誤：在嗎？／是不是討厭我了')
        self.assertEqual(n('V↑(有辨識力、有工作)E↑(具體畫面)。開口:她可糾正你'),
                         'V↑（有辨識力、有工作）E↑（具體畫面）。開口：她可糾正你')
        # 全形空白（U+3000）與英數間的半形空白都不是目標
        self.assertEqual(n('V↑（側面露出）　E↑（自嘲）· 開口成本低'), 'V↑（側面露出）　E↑（自嘲）· 開口成本低')
        self.assertEqual(n('兩週內配對到 3 個人'), '兩週內配對到 3 個人')

    def test_n09_lines_and_newlines(self):
        self.assertEqual(n('修正:\n\n 男:發生什麼事\n\n\n 通用原則:情緒是開口 '),
                         '修正：\n\n男：發生什麼事\n\n通用原則：情緒是開口')

    def test_n10_simplified_and_terms(self):
        self.assertEqual(n('關係升温了，留一個勾子，這是好的信號，加個 Line。'),
                         '關係升溫了，留一個鉤子，這是好的訊號，加個 LINE。')
        self.assertEqual(n('Online 課程與 Airline'), 'Online 課程與 Airline')  # Line 只換獨立字

    def test_never_empties_a_field(self):
        self.assertEqual(n('　'), '　')  # 全形空白不在規則裡，原樣
        text, counts = norm.normalize_text(' \n ', RULES)
        self.assertEqual((text, dict(counts)), (' \n ', {}))  # 沒有 CJK 不動

    def test_idempotent(self):
        samples = ['第 5 句修正:中山區?那你晚上應該有很多不該有的宵夜選擇。\nE↑(誇張化) V↑(住信義區,側面) 開口:她可推薦、吐槽、反問。',
                   '「改天約?」——改天不存在\n 「你什麼時候有空?」——把工作丟給她,還要她先承諾',
                   '🟢 綠燈:主動加碼、超出你問的']
        for sample in samples:
            once = n(sample)
            self.assertEqual(n(once), once, sample)

    def test_counts_report_each_rule(self):
        _text, counts = norm.normalize_text('你好,世界:再見?', RULES)
        self.assertEqual(dict(counts), {',→，': 1, ':→：': 1, '?→？': 1})


class NormalizeBookTests(unittest.TestCase):
    def _book(self):
        bid = 'ebook-9-fixture'
        return {
            'schemaVersion': 1, 'id': bid, 'contentVersion': 1, 'number': 9, 'unit': 'ultimateGuide',
            'title': '測試 · 書', 'subtitle': '副標,半形', 'goal': '目標', 'access': 'premium', 'theme': 'compass',
            'estimatedMinutes': 3, 'sourceRefs': [{'document': 'doc, with comma', 'sections': ['第 1 部, x']}],
            'chapters': [{
                'id': f'{bid}-chapter-1', 'number': '9.1', 'title': '章名(半形)', 'learningGoal': '目標?',
                'estimatedMinutes': 3, 'sourceRefs': [{'document': 'doc', 'sections': ['x']}],
                'blocks': [
                    {'type': 'paragraph', 'id': f'{bid}-p1,id', 'text': '一段,半形'},
                    {'type': 'dialogue', 'id': f'{bid}-d', 'lines': [
                        {'id': f'{bid}-d-l1', 'speaker': 'you', 'text': '嗨,你好', 'timeLabel': '10:00'},
                    ]},
                    {'type': 'crossRef', 'id': f'{bid}-x', 'label': '案例 K · 完整弧線(她比較被動的版本)',
                     'contextLabel': '《續航》第 5 章', 'targetBookId': 'book,id', 'targetChapterId': 'ch:1'},
                    {'type': 'bulletList', 'id': f'{bid}-b', 'items': ['A. 配對數｜兩週內,配對到幾個']},
                ],
            }],
        }

    def test_only_visible_fields_change_and_metadata_is_untouched(self):
        book = self._book()
        original = copy.deepcopy(book)
        changes = norm.normalize_book(book, RULES)
        changed = {c.field.path for c in changes}
        self.assertIn('ebook-9-fixture.subtitle', changed)
        self.assertIn('ebook-9-fixture-chapter-1.title', changed)
        self.assertIn('ebook-9-fixture-chapter-1/ebook-9-fixture-p1,id.text', changed)
        self.assertIn('ebook-9-fixture-chapter-1/ebook-9-fixture-x.label', changed)
        self.assertEqual(book['chapters'][0]['blocks'][0]['text'], '一段，半形')
        self.assertEqual(book['chapters'][0]['blocks'][3]['items'], ['A. 配對數｜兩週內，配對到幾個'])
        # metadata 一個字都不動
        self.assertEqual(book['sourceRefs'], original['sourceRefs'])
        self.assertEqual(book['chapters'][0]['blocks'][0]['id'], original['chapters'][0]['blocks'][0]['id'])
        self.assertEqual(book['chapters'][0]['blocks'][2]['targetBookId'], 'book,id')
        self.assertEqual(book['chapters'][0]['blocks'][2]['targetChapterId'], 'ch:1')
        self.assertEqual(book['chapters'][0]['blocks'][1]['lines'][0]['timeLabel'], '10:00')
        self.assertEqual(book['chapters'][0]['blocks'][1]['lines'][0]['speaker'], 'you')
        # 第二次 0 變動
        self.assertEqual(norm.normalize_book(book, RULES), [])

    def test_cli_modes_and_exit_codes(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, 'book_9_fixture.json')
            with open(path, 'w', encoding='utf-8') as fh:
                json.dump(self._book(), fh, ensure_ascii=False, indent=2)
            with redirect_stdout(io.StringIO()):
                self.assertEqual(norm.main(['--check', path]), 1)
                self.assertEqual(norm.main(['--diff', path]), 0)
                self.assertEqual(norm.main(['--write', tmp]), 2)   # 目錄不准寫
                self.assertEqual(norm.main(['--write']), 2)        # 省略路徑不准寫
                self.assertEqual(norm.main(['--write', path]), 0)
                self.assertEqual(norm.main(['--check', path]), 0)  # 冪等
            written = open(path, encoding='utf-8').read()
            self.assertTrue(written.endswith('}\n'))
            self.assertEqual(json.loads(written)['chapters'][0]['blocks'][0]['text'], '一段，半形')


@unittest.skipUnless(os.path.isdir(schema.OFFICIAL_DIR), '正式內容資產不在')
class ProductionNormalizationTests(unittest.TestCase):
    def test_official_assets_are_already_normalized(self):
        """工作包 1 之後正式內容必須維持正規化；有人加回半形標點時這條會紅。"""
        pending = []
        for name, book in schema.load_books(schema.OFFICIAL_DIR):
            for change in norm.normalize_book(book, RULES):
                pending.append(f'{name} {change.field.path}: {change.before[:40]!r}')
        self.assertEqual(pending, [], '請跑 python3 tools/content/normalize_ebook_copy.py --write <檔案>')


if __name__ == '__main__':
    unittest.main()
