import 'dart:io';

/// Writes [contents] to [file] so a crash leaves the old file or the new
/// one, never half of either: a sibling temp file is flushed to disk, then
/// renamed over the target (MoveFileEx with replace on Windows, rename(2)
/// elsewhere — both atomic on one volume).
Future<void> writeFileAtomic(File file, String contents) async {
  await file.parent.create(recursive: true);
  final temp = File('${file.path}.tmp');
  await temp.writeAsString(contents, flush: true);
  await temp.rename(file.path);
}
