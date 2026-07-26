// lib/features/learning/data/repositories/ebook_catalog_repository.dart
//
// 從 bundled JSON 載入四本互動電子書。
//
// 為什麼是 bundled JSON 而不是 const Dart：二十章、四十個以上互動元素若寫在
// Dart 常數裡，文案 review 會被語法干擾、且容易誤改型別。JSON + typed parser
// 讓內容與 UI 解耦，同時用 schema 驗證換回型別安全。這不是 CMS——內容仍隨版本
// 發布。
//
// Parser 一律 fail closed：未知 block type、缺必填欄位、單選題不是恰好一個正解
// 都直接拋 [EbookContentException]，而不是靜默跳過造成「看起來讀完了但少一題」。
library;

import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../../domain/models/ebook.dart';
import '../../domain/models/ebook_block.dart';

/// 內容資產無法安全解析時拋出。訊息是給開發者與測試看的可讀定位資訊，
/// 不含使用者資料。
class EbookContentException implements Exception {
  const EbookContentException(this.message);

  final String message;

  @override
  String toString() => 'EbookContentException: $message';
}

/// 目前支援的 book JSON schema 版本。未知版本 fail closed。
const int kEbookSchemaVersion = 1;

class EbookCatalogRepository {
  EbookCatalogRepository({
    AssetBundle? bundle,
    List<String>? assetPaths,
  })  : _bundle = bundle,
        assetPaths = assetPaths ?? productionAssetPaths;

  /// production 內容資產。順序即書架顯示順序，也是書號 1–4 的順序。
  static const List<String> productionAssetPaths = <String>[
    'assets/learning/ebooks/book_1_bottleneck.json',
    'assets/learning/ebooks/book_2_conversation.json',
    'assets/learning/ebooks/book_3_rescue.json',
    'assets/learning/ebooks/book_4_meeting.json',
  ];

  final AssetBundle? _bundle;
  final List<String> assetPaths;

  AssetBundle get _resolvedBundle => _bundle ?? rootBundle;

  Future<EbookCatalog> load() async {
    final books = <Ebook>[];
    for (final path in assetPaths) {
      final String raw;
      try {
        raw = await _resolvedBundle.loadString(path);
      } catch (error) {
        throw EbookContentException('無法讀取電子書資產 $path：$error');
      }
      books.add(parseBookJson(raw, assetPath: path));
    }
    _validateCatalog(books);
    return EbookCatalog(books: books);
  }
}

/// Catalog 層級不變量。
///
/// 這裡刻意重述「Book 1 免費、其餘訂閱」的產品拍板：內容資產若被改成 Book 2
/// 免費，等於付費牆破洞，寧可在載入時就爆掉並由測試擋下，也不要靜默上線。
///
/// 章數（四本二十章）刻意不在 runtime 強制：那是內容審稿的不變量，由
/// `ebook_content_invariants_test.dart` 守。若寫進 runtime，未來合法地新增
/// 一章就會讓整個學習頁書架掛掉，代價遠大於效益。
void _validateCatalog(List<Ebook> books) {
  if (books.isEmpty) {
    throw const EbookContentException('電子書 catalog 不得為空');
  }

  final bookIds = <String>{};
  final blockIds = <String, String>{};
  final chapterIdsByBook = <String, Set<String>>{};

  for (var index = 0; index < books.length; index++) {
    final book = books[index];
    if (!bookIds.add(book.id)) {
      throw EbookContentException('電子書 id 重複：${book.id}');
    }
    if (book.number != index + 1) {
      throw EbookContentException(
        '電子書 ${book.id} 的 number=${book.number} 與資產順序 ${index + 1} 不一致',
      );
    }
    final expectedAccess = index == 0 ? EbookAccess.free : EbookAccess.premium;
    if (book.access != expectedAccess) {
      throw EbookContentException(
        '電子書 ${book.id} 的 access=${book.access.name} 違反權限拍板'
        '（第一本免費、其餘訂閱）',
      );
    }

    final chapterIds = <String>{};
    for (final chapter in book.chapters) {
      if (!chapterIds.add(chapter.id)) {
        throw EbookContentException(
          '電子書 ${book.id} 章節 id 重複：${chapter.id}',
        );
      }
      // 條目裡的 block 也要納入：互動型 block 的 id 就是本機進度的儲存鍵，
      // 巢狀的一樣會被寫進去，重複就會互相蓋掉。
      for (final block in _flattenBlocks(chapter.blocks)) {
        final owner = blockIds[block.id];
        if (owner != null) {
          throw EbookContentException(
            '區塊 id 全域重複：${block.id}（已出現於 $owner）',
          );
        }
        blockIds[block.id] = '${book.id}/${chapter.id}';
      }
    }
    chapterIdsByBook[book.id] = chapterIds;
  }

  _validateFunnelTargets(books, chapterIdsByBook);
}

