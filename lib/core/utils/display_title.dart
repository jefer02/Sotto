/// A script title as people should read it. Imported files keep their file
/// name as the title ("Generalidades_Solo_Monitoreo_Rastreo"); this shows
/// "Generalidades Solo Monitoreo Rastreo" without touching what's stored.
///
/// Underscores always become spaces. Hyphens only do when the title has no
/// spaces at all — it then looks like a file name ("q3-board-review"), while
/// "Q3-2026 review" keeps its hyphen.
String displayTitle(String title) {
  final fileName = !title.trim().contains(' ');
  var t = title.replaceAll('_', ' ');
  if (fileName) t = t.replaceAll('-', ' ');
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  // A title made only of separators reads as what was typed.
  return t.isEmpty ? title : t;
}
