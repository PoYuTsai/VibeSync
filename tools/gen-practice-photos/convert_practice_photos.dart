// 把陪練女孩來源 PNG 轉成 app-ready 的 resized JPEG，放進 bundled assets。
//
// 用法（來源路徑只經 CLI arg，絕不寫進 committed code）：
//   dart run tools/gen-practice-photos/convert_practice_photos.dart \
//     --src "<來源 upload_ready 目錄>" \
//     --out assets/images/practice_girls \
//     [--count 100] [--max 1080] [--quality 82]
//
// 為何 JPEG 而非 WebP：本機無 cwebp/Pillow，且 Dart `image` 套件 WebP 僅 decode。
// JPEG 由既有 `image` 依賴直接編碼；檔名 practice_girl_NNN.jpg 與 photoId 一致，
// 日後若要改用 WebP（Windows cwebp 重壓）只需替換同名檔，client 路徑不變。
import 'dart:io';

import 'package:image/image.dart' as img;

const int _defaultCount = 100;

String _arg(List<String> a, String key, String fallback) {
  final i = a.indexOf(key);
  if (i >= 0 && i + 1 < a.length) return a[i + 1];
  return fallback;
}

void main(List<String> args) {
  final srcDir = _arg(args, '--src', '');
  final outDir = _arg(args, '--out', 'assets/images/practice_girls');
  final count = int.parse(_arg(args, '--count', _defaultCount.toString()));
  final maxDim = int.parse(_arg(args, '--max', '1080'));
  final quality = int.parse(_arg(args, '--quality', '82'));

  if (srcDir.isEmpty) {
    stderr.writeln('ERROR: --src <來源目錄> 必填');
    exitCode = 2;
    return;
  }
  if (count <= 0) {
    stderr.writeln('ERROR: --count 必須大於 0');
    exitCode = 2;
    return;
  }

  Directory(outDir).createSync(recursive: true);

  final missing = <String>[];
  final sizes = <String, int>{};
  var totalBytes = 0;
  var biggest = 0;
  String biggestName = '';

  for (var n = 1; n <= count; n++) {
    final id = 'practice_girl_${n.toString().padLeft(3, '0')}';
    final srcPath = '$srcDir/$id.png';
    final srcFile = File(srcPath);
    if (!srcFile.existsSync()) {
      missing.add(id);
      continue;
    }

    final decoded = img.decodeImage(srcFile.readAsBytesSync());
    if (decoded == null) {
      stderr.writeln('WARN: 無法解碼 $srcPath');
      missing.add(id);
      continue;
    }

    final resized = decoded.width >= decoded.height
        ? (decoded.width > maxDim
            ? img.copyResize(decoded, width: maxDim)
            : decoded)
        : (decoded.height > maxDim
            ? img.copyResize(decoded, height: maxDim)
            : decoded);

    final jpg = img.encodeJpg(resized, quality: quality);
    final outPath = '$outDir/$id.jpg';
    File(outPath).writeAsBytesSync(jpg);

    sizes[id] = jpg.length;
    totalBytes += jpg.length;
    if (jpg.length > biggest) {
      biggest = jpg.length;
      biggestName = id;
    }
  }

  final done = count - missing.length;
  String kb(int b) => '${(b / 1024).toStringAsFixed(1)}KB';
  String mb(int b) => '${(b / 1024 / 1024).toStringAsFixed(2)}MB';

  stdout.writeln('converted $done/$count  (max=$maxDim q=$quality)');
  stdout.writeln('total: ${mb(totalBytes)}  '
      'avg: ${done > 0 ? kb(totalBytes ~/ done) : "-"}  '
      'biggest: $biggestName ${kb(biggest)}');
  if (missing.isNotEmpty) {
    stderr.writeln('MISSING ${missing.length}: ${missing.join(", ")}');
    exitCode = 1;
  }
}