/// 攤平章節區塊，含條目庫裡的巢狀區塊。
Iterable<EbookBlock> _flattenBlocks(List<EbookBlock> blocks) sync* {
  for (final block in blocks) {
    yield block;
    if (block is EbookEntryListBlock) {
      for (final entry in block.entries) {
        yield* entry.blocks;
      }
    }
  }
}

/// 漏斗跳章目標必須真的存在。
///
/// 這個檢查是必要的：漏斗是第一章唯一的診斷入口，目標指到不存在的章節時
/// 使用者會按到一個死路（或閱讀器 fallback 到第一章，看起來像沒反應）。
/// 寧可載入時就爆掉並被測試擋下。
void _validateFunnelTargets(
  List<Ebook> books,
  Map<String, Set<String>> chapterIdsByBook,
) {
  for (final book in books) {
    for (final chapter in book.chapters) {
      for (final funnel in chapter.stageFunnels) {
        for (final stage in funnel.stages) {
          final chapters = chapterIdsByBook[stage.targetBookId];
          if (chapters == null) {
            throw EbookContentException(
              '漏斗 ${funnel.id}/${stage.id} 的 targetBookId='
              '${stage.targetBookId} 不存在',
            );
          }
          if (!chapters.contains(stage.targetChapterId)) {
            throw EbookContentException(
              '漏斗 ${funnel.id}/${stage.id} 的 targetChapterId='
              '${stage.targetChapterId} 不屬於 ${stage.targetBookId}',
            );
          }
        }
      }
    }
  }
}

/// 解析單一本書的 JSON。[assetPath] 只用於錯誤訊息定位。
Ebook parseBookJson(String raw, {required String assetPath}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (error) {
    throw EbookContentException('$assetPath 不是合法 JSON：$error');
  }
  if (decoded is! Map<String, Object?>) {
    throw EbookContentException('$assetPath 最外層必須是 JSON object');
  }

  final path = assetPath;
  final schemaVersion = _requireInt(decoded, 'schemaVersion', path);
  if (schemaVersion != kEbookSchemaVersion) {
    throw EbookContentException(
      '$path 的 schemaVersion=$schemaVersion 不受支援'
      '（目前支援 $kEbookSchemaVersion）',
    );
  }

  final chaptersRaw = _requireList(decoded, 'chapters', path);
  if (chaptersRaw.isEmpty) {
    throw EbookContentException('$path.chapters 不得為空');
  }

  final chapters = <EbookChapter>[];
  for (var index = 0; index < chaptersRaw.length; index++) {
    chapters.add(
      _parseChapter(
        _requireObjectAt(chaptersRaw, index, '$path.chapters'),
        '$path.chapters[$index]',
      ),
    );
  }

  return Ebook(
    schemaVersion: schemaVersion,
    id: _requireString(decoded, 'id', path),
    contentVersion: _requireInt(decoded, 'contentVersion', path, min: 1),
    number: _requireInt(decoded, 'number', path, min: 1),
    title: _requireString(decoded, 'title', path),
    subtitle: _requireString(decoded, 'subtitle', path),
    goal: _requireString(decoded, 'goal', path),
    access: _requireEnum(decoded, 'access', path, _accessByName),
    theme: _requireEnum(decoded, 'theme', path, _themeByName),
    estimatedMinutes: _requireInt(decoded, 'estimatedMinutes', path, min: 1),
    sourceRefs: _parseSourceRefs(decoded, path),
    chapters: chapters,
  );
}

