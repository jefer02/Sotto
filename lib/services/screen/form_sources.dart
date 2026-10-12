import '../../domain/forms/form_model.dart';
import 'form_access.dart';

/// Where a page's form was read from, best first.
enum FormSource {
  /// The browser extension: the page's own DOM.
  extension,

  /// Windows UI Automation / macOS AX.
  accessibility,

  /// Nothing readable: the screenshot is the source.
  vision,
}

class SourcedSnapshot {
  const SourcedSnapshot(this.snapshot, this.source);
  final FormSnapshot snapshot;
  final FormSource source;
}

/// The reading order: extension → UI Automation / AX → vision only.
abstract final class FormSources {
  /// [extension] is null when it doesn't apply (not a browser, or its
  /// extension isn't connected); a failure or an empty page moves on.
  /// [accessibility]'s "own window" and "permission denied" still stop the
  /// run — other failures mean an empty tree, and the screenshot takes over.
  static Future<SourcedSnapshot> read({
    Future<FormSnapshot?> Function()? extension,
    required Future<FormSnapshot> Function() accessibility,
  }) async {
    if (extension != null) {
      try {
        final page = await extension();
        if (page != null && page.fields.isNotEmpty) return SourcedSnapshot(page, FormSource.extension);
      } catch (_) {
        // On to accessibility.
      }
    }
    FormSnapshot tree;
    try {
      tree = await accessibility();
    } on FormAccessException catch (e) {
      if (e.code == 'own_window' || e.code == 'permission_denied') rethrow;
      tree = const FormSnapshot(fields: []);
    }
    return SourcedSnapshot(tree, tree.fields.isEmpty ? FormSource.vision : FormSource.accessibility);
  }
}
