import 'dart:io';

/// Opens [url] in the default browser. No plugin needed on desktop.
Future<void> openExternal(String url) async {
  if (Platform.isWindows) {
    await Process.start('rundll32', ['url.dll,FileProtocolHandler', url]);
  } else if (Platform.isMacOS) {
    await Process.start('open', [url]);
  } else {
    await Process.start('xdg-open', [url]);
  }
}