EbookChapter _parseChapter(Map<String, Object?> json, String path) {
  final blocksRaw = _requireList(json, 'blocks', path);
  if (blocksRaw.isEmpty) {
    throw EbookContentException('$path.blocks 不得為空');
  }

  final blocks = <EbookBlock>[];
  final seenBlockIds = <String>{};
  for (var index = 0; index < blocksRaw.length; index++) {
    final block = _parseBlock(
      _requireObjectAt(blocksRaw, index, '$path.blocks'),
      '$path.blocks[$index]',
    );
    if (!seenBlockIds.add(block.id)) {
      throw EbookContentException('$path.blocks 內區塊 id 重複：${block.id}');
    }
    blocks.add(block);
  }

  return EbookChapter(
    id: _requireString(json, 'id', path),
    number: _requireString(json, 'number', path),
    title: _requireString(json, 'title', path),
    learningGoal: _requireString(json, 'learningGoal', path),
    estimatedMinutes: _requireInt(json, 'estimatedMinutes', path, min: 1),
    sourceRefs: _parseSourceRefs(json, path),
    blocks: blocks,
  );
}

EbookBlock _parseBlock(
  Map<String, Object?> json,
  String path, {
  bool insideEntry = false,
}) {
  final type = _requireString(json, 'type', path);
  final id = _requireString(json, 'id', path);

  switch (type) {
    case 'entryList':
      if (insideEntry) {
        // 兩層收合在手機上找不回自己在哪，直接擋在 parser。
        throw EbookContentException('$path 條目庫不得巢狀在條目裡');
      }
      return EbookEntryListBlock(
        id: id,
        title: _optionalString(json, 'title', path),
        caption: _optionalString(json, 'caption', path),
        entries: _parseEntries(json, path),
      );

    case 'heading':
      return EbookHeadingBlock(id: id, text: _requireString(json, 'text', path));

    case 'paragraph':
      return EbookParagraphBlock(
        id: id,
        text: _requireString(json, 'text', path),
      );

    case 'bulletList':
      final items = _requireStringList(json, 'items', path);
      return EbookBulletListBlock(
        id: id,
        title: _optionalString(json, 'title', path),
        items: items,
        ordered: _optionalBool(json, 'ordered', path) ?? false,
      );

    case 'callout':
      return EbookCalloutBlock(
        id: id,
        tone: _requireEnum(json, 'tone', path, _calloutToneByName),
        title: _optionalString(json, 'title', path),
        text: _requireString(json, 'text', path),
      );

    case 'comparison':
      return EbookComparisonBlock(
        id: id,
        title: _optionalString(json, 'title', path),
        caption: _optionalString(json, 'caption', path),
        items: _parseComparisonItems(json, path),
      );

    case 'dialogue':
      return EbookDialogueBlock(
        id: id,
        title: _optionalString(json, 'title', path),
        caption: _optionalString(json, 'caption', path),
        lines: _parseDialogueLines(json, path),
      );

    case 'flipCard':
      return EbookFlipCardBlock(
        id: id,
        frontTitle: _requireString(json, 'frontTitle', path),
        frontText: _requireString(json, 'frontText', path),
        backTitle: _requireString(json, 'backTitle', path),
        backText: _requireString(json, 'backText', path),
        backPoints: _optionalStringList(json, 'backPoints', path),
      );

    case 'quiz':
      return _parseQuiz(json, path, id);

    case 'stageFunnel':
      return EbookStageFunnelBlock(
        id: id,
        title: _requireString(json, 'title', path),
        intro: _requireString(json, 'intro', path),
        stages: _parseFunnelStages(json, path),
      );

    case 'checklist':
      return EbookChecklistBlock(
        id: id,
        title: _optionalString(json, 'title', path),
        caption: _optionalString(json, 'caption', path),
        items: _parseChecklistItems(json, path),
      );

    default:
      // Fail closed：新 block type 沒有 renderer 時，寧可整份內容拒絕載入，
      // 也不要靜默跳過一個互動讓使用者以為讀完整章。
      throw EbookContentException('$path.type 未知的區塊型別「$type」');
  }
}

List<EbookComparisonItem> _parseComparisonItems(
  Map<String, Object?> json,
  String path,
) {
  final raw = _requireList(json, 'items', path);
  if (raw.isEmpty) {
    throw EbookContentException('$path.items 不得為空');
  }
  final items = <EbookComparisonItem>[];
  final seen = <String>{};
  for (var index = 0; index < raw.length; index++) {
    final itemPath = '$path.items[$index]';
    final item = _requireObjectAt(raw, index, '$path.items');
    final id = _requireString(item, 'id', itemPath);
    if (!seen.add(id)) {
      throw EbookContentException('$path.items 內 id 重複：$id');
    }
    items.add(
      EbookComparisonItem(
        id: id,
        stance: _requireEnum(item, 'stance', itemPath, _stanceByName),
        label: _requireString(item, 'label', itemPath),
        text: _requireString(item, 'text', itemPath),
        note: _optionalString(item, 'note', itemPath),
      ),
    );
  }
  return items;
}

