"""tools/content 內容工具的單元測試（標準函式庫 unittest，不裝套件）。

    python3 -m unittest discover -s tools/content/tests -v
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

import audit_ebook_copy as audit  # noqa: E402
import compare_ebook_import as compare  # noqa: E402
import ebook_schema as schema  # noqa: E402
import build_ebooks_from_guide as builder  # noqa: E402

RULES = audit.load_json(os.path.join(TOOLS_DIR, 'audit_rules.json'))


def make_book(book_id='ebook-9-fixture', number=9, unit='ultimateGuide', access='premium', blocks=None):
    """最小合法書：一章、可自訂區塊。"""
    return {
        'schemaVersion': 1,
        'id': book_id,
        'contentVersion': 1,
        'number': number,
        'unit': unit,
        'title': '測試 · 書',
        'subtitle': '副標',
        'goal': '目標',
        'access': access,
        'theme': 'compass',
        'estimatedMinutes': 3,
        'sourceRefs': [{'document': 'fixture', 'sections': ['x']}],
        'chapters': [{
            'id': f'{book_id}-chapter-1',
            'number': f'{number}.1',
            'title': '章名',
            'learningGoal': '學習目標',
            'estimatedMinutes': 3,
            'sourceRefs': [{'document': 'fixture', 'sections': ['x']}],
            'blocks': blocks if blocks is not None else [
                {'type': 'paragraph', 'id': f'{book_id}-p1', 'text': '這是一段正常的中文。'},
            ],
        }],
    }


def all_block_types_book():
    bid = 'ebook-9-fixture'
    blocks = [
        {'type': 'heading', 'id': f'{bid}-h', 'text': '標題'},
        {'type': 'paragraph', 'id': f'{bid}-p', 'text': '段落'},
        {'type': 'bulletList', 'id': f'{bid}-b', 'title': '清單', 'items': ['一', '二']},
        {'type': 'callout', 'id': f'{bid}-c', 'tone': 'info', 'title': '補充', 'text': '內文'},
        {'type': 'comparison', 'id': f'{bid}-cmp', 'caption': '說明', 'items': [
            {'id': f'{bid}-cmp-w', 'stance': 'weak', 'label': '弱', 'text': '弱句', 'note': '註'},
            {'id': f'{bid}-cmp-s', 'stance': 'strong', 'label': '強', 'text': '強句'},
        ]},
        {'type': 'dialogue', 'id': f'{bid}-d', 'lines': [
            {'id': f'{bid}-d-l1', 'speaker': 'you', 'text': '嗨', 'timeLabel': '10:00', 'annotation': '註解'},
        ]},
        {'type': 'flipCard', 'id': f'{bid}-f', 'frontTitle': '正', 'frontText': '正文', 'backTitle': '背',
         'backText': '背文', 'backPoints': ['點']},
        {'type': 'quiz', 'id': f'{bid}-q', 'question': '問', 'scenario': '情境', 'mode': 'single', 'revision': 1,
         'takeaway': '帶走', 'choices': [
             {'id': f'{bid}-q-a', 'text': 'A', 'isCorrect': True, 'feedback': '對'},
             {'id': f'{bid}-q-b', 'text': 'B', 'isCorrect': False, 'feedback': '錯'},
         ]},
        {'type': 'stageFunnel', 'id': f'{bid}-sf', 'title': '漏斗', 'intro': '引言', 'stages': [
            {'id': f'{bid}-sf-0', 'number': '0', 'stageName': '階段', 'symptom': '症狀', 'verdictTitle': '判',
             'verdictText': '判文', 'targetBookId': bid, 'targetChapterId': f'{bid}-chapter-1', 'targetLabel': '前往'},
            {'id': f'{bid}-sf-1', 'number': '1', 'stageName': '階段', 'symptom': '症狀', 'verdictTitle': '判',
             'verdictText': '判文', 'targetBookId': bid, 'targetChapterId': f'{bid}-chapter-1', 'targetLabel': '前往'},
        ]},
        {'type': 'entryList', 'id': f'{bid}-el', 'title': '條目庫', 'caption': '說明', 'entries': [
            {'id': f'{bid}-el-e1', 'title': '條目一', 'summary': '摘要', 'blocks': [
                {'type': 'paragraph', 'id': f'{bid}-el-e1-p', 'text': '條目內文'},
            ]},
            {'id': f'{bid}-el-e2', 'title': '條目二', 'blocks': [
                {'type': 'crossRef', 'id': f'{bid}-el-e2-x', 'label': '前往', 'contextLabel': '本書 · 第 1 章',
                 'targetBookId': bid, 'targetChapterId': f'{bid}-chapter-1', 'targetEntryId': f'{bid}-el-e1'},
            ]},
        ]},
        {'type': 'checklist', 'id': f'{bid}-ck', 'title': '自評', 'items': [
            {'id': f'{bid}-ck-1', 'text': '項目', 'note': '註'},
        ]},
    ]
    return make_book(blocks=blocks)


def write_books(dir_path, books):
    for name, book in books:
        with open(os.path.join(dir_path, name), 'w', encoding='utf-8') as fh:
            json.dump(book, fh, ensure_ascii=False, indent=2)


def audit_findings(book, rules=None):
    result = audit.run_audit([('fixture.json', book)], rules or RULES, {})
    return result['findings']


def rules_of(findings):
    return sorted({item.rule for item in findings})


class SchemaTests(unittest.TestCase):
    def test_visible_fields_cover_every_block_type(self):
        fields = list(schema.iter_fields(all_block_types_book()))
        names = {(f.block_type, f.name) for f in fields if f.block_type}
        expected = {
            ('heading', 'text'), ('paragraph', 'text'), ('bulletList', 'title'), ('bulletList', 'items[1]'),
            ('callout', 'title'), ('callout', 'text'), ('comparison', 'caption'), ('comparison', 'items[0].note'),
            ('dialogue', 'lines[0].annotation'), ('dialogue', 'lines[0].timeLabel'), ('flipCard', 'backPoints[0]'),
            ('quiz', 'scenario'), ('quiz', 'choices[1].feedback'), ('stageFunnel', 'stages[1].targetLabel'),
            ('entryList', 'entries[0].summary'), ('entryList', 'caption'), ('crossRef', 'contextLabel'),
            ('checklist', 'items[0].note'),
        }
        self.assertTrue(expected <= names, expected - names)
        kinds = {f.kind for f in fields}
        self.assertEqual(kinds, {'book', 'chapter', 'block', 'item', 'comparisonItem', 'line', 'choice', 'stage',
                                 'entry', 'checklistItem'})
        # metadata 永遠不會被當成文字
        texts = {f.text for f in fields}
        self.assertNotIn('you', texts)
        self.assertNotIn('info', texts)
        self.assertNotIn('ebook-9-fixture-chapter-1', texts)

    def test_unknown_block_type_fails_closed(self):
        book = make_book(blocks=[{'type': 'table', 'id': 'x', 'rows': []}])
        with self.assertRaises(schema.SchemaError):
            list(schema.iter_fields(book))

    def test_missing_required_text_fails_closed(self):
        book = make_book(blocks=[{'type': 'paragraph', 'id': 'x'}])
        with self.assertRaises(schema.SchemaError):
            list(schema.iter_fields(book))

    def test_set_text_writes_back_in_place(self):
        book = make_book()
        field = [f for f in schema.iter_fields(book) if f.kind == 'block'][0]
        field.set_text('改寫後')
        self.assertEqual(book['chapters'][0]['blocks'][0]['text'], '改寫後')
        book = make_book(blocks=[{'type': 'bulletList', 'id': 'b', 'items': ['甲', '乙']}])
        field = [f for f in schema.iter_fields(book) if f.name == 'items[1]'][0]
        field.set_text('丙')
        self.assertEqual(book['chapters'][0]['blocks'][0]['items'], ['甲', '丙'])


class AuditRuleTests(unittest.TestCase):
    def test_clean_fixture_only_reports_catalog_level_rules(self):
        findings = audit_findings(all_block_types_book())
        # 定稿句（R13）與 glossary（R10）是整套教材層級的要求，單一 fixture 本來就不會有。
        self.assertTrue(set(rules_of(findings)) <= {'R13', 'R10'}, findings)

    def test_r01_half_width_punctuation_with_digit_exceptions(self):
        book = make_book(blocks=[
            {'type': 'paragraph', 'id': 'p1', 'text': '如果你兩週只配對到 3 個人,天花板也是 3。'},
            {'type': 'paragraph', 'id': 'p2', 'text': '晚上 10:00 見，比例 2:1，總共 1,000 元。'},
            {'type': 'paragraph', 'id': 'p3', 'text': 'pure ascii, no cjk (skip)'},
        ])
        findings = [f for f in audit_findings(book) if f.rule == 'R01']
        self.assertEqual([f.id for f in findings], ['p1'])
        self.assertIn(',×1', findings[0].message)

    def test_r02_ascii_symbols(self):
        book = make_book(blocks=[{'type': 'paragraph', 'id': 'p1', 'text': '改天約? / 有空出來...行為 > 字面 V=0'}])
        finding = [f for f in audit_findings(book) if f.rule == 'R02'][0]
        self.assertIn('...', finding.message)
        self.assertIn('/', finding.message)
        self.assertIn('>', finding.message)
        self.assertNotIn('=', finding.message)  # V=0 是英數之間，允許

    def test_r03_r04_r05_whitespace_paragraphs_pipes(self):
        book = make_book(blocks=[
            {'type': 'paragraph', 'id': 'p1', 'text': '第一段\n\n第二段'},
            {'type': 'callout', 'id': 'c1', 'tone': 'warning', 'text': '硬規則：\n\n 種子拿到綠燈\n 累計兩個'},
            {'type': 'bulletList', 'id': 'b1', 'items': ['A. 配對數｜兩週內配對到幾個']},
        ])
        findings = audit_findings(book)
        self.assertEqual([f.id for f in findings if f.rule == 'R04'], ['p1'])
        self.assertEqual([f.id for f in findings if f.rule == 'R03'], ['c1'])
        self.assertEqual([f.id for f in findings if f.rule == 'R05'], ['b1'])

    def test_r06_length_limits_by_field_type(self):
        long_text = '很' * 121
        book = make_book(blocks=[
            {'type': 'paragraph', 'id': 'p1', 'text': long_text},
            {'type': 'paragraph', 'id': 'p2', 'text': '短' * 120 + '\n' + ' ' * 10},  # 空白不算長度
            {'type': 'callout', 'id': 'c1', 'tone': 'info', 'text': '長' * 121},  # callout 上限 160
            {'type': 'entryList', 'id': 'el', 'entries': [
                {'id': 'e1', 'title': '一', 'summary': '摘' * 41, 'blocks': [{'type': 'paragraph', 'id': 'e1p', 'text': '內'}]},
                {'id': 'e2', 'title': '二', 'blocks': [{'type': 'paragraph', 'id': 'e2p', 'text': '內'}]},
            ]},
        ])
        book['chapters'][0]['title'] = '章' * 23
        findings = [f for f in audit_findings(book) if f.rule == 'R06']
        self.assertEqual(sorted(f.id for f in findings), ['e1', 'ebook-9-fixture-chapter-1', 'p1'])

    def test_r07_summary_equals_first_paragraph(self):
        book = make_book(blocks=[{'type': 'entryList', 'id': 'el', 'entries': [
            {'id': 'e1', 'title': '一', 'summary': '她的 bio', 'blocks': [{'type': 'paragraph', 'id': 'e1p', 'text': '她的 bio'}]},
            {'id': 'e2', 'title': '二', 'summary': '不同', 'blocks': [{'type': 'paragraph', 'id': 'e2p', 'text': '內文'}]},
        ]}])
        findings = [f for f in audit_findings(book) if f.rule == 'R07']
        self.assertEqual([f.id for f in findings], ['e1'])

    def test_r08_simplified_and_term_pairs(self):
        book = make_book(blocks=[{'type': 'paragraph', 'id': 'p1', 'text': '關係升温了，留一個勾子，這是好的信號，加個 Line。'}])
        finding = [f for f in audit_findings(book) if f.rule == 'R08'][0]
        for expected in ('温', '「勾子」應為「鉤子」', '「信號」應為「訊號」', '「Line」應為「LINE」'):
            self.assertIn(expected, finding.message)

    def test_r09_codes_only_flagged_in_configured_book(self):
        blocks = [{'type': 'paragraph', 'id': 'p1', 'text': 'V↑（有辨識力）E↑（具體畫面）。只有 I，沒有 V/E/R。'}]
        flagged = audit_findings(make_book(book_id='ebook-1-bottleneck', number=1, blocks=blocks))
        self.assertEqual([f.id for f in flagged if f.rule == 'R09'], ['p1'])
        other = audit_findings(make_book(book_id='ebook-2-conversation', number=2, blocks=blocks))
        self.assertEqual([f for f in other if f.rule == 'R09'], [])

    def test_r11_r12_textbook_refs_and_banned_phrases(self):
        book = make_book(blocks=[
            {'type': 'paragraph', 'id': 'p1', 'text': '不要。見案例 D 和課本 6.1。類型 A 的解法見第六節。'},
            {'type': 'paragraph', 'id': 'p2', 'text': '判讀順位：行為＞情緒＞字面。然後是拒絕階梯。'},
        ])
        findings = audit_findings(book)
        r11 = [f for f in findings if f.rule == 'R11'][0]
        for expected in ('見案例 D', '課本 6.1', '類型 A', '見第六節'):
            self.assertIn(expected, r11.message)
        r12 = sorted(f.field for f in findings if f.rule == 'R12')
        self.assertEqual(r12, ['text#拒絕階梯', 'text#行為＞情緒＞字面'])

    def test_r10_r13_catalog_level_requirements(self):
        book = make_book(book_id='ebook-2-conversation', number=2, blocks=[
            {'type': 'paragraph', 'id': 'p1', 'text': '讓她認識你（V）、誰在帶方向（F）'},
        ])
        book['chapters'][0]['id'] = 'ebook-2-chapter-1'
        findings = audit_findings(book)
        missing = sorted(f.field for f in findings if f.rule == 'R10')
        self.assertEqual(len(missing), 3)
        self.assertIn('glossary#興趣回應（R）', missing)
        self.assertEqual(len([f for f in findings if f.rule == 'R13']), len(RULES['canonicalRequired']))

    def test_r14_structure_contracts(self):
        bid = 'ebook-9-fixture'
        book = make_book(blocks=[
            {'type': 'paragraph', 'id': 'dup', 'text': '一'},
            {'type': 'paragraph', 'id': 'dup', 'text': '二'},
            {'type': 'crossRef', 'id': 'x1', 'label': '前往', 'contextLabel': '本書', 'targetBookId': bid,
             'targetChapterId': 'no-such-chapter'},
            {'type': 'entryList', 'id': 'el', 'entries': [
                {'id': 'e1', 'title': '一', 'blocks': [{'type': 'paragraph', 'id': 'e1p', 'text': '內'}]},
            ]},
        ])
        findings = [f for f in audit_findings(book) if f.rule == 'R14']
        messages = ' '.join(f.message for f in findings)
        self.assertIn('id 重複', messages)
        self.assertIn('交叉指涉目標章不存在', messages)
        self.assertIn('條目庫少於兩條', messages)

    def test_allowlist_suppresses_only_named_entries(self):
        book = make_book(blocks=[{'type': 'paragraph', 'id': 'p1', 'text': '一段,半形逗號'}])
        allowlist = {'entries': [{'rule': 'R01', 'id': 'p1', 'reason': '測試'}]}
        result = audit.run_audit([('f.json', book)], RULES, allowlist)
        self.assertEqual([f for f in result['findings'] if f.rule == 'R01'], [])
        self.assertEqual(len(result['suppressed']), 1)
        with self.assertRaises(ValueError):
            audit.apply_allowlist([], {'entries': [{'rule': 'R01', 'id': 'p1'}]})  # 沒有 reason

    def test_baseline_ratchet_blocks_only_new_findings(self):
        book = make_book(blocks=[{'type': 'paragraph', 'id': 'p1', 'text': '一段,半形逗號'}])
        result = audit.run_audit([('f.json', book)], RULES, {})
        baseline = audit.make_baseline(result['findings'], 'fixture')
        new, resolved = audit.compare_with_baseline(result['findings'], baseline)
        self.assertEqual((new, resolved), ([], []))
        worse = copy.deepcopy(book)
        worse['chapters'][0]['blocks'].append({'type': 'paragraph', 'id': 'p2', 'text': '再一段,半形'})
        result2 = audit.run_audit([('f.json', worse)], RULES, {})
        new, _ = audit.compare_with_baseline(result2['findings'], baseline)
        self.assertEqual([f.id for f in new], ['p2'])
        fixed = copy.deepcopy(book)
        fixed['chapters'][0]['blocks'][0]['text'] = '一段，全形逗號'
        result3 = audit.run_audit([('f.json', fixed)], RULES, {})
        new, resolved = audit.compare_with_baseline(result3['findings'], baseline)
        self.assertEqual(new, [])
        self.assertEqual(resolved, [('R01', 'p1', 'text')])

    def test_cli_exit_codes(self):
        book = make_book(blocks=[{'type': 'paragraph', 'id': 'p1', 'text': '一段,半形逗號'}])
        with tempfile.TemporaryDirectory() as tmp:
            src = os.path.join(tmp, 'src')
            os.makedirs(src)
            write_books(src, [('book_9_fixture.json', book)])
            baseline_path = os.path.join(tmp, 'baseline.json')
            with redirect_stdout(io.StringIO()):
                self.assertEqual(audit.main([src, '--check']), 1)
                self.assertEqual(audit.main([src, '--write-baseline', baseline_path, '--quiet']), 0)
                self.assertEqual(audit.main([src, '--baseline', baseline_path, '--quiet']), 0)
                self.assertEqual(audit.main([os.path.join(tmp, 'missing'), '--quiet']), 2)


class CompareTests(unittest.TestCase):
    def test_official_vs_itself_has_no_diff(self):
        official = [('book_9_fixture.json', all_block_types_book())]
        result = compare.compare_indexes(compare.index_books(official), compare.index_books(copy.deepcopy(official)))
        self.assertFalse(result['hasDiff'])

    def test_added_removed_changed_by_stable_id(self):
        official = all_block_types_book()
        candidate = copy.deepcopy(official)
        blocks = candidate['chapters'][0]['blocks']
        blocks[1]['text'] = '段落改了'
        blocks[2]['type'] = 'checklist'
        blocks[2]['items'] = [{'id': 'ck-new', 'text': '一'}]
        del blocks[2]['title']
        blocks.append({'type': 'paragraph', 'id': 'ebook-9-fixture-new', 'text': '新段'})
        entry_list = [b for b in blocks if b['type'] == 'entryList'][0]
        entry_list['entries'][0]['summary'] = '摘要改了'
        del entry_list['entries'][1]
        candidate['chapters'][0]['learningGoal'] = '目標改了'
        result = compare.compare_indexes(
            compare.index_books([('book_9_fixture.json', official)]),
            compare.index_books([('book_9_fixture.json', candidate)]))
        book = result['books']['ebook-9-fixture']
        self.assertTrue(result['hasDiff'])
        self.assertEqual(book['blocks']['added'], ['ebook-9-fixture-new'])
        self.assertIn('ebook-9-fixture-el-e2-x', book['blocks']['removed'])
        changed = {item['id']: item['fields'] for item in book['blocks']['changed']}
        self.assertEqual(changed['ebook-9-fixture-p'], ['text'])
        self.assertIn('type:bulletList→checklist', changed['ebook-9-fixture-b'])
        self.assertEqual(book['entries']['removed'], ['ebook-9-fixture-el-e2'])
        self.assertEqual(book['entries']['changed'], [{'id': 'ebook-9-fixture-el-e1', 'fields': ['summary']}])
        self.assertEqual(book['chapters']['changed'], [{'id': 'ebook-9-fixture-chapter-1', 'fields': ['learningGoal']}])
        summary = compare.format_summary(result)
        self.assertIn('有差異', summary)

    def test_cli_reports_missing_candidate_dir(self):
        with tempfile.TemporaryDirectory() as tmp, redirect_stdout(io.StringIO()):
            self.assertEqual(compare.main(['--candidate', os.path.join(tmp, 'nope')]), 2)


class BuilderGuardTests(unittest.TestCase):
    def test_default_output_is_candidate_dir_not_assets(self):
        self.assertTrue(builder.DEFAULT_OUT.endswith(os.path.join('build', 'ebook_import_candidate')))
        self.assertFalse(builder.DEFAULT_OUT.startswith(builder.OFFICIAL_DIR))

    def test_refuses_official_dir_and_subdirs(self):
        for target in (builder.OFFICIAL_DIR, os.path.join(builder.OFFICIAL_DIR, 'sub'),
                       builder.OFFICIAL_DIR + os.sep + '..' + os.sep + 'ebooks'):
            with self.assertRaises(SystemExit):
                builder.assert_not_official_dir(target)
        with tempfile.TemporaryDirectory() as tmp:
            builder.assert_not_official_dir(tmp)  # 其他目錄可以

    def test_cli_refuses_env_override_into_assets(self):
        argv = ['--out', builder.OFFICIAL_DIR, '--nodes', os.path.join(TOOLS_DIR, 'funnel_block.json')]
        with self.assertRaises(SystemExit):
            builder.main(argv)


@unittest.skipUnless(os.path.isdir(schema.OFFICIAL_DIR), '正式內容資產不在')
class ProductionSmokeTests(unittest.TestCase):
    def test_official_assets_parse_and_audit_without_crashing(self):
        books = schema.load_books(schema.OFFICIAL_DIR)
        self.assertEqual([name for name, _ in books], schema.BOOK_FILES)
        result = audit.run_audit(books, RULES, {})
        self.assertEqual(result['stats']['total']['books'], 7)
        self.assertEqual(result['stats']['total']['chapters'], 39)
        self.assertEqual([f for f in result['findings'] if f.rule == 'R14'], [])

    def test_official_assets_compare_to_themselves(self):
        result = compare.compare_dirs(schema.OFFICIAL_DIR, schema.OFFICIAL_DIR)
        self.assertFalse(result['hasDiff'])

    def test_committed_baseline_still_covers_official_assets(self):
        baseline_path = os.path.join(TOOLS_DIR, 'audit_baseline.json')
        if not os.path.exists(baseline_path):
            self.skipTest('尚未產生 baseline')
        books = schema.load_books(schema.OFFICIAL_DIR)
        allowlist = audit.load_json(os.path.join(TOOLS_DIR, 'audit_allowlist.json'))
        result = audit.run_audit(books, RULES, allowlist)
        new, _resolved = audit.compare_with_baseline(result['findings'], audit.load_json(baseline_path))
        self.assertEqual(new, [], '正式內容出現 baseline 以外的新問題，請先修或更新 baseline')


if __name__ == '__main__':
    unittest.main()
