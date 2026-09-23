import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Strings for code without a [BuildContext] — controllers, services,
/// formatters. The app root keeps it in step with the active locale.
abstract final class L10n {
  static AppLocalizations current = lookupAppLocalizations(const Locale('en'));

  static const supported = [Locale('en'), Locale('es')];

  /// Resolves a device locale ("es_MX") to a supported one.
  static Locale resolve(Locale? device) =>
      supported.firstWhere((l) => l.languageCode == device?.languageCode, orElse: () => supported.first);
}