List<EbookDialogueLine> _parseDialogueLines(
  Map<String, Object?> json,
  String path,
) {
  final raw = _requireList(json, 'lines', path);
  if (raw.isEmpty) {
    throw EbookContentException('$path.lines 不得為空');
  }
  final lines = <EbookDialogueLine>[];
  final seen = <String>{};
  for (var index = 0; index < raw.length; index++) {
    final linePath = '$path.lines[$index]';
    final line = _requireObjectAt(raw, index, '$path.lines');
    final id = _requireString(line, 'id', linePath);
    if (!seen.add(id)) {
      throw EbookContentException('$path.lines 內 id 重複：$id');
    }
    lines.add(
      EbookDialogueLine(
        id: id,
        speaker: _requireEnum(line, 'speaker', linePath, _speakerByName),
        text: _requireString(line, 'text', linePath),
        timeLabel: _optionalString(line, 'timeLabel', linePath),
        annotation: _optionalString(line, 'annotation', linePath),
        signal: _optionalEnum(line, 'signal', linePath, _signalByName),
        isDeathPoint: _optionalBool(line, 'isDeathPoint', linePath) ?? false,
      ),
    );
  }
  return lines;
}

EbookQuizBlock _parseQuiz(Map<String, Object?> json, String path, String id) {
  final mode = _requireEnum(json, 'mode', path, _quizModeByName);
  final choicesRaw = _requireList(json, 'choices', path);
  if (choicesRaw.length < 2) {
    throw EbookContentException('$path.choices 至少要兩個選項');
  }

  final choices = <EbookQuizChoice>[];
  final seen = <String>{};
  for (var index = 0; index < choicesRaw.length; index++) {
    final choicePath = '$path.choices[$index]';
    final choice = _requireObjectAt(choicesRaw, index, '$path.choices');
    final choiceId = _requireString(choice, 'id', choicePath);
    if (!seen.add(choiceId)) {
      throw EbookContentException('$path.choices 內 id 重複：$choiceId');
    }
    choices.add(
      EbookQuizChoice(
        id: choiceId,
        text: _requireString(choice, 'text', choicePath),
        isCorrect: _requireBool(choice, 'isCorrect', choicePath),
        feedback: _requireString(choice, 'feedback', choicePath),
      ),
    );
  }

  final correctCount = choices.where((choice) => choice.isCorrect).length;
  switch (mode) {
    case EbookQuizMode.single:
      if (correctCount != 1) {
        throw EbookContentException(
          '$path 是單選題但有 $correctCount 個正解（必須恰好一個）',
        );
      }
    case EbookQuizMode.multiple:
      // 複選題需要至少一個正解與至少一個錯誤選項，否則不構成辨識任務。
      if (correctCount < 1) {
        throw EbookContentException('$path 是複選題但沒有正解');
      }
      if (correctCount == choices.length) {
        throw EbookContentException('$path 是複選題但全部選項都是正解');
      }
  }

  return EbookQuizBlock(
    id: id,
    question: _requireString(json, 'question', path),
    scenario: _optionalString(json, 'scenario', path),
    mode: mode,
    retryPolicy: _optionalEnum(
          json,
          'retryPolicy',
          path,
          _retryPolicyByName,
        ) ??
        EbookQuizRetryPolicy.untilCorrect,
    revision: _requireInt(json, 'revision', path, min: 1),
    choices: choices,
    takeaway: _requireString(json, 'takeaway', path),
  );
}

List<EbookEntry> _parseEntries(Map<String, Object?> json, String path) {
  final raw = _requireList(json, 'entries', path);
  if (raw.length < 2) {
    throw EbookContentException('$path.entries 至少要兩條（一條不需要做成列表）');
  }
  final entries = <EbookEntry>[];
  final seen = <String>{};
  for (var index = 0; index < raw.length; index++) {
    final entryPath = '$path.entries[$index]';
    final entry = _requireObjectAt(raw, index, '$path.entries');
    final id = _requireString(entry, 'id', entryPath);
    if (!seen.add(id)) {
      throw EbookContentException('$path.entries 內 id 重複：$id');
    }
    final blocksRaw = _requireList(entry, 'blocks', entryPath);
    if (blocksRaw.isEmpty) {
      throw EbookContentException('$entryPath.blocks 不得為空');
    }
    final blocks = <EbookBlock>[];
    final seenBlockIds = <String>{};
    for (var b = 0; b < blocksRaw.length; b++) {
      final block = _parseBlock(
        _requireObjectAt(blocksRaw, b, '$entryPath.blocks'),
        '$entryPath.blocks[$b]',
        insideEntry: true,
      );
      if (!seenBlockIds.add(block.id)) {
        throw EbookContentException('$entryPath.blocks 內區塊 id 重複：${block.id}');
      }
      blocks.add(block);
    }
    entries.add(
      EbookEntry(
        id: id,
        title: _requireString(entry, 'title', entryPath),
        summary: _optionalString(entry, 'summary', entryPath),
        blocks: blocks,
      ),
    );
  }
  return entries;
}

List<EbookFunnelStage> _parseFunnelStages(
  Map<String, Object?> json,
  String path,
) {
  final raw = _requireList(json, 'stages', path);
  if (raw.length < 2) {
    throw EbookContentException('$path.stages 至少要兩層（否則不構成選擇）');
  }
  final stages = <EbookFunnelStage>[];
  final seen = <String>{};
  for (var index = 0; index < raw.length; index++) {
    final stagePath = '$path.stages[$index]';
    final stage = _requireObjectAt(raw, index, '$path.stages');
    final id = _requireString(stage, 'id', stagePath);
    if (!seen.add(id)) {
      throw EbookContentException('$path.stages 內 id 重複：$id');
    }
    stages.add(
      EbookFunnelStage(
        id: id,
        number: _requireString(stage, 'number', stagePath),
        stageName: _requireString(stage, 'stageName', stagePath),
        symptom: _requireString(stage, 'symptom', stagePath),
        verdictTitle: _requireString(stage, 'verdictTitle', stagePath),
        verdictText: _requireString(stage, 'verdictText', stagePath),
        targetBookId: _requireString(stage, 'targetBookId', stagePath),
        targetChapterId: _requireString(stage, 'targetChapterId', stagePath),
        targetLabel: _requireString(stage, 'targetLabel', stagePath),
      ),
    );
  }
  return stages;
}

List<EbookChecklistItem> _parseChecklistItems(
  Map<String, Object?> json,
  String path,
) {
  final raw = _requireList(json, 'items', path);
  if (raw.isEmpty) {
    throw EbookContentException('$path.items 不得為空');
  }
  final items = <EbookChecklistItem>[];
  final seen = <String>{};
  for (var index = 0; index < raw.length; index++) {
    final itemPath = '$path.items[$index]';
    final item = _requireObjectAt(raw, index, '$path.items');
    final id = _requireString(item, 'id', itemPath);
    if (!seen.add(id)) {
      throw EbookContentException('$path.items 內 id 重複：$id');
    }
    items.add(
      EbookChecklistItem(
        id: id,
        text: _requireString(item, 'text', itemPath),
        note: _optionalString(item, 'note', itemPath),
      ),
    );
  }
  return items;
}

List<EbookSourceRef> _parseSourceRefs(Map<String, Object?> json, String path) {
  final raw = _requireList(json, 'sourceRefs', path);
  if (raw.isEmpty) {
    throw EbookContentException('$path.sourceRefs 不得為空');
  }
  final refs = <EbookSourceRef>[];
  for (var index = 0; index < raw.length; index++) {
    final refPath = '$path.sourceRefs[$index]';
    final ref = _requireObjectAt(raw, index, '$path.sourceRefs');
    refs.add(
      EbookSourceRef(
        document: _requireString(ref, 'document', refPath),
        sections: _requireStringList(ref, 'sections', refPath),
      ),
    );
  }
  return refs;
}

// ---------------------------------------------------------------------------
// JSON 讀取小工具。全部帶 path，讓錯誤訊息能直接定位到出錯的欄位。
// ---------------------------------------------------------------------------

const Map<String, EbookAccess> _accessByName = <String, EbookAccess>{
  'free': EbookAccess.free,
  'premium': EbookAccess.premium,
};

const Map<String, EbookTheme> _themeByName = <String, EbookTheme>{
  'compass': EbookTheme.compass,
  'lens': EbookTheme.lens,
  'firstAid': EbookTheme.firstAid,
  'bridge': EbookTheme.bridge,
};

const Map<String, EbookCalloutTone> _calloutToneByName =
    <String, EbookCalloutTone>{
  'info': EbookCalloutTone.info,
  'principle': EbookCalloutTone.principle,
  'goal': EbookCalloutTone.goal,
  'safety': EbookCalloutTone.safety,
  'warning': EbookCalloutTone.warning,
  'takeaway': EbookCalloutTone.takeaway,
  'fix': EbookCalloutTone.fix,
};

const Map<String, EbookComparisonStance> _stanceByName =
    <String, EbookComparisonStance>{
  'weak': EbookComparisonStance.weak,
  'strong': EbookComparisonStance.strong,
  'neutral': EbookComparisonStance.neutral,
};

const Map<String, EbookSpeaker> _speakerByName = <String, EbookSpeaker>{
  'you': EbookSpeaker.you,
  'other': EbookSpeaker.other,
  'coach': EbookSpeaker.coach,
};

const Map<String, EbookSignal> _signalByName = <String, EbookSignal>{
  'green': EbookSignal.green,
  'yellow': EbookSignal.yellow,
  'red': EbookSignal.red,
};

const Map<String, EbookQuizMode> _quizModeByName = <String, EbookQuizMode>{
  'single': EbookQuizMode.single,
  'multiple': EbookQuizMode.multiple,
};

const Map<String, EbookQuizRetryPolicy> _retryPolicyByName =
    <String, EbookQuizRetryPolicy>{
  'untilCorrect': EbookQuizRetryPolicy.untilCorrect,
  'lockedAfterSubmit': EbookQuizRetryPolicy.lockedAfterSubmit,
};

Map<String, Object?> _requireObjectAt(List<Object?> list, int index, String path) {
  final value = list[index];
  if (value is! Map<String, Object?>) {
    throw EbookContentException('$path[$index] 必須是 JSON object');
  }
  return value;
}

String _requireString(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw EbookContentException('$path.$key 必須是非空字串');
  }
  return value;
}

String? _optionalString(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) {
    throw EbookContentException('$path.$key 必須是字串');
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : value;
}

int _requireInt(
  Map<String, Object?> json,
  String key,
  String path, {
  int? min,
}) {
  final value = json[key];
  if (value is! int) {
    throw EbookContentException('$path.$key 必須是整數');
  }
  if (min != null && value < min) {
    throw EbookContentException('$path.$key 必須 >= $min（實際 $value）');
  }
  return value;
}

bool _requireBool(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! bool) {
    throw EbookContentException('$path.$key 必須是布林值');
  }
  return value;
}

bool? _optionalBool(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value == null) return null;
  if (value is! bool) {
    throw EbookContentException('$path.$key 必須是布林值');
  }
  return value;
}

List<Object?> _requireList(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! List) {
    throw EbookContentException('$path.$key 必須是陣列');
  }
  return value;
}

List<String> _requireStringList(
  Map<String, Object?> json,
  String key,
  String path,
) {
  final raw = _requireList(json, key, path);
  if (raw.isEmpty) {
    throw EbookContentException('$path.$key 不得為空');
  }
  return _asStringList(raw, '$path.$key');
}

List<String> _optionalStringList(
  Map<String, Object?> json,
  String key,
  String path,
) {
  final value = json[key];
  if (value == null) return const <String>[];
  if (value is! List) {
    throw EbookContentException('$path.$key 必須是陣列');
  }
  return _asStringList(value, '$path.$key');
}

List<String> _asStringList(List<Object?> raw, String path) {
  final items = <String>[];
  for (var index = 0; index < raw.length; index++) {
    final item = raw[index];
    if (item is! String || item.trim().isEmpty) {
      throw EbookContentException('$path[$index] 必須是非空字串');
    }
    items.add(item);
  }
  return List<String>.unmodifiable(items);
}

T _requireEnum<T>(
  Map<String, Object?> json,
  String key,
  String path,
  Map<String, T> byName,
) {
  final raw = _requireString(json, key, path);
  final value = byName[raw];
  if (value == null) {
    throw EbookContentException(
      '$path.$key 的值「$raw」不受支援（可用：${byName.keys.join(' / ')}）',
    );
  }
  return value;
}

T? _optionalEnum<T>(
  Map<String, Object?> json,
  String key,
  String path,
  Map<String, T> byName,
) {
  if (json[key] == null) return null;
  return _requireEnum(json, key, path, byName);
}
